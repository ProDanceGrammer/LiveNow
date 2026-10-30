import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../domain/ai/ai_draft.dart';
import '../../domain/ai/ai_protocol.dart';
import '../ai_providers.dart';
import 'ai_line_editor.dart';
import 'ai_message_widgets.dart';
import 'app_toast.dart';

String _fmt(double? v) {
  if (v == null) return '-';
  final s = v.toStringAsFixed(2);
  return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
}

String _day(DateTime utc) {
  final d = utc.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

/// The draft (a [DraftCard] in `content_json`): header, lines (item ->
/// category -> qty x price = amount, with badges), sum check, action and rate
/// summary, and Confirm / Reject. Tapping a line edits it; the edits are sent
/// with Confirm. Once the user decided (or the hub already committed), the
/// buttons are replaced by the decision.
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

  Future<void> _editLine(DraftLine line) async {
    final r = await showAiLineEditor(
      context,
      line: line,
      current: _edits[line.index],
      categoryName: _categoryNames[line.index] ?? line.categoryName,
    );
    if (r == null || !mounted) return;
    setState(() {
      _edits[line.index] = r.edit;
      if (r.categoryName != null) _categoryNames[line.index] = r.categoryName!;
    });
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
          const SizedBox(height: 6),
          for (final l in shown)
            _LineRow(
              key: ValueKey(_key('ai-draft-line-${l.index}')),
              line: l,
              edit: _edits[l.index],
              categoryName: _categoryNames[l.index],
              onTap: decided || l.committed ? null : () => _editLine(l),
            ),
          if (sum != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                key: ValueKey(_key('ai-draft-sum')),
                sum.ok
                    ? 'Lines add up to ${_fmt(sum.linesSum)} ${draft.currency}'
                    : 'Sum mismatch: lines ${_fmt(sum.linesSum)}, '
                          'receipt ${_fmt(sum.expected)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: sum.ok ? null : theme.colorScheme.error,
                ),
              ),
            ),
          if (draft.action != null || draft.useAccountName != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                [
                  if (draft.action != null)
                    'Action: ${draft.action!.name}${draft.action!.isNew ? ' (new)' : ''}',
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

class _LineRow extends StatelessWidget {
  const _LineRow({
    super.key,
    required this.line,
    required this.edit,
    required this.categoryName,
    required this.onTap,
  });

  final DraftLine line;
  final LineEdit? edit;
  final String? categoryName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final qty = edit?.quantity ?? line.quantity;
    final price = edit?.unitPrice ?? line.unitPrice;
    final amount =
        (edit?.quantity != null || edit?.unitPrice != null) &&
            qty != null &&
            price != null
        ? qty * price
        : line.amount;
    final cat = categoryName ?? line.categoryName ?? '?';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${line.name}  ->  $cat'),
                  Wrap(
                    spacing: 4,
                    children: [
                      if (line.newCategory) const _Badge('new category'),
                      if (line.priceChange) const _Badge('price change'),
                      if (line.needsAnswer) const _Badge('needs answer'),
                      if (edit != null) const _Badge('edited'),
                      if (line.committed) const _Badge('recorded'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${_fmt(qty)} x ${_fmt(price)}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 64,
              child: Text(_fmt(amount), textAlign: TextAlign.end),
            ),
          ],
        ),
      ),
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
