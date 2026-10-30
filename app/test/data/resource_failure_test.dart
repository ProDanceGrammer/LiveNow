import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/db_errors.dart';
import 'package:livenow/core/error_log.dart';
import 'package:livenow/data/accounts/profile_paths.dart';
import 'package:livenow/data/backup/auto_backup.dart';
import 'package:livenow/data/backup/backup_import_service.dart';
import 'package:livenow/data/backup/backup_sources.dart';
import 'package:livenow/data/backup/backup_writer.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/data/sync/sync_store.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/full_backup.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/undo.dart';
import 'package:livenow/ui/widgets/action_editor.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Disk full, read-only, locked and busy databases; memory for big exports;
/// a failed backup must leave no half file and never lose what was there.
void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => Directory.systemTemp.path,
        );
    initPostponeTimeZoneData();
  });

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('livenow_res_'));
  tearDown(() {
    activeProfileDirectory = null;
    ErrorLog.errorLogDirectoryOverride = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  AppDatabase memDb() => AppDatabase.forTesting(
    NativeDatabase.memory(
      setup: (raw) => raw.execute('PRAGMA foreign_keys = ON;'),
    ),
  );

  String p(String name) => '${dir.path}${Platform.pathSeparator}$name';

  group('friendly database errors', () {
    test('codes map to plain sentences', () {
      expect(friendlyDbError(sqlite.SqliteException(extendedResultCode: 13, message: 'database or disk is full')), contains('Disk is full'));
      expect(friendlyDbError(sqlite.SqliteException(extendedResultCode: 5, message: 'database is locked')), contains('busy'));
      expect(friendlyDbError(sqlite.SqliteException(extendedResultCode: 6, message: 'table locked')), contains('busy'));
      expect(friendlyDbError(sqlite.SqliteException(extendedResultCode: 8, message: 'readonly')), contains('read-only'));
      expect(friendlyDbError(sqlite.SqliteException(extendedResultCode: attemptWrite, message: 'x')), isNull);
      expect(friendlyDbError(sqlite.SqliteException(extendedResultCode: 10, message: 'io')), contains('disk'));
      expect(friendlyDbError(sqlite.SqliteException(extendedResultCode: 11, message: 'corrupt')), contains('damaged'));
      // Extended codes keep their primary code in the low byte.
      expect(friendlyDbError(sqlite.SqliteException(extendedResultCode: 13 | (2 << 8), message: 'x')), contains('Disk is full'));
      expect(friendlyDbError(StateError('other')), isNull);
      expect(friendlyDbError(sqlite.SqliteException(extendedResultCode: 1, message: 'syntax')), isNull);
    });
  });

  // First on purpose: ErrorLog serialises its writes on one future chain; a
  // write started inside a testWidgets fake zone (the editor test below) would
  // never complete after the test and block every later write.
  group('the error log', () {
    test('never throws, whatever is wrong with its folder', () async {
      final blocker = File(p('blocker3'))..writeAsStringSync('x');
      ErrorLog.errorLogDirectoryOverride = Directory('${blocker.path}${Platform.pathSeparator}sub');
      await ErrorLog.write(StateError('boom'), StackTrace.current, context: 'test');
      ErrorLog.errorLogDirectoryOverride = Directory(p('does${Platform.pathSeparator}not${Platform.pathSeparator}exist'));
      await ErrorLog.write('plain string', null);
      // A folder sits where the log file should be.
      final logDir = Directory(p('logdir'))..createSync();
      Directory('${logDir.path}${Platform.pathSeparator}error.log').createSync();
      ErrorLog.errorLogDirectoryOverride = logDir;
      await ErrorLog.write(StateError('again'), null);
      // And 30 overlapping writes into a good folder all land.
      final good = Directory(p('goodlog'))..createSync();
      ErrorLog.errorLogDirectoryOverride = good;
      await Future.wait([for (var i = 0; i < 30; i++) ErrorLog.write('e$i', null)]);
      final text = File('${good.path}${Platform.pathSeparator}error.log').readAsStringSync();
      for (var i = 0; i < 30; i++) {
        expect(text, contains('e$i\n'));
      }
    });
  });

  group('real SQLite failures through the services', () {
    test('SQLITE_FULL: the write fails, earlier data stays, and writes work again after space is freed', () async {
      final db = memDb();
      addTearDown(db.close);
      final service = ActionService(db);
      await service.createAction(name: 'Before');
      final pages = (await db.customSelect('PRAGMA page_count').getSingle()).read<int>('page_count');
      await db.customStatement('PRAGMA max_page_count = ${pages + 3}');

      Object? err;
      try {
        for (var i = 0; i < 200; i++) {
          await service.createAction(name: 'Filler $i', notes: 'x' * 20000);
        }
      } on Object catch (e) {
        err = e;
      }
      expect(err, isNotNull, reason: 'the database should have filled up');
      expect(friendlyDbError(err!), contains('Disk is full'), reason: '$err');

      // Whatever committed before the failure is intact and readable.
      final names = [
        for (final r in await db.customSelect('SELECT name FROM actions').get())
          r.read<String>('name'),
      ];
      expect(names, contains('Before'));
      // Each failed create was atomic: no half-created action (a row without
      // its metric links is fine; a row without a name is not).
      expect(names.every((n) => n.isNotEmpty), isTrue);

      await db.customStatement('PRAGMA max_page_count = 100000');
      await service.createAction(name: 'After space is freed');
      expect(
        (await db.customSelect("SELECT COUNT(*) AS n FROM actions WHERE name = 'After space is freed'").getSingle()).read<int>('n'),
        1,
      );
    });

    test('SQLITE_READONLY: writes are refused with a friendly reason, reads still work', () async {
      final db = memDb();
      addTearDown(db.close);
      final service = ActionService(db);
      await service.createAction(name: 'Readable');
      await db.customStatement('PRAGMA query_only = ON');
      Object? err;
      try {
        await service.createAction(name: 'Refused');
      } on Object catch (e) {
        err = e;
      }
      expect(err, isNotNull);
      expect(friendlyDbError(err!), isNotNull, reason: '$err');
      expect(
        (await db.customSelect('SELECT COUNT(*) AS n FROM actions').getSingle()).read<int>('n'),
        1,
      );
    });

    test('SQLITE_BUSY: a second connection waits (busy_timeout) instead of failing at once', () async {
      activeProfileDirectory = Directory(p('profile'))..createSync();
      final db = AppDatabase();
      addTearDown(db.close);
      await ActionService(db).createAction(name: 'Seed');
      expect(
        (await db.customSelect('PRAGMA busy_timeout').getSingle()).read<int>('timeout'),
        greaterThanOrEqualTo(1000),
      );

      // Another process holds the write lock for a moment.
      final other = sqlite.sqlite3.open('${activeProfileDirectory!.path}${Platform.pathSeparator}livenow.sqlite');
      addTearDown(other.close);
      other.execute('PRAGMA busy_timeout = 0');
      other.execute('BEGIN IMMEDIATE');
      final release = Future<void>.delayed(const Duration(milliseconds: 700), () => other.execute('COMMIT'));
      final sw = Stopwatch()..start();
      await ActionService(db).createAction(name: 'Waited for the lock');
      await release;
      expect(sw.elapsedMilliseconds, greaterThan(300), reason: 'it should have waited');
      expect(
        (await db.customSelect('SELECT COUNT(*) AS n FROM actions').getSingle()).read<int>('n'),
        2,
      );
    });

    test('SQLITE_BUSY longer than the timeout surfaces as "busy", nothing half-written', () async {
      activeProfileDirectory = Directory(p('profile2'))..createSync();
      final db = AppDatabase();
      addTearDown(db.close);
      await ActionService(db).createAction(name: 'Seed');
      await db.customStatement('PRAGMA busy_timeout = 100');
      final other = sqlite.sqlite3.open('${activeProfileDirectory!.path}${Platform.pathSeparator}livenow.sqlite');
      addTearDown(other.close);
      other.execute('BEGIN IMMEDIATE');
      Object? err;
      try {
        await ActionService(db).createAction(name: 'Blocked');
      } on Object catch (e) {
        err = e;
      }
      other.execute('ROLLBACK');
      expect(err, isNotNull);
      expect(friendlyDbError(err!), contains('busy'), reason: '$err');
      expect(
        (await db.customSelect('SELECT COUNT(*) AS n FROM actions').getSingle()).read<int>('n'),
        1,
      );
    });
  });

  group('the UI says what happened', () {
    testWidgets('a quick action that hits a full disk shows "Disk is full" and logs', (tester) async {
      final logDir = Directory(p('log'))..createSync();
      ErrorLog.errorLogDirectoryOverride = logDir;
      final db = memDb();
      addTearDown(db.close);
      final id = (await tester.runAsync(() => ActionService(db).createAction(name: 'Task')))!;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () => runUndoable(
                    context,
                    ref,
                    id,
                    'Finished',
                    () async => throw sqlite.SqliteException(extendedResultCode: 13, message: 'database or disk is full'),
                  ),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('go'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Disk is full'), findsOneWidget);
      expect(find.textContaining('Could not complete "Finished"'), findsOneWidget);
      final log = await tester.runAsync(() => File('${logDir.path}${Platform.pathSeparator}error.log').readAsString());
      expect(log, contains('[Finished]'));
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('the editor keeps its dialog and text when saving fails with a full disk', (tester) async {
      ErrorLog.errorLogDirectoryOverride = Directory(p('log2'))..createSync();
      tester.view.physicalSize = const Size(1400, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = memDb();
      addTearDown(db.close);
      var fail = true;
      final service = _FlakyService(db, () => fail);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            actionServiceProvider.overrideWithValue(service),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => ActionEditorDialog.show(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
      final name = find.widgetWithText(TextFormField, 'Name');
      await tester.enterText(name.first, 'A very important task');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Disk is full'), findsOneWidget);
      expect(find.byType(ActionEditorDialog), findsOneWidget);
      expect(find.text('A very important task'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6)); // the toast goes away

      // Space is back: the same dialog saves what was typed.
      fail = false;
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 150));
      }
      expect(find.byType(ActionEditorDialog), findsNothing);
      final names = await tester.runAsync(
        () async => [
          for (final r in await db.customSelect('SELECT name FROM actions').get()) r.read<String>('name'),
        ],
      );
      expect(names, ['A very important task']);
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });

  group('backup writing on a failing disk', () {
    test('a failure in the middle removes the tmp file and leaves the old backup intact', () async {
      final db = memDb();
      addTearDown(db.close);
      await ActionService(db).createAction(name: 'x');
      final out = File(p('b.livenow'));
      await BackupWriter(db).writeCompact(out);
      final good = out.readAsBytesSync();

      final writer = _BrokenWriter(db);
      await expectLater(writer.writeCompact(out), throwsA(isA<FileSystemException>()));
      expect(File('${out.path}.tmp').existsSync(), isFalse);
      expect(out.readAsBytesSync(), good, reason: 'the previous backup is untouched');
    });

    test('the target cannot be replaced (a folder sits there): error, no tmp left behind', () async {
      final db = memDb();
      addTearDown(db.close);
      await ActionService(db).createAction(name: 'x');
      final out = File(p('blocked.livenow'));
      Directory(out.path).createSync();
      File('${out.path}${Platform.pathSeparator}keep.txt').writeAsStringSync('k');
      await expectLater(BackupWriter(db).writeCompact(out), throwsA(isA<FileSystemException>()));
      expect(File('${out.path}.tmp').existsSync(), isFalse);
      expect(File('${out.path}${Platform.pathSeparator}keep.txt').existsSync(), isTrue);
    });

    test('the tmp path cannot be created (a folder sits there): error, nothing half written', () async {
      final db = memDb();
      addTearDown(db.close);
      final out = File(p('c.livenow'));
      Directory('${out.path}.tmp').createSync();
      await expectLater(BackupWriter(db).writeCompact(out), throwsA(isA<FileSystemException>()));
      expect(out.existsSync(), isFalse);
    });

    test('the folder does not exist and cannot be made (a file sits there): failed, lastRunAt untouched, old backups kept', () async {
      final db = memDb();
      addTearDown(db.close);
      await ActionService(db).createAction(name: 'x');
      final good = Directory(p('good'))..createSync();
      final settingsFile = File(p('auto.json'));
      var now = DateTime.utc(2026, 10, 24, 12);
      final store = AutoBackupStore(settingsFile);
      await store.save(
        AutoBackupSettings(
          enabled: true,
          folder: good.path,
          lastRunAt: now.subtract(const Duration(hours: 6)),
          lastSeq: -1,
        ),
      );
      final runner = AutoBackupRunner(db, store, now: () => now);
      // One real run first (control) so old files exist.
      expect((await runner.run()).outcome, AutoBackupOutcome.written);
      final before = good.listSync().whereType<File>().map((f) => f.path).toList();
      expect(before, isNotEmpty);

      // The folder is replaced by a FILE: creating it fails.
      final s = await store.load();
      final blocker = File(p('blocker'))..writeAsStringSync('not a folder');
      await store.save(s.copyWith(folder: '${blocker.path}${Platform.pathSeparator}sub', lastRunAt: now.subtract(const Duration(hours: 6))));
      final lastRunBefore = (await store.load()).lastRunAt;
      await ActionService(db).createAction(name: 'Changed since the last file');
      final r = await runner.run();
      expect(r.outcome, AutoBackupOutcome.failed);
      expect(r.error, isNotEmpty);
      final after = await store.load();
      expect(after.lastRunAt, lastRunBefore, reason: 'a failed run must not look like a success');
      expect(after.lastError, isNotNull);
      // Still due at once, so the retry picks it up.
      expect(runner.timeUntilDue(after), Duration.zero);
      expect(good.listSync().whereType<File>().map((f) => f.path).toList(), before);
      expect(kAutoBackupRetry, const Duration(minutes: 30));
      // And it recovers when the folder is fine again.
      await store.save(after.copyWith(folder: good.path));
      now = now.add(const Duration(minutes: 31));
      expect((await runner.run(force: true)).outcome, AutoBackupOutcome.written);
      expect((await store.load()).lastError, isNull);
    });

    test('a failing run does not prune the backups that exist', () async {
      final db = memDb();
      addTearDown(db.close);
      final folder = Directory(p('keep'))..createSync();
      for (var i = 0; i < 5; i++) {
        File('${folder.path}${Platform.pathSeparator}livenow-backup-2026010$i-000000.livenow').writeAsStringSync('old $i');
      }
      final store = AutoBackupStore(File(p('auto2.json')));
      await store.save(AutoBackupSettings(enabled: true, folder: folder.path));
      // The Directory of a NEW file's tmp is blocked: a directory named like
      // the next file's tmp (same second), so writing it fails.
      final now = DateTime(2026, 10, 24, 12, 0, 0);
      final name = 'livenow-backup-20261024-120000.livenow';
      Directory('${folder.path}${Platform.pathSeparator}$name.tmp').createSync();
      final runner = AutoBackupRunner(db, store, now: () => now);
      final r = await runner.run(force: true);
      expect(r.outcome, AutoBackupOutcome.failed);
      expect(folder.listSync().whereType<File>(), hasLength(5));
    });

    test('a settings file that cannot be written never throws', () async {
      final db = memDb();
      addTearDown(db.close);
      final blocker = File(p('blocker2'))..writeAsStringSync('x');
      final store = AutoBackupStore(File('${blocker.path}${Platform.pathSeparator}auto.json'));
      await store.save(const AutoBackupSettings(enabled: true)); // no throw
      expect((await store.load()).enabled, isFalse);
    });

  });

  group('memory: big exports and imports stream', () {
    test('50,000 rows are written, read back and imported in bounded batches', () async {
      final db = memDb();
      addTearDown(db.close);
      // Fill `actions` with 50k rows in SQL (every NOT NULL column without a
      // default gets a neutral value).
      final info = await db.customSelect('PRAGMA table_info(actions)').get();
      final cols = <String>[];
      final vals = <String>[];
      for (final r in info) {
        final name = r.read<String>('name');
        final notNull = r.read<int>('notnull') == 1;
        final hasDefault = r.data['dflt_value'] != null;
        if (name == 'id') {
          cols.add(name);
          vals.add("printf('a%06d', i)");
        } else if (name == 'name') {
          cols.add(name);
          vals.add("'Action ' || i");
        } else if (notNull && !hasDefault) {
          cols.add(name);
          final t = r.read<String>('type').toUpperCase();
          vals.add(t.contains('INT') || t.contains('REAL') || t.contains('BOOL') ? '0' : "'2026-01-01T00:00:00.000000Z'");
        }
      }
      await db.customStatement(
        'WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 50000) '
        'INSERT INTO actions (${cols.join(', ')}) SELECT ${vals.join(', ')} FROM n',
      );
      expect((await db.customSelect('SELECT COUNT(*) AS n FROM actions').getSingle()).read<int>('n'), 50000);

      // Export: chunks never exceed the batch size.
      var maxRows = 0, actionRows = 0, chunks = 0;
      await for (final c in BackupWriter(db).chunks()) {
        if (c.rows.length > maxRows) maxRows = c.rows.length;
        if (c.table == 'actions') {
          actionRows += c.rows.length;
          chunks++;
        }
      }
      expect(maxRows, lessThanOrEqualTo(kBackupBatchRows));
      expect(actionRows, 50000);
      expect(chunks, greaterThanOrEqualTo(50000 ~/ kBackupBatchRows));

      // File: written streaming; sample the process memory while it runs.
      var peak = ProcessInfo.currentRss;
      final base = peak;
      final sampler = Stream<void>.periodic(const Duration(milliseconds: 20)).listen((_) {
        if (ProcessInfo.currentRss > peak) peak = ProcessInfo.currentRss;
      });
      final f = File(p('big.livenow'));
      final rows = await BackupWriter(db).writeCompact(f);
      expect(rows, greaterThanOrEqualTo(50000));

      // Import into a second database: batches stay bounded, all rows arrive.
      final target = memDb();
      addTearDown(target.close);
      var imported = 0, maxImportChunk = 0;
      final source = CompactBackupSource(f);
      await for (final c in source.chunks()) {
        if (c.rows.length > maxImportChunk) maxImportChunk = c.rows.length;
        imported += c.rows.length;
      }
      expect(maxImportChunk, lessThanOrEqualTo(kBackupBatchRows));
      expect(imported, rows);
      final summary = await BackupImportService(target, SyncStore(target)).import(
        CompactBackupSource(f),
        mode: BackupImportMode.replace,
      );
      expect(summary, isNotNull);
      expect((await target.customSelect('SELECT COUNT(*) AS n FROM actions').getSingle()).read<int>('n'), 50000);
      await sampler.cancel();
      // 50k small rows; the whole run (two databases included) stays far
      // below holding several copies of the data in memory.
      expect(peak - base, lessThan(400 * 1024 * 1024), reason: 'peak growth ${(peak - base) ~/ (1024 * 1024)} MB');
      expect(f.lengthSync(), lessThan(20 * 1024 * 1024));
    }, timeout: const Timeout(Duration(minutes: 4)));

    test('a 5 MB notes document is stored, read back whole and exported', () async {
      final db = memDb();
      addTearDown(db.close);
      final notes = jsonEncode({
        'document': {
          'type': 'page',
          'children': [
            for (var i = 0; i < 50; i++)
              {
                'type': 'paragraph',
                'data': {
                  'delta': [
                    {'insert': 'Line $i ${'z' * 100000}'},
                  ],
                },
              },
          ],
        },
      });
      expect(notes.length, greaterThan(5 * 1000 * 1000));
      final id = await ActionService(db).createAction(name: 'Big notes', notes: notes);
      final back = (await db.customSelect('SELECT notes FROM actions WHERE id = ?', variables: [Variable.withString(id)]).getSingle()).read<String>('notes');
      expect(back.length, notes.length);
      final f = File(p('notes.livenow'));
      await BackupWriter(db).writeCompact(f);
      expect(f.lengthSync(), lessThan(1024 * 1024), reason: 'gzip squeezes the repeated text');
    });
  });
}

const attemptWrite = 1; // SQLITE_ERROR: not one of the friendly codes

/// A service whose create fails with SQLITE_FULL while [failing] says so.
class _FlakyService extends ActionService {
  _FlakyService(super.db, this.failing);
  final bool Function() failing;

  @override
  Future<String> createAction({
    required String name,
    String postponeFlex = 'flexible',
    String? depthLevel,
    DateTime? startAt,
    DateTime? endAt,
    bool isAllDay = false,
    int? estimatedMinutes,
    String? countableActivityId,
    String? notes,
    List<String> metricIds = const [],
    String? planItemId,
    String? planKey,
    String? id,
  }) {
    if (failing()) {
      throw sqlite.SqliteException(extendedResultCode: 13, message: 'database or disk is full');
    }
    return super.createAction(
      name: name,
      postponeFlex: postponeFlex,
      depthLevel: depthLevel,
      startAt: startAt,
      endAt: endAt,
      isAllDay: isAllDay,
      estimatedMinutes: estimatedMinutes,
      countableActivityId: countableActivityId,
      notes: notes,
      metricIds: metricIds,
      planItemId: planItemId,
      planKey: planKey,
      id: id,
    );
  }
}

/// Writes a few chunks and then "runs out of disk".
class _BrokenWriter extends BackupWriter {
  _BrokenWriter(super.db);

  @override
  Stream<TableChunk> chunks() async* {
    var n = 0;
    await for (final c in super.chunks()) {
      yield c;
      if (++n >= 3) {
        throw const FileSystemException('No space left on device');
      }
    }
  }
}
