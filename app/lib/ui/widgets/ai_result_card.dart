import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../ai_providers.dart';
import '../ai_ui_providers.dart';
import 'ai_message_widgets.dart';
import 'app_toast.dart';

/// What the assistant recorded (`content_json`: `batch_id`, `summary`,
/// `lines[]` with name / category_name / amount, `total`, `currency`) and an
/// "Undo batch" button. After an undo the card says so.
class AiResultCard extends ConsumerStatefulWidget {
  const AiResultCard({super.key, required this.message, this.latest = true});

  final AiMessage message;
  final bool latest;

  @override
  ConsumerState<AiResultCard> createState() => _AiResultCardState();
}

class _AiResultCardState extends ConsumerState<AiResultCard> {
  bool _busy = false;

  Future<void> _undo(String batchId) async {
    if (_busy) return;
    final overlay = rootOverlayOf(context);
    final service = ref.read(aiBatchServiceProvider);
    setState(() => _busy = true);
    try {
      final r = await service.undoBatch(batchId);
      showInfoToast(
        overlay,
        r.alreadyUndone
            ? 'That batch was already undone'
            : 'Undone: ${r.total} change${r.total == 1 ? '' : 's'} reverted'
                  '${r.skipped.isEmpty ? '' : ', ${r.skipped.length} left as they are'}',
      );
    } catch (e) {
      showInfoToast(overlay, 'Undo failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final j = aiContent(widget.message);
    final batchId = j['batch_id']?.toString() ?? '';
    final batch = batchId.isEmpty
        ? null
        : ref.watch(aiBatchRowProvider(batchId)).asData?.value;
    final undone = batch?.undoneAt != null;
    final theme = Theme.of(context);
    final lines = [
      if (j['lines'] is List)
        for (final l in j['lines'] as List)
          if (l is Map) Map<String, dynamic>.from(l),
    ];
    final summary = (j['summary'] ?? '').toString();
    return AiBubbleFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Recorded - created by assistant',
            style: theme.textTheme.titleSmall,
          ),
          if (widget.message.body.isNotEmpty) Text(widget.message.body),
          if (summary.isNotEmpty) Text(summary),
          for (final l in lines)
            Text(
              '${l['name'] ?? l['item'] ?? ''}  ->  '
              '${l['category_name'] ?? l['category'] ?? ''}  '
              '${l['amount'] ?? ''}',
              style: theme.textTheme.bodySmall,
            ),
          if (j['total'] != null)
            Text('Total ${j['total']} ${j['currency'] ?? ''}'.trim()),
          const SizedBox(height: 6),
          if (undone)
            Text(
              'Undone - these changes were reverted',
              key: ValueKey(
                widget.latest
                    ? 'ai-result-undone'
                    : 'ai-result-undone-${widget.message.id}',
              ),
              style: theme.textTheme.labelMedium,
            )
          else if (batchId.isNotEmpty)
            OutlinedButton.icon(
              key: ValueKey(
                widget.latest
                    ? 'ai-result-undo'
                    : 'ai-result-undo-${widget.message.id}',
              ),
              onPressed: _busy ? null : () => _undo(batchId),
              icon: const Icon(Icons.undo, size: 16),
              label: const Text('Undo batch'),
            ),
        ],
      ),
    );
  }
}
