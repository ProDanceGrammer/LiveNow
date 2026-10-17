import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../budget_providers.dart';
import '../dialog_stack.dart';
import '../layout.dart';
import '../undo.dart';
import 'app_toast.dart';
import 'budget_dialogs.dart' show pickBudgetCategory;
import 'param_icons.dart' show Param, ParamIcon;
import 'section_block.dart';

// Transaction templates: a category + quantity + price that can be turned into a
// real transaction at any time (Budget > Transactions) or created together with
// the actions of a plan item (planning mode).

String txTemplateSummary(BudgetTxTemplate t, String categoryName) {
  final qty = t.quantity == t.quantity.roundToDouble()
      ? t.quantity.toStringAsFixed(0)
      : t.quantity.toString();
  final price = t.unitPrice == null ? '' : ' × ${_num(t.unitPrice!)}';
  return '$categoryName · $qty$price';
}

String _num(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

final budgetTxTemplatesProvider =
    StreamProvider.autoDispose<List<BudgetTxTemplate>>(
      (ref) => ref.watch(budgetServiceProvider).watchTxTemplates(),
    );

/// Creates or edits a transaction template; returns its id (null = cancelled).
class TransactionTemplateDialog extends ConsumerStatefulWidget {
  const TransactionTemplateDialog({super.key, this.existing});

  final BudgetTxTemplate? existing;

  static Future<String?> show(
    BuildContext context, {
    BudgetTxTemplate? existing,
  }) => showStackedDialog<String>(
    context: context,
    builder: (_) => TransactionTemplateDialog(existing: existing),
  );

  @override
  ConsumerState<TransactionTemplateDialog> createState() =>
      _TransactionTemplateDialogState();
}

class _TransactionTemplateDialogState
    extends ConsumerState<TransactionTemplateDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _qty = TextEditingController(
    text: widget.existing == null ? '1' : _num(widget.existing!.quantity),
  );
  late final _price = TextEditingController(
    text: widget.existing?.unitPrice == null
        ? ''
        : _num(widget.existing!.unitPrice!),
  );
  late String? _categoryId = widget.existing?.categoryId;

  @override
  void dispose() {
    _name.dispose();
    _qty.dispose();
    _price.dispose();
    super.dispose();
  }

  double? _parse(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

  /// The name this dialog filled in from the category (so a later category
  /// change may replace it, while a name the user typed is never overwritten).
  String? _autoName;

  Future<void> _pickCategory() async {
    final id = await pickBudgetCategory(context, allowCreate: true);
    if (id == null || id.isEmpty || !mounted) return;
    final name = ref.read(budgetViewProvider).value?.categoryById[id]?.name;
    setState(() {
      _categoryId = id;
      // The transaction takes the category's name unless the user chose one.
      if (name != null &&
          (_name.text.trim().isEmpty || _name.text == _autoName)) {
        _name.text = name;
        _autoName = name;
      }
    });
  }

  Future<void> _save() async {
    final cat = _categoryId;
    if (cat == null) {
      showInfoToast(rootOverlayOf(context), 'Pick a category');
      return;
    }
    final nav = Navigator.of(context);
    final id = await ref
        .read(budgetServiceProvider)
        .saveTxTemplate(
          id: widget.existing?.id,
          name: _name.text,
          categoryId: cat,
          quantity: _parse(_qty.text) ?? 1,
          unitPrice: _parse(_price.text),
        );
    if (nav.mounted) nav.pop(id);
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(budgetViewProvider).value?.categoryById;
    final catName = _categoryId == null
        ? null
        : (cats?[_categoryId]?.name ?? 'Deleted category');
    return AlertDialog(
      title: Text(
        widget.existing == null
            ? 'New transaction template'
            : 'Transaction template',
      ),
      content: SizedBox(
        width: dialogWidth(context, 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The category comes first (it also names the transaction), with
            // the same category icon as everywhere else in the budget.
            OutlinedButton.icon(
              key: const ValueKey('txt-category'),
              autofocus: widget.existing == null,
              icon: const ParamIcon(Param.categories, size: 20, tooltip: false),
              label: Text(catName ?? 'Choose a category'),
              onPressed: _pickCategory,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('txt-name'),
              controller: _name,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Name (empty = the action\'s name)',
              ),
            ),
            // Cleared the name? One tap puts the category's name back, like in
            // the transaction dialog.
            if (_name.text.trim().isEmpty && catName != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('txt-name-from-category'),
                  icon: const Icon(Icons.subdirectory_arrow_left, size: 16),
                  label: Text('Use "$catName" as the name'),
                  onPressed: () => setState(() {
                    _name.text = catName;
                    _autoName = catName;
                  }),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('txt-quantity'),
                    controller: _qty,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: const InputDecoration(labelText: 'Quantity'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    key: const ValueKey('txt-price'),
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Price (empty = category\'s)',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('txt-save'),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// A dialog that picks ONE transaction template; "New transaction template..."
/// is pinned on top and creates one on the spot. Returns the id.
Future<String?> pickTxTemplate(
  BuildContext context, {
  Set<String> excludeIds = const {},
}) => showStackedDialog<String>(
  context: context,
  builder: (_) => _TxTemplatePicker(excludeIds: excludeIds),
);

class _TxTemplatePicker extends ConsumerWidget {
  const _TxTemplatePicker({required this.excludeIds});

  final Set<String> excludeIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(budgetTxTemplatesProvider).value ?? const [];
    final cats = ref.watch(budgetViewProvider).value?.categoryById;
    final list = [
      for (final t in all)
        if (!excludeIds.contains(t.id)) t,
    ];
    return AlertDialog(
      title: const Text('Transaction template'),
      content: SizedBox(
        width: dialogWidth(context, 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                key: const ValueKey('txt-pick-new'),
                leading: const Icon(Icons.add),
                title: const Text('New transaction template...'),
                onTap: () async {
                  final nav = Navigator.of(context);
                  final id = await TransactionTemplateDialog.show(context);
                  if (id != null && nav.mounted) nav.pop(id);
                },
              ),
              for (final t in list)
                ListTile(
                  key: ValueKey('txt-pick-${t.id}'),
                  title: Text(t.name.isEmpty ? '(action\'s name)' : t.name),
                  subtitle: Text(
                    txTemplateSummary(
                      t,
                      cats?[t.categoryId]?.name ?? 'Deleted category',
                    ),
                  ),
                  onTap: () => Navigator.of(context).pop(t.id),
                ),
            ],
          ),
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
}

/// The list of transaction templates shown in Budget > Transactions.
class TxTemplatesPanel extends ConsumerWidget {
  const TxTemplatesPanel({super.key});

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    BudgetTxTemplate t,
  ) async {
    final service = ref.read(budgetServiceProvider);
    final overlay = rootOverlayOf(context);
    final history = ref.read(undoHistoryProvider.notifier);
    final row = await service.deleteTxTemplate(t.id);
    if (row == null) return;
    offerUndo(
      overlay,
      history,
      'Deleted template "${t.name.isEmpty ? 'transaction' : t.name}"',
      () => service.undoDeleteTxTemplate(row),
    );
  }

  Future<void> _createNow(
    BuildContext context,
    WidgetRef ref,
    BudgetTxTemplate t,
  ) async {
    final overlay = rootOverlayOf(context);
    final service = ref.read(budgetServiceProvider);
    try {
      await service.createTransactionFromTemplate(t.id);
      showInfoToast(overlay, 'Transaction created');
    } on Exception catch (e) {
      showInfoToast(overlay, e.toString());
    } on StateError catch (e) {
      showInfoToast(overlay, e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(budgetTxTemplatesProvider).value ?? const [];
    final cats = ref.watch(budgetViewProvider).value?.categoryById;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: SectionBlock(
        key: const ValueKey('tx-templates-panel'),
        // ListTile paints on the nearest Material: a transparent one keeps the
        // block's glass fill visible.
        child: Material(
          type: MaterialType.transparency,
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Transaction templates',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  key: const ValueKey('tx-template-add'),
                  tooltip: 'New transaction template',
                  icon: const Icon(Icons.add),
                  onPressed: () => TransactionTemplateDialog.show(context),
                ),
              ],
            ),
            if (templates.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('None yet. A plan item can create these with its actions.'),
              ),
            // The list scrolls inside a bounded area: with many templates an
            // unbounded Column pushed the transaction list below it off the
            // screen ("BOTTOM OVERFLOWED" stripe).
            if (templates.isNotEmpty)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: (MediaQuery.sizeOf(context).height * 0.3).clamp(
                    120.0,
                    320.0,
                  ),
                ),
                child: ListView(
                  key: const ValueKey('tx-templates-list'),
                  primary: false,
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [
                    for (final t in templates)
                      ListTile(
                        key: ValueKey('tx-template-${t.id}'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          t.name.isEmpty ? '(action\'s name)' : t.name,
                        ),
                        subtitle: Text(
                          txTemplateSummary(
                            t,
                            cats?[t.categoryId]?.name ?? 'Deleted category',
                          ),
                        ),
                        onTap: () => TransactionTemplateDialog.show(
                          context,
                          existing: t,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              key: ValueKey('tx-template-use-${t.id}'),
                              tooltip: 'Create a transaction now',
                              icon: const Icon(Icons.add_card, size: 18),
                              onPressed: () => _createNow(context, ref, t),
                            ),
                            IconButton(
                              key: ValueKey('tx-template-delete-${t.id}'),
                              tooltip: 'Delete',
                              icon: const Icon(Icons.delete_outline, size: 18),
                              onPressed: () => _delete(context, ref, t),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
        ),
      ),
    );
  }
}
