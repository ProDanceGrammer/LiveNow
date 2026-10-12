import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/main.dart';
import 'package:livenow/ui/calendar_allday.dart';
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/sync_providers.dart';
import 'package:livenow/ui/views/calendar_layout.dart';

/// Calendar round 2: the Windows header (Now, 1-7 days, all-day switch, no
/// range text), the phone's floating menu, swipe to change days, the all-day
/// strip on/off, and the drag-while-scrolling maths.
void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;

  Future<void> pumpApp(
    WidgetTester tester, {
    required Size size,
    bool phone = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final service = ActionService(db);
    final now = DateTime.now();
    await tester.runAsync(() async {
      await service.createAction(
        name: 'Timed one',
        startAt: now.subtract(const Duration(minutes: 5)),
        endAt: now.add(const Duration(hours: 1)),
      );
      await service.createAction(
        name: 'Water all day',
        isAllDay: true,
        startAt: DateTime(now.year, now.month, now.day),
      );
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          syncRoleProvider.overrideWithValue(
            phone ? SyncRole.client : SyncRole.host,
          ),
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

  Future<void> openCalendarTab(WidgetTester tester) async {
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('actions-switch')),
        matching: find.text('Calendar'),
      ),
    );
    await settle(tester, 400);
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

  // ---- Windows -------------------------------------------------------------

  testWidgets('Windows header: Now (not Today), 1-7 days, no range text', (
    tester,
  ) async {
    await pumpApp(tester, size: const Size(1400, 900));
    await openCalendarTab(tester);
    expect(find.byKey(const ValueKey('calendar-now')), findsOneWidget);
    expect(find.text('Now'), findsOneWidget);
    expect(find.text('Today'), findsNothing);
    // "Oct 11 – 13, 2026": the range label is gone.
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            RegExp(r'^[A-Z][a-z]{2} \d{1,2} [–-] .*\d{4}$')
                .hasMatch(w.data ?? ''),
      ),
      findsNothing,
    );
    // The day selector now starts at 1.
    final seg = find.descendant(
      of: find.byType(SegmentedButton<int>),
      matching: find.byType(Text),
    );
    expect(
      [for (final e in seg.evaluate()) (e.widget as Text).data],
      ['1', '2', '3', '4', '5', '6', '7'],
    );
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<int>),
        matching: find.text('1'),
      ),
    );
    await settle(tester, 300);
    expect(containerOf(tester).read(calendarDayCountProvider), 1);
    expect(find.byKey(const ValueKey('day-header-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('day-header-1')), findsNothing);
    await unmount(tester);
  });

  testWidgets('the all-day switch hides and shows the all-day strip', (
    tester,
  ) async {
    await pumpApp(tester, size: const Size(1400, 900));
    await openCalendarTab(tester);
    expect(find.text('Water all day'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('calendar-allday-toggle')));
    await settle(tester, 300);
    expect(find.text('Water all day'), findsNothing);
    expect(containerOf(tester).read(calendarAllDayProvider), isFalse);
    // The timed action stays.
    expect(find.textContaining('Timed one'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('calendar-allday-toggle')));
    await settle(tester, 300);
    expect(find.text('Water all day'), findsWidgets);
    await unmount(tester);
  });

  // ---- phone ---------------------------------------------------------------

  testWidgets('phone: full screen with only a floating menu, no zoom buttons', (
    tester,
  ) async {
    await pumpApp(tester, size: const Size(375, 812), phone: true);
    await openCalendarTab(tester);
    // Full screen: no app bar, no bottom navigation, no view tabs.
    expect(find.byKey(const ValueKey('phone-nav')), findsNothing);
    expect(find.byKey(const ValueKey('actions-switch')), findsNothing);
    expect(find.byKey(const ValueKey('calendar-menu')), findsOneWidget);
    expect(find.byIcon(Icons.zoom_in), findsNothing);
    expect(find.byIcon(Icons.zoom_out), findsNothing);
    expect(find.text('Today'), findsNothing);
    expect(find.byKey(const ValueKey('day-header-0')), findsOneWidget);

    // The menu: Now, 1-3 days upright, all-day, icons, leave full screen.
    await tester.tap(find.byKey(const ValueKey('calendar-menu')));
    await tester.pumpAndSettle();
    // Now has its own icon next to the menu (not an item in it).
    expect(find.byKey(const ValueKey('calendar-now-phone')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-menu-now')), findsNothing);
    expect(find.byKey(const ValueKey('calendar-menu-days-3')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-menu-days-4')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('calendar-menu-days-2')));
    await tester.pumpAndSettle();
    expect(containerOf(tester).read(calendarDayCountProvider), 2);

    // Leaving full screen brings the app bar and bottom navigation back.
    await tester.tap(find.byKey(const ValueKey('calendar-full-toggle')));
    await settle(tester, 300);
    expect(find.byKey(const ValueKey('phone-nav')), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('phone landscape: up to 7 days in the menu', (tester) async {
    await pumpApp(tester, size: const Size(812, 375), phone: true);
    await openCalendarTab(tester);
    await tester.tap(find.byKey(const ValueKey('calendar-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calendar-menu-days-7')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('calendar-menu-days-5')));
    await tester.pumpAndSettle();
    expect(containerOf(tester).read(calendarDayCountProvider), 5);
    await unmount(tester);
  });

  testWidgets('a horizontal swipe turns the page, a vertical drag does not', (
    tester,
  ) async {
    await pumpApp(tester, size: const Size(375, 812), phone: true);
    await openCalendarTab(tester);
    final container = containerOf(tester);
    final before = container.read(calendarRangeStartProvider);

    // Finger moves left: next page (1 day on the phone).
    await tester.dragFrom(const Offset(200, 500), const Offset(-160, 6));
    await settle(tester, 300);
    final next = container.read(calendarRangeStartProvider);
    expect(next, calendarAddDays(before, 1));

    // Finger moves right: back.
    await tester.dragFrom(const Offset(120, 500), const Offset(160, -6));
    await settle(tester, 300);
    expect(container.read(calendarRangeStartProvider), before);

    // A mostly vertical drag (scroll) never changes the day.
    await tester.dragFrom(const Offset(200, 500), const Offset(30, -200));
    await settle(tester, 300);
    expect(container.read(calendarRangeStartProvider), before);
    // A short sideways nudge does not either.
    await tester.dragFrom(const Offset(200, 500), const Offset(-30, 0));
    await settle(tester, 300);
    expect(container.read(calendarRangeStartProvider), before);
    await unmount(tester);
  });

  // ---- dragging while the grid scrolls ----------------------------------------

  test(
    'a block follows the content when the grid scrolls under a still pointer',
    () {
      const ppm = 1.0; // 1 px per minute
      // Pointer did not move, the grid scrolled down 90 px: the block moved 90 min.
      expect(dragMinuteDelta(0, 90, pxPerMinute: ppm), 90);
      // The pointer moved up 30 and the wheel scrolled down 60: net +30 -> 30 min.
      expect(dragMinuteDelta(-30, 60, pxPerMinute: ppm), 30);
      // Scrolling back up undoes it; snapping to 10-minute steps applies.
      expect(dragMinuteDelta(0, -40, pxPerMinute: ppm), -40);
      expect(dragMinuteDelta(0, 14, pxPerMinute: ppm), 10);
      expect(dragMinuteDelta(0, 16, pxPerMinute: ppm), 20);
      // At other zooms the scroll counts in pixels too.
      expect(dragMinuteDelta(0, 60, pxPerMinute: 2.0), 30);
    },
  );
}
