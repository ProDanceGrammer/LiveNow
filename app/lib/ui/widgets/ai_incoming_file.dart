import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai_providers.dart';
import '../ai_ui_providers.dart';
import '../dialog_stack.dart';
import '../screens/ai_chat_screen.dart';
import 'app_toast.dart';
import 'glass.dart';

/// A statement file arrived from another app (share sheet / "Open in"): asks
/// which chat gets it, then opens that chat with the file waiting in the
/// composer. A file is never sent without the user pressing Send there.
Future<void> showIncomingFilePicker(
  BuildContext context,
  WidgetRef ref,
  StatementPick file,
) async {
  final navigator = Navigator.of(context);
  final overlay = rootOverlayOf(context);
  final service = ref.read(aiChatServiceProvider);
  final choice = await showStackedDialog<String>(
    context: context,
    builder: (_) => _IncomingFileDialog(fileName: file.name),
  );
  if (choice == null) return;
  try {
    final id = choice == _newChat ? await service.createThread() : choice;
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => GlassPage(
          child: AiChatScreen(threadId: id, initialFile: file),
        ),
      ),
    );
  } catch (e) {
    showInfoToast(overlay, '$e');
  }
}

const _newChat = '\u0000new';

class _IncomingFileDialog extends ConsumerWidget {
  const _IncomingFileDialog({required this.fileName});

  final String fileName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threads = ref.watch(aiThreadsProvider).asData?.value ?? const [];
    return AlertDialog(
      key: const ValueKey('ai-incoming-dialog'),
      title: const Text('Send to chat'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(fileName, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            ListTile(
              key: const ValueKey('ai-incoming-new'),
              leading: const Icon(Icons.add_comment_outlined),
              title: const Text('New chat'),
              onTap: () => Navigator.of(context).pop(_newChat),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: threads.length,
                itemBuilder: (_, i) => ListTile(
                  key: ValueKey('ai-incoming-thread-$i'),
                  title: Text(
                    threads[i].title.isEmpty ? 'New chat' : threads[i].title,
                  ),
                  onTap: () => Navigator.of(context).pop(threads[i].id),
                ),
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
      ],
    );
  }
}
