import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/sync/http_transport.dart';
import '../data/sync/sync_peers.dart';
import 'sync_providers.dart';

/// Fetches messages older than [beforeCreatedAt] from the hub (the hub is the
/// chat archive; a phone keeps only a recent window). Returns them OLDEST FIRST.
typedef AiHistoryLoader =
    Future<List<AiMessage>> Function(String threadId, String beforeCreatedAt);

/// Fetches a photo original from the hub, or null when it has none by that id.
typedef AiBlobFetcher = Future<Uint8List?> Function(String blobId);

/// The server this device reads the assistant's archive from: the hub it is
/// paired with (the desktop window's hub, else the phone's paired PC).
Future<SyncPeer?> _archivePeer(Ref ref) async {
  final hub = await ref.read(hubAdminProvider).peer();
  if (hub != null) return hub;
  final all = await ref.read(syncPeersProvider).all();
  return all.isEmpty ? null : all.first;
}

/// Runs [body] over a short-lived transport to the archive server; null when
/// there is none, it is unreachable, or it has no assistant (an old hub / a
/// plain host): the caller then simply shows what the device has.
Future<T?> _withArchive<T>(
  Ref ref,
  Future<T> Function(HttpTransport t) body,
) async {
  final peer = await _archivePeer(ref);
  if (peer == null) return null;
  final t = await ref.read(syncTransportFactoryProvider)(peer);
  if (t is! HttpTransport) return null;
  try {
    return await body(t);
  } on AiUnavailable {
    return null;
  } on Object {
    return null; // unreachable / refused: the local window is all there is
  } finally {
    t.close();
  }
}

AiMessage _messageFromRow(Map<String, Object?> r) => AiMessage(
  id: (r['id'] ?? '').toString(),
  threadId: (r['thread_id'] ?? '').toString(),
  role: (r['role'] ?? 'user').toString(),
  kind: (r['kind'] ?? 'text').toString(),
  body: (r['body'] ?? '').toString(),
  contentJson: (r['content_json'] ?? '{}').toString(),
  jobId: r['job_id']?.toString(),
  createdAt: (r['created_at'] ?? '').toString(),
  updatedAt: (r['updated_at'] ?? '').toString(),
);

/// "Load older" reads from the hub (`/v1/ai/history`). Messages come back as sync
/// rows and are shown as they are (not written to this device's database: the
/// hub stays the archive).
final aiHistoryLoaderProvider = Provider<AiHistoryLoader>(
  (ref) => (threadId, beforeCreatedAt) async {
    final page = await _withArchive(
      ref,
      (t) => t.fetchAiHistory(threadId, before: beforeCreatedAt),
    );
    if (page == null) return const <AiMessage>[];
    return [for (final r in page.messages) _messageFromRow(r)];
  },
);

/// A photo original from the hub (`/v1/ai/blob`), for the tap on a placeholder.
final aiBlobFetcherProvider = Provider<AiBlobFetcher>(
  (ref) => (blobId) async {
    final r = await _withArchive(ref, (t) => t.fetchAiBlob(blobId));
    return r?.data;
  },
);
