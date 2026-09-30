import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/data/queries.dart';
import 'package:livenow/domain/growth_rules.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/widgets/action_card.dart';
import 'package:livenow/ui/widgets/action_editor.dart';
import 'package:livenow/ui/widgets/action_tile.dart';

void main() {
  late AppDatabase db;

  Future<void> unmount(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<ActionRow> makeAction(
    WidgetTester tester, {
    List<String>? metrics,
  }) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    late ActionRow row;
    await tester.runAsync(() async {
      final c = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      final ids = <String>[];
      for (final n in metrics ?? const <String>[]) {
        ids.add(
          await c
              .read(metricServiceProvider)
              .saveMetric(
                name: n,
                kind: MetricKind.count,
                window: MetricWindow.week,
              ),
        );
      }
      final id = await c
          .read(actionServiceProvider)
          .createAction(name: 'Read', metricIds: ids);
      row = await (db.select(
        db.actionsTable,
      )..where((t) => t.id.equals(id))).getSingle();
    });
    return row;
  }

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    List<Override> extra = const [],
  }) => tester.pumpWidget(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db), ...extra],
      child: MaterialApp(home: Scaffold(body: child)),
    ),
  );

  testWidgets('card and tile show U chip only when the action has urgency', (
    tester,
  ) async {
    final row = await makeAction(tester);
    final item = ActionListItem.fromRow(row);

    await pump(
      tester,
      Column(
        children: [
          ActionCard(action: item),
          ActionTile(action: item),
        ],
      ),
      extra: [
        actionUrgencyProvider.overrideWithValue({item.id: 909.6}),
      ],
    );
    expect(find.byKey(const ValueKey('actionUrgencyChip')), findsOneWidget);
    expect(find.text('U 910'), findsOneWidget);
    expect(find.textContaining('U 910'), findsNWidgets(2));
    await unmount(tester);

    await pump(
      tester,
      Column(
        children: [
          ActionCard(action: item),
          ActionTile(action: item),
        ],
      ),
      extra: [actionUrgencyProvider.overrideWithValue(const {})],
    );
    expect(find.textContaining('U '), findsNothing);
    await unmount(tester);
  });

  testWidgets('editor shows the summed urgency of linked directions', (
    tester,
  ) async {
    final row = await makeAction(tester, metrics: ['A', 'B']);
    final ids = await tester.runAsync(
      () async =>
          (await db.select(db.metricsTable).get()).map((m) => m.id).toList(),
    );
    final snapshot = GrowthSnapshot(
      metrics: const [],
      graph: GrowthGraph(const []),
      stats: {
        ids![0]: const MetricStat(fact: 0, progress: 0, urgency: 1000),
        ids[1]: const MetricStat(fact: 0, progress: 0, urgency: -90),
      },
    );
    await pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => ActionEditorDialog.show(context, existing: row),
          child: const Text('open'),
        ),
      ),
      extra: [
        growthSnapshotProvider.overrideWithValue(AsyncValue.data(snapshot)),
      ],
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    // The direction picker lives in the collapsed 'Manual parameters' section.
    await tester.tap(find.text('Manual parameters'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Urgency to Keep in Balance: 910'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('editor shows nothing when no direction is selected', (
    tester,
  ) async {
    final row = await makeAction(tester);
    await pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => ActionEditorDialog.show(context, existing: row),
          child: const Text('open'),
        ),
      ),
      extra: [
        growthSnapshotProvider.overrideWithValue(
          AsyncValue.data(
            GrowthSnapshot(
              metrics: const [],
              graph: GrowthGraph(const []),
              stats: const {},
            ),
          ),
        ),
      ],
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Urgency to Keep in Balance'), findsNothing);
    await unmount(tester);
  });
}
