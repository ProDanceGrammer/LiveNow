import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../budget_providers.dart';
import '../dialog_stack.dart';
import 'budget_format.dart';

/// What [TransactionPickerDialog] hands back: an existing transaction to link,
/// or [createNew].
class TransactionPick {
  final BudgetTxItem? item;
  final bool createNew;
  const TransactionPick.existing(BudgetTxItem this.item) : createNew = false;
  const TransactionPick.create() : item = null, createNew = true;
}

/// A searchable "Link a transaction" list for the action editor: the existing
/// transactions that belong to no action yet, with "Create new transaction"
/// pinned on top. Search matches the transaction name, category name, date and
/// amount.
class TransactionPickerDialog extends ConsumerStatefulWidget {
  const TransactionPickerDialog({super.key});

  static Future<TransactionPick?> show(BuildContext context) =>
      showStackedDialog<TransactionPick>(
        context: context,
        builder: (_) => const TransactionPickerDialog(),
      );

  @override
  ConsumerState<TransactionPickerDialog> createState() =>
      _TransactionPickerDialogState();
}

class _TransactionPickerDialogState
    extends ConsumerState<TransactionPickerDialog> {
  String _query = '';

  static double _amount(BudgetTxItem t) =>
      (t.row.isIncome ? 1 : -1) *
      (t.row.isAmount ? t.row.quantity : t.row.unitPrice * t.row.quantity);

  @override
  Widget build(BuildContext context) {
    final cats = <String, String>{
      for (final c in ref.watch(budgetCategoriesProvider).value ?? const [])
        c.id: c.name,
    };
    final all = ref.watch(budgetTransactionsProvider);
    return AlertDialog(
      title: const Text('Link a transaction'),
      content: SizedBox(
        width: math.min(640.0, MediaQuery.sizeOf(context).width - 80),
        height: 400,
        child: Column(
          children: [
            TextField(
              key: const ValueKey('tx-pick-search'),
              decoration: const InputDecoration(labelText: 'Search'),
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
            ),
            ListTile(
              key: const ValueKey('tx-pick-new'),
              leading: const Icon(Icons.add),
              title: const Text('Create new transaction'),
              onTap: () =>
                  Navigator.of(context).pop(const TransactionPick.create()),
            ),
            const Divider(height: 1),
            Expanded(
              child: all.when(
                data: (items) {
                  final free = [
                    for (final t in items)
                      if (t.row.actionId == null)
                        if (_query.isEmpty ||
                            _haystack(t, cats).contains(_query))
                          t,
                  ];
                  if (free.isEmpty) {
                    return const Center(
                      child: Text('No unlinked transactions.'),
                    );
                  }
                  return ListView.builder(
                    itemCount: free.length,
                    itemBuilder: (context, i) {
                      final t = free[i];
                      final cat = cats[t.row.categoryId] ?? 'No category';
                      return ListTile(
                        key: ValueKey('tx-pick-${t.row.id}'),
                        title: Text(
                          t.row.name.isEmpty ? cat : t.row.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${t.row.name.isEmpty ? '' : '$cat · '}'
                          '${budgetDate(t.date)}',
                        ),
                        trailing: Text(budgetMoney(_amount(t), sign: true)),
                        onTap: () =>
                            Navigator.of(context)
                                .pop(TransactionPick.existing(t)),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
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
      ],
    );
  }

  String _haystack(BudgetTxItem t, Map<String, String> cats) =>
      '${t.row.name} ${cats[t.row.categoryId] ?? ''} ${budgetDate(t.date)} '
              '${budgetNumber(_amount(t).abs())}'
          .toLowerCase();
}
