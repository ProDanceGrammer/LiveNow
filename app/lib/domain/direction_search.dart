import 'growth_rules.dart' show GrowthMetric, metricLabel;
import 'name_sort.dart' show compareIgnoringEmoji;
import 'search_match.dart';

/// Growth directions whose name or label (emoji + name) contains [query],
/// ignoring case (Cyrillic included - done in Dart, not SQL) and `’` vs `'`.
/// Whole-word matches come first ("Do it" before "Digit"), then the rest (see
/// [rankMatches]); inside each group by name ignoring the leading emoji. At most
/// [limit] results; an empty query finds nothing.
List<GrowthMetric> searchDirections(
  Iterable<GrowthMetric> all,
  String query, {
  int limit = 8,
}) {
  if (foldSearch(query).isEmpty) return const [];
  final byName = all.toList()
    ..sort((a, b) => compareIgnoringEmoji(a.name, b.name));
  final out = rankMatches(
    byName,
    query,
    (m) => [m.name, metricLabel(m.name, m.icon)],
  );
  return out.length <= limit ? out : out.sublist(0, limit);
}
