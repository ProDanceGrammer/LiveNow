import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/calendar_selection.dart';
import 'package:livenow/ui/plan_providers.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/views/calendar_layout.dart';
import 'package:livenow/ui/views/calendar_view.dart';

import 'calendar_stress_fixture.dart';

/// The calendar under load: a 7-day week with ~100 overlapping actions per day,
/// plus ~100 plan ghosts per day, 100 events starting the same minute, 100
/// all-day items, and a phone window that rotates. Seeded through the real DB
/// path (`watchCalendarWeek`), BEFORE mounting.
void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late ProviderContainer container;

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<Duration> mount(
    WidgetTester tester, {
    Size size = const Size(1400, 1000),
    int hours = 24,
    Future<void> Function(AppDatabase db)? seed,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    if (seed != null) await tester.runAsync(() => seed(db));
    final sw = Stopwatch()..start();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          calendarVisibleHoursProvider.overrideWith((ref) => hours),
        ],
        child: const MaterialApp(home: Scaffold(body: CalendarView())),
      ),
    );
    container = ProviderScope.containerOf(
      tester.element(find.byType(CalendarView)),
    );
    await settle(tester);
    sw.stop();
    return sw.elapsed;
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  bool isEvent(Widget w) {
    final k = w.key;
    return k is ValueKey<String> && k.value.startsWith('event-');
  }

  /// Every built event block has a real, visible size.
  void expectBlocksSane(WidgetTester tester, {double minW = 1}) {
    final els = find.byWidgetPredicate(isEvent).evaluate().toList();
    for (final e in els) {
      final box = e.renderObject! as RenderBox;
      expect(
        box.size.width,
        greaterThanOrEqualTo(minW),
        reason: '${e.widget.key} width ${box.size.width}',
      );
      expect(
        box.size.height,
        greaterThan(0),
        reason: '${e.widget.key} height ${box.size.height}',
      );
    }
  }

  ScrollPosition gridPosition(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(CalendarView),
              matching: find.byType(Scrollable),
            )
            .last,
      )
      .position;

  Finder ghosts() => find.byWidgetPredicate((w) {
    final k = w.key;
    return k is ValueKey<String> &&
        k.value.startsWith('plan-ghost-') &&
        !k.value.startsWith('plan-ghost-handle-');
  });

  testWidgets('7 days x 100 overlapping actions: builds, scrolls, selects', (
    tester,
  ) async {
    CalendarPerfCounters.reset();
    final elapsed = await mount(tester, seed: (d) => seedBusyWeek(d));
    // ignore: avoid_print
    print(
      'STRESS busy week: ${elapsed.inMilliseconds} ms, '
      'blockBuilds=${CalendarPerfCounters.blockBuilds}, '
      'layoutRuns=${CalendarPerfCounters.layoutRuns}',
    );
    expect(elapsed.inSeconds, lessThan(40));
    expect(tester.takeException(), isNull);
    expect(find.byWidgetPredicate(isEvent), findsWidgets);
    expectBlocksSane(tester);

    final pos = gridPosition(tester);
    pos.jumpTo(0);
    await tester.pump(const Duration(milliseconds: 200));
    CalendarPerfCounters.reset();
    for (var i = 1; i <= 10; i++) {
      pos.jumpTo(pos.maxScrollExtent * i / 10);
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expectBlocksSane(tester);
    // Scrolling only builds blocks newly entering the viewport.
    // ignore: avoid_print
    print('STRESS scroll blockBuilds=${CalendarPerfCounters.blockBuilds}');
    expect(CalendarPerfCounters.blockBuilds, lessThan(700 * 2));
    expect(CalendarPerfCounters.layoutRuns, 0);

    final one = find.byWidgetPredicate(isEvent).evaluate().first.widget.key!
        as ValueKey<String>;
    final id = one.value.substring('event-'.length).split('-d').first;
    CalendarPerfCounters.reset();
    container.read(calendarSelectionProvider.notifier).state = {id};
    await tester.pump();
    expect(CalendarPerfCounters.blockBuilds, lessThanOrEqualTo(8));
    expect(CalendarPerfCounters.layoutRuns, 0);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('plus ~100 plan ghosts a day in planning mode', (tester) async {
    final elapsed = await mount(
      tester,
      seed: (d) async {
        await seedBusyWeek(d);
        await seedPlanGhosts(d);
      },
    );
    container.read(calendarPlanningProvider.notifier).state = true;
    await settle(tester);
    final sw = Stopwatch()..start();
    await tester.pump(const Duration(milliseconds: 100));
    sw.stop();
    // ignore: avoid_print
    print(
      'STRESS ghosts: mount ${elapsed.inMilliseconds} ms, '
      'ghosts built=${ghosts().evaluate().length}, '
      'frame ${sw.elapsedMilliseconds} ms',
    );
    expect(tester.takeException(), isNull);
    expect(ghosts(), findsWidgets);
    expectBlocksSane(tester);
    for (final e in ghosts().evaluate()) {
      final box = e.renderObject! as RenderBox;
      expect(box.size.width, greaterThan(0));
      expect(box.size.height, greaterThan(0));
    }
    // Scrolling and a mouse drag of a ghost stay exception-free.
    final pos = gridPosition(tester);
    pos.jumpTo(pos.maxScrollExtent / 2);
    await tester.pump(const Duration(milliseconds: 300));
    final g = await tester.startGesture(
      tester.getCenter(ghosts().first),
      kind: PointerDeviceKind.mouse,
    );
    await g.moveBy(const Offset(0, 1));
    await tester.pump();
    await g.moveBy(const Offset(0, 20));
    await tester.pump();
    await g.moveBy(const Offset(0, -20));
    await tester.pump();
    await g.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('100 events starting the same minute stay usable', (
    tester,
  ) async {
    await mount(tester, seed: (d) => seedSameStart(d));
    expect(tester.takeException(), isNull);
    final events = find.byWidgetPredicate(isEvent).evaluate().toList();
    expect(events, isNotEmpty);
    expectBlocksSane(tester);
    // ignore: avoid_print
    print(
      'STRESS same-start: built ${events.length} of 100, narrowest '
      '${events.map((e) => (e.renderObject! as RenderBox).size.width).reduce((a, b) => a < b ? a : b)}',
    );
    await unmount(tester);
  });

  testWidgets('100 all-day items on one day', (tester) async {
    await mount(tester, seed: (d) => seedAllDay(d));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('phone width, rotating to landscape and back', (tester) async {
    await mount(
      tester,
      size: const Size(375, 812),
      seed: (d) async {
        await seedBusyWeek(d, perDay: 40);
        await seedAllDay(d, count: 10);
      },
    );
    expect(tester.takeException(), isNull);
    expectBlocksSane(tester);

    tester.view.physicalSize = const Size(812, 375);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expectBlocksSane(tester);

    tester.view.physicalSize = const Size(375, 812);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expectBlocksSane(tester);
    await unmount(tester);
  });

  group('packLanes', () {
    final t0 = DateTime.utc(2030, 1, 1, 8);

    test('1000 events with the same start finish quickly', () {
      final events = [for (var i = 0; i < 1000; i++) (i, 5 + i % 120)];
      final sw = Stopwatch()..start();
      final out = packLanes<(int, int)>(
        events,
        startOf: (_) => t0,
        endOf: (e) => t0.add(Duration(minutes: e.$2)),
      );
      sw.stop();
      // ignore: avoid_print
      print('PACK same-start x1000: ${sw.elapsedMilliseconds} ms');
      expect(out, hasLength(1000));
      expect(out.every((a) => a.laneCount == 1000), isTrue);
      expect(out.map((a) => a.lane).toSet(), hasLength(1000));
      expect(sw.elapsedMilliseconds, lessThan(3000));
    });

    test('a long chain of overlapping events is one cluster', () {
      // Each event overlaps the next, so the cluster never closes.
      final events = [for (var i = 0; i < 3000; i++) i];
      final sw = Stopwatch()..start();
      final out = packLanes<int>(
        events,
        startOf: (i) => t0.add(Duration(minutes: i * 10)),
        endOf: (i) => t0.add(Duration(minutes: i * 10 + 15)),
      );
      sw.stop();
      // ignore: avoid_print
      print('PACK chain x3000: ${sw.elapsedMilliseconds} ms');
      expect(out, hasLength(3000));
      expect(out.every((a) => a.laneCount == 2), isTrue);
      expect(sw.elapsedMilliseconds, lessThan(3000));
    });

    test('zero-length and identical events do not crash', () {
      final out = packLanes<int>(
        [for (var i = 0; i < 50; i++) i],
        startOf: (_) => t0,
        endOf: (_) => t0,
      );
      expect(out, hasLength(50));
      expect(out.map((a) => a.lane).toSet(), hasLength(50));
    });
  });
}
