import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/time_codec.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/budget_rules.dart';
import 'package:livenow/domain/budget_service.dart';
import 'package:livenow/domain/postpone_rules.dart';

void main() {
  late AppDatabase db;
  late BudgetService budget;
  late ActionService actions;

  setUpAll(initPostponeTimeZoneData);

  setUp(() {
    db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys = ON;'),
      ),
    );
    budget = BudgetService(db);
    actions = ActionService(db);
  });

  tearDown(() => db.close());

  Future<String> eur() => budget.saveAccount(
    name: 'Euro',
    currency: 'eur',
    rateToBase: 1,
    openingBalance: 100,
  );

  Future<BudgetTransaction> tx(String id) => (db.select(
    db.budgetTransactionsTable,
  )..where((t) => t.id.equals(id))).getSingle();

  group('settings', () {
    test('defaults, then saved values', () async {
      var s = await budget.settings();
      expect(s.baseCurrency, 'EUR');
      expect(s.periodMonths, 3);
      expect(s.tolerance, 10);
      await budget.saveSettings(
        const BudgetSettings(baseCurrency: 'usd', periodMonths: 6, tolerance: 25),
      );
      s = await budget.settings();
      expect(s.baseCurrency, 'USD');
      expect(s.periodMonths, 6);
      expect(s.tolerance, 25);
    });

    test('garbage values fall back to defaults', () {
      final s = BudgetService.settingsFromMap({
        'base_currency': ' ',
        'period_months': 'x',
        'tolerance': '-4',
      });
      expect(s.baseCurrency, 'EUR');
      expect(s.periodMonths, 3);
      expect(s.tolerance, 10);
    });
  });

  group('accounts', () {
    test('rate must be positive; currency is upper-cased', () async {
      expect(
        () => budget.saveAccount(name: 'x', currency: 'tl', rateToBase: 0),
        throwsArgumentError,
      );
      final id = await eur();
      final a = await (db.select(db.budgetAccountsTable)).getSingle();
      expect(a.id, id);
      expect(a.currency, 'EUR');
    });

    test('delete detaches categories and transactions, undo reattaches', () async {
      final acc = await eur();
      final cat = await budget.saveCategory(
        CategoryInput(name: 'Food', accountCountId: acc, accountUseId: acc),
      );
      final t = await budget.createTransaction(categoryId: cat, unitPrice: 5);
      final undo = (await budget.deleteAccount(acc))!;
      expect((await tx(t)).accountUseId, isNull);
      expect(await db.select(db.budgetAccountsTable).get(), isEmpty);
      await budget.undoDeleteAccount(undo);
      expect((await tx(t)).accountUseId, acc);
      expect(
        (await db.select(db.budgetCategoriesTable).getSingle()).accountCountId,
        acc,
      );
    });
  });

  group('categories', () {
    test('parent cycle and percent cycle are refused', () async {
      final a = await budget.saveCategory(const CategoryInput(name: 'a'));
      final b = await budget.saveCategory(CategoryInput(name: 'b', parentId: a));
      expect(
        () => budget.saveCategory(CategoryInput(id: a, name: 'a', parentId: b)),
        throwsA(isA<BudgetCycleException>()),
      );
      final p = await budget.saveCategory(
        CategoryInput(
          name: 'p',
          unit: BudgetUnit.percentPerMonth,
          percent: 10,
          countPercentOfId: a,
        ),
      );
      expect(
        () => budget.saveCategory(
          CategoryInput(
            id: a,
            name: 'a',
            unit: BudgetUnit.percentPerMonth,
            percent: 5,
            countPercentOfId: p,
          ),
        ),
        throwsA(isA<BudgetCycleException>()),
      );
    });

    test('a category with transactions cannot become a parent until moved',
        () async {
      final acc = await eur();
      final chicken = await budget.saveCategory(
        CategoryInput(name: 'Chicken', price: 5, accountCountId: acc),
      );
      await budget.createTransaction(categoryId: chicken);
      expect(
        () => budget.saveCategory(
          CategoryInput(name: 'Chicken 5', parentId: chicken),
        ),
        throwsA(isA<BudgetGroupException>()),
      );
      final child = await budget.saveCategory(
        CategoryInput(name: 'Chicken 5 EUR', price: 5, accountCountId: acc),
      );
      expect(await budget.moveTransactions(chicken, child), 1);
      await budget.saveCategory(
        CategoryInput(id: child, name: 'Chicken 5 EUR', parentId: chicken),
      );
      // The moved transaction now lives in the leaf, the parent is a group.
      expect(
        () => budget.createTransaction(categoryId: chicken),
        throwsA(isA<BudgetGroupException>()),
      );
      // Re-saving an existing child does not re-trigger the rule.
      await budget.saveCategory(
        CategoryInput(id: child, name: 'Renamed', parentId: chicken),
      );
    });

    test('delete: children go top-level, transactions stay; undo restores', () async {
      final acc = await eur();
      final parent = await budget.saveCategory(const CategoryInput(name: 'Food'));
      final leaf = await budget.saveCategory(
        CategoryInput(name: 'Meat', parentId: parent, price: 10, accountCountId: acc),
      );
      final t = await budget.createTransaction(categoryId: leaf);
      final undo = (await budget.deleteCategory(leaf))!;
      expect((await tx(t)).categoryId, isNull);
      expect((await tx(t)).unitPrice, 10); // snapshot survives
      final undoParent = (await budget.deleteCategory(parent))!;
      expect(await db.select(db.budgetCategoriesTable).get(), isEmpty);
      await budget.undoDeleteCategory(undoParent);
      await budget.undoDeleteCategory(undo);
      expect((await tx(t)).categoryId, leaf);
      final cats = await db.select(db.budgetCategoriesTable).get();
      expect(cats.firstWhere((c) => c.id == leaf).parentId, parent);
    });
  });

  group('transactions', () {
    test('snapshot price, accounts and rates from the category', () async {
      final tl = await budget.saveAccount(
        name: 'Lira',
        currency: 'TRY',
        rateToBase: 40,
      );
      final cat = await budget.saveCategory(
        CategoryInput(
          name: 'Market',
          isIncome: false,
          price: 400,
          accountCountId: tl,
          accountUseId: tl,
        ),
      );
      final id = await budget.createTransaction(categoryId: cat, quantity: 2);
      var row = await tx(id);
      expect(row.unitPrice, 400);
      expect(row.quantity, 2);
      expect(row.isIncome, isFalse);
      expect(row.rateCount, 40);
      expect(row.accountCountId, tl);

      // Changing the category price later does not touch the old transaction.
      await budget.saveCategory(
        CategoryInput(
          id: cat,
          name: 'Market',
          price: 999,
          accountCountId: tl,
          accountUseId: tl,
        ),
      );
      row = await tx(id);
      expect(row.unitPrice, 400);
    });

    test('updateAccountRate: false keeps the account rate; explicit id is idempotent',
        () async {
      final tl = await budget.saveAccount(
        name: 'Lira',
        currency: 'TRY',
        rateToBase: 40,
      );
      final cat = await budget.saveCategory(
        CategoryInput(name: 'Market', price: 1, accountCountId: tl),
      );
      final id = await budget.createTransaction(
        id: 'fixed-id',
        categoryId: cat,
        rateCount: 45,
        updateAccountRate: false,
      );
      expect(id, 'fixed-id');
      expect((await tx(id)).rateCount, 45);
      expect(
        (await db.select(db.budgetAccountsTable).getSingle()).rateToBase,
        40,
      );
      final again = await budget.createTransaction(
        id: 'fixed-id',
        categoryId: cat,
        quantity: 9,
      );
      expect(again, 'fixed-id');
      expect((await tx(id)).quantity, 1);
      expect(await db.select(db.budgetTransactionsTable).get(), hasLength(1));
      await budget.updateTransaction(id, rateCount: 50, updateAccountRate: false);
      expect((await tx(id)).rateCount, 50);
      expect(
        (await db.select(db.budgetAccountsTable).getSingle()).rateToBase,
        40,
      );
    });

    test('a rate typed on a transaction becomes the account rate', () async {
      final tl = await budget.saveAccount(
        name: 'Lira',
        currency: 'TRY',
        rateToBase: 40,
      );
      final cat = await budget.saveCategory(
        CategoryInput(name: 'Market', price: 1, accountCountId: tl),
      );
      final id = await budget.createTransaction(categoryId: cat, rateCount: 45);
      expect((await tx(id)).rateCount, 45);
      expect(
        (await db.select(db.budgetAccountsTable).getSingle()).rateToBase,
        45,
      );
      // Editing the quantity afterwards carries the rate but never re-sets it.
      await budget.updateTransaction(id, quantity: 3);
      expect((await tx(id)).rateCount, 45);
    });

    test('percent categories store the quantity as the amount', () async {
      final acc = await eur();
      final cat = await budget.saveCategory(
        CategoryInput(
          name: 'Cushion',
          unit: BudgetUnit.percentPerMonth,
          percent: 10,
          accountCountId: acc,
        ),
      );
      final id = await budget.createTransaction(categoryId: cat, quantity: 220);
      final row = await tx(id);
      expect(row.isAmount, isTrue);
      expect(row.unitPrice, 0);
    });

    test('moving to another category re-snapshots income flag and accounts',
        () async {
      final acc = await eur();
      final spend = await budget.saveCategory(
        CategoryInput(name: 'Food', price: 5, accountCountId: acc),
      );
      final earn = await budget.saveCategory(
        CategoryInput(
          name: 'Salary',
          isIncome: true,
          price: 100,
          accountCountId: acc,
        ),
      );
      final id = await budget.createTransaction(categoryId: spend);
      await budget.updateTransaction(id, categoryId: earn);
      final row = await tx(id);
      expect(row.isIncome, isTrue);
      expect(row.unitPrice, 100);
    });

    test('delete + undo', () async {
      final cat = await budget.saveCategory(const CategoryInput(name: 'x'));
      final id = await budget.createTransaction(categoryId: cat);
      final row = (await budget.deleteTransaction(id))!;
      expect(await db.select(db.budgetTransactionsTable).get(), isEmpty);
      await budget.undoDeleteTransaction(row);
      expect((await tx(id)).id, id);
    });

    test('lastQuantity returns the newest transaction quantity', () async {
      final cat = await budget.saveCategory(const CategoryInput(name: 'x'));
      expect(await budget.lastQuantity(cat), isNull);
      await budget.createTransaction(categoryId: cat, quantity: 2);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await budget.createTransaction(categoryId: cat, quantity: 7);
      expect(await budget.lastQuantity(cat), 7);
    });
  });

  group('actions <-> transactions', () {
    test('deleting an action detaches its transactions and freezes the date; '
        'undo re-links them', () async {
      final cat = await budget.saveCategory(const CategoryInput(name: 'x'));
      final start = DateTime.utc(2026, 11, 3, 9);
      final a = await actions.createAction(name: 'Buy', startAt: start);
      final t = await budget.createTransaction(
        categoryId: cat,
        actionId: a,
        date: DateTime.utc(2026, 1, 1),
      );

      final undo = await actions.deleteAction(a);
      var row = await tx(t);
      expect(row.actionId, isNull);
      expect(row.occurredAt, dateTimeToDb(start));

      await actions.undoDelete(undo);
      row = await tx(t);
      expect(row.actionId, a);
      expect(row.occurredAt, dateTimeToDb(DateTime.utc(2026, 1, 1)));
    });

    test('undo skips a transaction deleted or re-linked meanwhile', () async {
      final cat = await budget.saveCategory(const CategoryInput(name: 'x'));
      final a = await actions.createAction(name: 'A');
      final b = await actions.createAction(name: 'B');
      final gone = await budget.createTransaction(categoryId: cat, actionId: a);
      final moved = await budget.createTransaction(categoryId: cat, actionId: a);
      final undo = await actions.deleteAction(a);
      await budget.deleteTransaction(gone);
      await budget.updateTransaction(moved, actionId: Value(b));
      await actions.undoDelete(undo);
      expect((await tx(moved)).actionId, b);
      expect(await db.select(db.budgetTransactionsTable).get(), hasLength(1));
    });

    test('deleteActions + undoDeleteMany keeps every link', () async {
      final cat = await budget.saveCategory(const CategoryInput(name: 'x'));
      final a = await actions.createAction(name: 'A');
      final b = await actions.createAction(name: 'B');
      final ta = await budget.createTransaction(categoryId: cat, actionId: a);
      final tb = await budget.createTransaction(categoryId: cat, actionId: b);
      final undo = await actions.deleteActions([a, b]);
      expect((await tx(ta)).actionId, isNull);
      expect((await tx(tb)).actionId, isNull);
      await actions.undoDeleteMany(undo);
      expect((await tx(ta)).actionId, a);
      expect((await tx(tb)).actionId, b);
    });
  });

  group('suggestedActionId', () {
    test('none, then last finished, then the running one', () async {
      expect(await budget.suggestedActionId(), isNull);
      final first = await actions.createAction(name: 'First');
      await actions.start(first);
      await actions.finish(first);
      expect(await budget.suggestedActionId(), first);

      final second = await actions.createAction(name: 'Second');
      await actions.start(second);
      expect(await budget.suggestedActionId(), second);
    });
  });
}
