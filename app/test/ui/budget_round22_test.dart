import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/budget_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/screens/budget_screen.dart';
import 'package:livenow/ui/widgets/budget_dialogs.dart';

/// Round 22 (Budget): add / create transactions from the category dialog, the
/// transactions grouping always shows the three sums, accounts (delete only in
/// the edit menu, phone balances with the main-currency star) and the phone
/// Categories row (icons + currency).
void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late String catHome, catFlat, catFood, accEuro, accLira, txBread;

  Future<void> settle(WidgetTester tester, [int ms = 300]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pump(
    WidgetTester tester, {
    String? tab,
    Size size = const Size(1400, 1000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys = ON;'),
      ),
    );
    addTearDown(db.close);
    await tester.runAsync(() async {
      final b = BudgetService(db);
      accEuro = await b.saveAccount(
        name: 'Euro',
        currency: 'EUR',
        rateToBase: 1,
        openingBalance: 80,
      );
      accLira = await b.saveAccount(
        name: 'Lira',
        currency: 'TRY',
        rateToBase: 40,
        openingBalance: 4000,
      );
      catHome = await b.saveCategory(
        CategoryInput(name: 'Home', accountCountId: accEuro),
      );
      catFlat = await b.saveCategory(
        CategoryInput(
          name: 'Flat',
          parentId: catHome,
          price: 100,
          unitsPerMonth: 1,
          frequencyMonths: 1,
          accountCountId: accEuro,
        ),
      );
      catFood = await b.saveCategory(
        CategoryInput(name: 'Food', price: 10, accountCountId: accLira),
      );
      final action = await ActionService(db).createAction(name: 'Shopping');
      txBread = await b.createTransaction(
        categoryId: catFood,
        actionId: action,
        name: 'Bread',
        quantity: 2,
        unitPrice: 100,
      );
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: BudgetScreen()),
      ),
    );
    await settle(tester);
    if (tab != null) {
      final f = find.descendant(
        of: find.byKey(const ValueKey('budget-switch')),
        matching: find.text(tab),
      );
      await tester.ensureVisible(f);
      await tester.pump();
      await tester.tap(f);
      await settle(tester);
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    resetStackedDialogsForTest();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> openCategory(WidgetTester tester, String id) async {
    final c = (await tester.runAsync(
      () => (db.select(
        db.budgetCategoriesTable,
      )..where((t) => t.id.equals(id))).getSingle(),
    ))!;
    BudgetCategoryDialog.show(
      tester.element(find.byType(Scaffold).first),
      existing: c,
    );
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<String?> categoryOf(WidgetTester tester, String txId) async =>
      (await tester.runAsync(
        () => (db.select(
          db.budgetTransactionsTable,
        )..where((t) => t.id.equals(txId))).getSingle(),
      ))!.categoryId;

  group('category dialog: add / create transactions', () {
    testWidgets('+ is there for a leaf category and hidden for a group', (
      tester,
    ) async {
      await pump(tester, tab: 'Categories');
      await openCategory(tester, catFood);
      expect(find.byKey(const ValueKey('category-tx-add')), findsOneWidget);
      resetStackedDialogsForTest();
      await unmount(tester);

      await pump(tester, tab: 'Categories');
      await openCategory(tester, catHome);
      expect(find.byKey(const ValueKey('category-tx-add')), findsNothing);
      await unmount(tester);
    });

    testWidgets('an existing transaction moves into the category', (
      tester,
    ) async {
      await pump(tester, tab: 'Categories');
      // The picker lists transactions NOT in this category.
      await openCategory(tester, catFlat);
      await tester.tap(find.byKey(const ValueKey('category-tx-add')));
      await settle(tester);
      expect(find.text('Add a transaction'), findsOneWidget);
      expect(find.byKey(const ValueKey('tx-pick-new')), findsOneWidget);
      // A search by the ACTION's name finds it too.
      await tester.enterText(
        find.byKey(const ValueKey('tx-pick-search')),
        'shopp',
      );
      await tester.pump();
      expect(find.byKey(ValueKey('tx-pick-$txBread')), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('tx-pick-$txBread')));
      await settle(tester);
      expect(await categoryOf(tester, txBread), catFlat);
      await unmount(tester);
    });

    testWidgets('Create new opens the transaction dialog for this category', (
      tester,
    ) async {
      await pump(tester, tab: 'Categories');
      await openCategory(tester, catFlat);
      await tester.tap(find.byKey(const ValueKey('category-tx-add')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('tx-pick-new')));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('New transaction'), findsOneWidget);
      // The category is preselected.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('tx-open-category')),
          matching: find.text('Flat'),
        ),
        findsOneWidget,
      );
      await unmount(tester);
    });
  });

  group('transactions grouping', () {
    testWidgets('every group shows Counting, Interactional (a dash without a use account) and Main', (
      tester,
    ) async {
      await pump(tester, tab: 'Transactions');
      expect(find.byTooltip('Counting'), findsWidgets);
      expect(find.byTooltip('Interactional'), findsWidgets);
      expect(find.byTooltip('Main'), findsWidgets);
      // Bread has no use account: the dash.
      expect(find.text('—'), findsWidgets);
      await unmount(tester);
    });
  });

  group('accounts', () {
    testWidgets('no delete on the cards; the edit menu has a red delete with Undo', (
      tester,
    ) async {
      await pump(tester, tab: 'Accounts');
      expect(
        find.byKey(ValueKey('budget-delete-account-$accEuro')),
        findsNothing,
      );
      await tester.tap(find.byKey(ValueKey('budget-account-$accEuro')));
      await settle(tester);
      final del = find.byKey(const ValueKey('account-delete'));
      expect(del, findsOneWidget);
      expect(
        tester.widget<IconButton>(del).color,
        Theme.of(tester.element(del)).colorScheme.error,
      );
      await tester.tap(del);
      await settle(tester);
      expect(find.byKey(ValueKey('budget-account-$accEuro')), findsNothing);
      expect(find.text('Undo'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await settle(tester);
      expect(find.byKey(ValueKey('budget-account-$accEuro')), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('a new account has no delete button', (tester) async {
      await pump(tester, tab: 'Accounts');
      BudgetAccountDialog.show(tester.element(find.byType(Scaffold).first));
      await settle(tester);
      expect(find.byKey(const ValueKey('account-delete')), findsNothing);
      await unmount(tester);
    });

    testWidgets('on a phone the main balance (star) sits over the account balance at the bottom right', (
      tester,
    ) async {
      await pump(tester, tab: 'Accounts', size: const Size(375, 812));
      final star = find.descendant(
        of: find.byKey(ValueKey('budget-account-$accLira')),
        matching: find.byTooltip('Main'),
      );
      expect(star, findsOneWidget);
      final main = tester.getTopLeft(
        find.byKey(ValueKey('budget-main-balance-$accLira')),
      );
      final own = tester.getTopLeft(
        find.byKey(ValueKey('budget-balance-$accLira')),
      );
      expect(main.dy, lessThan(own.dy), reason: 'main over the own balance');
      // Right-aligned: the right edges meet near the card's right edge.
      final card = tester.getRect(find.byKey(ValueKey('budget-account-$accLira')));
      final mainRect = tester.getRect(
        find.byKey(ValueKey('budget-main-balance-$accLira')),
      );
      expect(card.right - mainRect.right, lessThan(40));
      await unmount(tester);
    });
  });

  group('phone Categories row', () {
    testWidgets('plan and fact have their icons on the left and the currency on the right', (
      tester,
    ) async {
      await pump(tester, tab: 'Categories', size: const Size(375, 812));
      final row = find.byKey(ValueKey('budget-category-$catFlat'));
      expect(row, findsOneWidget);
      // The main currency code appears next to the figures (EUR is the base).
      expect(
        find.descendant(of: row, matching: find.text('EUR')),
        findsNWidgets(2),
      );
      await unmount(tester);
    });
  });
}
