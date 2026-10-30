import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/ids.dart';
import '../../core/time_codec.dart';
import '../../data/database.dart';
import '../action_service.dart';
import '../budget_rules.dart';
import '../budget_service.dart';

/// `ai_batch_items.entity_type`
abstract final class AiEntity {
  static const transaction = 'transaction';
  static const category = 'category';
  static const action = 'action';
}

/// `ai_batch_items.op`
abstract final class AiOp {
  /// The batch created the row (undo deletes it, when still safe).
  static const insert = 'insert';

  /// The batch changed fields; `before_json` holds the old values
  /// (transaction: name, category_id, quantity, unit_price; category: name,
  /// price).
  static const update = 'update';

  /// The batch moved a category; `before_json` = `{"parent_id": ...}`.
  static const reparent = 'reparent';
}

/// What [AiBatchService.undoBatch] did.
class BatchUndoResult {
  const BatchUndoResult({
    this.alreadyUndone = false,
    this.transactions = 0,
    this.categories = 0,
    this.actions = 0,
    this.restored = 0,
    this.skipped = const [],
  });

  /// The batch was undone before (or does not exist): nothing was changed.
  final bool alreadyUndone;
  final int transactions;
  final int categories;
  final int actions;

  /// Updates / reparents put back.
  final int restored;

  /// Human-readable reasons for rows that were left alone (they changed since,
  /// or hold data the batch did not create).
  final List<String> skipped;

  int get total => transactions + categories + actions + restored;
}

/// The journal of what one assistant job wrote to the budget, and the undo
/// that goes with it. Ids are derived from the job / batch id, so a re-run of
/// a job records the same rows (insert-if-absent). Undo goes through the
/// public services only and never deletes a row the batch did not create.
class AiBatchService {
  AiBatchService(this.db)
    : _budget = BudgetService(db),
      _actions = ActionService(db);

  final AppDatabase db;
  final BudgetService _budget;
  final ActionService _actions;

  /// Creates (or finds, on a re-run) the batch of [jobId]; returns its id.
  /// [index] numbers several batches of one job.
  Future<String> startBatch({
    required String jobId,
    required String threadId,
    String? messageId,
    String summary = '',
    int index = 0,
  }) async {
    final id = deriveId(jobId, 'batch', index);
    final now = dateTimeToDb(DateTime.now())!;
    await db
        .into(db.aiBatchesTable)
        .insert(
          AiBatchesTableCompanion.insert(
            id: id,
            jobId: jobId,
            threadId: threadId,
            messageId: Value(messageId),
            summary: Value(summary),
            createdAt: now,
            updatedAt: now,
          ),
          mode: InsertMode.insertOrIgnore,
        );
    return id;
  }

  /// Journals one change. [position] is the caller's running number inside the
  /// batch (deterministic across a re-run), which also fixes the undo order.
  Future<void> record(
    String batchId, {
    required int position,
    required String entityType,
    required String entityId,
    String op = AiOp.insert,
    Map<String, Object?>? before,
    Map<String, Object?>? after,
  }) async {
    final now = dateTimeToDb(DateTime.now())!;
    await db
        .into(db.aiBatchItemsTable)
        .insert(
          AiBatchItemsTableCompanion.insert(
            id: deriveId(batchId, 'item', position),
            batchId: batchId,
            entityType: entityType,
            entityId: entityId,
            op: Value(op),
            beforeJson: Value(before == null ? null : jsonEncode(before)),
            afterJson: Value(after == null ? null : jsonEncode(after)),
            position: Value(position),
            createdAt: now,
            updatedAt: now,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<AiBatch?> batch(String batchId) => (db.select(
    db.aiBatchesTable,
  )..where((t) => t.id.equals(batchId))).getSingleOrNull();

  Future<List<AiBatchItem>> items(String batchId) =>
      (db.select(db.aiBatchItemsTable)
            ..where((t) => t.batchId.equals(batchId))
            ..orderBy([(t) => OrderingTerm.asc(t.position)]))
          .get();

  /// Reverts the batch, newest change first, in ONE transaction, and stamps
  /// `undone_at`. A second call changes nothing. Rows that were touched since
  /// (a category that now holds other transactions, an action that was edited
  /// or has other transactions) are left and listed in [BatchUndoResult.skipped].
  Future<BatchUndoResult> undoBatch(String batchId) {
    return db.transaction(() async {
      final b = await batch(batchId);
      if (b == null || b.undoneAt != null) {
        return const BatchUndoResult(alreadyUndone: true);
      }
      final list = (await items(batchId)).reversed;
      var tx = 0, cat = 0, act = 0, restored = 0;
      final skipped = <String>[];
      for (final it in list) {
        final before = _decode(it.beforeJson);
        switch ((it.entityType, it.op)) {
          case (AiEntity.transaction, AiOp.insert):
            if (await _budget.deleteTransaction(it.entityId) != null) tx++;
          case (AiEntity.transaction, AiOp.update):
            if (await _restoreTransaction(it.entityId, before)) {
              restored++;
            } else {
              skipped.add('transaction ${it.entityId} could not be restored');
            }
          case (AiEntity.category, AiOp.insert):
            switch (await _deleteCreatedCategory(it.entityId)) {
              case _Deleted.yes:
                cat++;
              case _Deleted.kept:
                skipped.add('category ${it.entityId} still has content');
              case _Deleted.gone:
                break;
            }
          case (AiEntity.category, AiOp.reparent):
            if (await _moveBack(it.entityId, before)) {
              restored++;
            } else {
              skipped.add('category ${it.entityId} could not be moved back');
            }
          case (AiEntity.category, AiOp.update):
            if (await _restoreCategory(it.entityId, before)) {
              restored++;
            } else {
              skipped.add('category ${it.entityId} could not be restored');
            }
          case (AiEntity.action, AiOp.insert):
            switch (await _deleteCreatedAction(it.entityId)) {
              case _Deleted.yes:
                act++;
              case _Deleted.kept:
                skipped.add('action ${it.entityId} was changed or is in use');
              case _Deleted.gone:
                break;
            }
          default:
            skipped.add('${it.entityType}/${it.op} is not undoable');
        }
      }
      final now = dateTimeToDb(DateTime.now())!;
      await (db.update(
        db.aiBatchesTable,
      )..where((t) => t.id.equals(batchId))).write(
        AiBatchesTableCompanion(undoneAt: Value(now), updatedAt: Value(now)),
      );
      return BatchUndoResult(
        transactions: tx,
        categories: cat,
        actions: act,
        restored: restored,
        skipped: skipped,
      );
    });
  }

  // ---- undo steps -------------------------------------------------------------

  Map<String, dynamic> _decode(String? json) {
    if (json == null) return {};
    try {
      final j = jsonDecode(json);
      if (j is Map) return Map<String, dynamic>.from(j);
    } catch (_) {}
    return {};
  }

  Future<bool> _restoreTransaction(
    String id,
    Map<String, dynamic> before,
  ) async {
    final row = await (db.select(
      db.budgetTransactionsTable,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return false;
    try {
      await _budget.updateTransaction(
        id,
        name: before['name'] as String?,
        categoryId: before['category_id'] as String?,
        quantity: (before['quantity'] as num?)?.toDouble(),
        unitPrice: (before['unit_price'] as num?)?.toDouble(),
        // A screenshot batch only changed the rates: put them back too.
        rateCount: (before['rate_count'] as num?)?.toDouble(),
        rateInteract: (before['rate_interact'] as num?)?.toDouble(),
        updateAccountRate: false,
      );
      return true;
    } on Object {
      return false;
    }
  }

  /// Deletes a category the batch created, only when nothing was added to it
  /// since (no transactions, no sub-categories).
  Future<_Deleted> _deleteCreatedCategory(String id) async {
    final c = await (db.select(
      db.budgetCategoriesTable,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (c == null) return _Deleted.gone;
    final used = await db
        .customSelect(
          'SELECT (SELECT COUNT(*) FROM budget_transactions WHERE category_id = ?1) '
          '+ (SELECT COUNT(*) FROM budget_categories WHERE parent_id = ?1) AS n',
          variables: [Variable.withString(id)],
        )
        .getSingle();
    if (used.read<int>('n') > 0) return _Deleted.kept;
    await _budget.deleteCategory(id);
    return _Deleted.yes;
  }

  Future<bool> _moveBack(String id, Map<String, dynamic> before) async {
    if (!before.containsKey('parent_id')) return false;
    final exists = await (db.select(
      db.budgetCategoriesTable,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (exists == null) return false;
    try {
      await _budget.moveCategory(id, before['parent_id'] as String?);
      return true;
    } on BudgetCycleException {
      return false;
    } on BudgetGroupException {
      return false;
    }
  }

  Future<bool> _restoreCategory(String id, Map<String, dynamic> before) async {
    final c = await (db.select(
      db.budgetCategoriesTable,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (c == null) return false;
    try {
      await _budget.saveCategory(
        CategoryInput(
          id: c.id,
          name: (before['name'] as String?) ?? c.name,
          isIncome: c.isIncome,
          oneTime: c.oneTime,
          unit: BudgetUnit.fromDb(c.unit),
          endDate: dateTimeFromDb(c.endDate),
          price: before.containsKey('price')
              ? (before['price'] as num?)?.toDouble()
              : c.price,
          percent: c.percent,
          frequencyMonths: c.frequencyMonths,
          unitsPerMonth: c.unitsPerMonth,
          parentId: c.parentId,
          countPercentOfId: c.countPercentOfId,
          accountCountId: c.accountCountId,
          accountUseId: c.accountUseId,
        ),
      );
      return true;
    } on Object {
      return false;
    }
  }

  /// Deletes an action the batch created, only while untouched: never edited
  /// since (`updated_at == created_at`) and without budget transactions.
  Future<_Deleted> _deleteCreatedAction(String id) async {
    final a = await (db.select(
      db.actionsTable,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (a == null) return _Deleted.gone;
    final linked = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM budget_transactions WHERE action_id = ?',
          variables: [Variable.withString(id)],
        )
        .getSingle();
    if (a.updatedAt != a.createdAt || linked.read<int>('n') > 0) {
      return _Deleted.kept;
    }
    await _actions.deleteAction(id);
    return _Deleted.yes;
  }
}

enum _Deleted { yes, kept, gone }
