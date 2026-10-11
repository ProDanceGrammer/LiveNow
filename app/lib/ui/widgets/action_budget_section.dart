import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../budget_providers.dart';
import 'budget_dialogs.dart';
import 'budget_format.dart';
import 'section_block.dart';
import 'transaction_picker_dialog.dart';

/// "Transactions" block of the action editor: the budget transactions linked
/// to this action (each opens its editor) and a button to add one. Opens
/// expanded only when the action already has some.
class ActionBudgetSection extends ConsumerWidget {
  const ActionBudgetSection({super.key, required this.actionId});

  final String actionId;

  /// Find an existing unlinked transaction first (link it to this action), or
  /// fall through to the "new transaction" dialog.
  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final service = ref.read(budgetServiceProvider);
    final pick = await TransactionPickerDialog.show(context);
    if (pick == null || !context.mounted) return;
    final item = pick.item;
    if (item != null) {
      await service.updateTransaction(item.row.id, actionId: Value(actionId));
    } else {
      await BudgetTransactionDialog.show(context, actionId: actionId);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(actionBudgetTransactionsProvider(actionId));
    final cats = {
      for (final c in ref.watch(budgetCategoriesProvider).value ?? const [])
        c.id: c,
    };
    return SectionBlock(
      padding: kSectionTileBlockPadding,
      child: ExpansionTile(
        key: ValueKey('action-budget-${items.isEmpty}'),
        title: Text(
          items.isEmpty ? 'Transactions' : 'Transactions (${items.length})',
        ),
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: kSectionTilePadding,
        childrenPadding: kSectionChildrenPadding,
        initiallyExpanded: items.isNotEmpty,
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            type: MaterialType.transparency,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final t in items)
                  ListTile(
                    key: ValueKey('action-budget-tx-${t.row.id}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(cats[t.row.categoryId]?.name ?? 'No category'),
                    trailing: Text(
                      budgetMoney(
                        (t.row.isIncome ? 1 : -1) *
                            (t.row.isAmount
                                ? t.row.quantity
                                : t.row.unitPrice * t.row.quantity),
                        sign: true,
                      ),
                    ),
                    onTap: () =>
                        BudgetTransactionDialog.show(context, existing: t),
                  ),
                TextButton.icon(
                  key: const ValueKey('action-add-budget-transaction'),
                  icon: const Icon(Icons.add),
                  label: const Text('Add transaction'),
                  onPressed: () => _add(context, ref),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
