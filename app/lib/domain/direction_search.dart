import 'growth_rules.dart' show GrowthMetric, metricLabel;
import 'name_sort.dart' show compareIgnoringEmoji;

String _fold(String s) => s.replaceAll('’', "'").toLowerCase().trim();

/// Growth directions whose label (emoji + name) contains [query], ignoring
/// case (Cyrillic included - done in Dart, not SQL) and `’` vs `'`. Names that
/// START with the query come first, then the rest, each group by name ignoring
/// the leading emoji. At most [limit] results; an empty query finds nothing.
List<GrowthMetric> searchDirections(
  Iterable<GrowthMetric> all,
  String query, {
  int limit = 8,
}) {
  final q = _fold(query);
  if (q.isEmpty) return const [];
  final starts = <GrowthMetric>[], contains = <GrowthMetric>[];
  for (final m in all) {
    final name = _fold(m.name);
    if (name.startsWith(q)) {
      starts.add(m);
    } else if (_fold(metricLabel(m.name, m.icon)).contains(q)) {
      contains.add(m);
    }
  }
  int byName(GrowthMetric a, GrowthMetric b) =>
      compareIgnoringEmoji(a.name, b.name);
  starts.sort(byName);
  contains.sort(byName);
  final out = [...starts, ...contains];
  return out.length <= limit ? out : out.sublist(0, limit);
}
