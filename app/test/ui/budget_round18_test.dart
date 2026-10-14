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

/// Round 18, Transactions: grouping (default by action), totals in the three
/// currencies, the transaction dialog (delete, name from the category, amounts)
/// and the Budget settings switch.
void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late String txPlain, txBread, catFood;

  Future<void> settle(WidgetTester tester, [int ms = 300]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
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
      await b.saveAccount(name: 'Euro', currency: 'EUR', rateToBase: 1);
      final lira = await b.saveAccount(
        name: 'Lira',
        currency: 'TRY',
        rateToBase: 40,
      );
      catFood = await b.saveCategory(
        CategoryInput(name: 'Food', price: 100, accountCountId: lira),
      );
      final action = await ActionService(db).createAction(name: 'Shopping');
      txBread = await b.createTransaction(
        categoryId: catFood,
        actionId: action,
        name: 'Bread',
        quantity: 2,
        unitPrice: 100,
      );
      txPlain = await b.createTransaction(
        categoryId: catFood,
        name: '',
        quantity: 1,
        unitPrice: 40,
      );
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: BudgetScreen()),
      ),
    );
    await settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('budget-switch')),
        matching: find.text('Transactions'),
      ),
    );
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    resetStackedDialogsForTest();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('grouped by action by default, with totals in three currencies', (
    tester,
  ) async {
    await pump(tester);
    // The default grouping: a header per action, then "No action" last.
    expect(find.textContaining('Shopping (1)'), findsOneWidget);
    expect(find.textContaining('No action (1)'), findsOneWidget);
    // The overall total: 200 + 40 TRY spent = 6 EUR at 1 EUR = 40 TRY.
    final total = find.byKey(const ValueKey('tx-totals'));
    expect(
      find.descendant(of: total, matching: find.textContaining('Total (2)')),
      findsOneWidget,
    );
    // (The main row, the expense line and the period's fact all say 6.00 EUR.)
    expect(
      find.descendant(of: total, matching: find.textContaining('6.00 EUR')),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: total,
        matching: find.byKey(const ValueKey('tx-totals-plan')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: total,
        matching: find.byKey(const ValueKey('tx-totals-fact')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: total, matching: find.textContaining('TRY')),
      findsOneWidget,
    );
    // No delete icon on the rows any more.
    expect(find.byKey(ValueKey('budget-delete-tx-$txBread')), findsNothing);
    await unmount(tester);
  });

  testWidgets('grouping can be switched to categories, accounts or none', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('budget-tx-options-toggle')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('tx-group-category')));
    await settle(tester);
    expect(find.textContaining('Food (2)'), findsOneWidget);
    expect(find.textContaining('Shopping ('), findsNothing);
    await tester.tap(find.byKey(const ValueKey('tx-group-account')));
    await settle(tester);
    expect(find.textContaining('Lira (2)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tx-group-none')));
    await settle(tester);
    expect(find.textContaining('Lira ('), findsNothing);
    expect(find.byKey(ValueKey('budget-tx-$txBread')), findsOneWidget);
    expect(find.byKey(ValueKey('budget-tx-$txPlain')), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a group folds and unfolds', (tester) async {
    await pump(tester);
    expect(find.byKey(ValueKey('budget-tx-$txBread')), findsOneWidget);
    final key = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('tx-group-header-'),
    );
    await tester.tap(key.first);
    await settle(tester);
    // The first group is the action's (newest first): its row is hidden.
    expect(
      find.byKey(ValueKey('budget-tx-$txBread')).evaluate().length +
          find.byKey(ValueKey('budget-tx-$txPlain')).evaluate().length,
      1,
    );
    await unmount(tester);
  });

  testWidgets('the edit dialog shows three amounts, the categories icon, delete '
      'and "use the category name"', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(ValueKey('budget-tx-$txPlain')));
    await settle(tester);
    expect(find.byKey(const ValueKey('tx-delete')), findsOneWidget);
    expect(find.byIcon(Icons.category_outlined), findsNothing);
    Finder inDialog(String text) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.textContaining(text),
    );
    // The labels are icons now (tooltips name them).
    Finder tip(String name) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byTooltip(name),
    );
    expect(tip('Counting'), findsOneWidget);
    expect(tip('Main'), findsOneWidget);
    expect(tip('Expense'), findsOneWidget);
    expect(inDialog('1.00 EUR'), findsOneWidget); // 40 TRY / 40

    // An empty name can take the category's name.
    final fill = find.byKey(const ValueKey('tx-name-from-category'));
    expect(fill, findsOneWidget);
    await tester.tap(fill);
    await settle(tester);
    expect(find.byKey(const ValueKey('tx-name-from-category')), findsNothing);
    final field = tester.widget<TextFormField>(
      find.byKey(const ValueKey('tx-name')),
    );
    expect(field.controller!.text, 'Food');
    await unmount(tester);
  });

  testWidgets('the settings dialog has the urgency switch (off by default)', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('budget-settings')));
    await settle(tester);
    final sw = find.byKey(const ValueKey('settings-show-urgency'));
    expect(tester.widget<SwitchListTile>(sw).value, isFalse);
    await tester.tap(sw);
    await settle(tester, 100);
    await tester.tap(find.byKey(const ValueKey('settings-save')));
    await settle(tester);
    final s = await tester.runAsync(() => BudgetService(db).settings());
    expect(s!.showUrgency, isTrue);
    await unmount(tester);
  });
}
