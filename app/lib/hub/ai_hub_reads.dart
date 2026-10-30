import 'dart:convert';

import 'package:drift/drift.dart';

import '../data/database.dart';
import '../data/sync/sync_schema.dart';
import '../data/sync/sync_server.dart';
import 'ai_photo_store.dart';

/// The hub's answers to `/v1/ai/history` and `/v1/ai/blob`: the chat archive
/// from its database and the photo originals from its [AiPhotoStore].
class AiHubReads implements AiReadHandler {
  AiHubReads({required this.db, required this.photos});

  final AppDatabase db;
  final AiPhotoStore photos;

  /// A page of one thread's messages older than [before] (a `created_at`
  /// cursor; null = from the newest), as sync rows, oldest first within the
  /// page. [more] says there are older ones still.
  @override
  Future<Map<String, Object?>> history(
    String threadId,
    String? before,
    int limit,
  ) async {
    final cols = await syncedColumns(db, 'ai_messages');
    final rows = await db
        .customSelect(
          'SELECT ${cols.join(', ')} FROM ai_messages WHERE thread_id = ? '
          '${before == null ? '' : 'AND created_at < ? '}'
          'ORDER BY created_at DESC, id DESC LIMIT ?',
          variables: [
            Variable.withString(threadId),
            if (before != null) Variable.withString(before),
            Variable.withInt(limit + 1),
          ],
        )
        .get();
    final page = rows.take(limit).toList().reversed;
    return {
      'messages': [
        for (final r in page) {for (final c in cols) c: r.data[c]},
      ],
      'more': rows.length > limit,
    };
  }

  /// One photo, or `{error: not_found}`.
  @override
  Future<Map<String, Object?>> blob(String blobId) async {
    final p = await photos.read(blobId);
    if (p == null) return {'error': 'not_found'};
    return {'mime': p.mime, 'data': base64.encode(p.data)};
  }
}
