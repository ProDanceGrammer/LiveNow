import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show OrderingTerm, Value, Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/ids.dart';
import 'package:livenow/core/time_codec.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/ai/ai_chat_service.dart';
import 'package:livenow/domain/ai/ai_protocol.dart';

import 'ai_test_support.dart';

void main() {
  late AppDatabase db;
  late AiChatService chat;
  late String thread;

  setUp(() async {
    db = memoryDb();
    chat = AiChatService(db);
    thread = await chat.createThread(title: 'Receipts');
  });

  tearDown(() => db.close());

  Future<List<AiJob>> jobs() => db.select(db.aiJobsTable).get();
  Future<List<AiMessage>> messages() => db.select(db.aiMessagesTable).get();

  Future<({String versions, int deleted})> versionOf(
    String table,
    String id,
  ) async {
    final r = await db
        .customSelect(
          'SELECT hlc, deleted FROM sync_versions WHERE tbl = ? AND row_id = ?',
          variables: [Variable.withString(table), Variable.withString(id)],
        )
        .getSingle();
    return (versions: r.read<String>('hlc'), deleted: r.read<int>('deleted'));
  }

  group('sendText', () {
    test('creates the message and a queued job together', () async {
      final r = await chat.sendText(thread, '  moved 100 to Monobank \u0000');
      final m = (await messages()).single;
      final j = (await jobs()).single;
      expect(r.answered, isFalse);
      expect(m.id, r.messageId);
      expect(m.body, 'moved 100 to Monobank');
      expect(m.role, AiRole.user);
      expect(m.jobId, j.id);
      expect(j.state, AiJobState.queued);
      expect(j.kind, AiJobKind.text);
      final p = JobPayload.decode(j.payloadJson);
      expect(p.messageId, m.id);
      expect(p.text, 'moved 100 to Monobank');
    });

    test('a checklist becomes a bazaar job', () async {
      await chat.sendText(thread, '- [x] Cherries 2 kg 300\n- [ ] Plums');
      expect((await jobs()).single.kind, AiJobKind.bazaar);
    });

    test('empty text is refused and writes nothing', () async {
      await expectLater(
        chat.sendText(thread, '  \u0001 '),
        throwsA(isA<AiChatException>()),
      );
      expect(await messages(), isEmpty);
      expect(await jobs(), isEmpty);
    });

    test('long text is capped', () async {
      await chat.sendText(thread, 'a' * 9000);
      expect((await messages()).single.body.length, kMaxChatTextLength);
    });

    test('answering a needs_input job creates no second job', () async {
      final first = await chat.sendText(thread, 'receipt please');
      final jobId = first.jobId!;
      final cardId = newId();
      final now = dateTimeToDb(DateTime.now())!;
      await (db.update(db.aiJobsTable)..where((t) => t.id.equals(jobId))).write(
        const AiJobsTableCompanion(state: Value(AiJobState.needsInput)),
      );
      await db
          .into(db.aiMessagesTable)
          .insert(
            AiMessagesTableCompanion.insert(
              id: cardId,
              threadId: thread,
              role: const Value(AiRole.assistant),
              kind: const Value(AiMessageKind.question),
              contentJson: Value(
                jsonEncode(
                  const QuestionCard([
                    Question(id: 'a', text: 'Which shop?'),
                    Question(id: 'b', text: 'Weight?'),
                  ]).toJson(),
                ),
              ),
              jobId: Value(jobId),
              createdAt: now,
              updatedAt: now,
            ),
          );

      final r = await chat.sendText(thread, '2. 500 g');
      expect(r.answered, isTrue);
      expect(r.jobId, jobId);
      expect(await jobs(), hasLength(1));
      // The app never changes the job state: the hub owns it.
      expect((await jobs()).single.state, AiJobState.needsInput);
      final reply = (await messages()).firstWhere((m) => m.id == r.messageId);
      expect(reply.jobId, jobId);
      var qs = QuestionCard.fromJson(
        jsonDecode(
          (await messages()).firstWhere((m) => m.id == cardId).contentJson,
        ),
      ).questions;
      expect(qs[0].answer, isNull);
      expect(qs[1].answer, '500 g');

      // Plain text answers the first unanswered question.
      await chat.sendText(thread, 'Migros');
      qs = QuestionCard.fromJson(
        jsonDecode(
          (await messages()).firstWhere((m) => m.id == cardId).contentJson,
        ),
      ).questions;
      expect(qs[0].answer, 'Migros');
      expect(await jobs(), hasLength(1));

      // Everything answered: new text is new work again.
      final third = await chat.sendText(thread, 'another one');
      expect(third.answered, isFalse);
      expect(await jobs(), hasLength(2));
    });

    test('a tapped option answers that question', () async {
      final first = await chat.sendText(thread, 'x');
      final cardId = newId();
      final now = dateTimeToDb(DateTime.now())!;
      await (db.update(
        db.aiJobsTable,
      )..where((t) => t.id.equals(first.jobId!))).write(
        const AiJobsTableCompanion(state: Value(AiJobState.needsInput)),
      );
      await db
          .into(db.aiMessagesTable)
          .insert(
            AiMessagesTableCompanion.insert(
              id: cardId,
              threadId: thread,
              kind: const Value(AiMessageKind.question),
              contentJson: Value(
                jsonEncode(
                  const QuestionCard([
                    Question(id: 'q1', text: 'Card?', options: ['A', 'B']),
                  ]).toJson(),
                ),
              ),
              jobId: Value(first.jobId),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await chat.answerQuestion(cardId, 'q1', 'B');
      final card = (await messages()).firstWhere((m) => m.id == cardId);
      expect(
        QuestionCard.fromJson(jsonDecode(card.contentJson))
            .questions
            .single
            .answer,
        'B',
      );
      expect(await jobs(), hasLength(1));
    });
  });

  group('sendPhoto', () {
    test('stores the bytes as base64 with a queued job', () async {
      final bytes = Uint8List.fromList(List.generate(300, (i) => i % 256));
      final r = await chat.sendPhoto(thread, bytes, width: 30, height: 10);
      final m = (await messages()).single;
      final blob = (await db.select(db.aiBlobsTable).get()).single;
      final j = (await jobs()).single;
      expect(m.kind, AiMessageKind.photo);
      expect(blob.data, base64.encode(bytes));
      expect(blob.sha256, hasLength(64));
      expect(blob.width, 30);
      expect(blob.messageId, m.id);
      expect(blob.storedOnHubAt, isNull);
      expect(j.state, AiJobState.queued);
      expect(j.kind, AiJobKind.receipt);
      expect(JobPayload.decode(j.payloadJson).blobIds, [blob.id]);
      expect(r.jobId, j.id);
    });

    test(
      'a screenshot photo makes a screenshot job; empty is refused',
      () async {
        await chat.sendPhoto(
          thread,
          Uint8List.fromList([1, 2, 3]),
          kind: AiJobKind.screenshot,
        );
        expect((await jobs()).single.kind, AiJobKind.screenshot);
        await expectLater(
          chat.sendPhoto(thread, Uint8List(0)),
          throwsA(isA<AiChatException>()),
        );
        expect(await jobs(), hasLength(1));
      },
    );
  });

  group('sendPhotos', () {
    ({Uint8List bytes, int? width, int? height}) photo(int marker) =>
        (bytes: Uint8List.fromList(List.filled(30, marker)), width: 30, height: 10);

    test('one message, one job and one blob per photo, in order', () async {
      final r = await chat.sendPhotos(thread, [photo(1), photo(2)], caption: 'BIM, card 6141');
      final m = (await messages()).single;
      final blobs = await (db.select(db.aiBlobsTable)
            ..orderBy([(t) => OrderingTerm(expression: t.id)]))
          .get();
      final j = (await jobs()).single;
      expect(m.kind, AiMessageKind.photo);
      expect(m.body, 'BIM, card 6141');
      expect(blobs, hasLength(2));
      expect(blobs.every((b) => b.messageId == m.id && b.data != null), isTrue);
      expect(j.kind, AiJobKind.photos);
      expect(j.state, AiJobState.queued);
      final payload = JobPayload.decode(j.payloadJson);
      expect(payload.blobIds.toSet(), blobs.map((b) => b.id).toSet());
      expect(
        [for (final id in payload.blobIds) base64Decode(blobs.firstWhere((b) => b.id == id).data!)[0]],
        [1, 2],
        reason: 'the photos keep the order they were added in',
      );
      expect(payload.text, 'BIM, card 6141');
      expect(r.jobId, j.id);
    });

    test('nothing, an empty photo, or too many photos are refused and write nothing', () async {
      await expectLater(chat.sendPhotos(thread, const []), throwsA(isA<AiChatException>()));
      await expectLater(
        chat.sendPhotos(thread, [(bytes: Uint8List(0), width: null, height: null)]),
        throwsA(isA<AiChatException>()),
      );
      await expectLater(
        chat.sendPhotos(thread, [for (var i = 0; i <= AiChatService.maxPhotosPerMessage; i++) photo(i)]),
        throwsA(isA<AiChatException>()),
      );
      expect(await jobs(), isEmpty);
      expect(await messages(), isEmpty);
    });

    test('up to the limit is accepted, and the total size is capped for the sync push', () async {
      await chat.sendPhotos(thread, [for (var i = 0; i < AiChatService.maxPhotosPerMessage; i++) photo(i)]);
      expect(await db.select(db.aiBlobsTable).get(), hasLength(AiChatService.maxPhotosPerMessage));
      final big = (bytes: Uint8List(5 * 1024 * 1024), width: 1, height: 1);
      await expectLater(
        chat.sendPhotos(thread, [big, big, big, big, big]),
        throwsA(isA<AiChatException>()),
      );
      expect(await jobs(), hasLength(1), reason: 'the refused message wrote nothing');
    });
  });

  group('confirm / reject', () {
    Future<String> draft(String jobId) async {
      final id = newId();
      final now = dateTimeToDb(DateTime.now())!;
      await db
          .into(db.aiMessagesTable)
          .insert(
            AiMessagesTableCompanion.insert(
              id: id,
              threadId: thread,
              role: const Value(AiRole.assistant),
              kind: const Value(AiMessageKind.draft),
              jobId: Value(jobId),
              createdAt: now,
              updatedAt: now,
            ),
          );
      return id;
    }

    test('confirm writes a decision message on the draft job', () async {
      final jobId = (await chat.sendText(thread, 'x')).jobId!;
      final d = await draft(jobId);
      final id = await chat.confirmDraft(
        d,
        edits: const [LineEdit(index: 1, quantity: 2)],
      );
      final m = (await messages()).firstWhere((m) => m.id == id);
      expect(m.kind, AiMessageKind.confirm);
      expect(m.jobId, jobId);
      final dec = ConfirmDecision.fromJson(jsonDecode(m.contentJson));
      expect(dec.confirm, isTrue);
      expect(dec.draftMessageId, d);
      expect(dec.edits.single.quantity, 2);
    });

    test('reject writes a reject decision; unknown draft is refused', () async {
      final jobId = (await chat.sendText(thread, 'x')).jobId!;
      final d = await draft(jobId);
      final id = await chat.rejectDraft(d);
      final m = (await messages()).firstWhere((m) => m.id == id);
      expect(
        ConfirmDecision.fromJson(jsonDecode(m.contentJson)).confirm,
        isFalse,
      );
      await expectLater(
        chat.confirmDraft('nope'),
        throwsA(isA<AiChatException>()),
      );
    });
  });

  group('reading', () {
    test('watchMessages gives the newest window oldest first', () async {
      for (var i = 0; i < 5; i++) {
        await chat.sendText(thread, 'm$i');
        await Future<void>.delayed(const Duration(milliseconds: 3));
      }
      final w = await chat.watchMessages(thread, limit: 3).first;
      expect(w.map((m) => m.body), ['m2', 'm3', 'm4']);
      final older = await chat.olderMessages(thread, w.first.createdAt);
      expect(older.map((m) => m.body), ['m0', 'm1']);
    });

    test('status message of a job is found', () async {
      final jobId = (await chat.sendText(thread, 'x')).jobId!;
      expect(await chat.statusMessageOf(jobId), isNull);
      final now = dateTimeToDb(DateTime.now())!;
      await db
          .into(db.aiMessagesTable)
          .insert(
            AiMessagesTableCompanion.insert(
              id: deriveId(jobId, 'status'),
              threadId: thread,
              role: const Value(AiRole.assistant),
              kind: const Value(AiMessageKind.status),
              jobId: Value(jobId),
              createdAt: now,
              updatedAt: now,
            ),
          );
      expect(
        (await chat.statusMessageOf(jobId))?.id,
        deriveId(jobId, 'status'),
      );
    });

    test('archived threads are hidden', () async {
      await chat.archiveThread(thread);
      expect(await chat.watchThreads().first, isEmpty);
      expect(
        await chat.watchThreads(includeArchived: true).first,
        hasLength(1),
      );
      await chat.renameThread(thread, 'Old');
    });
  });

  group('retention', () {
    Future<String> oldMessage({
      required int daysAgo,
      String? jobId,
      String kind = AiMessageKind.text,
    }) async {
      final id = newId();
      final at = dateTimeToDb(
        DateTime.now().subtract(Duration(days: daysAgo)),
      )!;
      await db
          .into(db.aiMessagesTable)
          .insert(
            AiMessagesTableCompanion.insert(
              id: id,
              threadId: thread,
              kind: Value(kind),
              jobId: Value(jobId),
              createdAt: at,
              updatedAt: at,
            ),
          );
      return id;
    }

    test(
      'pruneLocal removes old rows without a tombstone and keeps the window',
      () async {
        final oldA = await oldMessage(daysAgo: 60);
        final oldB = await oldMessage(daysAgo: 50);
        final recent = await oldMessage(daysAgo: 1);
        final vBefore = await versionOf('ai_messages', oldA);

        final removed = await chat.pruneLocal(keepDays: 30, keepMessages: 200);
        // All three are inside the 200-message window: nothing goes.
        expect(removed, 0);

        final removed2 = await chat.pruneLocal(keepDays: 30, keepMessages: 1);
        expect(removed2, 2);
        final left = (await messages()).map((m) => m.id).toList();
        expect(left, [recent]);
        expect(left, isNot(contains(oldA)));
        expect(left, isNot(contains(oldB)));

        // No tombstone, no new stamp: the hub's copy is not deleted.
        final vAfter = await versionOf('ai_messages', oldA);
        expect(vAfter.deleted, 0);
        expect(vAfter.versions, vBefore.versions);
        expect((await versionOf('ai_messages', oldB)).deleted, 0);
        // The silent switch is back off: a normal delete DOES tombstone.
        await db.customStatement('DELETE FROM ai_messages WHERE id = ?', [
          recent,
        ]);
        expect((await versionOf('ai_messages', recent)).deleted, 1);
      },
    );

    test('pruneLocal keeps messages of jobs that are still active', () async {
      final jobId = (await chat.sendText(thread, 'live')).jobId!;
      final old = await oldMessage(daysAgo: 90, jobId: jobId);
      await chat.pruneLocal(keepDays: 30, keepMessages: 0);
      expect((await messages()).map((m) => m.id), contains(old));
    });

    test(
      'pruneLocal drops finished old jobs and confirmed old photos',
      () async {
        final jobId = newId();
        final at = dateTimeToDb(
          DateTime.now().subtract(const Duration(days: 60)),
        )!;
        await db
            .into(db.aiJobsTable)
            .insert(
              AiJobsTableCompanion.insert(
                id: jobId,
                threadId: thread,
                state: const Value(AiJobState.done),
                createdAt: at,
                updatedAt: at,
              ),
            );
        for (final (id, stored) in [('b1', true), ('b2', false)]) {
          await db
              .into(db.aiBlobsTable)
              .insert(
                AiBlobsTableCompanion.insert(
                  id: id,
                  data: const Value('QQ=='),
                  storedOnHubAt: Value(stored ? at : null),
                  createdAt: at,
                  updatedAt: at,
                ),
              );
        }
        await chat.pruneLocal(keepDays: 30, keepMessages: 200);
        expect(await jobs(), isEmpty);
        // The unconfirmed photo stays: the hub does not have it yet.
        expect((await db.select(db.aiBlobsTable).get()).map((b) => b.id), [
          'b2',
        ]);
        expect((await versionOf('ai_jobs', jobId)).deleted, 0);
      },
    );

    test(
      'clearBlobData frees the bytes only after the hub confirmed, silently',
      () async {
        final r = await chat.sendPhoto(thread, Uint8List.fromList([9, 9, 9]));
        final blob = (await db.select(db.aiBlobsTable).get()).single;
        expect(await chat.clearBlobData(blob.id), isFalse);
        expect((await db.select(db.aiBlobsTable).get()).single.data, isNotNull);

        await db.customStatement(
          'UPDATE ai_blobs SET stored_on_hub_at = ? WHERE id = ?',
          [dateTimeToDb(DateTime.now()), blob.id],
        );
        final stamp = (await versionOf('ai_blobs', blob.id)).versions;
        expect(await chat.clearBlobData(blob.id), isTrue);
        final after = (await db.select(db.aiBlobsTable).get()).single;
        expect(after.data, isNull);
        expect(after.sha256, blob.sha256);
        expect((await versionOf('ai_blobs', blob.id)).versions, stamp);
        expect(r.jobId, isNotNull);
      },
    );
  });
}
