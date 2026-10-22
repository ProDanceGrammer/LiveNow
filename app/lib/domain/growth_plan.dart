import '../core/local_time.dart';
import 'date_range_filter.dart';
import 'growth_rules.dart';
import 'plan_rules.dart' show planDateOf;

// The Treemap's PLANNED-hours mode: how many hours the owner has planned per
// day / week / month / year across the hour-dependent directions (kind `hours`,
// from the target + window typed on each), against the hours available in that
// span, and where it is overplanned. Pure, like the rest of the growth rules.

/// What the Treemap measures: finished time, or planned hours.
enum TreemapMode {
  time('Time spent'),
  planned('Planned hours');

  const TreemapMode(this.label);
  final String label;

  static TreemapMode? byName(Object? name) =>
      TreemapMode.values.where((m) => m.name == name).firstOrNull;
}

/// The span the plan is shown for. It is a REAL Istanbul span ending today
/// (so the plan and "time really spent" cover the same dates): today, the last
/// 7 days, one calendar month back, one calendar year back.
enum PlanSpan {
  day('Day'),
  week('Week'),
  month('Month'),
  year('Year');

  const PlanSpan(this.label);
  final String label;

  /// The first day of the span (Istanbul midnight, as UTC).
  DateTime start(DateTime nowUtc) => switch (this) {
    PlanSpan.day => localDayStart(nowUtc),
    PlanSpan.week => windowStart(nowUtc, MetricWindow.week),
    PlanSpan.month => windowStart(nowUtc, MetricWindow.month),
    PlanSpan.year => windowStart(nowUtc, MetricWindow.year),
  };

  static PlanSpan? byName(Object? name) =>
      PlanSpan.values.where((s) => s.name == name).firstOrNull;
}

/// Inclusive Istanbul days from [fromUtc] to [untilUtc] (both are the start of
/// their day). Counted on the DATES, never as an instant difference.
int daysInclusive(DateTime fromUtc, DateTime untilUtc) =>
    planDateOf(untilUtc).difference(planDateOf(fromUtc)).inDays + 1;

/// The dates a plan is shown for: both ends are the start of their day (the
/// last day is included) and [days] counts them.
class PlanRange {
  const PlanRange(this.from, this.until, this.days);
  final DateTime from;
  final DateTime until;
  final int days;

  /// As a filter, for the "time really spent" side.
  DateRangeFilter get filter => DateRangeFilter(from: from, until: until);

  @override
  bool operator ==(Object other) =>
      other is PlanRange &&
      other.from == from &&
      other.until == until &&
      other.days == days;

  @override
  int get hashCode => Object.hash(from, until, days);
}

/// The range the plan covers: the custom [range] when it is active and closed
/// (both dates, from not after until), else [span] up to today. Null for an
/// active range that cannot be planned over (open-ended or empty).
PlanRange? resolvePlanRange({
  required PlanSpan span,
  required DateRangeFilter range,
  required DateTime nowUtc,
}) {
  if (range.active) {
    final r = range.resolved(nowUtc);
    final from = r.from;
    final until = r.until;
    if (from == null || until == null || from.isAfter(until)) return null;
    return PlanRange(from, until, daysInclusive(from, until));
  }
  final from = span.start(nowUtc);
  final until = localDayStart(nowUtc);
  return PlanRange(from, until, daysInclusive(from, until));
}

/// How many days a direction's own window stands for when its target is turned
/// into a per-day rate. Averages (a calendar month is 28-31 days, a year 365 or
/// 366): the plan is a rate, not a calendar fact.
double windowDays(MetricWindow window) => switch (window) {
  MetricWindow.week => 7,
  MetricWindow.month => 30.4375,
  MetricWindow.year => 365.25,
  MetricWindow.fiveYears => 1826.25,
};

/// Whether [m] has a plan to show: an hours direction with a window and a
/// positive target.
bool isPlannable(GrowthMetric m) =>
    m.kind == MetricKind.hours && m.window != null && m.target > 0;

/// Planned hours of [m] over [spanDays] days: its target spread evenly over its
/// window. Zero for a direction that is not plannable.
double plannedHours(GrowthMetric m, double spanDays) =>
    isPlannable(m) ? m.target * spanDays / windowDays(m.window!) : 0;

/// One direction's planned hours.
class PlanBlock {
  const PlanBlock(this.metric, this.hours);
  final GrowthMetric metric;
  final double hours;
}

/// The plan for a span: the blocks (biggest first, then by id so the order
/// never shuffles), what they add up to, and the check against the hours
/// available.
class PlanReport {
  const PlanReport({
    required this.blocks,
    required this.total,
    required this.available,
    required this.days,
  });

  final List<PlanBlock> blocks;
  final double total;

  /// Hours available in the span (hours per day x days).
  final double available;
  final int days;

  /// Hours planned beyond the available ones (zero when it fits).
  double get over => total > available ? total - available : 0;
  bool get overplanned => total > available + 1e-9;

  /// Hours still free when it fits.
  double get free => total < available ? available - total : 0;

  /// By how much EVERY plan would have to shrink to fit (0..1).
  double get shrinkFraction => overplanned && total > 0 ? over / total : 0;

  /// The biggest plans, the first to re-estimate.
  List<PlanBlock> biggest([int n = 3]) => blocks.take(n).toList();

  /// The share of the available hours one block takes (0..).
  double share(PlanBlock b) => available <= 0 ? 0 : b.hours / available;
}

/// The plan of the [included] directions among [metrics] (null = every
/// plannable one) over [range], against [hoursPerDay] available each day.
/// Directions that are not plannable, or whose plan is zero, are left out.
PlanReport buildPlan({
  required Iterable<GrowthMetric> metrics,
  required Set<String>? included,
  required PlanRange range,
  double hoursPerDay = 24,
}) {
  final blocks = <PlanBlock>[
    for (final m in metrics)
      if (isPlannable(m) && (included == null || included.contains(m.id)))
        if (plannedHours(m, range.days.toDouble()) > 0)
          PlanBlock(m, plannedHours(m, range.days.toDouble())),
  ]..sort((a, b) {
      final byHours = b.hours.compareTo(a.hours);
      return byHours != 0 ? byHours : a.metric.id.compareTo(b.metric.id);
    });
  return PlanReport(
    blocks: blocks,
    total: blocks.fold(0.0, (sum, b) => sum + b.hours),
    available: hoursPerDay * range.days,
    days: range.days,
  );
}

/// Hours as short text: `8 h`, `5.5 h`, `45 min` for under an hour.
String formatHours(double hours) {
  if (hours < 1) {
    final minutes = (hours * 60).round();
    return minutes <= 0 ? '0 h' : '$minutes min';
  }
  final rounded = (hours * 10).round() / 10;
  return rounded == rounded.roundToDouble()
      ? '${rounded.round()} h'
      : '${rounded.toStringAsFixed(1)} h';
}
