import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;

import '../domain/date_range_filter.dart';
import '../domain/growth_plan.dart';
import '../domain/growth_rules.dart';
import '../domain/growth_time.dart';
import 'device_prefs.dart';
import 'providers.dart';

// The Growth directions List and Treemap tabs share their search text and type
// filter (and the saved views): change one on a tab and the other follows, and
// it survives a tab switch.

final growthSearchProvider = StateProvider<String>((ref) => '');

final growthKindProvider = StateProvider<MetricKind?>((ref) => null);

/// The Treemap's period (session only; saved with a saved view).
final treemapPeriodProvider = StateProvider<TreemapPeriod>(
  (ref) => TreemapPeriod.month,
);

/// What the Treemap shows: finished time, or planned hours (session only; saved
/// with a saved view).
final treemapModeProvider = StateProvider<TreemapMode>(
  (ref) => TreemapMode.time,
);

/// A custom date range for the Treemap (session only; saved with a saved view).
/// Kept UNRESOLVED: a quick preset such as "Last week" is turned into dates each
/// time it is used, so it follows today.
final treemapRangeProvider = StateProvider<DateRangeFilter>(
  (ref) => const DateRangeFilter(),
);

/// The span of the planned-hours mode (a custom range overrides it).
final plannedSpanProvider = StateProvider<PlanSpan>((ref) => PlanSpan.day);

/// Device-local plan settings (ui_prefs.json).
const kPlanHoursKey = 'plan_hours_per_day';
const kPlanIncludedKey = 'plan_included_ids';

/// Hours available per day for the overplanned check (24 unless changed).
final plannedHoursPerDayProvider = Provider<double>((ref) {
  final v = ref.watch(devicePrefsProvider.select((m) => m[kPlanHoursKey]));
  return v is num && v > 0 && v <= 24 ? v.toDouble() : 24;
});

/// The hours directions chosen for the plan; null = every plannable one (the
/// starting state; a direction made later is only in once it is chosen).
final plannedIncludedProvider = Provider<Set<String>?>((ref) {
  final v = ref.watch(devicePrefsProvider.select((m) => m[kPlanIncludedKey]));
  if (v is! List) return null;
  return {
    for (final x in v)
      if (x is String) x,
  };
});

/// The planned-hours chart: the plan, the time really spent in the same dates,
/// and each direction's urgency (for the colour).
class PlannedData {
  const PlannedData({
    required this.range,
    required this.report,
    required this.spentHours,
    required this.urgency,
    required this.plannable,
  });

  /// The dates covered, or null when the custom range cannot be planned over
  /// (open at one end, or from after until).
  final PlanRange? range;
  final PlanReport report;

  /// Direction id -> hours really spent on it in [range].
  final Map<String, double> spentHours;
  final Map<String, double> urgency;

  /// How many hours directions exist at all (to tell "none yet" from "none
  /// chosen").
  final int plannable;

  static const invalidRange = PlannedData(
    range: null,
    report: PlanReport(blocks: [], total: 0, available: 0, days: 0),
    spentHours: {},
    urgency: {},
    plannable: 0,
  );

  @override
  bool operator ==(Object other) =>
      other is PlannedData &&
      other.range == range &&
      other.plannable == plannable &&
      other.report.total == report.total &&
      other.report.available == report.available &&
      other.report.blocks.length == report.blocks.length &&
      [
        for (var i = 0; i < report.blocks.length; i++)
          report.blocks[i].metric.id == other.report.blocks[i].metric.id &&
              report.blocks[i].hours == other.report.blocks[i].hours,
      ].every((same) => same) &&
      _sameMap(other.spentHours, spentHours) &&
      _sameMap(other.urgency, urgency);

  @override
  int get hashCode =>
      Object.hash(range, plannable, report.total, report.blocks.length);

  static bool _sameMap(Map<String, double> a, Map<String, double> b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);
}

/// The plan for the chosen span or custom range, recomputed every minute (the
/// snapshot ticks) and when directions, links, the choices or the range change.
/// One `nowUtc` serves the span, the range and the time spent.
final plannedDataProvider = Provider.autoDispose<AsyncValue<PlannedData>>((
  ref,
) {
  final snapshot = ref.watch(growthSnapshotProvider);
  final linked = ref.watch(metricLinkedActionsProvider);
  final span = ref.watch(plannedSpanProvider);
  final range = ref.watch(treemapRangeProvider);
  final hoursPerDay = ref.watch(plannedHoursPerDayProvider);
  final included = ref.watch(plannedIncludedProvider);
  final query = ref.watch(growthSearchProvider);

  if (snapshot.hasError) {
    return AsyncValue.error(snapshot.error!, snapshot.stackTrace!);
  }
  if (linked.hasError) {
    return AsyncValue.error(linked.error!, linked.stackTrace!);
  }
  if (!snapshot.hasValue || !linked.hasValue) {
    return const AsyncValue.loading();
  }

  final s = snapshot.requireValue;
  final nowUtc = DateTime.now().toUtc();
  final planRange = resolvePlanRange(span: span, range: range, nowUtc: nowUtc);
  if (planRange == null) return const AsyncValue.data(PlannedData.invalidRange);

  // The search text applies (the type filter would only hide everything: the
  // plan is hours directions by definition).
  final shown = filterDirections(s.metrics, query: query);
  final report = buildPlan(
    metrics: shown,
    included: included,
    range: planRange,
    hoursPerDay: hoursPerDay,
  );
  final spent = timeSpentPerDirection(
    [
      for (final (metricId, action) in linked.requireValue)
        LinkedActionFact.fromAction(metricId, action),
    ],
    nowUtc: nowUtc,
    period: TreemapPeriod.all,
    range: planRange.filter,
  );
  return AsyncValue.data(
    PlannedData(
      range: planRange,
      report: report,
      spentHours: {
        for (final b in report.blocks)
          b.metric.id: (spent[b.metric.id]?.inSeconds ?? 0) / 3600,
      },
      urgency: {
        for (final b in report.blocks)
          b.metric.id: s.stats[b.metric.id]?.urgency ?? 0,
      },
      plannable: s.metrics.where(isPlannable).length,
    ),
  );
});

/// One rectangle of the treemap: a direction and its finished time.
class TreemapBlock {
  const TreemapBlock(this.metric, this.time, this.urgency);
  final GrowthMetric metric;
  final Duration time;
  final double urgency;

  @override
  bool operator ==(Object other) =>
      other is TreemapBlock &&
      other.metric.id == metric.id &&
      other.time == time &&
      other.urgency == urgency;

  @override
  int get hashCode => Object.hash(metric.id, time, urgency);
}

/// What the Treemap draws: the directions that passed the filters and have
/// finished time in the period (biggest first), how many passed the filters
/// but have none, and the sum of the blocks.
class TreemapData {
  const TreemapData({
    required this.blocks,
    required this.withoutTime,
    required this.total,
  });
  final List<TreemapBlock> blocks;
  final int withoutTime;
  final Duration total;

  @override
  bool operator ==(Object other) =>
      other is TreemapData &&
      other.withoutTime == withoutTime &&
      other.total == total &&
      other.blocks.length == blocks.length &&
      [
        for (var i = 0; i < blocks.length; i++) blocks[i] == other.blocks[i],
      ].every((same) => same);

  @override
  int get hashCode => Object.hash(withoutTime, total, blocks.length);
}

/// Finished time per direction for the shared filters and the chosen period,
/// recomputed every minute (the snapshot ticks) and whenever links, directions
/// or the filters change.
final treemapDataProvider = Provider.autoDispose<AsyncValue<TreemapData>>((
  ref,
) {
  final snapshot = ref.watch(growthSnapshotProvider);
  final linked = ref.watch(metricLinkedActionsProvider);
  final period = ref.watch(treemapPeriodProvider);
  final range = ref.watch(treemapRangeProvider);
  final query = ref.watch(growthSearchProvider);
  final kind = ref.watch(growthKindProvider);

  if (snapshot.hasError) {
    return AsyncValue.error(snapshot.error!, snapshot.stackTrace!);
  }
  if (linked.hasError) {
    return AsyncValue.error(linked.error!, linked.stackTrace!);
  }
  if (!snapshot.hasValue || !linked.hasValue) {
    return const AsyncValue.loading();
  }

  final s = snapshot.requireValue;
  final times = timeSpentPerDirection(
    [
      for (final (metricId, action) in linked.requireValue)
        LinkedActionFact.fromAction(metricId, action),
    ],
    nowUtc: DateTime.now().toUtc(),
    period: period,
    range: range,
  );
  final shown = filterDirections(s.metrics, query: query, kind: kind);
  final blocks = <TreemapBlock>[
    for (final m in shown)
      if ((times[m.id] ?? Duration.zero) > Duration.zero)
        TreemapBlock(m, times[m.id]!, s.stats[m.id]?.urgency ?? 0),
  ]..sort((a, b) {
      final byTime = b.time.compareTo(a.time);
      return byTime != 0 ? byTime : a.metric.id.compareTo(b.metric.id);
    });
  return AsyncValue.data(
    TreemapData(
      blocks: blocks,
      withoutTime: shown.length - blocks.length,
      total: blocks.fold(Duration.zero, (sum, b) => sum + b.time),
    ),
  );
});
