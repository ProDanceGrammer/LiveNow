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
import 'package:livenow/ui/urgency_colors.dart';

/// Budget rows take the colour of the URGENCY of their related action:
/// the scale when it has growth directions, WHITE when it has none, plain
/// glass when there is no action. A transaction also shows the urgency icon +
/// number on its action line.
void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late String linkedAction, unlinkedAction, catLinked, catUnlinked, catPlain;
  late String txLinked, txUnlinked, txPlain;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1400, 1000),
    bool showUrgency = true,
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
      // Urgency colours and numbers are off by default (Budget settings).
      await b.saveSettings(BudgetSettings(showUrgency: showUrgency));
      final acc = await b.saveAccount(
        name: 'Euro',
        currency: 'EUR',
        rateToBase: 1,
      );
      Future<String> category(String name) => b.saveCategory(
        CategoryInput(name: name, price: 5, accountCountId: acc),
      );
      catLinked = await category('Linked cat');
      catUnlinked = await category('Unlinked cat');
      catPlain = await category('Plain cat');
      final actions = ActionService(db);
      linkedAction = await actions.createAction(name: 'Planned');
      unlinkedAction = await actions.createAction(name: 'No direction');
      final soon = DateTime.now().toUtc().add(const Duration(days: 2));
      txLinked = await b.createTransaction(
        categoryId: catLinked,
        actionId: linkedAction,
        date: soon,
        name: 'Tx linked',
      );
      txUnlinked = await b.createTransaction(
        categoryId: catUnlinked,
        actionId: unlinkedAction,
        date: soon,
        name: 'Tx unlinked',
      );
      txPlain = await b.createTransaction(
        categoryId: catPlain,
        date: soon,
        name: 'Tx plain',
      );
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          actionUrgencyProvider.overrideWith((ref) => {linkedAction: 450.0}),
          actionsWithDirectionsProvider.overrideWith((ref) => {linkedAction}),
        ],
        child: const MaterialApp(home: BudgetScreen()),
      ),
    );
    await settle(tester);
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('budget-switch')),
        matching: find.text(label),
      ),
    );
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    resetStackedDialogsForTest();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// Is the widget with [key] drawn on a box filled with [color]?
  bool tinted(WidgetTester tester, String key, Color color) {
    return find
        .ancestor(
          of: find.byKey(ValueKey(key)),
          matching: find.byWidgetPredicate((w) {
            final d = w is DecoratedBox
                ? w.decoration
                : w is Ink
                ? w.decoration
                : null;
            return d is BoxDecoration && d.color == color;
          }),
        )
        .evaluate()
        .isNotEmpty;
  }

  final scale = urgencyColors(450, dark: false).bg;
  final white = emptyColors(dark: false).bg;

  testWidgets('transactions: scale colour + urgency number, white, plain', (
    tester,
  ) async {
    await pump(tester);
    await openTab(tester, 'Transactions');

    expect(tinted(tester, 'budget-tx-$txLinked', scale), isTrue);
    expect(
      find.descendant(
        of: find.byKey(ValueKey('budget-tx-urgency-$txLinked')),
        matching: find.text('450'),
      ),
      findsOneWidget,
    );

    // The action has no direction: white, and no urgency to show.
    expect(tinted(tester, 'budget-tx-$txUnlinked', white), isTrue);
    expect(find.byKey(ValueKey('budget-tx-urgency-$txUnlinked')), findsNothing);

    // No action at all: plain glass.
    expect(tinted(tester, 'budget-tx-$txPlain', scale), isFalse);
    expect(tinted(tester, 'budget-tx-$txPlain', white), isFalse);
    expect(find.byKey(ValueKey('budget-tx-urgency-$txPlain')), findsNothing);
    await unmount(tester);
  });

  testWidgets('categories (table): tinted by their upcoming action', (
    tester,
  ) async {
    await pump(tester);
    await openTab(tester, 'Categories');
    expect(tinted(tester, 'budget-category-$catLinked', scale), isTrue);
    expect(tinted(tester, 'budget-category-$catUnlinked', white), isTrue);
    expect(tinted(tester, 'budget-category-$catPlain', scale), isFalse);
    expect(tinted(tester, 'budget-category-$catPlain', white), isFalse);
    await unmount(tester);
  });

  testWidgets('hidden by default: no colour, no urgency number', (tester) async {
    await pump(tester, showUrgency: false);
    await openTab(tester, 'Transactions');
    expect(tinted(tester, 'budget-tx-$txLinked', scale), isFalse);
    expect(tinted(tester, 'budget-tx-$txUnlinked', white), isFalse);
    expect(find.byKey(ValueKey('budget-tx-urgency-$txLinked')), findsNothing);
    await openTab(tester, 'Categories');
    expect(tinted(tester, 'budget-category-$catLinked', scale), isFalse);
    expect(tinted(tester, 'budget-category-$catUnlinked', white), isFalse);
    await unmount(tester);
  });

  testWidgets('categories (phone cards): tinted the same way', (tester) async {
    await pump(tester, size: const Size(375, 900));
    await openTab(tester, 'Categories');
    expect(tinted(tester, 'budget-category-$catLinked', scale), isTrue);
    expect(tinted(tester, 'budget-category-$catUnlinked', white), isTrue);
    expect(tinted(tester, 'budget-category-$catPlain', scale), isFalse);
    await unmount(tester);
  });
}
