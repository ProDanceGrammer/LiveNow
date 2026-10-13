import 'name_sort.dart';

/// What the Templates list can be ordered by.
enum TemplateSortField {
  name('Name'),
  direction('Direction'),
  urgency('Urgency'),
  average('Average time'),
  manual('Manual time');

  final String label;
  const TemplateSortField(this.label);
}

class TemplateSortKey {
  final TemplateSortField field;
  final bool ascending;
  const TemplateSortKey(this.field, {this.ascending = true});

  TemplateSortKey toggled() => TemplateSortKey(field, ascending: !ascending);

  @override
  bool operator ==(Object other) =>
      other is TemplateSortKey &&
      other.field == field &&
      other.ascending == ascending;

  @override
  int get hashCode => Object.hash(field, ascending);
}

/// The values one template is compared on; null = it has none (such a
/// template goes LAST in both directions).
class TemplateSortInfo {
  final String name;

  /// Name of its first growth direction (A-Z, ignoring a leading emoji).
  final String? direction;
  final double? urgency;
  final int? averageMinutes;
  final int? manualMinutes;

  const TemplateSortInfo({
    required this.name,
    this.direction,
    this.urgency,
    this.averageMinutes,
    this.manualMinutes,
  });
}

/// The first of [names] when sorted A-Z ignoring a leading emoji; null when
/// there are none.
String? firstDirectionName(Iterable<String> names) {
  String? best;
  for (final n in names) {
    if (best == null || compareIgnoringEmoji(n, best) < 0) best = n;
  }
  return best;
}

int _compareOn(TemplateSortKey key, TemplateSortInfo a, TemplateSortInfo b) {
  int dir(int c) => key.ascending ? c : -c;
  int nullsLast<T>(T? x, T? y, int Function(T, T) cmp) {
    if (x == null && y == null) return 0;
    if (x == null) return 1;
    if (y == null) return -1;
    return dir(cmp(x, y));
  }

  switch (key.field) {
    case TemplateSortField.name:
      return dir(compareIgnoringEmoji(a.name, b.name));
    case TemplateSortField.direction:
      return nullsLast<String>(a.direction, b.direction, compareIgnoringEmoji);
    case TemplateSortField.urgency:
      return nullsLast<double>(a.urgency, b.urgency, (x, y) => x.compareTo(y));
    case TemplateSortField.average:
      return nullsLast<int>(
        a.averageMinutes,
        b.averageMinutes,
        (x, y) => x.compareTo(y),
      );
    case TemplateSortField.manual:
      return nullsLast<int>(
        a.manualMinutes,
        b.manualMinutes,
        (x, y) => x.compareTo(y),
      );
  }
}

/// A new list ordered by [sort] as a waterfall (the first key decides, later
/// keys break ties); remaining ties fall back to the name (A-Z), so the order
/// is always stable.
List<T> sortTemplates<T>(
  List<T> items,
  List<TemplateSortKey> sort,
  TemplateSortInfo Function(T) info,
) {
  final infos = {for (final t in items) t: info(t)};
  final out = List<T>.of(items);
  out.sort((x, y) {
    final a = infos[x]!, b = infos[y]!;
    for (final key in sort) {
      final c = _compareOn(key, a, b);
      if (c != 0) return c;
    }
    return compareIgnoringEmoji(a.name, b.name);
  });
  return out;
}
