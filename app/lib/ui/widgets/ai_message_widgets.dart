import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../domain/ai/ai_protocol.dart';
import '../../domain/ai/job_progress.dart' show ProgressSnapshot;
import '../ai_ui_providers.dart';
import '../ai_providers.dart';
import 'ai_photo_viewer.dart';

/// Widest a chat bubble or card grows (desktop); a phone uses the full width.
const kAiBubbleMaxWidth = 640.0;

/// A bank statement file sent in a message: a chip with its name and size, and
/// the caption. No viewer: the hub reads the file.
class _FileBubble extends StatelessWidget {
  const _FileBubble({required this.message, required this.content});

  final AiMessage message;
  final Map<String, dynamic> content;

  @override
  Widget build(BuildContext context) {
    final name = '${content['file_name'] ?? 'statement'}';
    final size = content['size'];
    final kb = size is num ? '${(size / 1024).ceil()} KB' : '';
    final sheet = !name.toLowerCase().endsWith('.csv');
    return AiBubbleFrame(
      fromUser: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            key: ValueKey('ai-file-${message.id}'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(sheet ? Icons.table_chart_outlined : Icons.description_outlined),
              const SizedBox(width: 8),
              Flexible(
                child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              if (kb.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(kb, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
          if (message.body.isNotEmpty)
            SelectableText(
              message.body,
              key: ValueKey('ai-photo-caption-${message.id}'),
            ),
        ],
      ),
    );
  }
}

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
    final content = aiContent(message);
    if (content['kind'] == AiJobKind.statement) {
      return _FileBubble(message: message, content: content);
    }
    final blobs =
        ref.watch(aiBlobsOfMessageProvider(message.id)).asData?.value ??
        const <AiBlob>[];
    // One photo is shown large, several side by side.
    final width = blobs.length > 1 ? 130.0 : 220.0;
    final pics = <Widget>[];
    for (var i = 0; i < blobs.length; i++) {
      // The first photo keeps the plain key (one-photo messages).
      final suffix = i == 0 ? '' : '-$i';
      pics.add(_photo(context, blobs, i, width, suffix));
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
          if (message.body.isNotEmpty)
            SelectableText(
              message.body,
              key: ValueKey('ai-photo-caption-${message.id}'),
            ),
        ],
      ),
    );
  }

  Widget _photo(
    BuildContext context,
    List<AiBlob> blobs,
    int index,
    double width,
    String suffix,
  ) {
    final data = blobs[index].data;
    if (data != null && data.isNotEmpty) {
      final bytes = base64Decode(data);
      // Still on this device (just sent): opens from here, no hub needed.
      return GestureDetector(
        key: ValueKey('ai-photo-open-${message.id}$suffix'),
        onTap: () => _openViewer(context, blobs, index),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            bytes,
            key: ValueKey('ai-photo-${message.id}$suffix'),
            width: width,
            cacheWidth: (width * 2).round(),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => _PhotoPlaceholder(width: width),
          ),
        ),
      );
    }
    return InkWell(
      key: ValueKey('ai-photo-original-${message.id}$suffix'),
      onTap: () => _openViewer(context, blobs, index),
      child: _PhotoPlaceholder(hub: true, width: width),
    );
  }
}

/// Opens the viewer at [index] with all photos of the message; hub originals
/// are fetched by the viewer when their page is first shown.
Future<void> _openViewer(
  BuildContext context,
  List<AiBlob> blobs,
  int index,
) {
  final photos = <AiPhotoRef>[
    for (final b in blobs)
      (b.data != null && b.data!.isNotEmpty)
          ? AiPhotoRef.local(base64Decode(b.data!))
          : AiPhotoRef.hub(b.id),
  ];
  return showAiPhotoViewer(context, photos, index);
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
class AiStatusLine extends ConsumerStatefulWidget {
  const AiStatusLine({super.key, required this.message, this.latest = true});

  final AiMessage message;

  /// Only the newest status line carries the plain `ai-status-line` key.
  final bool latest;

  @override
  ConsumerState<AiStatusLine> createState() => _AiStatusLineState();
}

/// While the hub works, a v2 status (one write per step: its share of the bar,
/// when it began and how long it should take) shows the step, a live % and the
/// step's time, and a thin bar that moves between the hub's writes.
class _AiStatusLineState extends ConsumerState<AiStatusLine> {
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _ticking(bool on) {
    if (on && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!on && _tick != null) {
      _tick!.cancel();
      _tick = null;
    }
  }

  static String _clock(Duration d) {
    final s = d.inSeconds < 0 ? 0 : d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final jobId = message.jobId;
    final job = jobId == null
        ? null
        : ref.watch(aiJobProvider(jobId)).asData?.value;
    final working = job != null && AiJobState.active.contains(job.state);
    final snap = ProgressSnapshot.fromJson(aiContent(message));
    final live = working && snap != null;
    // Only the newest line moves (older ones are history).
    _ticking(live && widget.latest);
    final now = DateTime.now();
    final pct = live ? snap.percentAt(now) : null;
    final text = live
        ? [
            snap.label,
            if (snap.detail != null && snap.detail!.isNotEmpty) snap.detail!,
            '${pct!.floor()}%',
            _clock(now.difference(snap.started)),
          ].join(' · ')
        : (message.body.isNotEmpty ? message.body : (job?.stage ?? ''));
    final row = Row(
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
    );
    return Padding(
      key: ValueKey(widget.latest ? 'ai-status-line' : 'ai-status-line-${message.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: pct == null
          ? row
          : ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  row,
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      key: const ValueKey('ai-status-bar'),
                      value: (pct / 100).clamp(0.0, 1.0),
                      minHeight: 3,
                    ),
                  ),
                ],
              ),
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
