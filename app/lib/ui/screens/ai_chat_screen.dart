import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../domain/ai/ai_protocol.dart';
import '../ai_history_loader.dart';
import '../ai_providers.dart';
import '../ai_ui_providers.dart';
import '../providers.dart' show databaseProvider;
import '../widgets/ai_draft_card.dart';
import '../widgets/ai_message_widgets.dart';
import '../widgets/ai_question_card.dart';
import '../widgets/ai_result_card.dart';
import '../widgets/app_toast.dart';
import 'ai_threads_screen.dart' show AiHubRequired;

/// One conversation with the assistant.
class AiChatScreen extends ConsumerStatefulWidget {
  const AiChatScreen({super.key, required this.threadId});

  final String threadId;

  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends ConsumerState<AiChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  String _photoKind = AiJobKind.receipt;
  bool _sending = false;

  /// Messages loaded by "load older" (oldest first), kept outside the stream.
  List<AiMessage> _older = const [];
  bool _loadingOlder = false;
  bool _noMoreOlder = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.hasClients &&
          _scroll.position.pixels >= _scroll.position.maxScrollExtent - 80) {
        _loadOlder();
      }
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty || _sending) return;
    final overlay = rootOverlayOf(context);
    final service = ref.read(aiChatServiceProvider);
    setState(() => _sending = true);
    try {
      await service.sendText(widget.threadId, text);
      _input.clear();
    } catch (e) {
      showInfoToast(overlay, '$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _attach(AiPhotoSource source) async {
    if (_sending) return;
    final overlay = rootOverlayOf(context);
    final pick = ref.read(aiPhotoPickerProvider);
    final prep = ref.read(aiPhotoPrepProvider);
    final service = ref.read(aiChatServiceProvider);
    final kind = _photoKind;
    setState(() => _sending = true);
    try {
      final bytes = await pick(source);
      if (bytes == null) return;
      final photo = await prep(bytes);
      await service.sendPhoto(
        widget.threadId,
        photo.bytes,
        kind: kind,
        width: photo.width,
        height: photo.height,
      );
    } on FormatException catch (e) {
      showInfoToast(overlay, e.message);
    } catch (e) {
      showInfoToast(overlay, '$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || _noMoreOlder) return;
    final shown = _shown(
      ref.read(aiMessagesProvider(widget.threadId)).asData?.value ?? const [],
    );
    if (shown.isEmpty) return;
    _loadingOlder = true;
    final service = ref.read(aiChatServiceProvider);
    final hub = ref.read(aiHistoryLoaderProvider);
    try {
      final before = shown.first.createdAt;
      var page = await service.olderMessages(widget.threadId, before);
      if (page.isEmpty) page = await hub(widget.threadId, before);
      if (!mounted) return;
      setState(() {
        if (page.isEmpty) {
          _noMoreOlder = true;
        } else {
          _older = [...page, ..._older];
        }
      });
    } catch (_) {
      // Leave the button so the user can try again.
    } finally {
      _loadingOlder = false;
    }
  }

  /// Older + newest, oldest first, without duplicates.
  List<AiMessage> _shown(List<AiMessage> window) {
    final seen = <String>{};
    final all = [..._older, ...window]
      ..sort((a, b) {
        final c = a.createdAt.compareTo(b.createdAt);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    return [
      for (final m in all)
        if (seen.add(m.id)) m,
    ];
  }

  Future<void> _retry(AiMessage error) async {
    final jobId = error.jobId;
    if (jobId == null) return;
    final overlay = rootOverlayOf(context);
    final db = ref.read(databaseProvider);
    final service = ref.read(aiChatServiceProvider);
    try {
      final job = await (db.select(
        db.aiJobsTable,
      )..where((t) => t.id.equals(jobId))).getSingleOrNull();
      final text = job == null ? null : JobPayload.decode(job.payloadJson).text;
      if (text == null || text.isEmpty) {
        showInfoToast(overlay, 'Send the photo again to retry.');
        return;
      }
      await service.sendText(widget.threadId, text);
    } catch (e) {
      showInfoToast(overlay, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = ref.watch(aiHubReadyProvider);
    final waiting =
        ready &&
        ref.watch(aiHubUnreachableProvider) &&
        (ref.watch(aiQueuedJobCountProvider).asData?.value ?? 0) > 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Assistant chat')),
      body: !ready
          ? const AiHubRequired()
          : Column(
              children: [
                if (waiting)
                  Container(
                    key: const ValueKey('ai-waiting-for-hub'),
                    width: double.infinity,
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    padding: const EdgeInsets.all(6),
                    child: const Text(
                      'Waiting for hub - your messages will be sent when it is reachable',
                      textAlign: TextAlign.center,
                    ),
                  ),
                Expanded(child: _messages()),
                _inputArea(context),
              ],
            ),
    );
  }

  Widget _messages() {
    final async = ref.watch(aiMessagesProvider(widget.threadId));
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => Center(child: Text('$e')),
      data: (window) {
        final items = _shown(window);
        if (items.isEmpty) {
          return const Center(
            key: ValueKey('ai-chat-empty'),
            child: Text('Send a receipt photo or a note to start.'),
          );
        }
        final decisions = <String, ConfirmDecision>{};
        for (final m in items) {
          if (m.kind == AiMessageKind.confirm) {
            final d = ConfirmDecision.fromJson(aiContent(m));
            decisions[d.draftMessageId] = d;
          }
        }
        String? lastOf(String kind) {
          for (var i = items.length - 1; i >= 0; i--) {
            if (items[i].kind == kind) return items[i].id;
          }
          return null;
        }

        final lastStatus = lastOf(AiMessageKind.status);
        // The newest draft that still waits for the user carries the plain keys.
        String? lastPendingDraft;
        for (var i = items.length - 1; i >= 0; i--) {
          if (items[i].kind == AiMessageKind.draft &&
              !decisions.containsKey(items[i].id)) {
            lastPendingDraft = items[i].id;
            break;
          }
        }
        final lastQuestion = lastOf(AiMessageKind.question);
        final lastResult = lastOf(AiMessageKind.result);
        final hasOlderButton = !_noMoreOlder;
        final count = items.length + (hasOlderButton ? 1 : 0);
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView.builder(
              key: const ValueKey('ai-chat-list'),
              controller: _scroll,
              reverse: true,
              itemCount: count,
              itemBuilder: (_, r) {
                // reverse: index 0 is the newest.
                final i = items.length - 1 - r;
                if (i < 0) {
                  return Center(
                    child: TextButton(
                      key: const ValueKey('ai-load-older'),
                      onPressed: _loadOlder,
                      child: const Text('Load older messages'),
                    ),
                  );
                }
                final m = items[i];
                return KeyedSubtree(
                  key: ValueKey('ai-msg-${m.id}'),
                  child: switch (m.kind) {
                    AiMessageKind.photo => AiPhotoBubble(message: m),
                    AiMessageKind.status => AiStatusLine(
                      message: m,
                      latest: m.id == lastStatus,
                    ),
                    AiMessageKind.draft => AiDraftCard(
                      message: m,
                      decision: decisions[m.id],
                      latest: m.id == lastPendingDraft,
                    ),
                    AiMessageKind.question => AiQuestionCard(
                      message: m,
                      latest: m.id == lastQuestion,
                    ),
                    AiMessageKind.result => AiResultCard(
                      message: m,
                      latest: m.id == lastResult,
                    ),
                    AiMessageKind.confirm => AiDecisionBubble(message: m),
                    AiMessageKind.error => AiErrorCard(
                      message: m,
                      onRetry: aiContent(m)['retryable'] == true
                          ? () => _retry(m)
                          : null,
                    ),
                    _ => AiTextBubble(message: m),
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _inputArea(BuildContext context) {
    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      key: const ValueKey('ai-chat-attach-photo-kind-receipt'),
                      label: const Text('Receipt'),
                      selected: _photoKind == AiJobKind.receipt,
                      onSelected: (_) =>
                          setState(() => _photoKind = AiJobKind.receipt),
                    ),
                    ChoiceChip(
                      key: const ValueKey(
                        'ai-chat-attach-photo-kind-screenshot',
                      ),
                      label: const Text('Bank screenshot'),
                      selected: _photoKind == AiJobKind.screenshot,
                      onSelected: (_) =>
                          setState(() => _photoKind = AiJobKind.screenshot),
                    ),
                  ],
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _attachButton(),
                    Expanded(
                      child: Focus(
                        // Enter sends, Shift+Enter inserts a new line.
                        onKeyEvent: (node, e) {
                          if (e is KeyDownEvent &&
                              (e.logicalKey == LogicalKeyboardKey.enter ||
                                  e.logicalKey ==
                                      LogicalKeyboardKey.numpadEnter) &&
                              !HardwareKeyboard.instance.isShiftPressed) {
                            _send();
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: TextField(
                          key: const ValueKey('ai-chat-input'),
                          controller: _input,
                          focusNode: _focus,
                          minLines: 1,
                          maxLines: 6,
                          keyboardType: TextInputType.multiline,
                          decoration: const InputDecoration(
                            hintText: 'Message, or paste a checklist',
                            isDense: true,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('ai-chat-send'),
                      tooltip: 'Send',
                      onPressed: _sending ? null : _send,
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _attachButton() {
    if (aiHasCamera) {
      return PopupMenuButton<AiPhotoSource>(
        key: const ValueKey('ai-chat-attach'),
        icon: const Icon(Icons.add_a_photo_outlined),
        tooltip: 'Attach a photo',
        enabled: !_sending,
        onSelected: _attach,
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: AiPhotoSource.camera,
            child: Text('Take a photo'),
          ),
          PopupMenuItem(
            value: AiPhotoSource.gallery,
            child: Text('From gallery'),
          ),
        ],
      );
    }
    return IconButton(
      key: const ValueKey('ai-chat-attach'),
      tooltip: 'Attach an image file',
      onPressed: _sending ? null : () => _attach(AiPhotoSource.file),
      icon: const Icon(Icons.attach_file),
    );
  }
}
