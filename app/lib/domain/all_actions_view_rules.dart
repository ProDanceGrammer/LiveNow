import '../data/queries.dart';
import 'date_range_filter.dart';
import 'duration_rules.dart';

/// Pure sort / filter / search rules of the All Actions list (the UI in
/// `ui/views/all_actions_view.dart` only edits these values).

enum SortField {
  name('Name'),
  start('Start'),
  end('End'),
  duration('Duration'),
  urgency('Urgency'),
  lastEdited('Last edited'),
  created('Created'),
  done('Done');

  final String label;
  const SortField(this.label);
}

/// One level of the waterfall sort.
class SortKey {
  final SortField field;
  final bool ascending;

  const SortKey(this.field, {this.ascending = true});

  SortKey toggled() => SortKey(field, ascending: !ascending);

  @override
  bool operator ==(Object other) =>
      other is SortKey && other.field == field && other.ascending == ascending;

  @override
  int get hashCode => Object.hash(field, ascending);
}

/// The default order: the most recently edited action first.
const List<SortKey> kDefaultAllActionsSort = [
  SortKey(SortField.lastEdited, ascending: false),
];

/// Which fields the search text is matched against.
class SearchFlags {
  final bool name;
  final bool notes;
  final bool directions;

  const SearchFlags({
    this.name = true,
    this.notes = false,
    this.directions = false,
  });

  SearchFlags copyWith({bool? name, bool? notes, bool? directions}) =>
      SearchFlags(
        name: name ?? this.name,
        notes: notes ?? this.notes,
        directions: directions ?? this.directions,
      );

  @override
  bool operator ==(Object other) =>
      other is SearchFlags &&
      other.name == name &&
      other.notes == notes &&
      other.directions == directions;

  @override
  int get hashCode => Object.hash(name, notes, directions);
}

enum LinkMode { any, has, none, linkedTo }

/// Previous / next filter: any, has at least one, has none, or linked to one
/// chosen action.
class LinkFilter {
  final LinkMode mode;
  final String? actionId;

  const LinkFilter({this.mode = LinkMode.any, this.actionId});

  bool get active => mode != LinkMode.any;

  @override
  bool operator ==(Object other) =>
      other is LinkFilter && other.mode == mode && other.actionId == actionId;

  @override
  int get hashCode => Object.hash(mode, actionId);
}

/// The filters of the All list. Empty/null parts do not filter.
class AllActionsFilters {
  final String nameText;
  final Set<String> metricIds;

  /// true = must have ALL chosen directions, false = ANY of them.
  final bool allMetrics;
  final LinkFilter previous;
  final LinkFilter next;
  final int? minMinutes;
  final int? maxMinutes;
  final double? minUrgency;
  final double? maxUrgency;

  /// Days the action's START must fall on. An action with no start (not
  /// scheduled) never matches while this is active; all-day actions count by
  /// their day.
  final DateRangeFilter dateRange;

  const AllActionsFilters({
    this.nameText = '',
    this.metricIds = const {},
    this.allMetrics = false,
    this.previous = const LinkFilter(),
    this.next = const LinkFilter(),
    this.minMinutes,
    this.maxMinutes,
    this.minUrgency,
    this.maxUrgency,
    this.dateRange = const DateRangeFilter(),
  });

  bool get usesUrgency => minUrgency != null || maxUrgency != null;

  bool get active =>
      nameText.trim().isNotEmpty ||
      metricIds.isNotEmpty ||
      previous.active ||
      next.active ||
      minMinutes != null ||
      maxMinutes != null ||
      usesUrgency ||
      dateRange.active;

  /// [clearMin] etc. exist because null means "keep" in a plain copyWith.
  AllActionsFilters copyWith({
    String? nameText,
    Set<String>? metricIds,
    bool? allMetrics,
    LinkFilter? previous,
    LinkFilter? next,
    int? minMinutes,
    bool clearMinMinutes = false,
    int? maxMinutes,
    bool clearMaxMinutes = false,
    double? minUrgency,
    bool clearMinUrgency = false,
    double? maxUrgency,
    bool clearMaxUrgency = false,
    DateRangeFilter? dateRange,
  }) => AllActionsFilters(
    nameText: nameText ?? this.nameText,
    metricIds: metricIds ?? this.metricIds,
    allMetrics: allMetrics ?? this.allMetrics,
    previous: previous ?? this.previous,
    next: next ?? this.next,
    minMinutes: clearMinMinutes ? null : (minMinutes ?? this.minMinutes),
    maxMinutes: clearMaxMinutes ? null : (maxMinutes ?? this.maxMinutes),
    minUrgency: clearMinUrgency ? null : (minUrgency ?? this.minUrgency),
    maxUrgency: clearMaxUrgency ? null : (maxUrgency ?? this.maxUrgency),
    dateRange: dateRange ?? this.dateRange,
  );
}

int _durationMinutes(ActionListItem a) => computeActionDuration(
  startAt: a.startAt,
  endAt: a.endAt,
  legacyEstimatedMinutes: a.estimatedMinutes,
).inMinutes;

/// Compares [a] and [b] on one [key]. Missing values (no start, no urgency…)
/// sort last in both directions.
int _compareOn(
  SortKey key,
  ActionListItem a,
  ActionListItem b,
  Map<String, double> urgency,
) {
  int dir(int c) => key.ascending ? c : -c;
  int nullsLast<T extends Comparable>(T? x, T? y) {
    if (x == null && y == null) return 0;
    if (x == null) return 1;
    if (y == null) return -1;
    return dir(x.compareTo(y));
  }

  switch (key.field) {
    case SortField.name:
      return dir(a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    case SortField.start:
      return nullsLast<DateTime>(a.startAt, b.startAt);
    case SortField.end:
      return nullsLast<DateTime>(a.endAt, b.endAt);
    case SortField.duration:
      return dir(_durationMinutes(a).compareTo(_durationMinutes(b)));
    case SortField.urgency:
      return nullsLast<num>(urgency[a.id], urgency[b.id]);
    case SortField.lastEdited:
      return nullsLast<DateTime>(a.updatedAt, b.updatedAt);
    case SortField.created:
      return nullsLast<DateTime>(a.createdAt, b.createdAt);
    case SortField.done:
      return dir((a.isDoneBefore ? 1 : 0).compareTo(b.isDoneBefore ? 1 : 0));
  }
}

/// A new list sorted by [sort] as a waterfall (the first key decides, later
/// keys break ties); equal rows keep their incoming order (stable).
List<ActionListItem> sortActions(
  List<ActionListItem> items,
  List<SortKey> sort, {
  Map<String, double> urgency = const {},
}) {
  if (sort.isEmpty) return List.of(items);
  final indexed = [for (var i = 0; i < items.length; i++) (i, items[i])];
  indexed.sort((x, y) {
    for (final key in sort) {
      final c = _compareOn(key, x.$2, y.$2, urgency);
      if (c != 0) return c;
    }
    return x.$1.compareTo(y.$1);
  });
  return [for (final e in indexed) e.$2];
}

/// The link data the rules may need; a null map means "not loaded / not
/// needed" (the matching filter is then skipped).
class AllActionsLinkData {
  final Map<String, Set<String>>? metricIdsByAction;
  final Map<String, String>? metricNamesById; // lower-cased
  final Map<String, Set<String>>? predecessors;
  final Map<String, Set<String>>? successors;

  const AllActionsLinkData({
    this.metricIdsByAction,
    this.metricNamesById,
    this.predecessors,
    this.successors,
  });
}

bool _linkMatches(LinkFilter f, Set<String>? linked) {
  switch (f.mode) {
    case LinkMode.any:
      return true;
    case LinkMode.has:
      return linked != null && linked.isNotEmpty;
    case LinkMode.none:
      return linked == null || linked.isEmpty;
    case LinkMode.linkedTo:
      return f.actionId == null ||
          (linked != null && linked.contains(f.actionId));
  }
}

/// Applies [filters] and the search ([query], already trimmed + lower-cased,
/// matched per [flags]) and then the sort.
///
/// [notesMatches] is the id set the notes search found (null while the Notes
/// flag is off). The directions flag matches names of linked directions.
List<ActionListItem> arrangeActions({
  required List<ActionListItem> items,
  required List<SortKey> sort,
  AllActionsFilters filters = const AllActionsFilters(),
  String query = '',
  SearchFlags flags = const SearchFlags(),
  Map<String, double> urgency = const {},
  AllActionsLinkData links = const AllActionsLinkData(),
  Set<String>? notesMatches,
}) {
  final nameFilter = filters.nameText.trim().toLowerCase();
  final q = query.trim().toLowerCase();

  bool keep(ActionListItem a) {
    if (nameFilter.isNotEmpty && !a.name.toLowerCase().contains(nameFilter)) {
      return false;
    }
    if (filters.metricIds.isNotEmpty && links.metricIdsByAction != null) {
      final have = links.metricIdsByAction![a.id] ?? const <String>{};
      final ok = filters.allMetrics
          ? filters.metricIds.every(have.contains)
          : filters.metricIds.any(have.contains);
      if (!ok) return false;
    }
    if (filters.previous.active &&
        links.predecessors != null &&
        !_linkMatches(filters.previous, links.predecessors![a.id])) {
      return false;
    }
    if (filters.next.active &&
        links.successors != null &&
        !_linkMatches(filters.next, links.successors![a.id])) {
      return false;
    }
    if (filters.minMinutes != null || filters.maxMinutes != null) {
      final m = _durationMinutes(a);
      if (filters.minMinutes != null && m < filters.minMinutes!) return false;
      if (filters.maxMinutes != null && m > filters.maxMinutes!) return false;
    }
    if (filters.dateRange.active) {
      final start = a.startAt;
      if (start == null || !filters.dateRange.contains(start)) return false;
    }
    if (filters.usesUrgency) {
      final u = urgency[a.id];
      if (u == null) return false;
      if (filters.minUrgency != null && u < filters.minUrgency!) return false;
      if (filters.maxUrgency != null && u > filters.maxUrgency!) return false;
    }
    if (q.isNotEmpty) {
      var hit = false;
      if (flags.name && a.name.toLowerCase().contains(q)) hit = true;
      if (!hit && flags.notes && (notesMatches?.contains(a.id) ?? false)) {
        hit = true;
      }
      if (!hit && flags.directions) {
        final ids = links.metricIdsByAction?[a.id];
        final names = links.metricNamesById;
        if (ids != null && names != null) {
          hit = ids.any((id) => (names[id] ?? '').contains(q));
        }
      }
      if (!hit) return false;
    }
    return true;
  }

  final kept = [
    for (final a in items)
      if (keep(a)) a,
  ];
  return sortActions(kept, sort, urgency: urgency);
}
