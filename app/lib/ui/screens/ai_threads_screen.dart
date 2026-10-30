import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../ai_providers.dart';
import '../ai_ui_providers.dart';
import '../dialog_stack.dart';
import '../time_format.dart' show formatDateTime, wallFromUtc;
import '../../core/time_codec.dart';
import '../widgets/app_toast.dart';
import 'ai_chat_screen.dart';
import 'settings_screen.dart';

/// The "connect a hub" state shown instead of the assistant on a device that is
/// not paired with a hub.
class AiHubRequired extends StatelessWidget {
  const AiHubRequired({super.key});

  @override
  Widget build(BuildContext context) => Center(
    key: const ValueKey('ai-hub-required'),
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.hub_outlined, size: 48),
          const SizedBox(height: 12),
          const Text(
            'Connect a hub in Settings to use the assistant',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const ValueKey('ai-hub-required-settings'),
            onPressed: () => SettingsScreen.open(context),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    ),
  );
}

/// The list of chats: open, create, rename, archive.
class AiThreadsScreen extends ConsumerWidget {
  const AiThreadsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const AiThreadsScreen()),
  );

  Future<void> _newThread(BuildContext context, WidgetRef ref) async {
    final overlay = rootOverlayOf(context);
    final navigator = Navigator.of(context);
    try {
      final id = await ref.read(aiChatServiceProvider).createThread();
      navigator.push(
        MaterialPageRoute<void>(builder: (_) => AiChatScreen(threadId: id)),
      );
    } catch (e) {
      showInfoToast(overlay, '$e');
    }
  }

  Future<void> _rename(BuildContext context, WidgetRef ref, AiThread t) async {
    final service = ref.read(aiChatServiceProvider);
    final c = TextEditingController(text: t.title);
    final title = await showStackedDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename chat'),
        content: TextField(
          key: const ValueKey('ai-thread-title'),
          controller: c,
          autofocus: true,
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('ai-thread-title-save'),
            onPressed: () => Navigator.of(ctx).pop(c.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    c.dispose();
    if (title != null) await service.renameThread(t.id, title);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = ref.watch(aiHubReadyProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Assistant')),
      floatingActionButton: ready
          ? FloatingActionButton(
              key: const ValueKey('ai-new-thread'),
              heroTag: null,
              tooltip: 'New chat',
              onPressed: () => _newThread(context, ref),
              child: const Icon(Icons.add_comment_outlined),
            )
          : null,
      body: !ready
          ? const AiHubRequired()
          : ref
                .watch(aiThreadsProvider)
                .when(
                  loading: () => const SizedBox.shrink(),
                  error: (e, _) => Center(child: Text('$e')),
                  data: (threads) => threads.isEmpty
                      ? const Center(
                          key: ValueKey('ai-threads-empty'),
                          child: Text('No chats yet. Tap + to start one.'),
                        )
                      : ListView.builder(
                          key: const ValueKey('ai-threads-list'),
                          itemCount: threads.length,
                          itemBuilder: (_, i) {
                            final t = threads[i];
                            return ListTile(
                              key: ValueKey('ai-thread-${t.id}'),
                              title: Text(t.title.isEmpty ? 'New chat' : t.title),
                              subtitle: Text(
                                formatDateTime(wallFromUtc(dateTimeFromDb(t.updatedAt)!)),
                              ),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => AiChatScreen(threadId: t.id),
                                ),
                              ),
                              trailing: PopupMenuButton<String>(
                                key: ValueKey('ai-thread-menu-${t.id}'),
                                onSelected: (v) {
                                  if (v == 'rename') _rename(context, ref, t);
                                  if (v == 'archive') {
                                    ref
                                        .read(aiChatServiceProvider)
                                        .archiveThread(t.id);
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'rename',
                                    child: Text('Rename'),
                                  ),
                                  PopupMenuItem(
                                    value: 'archive',
                                    child: Text('Archive'),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}
