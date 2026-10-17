import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/data/sync/sync_backup.dart';
import 'package:livenow/data/sync/sync_peers.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

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

  test('a backup carries the data but no pairing keys or sync history', () async {
    await ActionService(db).createAction(name: 'Keep me');
    await SyncPeers(db).save(
      SyncPeer(
        deviceId: 'phone-1',
        name: 'Phone',
        key: Uint8List.fromList(List.filled(32, 7)),
        lastCounter: 3,
        addresses: const ['192.168.1.5'],
        port: 47653,
      ),
    );
    final path = await backupDatabase(db, dir);

    final raw = sqlite.sqlite3.open(path, mode: sqlite.OpenMode.readOnly);
    addTearDown(raw.close);
    int count(String t) =>
        raw.select('SELECT COUNT(*) AS n FROM $t').first['n']! as int;
    expect(count('actions'), 1);
    for (final t in deviceLocalSyncTables) {
      expect(count(t), 0, reason: t);
    }
    // The live database still has its peer.
    expect(await SyncPeers(db).all(), hasLength(1));
  });

  test('legacy backups are moved once, their keys stripped, others stay', () async {
    final from = Directory('${dir.path}/docs')..createSync();
    final to = Directory('${dir.path}/support')..createSync();

    final real = sqlite.sqlite3.open('${from.path}/a.sqlite');
    real.execute('CREATE TABLE sync_peers (key TEXT)');
    real.execute("INSERT INTO sync_peers VALUES ('secret')");
    real.execute('CREATE TABLE actions (id TEXT)');
    real.execute("INSERT INTO actions VALUES ('x')");
    real.close();
    File('${from.path}/junk.sqlite').writeAsStringSync('not a database');
    File('${from.path}/notes.txt').writeAsStringSync('keep');
    File('${from.path}/dup.sqlite').writeAsStringSync('old');
    File('${to.path}/dup.sqlite').writeAsStringSync('already here');

    expect(await moveLegacyBackups(from, to), 2); // a + junk; dup is left alone

    expect(File('${from.path}/a.sqlite').existsSync(), isFalse);
    expect(File('${to.path}/junk.sqlite').existsSync(), isTrue);
    expect(File('${to.path}/dup.sqlite').readAsStringSync(), 'already here');
    expect(File('${from.path}/dup.sqlite').existsSync(), isTrue);
    expect(File('${from.path}/notes.txt').existsSync(), isTrue);
    expect(from.existsSync(), isTrue); // not empty, so it stays

    final moved = sqlite.sqlite3.open(
      '${to.path}/a.sqlite',
      mode: sqlite.OpenMode.readOnly,
    );
    addTearDown(moved.close);
    expect(moved.select('SELECT COUNT(*) AS n FROM sync_peers').first['n'], 0);
    expect(moved.select('SELECT COUNT(*) AS n FROM actions').first['n'], 1);
  });

  test('an empty legacy folder is removed after the move', () async {
    final from = Directory('${dir.path}/docs')..createSync();
    final to = Directory('${dir.path}/support')..createSync();
    expect(await moveLegacyBackups(from, to), 0);
    expect(from.existsSync(), isFalse);
    // A missing folder is not an error.
    expect(await moveLegacyBackups(from, to), 0);
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
