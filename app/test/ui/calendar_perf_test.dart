import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/data/queries.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/calendar_selection.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/views/calendar_layout.dart';
import 'package:livenow/ui/views/calendar_view.dart';

/// Rebuild-count and first-build budget checks for the calendar with a big
/// week (300 events), so a regression to "everything rebuilds on every
/// selection / hover / tick" shows up here.
void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late ProviderContainer container;
  late List<ActionListItem> items;

  /// 300 timed events spread over the 7 viewed days, some overlapping.
  List<ActionListItem> generate() {
    final weekStart = calendarAnchorStart(DateTime.now().toUtc(), 7);
    return [
      for (var i = 0; i < 300; i++)
        () {
          final day = calendarAddDays(weekStart, i % 7);
          final start = day.add(Duration(minutes: ((i ~/ 7) * 33) % 1300));
          return ActionListItem(
            id: 'perf-$i',
            name: 'Event $i',
            done: false,
            startAt: start,
            endAt: start.add(Duration(minutes: 30 + (i % 4) * 20)),
            isAllDay: false,
          );
        }(),
    ];
  }

  final iconsSource = StateProvider<Map<String, String>>((ref) => const {});

  final urgencySource = StateProvider<Map<String, double>>((ref) => const {});

  Future<Duration> pumpCalendar(
    WidgetTester tester, {
    int hours = 24,
    List<ActionListItem>? only,
  }) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    items = only ?? generate();
    final sw = Stopwatch()..start();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          calendarVisibleHoursProvider.overrideWith((ref) => hours),
          // The same list instance on every read, like `distinctList` gives.
          calendarRangeProvider.overrideWith((ref) => Stream.value(items)),
          actionDirectionIconsProvider.overrideWith(
            (ref) => ref.watch(iconsSource),
          ),
          actionUrgencyProvider.overrideWith((ref) => ref.watch(urgencySource)),
        ],
        child: const MaterialApp(home: Scaffold(body: CalendarView())),
      ),
    );
    final tMount = sw.elapsed;
    await tester.pump(); // the stream delivers
    final tData = sw.elapsed - tMount;
    await tester.pump(const Duration(milliseconds: 50));
    sw.stop();
    // ignore: avoid_print
    print(
      'PERF phases: mount=${tMount.inMilliseconds} ms, '
      'data frame=${tData.inMilliseconds} ms, '
      'next frame=${(sw.elapsed - tMount - tData).inMilliseconds} ms',
    );
    container = ProviderScope.containerOf(
      tester.element(find.byType(CalendarView)),
    );
    return sw.elapsed;
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('first build of 300 events stays within a coarse budget', (
    tester,
  ) async {
    CalendarPerfCounters.reset();
    final elapsed = await pumpCalendar(tester);
    // ignore: avoid_print
    print(
      'PERF first build: ${elapsed.inMilliseconds} ms, '
      'blockBuilds=${CalendarPerfCounters.blockBuilds}, '
      'layoutRuns=${CalendarPerfCounters.layoutRuns}',
    );
    expect(
      elapsed.inMilliseconds,
      lessThan(20000),
      reason: 'first build took ${elapsed.inMilliseconds} ms',
    );
    expect(find.byType(CalendarView), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('selecting an event rebuilds a handful of blocks, one layout', (
    tester,
  ) async {
    await pumpCalendar(tester);
    CalendarPerfCounters.reset();
    container.read(calendarSelectionProvider.notifier).state = {'perf-3'};
    await tester.pump();
    container.read(calendarSelectionProvider.notifier).state = {'perf-10'};
    await tester.pump();
    // ignore: avoid_print
    print(
      'PERF 2 selection changes: blockBuilds='
      '${CalendarPerfCounters.blockBuilds}, '
      'layoutRuns=${CalendarPerfCounters.layoutRuns}',
    );
    // Two changes touch at most old + new block each (a block may be split
    // over midnight), never the other ~300.
    expect(CalendarPerfCounters.blockBuilds, lessThanOrEqualTo(8));
    expect(
      CalendarPerfCounters.layoutRuns,
      0,
      reason: 'the memoized layout must be reused when only selection changes',
    );
    await unmount(tester);
  });

  testWidgets('hover and the clock tick do not rebuild the blocks', (
    tester,
  ) async {
    await pumpCalendar(tester);
    CalendarPerfCounters.reset();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1, 1));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('event-perf-3'))),
    );
    await tester.pump();
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('event-perf-4'))),
    );
    await tester.pump();
    final afterHover = CalendarPerfCounters.blockBuilds;

    // The grid's once-a-minute tick (moves the now-line).
    await tester.pump(const Duration(minutes: 1));
    final afterTick = CalendarPerfCounters.blockBuilds;
    // ignore: avoid_print
    print(
      'PERF hover blockBuilds=$afterHover, after tick=$afterTick, '
      'layoutRuns=${CalendarPerfCounters.layoutRuns}',
    );
    expect(afterHover, lessThanOrEqualTo(4));
    expect(afterTick - afterHover, lessThanOrEqualTo(4));
    expect(CalendarPerfCounters.layoutRuns, 0);
    await unmount(tester);
  });

  testWidgets('a drag preview does not rebuild unaffected blocks', (
    tester,
  ) async {
    await pumpCalendar(tester);
    CalendarPerfCounters.reset();
    final block = find.byKey(const ValueKey('event-perf-3'));
    final origin = tester.getCenter(block);
    final g = await tester.startGesture(origin, kind: PointerDeviceKind.mouse);
    await g.moveBy(const Offset(0, 1));
    await tester.pump();
    await g.moveBy(const Offset(0, 30));
    await tester.pump();
    await g.moveBy(const Offset(0, 30));
    await tester.pump();
    // ignore: avoid_print
    print(
      'PERF drag blockBuilds=${CalendarPerfCounters.blockBuilds}, '
      'layoutRuns=${CalendarPerfCounters.layoutRuns}',
    );
    expect(CalendarPerfCounters.blockBuilds, lessThanOrEqualTo(8));
    expect(CalendarPerfCounters.layoutRuns, 0);
    // Back to the start: an unchanged schedule ends the drag without a write.
    await g.moveTo(origin);
    await tester.pump();
    await g.up();
    await tester.pump(const Duration(milliseconds: 50));
    await unmount(tester);
  });

  testWidgets('zoomed in, only blocks near the visible hours are built', (
    tester,
  ) async {
    CalendarPerfCounters.reset();
    await pumpCalendar(tester, hours: 3);
    final firstBuild = CalendarPerfCounters.blockBuilds;
    // ignore: avoid_print
    print('PERF 3 h zoom first build: blockBuilds=$firstBuild of 300');
    expect(firstBuild, lessThan(200));

    // The latest event of the day is far below the initial scroll position;
    // scrolling there builds it.
    final late = items.reduce(
      (a, b) => minutesOfDay(a.startAt!) >= minutesOfDay(b.startAt!) ? a : b,
    );
    final key = find.byKey(ValueKey('event-${late.id}'));
    final scrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(CalendarView),
            matching: find.byType(Scrollable),
          )
          .last,
    );
    // Start from the top: the initial offset follows the time of day, so late
    // in the evening the last event would already be inside the window.
    scrollable.position.jumpTo(0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(key, findsNothing);
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(key, findsOneWidget);
    await unmount(tester);
  });

  testWidgets(
    'changing one action\'s direction icons rebuilds only its block',
    (tester) async {
      await pumpCalendar(tester);
      CalendarPerfCounters.reset();
      container.read(iconsSource.notifier).state = {'perf-3': '\u{1F381}'};
      await tester.pump();
      final first = CalendarPerfCounters.blockBuilds;
      // A block can be split over midnight, so allow a couple of segments.
      expect(first, inInclusiveRange(1, 2));
      container.read(iconsSource.notifier).state = {
        'perf-3': '\u{1F381}',
        'perf-10': '\u{26A1}',
      };
      await tester.pump();
      expect(CalendarPerfCounters.blockBuilds - first, inInclusiveRange(1, 2));
      expect(CalendarPerfCounters.layoutRuns, 0);
      await unmount(tester);
    },
  );

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

  const gift = '\u{1F381}';

  testWidgets('scrolling hides the badges and rebuilds no block', (
    tester,
  ) async {
    await pumpCalendar(tester, hours: 12);
    container.read(iconsSource.notifier).state = {
      for (final a in items) a.id: gift,
    };
    await tester.pump();
    final pos = gridPosition(tester);
    pos.jumpTo(0);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text(gift), findsWidgets, reason: 'badges at rest');
    expect(pos.maxScrollExtent, greaterThan(50));

    CalendarPerfCounters.reset();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(700, 400));
    addTearDown(mouse.removePointer);
    pos.jumpTo(pos.maxScrollExtent);
    await tester.pump();
    expect(find.text(gift), findsNothing, reason: 'hidden while scrolling');
    pos.jumpTo(pos.maxScrollExtent / 2);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(gift), findsNothing, reason: 'still moving');
    expect(CalendarPerfCounters.blockBuilds, 0);
    expect(CalendarPerfCounters.badgeBuilds, 0);

    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text(gift), findsWidgets, reason: 'back after the debounce');
    expect(
      CalendarPerfCounters.blockBuilds,
      0,
      reason: 'flipping the scrolling flag must not rebuild blocks',
    );
    await unmount(tester);
  });

  testWidgets('hover toolbar neither shows nor hides while scrolling', (
    tester,
  ) async {
    final weekStart = calendarAnchorStart(DateTime.now().toUtc(), 7);
    final start = weekStart.add(const Duration(hours: 4));
    final only = [
      ActionListItem(
        id: 'solo',
        name: 'Solo',
        done: false,
        startAt: start,
        endAt: start.add(const Duration(hours: 2)),
        isAllDay: false,
      ),
    ];
    await pumpCalendar(tester, hours: 12, only: only);
    final pos = gridPosition(tester);
    pos.jumpTo(0);
    await tester.pump(const Duration(milliseconds: 200));
    final rect = tester.getRect(find.byKey(const ValueKey('event-solo')));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset(rect.center.dx, rect.top - 3));
    addTearDown(mouse.removePointer);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byTooltip('Start'), findsNothing);

    CalendarPerfCounters.reset();
    // Content moves up 20 px: the parked pointer is now inside the block.
    pos.jumpTo(20);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(CalendarPerfCounters.toolbarShows, 0);
    expect(find.byTooltip('Start'), findsNothing);
    await tester.pump(const Duration(milliseconds: 200));
    expect(CalendarPerfCounters.toolbarShows, 1);
    expect(find.byTooltip('Start'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a minute tick that keeps every urgency band rebuilds nothing', (
    tester,
  ) async {
    await pumpCalendar(tester, hours: 12);
    container.read(urgencySource.notifier).state = {
      'perf-3': 50,
      'perf-10': 20,
    };
    await tester.pump();
    CalendarPerfCounters.reset();
    // The provider re-emits a new map every minute; numbers move, bands not.
    container.read(urgencySource.notifier).state = {
      'perf-3': 55,
      'perf-10': 21,
    };
    await tester.pump();
    container.read(urgencySource.notifier).state = {
      'perf-3': 60,
      'perf-10': 22,
    };
    await tester.pump();
    expect(CalendarPerfCounters.blockBuilds, 0);

    // perf-3 crosses 100 (medium -> high): only its block rebuilds.
    container.read(urgencySource.notifier).state = {
      'perf-3': 150,
      'perf-10': 22,
    };
    await tester.pump();
    expect(CalendarPerfCounters.blockBuilds, inInclusiveRange(1, 2));
    await unmount(tester);
  });
}
