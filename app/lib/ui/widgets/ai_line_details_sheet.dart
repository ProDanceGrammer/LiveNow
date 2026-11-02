import 'package:flutter/material.dart';

import '../../domain/ai/ai_draft.dart';
import '../dialog_stack.dart';

String _money(double v) => v.toStringAsFixed(2);

String _qty(double v) {
  final s = v.toStringAsFixed(3);
  return s.replaceFirst(RegExp(r'\.?0+$'), '');
}

String _unitShort(String? unit) => switch (unit) {
  'kilogram' => 'kg',
  'piece' => 'pcs',
  _ => unit ?? '',
};

/// `0.785 kg x 39.00 = 30.62 TRY`, or just `30.62 TRY` while the weight is unknown.
String aiLineSummary(DraftLine l, String currency) {
  final q = l.quantity;
  final p = l.unitPrice;
  final unit = _unitShort(l.unit);
  final head = q != null && p != null
      ? '${_qty(q)}${unit.isEmpty ? '' : ' $unit'} × ${_money(p)} = '
      : '';
  return '$head${_money(l.amount)} $currency';
}

/// What a candidate category is, for the details list: its usual price and unit.
String _choiceHint(DraftChoice c) {
  final parts = [
    if (c.price != null) _money(c.price!),
    if (c.unit != null && c.unit!.isNotEmpty) _unitShort(c.unit),
  ];
  return parts.join(' / ');
}

/// The data of ONE receipt line a question is about, so it can be checked before
/// answering: printed and translated name, quantity, price, amount, and every
/// category the assistant offers with its group and usual price. [onChoose] turns a
/// candidate into the answer (null once the question is answered).
Future<void> showAiLineDetails(
  BuildContext context, {
  required DraftLine line,
  required String currency,
  ValueChanged<DraftChoice>? onChoose,
}) => showStackedDialog<void>(
  context: context,
  builder: (ctx) => AlertDialog(
    key: const ValueKey('ai-line-details'),
    title: Text(line.displayName),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Field('Printed', line.raw),
          if (line.uaName != null && line.uaName != line.name)
            _Field('Translated', line.uaName!),
          _Field('Quantity × price', aiLineSummary(line, currency)),
          if (line.categoryName != null) _Field('Category', line.categoryName!),
          if (line.candidates.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Offered categories', style: Theme.of(ctx).textTheme.labelLarge),
            for (var i = 0; i < line.candidates.length; i++)
              ListTile(
                key: ValueKey('ai-detail-choice-$i'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(line.candidates[i].label),
                subtitle: _choiceHint(line.candidates[i]).isEmpty
                    ? null
                    : Text(_choiceHint(line.candidates[i])),
                enabled: onChoose != null,
                onTap: onChoose == null
                    ? null
                    : () {
                        Navigator.of(ctx).pop();
                        onChoose(line.candidates[i]);
                      },
              ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        key: const ValueKey('ai-line-details-close'),
        onPressed: () => Navigator.of(ctx).pop(),
        child: const Text('Close'),
      ),
    ],
  ),
);

class _Field extends StatelessWidget {
  const _Field(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          TextSpan(text: value),
        ],
      ),
    ),
  );
}
