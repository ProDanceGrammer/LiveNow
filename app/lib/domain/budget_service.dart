import 'package:drift/drift.dart';

import '../core/ids.dart';
import '../core/time_codec.dart';
import '../data/database.dart';
import 'budget_rules.dart';

/// A parent/percent link that would close a loop.
class BudgetCycleException implements Exception {
  const BudgetCycleException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Only categories WITHOUT sub-categories can hold transactions. Thrown when a
/// category that has transactions is about to get its first child (the UI asks
/// to move them, then retries) or when a transaction targets a group.
class BudgetGroupException implements Exception {
  const BudgetGroupException(this.categoryId, this.message);
  final String categoryId;
  final String message;
  @override
  String toString() => message;
}

class BudgetSettings {
  const BudgetSettings({
    this.baseCurrency = 'EUR',
    this.periodMonths = kDefaultPeriodMonths,
    this.tolerance = kDefaultTolerance,
    this.showUrgency = false,
  });

  final String baseCurrency;
  final int periodMonths;
  final double tolerance;

  /// Urgency colours and numbers on categories and transactions (off by
  /// default).
  final bool showUrgency;
}

/// Everything [BudgetService.deleteCategory] changed, for undo.
class CategoryDeleteUndo {
  const CategoryDeleteUndo({
    required this.category,
    required this.childIds,
    required this.percentDependentIds,
    required this.transactionIds,
  });

  final BudgetCategory category;
  final List<String> childIds;
  final List<String> percentDependentIds;
  final List<String> transactionIds;
}

/// Everything [BudgetService.deleteAccount] changed, for undo.
class AccountDeleteUndo {
  const AccountDeleteUndo({
    required this.account,
    required this.countCategoryIds,
    required this.useCategoryIds,
    required this.countTransactionIds,
    required this.useTransactionIds,
  });

  final BudgetAccount account;
  final List<String> countCategoryIds;
  final List<String> useCategoryIds;
  final List<String> countTransactionIds;
  final List<String> useTransactionIds;
}

/// Editable fields of a category (id null = new).
class CategoryInput {
  const CategoryInput({
    this.id,
    required this.name,
    this.isIncome = false,
    this.oneTime = false,
    this.unit = BudgetUnit.month,
    this.endDate,
    this.price,
    this.percent,
    this.frequencyMonths,
    this.unitsPerMonth,
    this.parentId,
    this.countPercentOfId,
    this.accountCountId,
    this.accountUseId,
  });

  final String? id;
  final String name;
  final bool isIncome;
  final bool oneTime;
  final BudgetUnit unit;
  final DateTime? endDate;
  final double? price;
  final double? percent;
  final double? frequencyMonths;
  final double? unitsPerMonth;
  final String? parentId;
  final String? countPercentOfId;
  final String? accountCountId;
  final String? accountUseId;
}

/// Budget CRUD and the rules that need the database. The numbers themselves
/// (plan/fact/balance) are computed by the pure `budget_rules.dart`.
class BudgetService {
  BudgetService(this.db);

  final AppDatabase db;

  // ---- settings -------------------------------------------------------------

  Future<BudgetSettings> settings() async {
    final rows = await db.select(db.budgetSettingsTable).get();
    final map = {for (final r in rows) r.key: r.value};
    return settingsFromMap(map);
  }

  static BudgetSettings settingsFromMap(Map<String, String> map) {
    final months = int.tryParse(map['period_months'] ?? '');
    final tol = double.tryParse(map['tolerance'] ?? '');
    final base = (map['base_currency'] ?? '').trim();
    return BudgetSettings(
      baseCurrency: base.isEmpty ? 'EUR' : base,
      periodMonths: months != null && months > 0
          ? months
          : kDefaultPeriodMonths,
      tolerance: tol != null && tol >= 0 ? tol : kDefaultTolerance,
      showUrgency: map['show_urgency'] == '1',
    );
  }

  Future<void> saveSettings(BudgetSettings s) async {
    Future<void> put(String key, String value) => db
        .into(db.budgetSettingsTable)
        .insertOnConflictUpdate(
          BudgetSettingsTableCompanion.insert(key: key, value: value),
        );
    await db.transaction(() async {
      await put('base_currency', s.baseCurrency.trim().toUpperCase());
      await put('period_months', '${s.periodMonths < 1 ? 1 : s.periodMonths}');
      await put('tolerance', '${s.tolerance < 0 ? 0 : s.tolerance}');
      await put('show_urgency', s.showUrgency ? '1' : '0');
    });
  }

  // ---- accounts -------------------------------------------------------------

  Future<String> saveAccount({
    String? id,
    required String name,
    String? type,
    required String currency,
    required double rateToBase,
    double openingBalance = 0,

    /// The picture (base64 PNG): absent = leave as it is, `Value(null)` =
    /// remove it.
    Value<String?> icon = const Value.absent(),
  }) async {
    if (!(rateToBase > 0)) {
      throw ArgumentError.value(rateToBase, 'rateToBase', 'must be > 0');
    }
    final now = dateTimeToDb(DateTime.now())!;
    final cleanType = type == null || type.trim().isEmpty ? null : type.trim();
    final code = currency.trim().toUpperCase();
    if (id == null) {
      final newAccountId = newId();
      await db
          .into(db.budgetAccountsTable)
          .insert(
            BudgetAccountsTableCompanion.insert(
              id: newAccountId,
              name: name.trim(),
              type: Value(cleanType),
              currency: code,
              rateToBase: Value(rateToBase),
              openingBalance: Value(openingBalance),
              icon: icon,
              createdAt: now,
              updatedAt: now,
            ),
          );
      return newAccountId;
    }
    await (db.update(
      db.budgetAccountsTable,
    )..where((t) => t.id.equals(id))).write(
      BudgetAccountsTableCompanion(
        name: Value(name.trim()),
        type: Value(cleanType),
        currency: Value(code),
        rateToBase: Value(rateToBase),
        openingBalance: Value(openingBalance),
        icon: icon,
        updatedAt: Value(now),
      ),
    );
    return id;
  }

  Future<AccountDeleteUndo?> deleteAccount(String id) {
    return db.transaction(() async {
      final account = await (db.select(
        db.budgetAccountsTable,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (account == null) return null;
      Future<List<String>> ids(
        TableInfo<Table, dynamic> table,
        GeneratedColumn<String> column,
      ) async {
        final rows = await db
            .customSelect(
              'SELECT id FROM ${table.actualTableName} WHERE ${column.name} = ?',
              variables: [Variable.withString(id)],
            )
            .get();
        return rows.map((r) => r.read<String>('id')).toList();
      }

      final undo = AccountDeleteUndo(
        account: account,
        countCategoryIds: await ids(
          db.budgetCategoriesTable,
          db.budgetCategoriesTable.accountCountId,
        ),
        useCategoryIds: await ids(
          db.budgetCategoriesTable,
          db.budgetCategoriesTable.accountUseId,
        ),
        countTransactionIds: await ids(
          db.budgetTransactionsTable,
          db.budgetTransactionsTable.accountCountId,
        ),
        useTransactionIds: await ids(
          db.budgetTransactionsTable,
          db.budgetTransactionsTable.accountUseId,
        ),
      );
      // Explicit, because ON DELETE SET NULL needs foreign keys enabled.
      await (db.update(
        db.budgetCategoriesTable,
      )..where((t) => t.accountCountId.equals(id))).write(
        const BudgetCategoriesTableCompanion(accountCountId: Value(null)),
      );
      await (db.update(
        db.budgetCategoriesTable,
      )..where((t) => t.accountUseId.equals(id))).write(
        const BudgetCategoriesTableCompanion(accountUseId: Value(null)),
      );
      await (db.update(
        db.budgetTransactionsTable,
      )..where((t) => t.accountCountId.equals(id))).write(
        const BudgetTransactionsTableCompanion(accountCountId: Value(null)),
      );
      await (db.update(
        db.budgetTransactionsTable,
      )..where((t) => t.accountUseId.equals(id))).write(
        const BudgetTransactionsTableCompanion(accountUseId: Value(null)),
      );
      await (db.delete(
        db.budgetAccountsTable,
      )..where((t) => t.id.equals(id))).go();
      return undo;
    });
  }

  Future<void> undoDeleteAccount(AccountDeleteUndo undo) {
    return db.transaction(() async {
      await db.into(db.budgetAccountsTable).insert(undo.account);
      final id = undo.account.id;
      await (db.update(db.budgetCategoriesTable)
            ..where((t) => t.id.isIn(undo.countCategoryIds)))
          .write(BudgetCategoriesTableCompanion(accountCountId: Value(id)));
      await (db.update(db.budgetCategoriesTable)
            ..where((t) => t.id.isIn(undo.useCategoryIds)))
          .write(BudgetCategoriesTableCompanion(accountUseId: Value(id)));
      await (db.update(db.budgetTransactionsTable)
            ..where((t) => t.id.isIn(undo.countTransactionIds)))
          .write(BudgetTransactionsTableCompanion(accountCountId: Value(id)));
      await (db.update(db.budgetTransactionsTable)
            ..where((t) => t.id.isIn(undo.useTransactionIds)))
          .write(BudgetTransactionsTableCompanion(accountUseId: Value(id)));
    });
  }

  // ---- categories -----------------------------------------------------------

  Future<int> _transactionCount(String categoryId) async {
    final row = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM budget_transactions WHERE category_id = ?',
          variables: [Variable.withString(categoryId)],
        )
        .getSingle();
    return row.read<int>('n');
  }

  Future<bool> _hasChildren(String categoryId) async {
    final row = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM budget_categories WHERE parent_id = ?',
          variables: [Variable.withString(categoryId)],
        )
        .getSingle();
    return row.read<int>('n') > 0;
  }

  /// Creates or updates a category. Throws [BudgetCycleException] for a parent
  /// or percent loop and [BudgetGroupException] when the chosen parent still
  /// holds transactions of its own (move them first: [moveTransactions]).
  Future<String> saveCategory(CategoryInput input) {
    return db.transaction(() async {
      final all = await db.select(db.budgetCategoriesTable).get();
      final id = input.id ?? newId();
      final parentId = input.parentId == id ? null : input.parentId;

      final parentOf = {for (final c in all) c.id: c.parentId};
      if (parentId != null && wouldCreateParentCycle(parentOf, id, parentId)) {
        throw const BudgetCycleException(
          'A category cannot be placed under itself or its own sub-category.',
        );
      }
      final percentOf = {for (final c in all) c.id: c.countPercentOfId};
      final source = input.unit == BudgetUnit.percentPerMonth
          ? input.countPercentOfId
          : null;
      if (source != null && wouldCreatePercentCycle(percentOf, id, source)) {
        throw const BudgetCycleException(
          'These categories would take a percent of each other.',
        );
      }
      if (parentId != null) {
        final parent = all.where((c) => c.id == parentId).firstOrNull;
        final alreadyChild = parent != null && input.id != null
            ? all.any((c) => c.id == input.id && c.parentId == parentId)
            : false;
        if (!alreadyChild && await _transactionCount(parentId) > 0) {
          throw BudgetGroupException(
            parentId,
            'That category has transactions; move them into a sub-category first.',
          );
        }
      }

      final now = dateTimeToDb(DateTime.now())!;
      final end = dateTimeToDb(input.endDate);
      if (input.id == null) {
        await db
            .into(db.budgetCategoriesTable)
            .insert(
              BudgetCategoriesTableCompanion.insert(
                id: id,
                name: input.name.trim(),
                isIncome: Value(input.isIncome),
                oneTime: Value(input.oneTime),
                unit: Value(input.unit.db),
                endDate: Value(end),
                price: Value(input.price),
                percent: Value(input.percent),
                frequencyMonths: Value(input.frequencyMonths),
                unitsPerMonth: Value(input.unitsPerMonth),
                parentId: Value(parentId),
                countPercentOfId: Value(source),
                accountCountId: Value(input.accountCountId),
                accountUseId: Value(input.accountUseId),
                createdAt: now,
                updatedAt: now,
              ),
            );
      } else {
        await (db.update(
          db.budgetCategoriesTable,
        )..where((t) => t.id.equals(id))).write(
          BudgetCategoriesTableCompanion(
            name: Value(input.name.trim()),
            isIncome: Value(input.isIncome),
            oneTime: Value(input.oneTime),
            unit: Value(input.unit.db),
            endDate: Value(end),
            price: Value(input.price),
            percent: Value(input.percent),
            frequencyMonths: Value(input.frequencyMonths),
            unitsPerMonth: Value(input.unitsPerMonth),
            parentId: Value(parentId),
            countPercentOfId: Value(source),
            accountCountId: Value(input.accountCountId),
            accountUseId: Value(input.accountUseId),
            updatedAt: Value(now),
          ),
        );
      }
      return id;
    });
  }

  /// Puts category [id] under [parentId] (null = top level) leaving everything
  /// else as it is. Same checks and exceptions as [saveCategory].
  Future<void> moveCategory(String id, String? parentId) async {
    final c = await (db.select(
      db.budgetCategoriesTable,
    )..where((t) => t.id.equals(id))).getSingle();
    await saveCategory(
      CategoryInput(
        id: c.id,
        name: c.name,
        isIncome: c.isIncome,
        oneTime: c.oneTime,
        unit: BudgetUnit.fromDb(c.unit),
        endDate: dateTimeFromDb(c.endDate),
        price: c.price,
        percent: c.percent,
        frequencyMonths: c.frequencyMonths,
        unitsPerMonth: c.unitsPerMonth,
        parentId: parentId,
        countPercentOfId: c.countPercentOfId,
        accountCountId: c.accountCountId,
        accountUseId: c.accountUseId,
      ),
    );
  }

  /// Moves every transaction of [fromCategoryId] into [toCategoryId] (used
  /// when a category with transactions becomes a group). Snapshots stay.
  Future<int> moveTransactions(String fromCategoryId, String toCategoryId) {
    return (db.update(
      db.budgetTransactionsTable,
    )..where((t) => t.categoryId.equals(fromCategoryId))).write(
      BudgetTransactionsTableCompanion(categoryId: Value(toCategoryId)),
    );
  }

  /// Deletes a category: sub-categories become top-level, percent categories
  /// that took a percent of it lose their source, and transactions keep their
  /// amounts with no category. Undo with [undoDeleteCategory].
  Future<CategoryDeleteUndo?> deleteCategory(String id) {
    return db.transaction(() async {
      final category = await (db.select(
        db.budgetCategoriesTable,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (category == null) return null;
      Future<List<String>> ids(String table, String column) async {
        final rows = await db
            .customSelect(
              'SELECT id FROM $table WHERE $column = ?',
              variables: [Variable.withString(id)],
            )
            .get();
        return rows.map((r) => r.read<String>('id')).toList();
      }

      final undo = CategoryDeleteUndo(
        category: category,
        childIds: await ids('budget_categories', 'parent_id'),
        percentDependentIds: await ids(
          'budget_categories',
          'count_percent_of_id',
        ),
        transactionIds: await ids('budget_transactions', 'category_id'),
      );
      await (db.update(db.budgetCategoriesTable)
            ..where((t) => t.parentId.equals(id)))
          .write(const BudgetCategoriesTableCompanion(parentId: Value(null)));
      await (db.update(
        db.budgetCategoriesTable,
      )..where((t) => t.countPercentOfId.equals(id))).write(
        const BudgetCategoriesTableCompanion(countPercentOfId: Value(null)),
      );
      await (db.update(
        db.budgetTransactionsTable,
      )..where((t) => t.categoryId.equals(id))).write(
        const BudgetTransactionsTableCompanion(categoryId: Value(null)),
      );
      await (db.delete(
        db.budgetCategoriesTable,
      )..where((t) => t.id.equals(id))).go();
      return undo;
    });
  }

  Future<void> undoDeleteCategory(CategoryDeleteUndo undo) {
    return db.transaction(() async {
      await db.into(db.budgetCategoriesTable).insert(undo.category);
      final id = undo.category.id;
      await (db.update(db.budgetCategoriesTable)
            ..where((t) => t.id.isIn(undo.childIds)))
          .write(BudgetCategoriesTableCompanion(parentId: Value(id)));
      await (db.update(db.budgetCategoriesTable)
            ..where((t) => t.id.isIn(undo.percentDependentIds)))
          .write(BudgetCategoriesTableCompanion(countPercentOfId: Value(id)));
      await (db.update(db.budgetTransactionsTable)
            ..where((t) => t.id.isIn(undo.transactionIds)))
          .write(BudgetTransactionsTableCompanion(categoryId: Value(id)));
    });
  }

  // ---- transactions ---------------------------------------------------------

  /// Creates a transaction, snapshotting the category's income flag, accounts,
  /// price and the accounts' current rates. A rate typed here ([rateCount] /
  /// [rateInteract]) also becomes the account's current rate.
  Future<String> createTransaction({
    required String categoryId,
    String name = '',
    String? actionId,
    DateTime? date,
    double? quantity,
    double? unitPrice,
    double? rateCount,
    double? rateInteract,
  }) {
    return db.transaction(() async {
      final category = await _leafCategory(categoryId);
      final id = newId();
      final now = DateTime.now();
      final snap = await _snapshot(
        category,
        unitPrice: unitPrice,
        typedCount: rateCount,
        typedInteract: rateInteract,
      );
      await db
          .into(db.budgetTransactionsTable)
          .insert(
            BudgetTransactionsTableCompanion.insert(
              id: id,
              name: Value(name),
              categoryId: Value(categoryId),
              actionId: Value(actionId),
              occurredAt: dateTimeToDb(date ?? now)!,
              quantity: Value(quantity ?? 1),
              unitPrice: Value(snap.unitPrice),
              isIncome: Value(category.isIncome),
              isAmount: Value(snap.isAmount),
              accountCountId: Value(category.accountCountId),
              accountUseId: Value(category.accountUseId),
              rateCount: Value(snap.rateCount),
              rateInteract: Value(snap.rateInteract),
              createdAt: dateTimeToDb(now)!,
              updatedAt: dateTimeToDb(now)!,
            ),
          );
      return id;
    });
  }

  /// Edits a transaction. Changing the category re-snapshots from the new one.
  Future<void> updateTransaction(
    String id, {
    String? name,
    String? categoryId,
    Value<String?> actionId = const Value.absent(),
    DateTime? date,
    double? quantity,
    double? unitPrice,
    double? rateCount,
    double? rateInteract,
  }) {
    return db.transaction(() async {
      final row = await (db.select(
        db.budgetTransactionsTable,
      )..where((t) => t.id.equals(id))).getSingle();
      var companion = BudgetTransactionsTableCompanion(
        name: name == null ? const Value.absent() : Value(name),
        actionId: actionId,
        occurredAt: date == null
            ? const Value.absent()
            : Value(dateTimeToDb(date)!),
        quantity: quantity == null ? const Value.absent() : Value(quantity),
        updatedAt: Value(dateTimeToDb(DateTime.now())!),
      );
      final newCategoryId = categoryId ?? row.categoryId;
      final categoryChanged =
          categoryId != null && categoryId != row.categoryId;
      if (newCategoryId != null &&
          (categoryChanged ||
              unitPrice != null ||
              rateCount != null ||
              rateInteract != null)) {
        final category = await _leafCategory(newCategoryId);
        final snap = await _snapshot(
          category,
          unitPrice: unitPrice ?? (categoryChanged ? null : row.unitPrice),
          // Only typed rates move the account; carried-over ones must not.
          typedCount: rateCount,
          typedInteract: rateInteract,
          keepCount: categoryChanged ? null : row.rateCount,
          keepInteract: categoryChanged ? null : row.rateInteract,
        );
        companion = companion.copyWith(
          categoryId: Value(newCategoryId),
          unitPrice: Value(snap.unitPrice),
          isIncome: categoryChanged ? Value(category.isIncome) : null,
          isAmount: Value(snap.isAmount),
          accountCountId: categoryChanged
              ? Value(category.accountCountId)
              : null,
          accountUseId: categoryChanged ? Value(category.accountUseId) : null,
          rateCount: Value(snap.rateCount),
          rateInteract: Value(snap.rateInteract),
        );
      }
      await (db.update(
        db.budgetTransactionsTable,
      )..where((t) => t.id.equals(id))).write(companion);
    });
  }

  Future<BudgetTransaction?> deleteTransaction(String id) async {
    final row = await (db.select(
      db.budgetTransactionsTable,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    await (db.delete(
      db.budgetTransactionsTable,
    )..where((t) => t.id.equals(id))).go();
    return row;
  }

  Future<void> undoDeleteTransaction(BudgetTransaction row) =>
      db.into(db.budgetTransactionsTable).insert(row);

  // ---- transaction templates ----------------------------------------------------

  Stream<List<BudgetTxTemplate>> watchTxTemplates() =>
      (db.select(db.budgetTxTemplatesTable)
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .watch();

  Future<List<BudgetTxTemplate>> txTemplates() =>
      db.select(db.budgetTxTemplatesTable).get();

  /// Creates (no [id]) or edits a transaction template; returns its id.
  Future<String> saveTxTemplate({
    String? id,
    required String name,
    required String? categoryId,
    double quantity = 1,
    double? unitPrice,
  }) async {
    final now = dateTimeToDb(DateTime.now())!;
    final qty = quantity > 0 ? quantity : 1.0;
    if (id == null) {
      final newTemplateId = newId();
      await db
          .into(db.budgetTxTemplatesTable)
          .insert(
            BudgetTxTemplatesTableCompanion.insert(
              id: newTemplateId,
              name: Value(name.trim()),
              categoryId: Value(categoryId),
              quantity: Value(qty),
              unitPrice: Value(unitPrice),
              createdAt: now,
              updatedAt: now,
            ),
          );
      return newTemplateId;
    }
    await (db.update(db.budgetTxTemplatesTable)..where((t) => t.id.equals(id)))
        .write(
          BudgetTxTemplatesTableCompanion(
            name: Value(name.trim()),
            categoryId: Value(categoryId),
            quantity: Value(qty),
            unitPrice: Value(unitPrice),
            updatedAt: Value(now),
          ),
        );
    return id;
  }

  /// Deletes a template and returns the row for an Undo (null = it was gone).
  Future<BudgetTxTemplate?> deleteTxTemplate(String id) async {
    final row = await (db.select(
      db.budgetTxTemplatesTable,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    await (db.delete(
      db.budgetTxTemplatesTable,
    )..where((t) => t.id.equals(id))).go();
    return row;
  }

  Future<void> undoDeleteTxTemplate(BudgetTxTemplate row) =>
      db.into(db.budgetTxTemplatesTable).insertOnConflictUpdate(row);

  /// A real transaction made from template [templateId]: its category, quantity
  /// and price (null = the category's), named like the template (else like
  /// [fallbackName], e.g. the action), linked to [actionId] and dated [date].
  /// Throws [BudgetGroupException] for a group category and [StateError] when the
  /// template or its category is gone.
  Future<String> createTransactionFromTemplate(
    String templateId, {
    String? actionId,
    DateTime? date,
    String fallbackName = '',
  }) async {
    final t = await (db.select(
      db.budgetTxTemplatesTable,
    )..where((r) => r.id.equals(templateId))).getSingleOrNull();
    if (t == null) throw StateError('That transaction template no longer exists.');
    final categoryId = t.categoryId;
    final exists =
        categoryId != null &&
        await (db.select(
              db.budgetCategoriesTable,
            )..where((c) => c.id.equals(categoryId))).getSingleOrNull() !=
            null;
    if (!exists) {
      throw StateError('The category of "${t.name}" no longer exists.');
    }
    return createTransaction(
      categoryId: categoryId,
      name: t.name.isEmpty ? fallbackName : t.name,
      actionId: actionId,
      date: date,
      quantity: t.quantity,
      unitPrice: t.unitPrice,
    );
  }

  Future<BudgetCategory> _leafCategory(String categoryId) async {
    final category = await (db.select(
      db.budgetCategoriesTable,
    )..where((t) => t.id.equals(categoryId))).getSingle();
    if (await _hasChildren(categoryId)) {
      throw BudgetGroupException(
        categoryId,
        'Pick a category without sub-categories for a transaction.',
      );
    }
    return category;
  }

  /// The price/rates a transaction of [category] stores. Rates typed now
  /// ([typedCount] / [typedInteract]) also become the accounts' current rate;
  /// otherwise a carried-over rate ([keepCount] / [keepInteract]) or the
  /// account's current one is used.
  Future<
    ({double unitPrice, bool isAmount, double? rateCount, double? rateInteract})
  >
  _snapshot(
    BudgetCategory category, {
    double? unitPrice,
    double? typedCount,
    double? typedInteract,
    double? keepCount,
    double? keepInteract,
  }) async {
    Future<double?> accountRate(String? accountId) async {
      if (accountId == null) return null;
      final a = await (db.select(
        db.budgetAccountsTable,
      )..where((t) => t.id.equals(accountId))).getSingleOrNull();
      return a?.rateToBase;
    }

    Future<void> setAccountRate(String? accountId, double? typed) async {
      if (accountId == null || typed == null || !(typed > 0)) return;
      await (db.update(
        db.budgetAccountsTable,
      )..where((t) => t.id.equals(accountId))).write(
        BudgetAccountsTableCompanion(
          rateToBase: Value(typed),
          updatedAt: Value(dateTimeToDb(DateTime.now())!),
        ),
      );
    }

    bool ok(double? v) => v != null && v > 0;
    await setAccountRate(category.accountCountId, typedCount);
    await setAccountRate(category.accountUseId, typedInteract);

    final isAmount = category.unit == BudgetUnit.percentPerMonth.db;
    return (
      unitPrice: isAmount ? 0.0 : (unitPrice ?? category.price ?? 0),
      isAmount: isAmount,
      rateCount: ok(typedCount)
          ? typedCount
          : ok(keepCount)
          ? keepCount
          : await accountRate(category.accountCountId),
      rateInteract: ok(typedInteract)
          ? typedInteract
          : ok(keepInteract)
          ? keepInteract
          : await accountRate(category.accountUseId),
    );
  }

  /// Quantity of the newest transaction of [categoryId] (prefill for quick
  /// add), or null when it has none.
  Future<double?> lastQuantity(String categoryId) async {
    final row = await db
        .customSelect(
          'SELECT quantity FROM budget_transactions WHERE category_id = ? '
          'ORDER BY created_at DESC LIMIT 1',
          variables: [Variable.withString(categoryId)],
        )
        .getSingleOrNull();
    return row?.read<double>('quantity');
  }

  /// Guess for quick add, from the schedule alone: the timed action running
  /// now (`start <= now < end`) that started most recently, else the one that
  /// ended most recently, else null.
  Future<String?> suggestedActionId({DateTime? nowUtc}) async {
    final now = dateTimeToDb(nowUtc ?? DateTime.now().toUtc())!;
    final running = await db
        .customSelect(
          'SELECT a.id AS id FROM actions a '
          'WHERE a.is_all_day = 0 AND a.start_at IS NOT NULL '
          'AND a.end_at IS NOT NULL AND a.start_at <= ? AND a.end_at > ? '
          'ORDER BY a.start_at DESC LIMIT 1',
          variables: [Variable.withString(now), Variable.withString(now)],
        )
        .getSingleOrNull();
    if (running != null) return running.read<String>('id');
    final finished = await db
        .customSelect(
          'SELECT a.id AS id FROM actions a '
          'WHERE a.is_all_day = 0 AND a.end_at IS NOT NULL AND a.end_at <= ? '
          'ORDER BY a.end_at DESC LIMIT 1',
          variables: [Variable.withString(now)],
        )
        .getSingleOrNull();
    return finished?.read<String>('id');
  }
}
