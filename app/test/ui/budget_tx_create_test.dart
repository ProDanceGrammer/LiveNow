import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/budget_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/screens/budget_screen.dart';

/// The transaction dialog can create a new category and a new action on the spot.
void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  Future<void> openNewTransaction(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys = ON;'),
      ),
    );
    addTearDown(db.close);
    // Seed BEFORE mounting: writing while Drift streams are live deadlocks.
    await tester.runAsync(
      () => BudgetService(
        db,
      ).saveAccount(name: 'Euro', currency: 'EUR', rateToBase: 1),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: BudgetScreen()),
      ),
    );
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('budget-fab')));
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    resetStackedDialogsForTest();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  String field(WidgetTester tester, String key) => tester
      .widget<TextFormField>(find.byKey(ValueKey(key)))
      .controller!
      .text;

  Future<void> createCategory(WidgetTester tester, {double? price}) async {
    await tester.tap(find.byKey(const ValueKey('tx-category')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('pick-category-new')));
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('category-name')), 'Tea');
    if (price != null) {
      await tester.enterText(
        find.byKey(const ValueKey('category-price')),
        '$price',
      );
    }
    await tester.ensureVisible(find.byKey(const ValueKey('category-save')));
    await tester.tap(find.byKey(const ValueKey('category-save')));
    await settle(tester);
  }

  testWidgets('a new category is created, selected and fills an empty price', (
    tester,
  ) async {
    await openNewTransaction(tester);
    await createCategory(tester, price: 4);

    expect(field(tester, 'tx-price'), '4');
    final cats = (await tester.runAsync(
      () => db.select(db.budgetCategoriesTable).get(),
    ))!;
    expect(cats.map((c) => c.name), ['Tea']);
    // The category is chosen: the dialog saves.
    await tester.tap(find.byKey(const ValueKey('tx-save')));
    await settle(tester);
    final txs = (await tester.runAsync(
      () => db.select(db.budgetTransactionsTable).get(),
    ))!;
    expect(txs.single.categoryId, cats.single.id);
    await unmount(tester);
  });

  testWidgets('a created category does not overwrite a typed price', (
    tester,
  ) async {
    await openNewTransaction(tester);
    await tester.enterText(find.byKey(const ValueKey('tx-price')), '9');
    await createCategory(tester, price: 4);

    expect(field(tester, 'tx-price'), '9');
    await unmount(tester);
  });

  testWidgets('a new action is created from the dialog and linked', (
    tester,
  ) async {
    await openNewTransaction(tester);
    await tester.tap(find.byKey(const ValueKey('tx-change-action')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('pick-new-action')));
    await settle(tester);

    final editor = find.byKey(const ValueKey('action-editor-dialog'));
    expect(editor, findsOneWidget);
    await tester.enterText(
      find.descendant(of: editor, matching: find.byType(TextFormField)).first,
      'Tea break',
    );
    await tester.tap(find.descendant(of: editor, matching: find.text('Save')));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);

    expect(editor, findsNothing);
    expect(find.byKey(const ValueKey('tx-open-action')), findsOneWidget);
    expect(find.text('Tea break'), findsWidgets);
    final actions = (await tester.runAsync(
      () => db.select(db.actionsTable).get(),
    ))!;
    expect(actions.map((a) => a.name), ['Tea break']);
    await unmount(tester);
  });
}
