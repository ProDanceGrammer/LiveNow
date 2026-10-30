import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/ai/ai_protocol.dart';
import 'package:livenow/domain/ai/ai_settings_store.dart';
import 'package:livenow/hub/ai_photo_store.dart';
import 'package:livenow/hub/ai_worker.dart';

const _now = '2026-10-30T10:00:00.000000Z';

void main() {
  late AppDatabase db;
  late Directory dir;
  late AiPhotoStore photos;
  late AiWorker worker;
  var calls = <String>[]; // llm model seen by each runNext call

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dir = await Directory.systemTemp.createTemp('ai_worker_test');
    photos = AiPhotoStore(Directory('${dir.path}/photos'));
    calls = [];
  });

  tearDown(() async {
    await worker.stop();
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<void> addJob(String id, {String state = AiJobState.queued}) =>
      db.into(db.aiJobsTable).insert(
        AiJobsTableCompanion.insert(
          id: id,
          threadId: 't1',
          state: Value(state),
          createdAt: _now,
          updatedAt: _now,
        ),
      );

  Future<String> stateOf(String id) async =>
      (await (db.select(db.aiJobsTable)..where((t) => t.id.equals(id)))
              .getSingle())
          .state;

  /// A runner that finishes the oldest queued job.
  AiRunStep fakeStep(AiSettingsSnapshot s) => () async {
    calls.add(s.llmModel);
    final job =
        await (db.select(db.aiJobsTable)
              ..where((t) => t.state.equals(AiJobState.queued))
              ..limit(1))
            .getSingleOrNull();
    if (job == null) return false;
    await (db.update(db.aiJobsTable)..where((t) => t.id.equals(job.id))).write(
      const AiJobsTableCompanion(state: Value(AiJobState.done)),
    );
    return true;
  };

  AiWorker make({AiRunnerFactory? factory}) => worker = AiWorker(
    db: db,
    photos: photos,
    runnerFactory: factory ?? fakeStep,
    debounce: const Duration(milliseconds: 10),
    safetyInterval: const Duration(milliseconds: 300),
    backoffBase: const Duration(milliseconds: 50),
    mergePoll: const Duration(milliseconds: 20),
  );

  Future<void> eventually(Future<bool> Function() ok) async {
    for (var i = 0; i < 200; i++) {
      if (await ok()) return;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    fail('condition not reached in time');
  }

  Future<void> setMerge(bool on) =>
      db.customStatement('UPDATE sync_applying SET flag = ${on ? 1 : 0}');

  test('runs a job that arrives while the worker is running', () async {
    make();
    await worker.start();
    await addJob('j1');
    await eventually(() async => await stateOf('j1') == AiJobState.done);
  });

  test('does nothing, builds nothing when there are no jobs', () async {
    make();
    await worker.start();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(calls, isEmpty);
  });

  test('waits while a sync merge is running, then runs the job', () async {
    await setMerge(true);
    await addJob('j1');
    make();
    await worker.start();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(await stateOf('j1'), AiJobState.queued);
    expect(calls, isEmpty);
    await setMerge(false);
    await eventually(() async => await stateOf('j1') == AiJobState.done);
  });

  test('recovers a job a crash left in running or committing', () async {
    await addJob('a', state: AiJobState.running);
    await addJob('b', state: AiJobState.committing);
    await addJob('c', state: AiJobState.draftReady);
    make();
    await worker.start();
    await eventually(() async => await stateOf('a') == AiJobState.done);
    await eventually(() async => await stateOf('b') == AiJobState.done);
    expect(await stateOf('c'), AiJobState.draftReady);
  });

  test('survives a throwing runner and tries again after a back-off', () async {
    var failures = 0;
    make(
      factory: (s) {
        final real = fakeStep(s);
        return () async {
          if (failures < 2) {
            failures++;
            throw StateError('boom');
          }
          return real();
        };
      },
    );
    await addJob('j1');
    await worker.start();
    await eventually(() async => await stateOf('j1') == AiJobState.done);
    expect(failures, 2);
  });

  test('a changed setting is used by the next job without a restart', () async {
    final store = AiSettingsStore(db);
    await store.set(AiSettingKey.llmModel, 'small');
    make();
    await worker.start();
    await addJob('j1');
    await eventually(() async => await stateOf('j1') == AiJobState.done);
    await store.set(AiSettingKey.llmModel, 'bigger');
    await addJob('j2');
    await eventually(() async => await stateOf('j2') == AiJobState.done);
    expect(calls, contains('small'));
    expect(calls.last, 'bigger');
  });

  test('purges photos older than the retention days', () async {
    final id = '11111111-2222-3333-4444-555555555555';
    await photos.save(id, Uint8List.fromList([1, 2, 3]), 'image/jpeg');
    final file = File('${photos.root.path}/$id.jpg');
    await file.setLastModified(DateTime.now().subtract(const Duration(days: 100)));
    await AiSettingsStore(db).set(AiSettingKey.photoRetentionDays, '90');
    make();
    expect(await worker.purgeOldPhotos(), 1);
    expect(await photos.exists(id), isFalse);

    await photos.save(id, Uint8List.fromList([1]), 'image/jpeg');
    expect(await worker.purgeOldPhotos(), 0); // fresh: kept
    expect(await photos.exists(id), isTrue);
  });
}
