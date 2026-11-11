import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ids.dart';
import '../../core/time_codec.dart';
import '../../data/database.dart';
import '../../domain/ai/action_creator.dart' show kNewActionHalfSpan;
import '../../domain/ai/ai_draft.dart';
import '../../domain/ai/alias_source.dart';
import '../../domain/ai/receipt_memory.dart';
import '../../domain/ai/ai_protocol.dart';
import '../ai_providers.dart';
import '../open_entity.dart';
import '../time_format.dart';
import 'ai_category_chooser.dart';
import 'ai_line_editor.dart';
import 'ai_message_widgets.dart';
import 'app_toast.dart';

String _fmt(double? v) {
  if (v == null) return '-';
  final s = v.toStringAsFixed(2);
  return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
}

/// A quantity: up to 3 decimals, no trailing zeros.
String _qty(double? v) {
  if (v == null) return '?';
  return v.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
}

double _round(double v, int digits) {
  var f = 1.0;
  for (var i = 0; i < digits; i++) {
    f *= 10;
  }
  return (v * f).round() / f;
}

String _unitLabel(String? unit) => switch (unit) {
  'kilogram' => 'kg',
  'piece' => 'pcs',
  null || '' => 'kg',
  final u => u,
};

String _day(DateTime utc) {
  final d = utc.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

/// The draft (a [DraftCard] in `content_json`): header, lines, sum check, action
/// and rate summary, and Confirm / Reject. Every line is an EDITABLE suggestion:
/// tap its category (offered list, search, or "create"), its quantity, its unit
/// or its price to change it. The printed amount of a line stays fixed, so
/// changing the quantity recomputes the price and the other way round. The edits
/// are sent with Confirm; nothing is written before. Once the user decided (or the
/// hub already committed), the buttons are replaced by the decision.
class AiDraftCard extends ConsumerStatefulWidget {
  const AiDraftCard({
    super.key,
    required this.message,
    required this.decision,
    this.latest = true,
  });

  final AiMessage message;

  /// The user's decision on this draft, or null while none was sent.
  final ConfirmDecision? decision;

  /// Only the newest pending draft carries the plain `ai-draft-*` keys.
  final bool latest;

  @override
  ConsumerState<AiDraftCard> createState() => _AiDraftCardState();
}

class _AiDraftCardState extends ConsumerState<AiDraftCard> {
  final Map<int, LineEdit> _edits = {};
  final Map<int, String> _categoryNames = {};
  bool _busy = false;

  String _key(String base) =>
      widget.latest ? base : '$base-${widget.message.id}';

  Future<void> _decide(bool confirm) async {
    if (_busy) return;
    final overlay = rootOverlayOf(context);
    final service = ref.read(aiChatServiceProvider);
    setState(() => _busy = true);
    try {
      if (confirm) {
        await service.confirmDraft(
          widget.message.id,
          edits: _edits.values.toList(),
        );
      } else {
        await service.rejectDraft(widget.message.id);
      }
    } catch (e) {
      showInfoToast(overlay, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The edit of [line] with the given fields replaced (the others kept).
  LineEdit _merged(
    DraftLine line, {
    bool category = false,
    String? categoryId,
    String? newName,
    double? quantity,
    double? unitPrice,
    String? unit,
  }) {
    final p = _edits[line.index];
    return LineEdit(
      index: line.index,
      categoryId: category ? categoryId : p?.categoryId,
      newName: category ? newName : p?.newName,
      quantity: quantity ?? p?.quantity,
      unitPrice: unitPrice ?? p?.unitPrice,
      unit: unit ?? p?.unit,
    );
  }

  void _setQuantity(DraftLine line, double q) => setState(
    () => _edits[line.index] = _merged(
      line,
      quantity: q,
      unitPrice: _round(line.amount / q, 4),
    ),
  );

  void _setPrice(DraftLine line, double p) => setState(
    () => _edits[line.index] = _merged(
      line,
      unitPrice: p,
      quantity: _round(line.amount / p, 4),
    ),
  );

  void _toggleUnit(DraftLine line) {
    final now = _edits[line.index]?.unit ?? line.unit;
    setState(
      () => _edits[line.index] = _merged(
        line,
        unit: now == 'piece' ? 'kilogram' : 'piece',
      ),
    );
  }

  Future<void> _pickCategory(DraftLine line) async {
    final r = await showAiCategoryChooser(context, line: line);
    if (r == null || !mounted) return;
    final twins = [
      for (final l in DraftCard.fromJson(aiContent(widget.message)).lines)
        if (l.index != line.index &&
            !l.skipped &&
            !l.committed &&
            productKey(l.name) == productKey(line.name))
          l,
    ];
    setState(() {
      for (final l in [line, ...twins]) {
        // A twin keeps a category the user already chose for it.
        if (l != line && _edits[l.index]?.categoryId != null) continue;
        _edits[l.index] = _merged(
          l,
          category: true,
          categoryId: r.id,
          newName: r.newName,
        );
        _categoryNames[l.index] = r.newName == null ? r.name : '${r.newName} (new)';
      }
    });
  }

  Future<void> _editLine(DraftLine line) async {
    final r = await showAiLineEditor(
      context,
      line: line,
      current: _edits[line.index],
      categoryName: _categoryNames[line.index] ?? line.categoryName,
    );
    if (r == null || !mounted) return;
    setState(() {
      _edits[line.index] = _merged(
        line,
        category: r.edit.categoryId != null,
        categoryId: r.edit.categoryId,
        newName: null,
        quantity: r.edit.quantity,
        unitPrice: r.edit.unitPrice,
      );
      if (r.categoryName != null) _categoryNames[line.index] = r.categoryName!;
    });
  }

  bool _hasTwins(List<DraftLine> lines) {
    final seen = <String>{};
    for (final l in lines) {
      if (!seen.add(productKey(l.name))) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final draft = DraftCard.fromJson(aiContent(widget.message));
    final theme = Theme.of(context);
    final decided =
        widget.decision != null || draft.userConfirmed || draft.confirmed;
    final shown = [for (final l in draft.lines) if (!l.skipped) l];
    final sum = draft.sum;
    final head = [
      if ((draft.merchant ?? '').isNotEmpty) draft.merchant!,
      _day(draft.at),
      if (sum != null) 'Total ${_fmt(sum.expected ?? sum.linesSum)} ${draft.currency}',
    ].join('  -  ');
    return AiBubbleFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(head, style: theme.textTheme.titleSmall),
          if (!decided)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Check the suggestions: tap a category, quantity, unit or price to change it.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (draft.seen != null && !decided)
            _SeenPanel(
              keyOf: _key,
              seen: SeenReceipt.fromJson(draft.seen!),
              currency: draft.currency,
            ),
          if (!decided && _hasTwins(shown))
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Lines with the same name share one category.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 6),
          for (final l in shown)
            _LineRow(
              key: ValueKey(_key('ai-draft-line-${l.index}')),
              keyOf: _key,
              line: l,
              edit: _edits[l.index],
              categoryName: _categoryNames[l.index],
              enabled: !(decided || l.committed),
              onName: () => _editLine(l),
              onCategory: () => _pickCategory(l),
              onQuantity: (v) => _setQuantity(l, v),
              onPrice: (v) => _setPrice(l, v),
              onUnit: () => _toggleUnit(l),
            ),
          if (sum != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                key: ValueKey(_key('ai-draft-sum')),
                sum.ok
                    ? 'Lines add up to ${_fmt(sum.linesSum)} ${draft.currency}'
                    : 'Sum mismatch: lines ${_fmt(sum.linesSum)}, '
                          'receipt ${_fmt(sum.expected)}'
                          '${decided ? '' : '. Tap a line name to fix its amounts.'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: sum.ok ? null : theme.colorScheme.error,
                ),
              ),
            ),
          if (draft.action != null)
            _DraftActionLine(
              action: draft.action!,
              at: draft.at,
              // Confirm gives a new action this id (`_ensureAction`).
              createdId: widget.message.jobId == null
                  ? null
                  : deriveId(widget.message.jobId!, 'action'),
              keyName: _key('ai-draft-action'),
            ),
          if (draft.action != null || draft.useAccountName != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                [
                  if (draft.useAccountName != null)
                    'Account: ${draft.useAccountName}',
                  'Rate: ${draft.fxSource}',
                ].join('   '),
                key: ValueKey(_key('ai-draft-summary')),
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (draft.duplicate)
            Text(
              'Looks like a duplicate of an earlier receipt',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          for (final n in draft.notes)
            Text(n, style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          if (!decided)
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  key: ValueKey(_key('ai-draft-confirm')),
                  onPressed: _busy ? null : () => _decide(true),
                  child: Text(
                    _edits.isEmpty
                        ? 'Confirm'
                        : 'Confirm (${_edits.length} edited)',
                  ),
                ),
                OutlinedButton(
                  key: ValueKey(_key('ai-draft-reject')),
                  onPressed: _busy ? null : () => _decide(false),
                  child: const Text('Reject'),
                ),
              ],
            )
          else
            Text(
              widget.decision?.confirm == false ? 'Rejected' : 'Confirmed',
              style: theme.textTheme.labelMedium,
            ),
        ],
      ),
    );
  }
}

/// What was saved the first time this receipt was confirmed (read-only); the
/// question card below asks what to do with the copy.
/// `Action: <name> · <start → end>` of the action the purchase goes to. An
/// action that exists here shows its live name and schedule and opens its edit
/// menu on tap; a new one (created only by Confirm) shows the span Confirm will
/// give it and is not tappable.
class _DraftActionLine extends ConsumerWidget {
  const _DraftActionLine({
    required this.action,
    required this.at,
    required this.createdId,
    required this.keyName,
  });

  final DraftAction action;
  final DateTime at;
  final String? createdId;
  final String keyName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final id = action.id ?? (action.isNew ? createdId : null);
    final row = id == null ? null : ref.watch(aiDraftActionProvider(id)).asData?.value;
    final String text;
    if (row != null) {
      final when = formatShortSchedule(
        dateTimeFromDb(row.startAt),
        dateTimeFromDb(row.endAt),
        isAllDay: row.isAllDay,
      );
      text = 'Action: ${row.name}${when == null ? '' : ' · $when'}';
    } else {
      final when = action.isNew
          ? formatShortSchedule(at.subtract(kNewActionHalfSpan), at.add(kNewActionHalfSpan))
          : null;
      text = 'Action: ${action.name}${action.isNew ? ' (new)' : ''}'
          '${when == null ? '' : ' · $when'}';
    }
    final label = Text(
      text,
      key: ValueKey(keyName),
      style: row == null
          ? theme.textTheme.bodySmall
          : theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
              decoration: TextDecoration.underline,
              decorationColor: theme.colorScheme.primary,
            ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: row == null
          ? label
          : InkWell(
              onTap: () => openActionById(context, ref, row.id),
              child: label,
            ),
    );
  }
}

class _SeenPanel extends StatelessWidget {
  const _SeenPanel({required this.keyOf, required this.seen, required this.currency});

  final String Function(String) keyOf;
  final SeenReceipt seen;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: ValueKey(keyOf('ai-seen')),
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Already saved from this receipt${seen.at == null ? '' : ' (${_day(seen.at!)})'}:',
            style: theme.textTheme.labelMedium,
          ),
          for (var i = 0; i < seen.lines.length; i++)
            Text(
              key: ValueKey(keyOf('ai-seen-line-$i')),
              '${seen.lines[i].name}  ->  ${seen.lines[i].category ?? '?'}  '
              '${_qty(seen.lines[i].quantity)} x ${_fmt(seen.lines[i].unitPrice)} '
              '= ${_fmt(seen.lines[i].amount)} $currency',
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({
    super.key,
    required this.keyOf,
    required this.line,
    required this.edit,
    required this.categoryName,
    required this.enabled,
    required this.onName,
    required this.onCategory,
    required this.onQuantity,
    required this.onPrice,
    required this.onUnit,
  });

  final String Function(String) keyOf;
  final DraftLine line;
  final LineEdit? edit;
  final String? categoryName;
  final bool enabled;
  final VoidCallback onName;
  final VoidCallback onCategory;
  final ValueChanged<double> onQuantity;
  final ValueChanged<double> onPrice;
  final VoidCallback onUnit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final i = line.index;
    final qty = edit?.quantity ?? line.quantity;
    final price = edit?.unitPrice ?? line.unitPrice;
    final unit = edit?.unit ?? line.unit;
    final hasCategory = edit?.categoryId != null || line.categoryId != null;
    final cat = categoryName ?? line.categoryName ?? '?';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: ValueKey(keyOf('ai-line-name-$i')),
            onTap: enabled ? onName : null,
            child: Text(line.displayName, style: theme.textTheme.bodyMedium),
          ),
          if (line.uaName != null && line.uaName != line.name)
            Text(
              line.name,
              key: ValueKey<String>('ai-line-printed-$i'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 2),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Cell(
                key: ValueKey(keyOf('ai-cell-cat-$i')),
                text: cat,
                missing: !hasCategory,
                edited: edit?.categoryId != null,
                icon: Icons.arrow_drop_down,
                onTap: enabled ? onCategory : null,
              ),
              _NumCell(
                key: ValueKey(keyOf('ai-cell-qty-$i')),
                fieldKey: ValueKey(keyOf('ai-cell-qty-$i-field')),
                value: qty,
                text: _qty(qty),
                missing: qty == null,
                edited: edit?.quantity != null,
                onSubmit: enabled ? onQuantity : null,
              ),
              _Cell(
                key: ValueKey(keyOf('ai-cell-unit-$i')),
                text: _unitLabel(unit),
                edited: edit?.unit != null,
                onTap: enabled ? onUnit : null,
              ),
              const Text('×'),
              _NumCell(
                key: ValueKey(keyOf('ai-cell-price-$i')),
                fieldKey: ValueKey(keyOf('ai-cell-price-$i-field')),
                value: price,
                text: _fmt(price),
                missing: price == null,
                edited: edit?.unitPrice != null,
                onSubmit: enabled ? onPrice : null,
              ),
              Text('= ${_fmt(line.amount)}', style: theme.textTheme.bodyMedium),
            ],
          ),
          Wrap(
            spacing: 4,
            children: [
              if (line.suggested)
                _Badge(
                  line.confidence == null
                      ? 'suggested'
                      : 'suggested ${(line.confidence! * 100).round()}%',
                ),
              if (line.flags.contains(kFlagWeightGuess)) const _Badge('weight estimated'),
              if (line.newCategory) const _Badge('new category'),
              if (line.priceChange) const _Badge('price change'),
              if (line.needsAnswer && edit == null) const _Badge('needs answer'),
              if (edit != null) const _Badge('edited'),
              if (line.committed) const _Badge('recorded'),
            ],
          ),
        ],
      ),
    );
  }
}

/// A tappable value chip (category, unit). [missing]: nothing known yet.
class _Cell extends StatelessWidget {
  const _Cell({
    super.key,
    required this.text,
    required this.onTap,
    this.missing = false,
    this.edited = false,
    this.icon,
  });

  final String text;
  final VoidCallback? onTap;
  final bool missing;
  final bool edited;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = missing
        ? cs.errorContainer
        : edited
        ? cs.primaryContainer
        : cs.surfaceContainerHighest;
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
              if (icon != null && onTap != null) Icon(icon, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// A number chip that turns into a small text field when tapped (Enter or tapping
/// away applies a valid positive number).
class _NumCell extends StatefulWidget {
  const _NumCell({
    super.key,
    required this.value,
    required this.text,
    required this.onSubmit,
    required this.fieldKey,
    this.missing = false,
    this.edited = false,
  });

  final Key fieldKey;
  final double? value;
  final String text;
  final ValueChanged<double>? onSubmit;
  final bool missing;
  final bool edited;

  @override
  State<_NumCell> createState() => _NumCellState();
}

class _NumCellState extends State<_NumCell> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _editing) _commit();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _start() {
    _controller.text = widget.value == null ? '' : _qty(widget.value);
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _commit() {
    if (!_editing) return;
    final v = double.tryParse(_controller.text.trim().replaceAll(',', '.'));
    setState(() => _editing = false);
    if (v != null && v > 0 && v != widget.value) widget.onSubmit?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    if (_editing) {
      return SizedBox(
        width: 84,
        child: TextField(
          key: widget.fieldKey,
          controller: _controller,
          focusNode: _focus,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: const InputDecoration(isDense: true),
          onSubmitted: (_) => _commit(),
        ),
      );
    }
    return _Cell(
      text: widget.text,
      missing: widget.missing,
      edited: widget.edited,
      onTap: widget.onSubmit == null ? null : _start,
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: cs.onSecondaryContainer),
      ),
    );
  }
}
