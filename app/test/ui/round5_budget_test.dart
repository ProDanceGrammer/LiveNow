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
import 'package:livenow/ui/widgets/budget_dialogs.dart';

/// Round 5: the Plan/Fact boards skip ended categories and fold same-name price
/// variants ("Leaves only"); "Part of" is a searchable picker.
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

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    required Future<void> Function() seed,
  }) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys = ON;'),
      ),
    );
    addTearDown(db.close);
    await tester.runAsync(seed);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(home: home),
      ),
    );
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    resetStackedDialogsForTest();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('an ended category leaves the boards but stays in the totals', (
    tester,
  ) async {
    await pump(
      tester,
      const BudgetScreen(),
      seed: () async {
        final b = BudgetService(db);
        final acc = await b.saveAccount(
          name: 'Euro',
          currency: 'EUR',
          rateToBase: 1,
        );
        await b.saveCategory(
          CategoryInput(
            name: 'Still running',
            price: 10,
            unitsPerMonth: 1,
            accountCountId: acc,
          ),
        );
        final gone = await b.saveCategory(
          CategoryInput(
            name: 'Finished two weeks ago',
            price: 50,
            unitsPerMonth: 1,
            accountCountId: acc,
            endDate: DateTime.now().toUtc().subtract(const Duration(days: 14)),
          ),
        );
        await b.createTransaction(
          categoryId: gone,
          quantity: 2,
          date: DateTime.now().toUtc().subtract(const Duration(days: 20)),
        );
      },
    );
    expect(find.text('Still running'), findsOneWidget);
    expect(find.text('Finished two weeks ago'), findsNothing);
    // The money it moved still counts in the fact total (2 x 50).
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('budget-fact-total')),
        matching: find.textContaining('100.00'),
      ),
      findsOneWidget,
    );
    await unmount(tester);
  });

  testWidgets('Leaves only folds same-name price variants into the parent', (
    tester,
  ) async {
    await pump(
      tester,
      const BudgetScreen(),
      seed: () async {
        final b = BudgetService(db);
        final acc = await b.saveAccount(
          name: 'Euro',
          currency: 'EUR',
          rateToBase: 1,
        );
        Future<String> leaf(String name, String? parent, double price) =>
            b.saveCategory(
              CategoryInput(
                name: name,
                parentId: parent,
                price: price,
                unitsPerMonth: 1,
                accountCountId: acc,
              ),
            );
        final bread = await b.saveCategory(const CategoryInput(name: 'Bread'));
        await leaf('Bread', bread, 10);
        await leaf('Bread', bread, 12);
        final veg = await b.saveCategory(
          const CategoryInput(name: 'Vegetables'),
        );
        await leaf('Potatoes', veg, 3);
        await leaf('Potatoes', veg, 4);
      },
    );
    await tester.tap(find.byKey(const ValueKey('budget-leaves-only')));
    await settle(tester);

    // One 'Bread' line (the parent), but the two Potatoes stay separate.
    expect(find.text('Bread'), findsOneWidget);
    expect(find.text('Potatoes'), findsNWidgets(2));
    expect(find.text('Vegetables'), findsNothing);
    await unmount(tester);
  });

  testWidgets('Part of opens a searchable list without itself or its children', (
    tester,
  ) async {
    late BudgetCategory alpha;
    await pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => BudgetCategoryDialog.show(context, existing: alpha),
          child: const Text('open'),
        ),
      ),
      seed: () async {
        final b = BudgetService(db);
        final a = await b.saveCategory(const CategoryInput(name: 'Alpha'));
        await b.saveCategory(CategoryInput(name: 'Alpha child', parentId: a));
        await b.saveCategory(const CategoryInput(name: 'Beta'));
        await b.saveCategory(const CategoryInput(name: 'Gamma'));
        alpha = await (db.select(
          db.budgetCategoriesTable,
        )..where((t) => t.id.equals(a))).getSingle();
      },
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const ValueKey('category-parent')));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 400));

    // Searchable, with "top level" pinned; the category and its child are absent.
    expect(find.byKey(const ValueKey('budget-category-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('pick-category-none')), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Gamma'), findsOneWidget);
    // (The dialog's own name field also says "Alpha": look at list rows only.)
    expect(find.widgetWithText(ListTile, 'Alpha child'), findsNothing);
    expect(find.widgetWithText(ListTile, 'Alpha'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('budget-category-search')),
      'gam',
    );
    await tester.pump();
    expect(find.text('Gamma'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);

    await tester.tap(find.text('Gamma'));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 400));
    // The field now names the chosen parent.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('category-parent')),
        matching: find.text('Gamma'),
      ),
      findsOneWidget,
    );
    await unmount(tester);
  });
}
