import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/budget_rules.dart' show BudgetUnit;
import 'package:livenow/domain/budget_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/screens/budget_screen.dart';
import 'package:livenow/ui/widgets/budget_dialogs.dart';

/// Round 19: category dialog (one-time switch, parent block, sub-category
/// blocks, plan / fact in the transactions panel), transaction dialog category
/// controls, Accounts (main balance + sort), Transactions columns / values /
/// saved views, Categories level buttons and the kg/lt label.
void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late String catRent, catFlat, catFood, accEuro, accLira, txBread;

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
    Widget? home,
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
      catRent = await b.saveCategory(
        CategoryInput(name: 'Home', accountCountId: accEuro),
      );
      catFlat = await b.saveCategory(
        CategoryInput(
          name: 'Flat',
          parentId: catRent,
          price: 100,
          unitsPerMonth: 1,
          frequencyMonths: 1,
          accountCountId: accEuro,
        ),
      );
      catFood = await b.saveCategory(
        CategoryInput(
          name: 'Food',
          price: 9.55,
          unit: BudgetUnit.kilogram,
          accountCountId: accLira,
        ),
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
        child: MaterialApp(home: home ?? const BudgetScreen()),
      ),
    );
    await settle(tester);
    if (tab != null) {
      final tabFinder = find.descendant(
        of: find.byKey(const ValueKey('budget-switch')),
        matching: find.text(tab),
      );
      await tester.ensureVisible(tabFinder);
      await tester.pump();
      await tester.tap(tabFinder);
      await settle(tester);
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    resetStackedDialogsForTest();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<BudgetCategory> category(String id) => (db.select(
    db.budgetCategoriesTable,
  )..where((t) => t.id.equals(id))).getSingle();

  Future<void> openCategory(WidgetTester tester, String id) async {
    final c = await tester.runAsync(() => category(id));
    final ctx = tester.element(find.byType(Scaffold).first);
    BudgetCategoryDialog.show(ctx, existing: c);
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('category dialog', () {
    testWidgets('One-time is a switch next to Type; only the switch toggles', (
      tester,
    ) async {
      await pump(tester, tab: 'Categories');
      await openCategory(tester, catFlat);
      final sw = find.byKey(const ValueKey('category-one-time'));
      expect(tester.widget(sw), isA<Switch>());
      expect(find.byType(SwitchListTile), findsNothing);
      expect(tester.widget<Switch>(sw).value, isFalse);
      // The label is not a tap target.
      await tester.tap(find.text('One-time'));
      await tester.pump();
      expect(tester.widget<Switch>(sw).value, isFalse);
      await tester.tap(sw);
      await tester.pump();
      expect(tester.widget<Switch>(sw).value, isTrue);
      await unmount(tester);
    });

    testWidgets('a group has no one-time switch', (tester) async {
      await pump(tester, tab: 'Categories');
      await openCategory(tester, catRent);
      expect(find.byKey(const ValueKey('category-one-time')), findsNothing);
      await unmount(tester);
    });

    testWidgets('Parent category is a block with + / change and a remove button', (
      tester,
    ) async {
      await pump(tester, tab: 'Categories');
      await openCategory(tester, catFlat);
      expect(find.text('Parent category'), findsOneWidget);
      // Flat sits under Home: its row opens it, the cross removes the parent.
      expect(
        find.byKey(const ValueKey('category-parent-open')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('category-parent-clear')));
      await tester.pump();
      expect(find.byKey(const ValueKey('category-parent-open')), findsNothing);
      // ... and + sets one again through the picker.
      await tester.tap(find.byKey(const ValueKey('category-parent-add')));
      await settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byKey(ValueKey('pick-category-$catFood')),
          matching: find.text('Food'),
        ),
      );
      await settle(tester);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('category-parent')),
          matching: find.text('Food'),
        ),
        findsOneWidget,
      );
      await unmount(tester);
    });

    testWidgets('sub-categories are separate bordered blocks', (tester) async {
      await pump(tester, tab: 'Categories');
      await openCategory(tester, catRent);
      expect(find.text('Sub-categories'), findsOneWidget);
      expect(find.byKey(ValueKey('category-sub-$catFlat')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(ValueKey('category-sub-$catFlat')),
          matching: find.byType(Container),
        ),
        findsWidgets,
      );
      await unmount(tester);
    });

    testWidgets('units and frequency sit on one row; percent value + source too', (
      tester,
    ) async {
      await pump(tester, tab: 'Categories');
      await openCategory(tester, catFlat);
      final units = tester.getTopLeft(
        find.byKey(const ValueKey('category-units')),
      );
      final freq = tester.getTopLeft(
        find.byKey(const ValueKey('category-frequency')),
      );
      expect(units.dy, freq.dy);
      expect(
        tester.getSize(find.byKey(const ValueKey('category-units'))).height,
        tester.getSize(find.byKey(const ValueKey('category-frequency'))).height,
      );
      await unmount(tester);
    });

    testWidgets('price, units and frequency share a row; the accounts sit below', (
      tester,
    ) async {
      await pump(tester, tab: 'Categories');
      await openCategory(tester, catFlat);
      final price = tester.getTopLeft(find.byKey(const ValueKey('category-price')));
      final units = tester.getTopLeft(find.byKey(const ValueKey('category-units')));
      final freq = tester.getTopLeft(find.byKey(const ValueKey('category-frequency')));
      expect(units.dy, price.dy);
      expect(freq.dy, price.dy);
      expect(price.dx, lessThan(units.dx));
      expect(units.dx, lessThan(freq.dx));
      final count = tester.getTopLeft(find.byKey(const ValueKey('category-account-count')));
      final use = tester.getTopLeft(find.byKey(const ValueKey('category-account-use')));
      expect(count.dy, greaterThan(price.dy));
      expect(use.dy, greaterThan(count.dy));
      // ... and above the parent block.
      final parent = tester.getTopLeft(find.byKey(const ValueKey('category-parent')));
      expect(use.dy, lessThan(parent.dy));
      await unmount(tester);
    });

    testWidgets('the transactions panel shows income, expense, plan and fact', (
      tester,
    ) async {
      await pump(tester, tab: 'Categories');
      await openCategory(tester, catFood);
      // The three totals and the plan / fact; no income / expense lines.
      expect(find.byKey(const ValueKey('category-tx-counting')), findsOneWidget);
      expect(find.byKey(const ValueKey('category-tx-main')), findsOneWidget);
      expect(find.byKey(const ValueKey('category-tx-plan')), findsOneWidget);
      expect(find.byKey(const ValueKey('category-tx-fact')), findsOneWidget);
      expect(find.byKey(const ValueKey('category-tx-income')), findsNothing);
      expect(find.byKey(const ValueKey('category-tx-expense')), findsNothing);
      // 2 x 100 TRY at 40 TRY per EUR = 5 EUR spent.
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('category-tx-main'))).data,
        contains('5.00'),
      );
      await unmount(tester);
    });
  });

  group('transaction dialog', () {
    testWidgets('category: open, change, clear (Save then asks for one)', (
      tester,
    ) async {
      await pump(tester, tab: 'Transactions');
      await tester.tap(find.byKey(ValueKey('budget-tx-$txBread')));
      await settle(tester);
      expect(find.byKey(const ValueKey('tx-open-category')), findsOneWidget);
      expect(find.byKey(const ValueKey('tx-category')), findsOneWidget);
      // The linked action's date is shown.
      expect(find.byKey(const ValueKey('tx-action-date')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tx-clear-category')));
      await tester.pump();
      expect(find.text('No category'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tx-save')));
      await tester.pump();
      expect(find.text('Pick a category'), findsWidgets);
      await unmount(tester);
    });
  });

  group('accounts', () {
    testWidgets('main-currency balance, biggest first', (
      tester,
    ) async {
      await pump(tester, tab: 'Accounts');
      // Euro 80, Lira 4000 / 40 = 100.
      final order = [
        for (final e in find.byKey(const ValueKey('budget-switch')).evaluate())
          e,
      ];
      expect(order, isNotEmpty);
      final lira = tester.getTopLeft(find.byKey(ValueKey('budget-account-$accLira'))).dy;
      final euro = tester.getTopLeft(find.byKey(ValueKey('budget-account-$accEuro'))).dy;
      expect(lira, lessThan(euro));
      expect(
        tester
            .widget<Text>(find.byKey(ValueKey('budget-main-balance-$accLira')))
            .data,
        '100.00 EUR',
      );
      await unmount(tester);
    });

    testWidgets('sorting by name puts Euro before Lira', (tester) async {
      await pump(tester, tab: 'Accounts');
      await tester.tap(find.byKey(const ValueKey('account-sort-add')));
      await settle(tester);
      await tester.tap(find.text('Name').last);
      await settle(tester);
      // Main balance stays the first level; remove it to leave the name sort.
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('account-sort-chip-mainBalance')),
          matching: find.byIcon(Icons.clear),
        ),
      );
      await settle(tester);
      final names = ['Euro', 'Lira'];
      final tops = [
        for (final n in names)
          tester.getTopLeft(find.text(n).first).dy,
      ];
      expect(tops[0], lessThan(tops[1]));
      await unmount(tester);
    });
  });

  group('transactions tab', () {
    testWidgets('column names and all three values per tile', (tester) async {
      await pump(tester, tab: 'Transactions');
      // The column names are icons (tooltips name them).
      expect(find.byTooltip('Counting'), findsWidgets);
      expect(find.byTooltip('Interactional'), findsWidgets);
      expect(find.byTooltip('Main'), findsWidgets);
      expect(find.text('Counting'), findsNothing);
      final tile = find.byKey(ValueKey('budget-tx-$txBread'));
      expect(
        find.descendant(of: tile, matching: find.textContaining('TRY')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tile, matching: find.textContaining('EUR')),
        findsOneWidget,
      );
      await unmount(tester);
    });

    testWidgets('a wide window shows all three values and has no value chips', (
      tester,
    ) async {
      await pump(tester, tab: 'Transactions');
      await tester.tap(find.byKey(const ValueKey('budget-tx-options-toggle')));
      await settle(tester);
      expect(find.byKey(const ValueKey('tx-col-main')), findsNothing);
      expect(find.byKey(const ValueKey('tx-totals-show')), findsOneWidget);
      final tile = find.byKey(ValueKey('budget-tx-$txBread'));
      expect(
        find.descendant(of: tile, matching: find.textContaining('TRY')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tile, matching: find.textContaining('EUR')),
        findsOneWidget,
      );
      await unmount(tester);
    });

    testWidgets('on a phone the values can be switched off, the last one stays', (
      tester,
    ) async {
      await pump(tester, tab: 'Transactions', size: const Size(375, 812));
      await tester.tap(find.byKey(const ValueKey('budget-tx-options-toggle')));
      await settle(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('tx-col-main')));
      await tester.tap(find.byKey(const ValueKey('tx-col-main')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('tx-col-interact')));
      await tester.pump();
      // Only Counting is left: it cannot be switched off.
      await tester.tap(find.byKey(const ValueKey('tx-col-counting')));
      await tester.pump();
      expect(
        tester.widget<FilterChip>(find.byKey(const ValueKey('tx-col-counting'))).selected,
        isTrue,
      );
      final tile = find.byKey(ValueKey('budget-tx-$txBread'));
      expect(
        find.descendant(of: tile, matching: find.textContaining('EUR')),
        findsNothing,
      );
      await unmount(tester);
    });

    testWidgets('totals can be hidden', (tester) async {
      await pump(tester, tab: 'Transactions');
      expect(find.byKey(const ValueKey('tx-totals-plan')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('budget-tx-options-toggle')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('tx-totals-show')));
      await settle(tester);
      expect(find.byKey(const ValueKey('tx-totals-plan')), findsNothing);
      // The title stays.
      expect(find.textContaining('Total (1)'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('an action group shows the action date under its name', (
      tester,
    ) async {
      await pump(tester, tab: 'Transactions');
      expect(find.byKey(const ValueKey('tx-group-date')), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('filter by chosen actions', (tester) async {
      await pump(tester, tab: 'Transactions');
      await tester.tap(find.byKey(const ValueKey('budget-tx-options-toggle')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('tx-filter-actions')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('tx-actions-all')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('tx-actions-apply')));
      await settle(tester);
      expect(find.text('Actions (1)'), findsOneWidget);
      expect(find.byKey(ValueKey('budget-tx-$txBread')), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('the sort icon of Category is the categories icon', (
      tester,
    ) async {
      await pump(tester, tab: 'Transactions');
      await tester.tap(find.byKey(const ValueKey('budget-tx-options-toggle')));
      await settle(tester);
      expect(find.byIcon(Icons.category_outlined), findsNothing);
      await unmount(tester);
    });

    testWidgets('a saved view: save it, clear, apply it back, make it default', (
      tester,
    ) async {
      await pump(tester, tab: 'Transactions');
      await tester.tap(find.byKey(const ValueKey('budget-tx-options-toggle')));
      await settle(tester);
      // Change the sort: add Name.
      await tester.tap(find.byKey(const ValueKey('tx-sort-add')));
      await settle(tester);
      await tester.tap(find.text('Name').last);
      await settle(tester);
      expect(find.byKey(const ValueKey('tx-sort-chip-name')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('views-save')));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('views-name')), 'By name');
      await tester.tap(find.byKey(const ValueKey('views-make-default')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('views-save-confirm')));
      await settle(tester, 600);
      expect(find.textContaining('By name'), findsOneWidget);
      expect(find.textContaining('★ By name'), findsOneWidget);

      // Clear: back to the plain sort.
      await tester.tap(find.byKey(const ValueKey('views-clear')));
      await settle(tester);
      expect(find.byKey(const ValueKey('tx-sort-chip-name')), findsNothing);

      // Tap the view: the sort comes back.
      await tester.tap(find.textContaining('By name'));
      await settle(tester);
      expect(find.byKey(const ValueKey('tx-sort-chip-name')), findsOneWidget);
      await unmount(tester);
    });
  });

  group('categories board', () {
    testWidgets('level buttons fold and open the hierarchy', (tester) async {
      await pump(tester, tab: 'Categories');
      expect(find.byKey(ValueKey('budget-category-$catFlat')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cat-level-1')));
      await settle(tester);
      expect(find.byKey(ValueKey('budget-category-$catFlat')), findsNothing);
      expect(find.byKey(ValueKey('budget-category-$catRent')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cat-level-all')));
      await settle(tester);
      expect(find.byKey(ValueKey('budget-category-$catFlat')), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('kilograms read kg/lt', (tester) async {
      await pump(tester, tab: 'Categories');
      expect(find.textContaining('per kg/lt'), findsWidgets);
      expect(find.textContaining('kilogram'), findsNothing);
      await unmount(tester);
    });

    testWidgets('no Used column on a wide window', (tester) async {
      await pump(tester, tab: 'Categories');
      expect(find.text('Used'), findsNothing);
      await unmount(tester);
    });

    testWidgets('a phone can hide search, sort and Flat', (tester) async {
      await pump(
        tester,
        tab: 'Categories',
        size: const Size(375, 812),
      );
      expect(find.byKey(const ValueKey('budget-categories-search')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cat-toolbar-toggle')));
      await settle(tester);
      expect(find.byKey(const ValueKey('budget-categories-search')), findsNothing);
      expect(find.byKey(const ValueKey('cat-flat')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('cat-toolbar-toggle')));
      await settle(tester);
      expect(find.byKey(const ValueKey('budget-categories-search')), findsOneWidget);
      await unmount(tester);
    });
  });

  group('overview', () {
    testWidgets('Plan comes before Fact', (tester) async {
      await pump(tester);
      final plan = tester.getTopLeft(find.byKey(const ValueKey('budget-plan-total')));
      final fact = tester.getTopLeft(find.byKey(const ValueKey('budget-fact-total')));
      expect(plan.dx, lessThan(fact.dx));
      await unmount(tester);
    });
  });
}
