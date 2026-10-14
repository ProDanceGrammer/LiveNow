import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/all_actions_view_rules.dart';
import '../domain/budget_account_view.dart';
import '../domain/budget_category_view.dart';
import '../domain/budget_tx_view_rules.dart';
import '../domain/saved_views.dart';
import 'budget_category_rows.dart';
import 'budget_providers.dart';
import 'providers.dart';
import 'saved_views_bar.dart';

/// How each provider-backed screen reads, applies and clears its sort and
/// filters for saved views. (Templates and the Growth list keep their state in
/// widgets and build their hooks there.) A saved sort that decodes to nothing
/// falls back to the screen's default.

SavedViewHooks txViewHooks(WidgetRef ref) => SavedViewHooks(
  screen: ViewScreens.budgetTransactions,
  readSort: () => txSortToJson(
    ref.read(budgetTxSortProvider),
    ref.read(budgetTxGroupProvider),
  ),
  applySort: (j) {
    final r = txSortFromJson(j);
    ref.read(budgetTxSortProvider.notifier).state = r.sort.isEmpty
        ? kDefaultTxSort
        : r.sort;
    ref.read(budgetTxGroupProvider.notifier).state = r.group;
  },
  clearSort: () {
    ref.read(budgetTxSortProvider.notifier).state = kDefaultTxSort;
    ref.read(budgetTxGroupProvider.notifier).state = TxGroupBy.action;
  },
  readFilter: () => txFilterToJson(
    ref.read(budgetTxFiltersProvider),
    ref.read(budgetTxSearchFlagsProvider),
  ),
  applyFilter: (j) {
    // Categories / accounts deleted since the view was saved are dropped.
    final r = txFilterFromJson(
      j,
      knownCategoryIds: {
        for (final c in ref.read(budgetCategoriesProvider).value ?? const [])
          c.id,
      },
      knownAccountIds: {
        for (final a in ref.read(budgetAccountsProvider).value ?? const [])
          a.id,
      },
    );
    ref.read(budgetTxFiltersProvider.notifier).state = r.filters;
    ref.read(budgetTxSearchFlagsProvider.notifier).state = r.flags;
  },
  clearFilter: () {
    ref.read(budgetTxFiltersProvider.notifier).state = const TxFilters();
    ref.read(budgetTxSearchFlagsProvider.notifier).state =
        const TxSearchFlags();
  },
);

SavedViewHooks categoryViewHooks(WidgetRef ref) => SavedViewHooks(
  screen: ViewScreens.budgetCategories,
  readSort: () => categorySortToJson(ref.read(budgetCategorySortProvider)),
  applySort: (j) {
    final keys = categorySortFromJson(j);
    ref.read(budgetCategorySortProvider.notifier).state = keys.isEmpty
        ? kDefaultCategorySort
        : keys;
  },
  clearSort: () =>
      ref.read(budgetCategorySortProvider.notifier).state =
          kDefaultCategorySort,
  readFilter: () =>
      categoryFilterToJson(flat: ref.read(budgetCategoryFlatProvider)),
  applyFilter: (j) =>
      ref.read(budgetCategoryFlatProvider.notifier).state =
          categoryFilterFromJson(j),
  clearFilter: () =>
      ref.read(budgetCategoryFlatProvider.notifier).state = false,
);

/// Accounts have a sort only.
SavedViewHooks accountViewHooks(WidgetRef ref) => SavedViewHooks(
  screen: ViewScreens.budgetAccounts,
  readSort: () => accountSortToJson(ref.read(budgetAccountSortProvider)),
  applySort: (j) {
    final keys = accountSortFromJson(j);
    ref.read(budgetAccountSortProvider.notifier).state = keys.isEmpty
        ? kDefaultAccountSort
        : keys;
  },
  clearSort: () =>
      ref.read(budgetAccountSortProvider.notifier).state = kDefaultAccountSort,
);

SavedViewHooks allActionsViewHooks(WidgetRef ref) => SavedViewHooks(
  screen: ViewScreens.actionsAll,
  readSort: () => allSortToJson(ref.read(allActionsSortProvider)),
  applySort: (j) {
    final keys = allSortFromJson(j);
    ref.read(allActionsSortProvider.notifier).state = keys.isEmpty
        ? kDefaultAllActionsSort
        : keys;
  },
  clearSort: () =>
      ref.read(allActionsSortProvider.notifier).state = kDefaultAllActionsSort,
  readFilter: () => allFilterToJson(
    ref.read(allActionsFiltersProvider),
    ref.read(allActionsSearchFlagsProvider),
  ),
  applyFilter: (j) {
    final r = allFilterFromJson(j);
    ref.read(allActionsFiltersProvider.notifier).state = r.filters;
    ref.read(allActionsSearchFlagsProvider.notifier).state = r.flags;
  },
  clearFilter: () {
    ref.read(allActionsFiltersProvider.notifier).state =
        const AllActionsFilters();
    ref.read(allActionsSearchFlagsProvider.notifier).state =
        const SearchFlags();
  },
);
