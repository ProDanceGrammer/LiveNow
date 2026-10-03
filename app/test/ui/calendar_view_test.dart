import 'dart:math' as math;

import 'package:drift/drift.dart' show BooleanExpressionOperators;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/time_codec.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/theme/glass_theme.dart';
import 'package:livenow/ui/views/calendar_layout.dart';
import 'package:livenow/ui/views/calendar_view.dart';

void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late ProviderContainer container;

  // Local (Europe/Istanbul, UTC+3) midnight today; events sit on today.
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
          // The whole day fits the window, so nothing sits out of view
          // whatever the time of day; the zoom tests change it themselves.
          calendarVisibleHoursProvider.overrideWith((ref) => 24),
        ],
        child: const MaterialApp(home: Scaffold(body: CalendarView())),
      ),
    );
    container = ProviderScope.containerOf(
      tester.element(find.byType(CalendarView)),
    );
  }

  /// Pixels per minute as drawn, read off two gutter labels: it depends on the
  /// zoom level and the window height, so tests must not hard-code it.
  double pxPerMinute(WidgetTester tester) =>
      (tester.getTopLeft(find.text('14:00')).dy -
          tester.getTopLeft(find.text('13:00')).dy) /
      60;

  Future<String> create(
    WidgetTester tester, {
    String name = 'Alpha',
    DateTime? startAt,
    DateTime? endAt,
    bool isAllDay = false,
  }) async {
    return (await tester.runAsync(
      () => container
          .read(actionServiceProvider)
          .createAction(
            name: name,
            startAt: startAt,
            endAt: endAt,
            isAllDay: isAllDay,
          ),
    ))!;
  }

  /// Lets Drift's streams deliver, then rebuilds.
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

  /// Real mouse drag starting [localFrom] inside [block], moving by [delta].
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
    await g.moveBy(delta - const Offset(0, 1));
    await tester.pump();
    await tester.runAsync(() async {
      await g.up();
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Puts a mouse over [target] so its hover toolbar shows.
  Future<TestGesture> hover(WidgetTester tester, Finder target) async {
    final m = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await m.addPointer(location: const Offset(1, 1));
    addTearDown(m.removePointer);
    await m.moveTo(tester.getCenter(target));
    await tester.pump();
    return m;
  }

  testWidgets('day-count selector renders 2..7 columns', (tester) async {
    await pump(tester);
    await settle(tester);
    int columns() => find
        .byWidgetPredicate(
          (w) =>
              w.key is ValueKey &&
              '${(w.key as ValueKey).value}'.startsWith('day-header-'),
        )
        .evaluate()
        .length;
    expect(columns(), 7);
    for (var n = 2; n <= 7; n++) {
      await tester.tap(find.byTooltip('$n days'));
      await tester.pump();
      expect(columns(), n, reason: '$n days');
    }
    await unmount(tester);
  });

  testWidgets('timed event shows name and start–end time, not duration', (
    tester,
  ) async {
    await pump(tester);
    final id = await create(tester, startAt: at(10), endAt: at(11, 30));
    await useDays(tester, 3);
    final block = find.byKey(ValueKey('event-$id'));
    expect(
      find.descendant(of: block, matching: find.textContaining('Alpha')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: block, matching: find.textContaining('10:00–11:30')),
      findsOneWidget,
    );
    expect(find.text('1 hour 30 min'), findsNothing);
    await unmount(tester);
  });

  testWidgets('a short event shows its whole range on one line', (
    tester,
  ) async {
    await pump(tester);
    final id = await create(tester, startAt: at(15, 40), endAt: at(15, 50));
    await useDays(tester, 3);
    expect(
      find.descendant(
        of: find.byKey(ValueKey('event-$id')),
        matching: find.text('Alpha · 15:40–15:50'),
      ),
      findsOneWidget,
    );
    await unmount(tester);
  });

  testWidgets('body drag moves the event, snapped to 10 minutes', (
    tester,
  ) async {
    await pump(tester);
    final id = await create(tester, startAt: at(10), endAt: at(11));
    await useDays(tester, 3);
    // 21 min of pixels -> snaps to 20.
    await dragBy(
      tester,
      find.byKey(ValueKey('event-$id')),
      const Offset(30, 24),
      Offset(0, 21 * pxPerMinute(tester)),
    );
    final r = await row(tester, id);
    expect(dateTimeFromDb(r.startAt), at(10, 20));
    expect(dateTimeFromDb(r.endAt), at(11, 20));
    await unmount(tester);
  });

  testWidgets('bottom handle changes the duration in 10 min steps', (
    tester,
  ) async {
    await pump(tester);
    final id = await create(tester, startAt: at(10), endAt: at(11));
    await useDays(tester, 3);
    final block = find.byKey(ValueKey('event-$id'));
    final ppm = pxPerMinute(tester);
    // 20 min of pixels, grabbing the bottom handle.
    await dragBy(
      tester,
      block,
      Offset(30, tester.getSize(block).height - 2),
      Offset(0, 20 * ppm),
    );
    var r = await row(tester, id);
    expect(dateTimeFromDb(r.startAt), at(10));
    expect(dateTimeFromDb(r.endAt), at(11, 20));

    // Dragging far up clamps to the 10 min minimum.
    await dragBy(
      tester,
      block,
      Offset(30, tester.getSize(block).height - 2),
      const Offset(0, -400),
    );
    r = await row(tester, id);
    expect(dateTimeFromDb(r.startAt), at(10));
    expect(dateTimeFromDb(r.endAt), at(10, 10));
    await unmount(tester);
  });

  testWidgets('top handle changes the start', (tester) async {
    await pump(tester);
    final id = await create(tester, startAt: at(10), endAt: at(11));
    await useDays(tester, 3);
    await dragBy(
      tester,
      find.byKey(ValueKey('event-$id')),
      const Offset(30, 2),
      Offset(0, 20 * pxPerMinute(tester)),
    );
    final r = await row(tester, id);
    expect(dateTimeFromDb(r.startAt), at(10, 20));
    expect(dateTimeFromDb(r.endAt), at(11));
    await unmount(tester);
  });

  testWidgets('sideways drag moves the event a whole day', (tester) async {
    await pump(tester);
    final id = await create(tester, startAt: at(10), endAt: at(11));
    await useDays(tester, 3);
    final dayW = (1400 - 56) / 3;
    await dragBy(
      tester,
      find.byKey(ValueKey('event-$id')),
      const Offset(30, 24),
      Offset(dayW + 10, 0),
    );
    final r = await row(tester, id);
    expect(dateTimeFromDb(r.startAt), at(10).add(const Duration(days: 1)));
    expect(dateTimeFromDb(r.endAt), at(11).add(const Duration(days: 1)));
    await unmount(tester);
  });

  testWidgets('a ghost shows during the drag and Undo restores afterwards', (
    tester,
  ) async {
    await pump(tester);
    final id = await create(tester, startAt: at(10), endAt: at(11));
    await useDays(tester, 3);
    final block = find.byKey(ValueKey('event-$id'));

    final g = await tester.startGesture(
      tester.getTopLeft(block) + const Offset(30, 24),
      kind: PointerDeviceKind.mouse,
    );
    await g.moveBy(Offset(0, 50 * pxPerMinute(tester)));
    await tester.pump();
    expect(find.byKey(const ValueKey('drag-ghost')), findsOneWidget);
    // The times are readable: bold, on a white chip.
    final range = find.descendant(
      of: find.byKey(const ValueKey('drag-ghost')),
      matching: find.text('10:50 – 11:50'),
    );
    expect(range, findsOneWidget);
    expect(tester.widget<Text>(range).style!.fontWeight, FontWeight.w700);
    expect(
      find.ancestor(
        of: range,
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              (w.decoration as BoxDecoration?)?.color ==
                  GlassTheme.light.fillStrong,
        ),
      ),
      findsOneWidget,
    );
    await tester.runAsync(() async {
      await g.up();
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('drag-ghost')), findsNothing);

    expect(dateTimeFromDb((await row(tester, id)).startAt), at(10, 50));
    expect(find.text('Moved'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Undo'));
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    final r = await row(tester, id);
    expect(dateTimeFromDb(r.startAt), at(10));
    expect(dateTimeFromDb(r.endAt), at(11));

    await tester.pump(const Duration(seconds: 1));
    await unmount(tester);
  });

  testWidgets('all-day action shows in the strip, not the grid', (
    tester,
  ) async {
    await pump(tester);
    final id = await create(
      tester,
      name: 'Holiday',
      startAt: at(0),
      isAllDay: true,
    );
    await useDays(tester, 3);
    expect(find.byKey(ValueKey('allday-$id')), findsOneWidget);
    expect(find.text('Holiday'), findsOneWidget);
    expect(find.byKey(ValueKey('event-$id')), findsNothing);
    await unmount(tester);
  });

  group('create by dragging on empty space', () {
    double lineY(WidgetTester tester, int hour) =>
        tester.getTopLeft(find.text('13:00')).dy +
        7 +
        (hour - 13) * 60 * pxPerMinute(tester);

    /// Drags from [fromY] to [toY] inside day column [day] of a 3-day view,
    /// like a mouse would (a tiny first move to pass the drag slop).
    Future<TestGesture> sweep(
      WidgetTester tester, {
      required int day,
      required double fromY,
      required double toY,
    }) async {
      final dayW = (1400 - 56) / 3;
      final x = 56 + dayW * day + dayW / 2;
      final g = await tester.startGesture(
        Offset(x, fromY),
        kind: PointerDeviceKind.mouse,
      );
      await g.moveBy(const Offset(0, 1));
      await tester.pump();
      await g.moveTo(Offset(x, toY));
      await tester.pump();
      return g;
    }

    Future<void> animate(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<List<ActionRow>> allActions(WidgetTester tester) async =>
        (await tester.runAsync(() => db.select(db.actionsTable).get()))!;

    testWidgets(
      'sweeping a range opens New action with that time; Enter saves',
      (tester) async {
        await pump(tester);
        await useDays(tester, 3);
        final ppm = pxPerMinute(tester);

        // 09:07 -> 10:33: the start snaps down and the end up to 10 minutes.
        final g = await sweep(
          tester,
          day: 1,
          fromY: lineY(tester, 9) + 7 * ppm,
          toY: lineY(tester, 10) + 33 * ppm,
        );
        final preview = find.byKey(const ValueKey('create-preview'));
        expect(preview, findsOneWidget);
        expect(
          find.descendant(of: preview, matching: find.text('09:00 – 10:40')),
          findsOneWidget,
        );

        await g.up();
        await animate(tester);
        expect(preview, findsNothing);
        expect(find.text('New action'), findsOneWidget);

        // Enter in the name field is the Save button.
        await tester.enterText(find.byType(TextFormField).first, 'Focus block');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        await tester.pump(const Duration(milliseconds: 400));

        final saved = await allActions(tester);
        expect(saved.single.name, 'Focus block');
        final tomorrow = const Duration(days: 1);
        expect(dateTimeFromDb(saved.single.startAt), at(9).add(tomorrow));
        expect(dateTimeFromDb(saved.single.endAt), at(10, 40).add(tomorrow));
        expect(saved.single.isAllDay, isFalse);
        await settle(tester);
        await unmount(tester);
      },
    );

    testWidgets('sweeping upwards gives the same kind of range', (
      tester,
    ) async {
      await pump(tester);
      await useDays(tester, 3);

      // From 10:59 up to 10:01 (a minute inside each edge, so pixel rounding
      // can't tip the snapping).
      final ppm = pxPerMinute(tester);
      final g = await sweep(
        tester,
        day: 0,
        fromY: lineY(tester, 11) - ppm,
        toY: lineY(tester, 10) + ppm,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('create-preview')),
          matching: find.text('10:00 – 11:00'),
        ),
        findsOneWidget,
      );
      await g.up();
      await animate(tester);

      // Cancelling creates nothing.
      await tester.tap(find.text('Cancel'));
      await animate(tester);
      expect(await allActions(tester), isEmpty);
      await settle(tester);
      await unmount(tester);
    });

    testWidgets('a plain click on empty space creates nothing', (tester) async {
      await pump(tester);
      await useDays(tester, 3);
      final dayW = (1400 - 56) / 3;
      await tester.tapAt(
        Offset(56 + dayW / 2, lineY(tester, 10)),
        kind: PointerDeviceKind.mouse,
      );
      await animate(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(const ValueKey('create-preview')), findsNothing);
      await unmount(tester);
    });

    testWidgets('dragging that starts on an event still moves the event', (
      tester,
    ) async {
      await pump(tester);
      final id = await create(tester, startAt: at(10), endAt: at(11));
      await useDays(tester, 3);
      await dragBy(
        tester,
        find.byKey(ValueKey('event-$id')),
        const Offset(30, 24),
        Offset(0, 20 * pxPerMinute(tester)),
      );
      expect(find.byType(AlertDialog), findsNothing);
      expect(dateTimeFromDb((await row(tester, id)).startAt), at(10, 20));
      await tester.pump(const Duration(seconds: 1));
      await unmount(tester);
    });
  });

  group('zoom', () {
    Future<void> withCtrl(
      WidgetTester tester,
      Future<void> Function() body,
    ) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await body();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    int hours() => container.read(calendarVisibleHoursProvider);

    /// The grid's scroll viewport (the last scroll view; the first is the
    /// all-day strip).
    Finder gridScroll() => find.byType(SingleChildScrollView).last;

    ScrollPosition gridPosition(WidgetTester tester) => tester
        .state<ScrollableState>(
          find.descendant(of: gridScroll(), matching: find.byType(Scrollable)),
        )
        .position;

    testWidgets('Ctrl+= / Ctrl+- step 3-6-9-12-16-24 and stop at the ends', (
      tester,
    ) async {
      await pump(tester);
      await settle(tester);
      // Hours visible * pixels per hour is always the viewport height.
      final viewport = pxPerMinute(tester) * 60 * hours();

      Future<void> press(LogicalKeyboardKey key) =>
          withCtrl(tester, () => tester.sendKeyEvent(key));

      expect(hours(), 24);
      await press(LogicalKeyboardKey.minus);
      expect(hours(), 24, reason: 'already the most zoomed out');

      final seen = <int>[];
      for (var i = 0; i < 6; i++) {
        await press(LogicalKeyboardKey.equal);
        seen.add(hours());
        expect(pxPerMinute(tester) * 60 * hours(), closeTo(viewport, 0.5));
      }
      expect(seen, [16, 12, 9, 6, 3, 3]);
      expect(find.text('3 h'), findsOneWidget);

      await press(LogicalKeyboardKey.minus);
      expect(hours(), 6);
      await press(LogicalKeyboardKey.numpadAdd);
      expect(hours(), 3);
      await press(LogicalKeyboardKey.numpadSubtract);
      expect(hours(), 6);
      await unmount(tester);
    });

    testWidgets('Ctrl+scroll zooms (up = in), plain scroll does not', (
      tester,
    ) async {
      await pump(tester);
      await settle(tester);
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(const Offset(700, 600)));

      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -100)));
      await tester.pump();
      expect(hours(), 24, reason: 'no Ctrl, no zoom');

      await withCtrl(tester, () async {
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, -100)));
        await tester.pump();
        expect(hours(), 16);
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, -100)));
        await tester.pump();
        expect(hours(), 12);
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, 100)));
        await tester.pump();
        expect(hours(), 16);
      });
      await unmount(tester);
    });

    testWidgets('the time at the viewport centre stays put when zooming', (
      tester,
    ) async {
      await pump(tester);
      container.read(calendarVisibleHoursProvider.notifier).state = 12;
      await settle(tester);
      final position = gridPosition(tester);
      position.jumpTo(position.maxScrollExtent / 2);
      await tester.pump();

      // The hour label nearest the viewport centre.
      final centre = tester.getRect(gridScroll()).center.dy;
      String nearest() {
        String? best;
        var bestDistance = double.infinity;
        for (var h = 1; h < 24; h++) {
          final label = '${h.toString().padLeft(2, '0')}:00';
          final y = tester.getCenter(find.text(label)).dy;
          if ((y - centre).abs() < bestDistance) {
            bestDistance = (y - centre).abs();
            best = label;
          }
        }
        return best!;
      }

      final label = nearest();
      final before = tester.getCenter(find.text(label)).dy;
      await withCtrl(
        tester,
        () => tester.sendKeyEvent(LogicalKeyboardKey.equal),
      );
      await tester.pump(); // the scroll correction runs after the layout
      expect(hours(), 9);
      expect(tester.getCenter(find.text(label)).dy, closeTo(before, 2));
      await unmount(tester);
    });

    testWidgets('Ctrl+scroll keeps the time under the pointer in place', (
      tester,
    ) async {
      await pump(tester);
      container.read(calendarVisibleHoursProvider.notifier).state = 12;
      await settle(tester);
      final position = gridPosition(tester);
      position.jumpTo(position.maxScrollExtent / 2);
      await tester.pump();

      // Point at the 3rd visible hour label from the top of the viewport.
      final top = tester.getRect(gridScroll()).top;
      String? label;
      for (var h = 1; h < 24 && label == null; h++) {
        final l = '${h.toString().padLeft(2, '0')}:00';
        if (tester.getCenter(find.text(l)).dy > top + 120) label = l;
      }
      final target = tester.getCenter(find.text(label!));
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        pointer.hover(Offset(target.dx + 300, target.dy)),
      );

      await withCtrl(tester, () async {
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, -100)));
        await tester.pump();
        await tester.pump();
      });
      expect(hours(), 9);
      expect(tester.getCenter(find.text(label)).dy, closeTo(target.dy, 2));
      await unmount(tester);
    });
  });

  group('day navigation', () {
    DateTime rangeStart() => container.read(calendarRangeStartProvider);

    testWidgets('Left/Right arrows move one day', (tester) async {
      await pump(tester);
      await settle(tester);
      final start = rangeStart();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(rangeStart(), calendarAddDays(start, 2));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(rangeStart(), calendarAddDays(start, 1));
      await unmount(tester);
    });

    testWidgets('Shift+scroll moves days, plain scroll does not', (
      tester,
    ) async {
      await pump(tester);
      await settle(tester);
      final start = rangeStart();
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(const Offset(700, 500)));

      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 100)));
      await tester.pump();
      expect(rangeStart(), start, reason: 'no Shift, vertical scroll only');

      // Two notches forward, one back: net one day.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 100)));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 100)));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -100)));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(rangeStart(), calendarAddDays(start, 1));
      await unmount(tester);
    });
  });

  group('delete', () {
    Future<bool> exists(WidgetTester tester, String id) async =>
        (await tester.runAsync(
          () =>
              (db.select(db.actionsTable)..where((t) => t.id.equals(id))).get(),
        ))!.isNotEmpty;

    /// A delete resumes in the fake-async zone after its database work: pump,
    /// give the database real time, then pump the snackbar in.
    Future<void> afterDelete(WidgetTester tester) async {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('click selects, Delete key deletes at once and Undo restores', (
      tester,
    ) async {
      await pump(tester);
      final id = await create(tester, startAt: at(10), endAt: at(11));
      await useDays(tester, 3);

      await tester.tap(find.byKey(ValueKey('event-$id')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(container.read(calendarSelectedActionProvider), id);

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await afterDelete(tester);
      // No "are you sure?" dialog; the Undo snackbar is the safety net.
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Deleted "Alpha"'), findsOneWidget);
      expect(await exists(tester, id), isFalse);
      expect(container.read(calendarSelectedActionProvider), isNull);

      await tester.runAsync(() async {
        await tester.tap(find.text('Undo'));
        await Future<void>.delayed(const Duration(milliseconds: 250));
      });
      expect(await exists(tester, id), isTrue);
      await tester.pump(const Duration(seconds: 1));
      await unmount(tester);
    });

    testWidgets('Delete key with nothing selected does nothing', (
      tester,
    ) async {
      await pump(tester);
      final id = await create(tester, startAt: at(10), endAt: at(11));
      await useDays(tester, 3);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await afterDelete(tester);
      expect(find.textContaining('Deleted'), findsNothing);
      expect(await exists(tester, id), isTrue);
      await unmount(tester);
    });

    testWidgets('toolbar trash button deletes, also on an all-day chip', (
      tester,
    ) async {
      await pump(tester);
      final id = await create(tester, startAt: at(10), endAt: at(11));
      final allDay = await create(
        tester,
        name: 'Holiday',
        startAt: at(0),
        isAllDay: true,
      );
      await useDays(tester, 3);

      // One mouse pointer, moved between the two targets.
      final mouse = await hover(tester, find.byKey(ValueKey('event-$id')));
      for (final (target, deleted) in [
        (find.byKey(ValueKey('event-$id')), id),
        (find.byKey(ValueKey('allday-$allDay')), allDay),
      ]) {
        await mouse.moveTo(tester.getCenter(target));
        await tester.pump();
        await tester.tap(find.byTooltip('Delete'));
        await afterDelete(tester);
        await settle(tester);
        expect(await exists(tester, deleted), isFalse);
      }
      await tester.pump(const Duration(seconds: 1));
      await unmount(tester);
    });
  });

  group('hover toolbar', () {
    testWidgets('Start marks the action running', (tester) async {
      await pump(tester);
      final id = await create(tester, startAt: at(10), endAt: at(11));
      await useDays(tester, 3);
      await hover(tester, find.byKey(ValueKey('event-$id')));
      expect(find.byTooltip('Start'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Start'));
        await Future<void>.delayed(const Duration(milliseconds: 250));
      });
      final occ = await tester.runAsync(
        () => (db.select(
          db.actionOccurrencesTable,
        )..where((t) => t.actionId.equals(id) & t.finishedAt.isNull())).get(),
      );
      expect(occ, hasLength(1));
      await tester.pump(const Duration(seconds: 1));
      await unmount(tester);
    });

    testWidgets('Finish sets done', (tester) async {
      await pump(tester);
      final id = await create(tester, startAt: at(10), endAt: at(11));
      await useDays(tester, 3);
      await hover(tester, find.byKey(ValueKey('event-$id')));
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Finish'));
        await Future<void>.delayed(const Duration(milliseconds: 250));
      });
      expect((await row(tester, id)).done, isTrue);
      await tester.pump(const Duration(seconds: 1));
      await unmount(tester);
    });

    testWidgets('+7 days postpones a week, also on an all-day chip', (
      tester,
    ) async {
      await pump(tester);
      final id = await create(tester, startAt: at(10), endAt: at(11));
      final allDay = await create(
        tester,
        name: 'Holiday',
        startAt: at(0),
        isAllDay: true,
      );
      await useDays(tester, 3);

      final m = await hover(tester, find.byKey(ValueKey('event-$id')));
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Postpone +7 days'));
        await Future<void>.delayed(const Duration(milliseconds: 250));
      });
      final limit = DateTime.now().toUtc().add(const Duration(days: 6));
      expect(
        dateTimeFromDb((await row(tester, id)).startAt)!.isAfter(limit),
        isTrue,
      );

      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      await m.moveTo(tester.getCenter(find.byKey(ValueKey('allday-$allDay'))));
      await tester.pump();
      expect(find.byTooltip('Postpone +7 days'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('toolbar stays clickable for a 10-minute (tiny) block', (
      tester,
    ) async {
      await pump(tester);
      final id = await create(tester, startAt: at(10), endAt: at(10, 10));
      await useDays(tester, 3);
      final block = find.byKey(ValueKey('event-$id'));
      // 10 minutes of pixels, but never under the 8 px floor.
      expect(
        tester.getSize(block).height,
        closeTo(math.max(8, 10 * pxPerMinute(tester)), 0.01),
      );
      final m = await hover(tester, block);

      // Move from the block onto the toolbar (above its top-right corner).
      final tool = find.byTooltip('Finish');
      expect(tool, findsOneWidget);
      await m.moveTo(tester.getCenter(tool));
      await tester.pump();
      expect(find.byTooltip('Finish'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(tool);
        await Future<void>.delayed(const Duration(milliseconds: 250));
      });
      expect((await row(tester, id)).done, isTrue);
      await tester.pump(const Duration(seconds: 1));
      await unmount(tester);
    });
  });

  group('G2 all-day workflow', () {
    Future<void> afterWrite(WidgetTester tester) async {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
    }

    /// Lets the real-zone continuations of the snackbar's exit animation run
    /// while the tree is still mounted, then unmounts.
    Future<void> finish(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(seconds: 1));
      await unmount(tester);
    }

    /// The Undo snackbar slides in after the write resumed in the fake zone.
    Future<void> tapUndo(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(() async {
        await tester.tap(find.text('Undo'));
        await Future<void>.delayed(const Duration(milliseconds: 250));
      });
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
    }

    double lineY(WidgetTester tester, int hour) =>
        tester.getTopLeft(find.text('13:00')).dy +
        7 +
        (hour - 13) * 60 * pxPerMinute(tester);

    double colX(int day) => 56 + (1400 - 56) / 3 * (day + 0.5);

    /// A real mouse drag from [from] to [to], paused at [to] for [during].
    Future<void> dragTo(
      WidgetTester tester,
      Offset from,
      Offset to, {
      Future<void> Function()? during,
    }) async {
      final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
      await g.moveBy(const Offset(0, 8));
      await tester.pump();
      await g.moveTo(to);
      await tester.pump();
      if (during != null) await during();
      await tester.runAsync(() async {
        await g.up();
        await Future<void>.delayed(const Duration(milliseconds: 250));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
    }

    testWidgets('chip checkbox ticks, strikes the name and Undo unticks', (
      tester,
    ) async {
      await pump(tester);
      final id = await create(
        tester,
        name: 'Holiday',
        startAt: at(0),
        isAllDay: true,
      );
      await useDays(tester, 3);
      final box = find.byKey(ValueKey('chip-check-$id'));
      Text name() => tester.widget<Text>(
        find.descendant(
          of: find.byKey(ValueKey('allday-$id')),
          matching: find.text('Holiday'),
        ),
      );
      expect(tester.widget<Checkbox>(box).value, isFalse);
      expect(name().style?.decoration, isNull);

      await tester.runAsync(() async {
        await tester.tap(box);
        await Future<void>.delayed(const Duration(milliseconds: 250));
      });
      await afterWrite(tester);
      expect((await row(tester, id)).done, isTrue);
      expect(tester.widget<Checkbox>(box).value, isTrue);
      expect(name().style?.decoration, TextDecoration.lineThrough);

      await tapUndo(tester);
      expect((await row(tester, id)).done, isFalse);
      expect(tester.widget<Checkbox>(box).value, isFalse);
      await finish(tester);
    });

    testWidgets('Start on an all-day chip makes it a running block now', (
      tester,
    ) async {
      await pump(tester);
      final id = await create(
        tester,
        name: 'Holiday',
        startAt: at(0),
        isAllDay: true,
      );
      await useDays(tester, 3);
      await hover(tester, find.byKey(ValueKey('allday-$id')));
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Start'));
        await Future<void>.delayed(const Duration(milliseconds: 250));
      });
      await settle(tester);

      final r = await row(tester, id);
      expect(r.isAllDay, isFalse);
      final s = dateTimeFromDb(r.startAt)!;
      expect(
        s.difference(DateTime.now().toUtc()).abs() < const Duration(minutes: 1),
        isTrue,
      );
      expect(dateTimeFromDb(r.endAt)!.difference(s), const Duration(hours: 1));
      expect(find.byKey(ValueKey('allday-$id')), findsNothing);
      expect(find.byKey(ValueKey('event-$id')), findsOneWidget);
      final running = await tester.runAsync(
        () => (db.select(
          db.actionOccurrencesTable,
        )..where((t) => t.actionId.equals(id) & t.finishedAt.isNull())).get(),
      );
      expect(running, hasLength(1));
      await finish(tester);
    });

    testWidgets('dragging a chip into the grid schedules it; Undo reverts', (
      tester,
    ) async {
      await pump(tester);
      final id = await create(
        tester,
        name: 'Holiday',
        startAt: at(0),
        isAllDay: true,
      );
      await useDays(tester, 3);
      final ppm = pxPerMinute(tester);
      final from = tester.getCenter(find.byKey(ValueKey('allday-$id')));

      // 14:03 on tomorrow's column snaps to 14:00.
      await dragTo(
        tester,
        from + const Offset(20, 0),
        Offset(colX(1), lineY(tester, 14) + 3 * ppm),
        during: () async {
          expect(find.byKey(const ValueKey('chip-ghost')), findsOneWidget);
          expect(
            find.descendant(
              of: find.byKey(const ValueKey('chip-ghost')),
              matching: find.text('14:00 – 15:00'),
            ),
            findsOneWidget,
          );
        },
      );
      expect(find.byKey(const ValueKey('chip-ghost')), findsNothing);
      var r = await row(tester, id);
      const day = Duration(days: 1);
      expect(r.isAllDay, isFalse);
      expect(dateTimeFromDb(r.startAt), at(14).add(day));
      expect(dateTimeFromDb(r.endAt), at(15).add(day));
      expect(find.byKey(ValueKey('event-$id')), findsOneWidget);

      await tapUndo(tester);
      r = await row(tester, id);
      expect(r.isAllDay, isTrue);
      expect(dateTimeFromDb(r.startAt), at(0));
      await finish(tester);
    });

    testWidgets('a chip dropped outside the grid changes nothing', (
      tester,
    ) async {
      await pump(tester);
      final id = await create(tester, startAt: at(0), isAllDay: true);
      await useDays(tester, 3);
      final from = tester.getCenter(find.byKey(ValueKey('allday-$id')));
      // Dropped on the hour gutter, left of the day columns.
      await dragTo(tester, from, Offset(20, lineY(tester, 14)));
      final r = await row(tester, id);
      expect(r.isAllDay, isTrue);
      expect(dateTimeFromDb(r.startAt), at(0));
      await finish(tester);
    });

    testWidgets('dragging a timed block onto a strip cell makes it all-day', (
      tester,
    ) async {
      await pump(tester);
      final id = await create(tester, startAt: at(10), endAt: at(11));
      await useDays(tester, 3);
      Color? cellColor(int i) =>
          (tester
                      .widget<Container>(
                        find.byKey(ValueKey('strip-cell-$i')),
                      )
                      .decoration
                  as BoxDecoration)
              .color;
      expect(cellColor(2), isNull);

      await dragTo(
        tester,
        tester.getCenter(find.byKey(ValueKey('event-$id'))),
        tester.getCenter(find.byKey(const ValueKey('strip-cell-2'))),
        during: () async {
          expect(cellColor(2), isNotNull, reason: 'target cell highlighted');
          expect(cellColor(1), isNull);
          expect(find.byKey(const ValueKey('drag-ghost')), findsNothing);
        },
      );
      expect(cellColor(2), isNull);
      var r = await row(tester, id);
      const days2 = Duration(days: 2);
      expect(r.isAllDay, isTrue);
      expect(dateTimeFromDb(r.startAt), at(0).add(days2));
      expect(r.endAt, isNull);
      expect(find.byKey(ValueKey('allday-$id')), findsOneWidget);

      await tapUndo(tester);
      r = await row(tester, id);
      expect(r.isAllDay, isFalse);
      expect(dateTimeFromDb(r.startAt), at(10));
      expect(dateTimeFromDb(r.endAt), at(11));
      await finish(tester);
    });
  });

  group('G1 calendar fixes', () {
    int dayCount() => container.read(calendarDayCountProvider);

    Finder gridScroll() => find.byType(SingleChildScrollView).last;

    ScrollPosition gridPosition(WidgetTester tester) => tester
        .state<ScrollableState>(
          find.descendant(of: gridScroll(), matching: find.byType(Scrollable)),
        )
        .position;

    testWidgets('keys 2-7 and the numpad set the day count', (tester) async {
      await pump(tester);
      await settle(tester);
      expect(dayCount(), 7);
      final keys = [
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit5,
        LogicalKeyboardKey.digit6,
        LogicalKeyboardKey.digit7,
      ];
      for (var n = 2; n <= 7; n++) {
        await tester.sendKeyEvent(keys[n - 2]);
        await tester.pump();
        expect(dayCount(), n, reason: 'digit $n');
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.numpad4);
      await tester.pump();
      expect(dayCount(), 4);
      await tester.sendKeyEvent(LogicalKeyboardKey.numpad7);
      await tester.pump();
      expect(dayCount(), 7);
      await unmount(tester);
    });

    testWidgets('an event expands over lanes that are free (D is 2/3 wide)', (
      tester,
    ) async {
      await pump(tester);
      final a = await create(tester, name: 'A', startAt: at(8), endAt: at(22));
      final b = await create(
        tester,
        name: 'B',
        startAt: at(8, 30),
        endAt: at(9, 10),
      );
      final c = await create(tester, name: 'C', startAt: at(9), endAt: at(10));
      final d = await create(
        tester,
        name: 'D',
        startAt: at(10, 10),
        endAt: at(11),
      );
      await useDays(tester, 3);
      final dayW = tester.getSize(find.byKey(const ValueKey('day-header-0'))).width;
      double width(String id) =>
          tester.getSize(find.byKey(ValueKey('event-$id'))).width;
      double left(String id) =>
          tester.getTopLeft(find.byKey(ValueKey('event-$id'))).dx;
      expect(width(a), closeTo(dayW / 3 - 2, 0.5));
      expect(width(b), closeTo(dayW / 3 - 2, 0.5));
      expect(width(c), closeTo(dayW / 3 - 2, 0.5));
      expect(width(d), closeTo(dayW * 2 / 3 - 2, 0.5));
      expect(left(d), closeTo(left(b), 0.5));
      await unmount(tester);
    });

    testWidgets('event text is 9 px (name) and 8 px (time)', (tester) async {
      await pump(tester);
      final id = await create(tester, startAt: at(10), endAt: at(12));
      await useDays(tester, 3);
      final rich = tester.widget<RichText>(
        find.descendant(
          of: find.byKey(ValueKey('event-$id')),
          matching: find.byType(RichText),
        ),
      );
      // Text wraps our span in the default style's span.
      final root = (rich.text as TextSpan).children!.first as TextSpan;
      expect(root.style!.fontSize, 9);
      expect((root.children!.last as TextSpan).style!.fontSize, 8);
      await unmount(tester);
    });

    testWidgets('resizing the bottom edge sideways crosses into the next day', (
      tester,
    ) async {
      await pump(tester);
      final id = await create(tester, startAt: at(10), endAt: at(11));
      await useDays(tester, 3);
      final block = find.byKey(ValueKey('event-$id'));
      final dayW = (1400 - 56) / 3;
      await dragBy(
        tester,
        block,
        Offset(30, tester.getSize(block).height - 2),
        Offset(dayW, 20 * pxPerMinute(tester)),
      );
      final r = await row(tester, id);
      expect(dateTimeFromDb(r.startAt), at(10));
      expect(
        dateTimeFromDb(r.endAt),
        at(11, 20).add(const Duration(days: 1)),
      );
      await unmount(tester);
    });

    testWidgets('resizing the top edge sideways crosses into the day before', (
      tester,
    ) async {
      await pump(tester);
      final tomorrow = const Duration(days: 1);
      final id = await create(
        tester,
        startAt: at(10).add(tomorrow),
        endAt: at(11).add(tomorrow),
      );
      await useDays(tester, 3);
      final dayW = (1400 - 56) / 3;
      await dragBy(
        tester,
        find.byKey(ValueKey('event-$id')),
        const Offset(30, 2),
        Offset(-dayW, 0),
      );
      final r = await row(tester, id);
      expect(dateTimeFromDb(r.startAt), at(10));
      expect(dateTimeFromDb(r.endAt), at(11).add(tomorrow));
      await unmount(tester);
    });

    testWidgets('a cross-day resize draws one ghost per day slice', (
      tester,
    ) async {
      await pump(tester);
      final id = await create(tester, startAt: at(22), endAt: at(23));
      await useDays(tester, 3);
      final block = find.byKey(ValueKey('event-$id'));
      final dayW = (1400 - 56) / 3;
      final g = await tester.startGesture(
        tester.getBottomLeft(block) + const Offset(30, -2),
        kind: PointerDeviceKind.mouse,
      );
      await g.moveBy(const Offset(0, 1));
      await tester.pump();
      await g.moveBy(Offset(dayW, 120 * pxPerMinute(tester)));
      await tester.pump();
      // Ends 01:00 two days on (the old 23:00 end + 1 day + 2 h): 22:00-24:00
      // today, all of tomorrow, and 00:00-01:00 the day after.
      expect(find.byKey(const ValueKey('drag-ghost')), findsOneWidget);
      expect(find.byKey(const ValueKey('drag-ghost-d1')), findsOneWidget);
      expect(find.byKey(const ValueKey('drag-ghost-d2')), findsOneWidget);
      await tester.runAsync(() async {
        await g.up();
        await Future<void>.delayed(const Duration(milliseconds: 250));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final r = await row(tester, id);
      expect(
        dateTimeFromDb(r.endAt),
        at(1).add(const Duration(days: 2)),
      );
      await tester.pump(const Duration(seconds: 6));
      await unmount(tester);
    });

    testWidgets('Today scrolls the now-line to the viewport centre', (
      tester,
    ) async {
      await pump(tester);
      container.read(calendarVisibleHoursProvider.notifier).state = 6;
      await settle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await settle(tester);
      final position = gridPosition(tester);
      position.jumpTo(0);
      await tester.pump();

      await tester.tap(find.text('Today'));
      await tester.pump();
      await tester.pump();
      await settle(tester);

      final viewport = tester.getSize(gridScroll()).height;
      final px = pxPerMinute(tester);
      final now = minutesOfDay(DateTime.now().toUtc());
      final target = (now * px - viewport / 2).clamp(
        0.0,
        position.maxScrollExtent,
      );
      expect(position.pixels, closeTo(target, px * 2 + 1));
      await unmount(tester);
    });

    testWidgets('hover toolbar hides while the event top is above the viewport', (
      tester,
    ) async {
      await pump(tester);
      container.read(calendarVisibleHoursProvider.notifier).state = 6;
      final id = await create(tester, startAt: at(3), endAt: at(8));
      await useDays(tester, 3);
      final position = gridPosition(tester);
      final px = pxPerMinute(tester);

      position.jumpTo(2 * 60 * px);
      await tester.pump();
      final block = find.byKey(ValueKey('event-$id'));
      await hover(tester, block);
      expect(find.byTooltip('Start'), findsOneWidget);

      // Half an hour of the block's top is now scrolled out; the pointer is
      // still over the block, but the bar would float over the header.
      position.jumpTo(3.5 * 60 * px);
      await tester.pump();
      await tester.pump();
      expect(find.byTooltip('Start'), findsNothing);

      // Scrolling back brings it back (re-evaluated while scrolling).
      position.jumpTo(2 * 60 * px);
      await tester.pump();
      await tester.pump();
      expect(find.byTooltip('Start'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('event block drawing cost', () {
    int countDescendants(Finder block) => find
        .descendant(of: block, matching: find.byWidgetPredicate((_) => true))
        .evaluate()
        .length;

    testWidgets('a tall block: one paragraph, no Opacity, no ClipRect', (
      tester,
    ) async {
      await pump(tester);
      final id = await create(tester, startAt: at(10), endAt: at(13));
      await useDays(tester, 3);
      final block = find.byKey(ValueKey('event-$id'));
      // ignore: avoid_print
      print('BLOCK WIDGETS (tall): ${countDescendants(block)}');
      expect(
        find.descendant(of: block, matching: find.byType(RichText)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: block, matching: find.textContaining('Alpha')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: block,
          matching: find.textContaining('10:00–13:00'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: block, matching: find.byType(Opacity)),
        findsNothing,
      );
      expect(
        find.descendant(of: block, matching: find.byType(ClipRect)),
        findsNothing,
      );
      expect(
        find.descendant(of: block, matching: find.byType(OverflowBox)),
        findsNothing,
      );
      expect(countDescendants(block), lessThanOrEqualTo(17));
      await unmount(tester);
    });

    testWidgets('a long title keeps two lines plus its own time line', (
      tester,
    ) async {
      await pump(tester);
      final id = await create(
        tester,
        name: List.filled(40, 'longword').join(' '),
        startAt: at(10),
        endAt: at(13),
      );
      await useDays(tester, 3);
      final block = find.byKey(ValueKey('event-$id'));
      expect(
        find.descendant(of: block, matching: find.text('10:00–13:00')),
        findsOneWidget,
      );
      await unmount(tester);
    });

    testWidgets('the dragged block (only) gets an Opacity', (tester) async {
      await pump(tester);
      final id = await create(tester, startAt: at(10), endAt: at(12));
      final other = await create(
        tester,
        name: 'Beta',
        startAt: at(14),
        endAt: at(15),
      );
      await useDays(tester, 3);
      final block = find.byKey(ValueKey('event-$id'));
      final g = await tester.startGesture(
        tester.getCenter(block),
        kind: PointerDeviceKind.mouse,
      );
      await g.moveBy(const Offset(0, 1));
      await tester.pump();
      await g.moveBy(const Offset(0, 20));
      await tester.pump();
      expect(
        find.descendant(of: block, matching: find.byType(Opacity)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(ValueKey('event-$other')),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );
      await tester.runAsync(() async {
        await g.up();
        await Future<void>.delayed(const Duration(milliseconds: 250));
      });
      await tester.pump(const Duration(milliseconds: 400));
      await unmount(tester);
    });

    testWidgets('resize cursor only in the top/bottom band', (tester) async {
      await pump(tester);
      final id = await create(tester, startAt: at(10), endAt: at(13));
      await useDays(tester, 3);
      final block = find.byKey(ValueKey('event-$id'));
      MouseCursor cursor() => tester
          .widget<MouseRegion>(
            find
                .descendant(
                  of: block,
                  matching: find.byWidgetPredicate(
                    (w) => w is MouseRegion && w.onHover != null,
                  ),
                )
                .first,
          )
          .cursor;
      final m = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await m.addPointer(location: const Offset(1, 1));
      addTearDown(m.removePointer);
      final tl = tester.getTopLeft(block);
      final size = tester.getSize(block);
      await m.moveTo(tl + Offset(size.width / 2, 2));
      await tester.pump();
      expect(cursor(), SystemMouseCursors.resizeUpDown);
      await m.moveTo(tl + Offset(size.width / 2, size.height / 2));
      await tester.pump();
      expect(cursor(), SystemMouseCursors.click);
      await m.moveTo(tl + Offset(size.width / 2, size.height - 2));
      await tester.pump();
      expect(cursor(), SystemMouseCursors.resizeUpDown);
      await m.moveTo(tl + Offset(size.width / 2, size.height / 2));
      await tester.pump();
      expect(cursor(), SystemMouseCursors.click);
      await unmount(tester);
    });
  });
}
