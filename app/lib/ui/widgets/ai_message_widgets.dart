import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../domain/ai/ai_protocol.dart';
import '../ai_history_loader.dart' show aiBlobFetcherProvider;
import '../ai_ui_providers.dart';
import '../dialog_stack.dart';
import '../ai_providers.dart';
import 'app_toast.dart';

/// Widest a chat bubble or card grows (desktop); a phone uses the full width.
const kAiBubbleMaxWidth = 640.0;

/// Common frame: aligns a message left (assistant) or right (user).
class AiBubbleFrame extends StatelessWidget {
  const AiBubbleFrame({
    super.key,
    required this.child,
    this.fromUser = false,
    this.tint,
  });

  final Widget child;
  final bool fromUser;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kAiBubbleMaxWidth),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color:
                tint ??
                (fromUser ? cs.primaryContainer : cs.surfaceContainerHighest),
            borderRadius: BorderRadius.circular(12),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// A text line of the user or the assistant.
class AiTextBubble extends StatelessWidget {
  const AiTextBubble({super.key, required this.message});

  final AiMessage message;

  @override
  Widget build(BuildContext context) {
    final fromUser = message.role == AiRole.user;
    return AiBubbleFrame(
      fromUser: fromUser,
      child: SelectableText(message.body),
    );
  }
}

/// What the user decided on a draft ("Confirm" / "Reject"): a small line.
class AiDecisionBubble extends StatelessWidget {
  const AiDecisionBubble({super.key, required this.message});

  final AiMessage message;

  @override
  Widget build(BuildContext context) {
    final edits = ConfirmDecision.fromJson(_json(message.contentJson)).edits;
    final extra = edits.isEmpty ? '' : ' (${edits.length} edited)';
    return AiBubbleFrame(fromUser: true, child: Text('${message.body}$extra'));
  }
}

/// The photos of one user message: each is a thumbnail while its bytes are
/// still on this device, else a placeholder (the original lives on the hub).
class AiPhotoBubble extends ConsumerWidget {
  const AiPhotoBubble({super.key, required this.message});

  final AiMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blobs =
        ref.watch(aiBlobsOfMessageProvider(message.id)).asData?.value ??
        const <AiBlob>[];
    // One photo is shown large, several side by side.
    final width = blobs.length > 1 ? 130.0 : 220.0;
    final pics = <Widget>[];
    for (var i = 0; i < blobs.length; i++) {
      // The first photo keeps the plain key (one-photo messages).
      final suffix = i == 0 ? '' : '-$i';
      pics.add(_photo(context, ref, blobs[i], width, suffix));
    }
    if (blobs.isEmpty) {
      pics.add(
        InkWell(
          key: ValueKey('ai-photo-original-${message.id}'),
          child: const _PhotoPlaceholder(hub: true),
        ),
      );
    }
    return AiBubbleFrame(
      fromUser: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 6,
            runSpacing: 6,
            children: pics,
          ),
          if (message.body.isNotEmpty) Text(message.body),
        ],
      ),
    );
  }

  Widget _photo(
    BuildContext context,
    WidgetRef ref,
    AiBlob blob,
    double width,
    String suffix,
  ) {
    final data = blob.data;
    if (data != null && data.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          base64Decode(data),
          key: ValueKey('ai-photo-${message.id}$suffix'),
          width: width,
          cacheWidth: (width * 2).round(),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _PhotoPlaceholder(width: width),
        ),
      );
    }
    return InkWell(
      key: ValueKey('ai-photo-original-${message.id}$suffix'),
      onTap: () => _openOriginal(context, ref, blob.id),
      child: _PhotoPlaceholder(hub: true, width: width),
    );
  }
}

/// Fetches the original from the hub and shows it full size; a toast when the
/// hub has no copy or cannot be reached.
Future<void> _openOriginal(
  BuildContext context,
  WidgetRef ref,
  String blobId,
) async {
  final overlay = rootOverlayOf(context);
  final fetch = ref.read(aiBlobFetcherProvider);
  final bytes = await fetch(blobId);
  if (bytes == null) {
    showInfoToast(overlay, 'The original is not available from the hub');
    return;
  }
  if (!context.mounted) return;
  await showStackedDialog<void>(
    context: context,
    builder: (_) => Dialog(
      key: const ValueKey('ai-photo-viewer'),
      child: InteractiveViewer(child: Image.memory(bytes)),
    ),
  );
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder({this.hub = false, this.width = 220});

  final bool hub;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: 90,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.image_outlined),
        const SizedBox(height: 4),
        Text(
          hub ? 'Original on the hub' : 'Photo not available',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

/// The live status line of a job: stage text + a small progress indicator while
/// the job is working. The text is the status message row, which the hub
/// updates in place, so this rebuilds as it changes.
class AiStatusLine extends ConsumerWidget {
  const AiStatusLine({super.key, required this.message, this.latest = true});

  final AiMessage message;

  /// Only the newest status line carries the plain `ai-status-line` key.
  final bool latest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobId = message.jobId;
    final job = jobId == null
        ? null
        : ref.watch(aiJobProvider(jobId)).asData?.value;
    final working = job != null && AiJobState.active.contains(job.state);
    final text = message.body.isNotEmpty ? message.body : (job?.stage ?? '');
    return Padding(
      key: ValueKey(latest ? 'ai-status-line' : 'ai-status-line-${message.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (working)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              job?.state == AiJobState.done
                  ? Icons.check_circle_outline
                  : Icons.hourglass_empty,
              size: 14,
            ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// An error from the job; "Try again" re-sends the user's request when the
/// caller gives [onRetry].
class AiErrorCard extends StatelessWidget {
  const AiErrorCard({super.key, required this.message, this.onRetry});

  final AiMessage message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AiBubbleFrame(
      tint: cs.errorContainer,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: cs.onErrorContainer),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message.body,
              style: TextStyle(color: cs.onErrorContainer),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 8),
            TextButton(
              key: ValueKey('ai-error-retry-${message.id}'),
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
          ],
        ],
      ),
    );
  }
}

Map<String, dynamic> _json(String s) {
  try {
    final j = jsonDecode(s);
    if (j is Map) return Map<String, dynamic>.from(j);
  } catch (_) {}
  return {};
}

/// Decodes a message's `content_json` (an empty map when it is not valid).
Map<String, dynamic> aiContent(AiMessage m) => _json(m.contentJson);
