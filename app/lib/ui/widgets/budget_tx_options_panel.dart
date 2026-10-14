import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../domain/budget_tx_view_rules.dart';
import '../budget_providers.dart';
import '../device_prefs.dart';
import '../dialog_stack.dart';
import '../saved_view_hooks.dart';
import '../saved_views_bar.dart';
import 'account_icon.dart';
import 'date_range_fields.dart';
import 'glass.dart';
import 'param_icons.dart';
import 'sort_chips.dart';
import 'sort_icons.dart';

/// Device-local choices of the Transactions list: whether the totals (the Total
/// block and the group headers) show, and which of the three values (counting,
/// interactional, main) are shown - in the totals and on every tile.
const kTxTotalsPref = 'tx_totals_show';
const kTxCountingPref = 'tx_col_counting';
const kTxInteractPref = 'tx_col_interact';
const kTxMainPref = 'tx_col_main';

/// The collapsible panel under the Transactions search field: waterfall sort,
/// where the search text looks, and the filters (categories, accounts, action
/// link, date range). It only edits the providers; the rules live in
/// `domain/budget_tx_view_rules.dart`.
class BudgetTxOptionsPanel extends ConsumerWidget {
  const BudgetTxOptionsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(budgetTxSortProvider);
    final flags = ref.watch(budgetTxSearchFlagsProvider);
    final filters = ref.watch(budgetTxFiltersProvider);
    final group = ref.watch(budgetTxGroupProvider);
    final accounts = ref.watch(budgetAccountsProvider).value ?? const [];
    final categories = ref.watch(budgetCategoriesProvider).value ?? const [];
    final theme = Theme.of(context);

    void setSort(List<TxSortKey> v) =>
        ref.read(budgetTxSortProvider.notifier).state = v;
    void setFlags(TxSearchFlags v) =>
        ref.read(budgetTxSearchFlagsProvider.notifier).state = v;
    void setFilters(TxFilters v) =>
        ref.read(budgetTxFiltersProvider.notifier).state = v;

    final remaining = [
      for (final f in TxSortField.values)
        if (!sort.any((k) => k.field == f)) (f.name, f.label, sortFieldIcon(f)),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: GlassSurface(
        radius: 16,
        shadow: false,
        blurWindow: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: math.min(380, MediaQuery.sizeOf(context).height * 0.5),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SavedViewsBar(hooks: txViewHooks(ref)),
                const SizedBox(height: 12),
                SortChipsRow(
                  keyPrefix: 'tx-sort',
                  chips: [
                    for (final k in sort)
                      SortChipData(
                        k.field.name,
                        k.field.label,
                        ascending: k.ascending,
                        icon: sortFieldIcon(k.field),
                      ),
                  ],
                  addOptions: remaining,
                  onToggle: (i) => setSort([
                    for (var j = 0; j < sort.length; j++)
                      if (j == i) sort[j].toggled() else sort[j],
                  ]),
                  onRemove: (i) => setSort([...sort]..removeAt(i)),
                  onMove: (from, to) {
                    if (from == to) return;
                    final list = [...sort];
                    list.insert(to, list.removeAt(from));
                    setSort(list);
                  },
                  onAdd: (id) => setSort([
                    ...sort,
                    TxSortKey(TxSortField.values.byName(id)),
                  ]),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Group by', style: theme.textTheme.titleSmall),
                    for (final g in TxGroupBy.values)
                      ChoiceChip(
                        key: ValueKey('tx-group-${g.name}'),
                        label: Text(g.label),
                        selected: group == g,
                        onSelected: (_) =>
                            ref.read(budgetTxGroupProvider.notifier).state = g,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Search in', style: theme.textTheme.titleSmall),
                    FilterChip(
                      key: const ValueKey('tx-flag-name'),
                      label: const Text('Name'),
                      selected: flags.name,
                      onSelected: (v) => setFlags(flags.copyWith(name: v)),
                    ),
                    FilterChip(
                      key: const ValueKey('tx-flag-category'),
                      label: const Text('Category'),
                      selected: flags.category,
                      onSelected: (v) => setFlags(flags.copyWith(category: v)),
                    ),
                    FilterChip(
                      key: const ValueKey('tx-flag-action'),
                      label: const Text('Action'),
                      selected: flags.action,
                      onSelected: (v) => setFlags(flags.copyWith(action: v)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _ValuesRow(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text('Filters', style: theme.textTheme.titleSmall),
                    const Spacer(),
                    if (filters.active)
                      TextButton(
                        key: const ValueKey('tx-filters-reset'),
                        onPressed: () => setFilters(const TxFilters()),
                        child: const Text('Reset filters'),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('tx-filter-categories'),
                      icon: const ParamIcon(
                        Param.categories,
                        size: 18,
                        tooltip: false,
                      ),
                      label: Text(
                        filters.categoryIds.isEmpty
                            ? 'Categories'
                            : 'Categories (${filters.categoryIds.length})',
                      ),
                      onPressed: () async {
                        final picked = await showStackedDialog<Set<String>>(
                          context: context,
                          builder: (_) => _CategoriesMultiPicker(
                            categories: categories,
                            initial: filters.categoryIds,
                          ),
                        );
                        if (picked != null) {
                          setFilters(filters.copyWith(categoryIds: picked));
                        }
                      },
                    ),
                    if (filters.categoryIds.isNotEmpty)
                      SegmentedButton<bool>(
                        key: const ValueKey('tx-filter-cat-mode'),
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: false, label: Text('Only these')),
                          ButtonSegment(value: true, label: Text('All but')),
                        ],
                        selected: {filters.excludeCategories},
                        onSelectionChanged: (s) => setFilters(
                          filters.copyWith(excludeCategories: s.first),
                        ),
                      ),
                    OutlinedButton.icon(
                      key: const ValueKey('tx-filter-actions'),
                      icon: const Icon(Icons.bolt_outlined, size: 18),
                      label: Text(
                        filters.actionIds.isEmpty
                            ? 'Actions'
                            : 'Actions (${filters.actionIds.length})',
                      ),
                      onPressed: () async {
                        final picked = await showStackedDialog<Set<String>>(
                          context: context,
                          builder: (_) => _ActionsMultiPicker(
                            options: {
                              for (final t in ref
                                      .read(budgetTransactionsProvider)
                                      .value ??
                                  const <BudgetTxItem>[])
                                if (t.row.actionId != null)
                                  t.row.actionId!: t.actionName ?? 'Action',
                            },
                            initial: filters.actionIds,
                          ),
                        );
                        if (picked != null) {
                          setFilters(filters.copyWith(actionIds: picked));
                        }
                      },
                    ),
                    SegmentedButton<TxActionLink>(
                      key: const ValueKey('tx-filter-action'),
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: TxActionLink.any,
                          label: Text('Any'),
                        ),
                        ButtonSegment(
                          value: TxActionLink.linked,
                          label: Text('Has action'),
                        ),
                        ButtonSegment(
                          value: TxActionLink.unlinked,
                          label: Text('No action'),
                        ),
                      ],
                      selected: {filters.action},
                      onSelectionChanged: (s) =>
                          setFilters(filters.copyWith(action: s.first)),
                    ),
                  ],
                ),
                if (accounts.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('Accounts', style: theme.textTheme.labelLarge),
                      for (final a in accounts)
                        FilterChip(
                          key: ValueKey('tx-filter-account-${a.id}'),
                          avatar: AccountIcon(icon: a.icon, size: 18),
                          label: Text(a.name),
                          selected: filters.accountIds.contains(a.id),
                          onSelected: (v) => setFilters(
                            filters.copyWith(
                              accountIds: v
                                  ? {...filters.accountIds, a.id}
                                  : ({...filters.accountIds}..remove(a.id)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                DateRangeFields(
                  keyPrefix: 'tx-date',
                  value: filters.dateRange,
                  onChanged: (r) => setFilters(filters.copyWith(dateRange: r)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pick several categories (a chosen group also covers everything below it).
class _CategoriesMultiPicker extends StatefulWidget {
  const _CategoriesMultiPicker({
    required this.categories,
    required this.initial,
  });

  final List<BudgetCategory> categories;
  final Set<String> initial;

  @override
  State<_CategoriesMultiPicker> createState() => _CategoriesMultiPickerState();
}

class _CategoriesMultiPickerState extends State<_CategoriesMultiPicker> {
  late final Set<String> _chosen = {...widget.initial};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final byId = {for (final c in widget.categories) c.id: c};
    final rows = [
      for (final c in widget.categories)
        if (c.name.toLowerCase().contains(_query)) c,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return AlertDialog(
      title: const Text('Categories'),
      content: SizedBox(
        width: 440,
        height: 380,
        child: Column(
          children: [
            TextField(
              key: const ValueKey('tx-categories-search'),
              decoration: const InputDecoration(
                hintText: 'Search',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) =>
                  setState(() => _query = v.trim().toLowerCase()),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'A chosen group includes all its sub-categories.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final c in rows)
                    CheckboxListTile(
                      key: ValueKey('tx-pick-cat-${c.id}'),
                      dense: true,
                      value: _chosen.contains(c.id),
                      title: Text(c.name),
                      subtitle: c.parentId == null
                          ? null
                          : Text(byId[c.parentId]?.name ?? ''),
                      onChanged: (v) => setState(() {
                        if (v ?? false) {
                          _chosen.add(c.id);
                        } else {
                          _chosen.remove(c.id);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const ValueKey('tx-categories-all'),
          onPressed: () => setState(
            () => _chosen.addAll([for (final c in rows) c.id]),
          ),
          child: const Text('Select all'),
        ),
        TextButton(
          onPressed: () => setState(_chosen.clear),
          child: const Text('Clear'),
        ),
        FilledButton(
          key: const ValueKey('tx-categories-apply'),
          onPressed: () => Navigator.of(context).pop({..._chosen}),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

/// "Values": which of counting / interactional / main show, and whether the
/// totals show at all. Device-local ([devicePrefsProvider]); at least one value
/// always stays on.
class _ValuesRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final totals = ref.watch(devicePrefBoolProvider((kTxTotalsPref, true)));
    final cols = {
      kTxCountingPref: ref.watch(devicePrefBoolProvider((kTxCountingPref, true))),
      kTxInteractPref: ref.watch(devicePrefBoolProvider((kTxInteractPref, true))),
      kTxMainPref: ref.watch(devicePrefBoolProvider((kTxMainPref, true))),
    };
    Widget chip(String key, String label, bool on, String id) => FilterChip(
      key: ValueKey(id),
      label: Text(label),
      selected: on,
      onSelected: (v) {
        // Never switch the last value off: the list would show no amounts.
        if (!v && cols.containsKey(key) && cols.values.where((x) => x).length == 1) {
          return;
        }
        setDevicePrefBool(ref, key, v);
      },
    );
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Values', style: theme.textTheme.titleSmall),
        chip(kTxCountingPref, 'Counting', cols[kTxCountingPref]!, 'tx-col-counting'),
        chip(kTxInteractPref, 'Interactional', cols[kTxInteractPref]!, 'tx-col-interact'),
        chip(kTxMainPref, 'Main', cols[kTxMainPref]!, 'tx-col-main'),
        chip(kTxTotalsPref, 'Show totals', totals, 'tx-totals-show'),
      ],
    );
  }
}

/// Pick several actions that have transactions (checkbox list, searchable).
class _ActionsMultiPicker extends StatefulWidget {
  const _ActionsMultiPicker({required this.options, required this.initial});

  /// action id -> name.
  final Map<String, String> options;
  final Set<String> initial;

  @override
  State<_ActionsMultiPicker> createState() => _ActionsMultiPickerState();
}

class _ActionsMultiPickerState extends State<_ActionsMultiPicker> {
  late final Set<String> _chosen = {...widget.initial};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final rows = [
      for (final e in widget.options.entries)
        if (e.value.toLowerCase().contains(_query)) e,
    ]..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    return AlertDialog(
      title: const Text('Actions'),
      content: SizedBox(
        width: 440,
        height: 380,
        child: Column(
          children: [
            TextField(
              key: const ValueKey('tx-actions-search'),
              decoration: const InputDecoration(
                hintText: 'Search',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Only actions that have transactions are listed.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final e in rows)
                    CheckboxListTile(
                      key: ValueKey('tx-pick-action-${e.key}'),
                      dense: true,
                      value: _chosen.contains(e.key),
                      title: Text(e.value),
                      onChanged: (v) => setState(() {
                        if (v ?? false) {
                          _chosen.add(e.key);
                        } else {
                          _chosen.remove(e.key);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const ValueKey('tx-actions-all'),
          onPressed: () =>
              setState(() => _chosen.addAll([for (final e in rows) e.key])),
          child: const Text('Select all'),
        ),
        TextButton(
          onPressed: () => setState(_chosen.clear),
          child: const Text('Clear'),
        ),
        FilledButton(
          key: const ValueKey('tx-actions-apply'),
          onPressed: () => Navigator.of(context).pop({..._chosen}),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
