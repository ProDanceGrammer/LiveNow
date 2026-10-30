import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/ids.dart';
import 'package:livenow/core/time_codec.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/plan_rules.dart';
import 'package:livenow/domain/plan_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/calendar_allday.dart';
import 'package:livenow/ui/dialog_stack.dart' show resetStackedDialogsForTest;
import 'package:livenow/ui/plan_providers.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/views/calendar_view.dart';
import 'package:livenow/ui/views/plan_ghost_layer.dart' show kPlanFasterColor;
import 'package:livenow/ui/widgets/plan_dialogs.dart' show PlanItemEditorDialog;

/// Planning mode on the calendar: the toggle shows one translucent block per
/// plan occurrence, dragging one asks "this day only / whole pattern", and the
/// confirm dialog turns the plan into real actions.
void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late ProviderContainer container;

  Finder ghosts() => find.byWidgetPredicate((w) {
    final k = w.key;
    return k is ValueKey<String> &&
        k.value.startsWith('plan-ghost-') &&
        !k.value.startsWith('plan-ghost-handle-');
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<String> mount(
    WidgetTester tester, {
    Future<void> Function(PlanService plans)? seed,
    int hours = 24,
  }) async {
    tester.view.physicalSize = const Size(1400, 1700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    // Seed BEFORE mounting: writes in runAsync while streams are live deadlock.
    final plans = PlanService(db, ActionService(db));
    final today = planDateOf(DateTime.now());
    final id = (await tester.runAsync(
      () => plans.saveItem(
        PlanItemInput(
          name: 'Run',
          kind: PlanKind.cycle,
          startDate: today.subtract(const Duration(days: 30)),
          cycle: const CycleRule(
            cycleDays: 1,
            occurrences: [
              CycleOccurrence(day: 0, startMin: 22 * 60, durationMin: 60),
            ],
          ),
        ),
      ),
    ))!;
    if (seed != null) await tester.runAsync(() => seed(plans));
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
    return id;
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('the toggle shows one ghost per occurrence and hides them', (
    tester,
  ) async {
    await mount(tester);
    expect(ghosts(), findsNothing);
    expect(find.byKey(const ValueKey('calendar-plan-bar')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('calendar-planning-toggle')));
    await settle(tester);
    expect(container.read(calendarPlanningProvider), isTrue);
    expect(ghosts(), findsNWidgets(7));
    expect(find.byKey(const ValueKey('calendar-plan-bar')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('calendar-planning-toggle')));
    await settle(tester);
    expect(ghosts(), findsNothing);
    await unmount(tester);
  });

  /// A finished run of [minutes] that ended yesterday (so it is in the 30-day
  /// window); `db` exists once `mount` has started seeding.
  Future<void> finishedRun(String name, int minutes) async {
    final end = DateTime.now().toUtc().subtract(const Duration(days: 1));
    final start = end.subtract(Duration(minutes: minutes));
    await db.into(db.actionsTable).insert(
      ActionsTableCompanion.insert(
        id: newId(),
        name: name,
        createdAt: dateTimeToDb(start)!,
        updatedAt: dateTimeToDb(end)!,
        done: const Value(true),
        startAt: Value(dateTimeToDb(start)),
        endAt: Value(dateTimeToDb(end)),
        completedAt: Value(dateTimeToDb(end)),
      ),
    );
  }

  Color ghostFill(WidgetTester tester) {
    final box = tester.widget<DecoratedBox>(
      find
          .descendant(of: ghosts().first, matching: find.byType(DecoratedBox))
          .first,
    );
    return (box.decoration as BoxDecoration).color!;
  }

  String ghostText(WidgetTester tester) => tester
      .widget<Text>(
        find.descendant(of: ghosts().first, matching: find.byType(Text)).first,
      )
      .data!;

  testWidgets('a block whose average is longer is red and shows the average', (
    tester,
  ) async {
    await mount(tester, seed: (_) => finishedRun('Run', 90));
    await tester.tap(find.byKey(const ValueKey('calendar-planning-toggle')));
    await settle(tester);
    await settle(tester);
    final error = Theme.of(tester.element(ghosts().first)).colorScheme.error;
    expect(ghostFill(tester), error.withValues(alpha: 0.16));
    expect(ghostText(tester), contains('⌀ 1 hour 30 min'));
    await unmount(tester);
  });

  testWidgets('a block whose average is shorter is green', (tester) async {
    await mount(tester, seed: (_) => finishedRun('Run', 30));
    await tester.tap(find.byKey(const ValueKey('calendar-planning-toggle')));
    await settle(tester);
    await settle(tester);
    expect(ghostFill(tester), kPlanFasterColor.withValues(alpha: 0.16));
    expect(ghostText(tester), contains('⌀ 30 min'));
    await unmount(tester);
  });

  testWidgets('no history: the old tint and no average text', (tester) async {
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('calendar-planning-toggle')));
    await settle(tester);
    final tertiary = Theme.of(tester.element(ghosts().first)).colorScheme.tertiary;
    expect(ghostFill(tester), tertiary.withValues(alpha: 0.16));
    expect(ghostText(tester), isNot(contains('⌀')));
    await unmount(tester);
  });

  testWidgets('dragging a ghost: "this day only" writes an override', (
    tester,
  ) async {
    final id = await mount(tester);
    await tester.tap(find.byKey(const ValueKey('calendar-planning-toggle')));
    await settle(tester);

    final first = ghosts().first;
    final g = await tester.startGesture(
      tester.getCenter(first),
      kind: PointerDeviceKind.mouse,
    );
    await g.moveBy(const Offset(0, 1));
    await tester.pump();
    // The ghost is one hour long: move it one ghost-height up.
    final hour = tester.getSize(first).height;
    await g.moveBy(Offset(0, -hour));
    await tester.pump();
    await g.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const ValueKey('plan-scope-day')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('plan-scope-day')));
    await settle(tester);

    final overrides = (await tester.runAsync(
      () => db.select(db.planOverridesTable).get(),
    ))!;
    expect(overrides, hasLength(1));
    expect(overrides.single.planItemId, id);
    expect(overrides.single.startMin, 21 * 60);
    await unmount(tester);
  });

  Future<String> lunchSeed(PlanService plans, {String name = 'Lunch'}) =>
      plans.saveItem(
        PlanItemInput(
          name: name,
          kind: PlanKind.cycle,
          startDate: planDateOf(DateTime.now()).subtract(const Duration(days: 30)),
          cycle: const CycleRule(
            cycleDays: 1,
            occurrences: [
              // 11:35-12:05: off the 10-minute grid on purpose.
              CycleOccurrence(day: 0, startMin: 11 * 60 + 35, durationMin: 30),
            ],
          ),
        ),
      );

  /// Drags the first ghost of the plan item [id] from its place to 12:05 (the end
  /// of the 'Lunch' item), with the given mouse [buttons], then chooses
  /// "whole pattern" and returns the saved start minute of that item.
  Future<int> dragRunTo1205(
    WidgetTester tester,
    String id,
    int buttons,
  ) async {
    await tester.tap(find.byKey(const ValueKey('calendar-planning-toggle')));
    await settle(tester);
    final run = find.byWidgetPredicate(
      (w) => w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('plan-ghost-$id-') &&
          !(w.key! as ValueKey<String>).value.startsWith('plan-ghost-handle-'),
    ).first;
    final pxPerMin = tester.getSize(run).height / 60;
    final g = await tester.startGesture(
      tester.getCenter(run),
      kind: PointerDeviceKind.mouse,
      buttons: buttons,
    );
    await g.moveBy(const Offset(0, 1));
    await tester.pump();
    // From 22:00 up to 12:05 = 595 minutes.
    await g.moveBy(Offset(0, -595 * pxPerMin));
    await tester.pump();
    await g.up();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('plan-scope-all')));
    await settle(tester);
    final item = (await tester.runAsync(
      () => PlanService(db, ActionService(db)).items(),
    ))!.firstWhere((r) => r.id == id);
    return PlanService(db, ActionService(db))
        .decode(item)
        .cycle!
        .occurrences
        .single
        .startMin;
  }

  testWidgets('a right-button drag locks onto the edge of another plan block', (
    tester,
  ) async {
    final id = await mount(tester, seed: (p) => lunchSeed(p));
    // Lunch ends at 12:05: the dragged block's start snaps there (off the grid).
    expect(await dragRunTo1205(tester, id, kSecondaryMouseButton), 12 * 60 + 5);
    await unmount(tester);
  });

  testWidgets('a plain drag stays on the 10-minute grid', (tester) async {
    final id = await mount(tester, seed: (p) => lunchSeed(p));
    final start = await dragRunTo1205(tester, id, kPrimaryMouseButton);
    expect(start % 10, 0);
    await unmount(tester);
  });

  testWidgets('dragging a ghost: "whole pattern" changes the rule', (
    tester,
  ) async {
    final id = await mount(tester);
    await tester.tap(find.byKey(const ValueKey('calendar-planning-toggle')));
    await settle(tester);

    final first = ghosts().first;
    final hour = tester.getSize(first).height;
    final g = await tester.startGesture(
      tester.getCenter(first),
      kind: PointerDeviceKind.mouse,
    );
    await g.moveBy(const Offset(0, 1));
    await tester.pump();
    await g.moveBy(Offset(0, -hour));
    await tester.pump();
    await g.up();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('plan-scope-all')));
    await settle(tester);

    final item = (await tester.runAsync(
      () => PlanService(db, ActionService(db)).items(),
    ))!.firstWhere((r) => r.id == id);
    final data = PlanService(db, ActionService(db)).decode(item);
    expect(data.cycle!.occurrences.single.startMin, 21 * 60);
    await unmount(tester);
  });

  testWidgets('confirm plan creates real actions with one preview', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('calendar-planning-toggle')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('plan-bar-confirm')));
    await settle(tester);

    expect(find.byKey(const ValueKey('plan-confirm-preview')), findsOneWidget);
    final preview = tester
        .widget<Text>(find.byKey(const ValueKey('plan-confirm-preview')))
        .data!;
    expect(preview, contains('action(s) to create'));

    await tester.tap(find.byKey(const ValueKey('plan-confirm')));
    await settle(tester);
    final actions = (await tester.runAsync(
      () => db.select(db.actionsTable).get(),
    ))!;
    expect(actions, isNotEmpty);
    expect(actions.every((a) => a.planItemId != null), isTrue);
    // Confirming again finds nothing new.
    final again = (await tester.runAsync(
      () => PlanService(db, ActionService(db)).preview(
        from: planDateOf(DateTime.now()),
        to: planDateOf(DateTime.now()).add(const Duration(days: 13)),
      ),
    ))!;
    expect(again.toCreate, isEmpty);
    await unmount(tester);
  });

  testWidgets('confirm plan: a chosen first day moves the created actions', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('calendar-planning-toggle')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('plan-bar-confirm')));
    await settle(tester);

    // The first day: 20 days ahead (the picker's text field is not driven here;
    // its Next-month arrows would be slow), picked through the calendar grid.
    await tester.tap(find.byKey(const ValueKey('plan-first-day')));
    await tester.pumpAndSettle();
    final target = DateTime.now().add(const Duration(days: 20));
    final today = DateTime.now();
    final months =
        (target.year - today.year) * 12 + target.month - today.month;
    for (var i = 0; i < months; i++) {
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('${target.day}').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('plan-confirm')));
    await settle(tester);
    final actions = (await tester.runAsync(
      () => db.select(db.actionsTable).get(),
    ))!;
    expect(actions, isNotEmpty);
    final first = actions
        .map((a) => dateTimeFromDb(a.startAt)!.toLocal())
        .reduce((a, b) => a.isBefore(b) ? a : b);
    expect(first.isBefore(DateTime(target.year, target.month, target.day)), isFalse);
    await unmount(tester);
  });

  testWidgets('the editor saves a weekly item and a template for it', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('calendar-planning-toggle')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('plan-bar-add')));
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('plan-name')), 'Swim');
    await tester.tap(find.byKey(const ValueKey('plan-save')));
    await settle(tester);

    final items = (await tester.runAsync(
      () => db.select(db.planItemsTable).get(),
    ))!;
    final swim = items.firstWhere((r) => r.name == 'Swim');
    expect(swim.templateId, isNotNull);
    final templates = (await tester.runAsync(
      () => db.select(db.actionTemplatesTable).get(),
    ))!;
    expect(templates.any((t) => t.id == swim.templateId), isTrue);
    // The pattern starts on the date chosen (today), not on a Monday.
    expect(planDateFromKey(swim.startDate), planDateOf(DateTime.now()));
    await unmount(tester);
  });

  testWidgets('right click on a real action in planning mode offers a plan item', (
    tester,
  ) async {
    await mount(tester);
    final start = DateTime.now().toUtc();
    final day = DateTime.utc(start.year, start.month, start.day, 12);
    final id = (await tester.runAsync(
      () => ActionService(db).createAction(
        name: 'Piano',
        startAt: day,
        endAt: day.add(const Duration(minutes: 45)),
      ),
    ))!;
    // Not in planning mode yet: the pointer does nothing special.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          calendarVisibleHoursProvider.overrideWith((ref) => 24),
        ],
        child: const MaterialApp(home: Scaffold(body: CalendarView())),
      ),
    );
    await settle(tester);
    final block = find.byKey(ValueKey('event-$id'));
    expect(block, findsOneWidget);
    Future<void> rightClick() async {
      final g = await tester.startGesture(
        tester.getCenter(block),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await g.up();
      await settle(tester);
    }

    await rightClick();
    expect(find.byKey(const ValueKey('block-plan-from-action')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('calendar-planning-toggle')));
    await settle(tester);
    await rightClick();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('block-plan-from-action')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('block-plan-from-action')));
    await settle(tester);

    // The editor opens prefilled with the action's name, time and length.
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('plan-name'))).controller!.text,
      'Piano',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('plan-row-duration-0')))
          .controller!
          .text,
      '45',
    );
    await unmount(tester);
  });

  testWidgets('a plan item that crosses midnight shows on the next day too', (
    tester,
  ) async {
    await mount(
      tester,
      seed: (plans) async {
        await plans.saveItem(
          PlanItemInput(
            name: 'Sleep',
            kind: PlanKind.cycle,
            startDate: planDateOf(DateTime.now()).subtract(const Duration(days: 30)),
            cycle: const CycleRule(
              cycleDays: 1,
              occurrences: [
                CycleOccurrence(day: 0, startMin: 22 * 60, durationMin: 9 * 60),
              ],
            ),
          ),
        );
      },
    );
    await tester.tap(find.byKey(const ValueKey('calendar-planning-toggle')));
    await settle(tester);

    Finder sleep(String suffix) => find.byWidgetPredicate((w) {
      final k = w.key;
      return k is ValueKey<String> &&
          k.value.startsWith('plan-ghost-') &&
          !k.value.contains('handle') &&
          k.value.contains(suffix);
    });
    // 7 days: a first slice on each (22:00-24:00) and, from the night before the
    // range too, a continuation at the top of each (00:00-07:00).
    final continuations = find.byWidgetPredicate((w) {
      final k = w.key;
      return k is ValueKey<String> &&
          k.value.startsWith('plan-ghost-') &&
          k.value.endsWith('~1');
    });
    expect(continuations, findsNWidgets(7));
    expect(ghosts(), findsNWidgets(7 * 3)); // Run + Sleep first slices, 7 tails
    expect(sleep('~1'), findsNWidgets(7));

    // The tail on the FIRST visible day starts at the top and is 7 hours tall.
    final tails = continuations.evaluate().toList()
      ..sort((a, b) => tester
          .getTopLeft(find.byWidget(a.widget))
          .dx
          .compareTo(tester.getTopLeft(find.byWidget(b.widget)).dx));
    final first = find.byWidget(tails.first.widget);
    final gridTop = tester.getTopLeft(find.byKey(const ValueKey('day-column-0'))).dy;
    expect(tester.getTopLeft(first).dy, closeTo(gridTop, 0.5));
    final hour = tester.getSize(find.byKey(const ValueKey('day-column-0'))).height / 24;
    expect(tester.getSize(first).height, closeTo(hour * 7, 1));
    await unmount(tester);
  });

  testWidgets('the Previous and Next actions of a row are drawn next to it', (
    tester,
  ) async {
    await mount(
      tester,
      seed: (plans) async {
        await plans.saveItem(
          PlanItemInput(
            name: 'Bazaar',
            kind: PlanKind.cycle,
            startDate: planDateOf(DateTime.now()).subtract(const Duration(days: 30)),
            cycle: const CycleRule(
              cycleDays: 1,
              occurrences: [
                CycleOccurrence(
                  day: 0,
                  startMin: 18 * 60,
                  durationMin: 60,
                  extras: PlanExtras(
                    prev: [PlanCompanion(name: 'Get ready', minutes: 30)],
                    next: [
                      PlanCompanion(name: 'Unpack', minutes: 20, gapMinutes: 10),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    await tester.tap(find.byKey(const ValueKey('calendar-planning-toggle')));
    await settle(tester);

    Finder keyed(String marker) => find.byWidgetPredicate((w) {
      final k = w.key;
      return k is ValueKey<String> &&
          k.value.startsWith('plan-ghost-') &&
          k.value.contains(marker);
    });
    expect(keyed('>p0'), findsNWidgets(7));
    expect(keyed('>n0'), findsNWidgets(7));
    expect(find.text('Get ready\n17:30-18:00'), findsNWidgets(7));
    expect(find.text('Unpack\n19:10-19:30'), findsNWidgets(7));

    // Geometry on the first day: ends where the block starts / 10 min after it.
    final col = find.byKey(const ValueKey('day-column-0'));
    final hour = tester.getSize(col).height / 24;
    final top = tester.getTopLeft(col).dy;
    final prev = keyed('>p0').first;
    expect(tester.getTopLeft(prev).dy, closeTo(top + 17.5 * hour, 1));
    expect(tester.getSize(prev).height, closeTo(0.5 * hour, 1));
    await unmount(tester);
  });

  testWidgets('a Previous action that falls on the day before a block shows there', (
    tester,
  ) async {
    await mount(
      tester,
      seed: (plans) async {
        await plans.saveItem(
          PlanItemInput(
            name: 'Early',
            kind: PlanKind.cycle,
            startDate: planDateOf(DateTime.now()).subtract(const Duration(days: 30)),
            cycle: const CycleRule(
              cycleDays: 1,
              occurrences: [
                CycleOccurrence(
                  day: 0,
                  startMin: 10, // 00:10
                  durationMin: 30,
                  extras: PlanExtras(
                    prev: [PlanCompanion(name: 'Warm up', minutes: 30)],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    await tester.tap(find.byKey(const ValueKey('calendar-planning-toggle')));
    await settle(tester);
    // 23:40-00:10: the part before midnight is on the PREVIOUS day. Seven days
    // are visible, so the blocks of days 1..7 put one on each visible day.
    final before = find.byWidgetPredicate((w) {
      final k = w.key;
      return k is ValueKey<String> &&
          k.value.startsWith('plan-ghost-') &&
          k.value.contains('>p0@-1');
    });
    expect(before, findsNWidgets(7));
    await unmount(tester);
  });

  testWidgets('dragging one ghost does not pull the other plan items of that day', (
    tester,
  ) async {
    Future<void> daily(PlanService plans, String name, int startMin) async {
      await plans.saveItem(
        PlanItemInput(
          name: name,
          kind: PlanKind.cycle,
          startDate: planDateOf(DateTime.now()).subtract(const Duration(days: 30)),
          cycle: CycleRule(
            cycleDays: 1,
            occurrences: [
              CycleOccurrence(day: 0, startMin: startMin, durationMin: 30),
            ],
          ),
        ),
      );
    }

    // Every item has the same occurrence key (date#0) on a day.
    await mount(
      tester,
      seed: (plans) async {
        await daily(plans, 'Alpha', 20 * 60);
        await daily(plans, 'Beta', 21 * 60);
      },
    );
    await tester.tap(find.byKey(const ValueKey('calendar-planning-toggle')));
    await settle(tester);

    final alpha = find.text('Alpha\n20:00-20:30').first;
    final hour = tester.getSize(find.byKey(const ValueKey('day-column-0'))).height / 24;
    final g = await tester.startGesture(
      tester.getCenter(alpha),
      kind: PointerDeviceKind.mouse,
    );
    await g.moveBy(const Offset(0, 1));
    await tester.pump();
    await g.moveBy(Offset(0, -hour));
    await tester.pump();

    // Only Alpha of that day moves (19:00); Beta and the other days stay.
    expect(find.text('Alpha\n19:00-19:30'), findsOneWidget);
    expect(find.text('Alpha\n20:00-20:30'), findsNWidgets(6));
    expect(find.text('Beta\n21:00-21:30'), findsNWidgets(7));
    expect(find.text('Beta\n20:00-20:30'), findsNothing);
    await g.cancel();
    await tester.pump(const Duration(milliseconds: 500));
    await unmount(tester);
  });

  testWidgets('an all-day plan item shows as chips in the all-day strip', (
    tester,
  ) async {
    await mount(
      tester,
      seed: (plans) async {
        await plans.saveItem(
          PlanItemInput(
            name: 'Rest day',
            kind: PlanKind.cycle,
            startDate: planDateOf(DateTime.now()).subtract(const Duration(days: 30)),
            cycle: const CycleRule(
              cycleDays: 1,
              occurrences: [CycleOccurrence(day: 0, startMin: 0, allDay: true)],
            ),
          ),
        );
      },
    );
    // Hide the strip the normal way: planning mode still shows it.
    container.read(calendarAllDayProvider.notifier).set(false);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('calendar-planning-toggle')));
    await settle(tester);

    final chips = find.byWidgetPredicate((w) {
      final k = w.key;
      return k is ValueKey<String> && k.value.startsWith('plan-ghost-allday-');
    });
    expect(chips, findsNWidgets(7));
    expect(find.text('Rest day'), findsNWidgets(7));
    // The timed ghosts (Run) are untouched and the all-day ones are not blocks.
    expect(ghosts(), findsNWidgets(7 + 7)); // Run blocks + the chips' keys
    await unmount(tester);
  });

  group('right click on an all-day plan chip', () {
    Finder chips() => find.byWidgetPredicate((w) {
      final k = w.key;
      return k is ValueKey<String> && k.value.startsWith('plan-ghost-allday-');
    });

    Future<void> mountRestDay(WidgetTester tester) async {
      await mount(
        tester,
        seed: (plans) async {
          await plans.saveItem(
            PlanItemInput(
              name: 'Rest day',
              kind: PlanKind.cycle,
              startDate: planDateOf(
                DateTime.now(),
              ).subtract(const Duration(days: 30)),
              cycle: const CycleRule(
                cycleDays: 1,
                occurrences: [CycleOccurrence(day: 0, startMin: 0, allDay: true)],
              ),
            ),
          );
        },
      );
      await tester.tap(find.byKey(const ValueKey('calendar-planning-toggle')));
      await settle(tester);
      expect(chips(), findsNWidgets(7));
    }

    Future<void> rightClickFirstChip(WidgetTester tester) async {
      final g = await tester.startGesture(
        tester.getCenter(chips().first),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await g.up();
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('opens a menu with Edit, Skip this day and Delete', (
      tester,
    ) async {
      await mountRestDay(tester);
      await rightClickFirstChip(tester);
      expect(find.byKey(const ValueKey('plan-chip-edit')), findsOneWidget);
      expect(find.byKey(const ValueKey('plan-chip-skip')), findsOneWidget);
      expect(find.byKey(const ValueKey('plan-chip-delete')), findsOneWidget);
      await tester.tapAt(const Offset(5, 5)); // close the menu
      await tester.pump(const Duration(milliseconds: 400));
      await unmount(tester);
    });

    testWidgets('Skip this day only hides that day, Undo brings it back', (
      tester,
    ) async {
      await mountRestDay(tester);
      await rightClickFirstChip(tester);
      await tester.tap(find.byKey(const ValueKey('plan-chip-skip')));
      await settle(tester);
      expect(chips(), findsNWidgets(6));
      expect(find.text('Rest day'), findsNWidgets(6));
      // The timed plan item is untouched.
      expect(ghosts(), findsNWidgets(6 + 7));

      await tester.tap(find.text('Undo'));
      await settle(tester);
      expect(chips(), findsNWidgets(7));
      await tester.pump(const Duration(seconds: 6)); // the toast timer
      await unmount(tester);
    });

    testWidgets('Edit this plan opens the plan item editor', (tester) async {
      await mountRestDay(tester);
      await rightClickFirstChip(tester);
      await tester.tap(find.byKey(const ValueKey('plan-chip-edit')));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(PlanItemEditorDialog), findsOneWidget);
      expect(find.text('Rest day'), findsWidgets);
      resetStackedDialogsForTest();
      await unmount(tester);
    });

    testWidgets('Delete this plan asks, then removes the plan and its chips', (
      tester,
    ) async {
      await mountRestDay(tester);
      await rightClickFirstChip(tester);
      await tester.tap(find.byKey(const ValueKey('plan-chip-delete')));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Delete "Rest day"?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('plan-delete-keep')));
      await settle(tester);
      expect(chips(), findsNothing);
      // The other plan item (Run) stays.
      expect(ghosts(), findsNWidgets(7));
      await tester.pump(const Duration(seconds: 6));
      await unmount(tester);
    });
  });

  testWidgets('the ghost follows the grid while it scrolls under the pointer', (
    tester,
  ) async {
    await mount(
      tester,
      hours: 6,
      seed: (plans) async {
        await plans.saveItem(
          PlanItemInput(
            name: 'Early',
            kind: PlanKind.cycle,
            startDate: planDateOf(DateTime.now()).subtract(const Duration(days: 30)),
            cycle: const CycleRule(
              cycleDays: 1,
              occurrences: [
                CycleOccurrence(day: 0, startMin: 120, durationMin: 30),
              ],
            ),
          ),
        );
      },
    );
    await tester.tap(find.byKey(const ValueKey('calendar-planning-toggle')));
    await settle(tester);
    final scrollable = Scrollable.of(
      tester.element(find.byKey(const ValueKey('day-column-0'))),
    );
    scrollable.position.jumpTo(0);
    await tester.pump();

    final ghost = find.text('Early\n02:00-02:30').first;
    final hour = tester.getSize(find.byKey(const ValueKey('day-column-0'))).height / 24;
    final g = await tester.startGesture(
      tester.getCenter(ghost),
      kind: PointerDeviceKind.mouse,
    );
    await g.moveBy(const Offset(0, 20)); // past the drag slop: the drag runs
    await tester.pump();
    // The wheel (or the auto-scroll) moves the grid by three hours while the
    // pointer stays: the dragged block goes with the content.
    scrollable.position.jumpTo(3 * hour);
    await tester.pump();
    final minutes = 120 + ((20 / (hour / 60) + 180) / 10).round() * 10;
    final hh = (minutes ~/ 60).toString().padLeft(2, '0');
    final mm = (minutes % 60).toString().padLeft(2, '0');
    final end = minutes + 30;
    final eh = (end ~/ 60).toString().padLeft(2, '0');
    final em = (end % 60).toString().padLeft(2, '0');
    expect(find.text('Early\n$hh:$mm-$eh:$em'), findsOneWidget);
    await g.cancel();
    await tester.pump(const Duration(milliseconds: 500));
    await unmount(tester);
  });

  testWidgets('dragging a ghost: "this weekday only" splits the pattern by weekday', (
    tester,
  ) async {
    final id = await mount(tester);
    await tester.tap(find.byKey(const ValueKey('calendar-planning-toggle')));
    await settle(tester);
    final first = ghosts().first;
    final hour = tester.getSize(first).height;
    final g = await tester.startGesture(
      tester.getCenter(first),
      kind: PointerDeviceKind.mouse,
    );
    await g.moveBy(const Offset(0, 1));
    await tester.pump();
    await g.moveBy(Offset(0, -hour));
    await tester.pump();
    await g.up();
    await tester.pump();
    expect(find.byKey(const ValueKey('plan-scope-weekday')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('plan-scope-weekday')));
    await settle(tester);

    final item = (await tester.runAsync(
      () => PlanService(db, ActionService(db)).items(),
    ))!.firstWhere((r) => r.id == id);
    final data = PlanService(db, ActionService(db)).decode(item);
    // The daily item became a weekly one; exactly one weekday has 21:00.
    expect(data.cycle!.cycleDays, 7);
    expect(data.cycle!.occurrences.where((o) => o.startMin == 21 * 60), hasLength(1));
    expect(data.cycle!.occurrences.where((o) => o.startMin == 22 * 60), hasLength(6));
    await unmount(tester);
  });
}
