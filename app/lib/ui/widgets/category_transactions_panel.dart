import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/budget_rules.dart';
import '../../domain/budget_tx_view_rules.dart';
import '../budget_providers.dart';
import 'budget_dialogs.dart';
import 'budget_format.dart';
import 'label_icon.dart';
import 'param_icons.dart';

/// The transactions of one category (a group: of everything below it), newest
/// first: date, name, the sum in the counting currency and in the main
/// currency, with the totals on top. Shown beside the category's settings in
/// its edit dialog; a tap opens the transaction.
///
/// [scrollable] false (a phone, where the dialog scrolls as a whole) lists the
/// most recent [kPanelPhoneLimit] rows without an own scroll view.
class CategoryTransactionsPanel extends ConsumerWidget {
  const CategoryTransactionsPanel({
    super.key,
    required this.categoryId,
    this.scrollable = true,
  });

  final String categoryId;
  final bool scrollable;

  static const kPanelPhoneLimit = 30;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(budgetViewProvider).value;
    final scheme = Theme.of(context).colorScheme;
    if (view == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final below = categoryWithDescendants({
          for (final c in view.categories) c.id: c.parentId,
        })[categoryId] ??
        {categoryId};
    final items = [
      for (final t in view.transactions)
        if (below.contains(t.row.categoryId)) t,
    ];
    final accts = {for (final a in view.accounts) a.id: budgetAcctFromRow(a)};
    final base = view.settings.baseCurrency;

    // The three totals (counting and interactional per currency, main as one
    // number) of this category's transactions - the same sums as the
    // Transactions tab - and the period's plan / fact.
    final totals = TxTotals();
    final amounts = <TxAmounts>[];
    for (final t in items) {
      final a = transactionAmounts(t.toRules(), accts);
      amounts.add(a);
      totals.add(
        a,
        countCurrency: view.accountById[t.row.accountCountId]?.currency ?? '',
        interactCurrency: view.accountById[t.row.accountUseId]?.currency,
      );
    }
    final figures = view.snapshot.byCategory[categoryId];
    final muted = TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5);

    String sums(Map<String, double> m) => [
      for (final e in m.entries)
        '${budgetMoney(e.value, sign: true)} ${e.key}'.trim(),
    ].join(', ');
    Widget row(Widget label, String value, Key key) => Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 30, child: label),
          Expanded(child: Text(value, key: key, style: muted)),
        ],
      ),
    );

    Widget figure(Widget icon, String text, {Key? key}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(width: 4),
        Text(text, key: key, style: muted),
      ],
    );

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Transactions (${items.length})',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (items.isNotEmpty) ...[
            const SizedBox(height: 2),
            row(
              const TxValueIcon(TxValue.counting, size: 16),
              sums(totals.counting),
              const ValueKey('category-tx-counting'),
            ),
            if (totals.interact.isNotEmpty)
              row(
                const TxValueIcon(TxValue.interactional, size: 16),
                sums(totals.interact),
                const ValueKey('category-tx-interact'),
              ),
            row(
              const TxValueIcon(TxValue.main, size: 16),
              '${budgetMoney(totals.base, sign: true)} $base'
                  '${totals.noBase > 0 ? ' (${totals.noBase} without a rate)' : ''}',
              const ValueKey('category-tx-main'),
            ),
          ],
          if (figures != null) ...[
            const SizedBox(height: 6),
            // Plan first, then Fact, for the budget settings period.
            Wrap(
              spacing: 20,
              runSpacing: 2,
              children: [
                figure(
                  const ParamIcon(Param.plan, size: 16, tapToShow: true),
                  '${budgetMoney(figures.planBase, sign: true)} $base',
                  key: const ValueKey('category-tx-plan'),
                ),
                figure(
                  const ParamIcon(Param.actual, size: 16, tapToShow: true),
                  '${budgetMoney(figures.factBase, sign: true)} $base',
                  key: const ValueKey('category-tx-fact'),
                ),
              ],
            ),
          ],
        ],
      ),
    );

    // A plain InkWell row (not a dense/compact ListTile: its fixed minimum
    // height overflowed by 3 px with the two-line amount on the right).
    Widget tile(int i) {
      final t = items[i];
      final a = amounts[i];
      final cur = view.accountById[t.row.accountCountId]?.currency ?? '';
      final name = t.row.name.isNotEmpty
          ? t.row.name
          : (view.categoryById[t.row.categoryId]?.name ?? 'No name');
      return InkWell(
        key: ValueKey('category-tx-${t.row.id}'),
        onTap: () => BudgetTransactionDialog.show(context, existing: t),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(budgetDate(t.date), style: muted),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${budgetMoney(a.count, sign: true)} $cur'.trim(),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (cur != base)
                    Text(
                      a.base == null
                          ? '— $base'
                          : '${budgetMoney(a.base!, sign: true)} $base',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final Widget body = items.isEmpty
        ? const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No transactions in this category yet.'),
          )
        : scrollable
        ? ListView.builder(
            itemCount: items.length,
            itemBuilder: (_, i) => tile(i),
          )
        : Column(
            children: [
              for (var i = 0; i < items.length && i < kPanelPhoneLimit; i++)
                tile(i),
              if (items.length > kPanelPhoneLimit)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('… and ${items.length - kPanelPhoneLimit} older'),
                ),
            ],
          );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: scrollable ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [header, if (scrollable) Expanded(child: body) else body],
      ),
    );
  }
}
