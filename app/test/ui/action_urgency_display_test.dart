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
import 'package:livenow/ui/urgency_colors.dart';
import 'package:livenow/ui/widgets/action_tile.dart';
import 'package:livenow/ui/widgets/param_icons.dart';
import 'package:livenow/ui/widgets/quick_action_bar.dart';

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
    // Card chip + tile subtitle part: icon + number, no 'U ' text.
    expect(find.text('910'), findsNWidgets(2));
    expect(find.textContaining('U 910'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('actionUrgencyChip')),
        matching: find.byTooltip('Urgency to Keep in Balance'),
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('Urgency to Keep in Balance'), findsNWidgets(2));
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
    expect(find.byType(ParamIcon), findsNothing);
    expect(find.text('910'), findsNothing);
    await unmount(tester);
  });

  testWidgets('done card with urgency gets the muted band colour', (
    tester,
  ) async {
    final row = await makeAction(tester);
    final base = ActionListItem.fromRow(row);
    final item = ActionListItem(
      id: base.id,
      name: base.name,
      done: true,
      isAllDay: false,
    );
    await pump(
      tester,
      ActionCard(action: item),
      extra: [
        actionUrgencyProvider.overrideWithValue({item.id: 909.6}),
      ],
    );
    final muted = urgencyColorsMuted(909.6, dark: false).bg;
    final full = urgencyColors(909.6, dark: false).bg;
    final colors = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .map((d) => d.color)
        .toList();
    expect(colors, contains(muted));
    expect(colors, isNot(contains(full)));
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
    final line = find.byKey(const ValueKey('actionUrgencyLine'));
    expect(line, findsOneWidget);
    expect(
      find.descendant(of: line, matching: find.text('910')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: line,
        matching: find.byTooltip('Urgency to Keep in Balance'),
      ),
      findsOneWidget,
    );
    // Order: Name field above the urgency line above the button row.
    final nameY = tester.getTopLeft(find.byType(TextFormField).first).dy;
    final lineY = tester.getTopLeft(line).dy;
    final barY = tester.getTopLeft(find.byType(QuickActionBar)).dy;
    expect(nameY, lessThan(lineY));
    expect(lineY, lessThan(barY));
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
    expect(find.byKey(const ValueKey('actionUrgencyLine')), findsNothing);
    expect(find.byTooltip('Urgency to Keep in Balance'), findsNothing);
    await unmount(tester);
  });
}
