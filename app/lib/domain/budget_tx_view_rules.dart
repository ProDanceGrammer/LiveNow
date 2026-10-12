import 'date_range_filter.dart';
import 'name_sort.dart' show compareIgnoringEmoji;

/// Pure sort / filter / search rules of the Budget "Transactions" list - the
/// same shape as `all_actions_view_rules.dart` for the Actions "All" list (the
/// UI only edits these values).

enum TxSortField {
  date('Date'),
  amount('Amount'),
  name('Name'),
  category('Category');

  final String label;
  const TxSortField(this.label);
}

/// One level of the waterfall sort.
class TxSortKey {
  final TxSortField field;
  final bool ascending;

  const TxSortKey(this.field, {this.ascending = true});

  TxSortKey toggled() => TxSortKey(field, ascending: !ascending);

  @override
  bool operator ==(Object other) =>
      other is TxSortKey &&
      other.field == field &&
      other.ascending == ascending;

  @override
  int get hashCode => Object.hash(field, ascending);
}

/// The default order: the newest transaction first.
const List<TxSortKey> kDefaultTxSort = [
  TxSortKey(TxSortField.date, ascending: false),
];

/// Which fields the search text is matched against.
class TxSearchFlags {
  final bool name;
  final bool category;
  final bool action;

  const TxSearchFlags({
    this.name = true,
    this.category = true,
    this.action = true,
  });

  TxSearchFlags copyWith({bool? name, bool? category, bool? action}) =>
      TxSearchFlags(
        name: name ?? this.name,
        category: category ?? this.category,
        action: action ?? this.action,
      );

  @override
  bool operator ==(Object other) =>
      other is TxSearchFlags &&
      other.name == name &&
      other.category == category &&
      other.action == action;

  @override
  int get hashCode => Object.hash(name, category, action);
}

/// Whether a transaction is linked to an action.
enum TxActionLink { any, linked, unlinked }

/// The filters of the Transactions list. Empty/null parts do not filter.
class TxFilters {
  /// Chosen categories; a chosen GROUP also matches everything below it.
  final Set<String> categoryIds;
  final Set<String> accountIds;
  final TxActionLink action;
  final DateRangeFilter dateRange;

  const TxFilters({
    this.categoryIds = const {},
    this.accountIds = const {},
    this.action = TxActionLink.any,
    this.dateRange = const DateRangeFilter(),
  });

  bool get active =>
      categoryIds.isNotEmpty ||
      accountIds.isNotEmpty ||
      action != TxActionLink.any ||
      dateRange.active;

  TxFilters copyWith({
    Set<String>? categoryIds,
    Set<String>? accountIds,
    TxActionLink? action,
    DateRangeFilter? dateRange,
  }) => TxFilters(
    categoryIds: categoryIds ?? this.categoryIds,
    accountIds: accountIds ?? this.accountIds,
    action: action ?? this.action,
    dateRange: dateRange ?? this.dateRange,
  );
}

/// What the rules read of one transaction.
class TxRowView {
  final String id;
  final String name;
  final String? categoryId;
  final String categoryName;

  /// The account the amount is counted in (null = none).
  final String? accountId;

  /// Name of the linked action, '' when unlinked.
  final String actionName;
  final bool linked;

  /// The live effective date (UTC).
  final DateTime date;

  /// Signed: income positive, expense negative.
  final double amount;

  const TxRowView({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.categoryName,
    required this.accountId,
    required this.actionName,
    required this.linked,
    required this.date,
    required this.amount,
  });
}

/// For every category: itself and every category below it. [parentOf] maps a
/// category id to its parent id (null = top level). Guarded against loops.
Map<String, Set<String>> categoryWithDescendants(
  Map<String, String?> parentOf,
) {
  final out = {
    for (final id in parentOf.keys) id: <String>{id},
  };
  for (final id in parentOf.keys) {
    var p = parentOf[id];
    final seen = <String>{id};
    while (p != null && parentOf.containsKey(p) && seen.add(p)) {
      out[p]!.add(id);
      p = parentOf[p];
    }
  }
  return out;
}

int _compareOn(TxSortKey key, TxRowView a, TxRowView b) {
  int dir(int c) => key.ascending ? c : -c;
  switch (key.field) {
    case TxSortField.date:
      return dir(a.date.compareTo(b.date));
    case TxSortField.amount:
      return dir(a.amount.compareTo(b.amount));
    case TxSortField.name:
      return dir(compareIgnoringEmoji(a.name, b.name));
    case TxSortField.category:
      return dir(compareIgnoringEmoji(a.categoryName, b.categoryName));
  }
}

/// The ids of [rows] that pass [filters] and the search [query] (matched per
/// [flags], case-insensitive in Dart so Cyrillic works), in the [sort] order
/// (a waterfall: the first key decides, later keys break ties; equal rows keep
/// their incoming order). [descendants] comes from [categoryWithDescendants].
List<String> arrangeTransactionIds({
  required List<TxRowView> rows,
  required List<TxSortKey> sort,
  TxFilters filters = const TxFilters(),
  String query = '',
  TxSearchFlags flags = const TxSearchFlags(),
  Map<String, Set<String>> descendants = const {},
}) {
  final q = query.trim().toLowerCase();
  final wantedCategories = <String>{
    for (final id in filters.categoryIds) ...(descendants[id] ?? {id}),
  };

  bool keep(TxRowView t) {
    if (filters.categoryIds.isNotEmpty &&
        !(t.categoryId != null && wantedCategories.contains(t.categoryId))) {
      return false;
    }
    if (filters.accountIds.isNotEmpty &&
        !(t.accountId != null && filters.accountIds.contains(t.accountId))) {
      return false;
    }
    switch (filters.action) {
      case TxActionLink.any:
        break;
      case TxActionLink.linked:
        if (!t.linked) return false;
      case TxActionLink.unlinked:
        if (t.linked) return false;
    }
    if (filters.dateRange.active && !filters.dateRange.contains(t.date)) {
      return false;
    }
    if (q.isNotEmpty) {
      final hit =
          (flags.name && t.name.toLowerCase().contains(q)) ||
          (flags.category && t.categoryName.toLowerCase().contains(q)) ||
          (flags.action && t.actionName.toLowerCase().contains(q));
      if (!hit) return false;
    }
    return true;
  }

  final kept = [
    for (var i = 0; i < rows.length; i++)
      if (keep(rows[i])) (i, rows[i]),
  ];
  if (sort.isNotEmpty) {
    kept.sort((x, y) {
      for (final key in sort) {
        final c = _compareOn(key, x.$2, y.$2);
        if (c != 0) return c;
      }
      return x.$1.compareTo(y.$1);
    });
  }
  return [for (final e in kept) e.$2.id];
}
