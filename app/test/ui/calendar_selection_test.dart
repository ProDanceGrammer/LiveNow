import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/time_codec.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/calendar_selection.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/views/calendar_layout.dart';
import 'package:livenow/ui/views/calendar_view.dart';

/// Multi-selection of calendar events: Shift+click, dragging a group
/// together (also while Shift+scroll moves the range), Delete / Escape.
void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late ProviderContainer container;

  DateTime at(int hour, [int minute = 0, int days = 0]) =>
      DateTime.fromMillisecondsSinceEpoch(
        localDayStart(DateTime.now().toUtc()).millisecondsSinceEpoch +
            Duration(days: days, hours: hour, minutes: minute).inMilliseconds,
        isUtc: true,
      );

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys = ON;'),
      ),
    );
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

  Future<void> useDays(WidgetTester tester, int n) async {
    await tester.tap(find.byTooltip('$n days'));
    await settle(tester);
  }

  Future<(DateTime?, DateTime?)> times(WidgetTester tester, String id) async {
    final r = (await tester.runAsync(
      () => (db.select(
        db.actionsTable,
      )..where((t) => t.id.equals(id))).getSingle(),
    ))!;
    return (dateTimeFromDb(r.startAt), dateTimeFromDb(r.endAt));
  }

  Future<void> release(WidgetTester tester, TestGesture g) async {
    await tester.runAsync(() async {
      await g.up();
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> clickWithShift(WidgetTester tester, Finder target) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(target);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Set<String> selection() => container.read(calendarSelectionProvider);

  testWidgets('Shift+click builds a selection across days, a plain click '
      'resets it, a click on empty space clears it', (tester) async {
    await pump(tester);
    final a = await create(tester, 'A', at(9), at(10));
    final b = await create(tester, 'B', at(11, 0, 1), at(12, 0, 1));
    final c = await create(tester, 'C', at(13), at(14));
    await useDays(tester, 3);
    Finder block(String id) => find.byKey(ValueKey('event-$id'));

    await tester.tap(block(a));
    await tester.pump(const Duration(milliseconds: 400));
    expect(selection(), {a});
    expect(container.read(calendarSelectedActionProvider), a);

    await clickWithShift(tester, block(b));
    expect(selection(), {a, b});
    expect(container.read(calendarSelectedActionProvider), b);

    await clickWithShift(tester, block(c));
    expect(selection(), {a, b, c});

    // Shift+click on a selected one removes it.
    await clickWithShift(tester, block(b));
    expect(selection(), {a, c});
    expect(container.read(calendarSelectedActionProvider), c);

    // A plain click selects only that event.
    await tester.tap(block(b));
    await tester.pump(const Duration(milliseconds: 400));
    expect(selection(), {b});
    expect(container.read(calendarSelectedActionProvider), b);

    // Empty space clears.
    await tester.tapAt(
      tester.getTopRight(block(c)) + const Offset(-4, 300),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(selection(), isEmpty);
    expect(container.read(calendarSelectedActionProvider), isNull);
    await unmount(tester);
  });

  testWidgets('dragging one of three selected events moves all three by the '
      'same delta; one Undo restores them', (tester) async {
    await pump(tester);
    final a = await create(tester, 'A', at(9), at(10));
    final b = await create(tester, 'B', at(12), at(12, 30));
    final c = await create(tester, 'C', at(14, 0, 1), at(15, 0, 1));
    final loose = await create(tester, 'Loose', at(16), at(17));
    await useDays(tester, 3);
    final before = {
      for (final id in [a, b, c, loose]) id: await times(tester, id),
    };
    container.read(calendarSelectionProvider.notifier).state = {a, b, c};
    await tester.pump();

    final dayW = (1400 - 56) / 3;
    final block = find.byKey(ValueKey('event-$b'));
    final g = await tester.startGesture(
      tester.getTopLeft(block) + const Offset(30, 10),
      kind: PointerDeviceKind.mouse,
    );
    await g.moveBy(const Offset(0, 1));
    await tester.pump();
    // +20 minutes and one day (the sideways part is a little over a column).
    await g.moveBy(Offset(dayW + 10, 20 * pxPerMinute(tester) - 1));
    await tester.pump();
    // A ghost for each moved event, none for the unselected one.
    expect(find.byKey(const ValueKey('drag-ghost')), findsOneWidget);
    expect(find.byKey(ValueKey('drag-ghost-$a')), findsOneWidget);
    expect(find.byKey(ValueKey('drag-ghost-$c')), findsOneWidget);
    expect(find.byKey(ValueKey('drag-ghost-$loose')), findsNothing);
    await release(tester, g);

    const day = Duration(days: 1);
    const m20 = Duration(minutes: 20);
    for (final id in [a, b, c]) {
      final (s0, e0) = before[id]!;
      final (s1, e1) = await times(tester, id);
      expect(s1, s0!.add(day).add(m20), reason: 'start of $id');
      expect(e1, e0!.add(day).add(m20), reason: 'end of $id');
    }
    expect(await times(tester, loose), before[loose]);
    expect(selection(), {a, b, c});
    expect(find.text('Moved 3 events'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Undo'));
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    for (final id in [a, b, c, loose]) {
      expect(await times(tester, id), before[id], reason: 'undo of $id');
    }
    await tester.pump(const Duration(seconds: 1));
    await unmount(tester);
  });

  testWidgets('pressing an unselected event drags it alone and selects only '
      'it', (tester) async {
    await pump(tester);
    final a = await create(tester, 'A', at(9), at(10));
    final b = await create(tester, 'B', at(12), at(13));
    await useDays(tester, 3);
    container.read(calendarSelectionProvider.notifier).state = {a};
    await tester.pump();

    final g = await tester.startGesture(
      tester.getTopLeft(find.byKey(ValueKey('event-$b'))) +
          const Offset(30, 10),
      kind: PointerDeviceKind.mouse,
    );
    await g.moveBy(const Offset(0, 1));
    await tester.pump();
    await g.moveBy(Offset(0, 30 * pxPerMinute(tester) - 1));
    await tester.pump();
    await release(tester, g);

    expect((await times(tester, a)).$1, at(9));
    expect((await times(tester, b)).$1, at(12, 30));
    expect(selection(), {b});
    await tester.pump(const Duration(seconds: 1));
    await unmount(tester);
  });

  testWidgets('a plain press on a selected event keeps the group for a drag '
      'but collapses to it on a plain click', (tester) async {
    await pump(tester);
    final a = await create(tester, 'A', at(9), at(10));
    final b = await create(tester, 'B', at(12), at(13));
    await useDays(tester, 3);
    container.read(calendarSelectionProvider.notifier).state = {a, b};
    await tester.pump();

    await tester.tap(find.byKey(ValueKey('event-$b')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(selection(), {b});
    await unmount(tester);
  });

  testWidgets('Shift+scroll during a drag moves the range and the group lands '
      'on the new day', (tester) async {
    await pump(tester);
    final a = await create(tester, 'A', at(9), at(10));
    final b = await create(tester, 'B', at(12), at(13));
    await useDays(tester, 3);
    final before = {
      for (final id in [a, b]) id: await times(tester, id),
    };
    container.read(calendarSelectionProvider.notifier).state = {a, b};
    await tester.pump();
    final start0 = container.read(calendarRangeStartProvider);
    final col0 = tester.getTopLeft(find.byKey(const ValueKey('day-header-0')));

    final g = await tester.startGesture(
      tester.getTopLeft(find.byKey(ValueKey('event-$a'))) +
          const Offset(30, 10),
    );
    await g.moveBy(const Offset(0, 1));
    await tester.pump();
    await g.moveBy(Offset(0, 60 * pxPerMinute(tester) - 1));
    await tester.pump();
    expect(find.byKey(const ValueKey('drag-ghost')), findsOneWidget);

    // Two days forward with the wheel, Shift held.
    final wheel = TestPointer(7, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(wheel.hover(const Offset(700, 800)));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendEventToBinding(wheel.scroll(const Offset(0, 100)));
    await tester.sendEventToBinding(wheel.scroll(const Offset(0, 100)));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      container.read(calendarRangeStartProvider),
      calendarAddDays(start0, 2),
    );
    // The drag survived: both ghosts are up, still in the pointer's column.
    expect(find.byKey(const ValueKey('drag-ghost')), findsOneWidget);
    expect(find.byKey(ValueKey('drag-ghost-$b')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('drag-ghost'))).dx,
      moreOrLessEquals(col0.dx, epsilon: 1),
    );
    // Dimmed source blocks do not matter; the selection was not cleared.
    expect(selection(), {a, b});

    await release(tester, g);
    const m60 = Duration(minutes: 60);
    for (final id in [a, b]) {
      final (s0, e0) = before[id]!;
      final (s1, e1) = await times(tester, id);
      expect(s1, s0!.add(const Duration(days: 2)).add(m60), reason: id);
      expect(e1, e0!.add(const Duration(days: 2)).add(m60), reason: id);
    }
    await tester.pump(const Duration(seconds: 1));
    await unmount(tester);
  });

  testWidgets('Delete removes every selected event, one Undo brings them '
      'back with their dependency edges', (tester) async {
    await pump(tester);
    final a = await create(tester, 'A', at(9), at(10));
    final b = await create(tester, 'B', at(11), at(12));
    final c = await create(tester, 'C', at(13), at(14));
    await tester.runAsync(() async {
      final deps = container.read(dependencyServiceProvider);
      await deps.addDependency(predecessorId: a, successorId: b);
      await deps.addDependency(predecessorId: b, successorId: c);
    });
    await useDays(tester, 3);

    await tester.tap(find.byKey(ValueKey('event-$a')));
    await tester.pump(const Duration(milliseconds: 400));
    await clickWithShift(tester, find.byKey(ValueKey('event-$b')));
    expect(selection(), {a, b});

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Deleted 2 actions'), findsOneWidget);
    expect(selection(), isEmpty);
    Future<int> count(WidgetTester t) async => (await t.runAsync(
      () async => (await db.select(db.actionsTable).get()).length,
    ))!;
    Future<int> edges(WidgetTester t) async => (await t.runAsync(
      () async => (await db.select(db.actionDependenciesTable).get()).length,
    ))!;
    expect(await count(tester), 1);
    expect(await edges(tester), 0);

    await tester.runAsync(() async {
      await tester.tap(find.text('Undo'));
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    expect(await count(tester), 3);
    expect(await edges(tester), 2);
    await tester.pump(const Duration(seconds: 1));
    await unmount(tester);
  });

  testWidgets('the toolbar trash deletes the whole selection when the hovered '
      'event is part of it', (tester) async {
    await pump(tester);
    final a = await create(tester, 'A', at(9), at(10));
    final b = await create(tester, 'B', at(11), at(12));
    final c = await create(tester, 'C', at(13), at(14));
    await useDays(tester, 3);
    container.read(calendarSelectionProvider.notifier).state = {a, b};
    await tester.pump();

    final m = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await m.addPointer(location: const Offset(1, 1));
    addTearDown(m.removePointer);
    await m.moveTo(tester.getCenter(find.byKey(ValueKey('event-$a'))));
    await tester.pump();
    await tester.tap(find.byTooltip('Delete'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump(const Duration(milliseconds: 400));
    final left = (await tester.runAsync(
      () async =>
          (await db.select(db.actionsTable).get()).map((r) => r.id).toList(),
    ))!;
    expect(left, [c]);
    await tester.pump(const Duration(seconds: 1));
    await unmount(tester);
  });

  testWidgets(
    'Escape clears the selection, Ctrl+A selects everything in view',
    (tester) async {
      await pump(tester);
      final a = await create(tester, 'A', at(9), at(10));
      final b = await create(tester, 'B', at(11, 0, 1), at(12, 0, 1));
      await useDays(tester, 3);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(selection(), {a, b});

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(selection(), isEmpty);
      expect(container.read(calendarSelectedActionProvider), isNull);
      await unmount(tester);
    },
  );

  testWidgets('Shift+drag on empty grid space draws a rubber band and adds '
      'the events it touches to the selection', (tester) async {
    await pump(tester);
    final a = await create(tester, 'A', at(9), at(10));
    final b = await create(tester, 'B', at(11, 0, 1), at(12, 0, 1));
    final c = await create(tester, 'C', at(13), at(14));
    final d = await create(tester, 'D', at(16), at(17));
    await useDays(tester, 3);
    container.read(calendarSelectionProvider.notifier).state = {b};
    await tester.pump();

    final ppm = pxPerMinute(tester);
    final topA = tester.getTopLeft(find.byKey(ValueKey('event-$a')));
    final x = topA.dx + 20;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    final g = await tester.startGesture(
      Offset(x, topA.dy - 60 * ppm),
      kind: PointerDeviceKind.mouse,
    );
    await g.moveBy(const Offset(0, 1));
    await tester.pump();
    // From 08:00 to 13:30: touches A and C, not D (16:00) and not B (day 2).
    await g.moveTo(Offset(x + 30, topA.dy + 270 * ppm));
    await tester.pump();
    expect(find.byKey(const ValueKey('marquee')), findsOneWidget);
    expect(find.byKey(const ValueKey('create-preview')), findsNothing);
    await g.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const ValueKey('marquee')), findsNothing);
    expect(find.text('New action'), findsNothing);
    expect(selection(), {a, b, c});
    expect(selection().contains(d), isFalse);
    await unmount(tester);
  });

  testWidgets('a Shift+click on empty space keeps the selection', (
    tester,
  ) async {
    await pump(tester);
    final a = await create(tester, 'A', at(9), at(10));
    await useDays(tester, 3);
    container.read(calendarSelectionProvider.notifier).state = {a};
    await tester.pump();
    final p = tester.getTopLeft(find.byKey(ValueKey('event-$a')));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tapAt(
      Offset(p.dx + 20, p.dy + 300),
      kind: PointerDeviceKind.mouse,
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump(const Duration(milliseconds: 400));
    expect(selection(), {a});
    await unmount(tester);
  });

  testWidgets('Shift+drag across the all-day strip selects the chips it '
      'touches', (tester) async {
    await pump(tester);
    final h1 = (await tester.runAsync(
      () => container
          .read(actionServiceProvider)
          .createAction(name: 'H1', startAt: at(0), isAllDay: true),
    ))!;
    final timed = await create(tester, 'T', at(9), at(10));
    await useDays(tester, 3);
    final chip = find.byKey(ValueKey('allday-$h1'));
    expect(chip, findsOneWidget);
    final r = tester.getRect(chip);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    // Start on empty strip space (day 3's column), sweep left over the chip.
    final g = await tester.startGesture(
      Offset(r.right + r.width + 20, r.center.dy),
      kind: PointerDeviceKind.mouse,
    );
    await g.moveBy(const Offset(-10, 0));
    await tester.pump();
    await g.moveTo(r.center);
    await tester.pump();
    expect(find.byKey(const ValueKey('marquee-allday')), findsOneWidget);
    await g.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump(const Duration(milliseconds: 400));
    expect(selection(), {h1});
    expect(selection().contains(timed), isFalse);
    await unmount(tester);
  });

  testWidgets('moving to other days clears the selection', (tester) async {
    await pump(tester);
    final a = await create(tester, 'A', at(9), at(10));
    await useDays(tester, 3);
    await tester.tap(find.byKey(ValueKey('event-$a')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(selection(), {a});
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(selection(), isEmpty);
    await unmount(tester);
  });

  testWidgets('dragging a selected group onto the all-day strip makes all of '
      'them all-day with one Undo', (tester) async {
    await pump(tester);
    final a = await create(tester, 'A', at(9), at(10));
    final b = await create(tester, 'B', at(13), at(14));
    await useDays(tester, 3);
    container.read(calendarSelectionProvider.notifier).state = {a, b};
    await tester.pump();

    final g = await tester.startGesture(
      tester.getCenter(find.byKey(ValueKey('event-$a'))),
      kind: PointerDeviceKind.mouse,
    );
    await g.moveBy(const Offset(0, -8));
    await tester.pump();
    await g.moveTo(
      tester.getCenter(find.byKey(const ValueKey('strip-cell-1'))),
    );
    await tester.pump();
    await release(tester, g);
    await settle(tester);

    for (final id in [a, b]) {
      final r = (await tester.runAsync(
        () => (db.select(
          db.actionsTable,
        )..where((t) => t.id.equals(id))).getSingle(),
      ))!;
      expect(r.isAllDay, isTrue, reason: id);
      expect(dateTimeFromDb(r.startAt), at(0, 0, 1));
      expect(r.endAt, isNull);
    }

    await tester.runAsync(() async {
      await tester.tap(find.text('Undo'));
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    expect(await times(tester, a), (at(9), at(10)));
    expect(await times(tester, b), (at(13), at(14)));
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await unmount(tester);
  });

  testWidgets('dragging an all-day chip across the strip rebuilds no blocks', (
    tester,
  ) async {
    await pump(tester);
    final h = (await tester.runAsync(
      () => container
          .read(actionServiceProvider)
          .createAction(name: 'H', startAt: at(0), isAllDay: true),
    ))!;
    await create(tester, 'A', at(9), at(10));
    await useDays(tester, 3);

    final from = tester.getCenter(find.byKey(ValueKey('allday-$h')));
    final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
    await g.moveBy(const Offset(0, 8));
    await tester.pump();
    CalendarPerfCounters.reset();
    for (final i in [1, 2, 1]) {
      await g.moveTo(
        tester.getCenter(find.byKey(ValueKey('strip-cell-$i'))) +
            const Offset(30, 0),
      );
      await tester.pump();
    }
    expect(find.byKey(const ValueKey('chip-ghost')), findsNothing);
    expect(CalendarPerfCounters.blockBuilds, 0);
    expect(CalendarPerfCounters.layoutRuns, 0);
    // Back on its own cell: nothing is written.
    await g.moveTo(
      tester.getCenter(find.byKey(const ValueKey('strip-cell-0'))) +
          const Offset(30, 0),
    );
    await release(tester, g);
    expect(find.text('Undo'), findsNothing);
    await unmount(tester);
  });

  testWidgets('dragging an all-day chip over the grid rebuilds no blocks', (
    tester,
  ) async {
    await pump(tester);
    final h = (await tester.runAsync(
      () => container
          .read(actionServiceProvider)
          .createAction(name: 'H', startAt: at(0), isAllDay: true),
    ))!;
    await create(tester, 'A', at(9), at(10));
    await create(tester, 'B', at(13), at(14));
    await useDays(tester, 3);

    final from = tester.getCenter(find.byKey(ValueKey('allday-$h')));
    final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
    await g.moveBy(const Offset(0, 8));
    await tester.pump();
    CalendarPerfCounters.reset();
    for (var i = 1; i <= 5; i++) {
      await g.moveTo(Offset(300 + i * 40, 500 + i * 10));
      await tester.pump();
    }
    expect(find.byKey(const ValueKey('chip-ghost')), findsOneWidget);
    expect(CalendarPerfCounters.blockBuilds, 0);
    expect(CalendarPerfCounters.layoutRuns, 0);
    await g.moveTo(const Offset(20, 500)); // drop outside the day columns
    await release(tester, g);
    await unmount(tester);
  });
}
