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

/// A searchable list of existing transactions with "Create new transaction"
/// pinned on top. For the action editor ("Link a transaction") it lists the
/// transactions that belong to no action yet; with [excludeCategoryId] (the
/// category dialog's "Add a transaction") it lists every transaction NOT in
/// that category. Search matches the transaction name, category name, action
/// name, date and amount.
class TransactionPickerDialog extends ConsumerStatefulWidget {
  const TransactionPickerDialog({
    super.key,
    this.excludeCategoryId,
    this.title = 'Link a transaction',
  });

  final String? excludeCategoryId;
  final String title;

  static Future<TransactionPick?> show(
    BuildContext context, {
    String? excludeCategoryId,
    String title = 'Link a transaction',
  }) => showStackedDialog<TransactionPick>(
    context: context,
    builder: (_) => TransactionPickerDialog(
      excludeCategoryId: excludeCategoryId,
      title: title,
    ),
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
      title: Text(widget.title),
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
                      if (widget.excludeCategoryId == null
                          ? t.row.actionId == null
                          : t.row.categoryId != widget.excludeCategoryId)
                        if (_query.isEmpty ||
                            _haystack(t, cats).contains(_query))
                          t,
                  ];
                  if (free.isEmpty) {
                    return Center(
                      child: Text(
                        widget.excludeCategoryId == null
                            ? 'No unlinked transactions.'
                            : 'No other transactions.',
                      ),
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
      '${t.row.name} ${cats[t.row.categoryId] ?? ''} ${t.actionName ?? ''} '
              '${budgetDate(t.date)} '
              '${budgetNumber(_amount(t).abs())}'
          .toLowerCase();
}
