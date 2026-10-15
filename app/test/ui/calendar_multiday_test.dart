import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  Future<void> pump(WidgetTester tester, {double height = 1700}) async {
    tester.view.physicalSize = Size(1400, height);
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
    // Opaque: the events behind it must not show through.
    final bar = tester.widget<Material>(
      find.byKey(const ValueKey('calendar-bulk-bar')),
    );
    expect(bar.color!.a, 1.0);

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

  testWidgets('a block that started yesterday can be pulled up (it never turns all-day)', (
    tester,
  ) async {
    await pump(tester);
    // Yesterday 20:00 -> today 04:00: today shows its second slice at the very
    // top of the grid, right under the all-day strip.
    final id = await create(tester, 'Night', at(-4), at(4));
    await useDays(tester, 3);
    final ppm = pxPerMinute(tester);
    const up = 35.0; // px: the pointer ends inside the all-day strip
    await dragBy(
      tester,
      find.byKey(ValueKey('event-$id-d0')), // today's slice (a continuation)
      const Offset(30, 10),
      const Offset(0, -up),
    );
    final r = await row(tester, id);
    expect(r.isAllDay, isFalse);
    final minutes = (up / ppm / 10).round() * 10;
    expect(dateTimeFromDb(r.startAt), at(-4).subtract(Duration(minutes: minutes)));
    expect(dateTimeFromDb(r.endAt), at(4).subtract(Duration(minutes: minutes)));
    await unmount(tester);
  });

  testWidgets('the magnet locks a dragged block onto the edge of another one '
      '(Alt = grid only)', (tester) async {
    await pump(tester);
    final a = await create(tester, 'First', at(10), at(11));
    await create(tester, 'Second', at(12, 5), at(13)); // off the 10-min grid
    await useDays(tester, 3);
    // 61 min down: the grid alone would end at 12:00, the magnet at 12:05.
    await dragBy(
      tester,
      find.byKey(ValueKey('event-$a')),
      const Offset(30, 10),
      Offset(0, 61 * pxPerMinute(tester)),
    );
    var r = await row(tester, a);
    expect(dateTimeFromDb(r.startAt), at(11, 5));
    expect(dateTimeFromDb(r.endAt), at(12, 5));

    // With Alt held the magnet is off: plain 10-minute steps.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await dragBy(
      tester,
      find.byKey(ValueKey('event-$a')),
      const Offset(30, 10),
      Offset(0, -61 * pxPerMinute(tester)),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    r = await row(tester, a);
    expect(dateTimeFromDb(r.startAt), at(10, 5));
    await unmount(tester);
  });

  testWidgets('the snap guide shows while the block is locked', (tester) async {
    await pump(tester);
    final a = await create(tester, 'First', at(10), at(11));
    await create(tester, 'Second', at(12, 5), at(13));
    await useDays(tester, 3);
    final g = await tester.startGesture(
      tester.getTopLeft(find.byKey(ValueKey('event-$a'))) + const Offset(30, 10),
      kind: PointerDeviceKind.mouse,
    );
    await g.moveBy(const Offset(0, 1));
    await tester.pump();
    await g.moveBy(Offset(0, 61 * pxPerMinute(tester)));
    await tester.pump();
    expect(find.byKey(const ValueKey('snap-guide')), findsOneWidget);
    await g.up();
    await tester.pump();
    await settle(tester);
    await unmount(tester);
  });

  testWidgets('the magnet catches EVERY neighbour edge, whatever the minutes', (
    tester,
  ) async {
    // A tall window: ~4.7 px per minute with the whole day visible, so the
    // magnet reaches only ~1.7 minutes - the case the old lattice-first code
    // got wrong for every edge more than 2 minutes off the 10-minute grid.
    await pump(tester, height: 7000);
    final mover = await create(tester, 'Mover', at(8), at(8, 30));
    // Durations 25/35/45/55 and starts off the 10-minute grid: the lattice of
    // the dragged block never lands within reach of these edges by itself.
    final cases = <(DateTime, DateTime)>[
      (at(11), at(11, 25)),
      (at(13, 7), at(13, 42)),
      (at(15), at(15, 45)),
      (at(17, 3), at(17, 58)),
    ];
    for (final c in cases) {
      await create(tester, 'N${c.$1.hour}', c.$1, c.$2);
    }
    await useDays(tester, 3);
    final ppm = pxPerMinute(tester);
    Future<ActionRow> dragTo(DateTime wantedStart, double extraPx) async {
      final cur = dateTimeFromDb((await row(tester, mover)).startAt)!;
      await dragBy(
        tester,
        find.byKey(ValueKey('event-$mover')),
        const Offset(30, 15),
        Offset(0, wantedStart.difference(cur).inMinutes * ppm + extraPx),
      );
      return row(tester, mover);
    }

    for (final c in cases) {
      // Below it: the start lands exactly on the neighbour's end.
      var r = await dragTo(c.$2, 2);
      expect(dateTimeFromDb(r.startAt), c.$2, reason: 'after ${c.$1}');
      expect(
        dateTimeFromDb(r.endAt),
        c.$2.add(const Duration(minutes: 30)),
      );
      // Above it: the end lands exactly on the neighbour's start.
      r = await dragTo(c.$1.subtract(const Duration(minutes: 30)), -2);
      expect(
        dateTimeFromDb(r.endAt),
        c.$1,
        reason: 'before ${c.$1}',
      );
    }
    await unmount(tester);
  });

  testWidgets('a block grabbed next to the border does not turn the page', (
    tester,
  ) async {
    await pump(tester);
    final id = await create(tester, 'Walk', at(10), at(11));
    await tester.tap(find.byTooltip('1 day'));
    await settle(tester);
    final before = container.read(calendarRangeStartProvider);
    final block = find.byKey(ValueKey('event-$id'));
    // The only column spans the whole width: grab 6 px from its right border.
    final g = await tester.startGesture(
      tester.getTopRight(block) + const Offset(-6, 10),
      kind: PointerDeviceKind.mouse,
    );
    await g.moveBy(const Offset(0, 1));
    await tester.pump();
    await g.moveBy(const Offset(0, 20));
    await tester.pump(const Duration(milliseconds: 1500));
    expect(container.read(calendarRangeStartProvider), before);
    await g.up();
    await tester.pump();
    await settle(tester);
    await unmount(tester);
  });
}
