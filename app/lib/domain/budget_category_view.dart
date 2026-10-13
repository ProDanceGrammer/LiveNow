import 'name_sort.dart';

/// What the Categories board can be ordered by.
enum CategorySortField {
  name('Name'),
  plan('Plan'),
  fact('Fact'),
  urgency('Urgency');

  final String label;
  const CategorySortField(this.label);
}

class CategorySortKey {
  final CategorySortField field;
  final bool ascending;
  const CategorySortKey(this.field, {this.ascending = true});

  CategorySortKey toggled() => CategorySortKey(field, ascending: !ascending);

  @override
  bool operator ==(Object other) =>
      other is CategorySortKey &&
      other.field == field &&
      other.ascending == ascending;

  @override
  int get hashCode => Object.hash(field, ascending);
}

/// The default order: by name, A-Z.
const List<CategorySortKey> kDefaultCategorySort = [
  CategorySortKey(CategorySortField.name),
];

/// The least a category must tell the arranging rules.
class CategoryInfo {
  const CategoryInfo(this.id, this.name, this.parentId);

  final String id;
  final String name;
  final String? parentId;
}

/// One line of the board: which category, how deep it is indented and, for a
/// group, whether it is folded.
class CategoryRow {
  const CategoryRow(
    this.id, {
    this.depth = 0,
    this.hasChildren = false,
    this.collapsed = false,
  });

  final String id;
  final int depth;
  final bool hasChildren;
  final bool collapsed;

  @override
  bool operator ==(Object other) =>
      other is CategoryRow &&
      other.id == id &&
      other.depth == depth &&
      other.hasChildren == hasChildren &&
      other.collapsed == collapsed;

  @override
  int get hashCode => Object.hash(id, depth, hasChildren, collapsed);
}

/// The lines of the Categories board.
///
/// **Tree** (default): siblings are ordered inside each parent by [sort]; a
/// group carries its children and sorts by its own total ([plan] / [fact] are
/// the SIGNED base-currency totals, compared by size: income and expense alike).
/// A folded group ([collapsed]) hides its children. A [query] keeps the matching
/// categories, their ancestors (so the indentation still makes sense) and the
/// children of a matching group; folding is ignored then.
///
/// **Flat** ([flat]): only the categories without children (the ones that hold
/// transactions), no indentation, ordered by the same keys.
///
/// A category whose parent does not exist counts as top level; a parent loop
/// cannot hang it.
List<CategoryRow> arrangeCategoryRows({
  required List<CategoryInfo> categories,
  required Map<String, double> plan,
  required Map<String, double> fact,
  Map<String, double> urgency = const {},
  List<CategorySortKey> sort = kDefaultCategorySort,
  String query = '',
  Set<String> collapsed = const {},
  bool flat = false,
}) {
  final byId = {for (final c in categories) c.id: c};
  final kids = <String?, List<CategoryInfo>>{};
  for (final c in categories) {
    final parent = c.parentId != null && byId.containsKey(c.parentId)
        ? c.parentId
        : null;
    kids.putIfAbsent(parent, () => []).add(c);
  }
  bool hasKids(String id) => kids[id]?.isNotEmpty ?? false;

  int compare(CategoryInfo a, CategoryInfo b) {
    for (final key in sort) {
      final c = _compareOn(key, a, b, plan, fact, urgency);
      if (c != 0) return c;
    }
    return compareIgnoringEmoji(a.name, b.name);
  }

  final q = query.trim().toLowerCase();
  final matches = <String>{
    for (final c in categories)
      if (q.isEmpty || c.name.toLowerCase().contains(q)) c.id,
  };

  if (flat) {
    final leaves = [
      for (final c in categories)
        if (!hasKids(c.id) && matches.contains(c.id)) c,
    ]..sort(compare);
    return [for (final c in leaves) CategoryRow(c.id)];
  }

  // Visible set for a search: matches + their ancestors + children of matches.
  Set<String>? visible;
  if (q.isNotEmpty) {
    visible = {};
    void addAncestors(String id) {
      var current = byId[id]?.parentId;
      final guard = <String>{id};
      while (current != null && byId.containsKey(current) && guard.add(current)) {
        visible!.add(current);
        current = byId[current]!.parentId;
      }
    }

    void addDescendants(String id, Set<String> seen) {
      for (final k in kids[id] ?? const <CategoryInfo>[]) {
        if (!seen.add(k.id)) continue;
        visible!.add(k.id);
        addDescendants(k.id, seen);
      }
    }

    for (final id in matches) {
      visible.add(id);
      addAncestors(id);
      addDescendants(id, {id});
    }
  }

  final out = <CategoryRow>[];
  final seen = <String>{};
  void walk(String? parent, int depth) {
    final list = [...?kids[parent]]..sort(compare);
    for (final c in list) {
      if (!seen.add(c.id)) continue;
      if (visible != null && !visible.contains(c.id)) continue;
      final group = hasKids(c.id);
      final folded = group && visible == null && collapsed.contains(c.id);
      out.add(
        CategoryRow(
          c.id,
          depth: depth,
          hasChildren: group,
          collapsed: folded,
        ),
      );
      if (!folded) walk(c.id, depth + 1);
    }
  }

  walk(null, 0);
  return out;
}

int _compareOn(
  CategorySortKey key,
  CategoryInfo a,
  CategoryInfo b,
  Map<String, double> plan,
  Map<String, double> fact,
  Map<String, double> urgency,
) {
  int dir(int c) => key.ascending ? c : -c;
  int nullsLast(double? x, double? y) {
    if (x == null && y == null) return 0;
    if (x == null) return 1;
    if (y == null) return -1;
    return dir(x.compareTo(y));
  }

  switch (key.field) {
    case CategorySortField.name:
      return dir(compareIgnoringEmoji(a.name, b.name));
    case CategorySortField.plan:
      return nullsLast(plan[a.id]?.abs(), plan[b.id]?.abs());
    case CategorySortField.fact:
      return nullsLast(fact[a.id]?.abs(), fact[b.id]?.abs());
    case CategorySortField.urgency:
      return nullsLast(urgency[a.id], urgency[b.id]);
  }
}
