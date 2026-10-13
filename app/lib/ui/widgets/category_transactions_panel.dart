import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/budget_rules.dart';
import '../../domain/budget_tx_view_rules.dart';
import '../budget_providers.dart';
import 'budget_dialogs.dart';
import 'budget_format.dart';

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

    var baseTotal = 0.0;
    var baseMissing = false;
    final countTotals = <String, double>{};
    final amounts = <TxAmounts>[];
    for (final t in items) {
      final a = transactionAmounts(t.toRules(), accts);
      amounts.add(a);
      if (a.base == null) {
        baseMissing = true;
      } else {
        baseTotal += a.base!;
      }
      final cur = view.accountById[t.row.accountCountId]?.currency ?? '';
      countTotals[cur] = (countTotals[cur] ?? 0) + a.count;
    }

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Transactions (${items.length})',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (items.isNotEmpty)
            Text(
              [
                for (final e in countTotals.entries)
                  '${budgetMoney(e.value, sign: true)} ${e.key}'.trim(),
                if (countTotals.length != 1 ||
                    countTotals.keys.single != base)
                  '${budgetMoney(baseTotal, sign: true)} $base'
                      '${baseMissing ? ' (some without a rate)' : ''}',
              ].join('  ·  '),
              key: const ValueKey('category-tx-total'),
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
            ),
        ],
      ),
    );

    Widget tile(int i) {
      final t = items[i];
      final a = amounts[i];
      final cur = view.accountById[t.row.accountCountId]?.currency ?? '';
      final name = t.row.name.isNotEmpty
          ? t.row.name
          : (view.categoryById[t.row.categoryId]?.name ?? 'No name');
      return ListTile(
        key: ValueKey('category-tx-${t.row.id}'),
        dense: true,
        visualDensity: VisualDensity.compact,
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(budgetDate(t.date)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
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
        onTap: () => BudgetTransactionDialog.show(context, existing: t),
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
