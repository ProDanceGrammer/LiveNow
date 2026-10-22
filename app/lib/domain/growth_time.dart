import 'date_range_filter.dart';
import 'growth_rules.dart';

// Time spent per growth direction (the Treemap tab) and the filter the List and
// Treemap tabs share. Pure, like the rest of the growth rules.

/// The period the Treemap measures time over. One period for every direction
/// (boolean directions have no window of their own, and blocks of different
/// windows would not be comparable). Windows are the same rolling, day-aligned
/// Istanbul ones the directions use ([windowStart]).
enum TreemapPeriod {
  week('Week'),
  month('Month'),
  year('Year'),
  fiveYears('5 years'),
  all('All time');

  const TreemapPeriod(this.label);
  final String label;

  /// The UTC instant the period reaches back to, or null = no limit.
  DateTime? since(DateTime nowUtc) => switch (this) {
    TreemapPeriod.week => windowStart(nowUtc, MetricWindow.week),
    TreemapPeriod.month => windowStart(nowUtc, MetricWindow.month),
    TreemapPeriod.year => windowStart(nowUtc, MetricWindow.year),
    TreemapPeriod.fiveYears => windowStart(nowUtc, MetricWindow.fiveYears),
    TreemapPeriod.all => null,
  };

  /// The period saved under [name], or null.
  static TreemapPeriod? byName(Object? name) =>
      TreemapPeriod.values.where((p) => p.name == name).firstOrNull;
}

/// Finished time per direction id over [period]: the durations of the linked
/// actions that count as done (the app's derived rule) and fall in the period
/// by their start (else last change). Whatever the direction's kind: boolean
/// and count directions get a time too. An action linked to several directions
/// counts fully in each of them, so the sum over directions is not unique time.
/// A direction with no such action is absent.
///
/// An active custom [range] (calendar days, both ends included, see
/// [DateRangeFilter]) REPLACES the period: only actions whose start (else last
/// change) falls on a day inside it count. It is resolved ONCE here, against the
/// same [nowUtc], so a quick preset such as "Last week" means today's dates.
Map<String, Duration> timeSpentPerDirection(
  Iterable<LinkedActionFact> facts, {
  required DateTime nowUtc,
  required TreemapPeriod period,
  DateRangeFilter? range,
}) {
  final since = period.since(nowUtc);
  final custom = range != null && range.active ? range.resolved(nowUtc) : null;
  final seconds = <String, int>{};
  for (final f in facts) {
    if (!f.isDone) continue;
    if (custom != null) {
      if (!custom.contains(f.windowTime, nowUtc: nowUtc)) continue;
    } else if (since != null && f.windowTime.isBefore(since)) {
      continue;
    }
    seconds[f.metricId] = (seconds[f.metricId] ?? 0) + f.duration.inSeconds;
  }
  return {
    for (final e in seconds.entries) e.key: Duration(seconds: e.value),
  };
}

/// The directions the List and Treemap tabs show for the shared filters: a
/// name that contains [query] (trimmed, case-insensitive) and, when [kind] is
/// set, that type.
List<GrowthMetric> filterDirections(
  Iterable<GrowthMetric> metrics, {
  String query = '',
  MetricKind? kind,
}) {
  final q = query.trim().toLowerCase();
  return [
    for (final m in metrics)
      if ((kind == null || m.kind == kind) &&
          (q.isEmpty || m.name.toLowerCase().contains(q)))
        m,
  ];
}
