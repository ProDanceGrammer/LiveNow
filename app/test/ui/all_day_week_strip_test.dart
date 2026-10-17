import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/local_time.dart';
import 'package:livenow/core/time_codec.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/all_day_postpone.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/all_day_week.dart';
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/screens/settings_screen.dart';
import 'package:livenow/ui/sync_providers.dart' show SyncRole, syncRoleProvider;
import 'package:livenow/ui/views/all_day_week_strip.dart';
import 'package:livenow/ui/views/calendar_layout.dart' show calendarAnchorStart;
import 'package:livenow/ui/views/current_actions_view.dart';

/// The week strip of all-day actions above the Current Actions board.
void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late ActionService service;
  late ProviderContainer container;

  /// Local midnight (UTC instant) of day [i] (0 = Monday) of the CURRENT week.
  DateTime day(int i) =>
      calendarAddDays(calendarAnchorStart(DateTime.now().toUtc(), 7), i);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    resetStackedDialogsForTest();
    await tester.pump(const Duration(seconds: 6)); // the Undo toast's timer
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(1400, 900),
    Future<void> Function()? seed,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    service = ActionService(db);
    if (seed != null) await seed();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: Scaffold(body: CurrentActionsView())),
      ),
    );
    container = ProviderScope.containerOf(
      tester.element(find.byType(CurrentActionsView)),
    );
    await settle(tester);
  }

  Finder card(String id) => find.byKey(ValueKey('allday-card-$id'));
  Finder column(int i) => find.byKey(ValueKey('allday-strip-col-$i'));

  Future<DateTime?> startOf(WidgetTester tester, String id) async {
    final row = await tester.runAsync(
      () => (db.select(db.actionsTable)..where((t) => t.id.equals(id))).getSingle(),
    );
    return dateTimeFromDb(row!.startAt);
  }

  testWidgets('each all-day card sits in its day column; timed actions are not in the strip', (
    tester,
  ) async {
    late String water, pills;
    await mount(
      tester,
      seed: () async {
        water = (await service.createAction(
          name: 'Drink water',
          isAllDay: true,
          startAt: day(1),
        ));
        pills = (await service.createAction(
          name: 'Take pills',
          isAllDay: true,
          startAt: day(4),
        ));
        await service.createAction(
          name: 'A timed one',
          startAt: day(2).add(const Duration(hours: 10)),
          endAt: day(2).add(const Duration(hours: 11)),
        );
      },
    );

    expect(find.byKey(kAllDayStripKey), findsOneWidget);
    expect(
      find.descendant(of: column(1), matching: card(water)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: column(4), matching: card(pills)),
      findsOneWidget,
    );
    // The timed action is on the board (in one of its two columns), never in a
    // strip column.
    expect(find.text('A timed one'), findsOneWidget);
    for (var i = 0; i < 7; i++) {
      expect(
        find.descendant(of: column(i), matching: find.text('A timed one')),
        findsNothing,
      );
    }
    // Seven day names, Monday first.
    expect(find.textContaining('Mon '), findsWidgets);
    for (var i = 0; i < 7; i++) {
      expect(find.byKey(ValueKey('allday-strip-day-$i')), findsOneWidget);
    }
    await unmount(tester);
  });

  testWidgets('today is highlighted', (tester) async {
    await mount(tester);
    final today = localDayStart(DateTime.now().toUtc());
    for (var i = 0; i < 7; i++) {
      final box = tester.widget<Container>(
        find.byKey(ValueKey('allday-strip-day-$i')),
      );
      final colored = (box.decoration as BoxDecoration).color != null;
      expect(colored, day(i) == today, reason: 'day $i');
    }
    await unmount(tester);
  });

  testWidgets('thin grid lines separate the columns and the day names from the cards', (
    tester,
  ) async {
    await mount(
      tester,
      seed: () async {
        await service.createAction(
          name: 'Drink water',
          isAllDay: true,
          startAt: day(1),
        );
      },
    );
    // Six lines between seven columns, in the day names and in the card area.
    for (var i = 1; i < 7; i++) {
      expect(find.byKey(ValueKey('allday-strip-vline-head-$i')), findsOneWidget);
      expect(find.byKey(ValueKey('allday-strip-vline-$i')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('allday-strip-vline-head-0')), findsNothing);
    // One line under the day names, above the cards.
    final rule = find.byKey(const ValueKey('allday-strip-hline'));
    expect(rule, findsOneWidget);
    final names = tester.getBottomLeft(find.byKey(const ValueKey('allday-strip-day-0')));
    final firstCard = tester.getTopLeft(
      find.descendant(of: column(1), matching: find.byType(Material)).first,
    );
    expect(tester.getTopLeft(rule).dy, greaterThanOrEqualTo(names.dy));
    expect(tester.getTopLeft(rule).dy, lessThan(firstCard.dy));
    // Thin: one pixel.
    expect(tester.getSize(rule).height, 1);
    expect(tester.getSize(find.byKey(const ValueKey('allday-strip-vline-3'))).width, 1);
    // The column lines run the full height of the card area, also beside an
    // empty column (day 5 has no card).
    expect(
      tester.getSize(find.byKey(const ValueKey('allday-strip-vline-5'))).height,
      greaterThan(30),
    );
    await unmount(tester);
  });

  testWidgets('the columns line up: a column line sits between the same two day names', (
    tester,
  ) async {
    await mount(
      tester,
      seed: () async {
        await service.createAction(
          name: 'Drink water',
          isAllDay: true,
          startAt: day(0),
        );
      },
    );
    for (var i = 1; i < 7; i++) {
      final head = tester.getCenter(find.byKey(ValueKey('allday-strip-vline-head-$i'))).dx;
      final body = tester.getCenter(find.byKey(ValueKey('allday-strip-vline-$i'))).dx;
      expect((head - body).abs(), lessThan(0.5), reason: 'line $i');
    }
    await unmount(tester);
  });

  testWidgets('an empty week has the day names but no rule and no column lines in the body', (
    tester,
  ) async {
    await mount(tester);
    expect(find.byKey(const ValueKey('allday-strip-hline')), findsNothing);
    expect(find.byKey(const ValueKey('allday-strip-vline-3')), findsNothing);
    await unmount(tester);
  });

  testWidgets('done cards are hidden by default; the eye and the setting show them', (
    tester,
  ) async {
    late String open, finished;
    await mount(
      tester,
      seed: () async {
        open = await service.createAction(
          name: 'Open one',
          isAllDay: true,
          startAt: day(2),
        );
        finished = await service.createAction(
          name: 'Done one',
          isAllDay: true,
          startAt: day(2),
        );
        await service.toggleDone(finished);
      },
    );
    expect(card(open), findsOneWidget);
    expect(card(finished), findsNothing);
    expect(container.read(showDoneAllDayProvider), isFalse);

    await tester.tap(find.byKey(const ValueKey('allday-strip-eye')));
    await settle(tester);
    expect(container.read(showDoneAllDayProvider), isTrue);
    expect(card(finished), findsOneWidget);
    expect(card(open), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('allday-strip-eye')));
    await settle(tester);
    expect(container.read(showDoneAllDayProvider), isFalse);
    expect(card(finished), findsNothing);
    await unmount(tester);
  });

  testWidgets('ticking Done removes the card, Undo brings it back', (tester) async {
    late String id;
    await mount(
      tester,
      seed: () async {
        id = await service.createAction(
          name: 'Drink water',
          isAllDay: true,
          startAt: day(3),
        );
      },
    );
    expect(card(id), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('allday-card-check-$id')));
    await settle(tester);
    expect(card(id), findsNothing); // done cards disappear by default

    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(card(id), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('with "show done" a ticked card stays, struck through', (tester) async {
    late String id;
    await mount(
      tester,
      seed: () async {
        id = await service.createAction(
          name: 'Drink water',
          isAllDay: true,
          startAt: day(3),
        );
      },
    );
    await tester.tap(find.byKey(const ValueKey('allday-strip-eye')));
    await settle(tester);
    await tester.tap(find.byKey(ValueKey('allday-card-check-$id')));
    await settle(tester);

    expect(card(id), findsOneWidget);
    final text = tester.widget<Text>(
      find.descendant(of: card(id), matching: find.text('Drink water')),
    );
    expect(text.style?.decoration, TextDecoration.lineThrough);
    await unmount(tester);
  });

  Future<TestGesture> hover(WidgetTester tester, Finder target) async {
    final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await g.addPointer(location: const Offset(5, 5));
    addTearDown(g.removePointer);
    await g.moveTo(tester.getCenter(target));
    await tester.pump();
    await g.moveBy(const Offset(1, 1));
    await tester.pump();
    return g;
  }

  testWidgets('hovering shows the two buttons; To Monday moves the card, Undo restores it', (
    tester,
  ) async {
    late String id;
    await mount(
      tester,
      seed: () async {
        id = await service.createAction(
          name: 'Drink water',
          isAllDay: true,
          startAt: day(2), // Wednesday
        );
      },
    );
    expect(find.byKey(ValueKey('allday-card-monday-$id')), findsNothing);
    final original = await startOf(tester, id);

    await hover(tester, card(id));
    expect(find.byKey(ValueKey('allday-card-monday-$id')), findsOneWidget);
    expect(find.byKey(ValueKey('allday-card-week-$id')), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('allday-card-monday-$id')));
    await settle(tester);

    // (Compared as instants: a TZDateTime never equals a plain DateTime.)
    final moved = (await startOf(tester, id))!.millisecondsSinceEpoch;
    expect(moved, allDayToMonday(original!).millisecondsSinceEpoch);
    expect(
      moved,
      day(0).add(const Duration(days: 7)).millisecondsSinceEpoch, // next Monday
    );
    expect(card(id), findsNothing); // it left this week

    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(await startOf(tester, id), original);
    expect(card(id), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('+7 days moves the card a week, still all-day, and keeps a done tick', (
    tester,
  ) async {
    late String id;
    await mount(
      tester,
      seed: () async {
        id = await service.createAction(
          name: 'Drink water',
          isAllDay: true,
          startAt: day(1),
        );
      },
    );
    final original = await startOf(tester, id);

    await hover(tester, card(id));
    await tester.tap(find.byKey(ValueKey('allday-card-week-$id')));
    await settle(tester);

    final row = (await tester.runAsync(
      () => (db.select(db.actionsTable)..where((t) => t.id.equals(id))).getSingle(),
    ))!;
    expect(dateTimeFromDb(row.startAt), original!.add(const Duration(days: 7)));
    expect(row.isAllDay, isTrue);
    expect(row.endAt, isNull);
    expect(card(id), findsNothing);

    // Next week it is there.
    await tester.tap(find.byKey(const ValueKey('allday-strip-next')));
    await settle(tester);
    expect(
      find.descendant(of: column(1), matching: card(id)),
      findsOneWidget,
    );
    await unmount(tester);
  });

  testWidgets('the arrows change the week and Today comes back', (tester) async {
    late String id;
    await mount(
      tester,
      seed: () async {
        id = await service.createAction(
          name: 'Drink water',
          isAllDay: true,
          startAt: day(1),
        );
      },
    );
    final label = tester.widget<Text>(find.byKey(const ValueKey('allday-strip-label')));
    final thisWeek = label.data;
    expect(card(id), findsOneWidget);
    // "Today" is disabled on the current week.
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('allday-strip-today')))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const ValueKey('allday-strip-next')));
    await settle(tester);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('allday-strip-label'))).data,
      isNot(thisWeek),
    );
    expect(card(id), findsNothing);
    expect(container.read(allDayStripWeekOffsetProvider), 1);

    await tester.tap(find.byKey(const ValueKey('allday-strip-prev')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('allday-strip-prev')));
    await settle(tester);
    expect(container.read(allDayStripWeekOffsetProvider), -1);

    await tester.tap(find.byKey(const ValueKey('allday-strip-today')));
    await settle(tester);
    expect(container.read(allDayStripWeekOffsetProvider), 0);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('allday-strip-label'))).data,
      thisWeek,
    );
    expect(card(id), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('an earlier week\'s not-done action is not in this week\'s strip', (
    tester,
  ) async {
    late String id;
    await mount(
      tester,
      seed: () async {
        id = await service.createAction(
          name: 'Last week',
          isAllDay: true,
          startAt: day(-3), // the Friday before
        );
      },
    );
    expect(card(id), findsNothing);
    await unmount(tester);
  });

  testWidgets('with nothing to show the strip is only a thin row', (tester) async {
    await mount(tester);
    final size = tester.getSize(find.byKey(kAllDayStripKey));
    expect(size.height, lessThan(110));
    expect(find.byKey(const ValueKey('allday-strip-label')), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('many cards stay inside the height cap and scroll, nothing overflows', (
    tester,
  ) async {
    await mount(
      tester,
      size: const Size(1400, 700),
      seed: () async {
        for (var i = 0; i < 40; i++) {
          await service.createAction(
            name: 'Card $i',
            isAllDay: true,
            startAt: day(1),
          );
        }
      },
    );
    final strip = tester.getSize(find.byKey(kAllDayStripKey));
    expect(strip.height, lessThan(700 * 0.4));
    // The Current board below still has most of the window.
    expect(find.text('Not Done Yet'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('the Settings switch is the same choice as the eye button', (tester) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          syncRoleProvider.overrideWithValue(SyncRole.client),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await settle(tester);
    container = ProviderScope.containerOf(tester.element(find.byType(SettingsScreen)));

    final tile = find.byKey(const ValueKey('settings-show-done-all-day'));
    await tester.ensureVisible(tile);
    await tester.pump();
    expect(tester.widget<SwitchListTile>(tile).value, isFalse); // off by default
    expect(container.read(showDoneAllDayProvider), isFalse);

    await tester.tap(tile);
    await settle(tester);
    expect(container.read(showDoneAllDayProvider), isTrue);
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);

    await tester.tap(tile);
    await settle(tester);
    expect(container.read(showDoneAllDayProvider), isFalse);
    await unmount(tester);
  });

  group('phone', () {
    testWidgets('one list per day (days without cards are left out); long-press offers both postpones', (
      tester,
    ) async {
      late String id;
      await mount(
        tester,
        size: const Size(375, 812),
        seed: () async {
          id = await service.createAction(
            name: 'Drink water',
            isAllDay: true,
            startAt: day(2),
          );
        },
      );
      expect(find.byKey(const ValueKey('allday-strip-day-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('allday-strip-day-3')), findsNothing);
      expect(card(id), findsOneWidget);
      final original = await startOf(tester, id);

      await tester.longPress(card(id));
      await settle(tester);
      expect(find.byKey(const ValueKey('allday-menu-monday')), findsOneWidget);
      expect(find.byKey(const ValueKey('allday-menu-week')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('allday-menu-week')));
      await settle(tester);
      expect(
        await startOf(tester, id),
        original!.add(const Duration(days: 7)),
      );
      await unmount(tester);
    });

    testWidgets('a thin line separates one day from the next', (tester) async {
      await mount(
        tester,
        size: const Size(375, 812),
        seed: () async {
          await service.createAction(name: 'A', isAllDay: true, startAt: day(1));
          await service.createAction(name: 'B', isAllDay: true, startAt: day(4));
        },
      );
      // No line before the first day, one before the second.
      expect(find.byKey(const ValueKey('allday-strip-hline-1')), findsNothing);
      expect(find.byKey(const ValueKey('allday-strip-hline-4')), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('the header folds the strip away and unfolds it', (tester) async {
      late String id;
      await mount(
        tester,
        size: const Size(375, 812),
        seed: () async {
          id = await service.createAction(
            name: 'Drink water',
            isAllDay: true,
            startAt: day(2),
          );
        },
      );
      expect(card(id), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('allday-strip-toggle')));
      await settle(tester);
      expect(card(id), findsNothing);
      expect(container.read(allDayStripOpenProvider), isFalse);

      await tester.tap(find.byKey(const ValueKey('allday-strip-toggle')));
      await settle(tester);
      expect(card(id), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('the tick works on a phone too', (tester) async {
      late String id;
      await mount(
        tester,
        size: const Size(375, 812),
        seed: () async {
          id = await service.createAction(
            name: 'Drink water',
            isAllDay: true,
            startAt: day(0),
          );
        },
      );
      await tester.tap(find.byKey(ValueKey('allday-card-check-$id')));
      await settle(tester);
      expect(card(id), findsNothing);
      final row = (await tester.runAsync(
        () => (db.select(db.actionsTable)..where((t) => t.id.equals(id))).getSingle(),
      ))!;
      expect(row.done, isTrue);
      await unmount(tester);
    });
  });
}

