import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/backup/auto_backup.dart';
import 'package:livenow/data/backup/backup_sources.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';

void main() {
  late AppDatabase db;
  late Directory dir;
  late AutoBackupStore store;
  late DateTime clock;
  late AutoBackupRunner runner;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dir = Directory.systemTemp.createTempSync('livenow-auto-backup');
    store = AutoBackupStore(File('${dir.path}/auto_backup.json'));
    clock = DateTime(2026, 10, 13, 8);
    runner = AutoBackupRunner(db, store, now: () => clock);
    await ActionService(db).createAction(name: 'Something');
  });

  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  Future<void> enable() => store.save(
    AutoBackupSettings(enabled: true, folder: '${dir.path}/backups'),
  );

  List<File> backups() => Directory('${dir.path}/backups')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.livenow'))
      .toList();

  test('off until a folder is chosen and the switch is on', () async {
    expect((await runner.run()).outcome, AutoBackupOutcome.disabled);
    await store.save(const AutoBackupSettings(enabled: true));
    expect((await runner.run()).outcome, AutoBackupOutcome.disabled);
  });

  test('the first run writes a readable file; the next is not due for 5 h',
      () async {
    await enable();
    final r = await runner.run();
    expect(r.outcome, AutoBackupOutcome.written);
    final header = await CompactBackupSource(File(r.path!)).header();
    expect(header.schemaVersion, db.schemaVersion);

    clock = clock.add(const Duration(hours: 4, minutes: 59));
    expect((await runner.run()).outcome, AutoBackupOutcome.notDue);
    expect(backups(), hasLength(1));
  });

  test('when due but nothing changed, no new file is written', () async {
    await enable();
    await runner.run();
    clock = clock.add(const Duration(hours: 5));
    expect((await runner.run()).outcome, AutoBackupOutcome.unchanged);
    expect(backups(), hasLength(1));

    // A change makes the next due run write again.
    await ActionService(db).createAction(name: 'More');
    clock = clock.add(const Duration(hours: 5));
    expect((await runner.run()).outcome, AutoBackupOutcome.written);
    expect(backups(), hasLength(2));
  });

  test('only the newest five files are kept', () async {
    await enable();
    for (var i = 0; i < 8; i++) {
      await ActionService(db).createAction(name: 'Change $i');
      clock = clock.add(const Duration(hours: 5));
      expect((await runner.run()).outcome, AutoBackupOutcome.written);
    }
    final names = backups().map((f) => f.uri.pathSegments.last).toList()
      ..sort();
    expect(names, hasLength(5));
    // The newest file is the last run's.
    final s = await store.load();
    expect(s.lastFile, endsWith(names.last));
  });

  test('Back up now ignores the schedule and the unchanged check', () async {
    await enable();
    await runner.run();
    clock = clock.add(const Duration(minutes: 1));
    expect((await runner.run(force: true)).outcome, AutoBackupOutcome.written);
  });

  test('an unusable folder is reported, never thrown', () async {
    final blocker = File('${dir.path}/blocker')..writeAsStringSync('x');
    await store.save(
      AutoBackupSettings(enabled: true, folder: '${blocker.path}/inner'),
    );
    final r = await runner.run();
    expect(r.outcome, AutoBackupOutcome.failed);
    expect((await store.load()).lastError, isNotNull);
    // Fixing the folder clears the error on the next successful run.
    await enable();
    expect((await runner.run()).outcome, AutoBackupOutcome.written);
    expect((await store.load()).lastError, isNull);
  });

  test('timeUntilDue counts down from the last run', () async {
    await enable();
    await runner.run();
    clock = clock.add(const Duration(hours: 2));
    final left = runner.timeUntilDue(await store.load());
    expect(left, const Duration(hours: 3));
  });
}
