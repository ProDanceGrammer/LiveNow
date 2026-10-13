import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;

import '../core/time_codec.dart';
import '../data/database.dart';
import '../domain/budget_category_view.dart';
import '../domain/budget_rules.dart';
import 'budget_providers.dart';
import 'widgets/budget_format.dart';

// The Categories board's data. Everything the rows need is worked out ONCE here
// (arranging, sorting, money/date text) and handed over as small value-equal
// objects, so a minute tick, an unrelated database write or an action-urgency
// change that leaves a row's own numbers alone rebuilds nothing.

/// The sort levels, newest last (the board's `SortChipsRow`).
final budgetCategorySortProvider = StateProvider.autoDispose<List<CategorySortKey>>(
  (ref) => kDefaultCategorySort,
);

/// Only categories that hold transactions, no hierarchy (the "Flat" switch).
final budgetCategoryFlatProvider = StateProvider.autoDispose<bool>((ref) => false);

/// Folded groups (this session only).
final budgetCategoryCollapsedProvider = StateProvider.autoDispose<Set<String>>(
  (ref) => const {},
);

/// The search text.
final budgetCategoryQueryProvider = StateProvider.autoDispose<String>((ref) => '');

/// One line of the board, ready to draw: no formatting or lookups in `build`.
class CategoryRowView {
  const CategoryRowView({
    required this.category,
    required this.depth,
    required this.hasChildren,
    required this.collapsed,
    required this.subline,
    required this.planText,
    required this.factText,
    required this.plan,
    required this.fact,
    required this.noRate,
    required this.urgency,
    required this.unlinked,
  });

  final BudgetCategory category;
  final int depth;
  final bool hasChildren;
  final bool collapsed;

  /// The entered fields in one grey line (`12.5/kg · × 4/mo · every 2 mo`),
  /// null for a group or when nothing is entered.
  final String? subline;
  final String planText;
  final String factText;

  /// Signed base-currency figures (income +, expense -).
  final double plan;
  final double fact;
  final bool noRate;

  /// Urgency of the action of the nearest upcoming transaction.
  final double? urgency;

  /// That action has no growth direction (white "fill me in").
  final bool unlinked;

  String get id => category.id;

  /// How much of the plan is used: fact / plan by size; null without a plan.
  double? get ratio => plan.abs() < 0.005 ? null : fact.abs() / plan.abs();

  /// Spending above the plan (an expense category over its plan).
  bool get overPlan => !category.isIncome && (ratio ?? 0) > 1.0001;

  @override
  bool operator ==(Object other) =>
      other is CategoryRowView &&
      other.category == category &&
      other.depth == depth &&
      other.hasChildren == hasChildren &&
      other.collapsed == collapsed &&
      other.subline == subline &&
      other.planText == planText &&
      other.factText == factText &&
      other.plan == plan &&
      other.fact == fact &&
      other.noRate == noRate &&
      other.urgency == urgency &&
      other.unlinked == unlinked;

  @override
  int get hashCode => Object.hash(
    category,
    depth,
    hasChildren,
    collapsed,
    subline,
    planText,
    factText,
    urgency,
    unlinked,
  );
}

/// The board's rows with value equality, so the provider only notifies when a
/// line really changed.
class CategoryRows {
  const CategoryRows(this.rows);

  final List<CategoryRowView> rows;

  @override
  bool operator ==(Object other) =>
      other is CategoryRows && listEquals(other.rows, rows);

  @override
  int get hashCode => rows.length;
}

String? _subline(BudgetCategory c) {
  final unit = BudgetUnit.fromDb(c.unit);
  final parts = <String>[
    if (unit == BudgetUnit.percentPerMonth)
      if (c.percent != null) '${budgetNumber(c.percent!)}%'
    else if (c.price != null)
      '${budgetNumber(c.price!)}/${switch (unit) {
        BudgetUnit.piece => 'pc',
        BudgetUnit.kilogram => 'kg',
        _ => 'mo',
      }}',
    if (c.unitsPerMonth != null) '× ${budgetNumber(c.unitsPerMonth!)}/mo',
    if (c.frequencyMonths != null) 'every ${budgetNumber(c.frequencyMonths!)} mo',
    if (dateTimeFromDb(c.endDate) case final end?) 'until ${budgetDate(end)}',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// The rows of the Categories board, or null while the budget loads.
final budgetCategoryRowsProvider = Provider.autoDispose<CategoryRows?>((ref) {
  final view = ref.watch(budgetViewProvider).value;
  if (view == null) return null;
  final urgency = ref.watch(budgetCategoryUrgencyProvider);
  final unlinked = ref.watch(budgetCategoryUnlinkedProvider);
  final arranged = arrangeCategoryRows(
    categories: [
      for (final c in view.categories) CategoryInfo(c.id, c.name, c.parentId),
    ],
    plan: {
      for (final e in view.snapshot.byCategory.entries) e.key: e.value.planBase,
    },
    fact: {
      for (final e in view.snapshot.byCategory.entries) e.key: e.value.factBase,
    },
    urgency: urgency,
    sort: ref.watch(budgetCategorySortProvider),
    query: ref.watch(budgetCategoryQueryProvider),
    collapsed: ref.watch(budgetCategoryCollapsedProvider),
    flat: ref.watch(budgetCategoryFlatProvider),
  );
  final byId = view.categoryById;
  return CategoryRows([
    for (final r in arranged)
      () {
        final c = byId[r.id]!;
        final f = view.snapshot.byCategory[r.id];
        return CategoryRowView(
          category: c,
          depth: r.depth,
          hasChildren: r.hasChildren,
          collapsed: r.collapsed,
          subline: r.hasChildren ? null : _subline(c),
          planText: f == null ? '—' : budgetMoney(f.planBase),
          factText: f == null ? '—' : budgetMoney(f.factBase),
          plan: f?.planBase ?? 0,
          fact: f?.factBase ?? 0,
          noRate: f?.noRate ?? false,
          urgency: urgency[r.id],
          unlinked: unlinked.contains(r.id),
        );
      }(),
  ]);
});
