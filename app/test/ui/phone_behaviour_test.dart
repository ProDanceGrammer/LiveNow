import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/growth_rules.dart';
import 'package:livenow/domain/metric_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/main.dart';
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/sync_providers.dart';

/// Phone behaviour (375 x 812): the board switch, swipe and long-press on
/// cards, the 1-3 day calendar, one-finger pan on the mindmap.
void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late String openId;

  Future<void> pumpPhone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final actions = ActionService(db);
    final metrics = MetricService(db);
    final root = await metrics.saveMetric(
      name: 'Root',
      kind: MetricKind.boolean,
      isMain: true,
    );
    await metrics.saveMetric(
      name: 'Leaf',
      kind: MetricKind.count,
      window: MetricWindow.week,
      target: 3,
      leadsToIds: [root],
    );
    final now = DateTime.now();
    openId = await actions.createAction(
      name: 'Open one',
      startAt: now.subtract(const Duration(minutes: 10)),
      endAt: now.add(const Duration(hours: 2)),
    );
    await actions.createAction(
      name: 'Finished one',
      startAt: now.subtract(const Duration(hours: 5)),
      endAt: now.subtract(const Duration(hours: 4)),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          syncRoleProvider.overrideWithValue(SyncRole.client),
        ],
        child: const LiveNowApp(),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> settle(WidgetTester tester, [int ms = 600]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    resetStackedDialogsForTest();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('the board shows one column at a time, switchable', (
    tester,
  ) async {
    await pumpPhone(tester);
    expect(find.text('Open one'), findsOneWidget);
    expect(find.text('Finished one'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('board-switch-done')));
    await settle(tester, 300);
    expect(find.text('Finished one'), findsOneWidget);
    expect(find.text('Open one'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('board-switch-notdone')));
    await settle(tester, 300);
    expect(find.text('Open one'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('swipe right always finishes the action, with an Undo toast', (
    tester,
  ) async {
    await pumpPhone(tester);
    await tester.drag(find.text('Open one'), const Offset(300, 0));
    await settle(tester);
    final occurrences = (await tester.runAsync(
      () => db.select(db.actionOccurrencesTable).get(),
    ))!;
    expect(occurrences, hasLength(1));
    expect(occurrences.single.actionId, openId);
    expect(occurrences.single.outcome, 'done'); // Finish, not Start
    final row = (await tester.runAsync(
      () => (db.select(db.actionsTable)..where((t) => t.id.equals(openId)))
          .getSingle(),
    ))!;
    expect(row.done, isTrue);
    expect(find.text('Undo'), findsOneWidget);
    await settle(tester, 6000); // let the toast go
    await unmount(tester);
  });

  testWidgets('swipe left deletes the action (undoable)', (tester) async {
    await pumpPhone(tester);
    await tester.drag(find.text('Open one'), const Offset(-300, 0));
    await settle(tester);
    final left = (await tester.runAsync(
      () => db.select(db.actionsTable).get(),
    ))!;
    expect(left.map((a) => a.name), ['Finished one']);
    expect(find.text('Undo'), findsOneWidget);
    await settle(tester, 6000);
    await unmount(tester);
  });

  testWidgets('long-press selects, a tap adds, the bar deletes', (
    tester,
  ) async {
    await pumpPhone(tester);
    await tester.longPress(find.text('Open one'));
    await settle(tester, 300);
    // The long-press opens the action list; its "Select" row starts a
    // multi-selection.
    expect(find.byKey(const ValueKey('quick-action-select')), findsOneWidget);
    expect(find.text('Finish'), findsOneWidget);
    expect(find.text('Continue with same action'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('quick-action-select')));
    await settle(tester, 300);
    expect(find.byKey(const ValueKey('phone-selection-bar')), findsOneWidget);
    expect(find.text('1 selected'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('phone-selection-delete')));
    await settle(tester);
    final left = (await tester.runAsync(
      () => db.select(db.actionsTable).get(),
    ))!;
    expect(left.map((a) => a.name), ['Finished one']);
    expect(find.byKey(const ValueKey('phone-selection-bar')), findsNothing);
    await settle(tester, 6000);
    await unmount(tester);
  });

  testWidgets('the calendar starts on one day; the menu offers 1 to 3', (
    tester,
  ) async {
    await pumpPhone(tester);
    await tester.tap(find.text('Calendar'));
    await settle(tester, 300);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
    );
    expect(container.read(calendarDayCountProvider), 1);
    expect(find.byKey(const ValueKey('day-header-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('day-header-1')), findsNothing);
    // The day count is chosen in the floating menu (no segmented button on a
    // phone): 1, 2, 3 only while upright.
    expect(find.byType(SegmentedButton<int>), findsNothing);
    await tester.tap(find.byKey(const ValueKey('calendar-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calendar-menu-days-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-menu-days-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-menu-days-3')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-menu-days-4')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('calendar-menu-days-3')));
    await settle(tester, 300);
    expect(container.read(calendarDayCountProvider), 3);
    expect(find.byKey(const ValueKey('day-header-2')), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a long-press on empty calendar space starts a new action', (
    tester,
  ) async {
    await pumpPhone(tester);
    await tester.tap(find.text('Calendar'));
    await settle(tester, 300);
    expect(find.text('New action'), findsNothing);
    // The grid is scrolled to "now - 1 h": the very top of it is empty.
    final grid = find.byType(SingleChildScrollView).last;
    await tester.longPressAt(tester.getTopLeft(grid) + const Offset(200, 20));
    await settle(tester, 400);
    expect(find.text('New action'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('dragging empty calendar space scrolls instead of sweeping', (
    tester,
  ) async {
    await pumpPhone(tester);
    await tester.tap(find.text('Calendar'));
    await settle(tester, 300);
    final grid = find.byType(SingleChildScrollView).last;
    await tester.dragFrom(
      tester.getTopLeft(grid) + const Offset(200, 200),
      const Offset(0, -120),
    );
    await settle(tester, 300);
    expect(find.text('New action'), findsNothing); // no dialog from a drag
    await unmount(tester);
  });
}
