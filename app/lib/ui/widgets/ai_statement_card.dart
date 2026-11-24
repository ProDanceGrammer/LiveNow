import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../domain/ai/ai_protocol.dart';
import '../ai_providers.dart';
import 'ai_message_widgets.dart';
import 'app_toast.dart';

String _money(num v) {
  final s = v.toDouble().toStringAsFixed(2);
  return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
}

String _totals(Object? totals) {
  if (totals is! Map) return '';
  return totals.entries.map((e) => '${_money(e.value as num)} ${e.key}').join(' + ');
}

/// "2026-11-21T12:00:00" -> "21.11".
String _day(Object? iso) {
  final t = iso?.toString() ?? '';
  final m = RegExp(r'^\d{4}-(\d\d)-(\d\d)').firstMatch(t);
  return m == null ? '' : '${m.group(2)}.${m.group(1)}';
}

String _dayYear(Object? iso) {
  final t = iso?.toString() ?? '';
  final m = RegExp(r'^(\d{4})-(\d\d)-(\d\d)').firstMatch(t);
  return m == null ? '' : '${m.group(3)}.${m.group(2)}.${m.group(1)}';
}

/// The summary of a bank statement (`{type: 'statement'}` draft): the file, its
/// account and period, the groups of rows that Confirm writes, the rows that
/// were already recorded or cancelled, and ONE Confirm. Rows are read-only: a
/// wrong group is fixed by answering the hub's questions or by Undo after.
class AiStatementCard extends ConsumerStatefulWidget {
  const AiStatementCard({
    super.key,
    required this.message,
    required this.decision,
    this.latest = true,
  });

  final AiMessage message;
  final ConfirmDecision? decision;
  final bool latest;

  @override
  ConsumerState<AiStatementCard> createState() => _AiStatementCardState();
}

class _AiStatementCardState extends ConsumerState<AiStatementCard> {
  bool _busy = false;

  String _key(String base) => widget.latest ? base : '$base-${widget.message.id}';

  Future<void> _decide(bool confirm) async {
    if (_busy) return;
    final overlay = rootOverlayOf(context);
    final service = ref.read(aiChatServiceProvider);
    setState(() => _busy = true);
    try {
      if (confirm) {
        await service.confirmDraft(widget.message.id);
      } else {
        await service.rejectDraft(widget.message.id);
      }
    } catch (e) {
      showInfoToast(overlay, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = aiContent(widget.message);
    final theme = Theme.of(context);
    final stage = (c['stage'] ?? 'ready').toString();
    final groups = [
      if (c['groups'] is List)
        for (final g in c['groups'] as List)
          if (g is Map) Map<String, dynamic>.from(g),
    ];
    List<Map<String, dynamic>> list(String k) => [
      if (c[k] is List)
        for (final r in c[k] as List)
          if (r is Map) Map<String, dynamic>.from(r),
    ];
    final dups = list('skipped_duplicates');
    final cancelled = list('cancelled');
    final warnings = [
      if (c['warnings'] is List) for (final w in c['warnings'] as List) '$w',
    ];
    final period = c['period'] is Map ? c['period'] as Map : const {};
    final from = _dayYear(period['from']);
    final to = _dayYear(period['to']);
    final head = [
      if ((c['file_name'] ?? '').toString().isNotEmpty) c['file_name'].toString(),
      if ((c['account_name'] ?? '').toString().isNotEmpty) c['account_name'].toString(),
      if (from.isNotEmpty) from == to || to.isEmpty ? from : '$from - $to',
    ].join('  -  ');
    final decided = widget.decision != null || stage == 'done' || c['confirmed'] == true;
    final total = groups.fold<int>(0, (n, g) => n + ((g['count'] as num?)?.toInt() ?? 0));
    return AiBubbleFrame(
      key: ValueKey(_key('ai-stmt-card')),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(head.isEmpty ? 'Statement' : head, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          if (stage == 'working')
            Text('Reading the statement...', style: theme.textTheme.bodySmall)
          else if (stage == 'asking')
            Text(
              'Waiting for your answers below; the summary follows.',
              key: ValueKey(_key('ai-stmt-asking')),
              style: theme.textTheme.bodySmall,
            )
          else if (groups.isEmpty)
            Text('Nothing new to record.', style: theme.textTheme.bodySmall)
          else
            Text(
              '$total operations in ${groups.length} groups. Tap a group to see its rows.',
              style: theme.textTheme.bodySmall,
            ),
          const SizedBox(height: 6),
          for (var i = 0; i < groups.length; i++)
            _GroupTile(
              key: ValueKey(_key('ai-stmt-group-$i')),
              title: (groups[i]['title'] ?? '').toString(),
              kind: (groups[i]['kind'] ?? '').toString(),
              count: (groups[i]['count'] as num?)?.toInt() ?? 0,
              totals: _totals(groups[i]['totals']),
              rows: [
                if (groups[i]['rows'] is List)
                  for (final r in groups[i]['rows'] as List)
                    if (r is Map) Map<String, dynamic>.from(r),
              ],
            ),
          if (dups.isNotEmpty)
            _GroupTile(
              key: ValueKey(_key('ai-stmt-dups')),
              title: 'Already recorded',
              kind: 'dup',
              count: dups.length,
              totals: '',
              rows: dups,
              muted: true,
            ),
          if (cancelled.isNotEmpty)
            _GroupTile(
              key: ValueKey(_key('ai-stmt-cancelled')),
              title: 'Cancelled',
              kind: 'cancelled',
              count: cancelled.length,
              totals: '',
              rows: cancelled,
              muted: true,
            ),
          for (final w in warnings) Text(w, style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          if (stage == 'ready' && !decided)
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  key: ValueKey(_key('ai-stmt-confirm')),
                  onPressed: _busy ? null : () => _decide(true),
                  child: Text('Confirm ($total)'),
                ),
                OutlinedButton(
                  key: ValueKey(_key('ai-stmt-reject')),
                  onPressed: _busy ? null : () => _decide(false),
                  child: const Text('Reject'),
                ),
              ],
            )
          else if (stage == 'ready' || stage == 'done')
            Text(
              widget.decision?.confirm == false
                  ? 'Rejected'
                  : (groups.isEmpty ? 'Done' : 'Confirmed'),
              style: theme.textTheme.labelMedium,
            ),
        ],
      ),
    );
  }
}

/// One group: a header (title, count, totals per currency) that expands to its
/// rows (day, details, amount).
class _GroupTile extends StatefulWidget {
  const _GroupTile({
    super.key,
    required this.title,
    required this.kind,
    required this.count,
    required this.totals,
    required this.rows,
    this.muted = false,
  });

  final String title;
  final String kind;
  final int count;
  final String totals;
  final List<Map<String, dynamic>> rows;
  final bool muted;

  @override
  State<_GroupTile> createState() => _GroupTileState();
}

class _GroupTileState extends State<_GroupTile> {
  bool _open = false;

  IconData get _icon => switch (widget.kind) {
    'transfer' => Icons.swap_horiz,
    'income' => Icons.south_west,
    'fee' => Icons.percent,
    'dup' => Icons.check_circle_outline,
    'cancelled' => Icons.block,
    _ => Icons.shopping_bag_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: widget.muted ? theme.colorScheme.onSurfaceVariant : null,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          key: ValueKey('${widget.key is ValueKey ? (widget.key as ValueKey).value : ''}-header'),
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(_icon, size: 18, color: style?.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${widget.title} (${widget.count})',
                    style: style,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.totals.isNotEmpty) Text(widget.totals, style: style),
                Icon(_open ? Icons.expand_less : Icons.expand_more, size: 18),
              ],
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.only(left: 26, bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final r in widget.rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 44,
                          child: Text(_day(r['at']), style: theme.textTheme.bodySmall),
                        ),
                        Expanded(
                          child: Text(
                            [
                              (r['details'] ?? '').toString(),
                              if (r['reason'] != null) '(${r['reason']})',
                            ].join(' '),
                            style: theme.textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_money((r['amount'] as num?) ?? 0)} ${r['currency'] ?? ''}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
