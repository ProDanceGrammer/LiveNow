import 'dart:math' as math;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/main.dart';
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/notch_side.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/sync_providers.dart';
import 'package:livenow/ui/views/calendar_view.dart';

/// Round 6: the calendar keeps its TIME when the viewport height changes (the
/// keyboard under an event dialog), opens centred on Now, and the full-screen
/// landscape view uses the side opposite to the notch.
void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    resetStackedDialogsForTest();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// The calendar grid's own vertical scroll position (the one with the most to
  /// scroll).
  ScrollPosition gridPosition(WidgetTester tester) {
    ScrollPosition? best;
    for (final e in find.byType(Scrollable).evaluate()) {
      final st = (e as StatefulElement).state as ScrollableState;
      if (st.position.axis != Axis.vertical) continue;
      if (best == null ||
          st.position.maxScrollExtent > best.maxScrollExtent) {
        best = st.position;
      }
    }
    return best!;
  }

  Future<void> pumpCalendar(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: Scaffold(body: CalendarView())),
      ),
    );
    await settle(tester);
  }

  int nowMinutes() {
    final utc = DateTime.now().toUtc().add(const Duration(hours: 3)); // Istanbul
    return utc.hour * 60 + utc.minute;
  }

  testWidgets('the calendar opens with the now-line in the centre', (
    tester,
  ) async {
    await pumpCalendar(tester, const Size(1000, 800));
    final pos = gridPosition(tester);
    final pxPerMinute = pos.viewportDimension / 12 / 60; // 12 visible hours
    final expected = math.max(
      0.0,
      nowMinutes() * pxPerMinute - pos.viewportDimension / 2,
    ).clamp(0.0, pos.maxScrollExtent);
    // A minute of slack: the clock may tick over while the test runs.
    expect(pos.pixels, closeTo(expected, pxPerMinute * 2));
    await unmount(tester);
  });

  testWidgets('a shorter viewport (keyboard) does not change the time shown', (
    tester,
  ) async {
    await pumpCalendar(tester, const Size(1000, 800));
    var pos = gridPosition(tester);
    // The user scrolls to 16:00 at the top of the grid.
    final before = pos.viewportDimension / 12 / 60;
    pos.jumpTo((16 * 60 * before).clamp(0.0, pos.maxScrollExtent));
    await tester.pump(const Duration(milliseconds: 100));
    pos = gridPosition(tester);
    final topMinute = pos.pixels / (pos.viewportDimension / 12 / 60);

    // The keyboard comes up: much less height ...
    tester.view.physicalSize = const Size(1000, 380);
    await settle(tester);
    // ... and goes away again.
    tester.view.physicalSize = const Size(1000, 800);
    await settle(tester);

    pos = gridPosition(tester);
    final topMinuteAfter = pos.pixels / (pos.viewportDimension / 12 / 60);
    expect(
      topMinuteAfter,
      closeTo(topMinute, 1),
      reason: 'the same time is at the top as before the keyboard',
    );
    await unmount(tester);
  });

  group('landscape full screen uses the side opposite the notch', () {
    Future<Rect> calendarRect(WidgetTester tester, bool notchLeft) async {
      tester.view.physicalSize = const Size(812, 375);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(
        left: 59,
        right: 59,
        bottom: 21,
      );
      addTearDown(tester.view.reset);
      db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            syncRoleProvider.overrideWithValue(SyncRole.client),
            notchOnLeftProvider.overrideWith(() => NotchSideNotifier(notchLeft)),
          ],
          child: const LiveNowApp(),
        ),
      );
      await settle(tester);
      // Actions -> Calendar (full screen on a phone).
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('actions-switch')),
          matching: find.text('Calendar'),
        ),
      );
      await settle(tester);
      return tester.getRect(find.byType(CalendarView));
    }

    testWidgets('notch on the left: the right band is used', (tester) async {
      final r = await calendarRect(tester, true);
      expect(r.left, greaterThanOrEqualTo(59));
      expect(r.right, closeTo(812, 1));
      await unmount(tester);
    });

    testWidgets('notch on the right: the left band is used', (tester) async {
      final r = await calendarRect(tester, false);
      expect(r.left, lessThan(5));
      expect(r.right, lessThanOrEqualTo(812 - 59 + 1));
      await unmount(tester);
    });
  });
}
