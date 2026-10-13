import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/local_time.dart';
import 'package:livenow/core/time_codec.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/calendar_selection.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/views/calendar_view.dart';

/// Dragging actions that go through midnight (a sleep 23:00 -> 07:00): they
/// move up/down freely, any day-slice carries the whole action, the ghost shows
/// every slice, and holding a dragged block at the edge turns the page.
void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late ProviderContainer container;

  DateTime at(int hour, [int minute = 0]) =>
      DateTime.fromMillisecondsSinceEpoch(
        localDayStart(DateTime.now().toUtc()).millisecondsSinceEpoch +
            Duration(hours: hour, minutes: minute).inMilliseconds,
        isUtc: true,
      );

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          calendarVisibleHoursProvider.overrideWith((ref) => 24),
        ],
        child: const MaterialApp(home: Scaffold(body: CalendarView())),
      ),
    );
    container = ProviderScope.containerOf(
      tester.element(find.byType(CalendarView)),
    );
  }

  double pxPerMinute(WidgetTester tester) =>
      (tester.getTopLeft(find.text('14:00')).dy -
          tester.getTopLeft(find.text('13:00')).dy) /
      60;

  Future<String> create(
    WidgetTester tester,
    String name,
    DateTime start,
    DateTime end,
  ) async => (await tester.runAsync(
    () => container
        .read(actionServiceProvider)
        .createAction(name: name, startAt: start, endAt: end),
  ))!;

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<ActionRow> row(WidgetTester tester, String id) async =>
      (await tester.runAsync(
        () => (db.select(
          db.actionsTable,
        )..where((t) => t.id.equals(id))).getSingle(),
      ))!;

  Future<void> useDays(WidgetTester tester, int n) async {
    await tester.tap(find.byTooltip('$n days'));
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> dragBy(
    WidgetTester tester,
    Finder block,
    Offset localFrom,
    Offset delta,
  ) async {
    final g = await tester.startGesture(
      tester.getTopLeft(block) + localFrom,
      kind: PointerDeviceKind.mouse,
    );
    await g.moveBy(const Offset(0, 1));
    await tester.pump();
    await g.moveBy(delta);
    await tester.pump();
    await g.up();
    await tester.pump();
    await settle(tester);
  }

  testWidgets('a sleep across midnight can be dragged up and down', (
    tester,
  ) async {
    await pump(tester);
    final id = await create(tester, 'Sleep', at(23), at(31)); // 23:00 -> 07:00
    await useDays(tester, 3);
    await dragBy(
      tester,
      find.byKey(ValueKey('event-$id')),
      const Offset(30, 10),
      Offset(0, -41 * pxPerMinute(tester)), // 40 min earlier (10 min snap)
    );
    var r = await row(tester, id);
    expect(dateTimeFromDb(r.startAt), at(22, 20));
    expect(dateTimeFromDb(r.endAt), at(30, 20));

    // And later: its end lands later on the next day, the length is kept.
    await dragBy(
      tester,
      find.byKey(ValueKey('event-$id')),
      const Offset(30, 10),
      Offset(0, 61 * pxPerMinute(tester)),
    );
    r = await row(tester, id);
    expect(dateTimeFromDb(r.startAt), at(23, 20));
    expect(dateTimeFromDb(r.endAt), at(31, 20));
    await unmount(tester);
  });

  testWidgets('grabbing the continuation slice moves the whole action', (
    tester,
  ) async {
    await pump(tester);
    final id = await create(tester, 'Sleep', at(23), at(31));
    await useDays(tester, 3);
    final dayW = (1400 - 56) / 3;
    // The slice on the next day has its own key.
    await dragBy(
      tester,
      find.byKey(ValueKey('event-$id-d1')),
      const Offset(30, 10),
      Offset(dayW + 10, 0),
    );
    final r = await row(tester, id);
    expect(dateTimeFromDb(r.startAt), at(23).add(const Duration(days: 1)));
    expect(dateTimeFromDb(r.endAt), at(31).add(const Duration(days: 1)));
    await unmount(tester);
  });

  testWidgets('the ghost shows a piece on every day it crosses', (
    tester,
  ) async {
    await pump(tester);
    final id = await create(tester, 'Sleep', at(23), at(31));
    await useDays(tester, 3);
    final block = find.byKey(ValueKey('event-$id'));
    final g = await tester.startGesture(
      tester.getTopLeft(block) + const Offset(30, 10),
      kind: PointerDeviceKind.mouse,
    );
    await g.moveBy(Offset(0, -20 * pxPerMinute(tester)));
    await tester.pump();
    expect(find.byKey(const ValueKey('drag-ghost')), findsOneWidget);
    expect(find.byKey(const ValueKey('drag-ghost-d1')), findsOneWidget);
    await g.up();
    await settle(tester);
    await unmount(tester);
  });

  testWidgets('a group: the sleep moves freely, the short block keeps its day', (
    tester,
  ) async {
    await pump(tester);
    final sleep = await create(tester, 'Sleep', at(23), at(31));
    final short = await create(tester, 'Short', at(10), at(11));
    await useDays(tester, 3);
    container.read(calendarSelectionProvider.notifier).state = {sleep, short};
    await tester.pump();
    await dragBy(
      tester,
      find.byKey(ValueKey('event-$sleep')),
      const Offset(30, 10),
      Offset(0, 61 * pxPerMinute(tester)),
    );
    final s = await row(tester, sleep);
    final b = await row(tester, short);
    expect(dateTimeFromDb(s.startAt), at(23, 60));
    expect(dateTimeFromDb(b.startAt), at(11));
    expect(dateTimeFromDb(b.endAt), at(12));
    await unmount(tester);
  });

  testWidgets('holding a dragged block at the right edge turns the page', (
    tester,
  ) async {
    await pump(tester);
    final id = await create(tester, 'Walk', at(10), at(11));
    await useDays(tester, 3);
    final before = container.read(calendarRangeStartProvider);
    final block = find.byKey(ValueKey('event-$id'));
    final g = await tester.startGesture(
      tester.getTopLeft(block) + const Offset(30, 10),
      kind: PointerDeviceKind.mouse,
    );
    await g.moveBy(const Offset(0, 1));
    await tester.pump();
    await g.moveTo(const Offset(1396, 300)); // inside the right edge zone
    await tester.pump();
    expect(container.read(calendarRangeStartProvider), before);
    await tester.pump(const Duration(milliseconds: 650));
    final turned = container.read(calendarRangeStartProvider);
    expect(turned.difference(before), const Duration(days: 1));
    await tester.pump(const Duration(milliseconds: 650));
    expect(
      container.read(calendarRangeStartProvider).difference(before),
      const Duration(days: 2),
    );
    // Leaving the edge stops the turning.
    await g.moveTo(const Offset(700, 300));
    await tester.pump(const Duration(milliseconds: 1300));
    expect(
      container.read(calendarRangeStartProvider).difference(before),
      const Duration(days: 2),
    );
    await g.cancel();
    await tester.pump();
    await unmount(tester);
  });

  testWidgets('the bulk bar shifts the selected events by the same amount', (
    tester,
  ) async {
    await pump(tester);
    final a = await create(tester, 'Alpha', at(9), at(10));
    final b = await create(tester, 'Beta', at(13), at(14));
    final c = await create(tester, 'Gamma', at(16), at(17));
    await useDays(tester, 3);
    expect(find.byKey(const ValueKey('calendar-bulk-bar')), findsNothing);

    container.read(calendarSelectionProvider.notifier).state = {a, b};
    await tester.pump();
    expect(find.byKey(const ValueKey('calendar-bulk-bar')), findsOneWidget);
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cal-bulk-shift')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('shift-apply'))); // +1 day
    await settle(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();

    final day = const Duration(days: 1);
    expect(dateTimeFromDb((await row(tester, a)).startAt), at(9).add(day));
    expect(dateTimeFromDb((await row(tester, b)).startAt), at(13).add(day));
    expect(dateTimeFromDb((await row(tester, c)).startAt), at(16)); // untouched
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cal-bulk-clear')));
    await tester.pump();
    expect(find.byKey(const ValueKey('calendar-bulk-bar')), findsNothing);
    await tester.pump(const Duration(seconds: 6));
    await unmount(tester);
  });
}
