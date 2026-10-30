import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/ai/ai_batch_service.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/budget_service.dart';
import 'package:livenow/domain/postpone_rules.dart';

import 'ai_test_support.dart';

void main() {
  late AppDatabase db;
  late Seed seed;
  late BudgetService budget;
  late AiBatchService batches;

  setUpAll(initPostponeTimeZoneData);

  setUp(() {
    db = memoryDb();
    seed = Seed(db);
    budget = seed.budget;
    batches = AiBatchService(db);
  });

  tearDown(() => db.close());

  Future<int> count(String table) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle())
          .read<int>('n');

  test('startBatch and record are idempotent across a re-run', () async {
    final b1 = await batches.startBatch(jobId: 'job1', threadId: 't');
    final b2 = await batches.startBatch(jobId: 'job1', threadId: 't');
    expect(b2, b1);
    for (var run = 0; run < 2; run++) {
      await batches.record(
        b1,
        position: 0,
        entityType: AiEntity.transaction,
        entityId: 'x',
      );
      await batches.record(
        b1,
        position: 1,
        entityType: AiEntity.category,
        entityId: 'y',
      );
    }
    expect(await count('ai_batches'), 1);
    expect(await batches.items(b1), hasLength(2));
  });

  test(
    'undoBatch reverts a transaction, a created category and a reparent',
    () async {
      final foodGroup = await seed.group('Food');
      final otherGroup = await seed.group('Other');
      final moved = await seed.group('Moved', parentId: foodGroup);
      final oldLeaf = await seed.leaf(
        'Old leaf',
        price: 10,
        parentId: otherGroup,
      );
      final keepTx = await budget.createTransaction(categoryId: oldLeaf);

      final batchId = await batches.startBatch(jobId: 'job2', threadId: 't');
      // 1) a category created by the batch
      final newCat = await seed.leaf('Pears', price: 50, parentId: foodGroup);
      await batches.record(
        batchId,
        position: 0,
        entityType: AiEntity.category,
        entityId: newCat,
      );
      // 2) a reparent
      await budget.moveCategory(moved, otherGroup);
      await batches.record(
        batchId,
        position: 1,
        entityType: AiEntity.category,
        entityId: moved,
        op: AiOp.reparent,
        before: {'parent_id': foodGroup},
        after: {'parent_id': otherGroup},
      );
      // 3) a transaction on the new category
      final tx = await budget.createTransaction(
        categoryId: newCat,
        quantity: 2,
      );
      await batches.record(
        batchId,
        position: 2,
        entityType: AiEntity.transaction,
        entityId: tx,
      );

      final r = await batches.undoBatch(batchId);
      expect(r.alreadyUndone, isFalse);
      expect(r.transactions, 1);
      expect(r.categories, 1);
      expect(r.restored, 1);
      expect(r.skipped, isEmpty);

      final cats = await db.select(db.budgetCategoriesTable).get();
      expect(cats.any((c) => c.id == newCat), isFalse);
      expect(cats.firstWhere((c) => c.id == moved).parentId, foodGroup);
      final txs = await db.select(db.budgetTransactionsTable).get();
      expect(txs.map((t) => t.id), [
        keepTx,
      ]); // never touched what it did not create
      expect((await batches.batch(batchId))!.undoneAt, isNotNull);

      final again = await batches.undoBatch(batchId);
      expect(again.alreadyUndone, isTrue);
      expect(again.total, 0);
    },
  );

  test(
    'a created category that now holds foreign transactions is kept',
    () async {
      final group = await seed.group('Food');
      final batchId = await batches.startBatch(jobId: 'job3', threadId: 't');
      final cat = await seed.leaf('Plums', price: 30, parentId: group);
      await batches.record(
        batchId,
        position: 0,
        entityType: AiEntity.category,
        entityId: cat,
      );
      final foreign = await budget.createTransaction(categoryId: cat);

      final r = await batches.undoBatch(batchId);
      expect(r.categories, 0);
      expect(r.skipped, hasLength(1));
      expect(await count('budget_categories'), 2);
      expect(
        (await db.select(db.budgetTransactionsTable).get()).single.id,
        foreign,
      );
    },
  );

  test(
    'an untouched created action is deleted, an edited one is kept',
    () async {
      final actions = ActionService(db);
      final a1 = await actions.createAction(name: 'Shop');
      final a2 = await actions.createAction(name: 'Bazaar');
      final batchId = await batches.startBatch(jobId: 'job4', threadId: 't');
      for (final (i, id) in [a1, a2].indexed) {
        await batches.record(
          batchId,
          position: i,
          entityType: AiEntity.action,
          entityId: id,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await actions.updateNotes(a2, 'edited');

      final r = await batches.undoBatch(batchId);
      expect(r.actions, 1);
      expect(r.skipped, hasLength(1));
      final left = await db.select(db.actionsTable).get();
      expect(left.map((a) => a.id), [a2]);
    },
  );

  test('an update is restored from before_json', () async {
    final group = await seed.group('Food');
    final cat = await seed.leaf('Apples', price: 40, parentId: group);
    final tx = await budget.createTransaction(categoryId: cat, quantity: 1);
    final batchId = await batches.startBatch(jobId: 'job5', threadId: 't');
    await budget.updateTransaction(tx, quantity: 3);
    await batches.record(
      batchId,
      position: 0,
      entityType: AiEntity.transaction,
      entityId: tx,
      op: AiOp.update,
      before: {'quantity': 1.0},
      after: {'quantity': 3.0},
    );
    final r = await batches.undoBatch(batchId);
    expect(r.restored, 1);
    final row = (await db.select(db.budgetTransactionsTable).get()).single;
    expect(row.quantity, 1.0);
  });
}
