import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/growth_rules.dart';
import 'package:livenow/domain/metric_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/screens/growth_directions_screen.dart';
import 'package:livenow/ui/widgets/growth_direction_dialog.dart';

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

  Future<void> animate(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Main (boolean, no time), Alpha (count, 2 x 1 h), Bravo (hours, one 3 h
  /// action), Charlie (count, nothing done), Delta (count, one 1 h action 40
  /// days ago: outside the default month, inside a year).
  Future<void> seed(MetricService metrics, ActionService actions) async {
    final main = await metrics.saveMetric(
      name: 'Main',
      kind: MetricKind.boolean,
      isMain: true,
    );
    Future<String> direction(String name, MetricKind kind) async {
      final id = await metrics.saveMetric(
        name: name,
        kind: kind,
        window: MetricWindow.week,
        target: 3,
        leadsToIds: [main],
      );
      ids[name] = id;
      return id;
    }

    final alpha = await direction('Alpha', MetricKind.count);
    final bravo = await direction('Bravo', MetricKind.hours);
    await direction('Charlie', MetricKind.count);
    final delta = await direction('Delta', MetricKind.count);
    ids['Main'] = main;

    final now = DateTime.now().toUtc();
    final yesterday = now.subtract(const Duration(days: 1));
    Future<void> done(
      String name,
      DateTime start,
      int minutes,
      String metric,
    ) => actions.createAction(
      name: name,
      startAt: start,
      endAt: start.add(Duration(minutes: minutes)),
      metricIds: [metric],
    );
    await done('a1', yesterday, 60, alpha);
    await done('a2', yesterday.subtract(const Duration(hours: 3)), 60, alpha);
    await done('b1', yesterday, 180, bravo);
    await done('d1', now.subtract(const Duration(days: 40)), 60, delta);
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    bool withData = true,
    Size size = const Size(1400, 1800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    ids.clear();
    if (withData) {
      await tester.runAsync(() => seed(MetricService(db), ActionService(db)));
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: GrowthDirectionsScreen()),
      ),
    );
    await settle(tester);
  }

  Future<void> openTreemap(WidgetTester tester) async {
    await tester.tap(find.text('Treemap'));
    await animate(tester);
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Finder block(String name) =>
      find.byKey(ValueKey('treemap-block-${ids[name]}'));

  String summary(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('treemap-summary'))).data!;

  Future<void> pickKind(WidgetTester tester, String label) async {
    await tester.tap(find.byKey(const ValueKey('growth-kind')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('the Treemap tab sits between Balance and List', (tester) async {
    await pumpScreen(tester);
    double x(String t) => tester.getCenter(find.text(t).first).dx;
    expect(x('Balance'), lessThan(x('Treemap')));
    expect(x('Treemap'), lessThan(x('List')));
    expect(x('List'), lessThan(x('Mindmap')));
    await unmount(tester);
  });

  testWidgets('every direction with finished time is a block, with its time', (
    tester,
  ) async {
    await pumpScreen(tester);
    await openTreemap(tester);

    expect(block('Alpha'), findsOneWidget);
    expect(block('Bravo'), findsOneWidget);
    // Boolean main, a count direction with nothing done, and one whose only
    // action is older than the month: no block.
    expect(block('Main'), findsNothing);
    expect(block('Charlie'), findsNothing);
    expect(block('Delta'), findsNothing);

    // Count and hours directions both show their finished time.
    expect(
      find.descendant(of: block('Alpha'), matching: find.textContaining('2 hours')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: block('Bravo'), matching: find.textContaining('3 hours')),
      findsOneWidget,
    );
    // The bigger time gets the bigger area.
    final a = tester.getSize(block('Alpha'));
    final b = tester.getSize(block('Bravo'));
    expect(b.width * b.height, greaterThan(a.width * a.height));

    expect(summary(tester), 'Total 5 hours · 2 directions · 3 without time');
    await unmount(tester);
  });

  testWidgets('the period switch changes what is counted', (tester) async {
    await pumpScreen(tester);
    await openTreemap(tester);
    expect(block('Delta'), findsNothing); // 40 days ago, default = month

    await tester.tap(find.byKey(const ValueKey('treemap-period-year')));
    await settle(tester);
    expect(block('Delta'), findsOneWidget);
    expect(summary(tester), startsWith('Total 6 hours · 3 directions'));

    await tester.tap(find.byKey(const ValueKey('treemap-period-all')));
    await settle(tester);
    expect(block('Delta'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('treemap-period-week')));
    await settle(tester);
    expect(block('Delta'), findsNothing);
    expect(block('Alpha'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('the type filter is shared with the List tab', (tester) async {
    await pumpScreen(tester);
    await openTreemap(tester);
    await pickKind(tester, 'Actions');
    await settle(tester);
    expect(block('Alpha'), findsOneWidget);
    expect(block('Bravo'), findsNothing); // an hours direction

    await tester.tap(find.text('List'));
    await animate(tester);
    // Same filter over there: only the count directions are listed.
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Charlie'), findsOneWidget);
    expect(find.text('Bravo'), findsNothing);

    await tester.tap(find.text('Treemap'));
    await animate(tester);
    await settle(tester);
    expect(block('Bravo'), findsNothing); // still filtered after the switch
    await unmount(tester);
  });

  testWidgets('the search text is shared with the List tab and kept', (
    tester,
  ) async {
    await pumpScreen(tester);
    await openTreemap(tester);
    await tester.enterText(find.byKey(const ValueKey('growth-search')), 'brav');
    await settle(tester);
    expect(block('Bravo'), findsOneWidget);
    expect(block('Alpha'), findsNothing);

    await tester.tap(find.text('List'));
    await animate(tester);
    expect(find.text('Bravo'), findsOneWidget);
    expect(find.text('Alpha'), findsNothing);
    // The field shows what was typed on the other tab.
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('growth-search')))
          .controller!
          .text,
      'brav',
    );
    await unmount(tester);
  });

  testWidgets('tapping a block opens the direction', (tester) async {
    await pumpScreen(tester);
    await openTreemap(tester);
    await tester.tap(block('Alpha'));
    await animate(tester);
    expect(find.byType(GrowthDirectionDialog), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('empty states say what is missing', (tester) async {
    await pumpScreen(tester);
    await openTreemap(tester);
    await tester.enterText(find.byKey(const ValueKey('growth-search')), 'zzz');
    await settle(tester);
    expect(find.text('No growth directions match.'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('growth-search')), 'Charlie');
    await settle(tester);
    // The direction exists but has no finished time in the period.
    expect(find.text('No finished time in this period.'), findsOneWidget);
    expect(summary(tester), 'No time · 1 without time');
    await unmount(tester);
  });

  testWidgets('a phone width fits without overflow', (tester) async {
    await pumpScreen(tester, size: const Size(420, 900));
    await openTreemap(tester);
    expect(block('Alpha'), findsOneWidget);
    expect(block('Bravo'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Both blocks stay inside the screen.
    final screen = tester.view.physicalSize;
    for (final n in ['Alpha', 'Bravo']) {
      final r = tester.getRect(block(n));
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.right, lessThanOrEqualTo(screen.width));
      expect(r.bottom, lessThanOrEqualTo(screen.height));
    }
    await unmount(tester);
  });
}
