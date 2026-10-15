import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:livenow/core/ids.dart';
import 'package:livenow/core/time_codec.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/budget_service.dart';
import 'package:livenow/domain/plan_rules.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/plan_providers.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/screens/budget_screen.dart';
import 'package:livenow/ui/views/calendar_view.dart';

/// The plan item editor (template name, switch, duplicate, Previous / Next /
/// transactions) and the transaction templates panel in Budget > Transactions.
void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;

  Future<void> settle(WidgetTester tester, [int ms = 300]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    resetStackedDialogsForTest();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<String> template(WidgetTester tester, String name) async =>
      (await tester.runAsync(() async {
        final id = newId();
        await db
            .into(db.actionTemplatesTable)
            .insert(
              ActionTemplatesTableCompanion.insert(
                id: id,
                name: name,
                payload: jsonEncode({'name': name}),
              ),
            );
        return id;
      }))!;

  Future<void> openEditor(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('calendar-planning-toggle')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('plan-bar-add')));
    await settle(tester);
  }

  late String catId;

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
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
        name: 'Cash',
        currency: 'EUR',
        rateToBase: 1,
      );
      catId = await b.saveCategory(
        CategoryInput(name: 'Groceries', price: 600, accountCountId: acc),
      );
    });
  }

  Future<void> pumpCalendar(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          calendarVisibleHoursProvider.overrideWith((ref) => 24),
        ],
        child: const MaterialApp(home: Scaffold(body: CalendarView())),
      ),
    );
    await settle(tester);
  }

  Future<void> pickTemplate(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(const ValueKey('plan-template')));
    await settle(tester, 200);
    await tester.tap(find.text(name).last);
    await settle(tester, 200);
  }

  String nameText(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const ValueKey('plan-name')))
      .controller!
      .text;

  testWidgets('a template fills the name; the button re-applies it', (
    tester,
  ) async {
    await mount(tester);
    await template(tester, 'Swim');
    await template(tester, 'Run');
    await pumpCalendar(tester);
    await openEditor(tester);

    await pickTemplate(tester, 'Swim');
    expect(nameText(tester), 'Swim');
    expect(find.byKey(const ValueKey('plan-name-from-template')), findsNothing);

    // The name still follows the template while it equals the old one.
    await pickTemplate(tester, 'Run');
    expect(nameText(tester), 'Run');

    // A name typed by hand is kept; the button offers the template's name.
    await tester.enterText(find.byKey(const ValueKey('plan-name')), 'Morning');
    await tester.pump();
    await pickTemplate(tester, 'Swim');
    expect(nameText(tester), 'Morning');
    await tester.tap(find.byKey(const ValueKey('plan-name-from-template')));
    await tester.pump();
    expect(nameText(tester), 'Swim');
    await unmount(tester);
  });

  testWidgets('only the switch toggles "forever"; a time row duplicates', (
    tester,
  ) async {
    await mount(tester);
    await pumpCalendar(tester);
    await openEditor(tester);

    await tester.tap(find.text('Keep creating actions (forever)'));
    await tester.pump();
    expect(
      tester.widget<Switch>(find.byKey(const ValueKey('plan-forever'))).value,
      isFalse,
    );
    await tester.tap(find.byKey(const ValueKey('plan-forever')));
    await tester.pump();
    expect(
      tester.widget<Switch>(find.byKey(const ValueKey('plan-forever'))).value,
      isTrue,
    );

    expect(find.byKey(const ValueKey('plan-row-day-1')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('plan-row-duplicate-0')));
    await tester.pump();
    expect(find.byKey(const ValueKey('plan-row-day-1')), findsOneWidget);
    // The labels are written out, not truncated hints.
    expect(find.text('Minutes'), findsWidgets);
    expect(find.text('Own name'), findsWidgets);
    await unmount(tester);
  });

  testWidgets('Previous / Next and a transaction save with the time row', (
    tester,
  ) async {
    await mount(tester);
    final tx = (await tester.runAsync(
      () => BudgetService(db).saveTxTemplate(
        name: 'Groceries',
        categoryId: catId,
        unitPrice: 600,
      ),
    ))!;
    await pumpCalendar(tester);
    await openEditor(tester);

    await tester.enterText(find.byKey(const ValueKey('plan-name')), 'Bazaar');
    await tester.tap(find.byKey(const ValueKey('row-0-extras-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('row-0-add-prev')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('row-0-prev-0-name')),
      'Get ready',
    );
    await tester.tap(find.byKey(const ValueKey('row-0-add-next')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('row-0-next-0-name')),
      'Unpack',
    );
    await tester.enterText(
      find.byKey(const ValueKey('row-0-next-0-gap')),
      '10',
    );
    await tester.tap(find.byKey(const ValueKey('row-0-tx-add')));
    await settle(tester, 200);
    await tester.tap(find.byKey(ValueKey('txt-pick-$tx')));
    await settle(tester, 200);
    expect(find.widgetWithText(InputChip, 'Groceries'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('plan-save')));
    await settle(tester);

    final row = (await tester.runAsync(
      () => db.select(db.planItemsTable).getSingle(),
    ))!;
    final occ = CycleRule.fromJson(
      Map<String, Object?>.from(jsonDecode(row.rule) as Map),
    ).occurrences.single;
    expect(occ.extras.prev.single.name, 'Get ready');
    expect(occ.extras.next.single.name, 'Unpack');
    expect(occ.extras.next.single.gapMinutes, 10);
    expect(occ.extras.txTemplateIds, [tx]);
    await unmount(tester);
  });

  testWidgets('Transactions: the templates button shows the list', (
    tester,
  ) async {
    await mount(tester);
    final tx = (await tester.runAsync(
      () => BudgetService(db).saveTxTemplate(
        name: 'Market',
        categoryId: catId,
        quantity: 2,
        unitPrice: 50,
      ),
    ))!;
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

    expect(find.byKey(const ValueKey('tx-templates-panel')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('tx-templates-toggle')));
    await settle(tester);
    expect(find.byKey(const ValueKey('tx-templates-panel')), findsOneWidget);
    expect(find.text('Market'), findsOneWidget);
    expect(find.textContaining('Groceries · 2 × 50'), findsOneWidget);

    // "Create a transaction now" makes a real one.
    await tester.tap(find.byKey(ValueKey('tx-template-use-$tx')));
    await settle(tester);
    final txs = (await tester.runAsync(
      () => db.select(db.budgetTransactionsTable).get(),
    ))!;
    expect(txs.single.name, 'Market');
    expect(txs.single.quantity, 2);

    // Delete, then Undo brings it back.
    await tester.tap(find.byKey(ValueKey('tx-template-delete-$tx')));
    await settle(tester);
    expect(find.byKey(ValueKey('tx-template-$tx')), findsNothing);
    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(find.byKey(ValueKey('tx-template-$tx')), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('the editor fits a 375 px phone with every section open', (
    tester,
  ) async {
    await mount(tester);
    tester.view.physicalSize = const Size(375, 812);
    await pumpCalendar(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CalendarView)),
    );
    container.read(calendarPlanningProvider.notifier).state = true;
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('plan-bar-add')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('row-0-extras-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('row-0-add-prev')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('row-0-add-next')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('plan-row-duplicate-0')));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('the Minutes field shows the average and how yours differs', (
    tester,
  ) async {
    await mount(tester);
    await template(tester, 'Swim');
    // Two finished 45-minute runs of "Swim" in the last days.
    await tester.runAsync(() async {
      final now = DateTime.now().toUtc();
      for (var d = 1; d <= 2; d++) {
        final start = now.subtract(Duration(days: d, hours: 1));
        final id = await ActionService(db).createAction(
          name: 'Swim',
          startAt: start,
          endAt: start.add(const Duration(minutes: 45)),
        );
        await (db.update(db.actionsTable)..where((t) => t.id.equals(id))).write(
          ActionsTableCompanion(
            done: const Value(true),
            completedAt: Value(dateTimeToDb(now)!),
          ),
        );
      }
    });
    await pumpCalendar(tester);
    await openEditor(tester);

    // No average until the item is named / a template is chosen.
    expect(find.byKey(const ValueKey('plan-row-avg-0')), findsNothing);
    await pickTemplate(tester, 'Swim');
    await settle(tester);
    Text note() => tester.widget<Text>(find.byKey(const ValueKey('plan-row-avg-0')));
    expect(note().data, 'Average of finished runs: 45 min');

    await tester.enterText(find.byKey(const ValueKey('plan-row-duration-0')), '30');
    await tester.pump();
    expect(note().data, contains('yours is 15 min shorter'));
    await tester.enterText(find.byKey(const ValueKey('plan-row-duration-0')), '45');
    await tester.pump();
    expect(note().data, 'Average of finished runs: 45 min');
    await tester.enterText(find.byKey(const ValueKey('plan-row-duration-0')), '60');
    await tester.pump();
    expect(note().data, contains('yours is 15 min longer'));
    await unmount(tester);
  });
}
