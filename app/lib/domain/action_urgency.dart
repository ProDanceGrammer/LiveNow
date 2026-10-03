import 'growth_rules.dart';

/// "Urgency to Keep in Balance" of an action: the sum of the urgencies of the
/// growth directions it is linked to. Derived live (direction urgency changes
/// with the rolling windows), never stored. Null when the action has no linked
/// direction.
double? actionUrgency(
  Iterable<String> metricIds,
  Map<String, MetricStat> stats,
) {
  double? sum;
  for (final id in metricIds) {
    final stat = stats[id];
    if (stat != null) sum = (sum ?? 0) + stat.urgency;
  }
  return sum;
}

/// Sums [actionUrgency] for every action in [links] (metric id, action id).
Map<String, double> actionUrgencies(
  Iterable<(String, String)> links,
  Map<String, MetricStat> stats,
) {
  final byAction = <String, List<String>>{};
  for (final (metricId, actionId) in links) {
    (byAction[actionId] ??= []).add(metricId);
  }
  return {
    for (final e in byAction.entries) e.key: ?actionUrgency(e.value, stats),
  };
}
