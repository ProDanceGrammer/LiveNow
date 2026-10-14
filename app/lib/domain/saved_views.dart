import 'dart:convert';

import 'all_actions_view_rules.dart';
import 'budget_account_view.dart';
import 'budget_category_view.dart';
import 'budget_tx_view_rules.dart';
import 'date_range_filter.dart';
import 'template_sort.dart';

/// Saved views: a named sort / filter preset of one screen. Everything here is
/// pure (no Flutter, no database): the model, the screen ids and the JSON of
/// every screen's sort and filter state. `SavedViewService` stores them.

/// The screens that can save views.
abstract final class ViewScreens {
  static const budgetTransactions = 'budget.transactions';
  static const budgetCategories = 'budget.categories';
  static const budgetAccounts = 'budget.accounts';
  static const actionsAll = 'actions.all';
  static const actionsTemplates = 'actions.templates';
  static const growthList = 'growth.list';
}

/// What a view stores: only the sort, only the filters, or both.
enum SavedViewKind {
  sort,
  filter,
  both;

  bool get hasSort => this != filter;
  bool get hasFilter => this != sort;

  static SavedViewKind fromDb(String value) => values.firstWhere(
    (k) => k.name == value,
    orElse: () => SavedViewKind.both,
  );

  static SavedViewKind of({required bool sort, required bool filter}) =>
      sort && filter
      ? both
      : sort
      ? SavedViewKind.sort
      : SavedViewKind.filter;
}

/// One saved view. [sort] and [filter] are the screen's own JSON (empty when
/// the kind does not store that part).
class SavedViewItem {
  const SavedViewItem({
    required this.id,
    required this.screen,
    required this.name,
    required this.kind,
    this.sort = const {},
    this.filter = const {},
    this.isDefault = false,
    this.updatedAt = '',
  });

  final String id;
  final String screen;
  final String name;
  final SavedViewKind kind;
  final Map<String, Object?> sort;
  final Map<String, Object?> filter;
  final bool isDefault;
  final String updatedAt;

  /// The `payload` column.
  String get payload => encodeViewPayload(sort: sort, filter: filter);

  static SavedViewItem fromRow({
    required String id,
    required String screen,
    required String name,
    required String kind,
    required String payload,
    required bool isDefault,
    required String updatedAt,
  }) {
    final parts = decodeViewPayload(payload);
    return SavedViewItem(
      id: id,
      screen: screen,
      name: name,
      kind: SavedViewKind.fromDb(kind),
      sort: parts.sort,
      filter: parts.filter,
      isDefault: isDefault,
      updatedAt: updatedAt,
    );
  }
}

String encodeViewPayload({
  Map<String, Object?> sort = const {},
  Map<String, Object?> filter = const {},
}) => jsonEncode({'sort': sort, 'filter': filter});

({Map<String, Object?> sort, Map<String, Object?> filter}) decodeViewPayload(
  String payload,
) {
  Map<String, Object?> part(Object? v) =>
      v is Map ? {for (final e in v.entries) '${e.key}': e.value} : const {};
  try {
    final j = jsonDecode(payload);
    if (j is Map) return (sort: part(j['sort']), filter: part(j['filter']));
  } catch (_) {
    // A damaged payload is an empty view, never a crash.
  }
  return (sort: const {}, filter: const {});
}

/// The view that applies when a screen opens: the one marked default; if two
/// devices each marked one, the most recently edited wins (deterministic).
SavedViewItem? defaultViewOf(Iterable<SavedViewItem> views) {
  SavedViewItem? best;
  for (final v in views) {
    if (!v.isDefault) continue;
    if (best == null || v.updatedAt.compareTo(best.updatedAt) > 0) best = v;
  }
  return best;
}

// ---- generic helpers --------------------------------------------------------

List<Object?> encodeSortKeys<K>(
  List<K> keys,
  String Function(K) field,
  bool Function(K) ascending,
) => [
  for (final k in keys) {'f': field(k), 'asc': ascending(k)},
];

/// Unknown fields (a view saved by a newer app) are skipped.
List<K> decodeSortKeys<K>(Object? json, K? Function(String, bool) make) {
  if (json is! List) return const [];
  final out = <K>[];
  for (final e in json) {
    if (e is! Map) continue;
    final f = e['f'];
    if (f is! String) continue;
    final k = make(f, e['asc'] != false);
    if (k != null) out.add(k);
  }
  return out;
}

T? _byName<T extends Enum>(List<T> values, Object? name) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

Map<String, Object?> _rangeToJson(DateRangeFilter r) => {
  if (r.from != null) 'from': r.from!.toUtc().toIso8601String(),
  if (r.until != null) 'until': r.until!.toUtc().toIso8601String(),
};

DateRangeFilter _rangeFromJson(Object? j) {
  if (j is! Map) return const DateRangeFilter();
  DateTime? t(Object? v) => v is String ? DateTime.tryParse(v)?.toUtc() : null;
  return DateRangeFilter(from: t(j['from']), until: t(j['until']));
}

Set<String> _ids(Object? j, [Set<String>? known]) => {
  if (j is List)
    for (final v in j)
      if (v is String && (known == null || known.contains(v))) v,
};

// ---- Budget transactions ----------------------------------------------------

Map<String, Object?> txSortToJson(List<TxSortKey> sort, TxGroupBy group) => {
  'keys': encodeSortKeys<TxSortKey>(sort, (k) => k.field.name, (k) => k.ascending),
  'group': group.name,
};

({List<TxSortKey> sort, TxGroupBy group}) txSortFromJson(
  Map<String, Object?> j,
) => (
  sort: decodeSortKeys<TxSortKey>(j['keys'], (f, asc) {
    final field = _byName(TxSortField.values, f);
    return field == null ? null : TxSortKey(field, ascending: asc);
  }),
  group: _byName(TxGroupBy.values, j['group']) ?? TxGroupBy.action,
);

Map<String, Object?> txFilterToJson(TxFilters f, TxSearchFlags flags) => {
  'categories': f.categoryIds.toList()..sort(),
  'excludeCategories': f.excludeCategories,
  'accounts': f.accountIds.toList()..sort(),
  'action': f.action.name,
  'actions': f.actionIds.toList()..sort(),
  'range': _rangeToJson(f.dateRange),
  'flags': {'name': flags.name, 'category': flags.category, 'action': flags.action},
};

/// [knownCategoryIds] / [knownAccountIds]: ids that no longer exist are dropped
/// (null = keep every id).
({TxFilters filters, TxSearchFlags flags}) txFilterFromJson(
  Map<String, Object?> j, {
  Set<String>? knownCategoryIds,
  Set<String>? knownAccountIds,
}) {
  final fl = j['flags'];
  return (
    filters: TxFilters(
      categoryIds: _ids(j['categories'], knownCategoryIds),
      excludeCategories: j['excludeCategories'] == true,
      accountIds: _ids(j['accounts'], knownAccountIds),
      action: _byName(TxActionLink.values, j['action']) ?? TxActionLink.any,
      actionIds: _ids(j['actions']),
      dateRange: _rangeFromJson(j['range']),
    ),
    flags: fl is Map
        ? TxSearchFlags(
            name: fl['name'] != false,
            category: fl['category'] != false,
            action: fl['action'] != false,
          )
        : const TxSearchFlags(),
  );
}

// ---- Budget categories ------------------------------------------------------

Map<String, Object?> categorySortToJson(List<CategorySortKey> sort) => {
  'keys': encodeSortKeys<CategorySortKey>(sort, (k) => k.field.name, (k) => k.ascending),
};

List<CategorySortKey> categorySortFromJson(Map<String, Object?> j) =>
    decodeSortKeys<CategorySortKey>(j['keys'], (f, asc) {
      final field = _byName(CategorySortField.values, f);
      return field == null ? null : CategorySortKey(field, ascending: asc);
    });

Map<String, Object?> categoryFilterToJson({required bool flat}) => {'flat': flat};

bool categoryFilterFromJson(Map<String, Object?> j) => j['flat'] == true;

// ---- Budget accounts --------------------------------------------------------

Map<String, Object?> accountSortToJson(List<AccountSortKey> sort) => {
  'keys': encodeSortKeys<AccountSortKey>(sort, (k) => k.field.name, (k) => k.ascending),
};

List<AccountSortKey> accountSortFromJson(Map<String, Object?> j) =>
    decodeSortKeys<AccountSortKey>(j['keys'], (f, asc) {
      final field = _byName(AccountSortField.values, f);
      return field == null ? null : AccountSortKey(field, ascending: asc);
    });

// ---- Actions: All -----------------------------------------------------------

Map<String, Object?> allSortToJson(List<SortKey> sort) => {
  'keys': encodeSortKeys<SortKey>(sort, (k) => k.field.name, (k) => k.ascending),
};

List<SortKey> allSortFromJson(Map<String, Object?> j) =>
    decodeSortKeys<SortKey>(j['keys'], (f, asc) {
      final field = _byName(SortField.values, f);
      return field == null ? null : SortKey(field, ascending: asc);
    });

Map<String, Object?> _linkToJson(LinkFilter l) => {
  'mode': l.mode.name,
  if (l.actionId != null) 'actionId': l.actionId,
};

LinkFilter _linkFromJson(Object? j) => j is Map
    ? LinkFilter(
        mode: _byName(LinkMode.values, j['mode']) ?? LinkMode.any,
        actionId: j['actionId'] as String?,
      )
    : const LinkFilter();

Map<String, Object?> allFilterToJson(AllActionsFilters f, SearchFlags flags) => {
  'nameText': f.nameText,
  'metricIds': f.metricIds.toList()..sort(),
  'allMetrics': f.allMetrics,
  'directionsMode': f.directionsMode.name,
  'previous': _linkToJson(f.previous),
  'next': _linkToJson(f.next),
  if (f.minMinutes != null) 'minMinutes': f.minMinutes,
  if (f.maxMinutes != null) 'maxMinutes': f.maxMinutes,
  if (f.minUrgency != null) 'minUrgency': f.minUrgency,
  if (f.maxUrgency != null) 'maxUrgency': f.maxUrgency,
  'range': _rangeToJson(f.dateRange),
  'flags': {'name': flags.name, 'notes': flags.notes, 'directions': flags.directions},
};

({AllActionsFilters filters, SearchFlags flags}) allFilterFromJson(
  Map<String, Object?> j, {
  Set<String>? knownMetricIds,
}) {
  final fl = j['flags'];
  return (
    filters: AllActionsFilters(
      nameText: j['nameText'] as String? ?? '',
      metricIds: _ids(j['metricIds'], knownMetricIds),
      allMetrics: j['allMetrics'] == true,
      directionsMode:
          _byName(LinkMode.values, j['directionsMode']) ?? LinkMode.any,
      previous: _linkFromJson(j['previous']),
      next: _linkFromJson(j['next']),
      minMinutes: (j['minMinutes'] as num?)?.toInt(),
      maxMinutes: (j['maxMinutes'] as num?)?.toInt(),
      minUrgency: (j['minUrgency'] as num?)?.toDouble(),
      maxUrgency: (j['maxUrgency'] as num?)?.toDouble(),
      dateRange: _rangeFromJson(j['range']),
    ),
    flags: fl is Map
        ? SearchFlags(
            name: fl['name'] != false,
            notes: fl['notes'] == true,
            directions: fl['directions'] == true,
          )
        : const SearchFlags(),
  );
}

// ---- Templates --------------------------------------------------------------

Map<String, Object?> templateSortToJson(List<TemplateSortKey> sort) => {
  'keys': encodeSortKeys<TemplateSortKey>(sort, (k) => k.field.name, (k) => k.ascending),
};

List<TemplateSortKey> templateSortFromJson(Map<String, Object?> j) =>
    decodeSortKeys<TemplateSortKey>(j['keys'], (f, asc) {
      final field = _byName(TemplateSortField.values, f);
      return field == null ? null : TemplateSortKey(field, ascending: asc);
    });
