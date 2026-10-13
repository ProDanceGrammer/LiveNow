import 'package:drift/drift.dart'
    show OrderingTerm, TableUpdate, TableUpdateQuery, innerJoin;
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;

import '../data/database.dart';
import '../data/queries.dart';
import '../domain/action_service.dart';
import 'work_hours.dart';
import '../domain/action_urgency.dart';
import '../domain/all_actions_view_rules.dart';
import '../domain/dependency_service.dart';
import '../domain/growth_rules.dart';
import '../domain/metric_service.dart';
import '../domain/name_sort.dart';
import 'views/calendar_layout.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final actionServiceProvider = Provider<ActionService>(
  (ref) => ActionService(
    ref.watch(databaseProvider),
    // Read at the moment of a postpone, so a change in Settings applies at once.
    workHours: () => ref.read(workHoursProvider),
  ),
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

/// The one instant the Current Actions board uses as "now": it is passed to
/// the SQL column queries AND to every card, so a card's colour/done state
/// always agrees with the column it sits in. Refreshed once a minute; the
/// queries re-run with it and `distinctList` drops unchanged results.
final currentBoardNowProvider = Provider.autoDispose<DateTime>((ref) {
  ref.watch(minuteTickProvider);
  return DateTime.now().toUtc();
});

/// The Current board's search text (the name filter; '' = no search).
final currentSearchProvider = StateProvider<String>((ref) => '');

/// The ids matching the search, or null while there is none. Only watched
/// while a search is active, so it costs nothing otherwise.
final currentSearchIdsProvider = StreamProvider.autoDispose<Set<String>?>((
  ref,
) {
  final q = ref.watch(currentSearchProvider).trim().toLowerCase();
  if (q.isEmpty) return Stream.value(null);
  return ref.watch(viewQueriesProvider).watchNameMatchIds(q);
});

/// Runs [build] with the search's id filter; while the ids are still loading
/// the board keeps its previous rows (an empty stream stays "loading").
Stream<T> _withSearch<T>(Ref ref, Stream<T> Function(Set<String>? ids) build) {
  final ids = ref.watch(currentSearchIdsProvider);
  if (!ids.hasValue) return const Stream.empty();
  return build(ids.value);
}

final currentNotDoneProvider = StreamProvider.autoDispose<List<ActionListItem>>(
  (ref) => _withSearch(
    ref,
    (ids) => ref
        .watch(viewQueriesProvider)
        .watchCurrentNotDone(
          limit: ref.watch(currentNotDoneLimitProvider),
          nowUtc: ref.watch(currentBoardNowProvider),
          onlyIds: ids,
        ),
  ),
);

final currentDoneProvider = StreamProvider.autoDispose<List<ActionListItem>>(
  (ref) => _withSearch(
    ref,
    (ids) => ref
        .watch(viewQueriesProvider)
        .watchCurrentDone(
          limit: ref.watch(currentDoneLimitProvider),
          nowUtc: ref.watch(currentBoardNowProvider),
          onlyIds: ids,
        ),
  ),
);

/// Total not-done actions (the column header shows this, not the page size).
final currentNotDoneCountProvider = StreamProvider.autoDispose<int>(
  (ref) => _withSearch(
    ref,
    (ids) => ref
        .watch(viewQueriesProvider)
        .watchCurrentNotDoneCount(
          nowUtc: ref.watch(currentBoardNowProvider),
          onlyIds: ids,
        ),
  ),
);

/// Total done actions.
final currentDoneCountProvider = StreamProvider.autoDispose<int>(
  (ref) => _withSearch(
    ref,
    (ids) => ref
        .watch(viewQueriesProvider)
        .watchCurrentDoneCount(
          nowUtc: ref.watch(currentBoardNowProvider),
          onlyIds: ids,
        ),
  ),
);

/// How many day columns the calendar shows (1..7; a phone offers 1..3).
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
/// 1..6 -> today.
void setCalendarDayCount(WidgetRef ref, int days) {
  ref.read(calendarDayCountProvider.notifier).state = days.clamp(1, 7);
  ref.read(calendarRangeStartProvider.notifier).state = calendarAnchorStart(
    DateTime.now().toUtc(),
    days.clamp(1, 7),
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

/// Bumped by the "Today" button; the time grid scrolls the now-line to the
/// viewport centre when it changes.
final calendarScrollToNowProvider = StateProvider<int>((ref) => 0);

/// The "Today" button: re-anchors for the current day count and scrolls the
/// grid to the current time.
void goToCalendarToday(WidgetRef ref) {
  ref.read(calendarScrollToNowProvider.notifier).state++;
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

final _actionsWrittenProvider = StreamProvider.autoDispose<Set<TableUpdate>>((
  ref,
) {
  final db = ref.watch(databaseProvider);
  return db.tableUpdates(TableUpdateQuery.onTable(db.actionsTable));
});

/// Average real duration per template id (30-day mean of its runs, see
/// `ActionService.templateAverage`); templates without runs are absent.
/// Recomputed when actions or templates change and every minute.
final templateAveragesProvider =
    FutureProvider.autoDispose<Map<String, Duration>>((ref) async {
      ref.watch(minuteTickProvider);
      final templates = ref.watch(templatesProvider).value ?? const [];
      ref.watch(_actionsWrittenProvider); // any write re-runs this
      final service = ref.read(actionServiceProvider);
      final out = <String, Duration>{};
      for (final t in templates) {
        final avg = await service.templateAverage(t.name);
        if (avg != null) out[t.id] = avg;
      }
      return out;
    });

/// All Countable Activities, for the action editor's activity picker.
final countableActivitiesProvider =
    StreamProvider.autoDispose<List<CountableActivity>>((ref) {
      final db = ref.watch(databaseProvider);
      return (db.select(
        db.countableActivitiesTable,
      )..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();
    });

/// All saved "new from template" presets, by name ignoring leading emoji.
final templatesProvider = StreamProvider.autoDispose<List<ActionTemplate>>((
  ref,
) {
  final db = ref.watch(databaseProvider);
  return db
      .select(db.actionTemplatesTable)
      .watch()
      .map(
        (rows) =>
            [...rows]..sort((a, b) => compareIgnoringEmoji(a.name, b.name)),
      );
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

/// All actions regardless of status, most recently updated first — the
/// "see everything, including finished" view.
final allActionsProvider = StreamProvider.autoDispose<List<ActionListItem>>(
  (ref) => ref.watch(viewQueriesProvider).watchAllActions(),
);

/// The search text above the All list (matched case-insensitively against the
/// loaded names in Dart; empty = everything).
final allActionsQueryProvider = StateProvider.autoDispose<String>((ref) => '');

/// Which fields the All list's search text is matched against.
final allActionsSearchFlagsProvider = StateProvider.autoDispose<SearchFlags>(
  (ref) => const SearchFlags(),
);

/// The All list's waterfall sort (default: last edited first).
final allActionsSortProvider = StateProvider.autoDispose<List<SortKey>>(
  (ref) => kDefaultAllActionsSort,
);

/// The All list's filters.
final allActionsFiltersProvider = StateProvider.autoDispose<AllActionsFilters>(
  (ref) => const AllActionsFilters(),
);

// Lean link streams for the All list; only watched while a filter / search
// flag needs them (autoDispose drops them otherwise).
final allActionsMetricIdsProvider =
    StreamProvider.autoDispose<Map<String, Set<String>>>(
      (ref) => ref.watch(viewQueriesProvider).watchActionMetricIds(),
    );

/// metric id -> emoji, blank icons skipped. Value-equal on purpose: a mindmap
/// drag rewrites pos_x/pos_y (the metrics stream fires) but not the icons, so
/// nothing downstream recomputes.
class _IconMap {
  final Map<String, String> byId;
  const _IconMap(this.byId);

  @override
  bool operator ==(Object other) =>
      other is _IconMap && mapEquals(byId, other.byId);

  @override
  int get hashCode => byId.length;
}

final _iconByMetricIdProvider = Provider.autoDispose<_IconMap>((ref) {
  return ref.watch(
    metricsProvider.select((a) {
      final out = <String, String>{};
      for (final m in a.value ?? const <Metric>[]) {
        final icon = m.icon?.trim();
        if (icon != null && icon.isNotEmpty) out[m.id] = icon;
      }
      return _IconMap(out);
    }),
  );
});

/// At most this many direction emojis are shown, then '+n'.
const kMaxDirectionIcons = 4;

/// actionId -> the emojis of its linked growth directions joined by spaces
/// ('A B C D +2'); actions without any icon are absent. Widgets should
/// `.select((m) => m[id])` so only the affected block/card rebuilds.
final actionDirectionIconsProvider = Provider.autoDispose<Map<String, String>>((
  ref,
) {
  final links =
      ref.watch(allActionsMetricIdsProvider).value ??
      const <String, Set<String>>{};
  final icons = ref.watch(_iconByMetricIdProvider).byId;
  if (icons.isEmpty) return const {};
  final out = <String, String>{};
  links.forEach((actionId, metricIds) {
    // UUIDv7 ids sort by creation time: a stable order.
    final ids = metricIds.where(icons.containsKey).toList()..sort();
    if (ids.isEmpty) return;
    final shown = ids.take(kMaxDirectionIcons).map((id) => icons[id]!);
    final extra = ids.length - kMaxDirectionIcons;
    out[actionId] = [...shown, if (extra > 0) '+$extra'].join(' ');
  });
  return out;
});

class _NameMap {
  final Map<String, String> byId;
  const _NameMap(this.byId);

  @override
  bool operator ==(Object other) =>
      other is _NameMap && mapEquals(byId, other.byId);

  @override
  int get hashCode => byId.length;
}

/// metric id -> name of the directions that have an icon (value-equal, like
/// [_iconByMetricIdProvider]).
final _nameByIconMetricIdProvider = Provider.autoDispose<_NameMap>((ref) {
  return ref.watch(
    metricsProvider.select((a) {
      final out = <String, String>{};
      for (final m in a.value ?? const <Metric>[]) {
        final icon = m.icon?.trim();
        if (icon != null && icon.isNotEmpty) out[m.id] = m.name;
      }
      return _NameMap(out);
    }),
  );
});

/// actionId -> the direction names matching the chunks of
/// [actionDirectionIconsProvider]'s string: one name per shown emoji, plus a
/// last entry listing the hidden names (joined by ', ') when the '+n' chunk is
/// present. Same ordering and cap as the icons provider. Read with `ref.read`
/// on hover only.
final actionDirectionNamesProvider =
    Provider.autoDispose<Map<String, List<String>>>((ref) {
      final links =
          ref.watch(allActionsMetricIdsProvider).value ??
          const <String, Set<String>>{};
      final names = ref.watch(_nameByIconMetricIdProvider).byId;
      if (names.isEmpty) return const {};
      final out = <String, List<String>>{};
      links.forEach((actionId, metricIds) {
        final ids = metricIds.where(names.containsKey).toList()..sort();
        if (ids.isEmpty) return;
        out[actionId] = [
          for (final id in ids.take(kMaxDirectionIcons)) names[id]!,
          if (ids.length > kMaxDirectionIcons)
            ids.skip(kMaxDirectionIcons).map((id) => names[id]!).join(', '),
        ];
      });
      return out;
    });

final allActionsPredecessorsProvider =
    StreamProvider.autoDispose<Map<String, Set<String>>>(
      (ref) => ref.watch(viewQueriesProvider).watchPredecessorIds(),
    );
final allActionsSuccessorsProvider =
    StreamProvider.autoDispose<Map<String, Set<String>>>(
      (ref) => ref.watch(viewQueriesProvider).watchSuccessorIds(),
    );

/// Ids of actions whose notes contain the (lower-cased) query; watched only
/// while the Notes flag is on and the query is not empty.
final allActionsNotesMatchProvider = StreamProvider.autoDispose
    .family<Set<String>, String>(
      (ref, lowerQuery) =>
          ref.watch(viewQueriesProvider).watchNotesMatchIds(lowerQuery),
    );

/// The metric ids currently linked to [actionId].
final metricIdsOfProvider = StreamProvider.autoDispose
    .family<List<String>, String>((ref, actionId) {
      final db = ref.watch(databaseProvider);
      final query = db.select(db.actionMetricsTable)
        ..where((t) => t.actionId.equals(actionId));
      return query.watch().map((rows) => rows.map((r) => r.metricId).toList());
    });
