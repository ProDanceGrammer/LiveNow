import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/data/sync/sync_backup.dart';
import 'package:livenow/domain/action_service.dart';

void main() {
  late AppDatabase db;
  late Directory dir;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dir = Directory.systemTemp.createTempSync('livenow-backup-test');
  });

  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  test('a backup is a complete, openable copy of the database', () async {
    await ActionService(db).createAction(name: 'Keep me');
    final path = await backupDatabase(
      db,
      dir,
      label: 'before-pairing',
      now: DateTime(2026, 10, 10, 9, 30, 5),
    );
    expect(path, endsWith('livenow-before-pairing-20261010-093005.sqlite'));

    final copy = AppDatabase.forTesting(NativeDatabase(File(path)));
    addTearDown(copy.close);
    final rows = await copy.select(copy.actionsTable).get();
    expect(rows.map((r) => r.name), ['Keep me']);
  });

  test('old backups are removed, recent ones and other files stay', () async {
    final old = File('${dir.path}/old.sqlite')..writeAsStringSync('x');
    old.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 40)));
    final recent = File('${dir.path}/recent.sqlite')..writeAsStringSync('x');
    final note = File('${dir.path}/readme.txt')..writeAsStringSync('x');
    note.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 40)));

    expect(await pruneBackups(dir), 1);
    expect(old.existsSync(), isFalse);
    expect(recent.existsSync(), isTrue);
    expect(note.existsSync(), isTrue);
  });
}
