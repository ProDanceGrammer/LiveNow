import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/plan_rules.dart';
import 'package:livenow/domain/plan_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/plan_providers.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/views/calendar_view.dart';

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
          calendarVisibleHoursProvider.overrideWith((ref) => 24),
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
    // A weekly item is anchored to a Monday.
    expect(planDateFromKey(swim.startDate).weekday, DateTime.monday);
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
}
