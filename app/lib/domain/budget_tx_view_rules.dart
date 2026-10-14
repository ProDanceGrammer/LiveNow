import 'budget_rules.dart' show TxAmounts;
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
  /// Chosen categories; a chosen GROUP also matches everything below it. With
  /// [excludeCategories] the chosen ones are the only ones LEFT OUT instead.
  final Set<String> categoryIds;
  final bool excludeCategories;
  final Set<String> accountIds;
  final TxActionLink action;

  /// Chosen actions: only transactions linked to one of them (on top of
  /// [action]). Empty = any action.
  final Set<String> actionIds;
  final DateRangeFilter dateRange;

  const TxFilters({
    this.categoryIds = const {},
    this.excludeCategories = false,
    this.accountIds = const {},
    this.action = TxActionLink.any,
    this.actionIds = const {},
    this.dateRange = const DateRangeFilter(),
  });

  bool get active =>
      categoryIds.isNotEmpty ||
      accountIds.isNotEmpty ||
      action != TxActionLink.any ||
      actionIds.isNotEmpty ||
      dateRange.active;

  TxFilters copyWith({
    Set<String>? categoryIds,
    bool? excludeCategories,
    Set<String>? accountIds,
    TxActionLink? action,
    Set<String>? actionIds,
    DateRangeFilter? dateRange,
  }) => TxFilters(
    categoryIds: categoryIds ?? this.categoryIds,
    excludeCategories: excludeCategories ?? this.excludeCategories,
    accountIds: accountIds ?? this.accountIds,
    action: action ?? this.action,
    actionIds: actionIds ?? this.actionIds,
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

  /// The linked action's id (grouping key), null when unlinked.
  final String? actionId;

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
    this.actionId,
  });
}

/// How the Transactions list is grouped.
enum TxGroupBy {
  action('Action'),
  category('Category'),
  account('Account'),
  none('None');

  final String label;
  const TxGroupBy(this.label);
}

/// One group of the list: its [key] (stable, for folding), a [title] and the
/// transaction ids in the order they came in.
class TxGroup {
  final String key;
  final String title;
  final List<String> ids;

  TxGroup(this.key, this.title) : ids = [];
}

/// Splits [rows] (already filtered and sorted) into groups by [by]. A group
/// appears where its first transaction does, so the sort decides the group
/// order too; the group of transactions without an action / category / account
/// always goes last. [TxGroupBy.none] gives one untitled group.
List<TxGroup> groupTransactionRows(
  List<TxRowView> rows,
  TxGroupBy by, {
  String Function(String accountId)? accountName,
}) {
  if (by == TxGroupBy.none) {
    return rows.isEmpty
        ? const []
        : [
            TxGroup('all', '')..ids.addAll([for (final r in rows) r.id]),
          ];
  }
  final groups = <String, TxGroup>{};
  for (final r in rows) {
    final (String key, String title) = switch (by) {
      TxGroupBy.action => r.actionId == null
          ? ('', 'No action')
          : (r.actionId!, r.actionName.isEmpty ? 'Action' : r.actionName),
      TxGroupBy.category => r.categoryId == null
          ? ('', 'No category')
          : (r.categoryId!, r.categoryName),
      TxGroupBy.account => r.accountId == null
          ? ('', 'No account')
          : (r.accountId!, accountName?.call(r.accountId!) ?? 'Account'),
      TxGroupBy.none => ('all', ''),
    };
    groups.putIfAbsent(key, () => TxGroup(key, title)).ids.add(r.id);
  }
  final list = groups.values.toList();
  final none = list.where((g) => g.key.isEmpty).toList();
  return [...list.where((g) => g.key.isNotEmpty), ...none];
}

/// Sums of transactions in the three currencies: counting and interactional
/// per currency code (accounts differ), the main currency as one number.
class TxTotals {
  final Map<String, double> counting = {};
  final Map<String, double> interact = {};
  double base = 0;

  /// The main-currency sum split by sign (income / expense, the latter <= 0).
  double income = 0;
  double expense = 0;

  /// Transactions that could not be converted to the main currency.
  int noBase = 0;
  int count = 0;

  void add(
    TxAmounts a, {
    required String countCurrency,
    String? interactCurrency,
  }) {
    count++;
    counting[countCurrency] = (counting[countCurrency] ?? 0) + a.count;
    if (a.interact != null && interactCurrency != null) {
      interact[interactCurrency] =
          (interact[interactCurrency] ?? 0) + a.interact!;
    }
    if (a.base == null) {
      noBase++;
    } else {
      base += a.base!;
      if (a.base! >= 0) {
        income += a.base!;
      } else {
        expense += a.base!;
      }
    }
  }
}

/// The categories whose plan and fact belong to a filtered list: the leaf
/// categories of its transactions ([txCategoryIds]) and, when the categories are
/// filtered in (not excluded), every leaf below the chosen ones, so a chosen
/// category with no transaction in the period still shows its plan. [parentOf]
/// maps a category id to its parent id.
Set<String> figureCategoryIds({
  required Iterable<String> txCategoryIds,
  required TxFilters filters,
  required Map<String, String?> parentOf,
}) {
  final hasKids = {for (final p in parentOf.values) ?p};
  final out = <String>{for (final id in txCategoryIds) id};
  if (filters.categoryIds.isNotEmpty && !filters.excludeCategories) {
    final below = categoryWithDescendants(parentOf);
    for (final id in filters.categoryIds) {
      for (final d in below[id] ?? {id}) {
        if (!hasKids.contains(d)) out.add(d);
      }
    }
  }
  return out;
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
    if (filters.categoryIds.isNotEmpty) {
      final inChosen =
          t.categoryId != null && wantedCategories.contains(t.categoryId);
      if (filters.excludeCategories ? inChosen : !inChosen) return false;
    }
    if (filters.actionIds.isNotEmpty &&
        !(t.actionId != null && filters.actionIds.contains(t.actionId))) {
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
