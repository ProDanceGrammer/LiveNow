import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/date_range_filter.dart';
import 'package:livenow/domain/growth_rules.dart';
import 'package:livenow/domain/metric_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/growth_filters.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/screens/growth_directions_screen.dart';

/// The Treemap's planned-hours mode and the custom date range of the
/// time-spent mode, driven through the real screen. The fixture is the owner's
/// day: sleep 8 + job 8 + friends 3 + family 1 + sport 2 + reading 2 + games
/// 3 = 27 h, typed as weekly targets (x 7), plus a count and a boolean direction
/// that must never appear in the plan.
void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  final ids = <String, String>{};

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> seed(MetricService metrics, ActionService actions) async {
    final main = await metrics.saveMetric(
      name: 'Main',
      kind: MetricKind.boolean,
      isMain: true,
    );
    ids['Main'] = main;
    Future<void> hoursDirection(String name, String icon, double perWeek) async {
      ids[name] = await metrics.saveMetric(
        name: name,
        kind: MetricKind.hours,
        window: MetricWindow.week,
        target: perWeek,
        leadsToIds: [main],
        icon: Value(icon),
      );
    }

    await hoursDirection('Sleep', '🛏️', 56);
    await hoursDirection('Job', '💼', 56);
    await hoursDirection('Friends', '🍻', 21);
    await hoursDirection('Family', '👪', 7);
    await hoursDirection('Sport', '🏃', 14);
    await hoursDirection('Reading', '📚', 14);
    await hoursDirection('Games', '🎮', 21);
    ids['Steps'] = await metrics.saveMetric(
      name: 'Steps',
      kind: MetricKind.count,
      window: MetricWindow.week,
      target: 5,
      leadsToIds: [main],
    );
    // One hour really spent on Reading yesterday (finished).
    final start = DateTime.now().toUtc().subtract(const Duration(days: 1));
    await actions.createAction(
      name: 'read a book',
      startAt: start,
      endAt: start.add(const Duration(hours: 1)),
      metricIds: [ids['Reading']!],
    );
  }

  Future<void> seedOnlyBoolean(MetricService metrics, ActionService actions) async {
    ids['Main'] = await metrics.saveMetric(
      name: 'Main',
      kind: MetricKind.boolean,
      isMain: true,
    );
  }

  late ProviderContainer container;

  Future<void> pumpScreen(
    WidgetTester tester, {
    Size size = const Size(1400, 1800),
    Future<void> Function(MetricService, ActionService)? seeder,
    bool openFilters = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    ids.clear();
    await tester.runAsync(
      () => (seeder ?? seed)(MetricService(db), ActionService(db)),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: GrowthDirectionsScreen()),
      ),
    );
    container = ProviderScope.containerOf(
      tester.element(find.byType(GrowthDirectionsScreen)),
    );
    await settle(tester);
    await tester.tap(find.text('Treemap'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    // The filters are hidden until asked for.
    if (openFilters) {
      await tester.tap(find.byKey(const ValueKey('treemap-options-toggle')));
      await settle(tester);
    }
  }

  Future<void> openPlanned(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('treemap-mode-planned')));
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Finder block(String name) =>
      find.byKey(ValueKey('treemap-block-${ids[name]}'));

  String text(WidgetTester t, String key) {
    final w = t.widget<Text>(find.byKey(ValueKey(key)));
    return w.data ?? w.textSpan!.toPlainText();
  }

  String tooltipOf(WidgetTester t, String name) => t
      .widget<Tooltip>(
        find.ancestor(of: block(name), matching: find.byType(Tooltip)),
      )
      .message!;

  testWidgets('the mode switch: time spent is the default, planned shows hours directions only', (
    tester,
  ) async {
    await pumpScreen(tester);
    expect(find.byKey(const ValueKey('treemap-summary')), findsOneWidget);
    expect(find.byKey(const ValueKey('treemap-planned-summary')), findsNothing);

    await openPlanned(tester);
    expect(find.byKey(const ValueKey('treemap-summary')), findsNothing);
    for (final n in ['Sleep', 'Job', 'Friends', 'Family', 'Sport', 'Reading', 'Games']) {
      expect(block(n), findsOneWidget, reason: n);
    }
    // A count and a boolean direction are not hours: never in the plan.
    expect(block('Steps'), findsNothing);
    expect(block('Main'), findsNothing);

    // Back to time spent.
    await tester.tap(find.byKey(const ValueKey('treemap-mode-time')));
    await settle(tester);
    expect(find.byKey(const ValueKey('treemap-summary')), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('27 h planned in a 24 h day: the summary line says 3 h over, in red', (
    tester,
  ) async {
    await pumpScreen(tester);
    await openPlanned(tester);
    expect(
      text(tester, 'treemap-planned-summary'),
      'Planned 27 h of 24 h available in a day · 7 directions · 3 h over',
    );
    // The old red box is gone.
    expect(find.byKey(const ValueKey('treemap-overplanned')), findsNothing);
    expect(find.byKey(const ValueKey('treemap-plan-fits')), findsNothing);
    final rich = tester.widget<Text>(
      find.byKey(const ValueKey('treemap-planned-summary')),
    );
    final over = (rich.textSpan! as TextSpan).children!.last as TextSpan;
    expect(over.style?.fontWeight, FontWeight.w600);
    expect(over.style?.color, isNotNull);
    await unmount(tester);
  });

  testWidgets('the span chips scale the plan: a week is 189 h of 168 h', (tester) async {
    await pumpScreen(tester);
    await openPlanned(tester);
    await tester.tap(find.byKey(const ValueKey('treemap-span-week')));
    await settle(tester);
    expect(
      text(tester, 'treemap-planned-summary'),
      'Planned 189 h of 168 h available in 7 days · 7 directions · 21 h over',
    );
    await unmount(tester);
  });

  testWidgets('available hours per day can be lowered (16 awake hours: 11 h over)', (
    tester,
  ) async {
    await pumpScreen(tester);
    await openPlanned(tester);
    // Out of range (more than 24) is ignored; 16 is taken.
    await tester.enterText(find.byKey(const ValueKey('treemap-plan-hours')), '30');
    await settle(tester);
    expect(text(tester, 'treemap-planned-summary'), contains('of 24 h available'));
    await tester.enterText(find.byKey(const ValueKey('treemap-plan-hours')), '16');
    await settle(tester);
    expect(text(tester, 'treemap-planned-summary'), contains('Planned 27 h of 16 h'));
    expect(text(tester, 'treemap-planned-summary'), endsWith('· 11 h over'));
    await unmount(tester);
  });

  testWidgets('choosing directions: only hours directions are offered, unticking removes them', (
    tester,
  ) async {
    await pumpScreen(tester);
    await openPlanned(tester);
    expect(find.text('Directions (7 of 7)'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('treemap-plan-pick')));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNWidgets(7));
    expect(find.textContaining('Steps'), findsNothing);
    await tester.tap(find.widgetWithText(CheckboxListTile, '🛏️ Sleep'));
    await tester.tap(find.widgetWithText(CheckboxListTile, '💼 Job'));
    await tester.pump();
    await tester.tap(find.textContaining('Done ('));
    await tester.pumpAndSettle();
    await settle(tester);

    expect(block('Sleep'), findsNothing);
    expect(block('Job'), findsNothing);
    expect(
      text(tester, 'treemap-planned-summary'),
      'Planned 11 h of 24 h available in a day · 5 directions · 13 h free',
    );
    // 11 h of 24 h fits: the free hours in the normal colour, no warning.
    final rich = tester.widget<Text>(
      find.byKey(const ValueKey('treemap-planned-summary')),
    );
    expect(((rich.textSpan! as TextSpan).children!.last as TextSpan).style, isNull);
    expect(find.text('Directions (5 of 7)'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a custom range overrides the span chips; the plan scales by its days', (
    tester,
  ) async {
    await pumpScreen(tester);
    await openPlanned(tester);
    container.read(treemapRangeProvider.notifier).state = DateRangeFilter(
      from: DateRangeFilter.dayStart(DateTime(2026, 10, 1)),
      until: DateRangeFilter.dayStart(DateTime(2026, 10, 10)),
    );
    await settle(tester);
    // 10 days: 27 h x 10 = 270 h of 240 h.
    expect(
      text(tester, 'treemap-planned-summary'),
      'Planned 270 h of 240 h available in 10 days · 7 directions · 30 h over',
    );
    // The span chips show unselected while dates are set; a chip clears them.
    expect(
      tester.widget<ChoiceChip>(find.byKey(const ValueKey('treemap-span-day'))).selected,
      isFalse,
    );
    await tester.tap(find.byKey(const ValueKey('treemap-span-day')));
    await settle(tester);
    expect(container.read(treemapRangeProvider).active, isFalse);
    expect(text(tester, 'treemap-planned-summary'), contains('in a day'));
    await unmount(tester);
  });

  testWidgets('a range with only one date cannot be planned over', (tester) async {
    await pumpScreen(tester);
    await openPlanned(tester);
    container.read(treemapRangeProvider.notifier).state = DateRangeFilter(
      from: DateRangeFilter.dayStart(DateTime(2026, 10, 1)),
    );
    await settle(tester);
    expect(find.byKey(const ValueKey('treemap-plan-badrange')), findsOneWidget);
    expect(find.byKey(const ValueKey('treemap-planned-summary')), findsNothing);
    await unmount(tester);
  });

  testWidgets('each tooltip compares the plan with the time really spent', (tester) async {
    await pumpScreen(tester);
    await openPlanned(tester);
    // Today only: yesterday's reading is outside the span.
    expect(tooltipOf(tester, 'Reading'), contains('planned 2 h'));
    expect(tooltipOf(tester, 'Reading'), contains('spent nothing in these dates'));
    // A week includes it: 1 h of the 14 h planned.
    await tester.tap(find.byKey(const ValueKey('treemap-span-week')));
    await settle(tester);
    expect(tooltipOf(tester, 'Reading'), contains('planned 14 h'));
    expect(tooltipOf(tester, 'Reading'), contains('spent 1 h (7.1 % of the plan)'));
    expect(tooltipOf(tester, 'Sleep'), contains('spent nothing'));
    await unmount(tester);
  });

  testWidgets('with no hours direction at all the view says how to make one', (
    tester,
  ) async {
    await pumpScreen(tester, seeder: seedOnlyBoolean);
    await openPlanned(tester);
    expect(find.byKey(const ValueKey('treemap-plan-none')), findsOneWidget);
    expect(find.text('Directions (0 of 0)'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('with every direction unticked it asks to choose some', (tester) async {
    await pumpScreen(tester);
    await openPlanned(tester);
    await tester.tap(find.byKey(const ValueKey('treemap-plan-pick')));
    await tester.pumpAndSettle();
    final tiles = find.byType(CheckboxListTile);
    expect(tiles, findsNWidgets(7));
    for (var i = 0; i < 7; i++) {
      // The list keeps its order while ticking; scroll each tile into view.
      await tester.ensureVisible(tiles.at(i));
      await tester.pump();
      await tester.tap(tiles.at(i));
      await tester.pump();
    }
    await tester.tap(find.textContaining('Done ('));
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.byKey(const ValueKey('treemap-plan-nonechosen')), findsOneWidget);
    expect(find.text('Directions (0 of 7)'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('time spent over custom dates: an old range empties it, a period chip clears the range', (
    tester,
  ) async {
    await pumpScreen(tester);
    expect(block('Reading'), findsOneWidget); // yesterday, inside the month
    container.read(treemapRangeProvider.notifier).state = DateRangeFilter(
      from: DateRangeFilter.dayStart(DateTime(2020, 1, 1)),
      until: DateRangeFilter.dayStart(DateTime(2020, 1, 31)),
    );
    await settle(tester);
    expect(block('Reading'), findsNothing);
    expect(find.text('No finished time in this range.'), findsOneWidget);
    // Custom dates win: the period chips show unselected.
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('treemap-period-month')))
          .selected,
      isFalse,
    );

    await tester.tap(find.byKey(const ValueKey('treemap-period-month')));
    await settle(tester);
    expect(container.read(treemapRangeProvider).active, isFalse);
    expect(block('Reading'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('treemap-period-month')))
          .selected,
      isTrue,
    );
    await unmount(tester);
  });

  testWidgets('a range that includes yesterday shows the time spent in it', (tester) async {
    await pumpScreen(tester);
    final yesterday = DateTime.now().toUtc().subtract(const Duration(days: 1));
    final day = DateRangeFilter.dayStart(
      DateRangeFilter.dayOf(yesterday),
    );
    container.read(treemapRangeProvider.notifier).state = DateRangeFilter(
      from: day,
      until: day,
    );
    await settle(tester);
    expect(block('Reading'), findsOneWidget);
    expect(text(tester, 'treemap-summary'), startsWith('Total 1 h'));
    await unmount(tester);
  });

  testWidgets('phone width: both modes and their controls do not overflow', (tester) async {
    final errors = <FlutterErrorDetails>[];
    final old = FlutterError.onError;
    FlutterError.onError = errors.add;
    await pumpScreen(tester, size: const Size(375, 812));
    await openPlanned(tester);
    await tester.tap(find.byKey(const ValueKey('treemap-span-week')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('treemap-mode-time')));
    await settle(tester);
    FlutterError.onError = old;
    expect(errors.map((e) => e.exceptionAsString()), isEmpty);
    await unmount(tester);
  });
}
