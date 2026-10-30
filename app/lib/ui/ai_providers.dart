import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../domain/ai/ai_batch_service.dart';
import '../domain/ai/ai_chat_service.dart';
import '../domain/ai/ai_settings_store.dart';
import 'providers.dart';

final aiChatServiceProvider = Provider<AiChatService>(
  (ref) => AiChatService(ref.watch(databaseProvider)),
);

final aiBatchServiceProvider = Provider<AiBatchService>(
  (ref) => AiBatchService(ref.watch(databaseProvider)),
);

final aiSettingsStoreProvider = Provider<AiSettingsStore>(
  (ref) => AiSettingsStore(ref.watch(databaseProvider)),
);

/// Chats, most recently active first (archived ones are hidden).
final aiThreadsProvider = StreamProvider.autoDispose<List<AiThread>>(
  (ref) => ref.watch(aiChatServiceProvider).watchThreads(),
);

/// The newest messages of a thread, oldest first. Older ones are fetched with
/// `AiChatService.olderMessages`.
final aiMessagesProvider = StreamProvider.autoDispose
    .family<List<AiMessage>, String>(
      (ref, threadId) =>
          ref.watch(aiChatServiceProvider).watchMessages(threadId),
    );

final aiJobProvider = StreamProvider.autoDispose.family<AiJob?, String>(
  (ref, jobId) => ref.watch(aiChatServiceProvider).watchJob(jobId),
);
