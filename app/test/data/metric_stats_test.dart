import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/data/queries.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/growth_rules.dart';
import 'package:livenow/domain/metric_service.dart';
import 'package:livenow/domain/postpone_rules.dart';

void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late MetricService metrics;
  late ActionService actions;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    metrics = MetricService(db);
    actions = ActionService(db);
  });

  tearDown(() => db.close());

  /// The same path the growthSnapshotProvider takes.
  Future<Map<String, MetricStat>> statsNow() async {
    final rows = await db.select(db.metricsTable).get();
    final deps = await db.select(db.metricDependenciesTable).get();
    final linked = await ViewQueries(db).watchMetricLinkedActions().first;
    return computeStats(
      metrics: [for (final m in rows) GrowthMetric.fromRow(m)],
      graph: GrowthGraph([
        for (final e in deps)
          (metricId: e.metricId, dependsOnId: e.dependsOnId),
      ]),
      facts: [
        for (final (metricId, action) in linked)
          LinkedActionFact.fromAction(metricId, action),
      ],
      nowUtc: DateTime.now().toUtc(),
    );
  }

  test('counts finished actions in the window, hours from durations', () async {
    final now = DateTime.now().toUtc();
    final parent = await metrics.saveMetric(
      name: 'Parent',
      kind: MetricKind.boolean,
      isMain: true,
    );
    final count = await metrics.saveMetric(
      name: 'Gym',
      kind: MetricKind.count,
      window: MetricWindow.week,
      target: 4,
      leadsToIds: [parent],
    );
    final hours = await metrics.saveMetric(
      name: 'Deep work',
      kind: MetricKind.hours,
      window: MetricWindow.week,
      target: 5,
    );
    final tasks = await metrics.saveMetric(
      name: 'Finish the tasks',
      kind: MetricKind.boolean,
    );

    Future<String> action(
      String name, {
      DateTime? start,
      Duration? length,
      required List<String> links,
    }) => actions.createAction(
      name: name,
      startAt: start,
      endAt: start?.add(length ?? const Duration(hours: 1)),
      metricIds: links,
    );

    // Scheduled in the past, so "done" by the Done Before rule.
    await action(
      'a1',
      start: now.subtract(const Duration(days: 2)),
      links: [count, hours, tasks],
    );
    await action(
      'a2',
      start: now.subtract(const Duration(days: 3)),
      length: const Duration(minutes: 90),
      links: [count, hours],
    );
    // Done, but 20 days ago: outside the week window.
    await action(
      'a3',
      start: now.subtract(const Duration(days: 20)),
      links: [count, hours],
    );
    // Scheduled for tomorrow: not done yet.
    await action(
      'a4',
      start: now.add(const Duration(days: 1)),
      links: [count, tasks],
    );
    // Unscheduled but marked done: counted by its last change (just now).
    final a5 = await action('a5', links: [count]);
    await (db.update(db.actionsTable)..where((t) => t.id.equals(a5))).write(
      const ActionsTableCompanion(done: Value(true)),
    );
    // Unscheduled and not done.
    await action('a6', links: [count]);

    final stats = await statsNow();

    expect(stats[count]!.fact, 3); // a1, a2, a5
    expect(stats[count]!.progress, 75);
    expect(stats[hours]!.fact, 2.5); // 1 h + 1.5 h; a3 is out of the window
    expect(stats[hours]!.progress, 50);
    // Boolean with linked actions: a1 done, a4 not -> half.
    expect(stats[tasks]!.progress, 50);
    // The parent has no actions of its own: it follows its sub-direction.
    expect(stats[parent]!.progress, 75);
    // Gym leads to the main direction (weight 90); urgency = 90 x 15 / 90.
    expect(stats[count]!.urgency, closeTo(15, 0.01));
  });

  test('postponing a finished action into the future un-counts it', () async {
    final now = DateTime.now().toUtc();
    final gym = await metrics.saveMetric(
      name: 'Gym',
      kind: MetricKind.count,
      window: MetricWindow.week,
      target: 2,
    );
    final id = await actions.createAction(
      name: 'Gym session',
      startAt: now.subtract(const Duration(hours: 5)),
      endAt: now.subtract(const Duration(hours: 4)),
      metricIds: [gym],
    );
    expect((await statsNow())[gym]!.fact, 1);

    await actions.updateSchedule(
      id,
      startAt: now.add(const Duration(days: 1)),
      endAt: now.add(const Duration(days: 1, hours: 1)),
    );
    expect((await statsNow())[gym]!.fact, 0);
  });
}
