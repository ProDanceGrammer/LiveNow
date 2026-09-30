import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/growth_rules.dart';
import 'package:livenow/domain/metric_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/screens/growth_directions_screen.dart';
import 'package:livenow/ui/widgets/metric_picker.dart';

void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;

  /// Lets Drift's streams deliver, then rebuilds.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Runs a tab / dialog animation: the first frame only starts it, so a
  /// single pump(duration) would leave the new content unbuilt.
  Future<void> animate(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    Future<void> Function(MetricService metrics, ActionService actions)? seed,
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    if (seed != null) {
      await tester.runAsync(() => seed(MetricService(db), ActionService(db)));
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db), ...overrides],
        child: const MaterialApp(home: GrowthDirectionsScreen()),
      ),
    );
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<List<Metric>> allMetrics(WidgetTester tester) async =>
      (await tester.runAsync(() => db.select(db.metricsTable).get()))!;

  Future<void> seedWeekly(
    MetricService metrics,
    ActionService actions,
    List<(String name, int doneActions)> rows,
  ) async {
    final main = await metrics.saveMetric(
      name: 'Main',
      kind: MetricKind.boolean,
      isMain: true,
    );
    final past = DateTime.now().toUtc().subtract(const Duration(days: 1));
    for (final (name, done) in rows) {
      final id = await metrics.saveMetric(
        name: name,
        kind: MetricKind.count,
        window: MetricWindow.week,
        target: 3,
        leadsToIds: [main],
      );
      for (var i = 0; i < done; i++) {
        await actions.createAction(
          name: '$name $i',
          startAt: past,
          endAt: past.add(const Duration(hours: 1)),
          metricIds: [id],
        );
      }
    }
  }

  testWidgets('Balance shows the six boards, Focus On ordered by urgency', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      seed: (m, a) =>
          seedWeekly(m, a, [('Alpha', 0), ('Bravo', 1), ('Charlie', 2)]),
    );

    for (final side in ['focusOn', 'decreaseIt']) {
      for (final group in ['daily', 'weekly', 'monthly']) {
        expect(find.byKey(ValueKey('board-$side-$group')), findsOneWidget);
      }
    }
    final focus = find.byKey(const ValueKey('board-focusOn-weekly'));
    double y(String name) => tester
        .getTopLeft(find.descendant(of: focus, matching: find.text(name)))
        .dy;
    // Progress 0 / 33.33 / 66.67 -> urgency 90 / 56.67 / 23.33.
    expect(y('Alpha'), lessThan(y('Bravo')));
    expect(y('Bravo'), lessThan(y('Charlie')));
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('average-focusOn-weekly')))
          .data,
      'AVERAGE 33.33',
    );
    // The Boolean main direction is on no board.
    expect(
      find.descendant(of: focus, matching: find.text('Main')),
      findsNothing,
    );
    await unmount(tester);
  });

  testWidgets('a board shows 10 rows and "Show more" reveals the rest', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      seed: (m, a) => seedWeekly(m, a, [
        for (var i = 1; i <= 12; i++) ('Dir${i.toString().padLeft(2, '0')}', 0),
      ]),
    );
    final focus = find.byKey(const ValueKey('board-focusOn-weekly'));
    Finder name(String n) => find.descendant(of: focus, matching: find.text(n));

    expect(name('Dir10'), findsOneWidget);
    expect(name('Dir11'), findsNothing);
    await tester.tap(find.text('Show more (2)'));
    await tester.pump();
    expect(name('Dir11'), findsOneWidget);
    expect(name('Dir12'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('List tab filters by the search text', (tester) async {
    await pumpScreen(
      tester,
      seed: (m, a) => seedWeekly(m, a, [('Alpha', 0), ('Bravo', 0)]),
    );
    await tester.tap(find.text('List'));
    await animate(tester);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Bravo'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'brav');
    await tester.pump();
    expect(find.text('Alpha'), findsNothing);
    expect(find.text('Bravo'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('Mindmap tab replaces the Tree tab and shows the directions', (
    tester,
  ) async {
    await pumpScreen(tester, seed: (m, a) => seedWeekly(m, a, [('Alpha', 0)]));
    expect(find.text('Tree'), findsNothing);
    await tester.tap(find.text('Mindmap'));
    await animate(tester);
    await settle(tester);
    expect(find.text('Main'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('creating a direction from the + button saves it', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tester.tap(find.byTooltip('New growth direction'));
    await animate(tester);
    expect(find.text('New growth direction'), findsWidgets);

    await tester.enterText(find.byType(TextFormField).first, 'I read daily');
    await tester.tap(find.text('Save'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await animate(tester);

    final saved = await allMetrics(tester);
    expect(saved.single.name, 'I read daily');
    expect(saved.single.kind, 'count');
    expect(saved.single.timeWindow, 'week');
    await settle(tester);
    await unmount(tester);
  });

  testWidgets('deleting from the dialog asks nothing and Undo restores', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      seed: (m, a) async {
        await m.saveMetric(name: 'Zed', kind: MetricKind.boolean);
      },
    );
    await tester.tap(find.text('List'));
    await animate(tester);
    await tester.tap(find.text('Zed'));
    await animate(tester);
    await settle(tester); // the dialog loads the direction's relations

    await tester.tap(find.text('Delete'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await animate(tester);

    expect(await allMetrics(tester), isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Deleted "Zed"'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Undo'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    expect((await allMetrics(tester)).map((m) => m.name), ['Zed']);
    // Let the snackbar finish hiding before the tree goes away.
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await settle(tester);
    await unmount(tester);
  });

  testWidgets('importing a CSV replaces the directions', (tester) async {
    const csv =
        'page_id,objective_name,metric_data_type,numerical_objective,'
        'depends_on,improves_count\r\n'
        'p1,Big goal,Boolean,1,"[""Small step""]",1\r\n'
        'p2,Small step,Weekly Done Actions,3,[],0\r\n';
    await pumpScreen(
      tester,
      seed: (m, a) async {
        await m.saveMetric(name: 'Old', kind: MetricKind.boolean);
      },
      overrides: [growthCsvPickerProvider.overrideWithValue(() async => csv)],
    );

    await tester.tap(find.byTooltip('Import growth directions from CSV…'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('Imported 2 growth directions'), findsOneWidget);
    expect((await allMetrics(tester)).map((m) => m.name).toSet(), {
      'Big goal',
      'Small step',
    });
    await tester.pump(const Duration(seconds: 6));
    await settle(tester);
    await unmount(tester);
  });

  testWidgets('importing saved Notion pages sets icons shown in the list', (
    tester,
  ) async {
    const html =
        '<div class="notion-selectable notion-page-block notion-collection-item">'
        '<div data-col-index="0" style="x"><div><img class="notion-emoji" alt="P"></div>'
        '<div>Small step</div></div><div data-col-index="1" style="x"></div></div>';
    await pumpScreen(
      tester,
      seed: (m, a) async {
        await m.saveMetric(name: 'Small step', kind: MetricKind.boolean);
      },
      overrides: [
        notionPagesPickerProvider.overrideWithValue(() async => [html]),
      ],
    );

    await tester.tap(
      find.byTooltip(
        'Import icons (saved Notion pages .htm, or name⇥emoji .tsv)…',
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('Set 1 icons'), findsOneWidget);
    expect((await allMetrics(tester)).single.icon, 'P');
    await tester.pump(const Duration(seconds: 6));
    await settle(tester);
    await unmount(tester);
  });

  testWidgets('a direction icon shows on the Balance board and in the List', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      seed: (m, a) async {
        await m.saveMetric(
          name: 'Focus me',
          kind: MetricKind.count,
          window: MetricWindow.week,
          target: 3,
          isMain: true,
          icon: const Value('🚓'),
        );
      },
    );
    await settle(tester);
    expect(find.textContaining('🚓 Focus me'), findsWidgets);

    await tester.tap(find.text('List'));
    await animate(tester);
    await settle(tester);
    expect(find.textContaining('🚓 Focus me'), findsWidgets);
    await unmount(tester);
  });

  testWidgets('a malformed CSV is reported and nothing is lost', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      seed: (m, a) async {
        await m.saveMetric(name: 'Keep', kind: MetricKind.boolean);
      },
      overrides: [
        growthCsvPickerProvider.overrideWithValue(() async => 'a,b\r\n1,2\r\n'),
      ],
    );
    await tester.tap(find.byTooltip('Import growth directions from CSV…'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('Import failed'), findsOneWidget);
    expect((await allMetrics(tester)).map((m) => m.name), ['Keep']);
    await tester.pump(const Duration(seconds: 6));
    await settle(tester);
    await unmount(tester);
  });

  group('MetricPicker', () {
    testWidgets('searches, selects and reports the chosen ids', (tester) async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      late String sleep;
      await tester.runAsync(() async {
        final m = MetricService(db);
        sleep = await m.saveMetric(
          name: 'I sleep enough',
          kind: MetricKind.boolean,
        );
        await m.saveMetric(name: 'I read', kind: MetricKind.boolean);
      });

      Set<String> chosen = {};
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => MetricPicker(
                  label: 'Growth directions',
                  selectedIds: chosen,
                  onChanged: (ids) => setState(() => chosen = ids),
                ),
              ),
            ),
          ),
        ),
      );
      await settle(tester);

      await tester.tap(find.text('Add…'));
      await animate(tester);
      await tester.enterText(find.byType(TextField), 'sleep');
      await tester.pump();
      expect(find.text('I read'), findsNothing);

      await tester.tap(find.text('I sleep enough'));
      await tester.pump();
      await tester.tap(find.textContaining('Done'));
      await animate(tester);

      expect(chosen, {sleep});
      expect(find.widgetWithText(InputChip, 'I sleep enough'), findsOneWidget);
      await unmount(tester);
    });
  });
}
