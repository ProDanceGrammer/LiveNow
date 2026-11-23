import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/budget_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/screens/budget_screen.dart';

// Bug 2026-11-23 (img_2): on a phone the "Total" card seemed to cover the
// first group header of the Transactions list.
void main() {
  setUpAll(initPostponeTimeZoneData);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('phone: the first group header lies fully below the Total card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys = ON;'),
      ),
    );
    addTearDown(db.close);
    await tester.runAsync(() async {
      final b = BudgetService(db);
      final eur = await b.saveAccount(
        name: 'Euro',
        currency: 'EUR',
        rateToBase: 1,
        openingBalance: 80,
      );
      await b.saveAccount(
        name: 'Lira',
        currency: 'TRY',
        rateToBase: 40,
        openingBalance: 4000,
      );
      final cat = await b.saveCategory(
        CategoryInput(name: 'Food', price: 5, accountCountId: eur),
      );
      for (final name in ['Shopping', 'Cinema', 'Rent']) {
        final action = await ActionService(db).createAction(name: name);
        for (var i = 0; i < 3; i++) {
          await b.createTransaction(
            categoryId: cat,
            actionId: action,
            name: '$name $i',
            quantity: 1,
            unitPrice: 10.0 + i,
          );
        }
      }
      await b.createTransaction(
        categoryId: cat,
        name: 'Lira thing',
        quantity: 1,
        unitPrice: 3,
      );
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: BudgetScreen()),
      ),
    );
    await settle(tester);
    final tab = find.descendant(
      of: find.byKey(const ValueKey('budget-switch')),
      matching: find.text('Transactions'),
    );
    await tester.ensureVisible(tab);
    await tester.pump();
    await tester.tap(tab);
    await settle(tester);

    final totals = find.byKey(const ValueKey('tx-totals'));
    expect(totals, findsOneWidget);
    // The card around the block ends 10 px (its padding) below the block.
    final cardBottom = tester.getRect(totals).bottom + 10;
    final headers = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('tx-group-header-'),
    );
    expect(headers, findsWidgets);
    final first = tester.getRect(headers.first);
    expect(first.top, greaterThanOrEqualTo(cardBottom));
    // Its title is the first thing in the header and is on screen.
    expect(
      find.descendant(of: headers.first, matching: find.textContaining('(')),
      findsWidgets,
    );

    // The card is the list's first row: scrolled, it leaves WITH the headers
    // instead of cutting them off under a fixed card.
    await tester.drag(find.byType(ListView).last, const Offset(0, -60));
    await tester.pump();
    final card2 = tester.getRect(totals).bottom + 10;
    expect(tester.getRect(headers.first).top, greaterThanOrEqualTo(card2));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
