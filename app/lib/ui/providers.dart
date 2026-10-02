import 'package:drift/drift.dart' show OrderingTerm, innerJoin;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;

import '../data/database.dart';
import '../data/queries.dart';
import '../domain/action_service.dart';
import '../domain/action_urgency.dart';
import '../domain/dependency_service.dart';
import '../domain/growth_rules.dart';
import '../domain/metric_service.dart';
import 'views/calendar_layout.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final actionServiceProvider = Provider<ActionService>(
  (ref) => ActionService(ref.watch(databaseProvider)),
);

final dependencyServiceProvider = Provider<DependencyService>(
  (ref) => DependencyService(ref.watch(databaseProvider)),
);

final viewQueriesProvider = Provider<ViewQueries>(
  (ref) => ViewQueries(ref.watch(databaseProvider)),
);

/// Page size of a Current Actions column and how much "Show more" adds.
const kCurrentPageSize = 100;

/// How many cards the right ("Not Done Yet") column loads.
final currentNotDoneLimitProvider = StateProvider<int>(
  (ref) => kCurrentPageSize,
);

/// How many cards the left ("Done Before") column loads.
final currentDoneLimitProvider = StateProvider<int>((ref) => kCurrentPageSize);

final currentNotDoneProvider = StreamProvider.autoDispose<List<ActionListItem>>(
  (ref) => ref
      .watch(viewQueriesProvider)
      .watchCurrentNotDone(limit: ref.watch(currentNotDoneLimitProvider)),
);

final currentDoneProvider = StreamProvider.autoDispose<List<ActionListItem>>(
  (ref) => ref
      .watch(viewQueriesProvider)
      .watchCurrentDone(limit: ref.watch(currentDoneLimitProvider)),
);

/// Total not-done actions (the column header shows this, not the page size).
final currentNotDoneCountProvider = StreamProvider.autoDispose<int>(
  (ref) => ref.watch(viewQueriesProvider).watchCurrentNotDoneCount(),
);

/// Total done actions.
final currentDoneCountProvider = StreamProvider.autoDispose<int>(
  (ref) => ref.watch(viewQueriesProvider).watchCurrentDoneCount(),
);

/// How many day columns the calendar shows (2..7).
final calendarDayCountProvider = StateProvider<int>((ref) => 7);

/// The UTC instant of Istanbul midnight that starts the viewed range.
final calendarRangeStartProvider = StateProvider<DateTime>(
  (ref) => calendarAnchorStart(DateTime.now().toUtc(), 7),
);

/// Actions overlapping `[start, start + N days)`.
final calendarRangeProvider = StreamProvider.autoDispose<List<ActionListItem>>((
  ref,
) {
  final start = ref.watch(calendarRangeStartProvider);
  final days = ref.watch(calendarDayCountProvider);
  return ref
      .watch(viewQueriesProvider)
      .watchCalendarWeek(
        weekStartUtc: start,
        weekEndUtc: calendarAddDays(start, days),
      );
});

/// Changes the day count and re-anchors: 7 -> Monday of the current week,
/// 2..6 -> today.
void setCalendarDayCount(WidgetRef ref, int days) {
  ref.read(calendarDayCountProvider.notifier).state = days.clamp(2, 7);
  ref.read(calendarRangeStartProvider.notifier).state = calendarAnchorStart(
    DateTime.now().toUtc(),
    days.clamp(2, 7),
  );
}

/// Shifts the viewed range by [direction] * N days (-1 previous, +1 next).
void shiftCalendarRange(WidgetRef ref, int direction) {
  final days = ref.read(calendarDayCountProvider);
  final start = ref.read(calendarRangeStartProvider);
  ref.read(calendarRangeStartProvider.notifier).state = calendarAddDays(
    start,
    direction * days,
  );
}

/// Shifts the viewed range by [days] (negative = earlier) — the arrow keys
/// and Shift+scroll move one day at a time, unlike the header's page-sized
/// [shiftCalendarRange].
void shiftCalendarDays(WidgetRef ref, int days) {
  final start = ref.read(calendarRangeStartProvider);
  ref.read(calendarRangeStartProvider.notifier).state = calendarAddDays(
    start,
    days,
  );
}

/// How many hours of a day the calendar grid shows at once (its zoom); one
/// of [kCalendarZoomHours].
final calendarVisibleHoursProvider = StateProvider<int>(
  (ref) => kCalendarDefaultZoomHours,
);

/// Ctrl++ / Ctrl+- / Ctrl+scroll: [direction] > 0 zooms in (fewer hours
/// visible), < 0 zooms out.
void zoomCalendar(WidgetRef ref, int direction) {
  final notifier = ref.read(calendarVisibleHoursProvider.notifier);
  notifier.state = stepZoomHours(notifier.state, direction);
}

/// The calendar event last clicked (Delete removes it); null = none.
final calendarSelectedActionProvider = StateProvider<String?>((ref) => null);

/// The "Today" button: re-anchors for the current day count.
void goToCalendarToday(WidgetRef ref) {
  ref.read(calendarRangeStartProvider.notifier).state = calendarAnchorStart(
    DateTime.now().toUtc(),
    ref.read(calendarDayCountProvider),
  );
}

/// All metrics, for the action editor's metric picker.
final metricsProvider = StreamProvider.autoDispose<List<Metric>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.metricsTable).watch();
});

final metricServiceProvider = Provider<MetricService>(
  (ref) => MetricService(ref.watch(databaseProvider)),
);

/// The "depends on" edges between growth directions.
final metricDependenciesProvider =
    StreamProvider.autoDispose<List<MetricDependency>>((ref) {
      final db = ref.watch(databaseProvider);
      return db.select(db.metricDependenciesTable).watch();
    });

/// Actions linked to growth directions, as (metric id, action).
final metricLinkedActionsProvider =
    StreamProvider.autoDispose<List<(String, ActionRow)>>(
      (ref) => ref.watch(viewQueriesProvider).watchMetricLinkedActions(),
    );

/// Ticks once a minute so anything time-dependent (rolling windows, actions
/// becoming done as their end time passes) is recomputed.
final minuteTickProvider = StreamProvider.autoDispose<int>(
  (ref) => Stream.periodic(const Duration(minutes: 1), (i) => i),
);

/// Progress, weight and urgency of every growth direction, live.
final growthSnapshotProvider = Provider.autoDispose<AsyncValue<GrowthSnapshot>>(
  (ref) {
    ref.watch(minuteTickProvider);
    final metrics = ref.watch(metricsProvider);
    final dependencies = ref.watch(metricDependenciesProvider);
    final linked = ref.watch(metricLinkedActionsProvider);

    for (final v in [metrics, dependencies, linked]) {
      if (v.hasError) return AsyncValue.error(v.error!, v.stackTrace!);
    }
    if (!metrics.hasValue || !dependencies.hasValue || !linked.hasValue) {
      return const AsyncValue.loading();
    }

    final graph = GrowthGraph([
      for (final e in dependencies.requireValue)
        (metricId: e.metricId, dependsOnId: e.dependsOnId),
    ]);
    final growthMetrics = [
      for (final m in metrics.requireValue) GrowthMetric.fromRow(m),
    ];
    final stats = computeStats(
      metrics: growthMetrics,
      graph: graph,
      facts: [
        for (final (metricId, action) in linked.requireValue)
          LinkedActionFact.fromAction(metricId, action),
      ],
      nowUtc: DateTime.now().toUtc(),
    );
    return AsyncValue.data(
      GrowthSnapshot(metrics: growthMetrics, graph: graph, stats: stats),
    );
  },
);

/// "Urgency to Keep in Balance" per action id (sum of its directions'
/// urgencies), live. Actions with no linked direction are absent.
final actionUrgencyProvider = Provider.autoDispose<Map<String, double>>((ref) {
  final snapshot = ref.watch(growthSnapshotProvider).value;
  final linked = ref.watch(metricLinkedActionsProvider).value;
  if (snapshot == null || linked == null) return const {};
  return actionUrgencies([
    for (final (metricId, action) in linked) (metricId, action.id),
  ], snapshot.stats);
});

/// All Countable Activities, for the action editor's activity picker.
final countableActivitiesProvider =
    StreamProvider.autoDispose<List<CountableActivity>>((ref) {
      final db = ref.watch(databaseProvider);
      return (db.select(
        db.countableActivitiesTable,
      )..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();
    });

/// All saved "new from template" presets.
final templatesProvider = StreamProvider.autoDispose<List<ActionTemplate>>((
  ref,
) {
  final db = ref.watch(databaseProvider);
  return db.select(db.actionTemplatesTable).watch();
});

/// All not-done actions, for the action editor's predecessor/successor
/// picker.
/// The rows have `notes` / `resultNote` == null (not read).
final openActionsProvider = StreamProvider.autoDispose<List<ActionRow>>(
  (ref) => ref.watch(viewQueriesProvider).watchOpenActions(),
);

/// The actions that must happen before [actionId] (its current predecessors).
final predecessorsOfProvider = StreamProvider.autoDispose
    .family<List<ActionRow>, String>((ref, actionId) {
      final db = ref.watch(databaseProvider);
      final query = db.select(db.actionsTable).join([
        innerJoin(
          db.actionDependenciesTable,
          db.actionDependenciesTable.predecessorId.equalsExp(
            db.actionsTable.id,
          ),
        ),
      ])..where(db.actionDependenciesTable.successorId.equals(actionId));
      return query.watch().map(
        (rows) => rows.map((r) => r.readTable(db.actionsTable)).toList(),
      );
    });

/// The actions that must happen after [actionId] (its current successors).
final successorsOfProvider = StreamProvider.autoDispose
    .family<List<ActionRow>, String>((ref, actionId) {
      final db = ref.watch(databaseProvider);
      final query = db.select(db.actionsTable).join([
        innerJoin(
          db.actionDependenciesTable,
          db.actionDependenciesTable.successorId.equalsExp(db.actionsTable.id),
        ),
      ])..where(db.actionDependenciesTable.predecessorId.equals(actionId));
      return query.watch().map(
        (rows) => rows.map((r) => r.readTable(db.actionsTable)).toList(),
      );
    });

/// Ids of every action that's currently running (started but not yet
/// finished) — lets a tile/card mark itself as running without opening the
/// action. `actions.start_at` (not this table) is the single source for
/// *when* it started; this only answers "is it running at all."
final runningOccurrencesProvider = StreamProvider.autoDispose<Set<String>>((
  ref,
) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.actionOccurrencesTable)
    ..where((t) => t.finishedAt.isNull());
  return query.watch().map((rows) => rows.map((r) => r.actionId).toSet());
});

/// [actionId]'s start/finish/postpone history, most recent first — lets
/// the editor show when an action was actually started/finished, as
/// opposed to `actions.start_at`/`end_at`, which is only the *scheduled*
/// time.
final occurrencesOfProvider = StreamProvider.autoDispose
    .family<List<ActionOccurrence>, String>((ref, actionId) {
      final db = ref.watch(databaseProvider);
      final query = db.select(db.actionOccurrencesTable)
        ..where((t) => t.actionId.equals(actionId))
        ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]);
      return query.watch();
    });

/// All actions regardless of status, most recently updated first — the
/// "see everything, including finished" view.
final allActionsProvider = StreamProvider.autoDispose<List<ActionListItem>>(
  (ref) => ref.watch(viewQueriesProvider).watchAllActions(),
);

/// The metric ids currently linked to [actionId].
final metricIdsOfProvider = StreamProvider.autoDispose
    .family<List<String>, String>((ref, actionId) {
      final db = ref.watch(databaseProvider);
      final query = db.select(db.actionMetricsTable)
        ..where((t) => t.actionId.equals(actionId));
      return query.watch().map((rows) => rows.map((r) => r.metricId).toList());
    });
