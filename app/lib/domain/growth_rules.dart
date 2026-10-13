import 'dart:math' as math;

import '../core/local_time.dart';
import '../core/time_codec.dart';
import '../data/database.dart';
import 'done_rule.dart';
import 'duration_rules.dart';

// Growth directions ("metrics"): windows, progress, weight, urgency and the
// Balance Dashboard boards. Everything here is pure (no database), so the
// rules from the author's Notion system stay testable in isolation.

/// Progress (%) at which a direction counts as balanced, i.e. urgency 0.
const double kBalanceThreshold = 90;

/// Weight of a main growth direction, and its importance level.
const double kMainWeight = 1000;
const int kMainImportanceLevel = 10;

enum MetricKind {
  boolean,
  count,
  hours;

  String get dbValue => name;
  static MetricKind fromDb(String value) => values.byName(value);
}

/// How far back finished actions count toward a count/hours direction.
enum MetricWindow {
  week('week'),
  month('month'),
  year('year'),
  fiveYears('five_years');

  final String dbValue;
  const MetricWindow(this.dbValue);

  static MetricWindow? fromDb(String? value) =>
      value == null ? null : values.firstWhere((w) => w.dbValue == value);
}

/// A [Metric] row without the database types, the shape the rules work on.
/// A direction's name as shown in lists: `🚓 Name`, or the bare name.
String metricLabel(String name, String? icon) =>
    icon == null || icon.isEmpty ? name : '$icon $name';

class GrowthMetric {
  final String id;
  final String name;
  final MetricKind kind;
  final MetricWindow? window;
  final double target;
  final bool isMain;
  final double weight;
  final int importanceLevel;

  /// An emoji shown before the name, or null.
  final String? icon;

  /// Mindmap position, or null when the node has not been placed yet.
  final double? posX;
  final double? posY;

  const GrowthMetric({
    required this.id,
    required this.name,
    required this.kind,
    this.window,
    this.target = 1,
    this.isMain = false,
    this.weight = 0,
    this.importanceLevel = 0,
    this.icon,
    this.posX,
    this.posY,
  });

  /// The name as shown in lists: `🚓 Name`, or just the name without an icon.
  String get label => metricLabel(name, icon);

  factory GrowthMetric.fromRow(Metric row) => GrowthMetric(
    id: row.id,
    name: row.name,
    kind: MetricKind.fromDb(row.kind),
    window: MetricWindow.fromDb(row.timeWindow),
    target: row.target,
    isMain: row.isMain,
    weight: row.weight,
    importanceLevel: row.importanceLevel,
    icon: row.icon,
    posX: row.posX,
    posY: row.posY,
  );
}

// ---- windows, progress, urgency ---------------------------------------------

/// The UTC instant a window reaches back to: rolling and day-aligned in the
/// app's timezone, like the Notion formulas (`today().dateSubtract(...)`).
/// A week is the last 7 calendar days including today; a month is one
/// calendar month back, a year one calendar year, "5 years" five.
DateTime windowStart(DateTime nowUtc, MetricWindow window) => switch (window) {
  MetricWindow.week => calendarAddDays(localDayStart(nowUtc), -6),
  MetricWindow.month => localDayStartMonthsBack(nowUtc, 1),
  MetricWindow.year => localDayStartMonthsBack(nowUtc, 12),
  MetricWindow.fiveYears => localDayStartMonthsBack(nowUtc, 60),
};

/// The directions that still NEED DATA: no linked action with a start date in
/// the direction's period (the last week/month/year...) or after it, i.e. in
/// the future. [links] are (metricId, the action's start or null). A boolean
/// direction has no period: any dated linked action counts. Linked actions
/// without a date, and a direction with no links at all, do not count.
///
/// A direction that DEPENDS on other directions ([dependentIds]: it has
/// sub-directions) is never listed: it takes its progress from them, so it
/// is not missing data of its own.
Set<String> directionsNeedingData({
  required Iterable<GrowthMetric> metrics,
  required Iterable<(String, DateTime?)> links,
  required DateTime nowUtc,
  Set<String> dependentIds = const {},
}) {
  final since = <String, DateTime?>{
    for (final m in metrics)
      m.id: m.kind == MetricKind.boolean
          ? null
          : windowStart(nowUtc, m.window ?? MetricWindow.week),
  };
  final hasData = <String>{};
  for (final (metricId, start) in links) {
    if (start == null || !since.containsKey(metricId)) continue;
    final from = since[metricId];
    // "In the window or in the future" is one comparison: the window starts
    // in the past.
    if (from == null || !start.isBefore(from)) hasData.add(metricId);
  }
  return {
    for (final m in metrics)
      if (!hasData.contains(m.id) && !dependentIds.contains(m.id)) m.id,
  };
}

/// [fact] as a percentage of [target], rounded to 2 decimals and NOT capped
/// (12.5 h of a 7 h target is 178.57%). A non-positive target gives 0.
double progressPercent(double fact, double target) {
  if (target <= 0) return 0;
  return (fact * 100 / target * 100).round() / 100;
}

/// `U = max(0, W × (1 − P/90)) − min(1, max(0, P − 90)) × P² / W`: how urgently
/// the direction needs attention. Zero from the threshold up to P = 90, then
/// negative as the direction is over-performed (the penalty saturates at one
/// P-point over the threshold). A zero-weight direction has no penalty (the
/// formula would divide by zero).
double urgencyOf(double weight, double progress) {
  final deficit = math.max(0.0, weight * (1 - progress / kBalanceThreshold));
  final over = math.min(1.0, math.max(0.0, progress - kBalanceThreshold));
  final penalty = weight > 0 ? over * progress * progress / weight : 0.0;
  return deficit - penalty;
}

// ---- the direction graph ----------------------------------------------------

typedef MetricEdge = ({String metricId, String dependsOnId});

/// "metricId depends on dependsOnId" edges, indexed both ways. Going *down*
/// (dependsOn) reaches the sub-directions; going *up* (leadsTo) reaches the
/// larger goals a direction contributes to.
class GrowthGraph {
  final Map<String, Set<String>> _dependsOn = {};
  final Map<String, Set<String>> _leadsTo = {};

  GrowthGraph(Iterable<MetricEdge> edges) {
    for (final e in edges) {
      _dependsOn.putIfAbsent(e.metricId, () => {}).add(e.dependsOnId);
      _leadsTo.putIfAbsent(e.dependsOnId, () => {}).add(e.metricId);
    }
  }

  Set<String> dependsOnOf(String id) => _dependsOn[id] ?? const {};
  Set<String> leadsToOf(String id) => _leadsTo[id] ?? const {};

  /// Every direction reachable upwards from [id] (unique, [id] excluded).
  Set<String> ancestorsOf(String id) {
    final seen = <String>{};
    final queue = [...leadsToOf(id)];
    while (queue.isNotEmpty) {
      final next = queue.removeLast();
      if (seen.add(next)) queue.addAll(leadsToOf(next));
    }
    seen.remove(id);
    return seen;
  }

  /// Whether the edges contain a cycle (Kahn's algorithm).
  bool get hasCycle {
    final nodes = {..._dependsOn.keys, ..._leadsTo.keys};
    final remainingDeps = {for (final n in nodes) n: dependsOnOf(n).length};
    final ready = [
      for (final e in remainingDeps.entries)
        if (e.value == 0) e.key,
    ];
    var visited = 0;
    while (ready.isNotEmpty) {
      final n = ready.removeLast();
      visited++;
      for (final parent in leadsToOf(n)) {
        remainingDeps[parent] = remainingDeps[parent]! - 1;
        if (remainingDeps[parent] == 0) ready.add(parent);
      }
    }
    return visited != nodes.length;
  }
}

/// `Importance level`: 10 for a main direction, then one less per hop of the
/// shortest path up to a main one (never below 1 once connected); 0 when no
/// main direction is reachable.
Map<String, int> importanceLevels(
  Iterable<String> ids,
  Set<String> mainIds,
  GrowthGraph graph,
) {
  final distance = <String, int>{for (final m in mainIds) m: 0};
  final queue = [...mainIds];
  var head = 0;
  while (head < queue.length) {
    final current = queue[head++];
    for (final child in graph.dependsOnOf(current)) {
      if (distance.containsKey(child)) continue;
      distance[child] = distance[current]! + 1;
      queue.add(child);
    }
  }
  return {
    for (final id in ids)
      id: mainIds.contains(id)
          ? kMainImportanceLevel
          : distance.containsKey(id)
          ? (kMainImportanceLevel - distance[id]!).clamp(
              1,
              kMainImportanceLevel,
            )
          : 0,
  };
}

/// A main direction weighs 1000; any other one weighs its importance level
/// times the sum of the levels of all its unique ancestors — the Notion
/// formula `sum(map(All Leadings.unique(), Importance level)) * Importance level`.
Map<String, double> directionWeights(
  Iterable<String> ids,
  Set<String> mainIds,
  GrowthGraph graph,
  Map<String, int> levels,
) {
  return {
    for (final id in ids)
      id: mainIds.contains(id)
          ? kMainWeight
          : (levels[id] ?? 0) *
                graph
                    .ancestorsOf(id)
                    .fold<int>(0, (sum, a) => sum + (levels[a] ?? 0))
                    .toDouble(),
  };
}

// ---- live stats -------------------------------------------------------------

/// One action linked to one direction, reduced to what progress needs.
class LinkedActionFact {
  final String metricId;

  /// The app's derived Done Before rule.
  final bool isDone;

  /// Which window the action falls into: its start, else its last change.
  final DateTime windowTime;

  final Duration duration;

  const LinkedActionFact({
    required this.metricId,
    required this.isDone,
    required this.windowTime,
    required this.duration,
  });

  factory LinkedActionFact.fromAction(String metricId, ActionRow action) {
    final start = dateTimeFromDb(action.startAt);
    final end = dateTimeFromDb(action.endAt);
    return LinkedActionFact(
      metricId: metricId,
      isDone: isDoneBefore(
        startAt: start,
        endAt: end,
        isAllDay: action.isAllDay,
        done: action.done,
      ),
      windowTime: start ?? dateTimeFromDb(action.updatedAt)!,
      duration: computeActionDuration(
        startAt: start,
        endAt: end,
        legacyEstimatedMinutes: action.estimatedMinutes,
      ),
    );
  }
}

class MetricStat {
  /// The counted amount: finished actions, or hours.
  final double fact;
  final double progress;
  final double urgency;

  const MetricStat({
    required this.fact,
    required this.progress,
    required this.urgency,
  });
}

/// Progress and urgency for every direction, at [nowUtc].
///
/// - count/hours: what the linked, finished actions inside the window add up
///   to (1 each, or their duration in hours), as a percentage of the target.
/// - boolean with linked actions: the share of them that are finished.
/// - boolean without: the mean of its sub-directions' progress, each capped
///   at 100%; 0 when it has neither.
Map<String, MetricStat> computeStats({
  required List<GrowthMetric> metrics,
  required GrowthGraph graph,
  required Iterable<LinkedActionFact> facts,
  required DateTime nowUtc,
}) {
  final byId = {for (final m in metrics) m.id: m};
  final factsByMetric = <String, List<LinkedActionFact>>{};
  for (final f in facts) {
    factsByMetric.putIfAbsent(f.metricId, () => []).add(f);
  }

  final amounts = <String, double>{};
  final progress = <String, double>{};
  final inProgress = <String>{};

  double progressOf(String id) {
    final known = progress[id];
    if (known != null) return known;
    final metric = byId[id];
    if (metric == null || !inProgress.add(id)) return 0; // unknown / cycle
    final linked = factsByMetric[id] ?? const <LinkedActionFact>[];

    double value;
    switch (metric.kind) {
      case MetricKind.count:
      case MetricKind.hours:
        final since = windowStart(nowUtc, metric.window ?? MetricWindow.week);
        var amount = 0.0;
        for (final f in linked) {
          if (!f.isDone || f.windowTime.isBefore(since)) continue;
          amount += metric.kind == MetricKind.count
              ? 1
              : f.duration.inSeconds / 3600;
        }
        amounts[id] = amount;
        value = progressPercent(amount, metric.target);
      case MetricKind.boolean:
        final children = graph.dependsOnOf(id);
        if (linked.isNotEmpty) {
          final done = linked.where((f) => f.isDone).length;
          amounts[id] = done.toDouble();
          value = progressPercent(done.toDouble(), linked.length.toDouble());
        } else if (children.isNotEmpty) {
          var sum = 0.0;
          for (final c in children) {
            final p = progressOf(c);
            sum += p > 100 ? 100 : p;
          }
          value = (sum / children.length * 100).round() / 100;
        } else {
          value = 0;
        }
    }

    inProgress.remove(id);
    return progress[id] = value;
  }

  final stats = <String, MetricStat>{};
  for (final m in metrics) {
    final p = progressOf(m.id);
    stats[m.id] = MetricStat(
      fact: amounts[m.id] ?? 0,
      progress: p,
      urgency: urgencyOf(m.weight, p),
    );
  }
  return stats;
}

/// Everything the growth-direction screens show, computed together at one
/// instant so the tabs never disagree.
class GrowthSnapshot {
  final List<GrowthMetric> metrics;
  final GrowthGraph graph;
  final Map<String, MetricStat> stats;

  GrowthSnapshot({
    required this.metrics,
    required this.graph,
    required this.stats,
  });

  late final Map<String, GrowthMetric> byId = {
    for (final m in metrics) m.id: m,
  };

  MetricStat? statOf(String id) => stats[id];
}

// ---- Balance Dashboard ------------------------------------------------------

enum BalanceGroup { daily, weekly, monthly }

enum BalanceSide { focusOn, decreaseIt }

/// Rows each dashboard board shows before "Show more".
const int kBalancePageSize = 10;

/// Which dashboard row a direction belongs to (null = not on the dashboard):
/// weekly windows split by how often the target is hit (more than 7 actions or
/// 3 hours a week is "daily"), 30-day ones are "monthly"; boolean, yearly and
/// 5-year directions are not shown. Mirrors the Notion board filters.
BalanceGroup? balanceGroupOf(GrowthMetric m) {
  if (m.kind == MetricKind.boolean) return null;
  switch (m.window) {
    case MetricWindow.week:
      final dailyAbove = m.kind == MetricKind.count ? 7 : 3;
      return m.target > dailyAbove ? BalanceGroup.daily : BalanceGroup.weekly;
    case MetricWindow.month:
      return BalanceGroup.monthly;
    case MetricWindow.year:
    case MetricWindow.fiveYears:
    case null:
      return null;
  }
}

/// "Decrease It" shows directions whose urgency is below this limit.
double decreaseUrgencyLimit(BalanceGroup group) => switch (group) {
  BalanceGroup.daily => 1,
  BalanceGroup.weekly => 10,
  BalanceGroup.monthly => 100,
};

class BalanceRow {
  final GrowthMetric metric;
  final MetricStat stat;

  const BalanceRow(this.metric, this.stat);
}

/// The rows of one dashboard board: Focus On = urgency above 0, most urgent
/// first; Decrease It = urgency below the group's limit, lowest first.
List<BalanceRow> balanceBoard(
  BalanceGroup group,
  BalanceSide side,
  List<GrowthMetric> metrics,
  Map<String, MetricStat> stats,
) {
  final rows = <BalanceRow>[];
  for (final m in metrics) {
    final stat = stats[m.id];
    if (stat == null || balanceGroupOf(m) != group) continue;
    final accepted = side == BalanceSide.focusOn
        ? stat.urgency > 0
        : stat.urgency < decreaseUrgencyLimit(group);
    if (accepted) rows.add(BalanceRow(m, stat));
  }
  rows.sort((a, b) {
    final byUrgency = side == BalanceSide.focusOn
        ? b.stat.urgency.compareTo(a.stat.urgency)
        : a.stat.urgency.compareTo(b.stat.urgency);
    return byUrgency != 0 ? byUrgency : a.metric.name.compareTo(b.metric.name);
  });
  return rows;
}

/// Mean progress of [rows] (the board's footer), or null when empty.
double? averageProgress(List<BalanceRow> rows) => rows.isEmpty
    ? null
    : rows.fold<double>(0, (s, r) => s + r.stat.progress) / rows.length;
