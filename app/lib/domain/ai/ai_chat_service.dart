import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';

import '../../core/ids.dart';
import '../../core/text_rules.dart';
import '../../core/time_codec.dart';
import '../../data/database.dart';
import 'ai_protocol.dart';

/// Longest chat message, in characters.
const kMaxChatTextLength = 8000;

/// The message or photo was refused (empty, too big, unknown draft).
class AiChatException implements Exception {
  const AiChatException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// What [AiChatService.sendText] / [AiChatService.sendPhoto] did.
class SentText {
  const SentText({required this.messageId, this.jobId, this.answered = false});

  final String messageId;

  /// The job the message started, or (for an answer) the job it answers.
  final String? jobId;

  /// True when the text was written into a waiting question card and no new
  /// job was created.
  final bool answered;
}

/// The APP side of the assistant outbox (phone or desktop window): it only
/// writes rows - user messages, jobs, photos, answers, decisions - which sync
/// carries to the hub. The hub's worker owns the job STATE: the app never
/// changes `ai_jobs.state` (a stale write from a phone must not overwrite the
/// hub's progress); the hub reacts to the rows written here.
class AiChatService {
  AiChatService(this.db);

  final AppDatabase db;

  /// Largest photo (already resized JPEG) accepted by [sendPhoto].
  static const maxPhotoBytes = 6 * 1024 * 1024;

  // ---- threads --------------------------------------------------------------

  Future<String> createThread({String title = ''}) async {
    final id = newId();
    final now = dateTimeToDb(DateTime.now())!;
    await db
        .into(db.aiThreadsTable)
        .insert(
          AiThreadsTableCompanion.insert(
            id: id,
            title: Value(cleanName(title, what: 'chat title')),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  Future<void> renameThread(String id, String title) =>
      (db.update(db.aiThreadsTable)..where((t) => t.id.equals(id))).write(
        AiThreadsTableCompanion(
          title: Value(cleanName(title, what: 'chat title')),
          updatedAt: Value(dateTimeToDb(DateTime.now())!),
        ),
      );

  Future<void> archiveThread(String id, {bool archived = true}) =>
      (db.update(db.aiThreadsTable)..where((t) => t.id.equals(id))).write(
        AiThreadsTableCompanion(
          archived: Value(archived),
          updatedAt: Value(dateTimeToDb(DateTime.now())!),
        ),
      );

  /// Threads, most recently active first.
  Stream<List<AiThread>> watchThreads({bool includeArchived = false}) {
    final q = db.select(db.aiThreadsTable);
    if (!includeArchived) q.where((t) => t.archived.equals(false));
    q.orderBy([(t) => OrderingTerm.desc(t.updatedAt)]);
    return q.watch();
  }

  // ---- reading --------------------------------------------------------------

  /// The newest [limit] messages of a thread, OLDEST FIRST (ready to show).
  /// Older ones: [olderMessages].
  Stream<List<AiMessage>> watchMessages(String threadId, {int limit = 100}) =>
      (db.select(db.aiMessagesTable)
            ..where((t) => t.threadId.equals(threadId))
            ..orderBy([
              (t) => OrderingTerm.desc(t.createdAt),
              (t) => OrderingTerm.desc(t.id),
            ])
            ..limit(limit))
          .watch()
          .map((rows) => rows.reversed.toList());

  /// "Load older": up to [limit] messages created before [beforeCreatedAt]
  /// (the createdAt text of the oldest message shown), oldest first.
  Future<List<AiMessage>> olderMessages(
    String threadId,
    String beforeCreatedAt, {
    int limit = 100,
  }) async {
    final rows =
        await (db.select(db.aiMessagesTable)
              ..where(
                (t) =>
                    t.threadId.equals(threadId) &
                    t.createdAt.isSmallerThanValue(beforeCreatedAt),
              )
              ..orderBy([
                (t) => OrderingTerm.desc(t.createdAt),
                (t) => OrderingTerm.desc(t.id),
              ])
              ..limit(limit))
            .get();
    return rows.reversed.toList();
  }

  Stream<AiJob?> watchJob(String jobId) => (db.select(
    db.aiJobsTable,
  )..where((t) => t.id.equals(jobId))).watchSingleOrNull();

  /// The live status line of a job (written by the hub, one row updated in
  /// place), or null before the hub wrote it.
  Future<AiMessage?> statusMessageOf(String jobId) =>
      (db.select(db.aiMessagesTable)
            ..where(
              (t) =>
                  t.jobId.equals(jobId) & t.kind.equals(AiMessageKind.status),
            )
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
            ..limit(1))
          .getSingleOrNull();

  // ---- sending --------------------------------------------------------------

  /// Sends a typed line. ONE transaction. Three cases:
  ///  * the thread has a job waiting in `needs_input` with an unanswered
  ///    question: the text is an ANSWER. A user message linked to that job is
  ///    inserted and the answer is written into the question card's
  ///    `content_json` (no new job). `1. x` / `2) y` lines answer questions by
  ///    number; any other text answers the first unanswered question. The hub
  ///    notices the answered card and resumes.
  ///  * a bazaar checklist (`- [x]` / `- [ ]` lines): new job of kind `bazaar`;
  ///  * anything else: new job of kind `text`.
  Future<SentText> sendText(String threadId, String text) async {
    final clean = _cleanText(text);
    if (clean.isEmpty) throw const AiChatException('Type something first.');
    return db.transaction(() async {
      final now = dateTimeToDb(DateTime.now())!;
      final messageId = newId();

      final waiting = await _waitingQuestion(threadId);
      if (waiting != null) {
        await _insertUserMessage(
          messageId,
          threadId,
          AiMessageKind.text,
          clean,
          waiting.job.id,
          now,
        );
        await _writeAnswer(waiting.card, clean, now);
        await _touchThread(threadId, now);
        return SentText(
          messageId: messageId,
          jobId: waiting.job.id,
          answered: true,
        );
      }

      final jobId = newId();
      await _insertUserMessage(
        messageId,
        threadId,
        AiMessageKind.text,
        clean,
        jobId,
        now,
      );
      await _insertJob(
        jobId,
        threadId,
        looksLikeBazaarNote(clean) ? AiJobKind.bazaar : AiJobKind.text,
        JobPayload(messageId: messageId, text: clean),
        now,
      );
      await _touchThread(threadId, now);
      return SentText(messageId: messageId, jobId: jobId);
    });
  }

  /// Answers one question of a card by a tapped option (a quick-reply chip).
  /// Same effect as typing, but addressed to a known question.
  Future<void> answerQuestion(
    String questionMessageId,
    String questionId,
    String answer,
  ) {
    final clean = _cleanText(answer);
    if (clean.isEmpty) return Future.value();
    return db.transaction(() async {
      final card = await (db.select(
        db.aiMessagesTable,
      )..where((t) => t.id.equals(questionMessageId))).getSingleOrNull();
      if (card == null || card.kind != AiMessageKind.question) return;
      final now = dateTimeToDb(DateTime.now())!;
      final qs = _decodeCard(card);
      final i = qs.indexWhere((x) => x.id == questionId);
      if (i < 0) return;
      qs[i] = _withAnswer(qs[i], clean);
      await _saveCard(card, qs, now);
      await _insertUserMessage(
        newId(),
        card.threadId,
        AiMessageKind.text,
        clean,
        card.jobId,
        now,
      );
      await _touchThread(card.threadId, now);
    });
  }

  /// Sends a photo: the message, the image (base64 in `ai_blobs`) and a queued
  /// job of kind receipt / screenshot, in ONE transaction. [jpegBytes] should
  /// come from `prepareReceiptPhoto`.
  Future<SentText> sendPhoto(
    String threadId,
    Uint8List jpegBytes, {
    String kind = AiJobKind.receipt,
    int? width,
    int? height,
    String caption = '',
  }) async {
    if (jpegBytes.isEmpty) throw const AiChatException('The photo is empty.');
    if (jpegBytes.length > maxPhotoBytes) {
      throw const AiChatException('The photo is too large to send.');
    }
    if (kind != AiJobKind.receipt && kind != AiJobKind.screenshot) {
      throw const AiChatException('A photo is a receipt or a screenshot.');
    }
    final hash = await Sha256().hash(jpegBytes);
    final digest = hash.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final data = base64.encode(jpegBytes);
    return db.transaction(() async {
      final now = dateTimeToDb(DateTime.now())!;
      final messageId = newId();
      final jobId = newId();
      final blobId = newId();
      await _insertUserMessage(
        messageId,
        threadId,
        AiMessageKind.photo,
        _cleanText(caption),
        jobId,
        now,
        contentJson: jsonEncode({'v': 1, 'blob_id': blobId, 'kind': kind}),
      );
      await db
          .into(db.aiBlobsTable)
          .insert(
            AiBlobsTableCompanion.insert(
              id: blobId,
              messageId: Value(messageId),
              jobId: Value(jobId),
              kind: Value(kind),
              data: Value(data),
              sha256: Value(digest),
              width: Value(width),
              height: Value(height),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _insertJob(
        jobId,
        threadId,
        kind,
        JobPayload(messageId: messageId, blobIds: [blobId]),
        now,
      );
      await _touchThread(threadId, now);
      return SentText(messageId: messageId, jobId: jobId);
    });
  }

  /// The user taps Confirm on a draft (optionally with line [edits]): a
  /// `confirm` message linked to the draft's job. The hub commits the batch.
  Future<String> confirmDraft(
    String draftMessageId, {
    List<LineEdit> edits = const [],
  }) => _decide(draftMessageId, true, edits);

  /// The user taps Reject: the hub drops the draft and writes nothing.
  Future<String> rejectDraft(String draftMessageId) =>
      _decide(draftMessageId, false, const []);

  Future<String> _decide(
    String draftMessageId,
    bool confirm,
    List<LineEdit> edits,
  ) {
    return db.transaction(() async {
      final draft = await (db.select(
        db.aiMessagesTable,
      )..where((t) => t.id.equals(draftMessageId))).getSingleOrNull();
      if (draft == null || draft.kind != AiMessageKind.draft) {
        throw const AiChatException('That draft no longer exists.');
      }
      final now = dateTimeToDb(DateTime.now())!;
      final id = newId();
      await _insertUserMessage(
        id,
        draft.threadId,
        AiMessageKind.confirm,
        confirm ? 'Confirm' : 'Reject',
        draft.jobId,
        now,
        contentJson: jsonEncode(
          ConfirmDecision(
            draftMessageId: draftMessageId,
            confirm: confirm,
            edits: edits,
          ).toJson(),
        ),
      );
      await _touchThread(draft.threadId, now);
      return id;
    });
  }

  // ---- retention (phone) ----------------------------------------------------

  /// Keeps this device's copy of the chat small WITHOUT telling anyone. The
  /// triggers are silenced with the `sync_applying` switch (the one the merge
  /// engine uses), so the deletes create no tombstone and no new
  /// `sync_versions` stamp. The existing `sync_versions` rows are LEFT as they
  /// are (deleted = 0): `changesSince` skips a version whose row is missing, so
  /// nothing is sent, the hub's copy stays, and if the hub later changes such a
  /// row the merge re-creates it here as a cache entry (the kept stamp is what
  /// the merge compares against). Removing the version rows would only lose that.
  ///
  /// Removed: messages older than [keepDays] that are not among the newest
  /// [keepMessages] and whose job is not still active or waiting; finished jobs
  /// older than [keepDays]; photo rows older than [keepDays] that the hub
  /// confirmed (`stored_on_hub_at`), and the photos of removed messages.
  /// Returns the number of messages removed.
  Future<int> pruneLocal({int keepDays = 30, int keepMessages = 200}) async {
    final cutoff = dateTimeToDb(
      DateTime.now().subtract(Duration(days: keepDays)),
    )!;
    var removed = 0;
    await _silently(() async {
      final newest = await db
          .customSelect(
            'SELECT id FROM ai_messages ORDER BY created_at DESC, id DESC '
            'LIMIT ?',
            variables: [Variable.withInt(keepMessages)],
          )
          .get();
      final keep = {for (final r in newest) r.read<String>('id')};
      final old = await db
          .customSelect(
            'SELECT m.id AS id FROM ai_messages m WHERE m.created_at < ? '
            'AND NOT EXISTS (SELECT 1 FROM ai_jobs j WHERE j.id = m.job_id '
            "AND j.state NOT IN ('done', 'failed'))",
            variables: [Variable.withString(cutoff)],
          )
          .get();
      final drop = [
        for (final r in old)
          if (!keep.contains(r.read<String>('id'))) r.read<String>('id'),
      ];
      for (var i = 0; i < drop.length; i += 400) {
        final end = i + 400 > drop.length ? drop.length : i + 400;
        final part = drop.sublist(i, end);
        final marks = List.filled(part.length, '?').join(',');
        final vars = [for (final id in part) Variable.withString(id)];
        await db.customUpdate(
          'DELETE FROM ai_blobs WHERE message_id IN ($marks)',
          variables: vars,
        );
        removed += await db.customUpdate(
          'DELETE FROM ai_messages WHERE id IN ($marks)',
          variables: vars,
        );
      }
      await db.customUpdate(
        "DELETE FROM ai_jobs WHERE state IN ('done', 'failed') "
        'AND updated_at < ?',
        variables: [Variable.withString(cutoff)],
      );
      await db.customUpdate(
        'DELETE FROM ai_blobs WHERE stored_on_hub_at IS NOT NULL '
        'AND created_at < ?',
        variables: [Variable.withString(cutoff)],
      );
    });
    db.notifyUpdates({
      TableUpdate.onTable(db.aiMessagesTable, kind: UpdateKind.delete),
      TableUpdate.onTable(db.aiJobsTable, kind: UpdateKind.delete),
      TableUpdate.onTable(db.aiBlobsTable, kind: UpdateKind.delete),
    });
    return removed;
  }

  /// After the hub confirmed it stored the photo (`stored_on_hub_at` set):
  /// frees the bytes on THIS device without stamping a change (no sync).
  /// Does nothing while the hub has not confirmed. Returns true if cleared.
  Future<bool> clearBlobData(String blobId) async {
    var cleared = false;
    await _silently(() async {
      final n = await db.customUpdate(
        'UPDATE ai_blobs SET data = NULL WHERE id = ? '
        'AND stored_on_hub_at IS NOT NULL AND data IS NOT NULL',
        variables: [Variable.withString(blobId)],
        updates: {db.aiBlobsTable},
        updateKind: UpdateKind.update,
      );
      cleared = n > 0;
    });
    return cleared;
  }

  // ---- internals ------------------------------------------------------------

  /// Runs [body] with the sync triggers silenced (same switch the merge uses).
  Future<void> _silently(Future<void> Function() body) async {
    await db.transaction(() async {
      await db.customStatement('UPDATE sync_applying SET flag = 1');
      try {
        await body();
      } finally {
        await db.customStatement('UPDATE sync_applying SET flag = 0');
      }
    });
  }

  static String _cleanText(String raw) {
    var s = stripUnsafeText(raw).trim();
    if (s.length > kMaxChatTextLength) {
      s = s.substring(0, kMaxChatTextLength);
      // Do not leave half of a surrogate pair at the cut.
      final last = s.codeUnitAt(s.length - 1);
      if (last >= 0xD800 && last <= 0xDBFF) s = s.substring(0, s.length - 1);
    }
    return s;
  }

  /// A checklist pasted from the bazaar notes: at least one `- [x]` / `- [ ]`
  /// line.
  static bool looksLikeBazaarNote(String text) =>
      RegExp(r'^\s*[-*]\s*\[[ xX]\]', multiLine: true).hasMatch(text);

  Future<void> _insertUserMessage(
    String id,
    String threadId,
    String kind,
    String body,
    String? jobId,
    String now, {
    String contentJson = '{}',
  }) => db
      .into(db.aiMessagesTable)
      .insert(
        AiMessagesTableCompanion.insert(
          id: id,
          threadId: threadId,
          role: const Value(AiRole.user),
          kind: Value(kind),
          body: Value(body),
          contentJson: Value(contentJson),
          jobId: Value(jobId),
          createdAt: now,
          updatedAt: now,
        ),
      );

  Future<void> _insertJob(
    String id,
    String threadId,
    String kind,
    JobPayload payload,
    String now,
  ) => db
      .into(db.aiJobsTable)
      .insert(
        AiJobsTableCompanion.insert(
          id: id,
          threadId: threadId,
          kind: Value(kind),
          state: const Value(AiJobState.queued),
          stage: const Value(AiStage.queued),
          payloadJson: Value(payload.encode()),
          createdAt: now,
          updatedAt: now,
        ),
      );

  Future<void> _touchThread(String threadId, String now) =>
      (db.update(db.aiThreadsTable)..where((t) => t.id.equals(threadId))).write(
        AiThreadsTableCompanion(updatedAt: Value(now)),
      );

  /// The newest job of the thread in `needs_input` that has a question card
  /// with at least one unanswered question.
  Future<({AiJob job, AiMessage card})?> _waitingQuestion(
    String threadId,
  ) async {
    final jobs =
        await (db.select(db.aiJobsTable)
              ..where(
                (t) =>
                    t.threadId.equals(threadId) &
                    t.state.equals(AiJobState.needsInput),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
            .get();
    for (final job in jobs) {
      final card =
          await (db.select(db.aiMessagesTable)
                ..where(
                  (t) =>
                      t.jobId.equals(job.id) &
                      t.kind.equals(AiMessageKind.question),
                )
                ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
                ..limit(1))
              .getSingleOrNull();
      if (card != null && _decodeCard(card).any((q) => q.answer == null)) {
        return (job: job, card: card);
      }
    }
    return null;
  }

  List<Question> _decodeCard(AiMessage card) {
    try {
      final j = jsonDecode(card.contentJson);
      if (j is Map) {
        return QuestionCard.fromJson(Map<String, dynamic>.from(j)).questions;
      }
    } catch (_) {}
    return [];
  }

  Future<void> _saveCard(AiMessage card, List<Question> qs, String now) =>
      (db.update(db.aiMessagesTable)..where((t) => t.id.equals(card.id))).write(
        AiMessagesTableCompanion(
          contentJson: Value(jsonEncode(QuestionCard(qs).toJson())),
          updatedAt: Value(now),
        ),
      );

  Future<void> _writeAnswer(AiMessage card, String text, String now) async {
    final qs = _decodeCard(card);
    final numbered = RegExp(r'^\s*(\d{1,2})\s*[.):]\s*(.+)$', multiLine: true);
    var matched = false;
    for (final m in numbered.allMatches(text)) {
      final i = int.parse(m.group(1)!) - 1;
      if (i >= 0 && i < qs.length && qs[i].answer == null) {
        qs[i] = _withAnswer(qs[i], m.group(2)!.trim());
        matched = true;
      }
    }
    if (!matched) {
      final i = qs.indexWhere((q) => q.answer == null);
      if (i >= 0) qs[i] = _withAnswer(qs[i], text);
    }
    await _saveCard(card, qs, now);
  }

  Question _withAnswer(Question q, String a) => Question(
    id: q.id,
    text: q.text,
    options: q.options,
    recommended: q.recommended,
    answer: a,
  );
}
