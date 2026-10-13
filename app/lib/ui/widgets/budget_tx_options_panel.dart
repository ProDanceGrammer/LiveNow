import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../domain/budget_tx_view_rules.dart';
import '../budget_providers.dart';
import '../dialog_stack.dart';
import 'account_icon.dart';
import 'date_range_fields.dart';
import 'glass.dart';
import 'param_icons.dart';
import 'sort_chips.dart';
import 'sort_icons.dart';

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
