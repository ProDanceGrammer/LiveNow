import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/time_codec.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/budget_service.dart';
import 'package:livenow/domain/plan_rules.dart';
import 'package:livenow/domain/plan_service.dart';
import 'package:livenow/domain/postpone_rules.dart';

/// Plan rows with Previous / Next companions and transaction templates:
/// the rule JSON, what a confirmation creates (times, links, transactions), the
/// Undo that removes all of it, and the transaction template CRUD itself.
void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late PlanService plans;
  late BudgetService budget;

  setUp(() {
    db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys = ON;'),
      ),
    );
    plans = PlanService(db, ActionService(db));
    budget = BudgetService(db);
  });
  tearDown(() => db.close());

  // Mon 19 Oct 2026 08:00 local (05:00Z).
  final now = DateTime.utc(2026, 10, 19, 5);
  DateTime day(int d) => planDate(2026, 10, d);

  Future<String> leafCategory({double? price = 600}) async {
    final acc = await budget.saveAccount(
      name: 'Cash',
      currency: 'EUR',
      rateToBase: 1,
    );
    return budget.saveCategory(
      CategoryInput(name: 'Groceries', accountCountId: acc, price: price),
    );
  }

  group('rule JSON', () {
    test('companions and transaction ids round-trip; old rules still decode', () {
      const occ = CycleOccurrence(
        day: 3,
        startMin: 18 * 60,
        extras: PlanExtras(
          prev: [PlanCompanion(name: 'Get ready', minutes: 30, gapMinutes: 5)],
          next: [
            PlanCompanion(
              name: 'Unpack',
              minutes: 20,
              txTemplateIds: ['t2'],
            ),
          ],
          txTemplateIds: ['t1'],
        ),
      );
      final back = CycleOccurrence.fromJson(occ.toJson());
      expect(back.extras.prev.single.name, 'Get ready');
      expect(back.extras.prev.single.gapMinutes, 5);
      expect(back.extras.next.single.txTemplateIds, ['t2']);
      expect(back.extras.txTemplateIds, ['t1']);
      final old = CycleOccurrence.fromJson({'day': 1, 'startMin': 60});
      expect(old.extras.isEmpty, isTrue);
      final m = MonthlyRule.fromJson(
        const MonthlyRule(extras: PlanExtras(txTemplateIds: ['x'])).toJson(),
      );
      expect(m.extras.txTemplateIds, ['x']);
    });
  });

  group('transaction templates', () {
    test('save, edit, delete with undo; a template makes a real transaction', () async {
      final cat = await leafCategory();
      final id = await budget.saveTxTemplate(
        name: 'Market',
        categoryId: cat,
        quantity: 2,
      );
      expect((await budget.txTemplates()).single.name, 'Market');
      await budget.saveTxTemplate(
        id: id,
        name: 'Market run',
        categoryId: cat,
        quantity: 2,
        unitPrice: 50,
      );
      final t = (await budget.txTemplates()).single;
      expect((t.name, t.quantity, t.unitPrice), ('Market run', 2.0, 50.0));

      final txId = await budget.createTransactionFromTemplate(id);
      final tx = await (db.select(
        db.budgetTransactionsTable,
      )..where((r) => r.id.equals(txId))).getSingle();
      expect((tx.name, tx.quantity, tx.unitPrice, tx.categoryId), (
        'Market run',
        2.0,
        50.0,
        cat,
      ));

      final gone = await budget.deleteTxTemplate(id);
      expect(await budget.txTemplates(), isEmpty);
      await budget.undoDeleteTxTemplate(gone!);
      expect((await budget.txTemplates()).single.id, id);
    });

    test('a missing template or category is refused', () async {
      expect(
        () => budget.createTransactionFromTemplate('nope'),
        throwsA(isA<StateError>()),
      );
      final id = await budget.saveTxTemplate(name: 'X', categoryId: 'gone');
      expect(
        () => budget.createTransactionFromTemplate(id),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('confirm with companions and transactions', () {
    Future<String> bazaar({
      required String market,
      required String taxi,
    }) => plans.saveItem(
      PlanItemInput(
        name: 'Bazaar',
        kind: PlanKind.cycle,
        startDate: day(19),
        manualMinutes: 120,
        cycle: CycleRule(
          cycleDays: 7,
          occurrences: [
            CycleOccurrence(
              day: 3, // Thursday
              startMin: 18 * 60,
              durationMin: 120,
              extras: PlanExtras(
                prev: [
                  const PlanCompanion(name: 'Get ready', minutes: 30),
                ],
                next: [
                  PlanCompanion(
                    name: 'Unpack',
                    minutes: 20,
                    gapMinutes: 10,
                    txTemplateIds: [taxi],
                  ),
                ],
                txTemplateIds: [market],
              ),
            ),
          ],
        ),
      ),
    );

    test('creates the three connected actions and the transactions', () async {
      final cat = await leafCategory();
      final market = await budget.saveTxTemplate(
        name: 'Groceries',
        categoryId: cat,
        unitPrice: 600,
      );
      final taxi = await budget.saveTxTemplate(
        name: 'Taxi',
        categoryId: cat,
        unitPrice: 150,
      );
      final id = await bazaar(market: market, taxi: taxi);

      final r = await plans.confirm(from: day(19), to: day(22), nowUtc: now);
      expect(r.createdIds, hasLength(3));
      expect(r.transactionIds, hasLength(2));
      expect(r.skipped, 0);

      final rows = {
        for (final a in await db.select(db.actionsTable).get()) a.name: a,
      };
      // Thursday 22 Oct 18:00-20:00 local = 15:00-17:00Z.
      final main = rows['Bazaar']!;
      expect(dateTimeFromDb(main.startAt), DateTime.utc(2026, 10, 22, 15));
      expect(dateTimeFromDb(main.endAt), DateTime.utc(2026, 10, 22, 17));
      final before = rows['Get ready']!;
      expect(dateTimeFromDb(before.endAt), DateTime.utc(2026, 10, 22, 15));
      expect(
        dateTimeFromDb(before.startAt),
        DateTime.utc(2026, 10, 22, 14, 30),
      );
      final after = rows['Unpack']!;
      expect(dateTimeFromDb(after.startAt), DateTime.utc(2026, 10, 22, 17, 10));
      expect(dateTimeFromDb(after.endAt), DateTime.utc(2026, 10, 22, 17, 30));
      expect(
        {main.planItemId, before.planItemId, after.planItemId},
        {id},
      );

      final edges = {
        for (final e in await db.select(db.actionDependenciesTable).get())
          '${e.predecessorId}>${e.successorId}',
      };
      expect(edges, {
        '${before.id}>${main.id}',
        '${main.id}>${after.id}',
      });

      final txs = await db.select(db.budgetTransactionsTable).get();
      final byAction = {for (final t in txs) t.actionId: t};
      expect(byAction[main.id]!.unitPrice, 600);
      expect(byAction[after.id]!.unitPrice, 150);
      expect(
        dateTimeFromDb(byAction[after.id]!.occurredAt),
        isNotNull,
      );

      // Confirming again creates nothing new.
      final again = await plans.confirm(from: day(19), to: day(22), nowUtc: now);
      expect(again.createdIds, isEmpty);
      expect(await db.select(db.budgetTransactionsTable).get(), hasLength(2));
    });

    test('Undo removes the transactions too, not only the actions', () async {
      final cat = await leafCategory();
      final market = await budget.saveTxTemplate(
        name: 'Groceries',
        categoryId: cat,
      );
      final taxi = await budget.saveTxTemplate(name: 'Taxi', categoryId: cat);
      await bazaar(market: market, taxi: taxi);
      final r = await plans.confirm(from: day(19), to: day(22), nowUtc: now);
      await plans.undoConfirm(r.createdIds, transactionIds: r.transactionIds);
      expect(await db.select(db.actionsTable).get(), isEmpty);
      expect(await db.select(db.budgetTransactionsTable).get(), isEmpty);
    });

    test('a deleted template is skipped and counted, the actions still come', () async {
      final cat = await leafCategory();
      final market = await budget.saveTxTemplate(
        name: 'Groceries',
        categoryId: cat,
      );
      final taxi = await budget.saveTxTemplate(name: 'Taxi', categoryId: cat);
      await bazaar(market: market, taxi: taxi);
      await budget.deleteTxTemplate(taxi);
      final r = await plans.confirm(from: day(19), to: day(22), nowUtc: now);
      expect(r.createdIds, hasLength(3));
      expect(r.transactionIds, hasLength(1));
      expect(r.skipped, 1);
    });

    test('removeFuture also takes the companions', () async {
      final id = await bazaar(market: 'm', taxi: 't');
      await plans.confirm(from: day(19), to: day(22), nowUtc: now);
      final undo = await plans.removeFuture(id, nowUtc: now);
      expect(undo!.count, 3);
    });
  });
}
