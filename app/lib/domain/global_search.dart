import 'date_range_filter.dart';
import 'search_match.dart';

/// The kinds of things the Ctrl+K window can find.
enum SearchSection {
  actions('Actions'),
  templates('Templates'),
  directions('Directions'),
  categories('Categories'),
  transactions('Transactions'),
  forms('Forms'),
  plans('Plans');

  const SearchSection(this.label);
  final String label;
}

/// One thing the window can open.
class SearchHit {
  const SearchHit({
    required this.section,
    required this.id,
    required this.title,
    this.subtitle = '',
    this.icon,
    this.changedAt,
  });

  final SearchSection section;
  final String id;
  final String title;

  /// A second searchable line (a transaction's category and action).
  final String subtitle;

  /// An emoji (directions).
  final String? icon;

  /// When it was last changed (UTC); null when unknown (a row never edited since
  /// sync stamps were introduced).
  final DateTime? changedAt;
}

/// The "updated" menu of the window.
enum UpdatedWithin {
  any('Any time'),
  today('Today'),
  week('7 days'),
  month('30 days'),
  year('Past year');

  const UpdatedWithin(this.label);
  final String label;

  /// The earliest accepted change time, or null for [any].
  DateTime? since(DateTime nowUtc) => switch (this) {
    UpdatedWithin.any => null,
    UpdatedWithin.today => DateRangeFilter.dayStart(DateRangeFilter.dayOf(nowUtc)),
    UpdatedWithin.week => nowUtc.subtract(const Duration(days: 7)),
    UpdatedWithin.month => nowUtc.subtract(const Duration(days: 30)),
    UpdatedWithin.year => nowUtc.subtract(const Duration(days: 365)),
  };
}

/// What an empty query shows: the most recently changed things.
const kSearchRecentCount = 20;

/// How many results are listed at most.
const kSearchResultLimit = 100;

/// Narrows [all] to [sections] (empty = every section) and to what changed within
/// [updated], then orders it: with an empty [query] the most recently changed
/// first (at most [kSearchRecentCount]); with a query the whole-word matches first
/// and then the rest (see [rankMatches]), each group newest first, at most
/// [kSearchResultLimit].
List<SearchHit> searchHits(
  Iterable<SearchHit> all, {
  String query = '',
  Set<SearchSection> sections = const {},
  UpdatedWithin updated = UpdatedWithin.any,
  required DateTime nowUtc,
}) {
  final since = updated.since(nowUtc);
  final pool = [
    for (final h in all)
      if ((sections.isEmpty || sections.contains(h.section)) &&
          (since == null ||
              (h.changedAt != null && !h.changedAt!.isBefore(since))))
        h,
  ]..sort((a, b) {
      // Newest first; unknown times last.
      final x = a.changedAt, y = b.changedAt;
      if (x == null && y == null) return 0;
      if (x == null) return 1;
      if (y == null) return -1;
      return y.compareTo(x);
    });
  if (foldSearch(query).isEmpty) {
    return pool.length <= kSearchRecentCount
        ? pool
        : pool.sublist(0, kSearchRecentCount);
  }
  final ranked = rankMatches(pool, query, (h) => [h.title, h.subtitle]);
  return ranked.length <= kSearchResultLimit
      ? ranked
      : ranked.sublist(0, kSearchResultLimit);
}
