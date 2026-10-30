import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/ai/ai_draft.dart';
import '../../domain/ai/ai_protocol.dart';
import '../dialog_stack.dart';
import '../providers.dart';

import 'budget_dialogs.dart';

/// What the line editor returns: the edit plus the new category's name (to show).
typedef AiLineEditResult = ({LineEdit edit, String? categoryName});

/// Opens the small editor of one draft line (a stacked dialog). Returns null
/// when cancelled.
Future<AiLineEditResult?> showAiLineEditor(
  BuildContext context, {
  required DraftLine line,
  LineEdit? current,
  String? categoryName,
}) => showStackedDialog<AiLineEditResult>(
  context: context,
  builder: (_) => _AiLineEditor(
    line: line,
    current: current,
    categoryName: categoryName,
  ),
);

class _AiLineEditor extends ConsumerStatefulWidget {
  const _AiLineEditor({
    required this.line,
    required this.current,
    required this.categoryName,
  });

  final DraftLine line;
  final LineEdit? current;
  final String? categoryName;

  @override
  ConsumerState<_AiLineEditor> createState() => _AiLineEditorState();
}

class _AiLineEditorState extends ConsumerState<_AiLineEditor> {
  late final TextEditingController _qty;
  late final TextEditingController _price;
  String? _categoryId;
  String? _categoryName;
  String? _error;

  static String _text(double? v) {
    if (v == null) return '';
    final s = v.toString();
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  @override
  void initState() {
    super.initState();
    _qty = TextEditingController(
      text: _text(widget.current?.quantity ?? widget.line.quantity),
    );
    _price = TextEditingController(
      text: _text(widget.current?.unitPrice ?? widget.line.unitPrice),
    );
    _categoryId = widget.current?.categoryId;
    _categoryName = widget.categoryName;
  }

  @override
  void dispose() {
    _qty.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _pickCategory() async {
    final id = await pickBudgetCategory(context);
    if (id == null || !mounted) return;
    final db = ref.read(databaseProvider);
    final row = await (db.select(
      db.budgetCategoriesTable,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (!mounted) return;
    setState(() {
      _categoryId = id;
      _categoryName = row?.name ?? _categoryName;
    });
  }

  double? _parse(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

  void _save() {
    final q = _qty.text.trim().isEmpty ? null : _parse(_qty.text);
    final p = _price.text.trim().isEmpty ? null : _parse(_price.text);
    if ((_qty.text.trim().isNotEmpty && (q == null || q <= 0)) ||
        (_price.text.trim().isNotEmpty && (p == null || p < 0))) {
      setState(() => _error = 'Enter valid numbers.');
      return;
    }
    // Only fields that really changed are sent.
    final qChanged = q != null && q != widget.line.quantity;
    final pChanged = p != null && p != widget.line.unitPrice;
    Navigator.of(context).pop((
      edit: LineEdit(
        index: widget.line.index,
        categoryId: _categoryId,
        quantity: qChanged ? q : widget.current?.quantity,
        unitPrice: pChanged ? p : widget.current?.unitPrice,
      ),
      categoryName: _categoryId == null ? null : _categoryName,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.line.name.isEmpty ? 'Edit line' : widget.line.name),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OutlinedButton(
              key: const ValueKey('ai-line-category'),
              onPressed: _pickCategory,
              child: Text(_categoryName ?? widget.line.categoryName ?? 'Category'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('ai-line-qty'),
              controller: _qty,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Quantity'),
            ),
            TextFormField(
              key: const ValueKey('ai-line-price'),
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Unit price'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
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
        FilledButton(
          key: const ValueKey('ai-line-save'),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
