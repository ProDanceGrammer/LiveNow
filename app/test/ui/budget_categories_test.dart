import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/budget_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/budget_providers.dart';
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/screens/budget_screen.dart';
import 'package:livenow/ui/widgets/budget_categories_board.dart';

/// The Categories board: a tree with collapsible groups, sort levels (Plan /
/// Fact by size), a Flat switch, a search that keeps the parents, and rows that
/// only rebuild when their own numbers change.
void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late ProviderContainer container;
  late String food, milk, bread, rent, misc;

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
      final acc = await b.saveAccount(
        name: 'Euro',
        currency: 'EUR',
        rateToBase: 1,
      );
      Future<String> cat(String name, double price, double units, [String? p]) =>
          b.saveCategory(
            CategoryInput(
              name: name,
              price: price,
              unitsPerMonth: units,
              accountCountId: acc,
              parentId: p,
            ),
          );
      food = await b.saveCategory(
        CategoryInput(name: 'Food', accountCountId: acc),
      );
      milk = await cat('Milk', 10, 3, food); // 30 / month
      bread = await cat('Bread', 5, 2, food); // 10 / month
      rent = await cat('Rent', 500, 1); // 500 / month
      misc = await cat('Misc', 5, 1); // 5 / month
      // Facts: Milk is overspent (45 > 30).
      await b.createTransaction(
        categoryId: milk,
        quantity: 4,
        unitPrice: 10,
        date: DateTime.now().toUtc().subtract(const Duration(days: 3)),
      );
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: BudgetScreen()),
      ),
    );
    container = ProviderScope.containerOf(
      tester.element(find.byType(BudgetScreen)),
    );
    await settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('budget-switch')),
        matching: find.text('Categories'),
      ),
    );
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    resetStackedDialogsForTest();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Finder row(String id) => find.byKey(ValueKey('budget-category-$id'));
  double top(WidgetTester tester, String id) =>
      tester.getTopLeft(row(id)).dy;

  /// The category ids from top to bottom as drawn.
  List<String> order(WidgetTester tester, List<String> ids) =>
      ([...ids]..sort((a, b) => top(tester, a).compareTo(top(tester, b))));

  testWidgets('a tree by name: groups with indented children', (tester) async {
    await pump(tester);
    expect(order(tester, [food, milk, bread, rent, misc]), [
      food,
      bread,
      milk,
      misc,
      rent,
    ]);
    // Children are indented under their group.
    expect(
      tester.getTopLeft(find.text('Milk')).dx,
      greaterThan(tester.getTopLeft(find.text('Food')).dx),
    );
    // The entered fields became one grey line under the name.
    expect(find.textContaining('10 × 3 per month'), findsOneWidget);
    // ... followed by the account to count in.
    expect(find.textContaining('Euro'), findsWidgets);
    await unmount(tester);
  });

  testWidgets('a chevron folds and unfolds a group', (tester) async {
    await pump(tester);
    expect(find.text('Milk'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('budget-cat-toggle-$food')));
    await settle(tester);
    expect(find.text('Milk'), findsNothing);
    expect(find.text('Bread'), findsNothing);
    expect(find.text('Food'), findsOneWidget); // its totals stay in view
    await tester.tap(find.byKey(ValueKey('budget-cat-toggle-$food')));
    await settle(tester);
    expect(find.text('Milk'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('sort by Plan puts the biggest first inside every level', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('cat-sort-add')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Plan').last);
    await settle(tester);
    // Name stays the first level, so the order is unchanged until it is removed.
    final nameChip = find.byKey(const ValueKey('cat-sort-chip-name'));
    await tester.tap(
      find.descendant(
        of: nameChip,
        matching: find.byWidgetPredicate(
          (w) =>
              w is Icon &&
              (w.icon == Icons.cancel ||
                  w.icon == Icons.clear ||
                  w.icon == Icons.close),
        ),
      ),
    );
    await settle(tester);
    // Top level by size: Rent 500, Food 40, Misc 5; inside Food: Milk 30, Bread 10.
    expect(order(tester, [food, milk, bread, rent, misc]), [
      rent,
      food,
      milk,
      bread,
      misc,
    ]);
    await unmount(tester);
  });

  testWidgets('Flat lists only the categories that hold transactions', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('cat-flat')));
    await settle(tester);
    expect(row(food), findsNothing); // the group is gone
    expect(row(milk), findsOneWidget);
    expect(row(rent), findsOneWidget);
    // No indentation any more.
    expect(
      tester.getTopLeft(find.text('Milk')).dx,
      tester.getTopLeft(find.text('Rent')).dx,
    );
    await unmount(tester);
  });

  testWidgets('search keeps the parent of a match', (tester) async {
    await pump(tester);
    await tester.enterText(
      find.byKey(const ValueKey('budget-categories-search')),
      'milk',
    );
    await settle(tester, 600);
    expect(row(food), findsOneWidget);
    expect(row(milk), findsOneWidget);
    expect(row(rent), findsNothing);
    expect(row(bread), findsNothing);
    await unmount(tester);
  });

  testWidgets('no three-dots menu; the dialog deletes with an Undo', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byKey(ValueKey('budget-category-menu-$rent')), findsNothing);
    await tester.tap(row(rent));
    await settle(tester);
    expect(find.byKey(const ValueKey('category-delete')), findsOneWidget);
    // The transactions panel sits beside the settings on a wide window.
    expect(find.textContaining('Transactions ('), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('category-delete')));
    await settle(tester);
    expect(row(rent), findsNothing);
    expect(find.text('Undo'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(row(rent), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await unmount(tester);
  });

  testWidgets('the list is clipped so tinted rows cannot bleed over the header', (
    tester,
  ) async {
    await pump(tester);
    expect(
      find.ancestor(of: find.byType(ListView), matching: find.byType(ClipRect)),
      findsWidgets,
    );
    await unmount(tester);
  });

  testWidgets('a category dialog lists its transactions with the sums', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(row(milk));
    await settle(tester);
    expect(find.textContaining('Transactions (1)'), findsOneWidget);
    // 4 x 10 EUR expense, counted in the main currency too.
    expect(find.textContaining('40.00'), findsWidgets);
    await unmount(tester);
  });

  testWidgets('the parent picker shows price x units and can create a category', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(row(rent));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('category-parent-add')));
    await settle(tester);
    expect(find.byKey(const ValueKey('pick-category-new')), findsOneWidget);
    expect(find.textContaining('10 × 3 per month'), findsWidgets);
    await unmount(tester);
  });

  testWidgets('an unchanged snapshot rebuilds no row; one change rebuilds one', (
    tester,
  ) async {
    await pump(tester);
    CategoryPerfCounters.reset();
    // The whole budget is recomputed (as every minute and on any write) ...
    container.invalidate(budgetViewProvider);
    await settle(tester);
    // ... but nothing a row shows changed.
    expect(CategoryPerfCounters.rowBuilds, 0);

    // Renaming one category rebuilds (about) that row only.
    CategoryPerfCounters.reset();
    await tester.runAsync(() async {
      final c = await (db.select(db.budgetCategoriesTable)
            ..where((t) => t.id.equals(rent))).getSingle();
      await BudgetService(db).saveCategory(
        CategoryInput(
          id: c.id,
          name: 'Rent and bills',
          price: c.price,
          unitsPerMonth: c.unitsPerMonth,
          accountCountId: c.accountCountId,
        ),
      );
    });
    await settle(tester);
    expect(CategoryPerfCounters.rowBuilds, inInclusiveRange(1, 2));
    expect(find.text('Rent and bills'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('phone width: no sideways scrolling, nothing overflows', (
    tester,
  ) async {
    await pump(tester, size: const Size(375, 800));
    expect(row(rent), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BudgetCategoriesBoard),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
    await unmount(tester);
  });

  testWidgets('a row stays light: few elements per line', (tester) async {
    await pump(tester);
    var count = 0;
    void walk(Element e) {
      count++;
      e.visitChildren(walk);
    }

    row(rent).evaluate().single.visitChildren(walk);
    // The old 13-column row (13 cells x SizedBox/Align/Padding/Text + two
    // IconButtons with tooltips) built roughly twice this; the guard keeps the
    // new row from growing back.
    expect(count, lessThan(130), reason: 'elements in one row: $count');
    await unmount(tester);
  });
}
