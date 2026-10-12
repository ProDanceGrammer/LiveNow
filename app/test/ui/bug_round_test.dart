import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart' show CupertinoDatePicker;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/budget_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/screens/settings_screen.dart';
import 'package:livenow/ui/sync_providers.dart';
import 'package:livenow/ui/theme_mode.dart';
import 'package:livenow/ui/widgets/action_budget_section.dart';
import 'package:livenow/ui/widgets/quick_time_edit_dialog.dart';

/// Tests for the 11.10.2026 bug round: Settings page, linking an existing
/// transaction to an action, the phone's time wheel.
void main() {
  setUpAll(initPostponeTimeZoneData);

  Future<void> pump(
    WidgetTester tester,
    AppDatabase db,
    Widget home, {
    Size size = const Size(1400, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          syncRoleProvider.overrideWithValue(SyncRole.client),
        ],
        child: MaterialApp(home: home),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) async {
    resetStackedDialogsForTest();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('Settings lists every import, and the theme switch works', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await pump(tester, db, const SettingsScreen());

    for (final key in [
      'settings-import-actions',
      'settings-import-templates',
      'settings-import-growth',
      'settings-import-growth-icons',
      'settings-import-budget',
      'settings-import-budget-icons',
      'settings-export-budget-json',
      'settings-export-budget-csv',
    ]) {
      await tester.scrollUntilVisible(
        find.byKey(ValueKey(key)),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
    }
    // The list was scrolled to the bottom: the theme switch is built lazily, so
    // scroll back up to it.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-theme')),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    );
    await tester.tap(find.text('Dark'), warnIfMissed: false);
    await tester.pump();
    expect(container.read(themeModeProvider), ThemeMode.dark);
    await unmount(tester);
  });

  testWidgets('Add transaction offers unlinked ones and links the chosen', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final actionId = await ActionService(db).createAction(name: 'Shopping');
    final budget = BudgetService(db);
    final cat = await budget.saveCategory(
      const CategoryInput(name: 'Groceries', price: 25),
    );
    final free = await budget.createTransaction(categoryId: cat);
    final taken = await budget.createTransaction(
      categoryId: cat,
      actionId: actionId,
    );
    await pump(
      tester,
      db,
      Scaffold(body: ActionBudgetSection(actionId: actionId)),
    );
    await tester.tap(
      find.byKey(const ValueKey('action-add-budget-transaction')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // "Create new" is pinned on top; only the unlinked transaction is listed.
    expect(find.byKey(const ValueKey('tx-pick-new')), findsOneWidget);
    expect(find.byKey(ValueKey('tx-pick-$free')), findsOneWidget);
    expect(find.byKey(ValueKey('tx-pick-$taken')), findsNothing);

    await tester.tap(find.byKey(ValueKey('tx-pick-$free')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final row = (await tester.runAsync(
      () => (db.select(
        db.budgetTransactionsTable,
      )..where((t) => t.id.equals(free))).getSingle(),
    ))!;
    expect(row.actionId, actionId);
    await unmount(tester);
  });

  testWidgets('on a phone the time dialog is a wheel that saves', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    TimeEditResult? got;
    await pump(
      tester,
      db,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async => got = await QuickTimeEditDialog.pick(
            context,
            start: DateTime.utc(2026, 10, 12, 6),
            end: DateTime.utc(2026, 10, 12, 7),
          ),
          child: const Text('open'),
        ),
      ),
      size: const Size(375, 812),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CupertinoDatePicker), findsOneWidget);
    expect(find.byKey(const ValueKey('time-chip-end')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('time-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(got?.start, DateTime.utc(2026, 10, 12, 6));
    expect(got?.end, DateTime.utc(2026, 10, 12, 7));
    await unmount(tester);
  });
}
