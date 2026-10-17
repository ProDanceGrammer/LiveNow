import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/backup/backup_sources.dart';
import 'package:livenow/domain/full_backup.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// A backup file is untrusted input: hostile or broken files must be refused
/// quickly and without eating memory.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('livenow_hardening'));
  tearDown(() => dir.deleteSync(recursive: true));

  final header = jsonEncode({
    'format': kBackupFormat,
    'version': kBackupVersion,
    'schemaVersion': 16,
  });

  File gz(String name, String text) {
    final f = File('${dir.path}/$name');
    f.writeAsBytesSync(gzip.encode(utf8.encode(text)));
    return f;
  }

  Future<Object?> drain(CompactBackupSource s) async {
    try {
      await s.chunks().toList();
      return null;
    } on Object catch (e) {
      return e;
    }
  }

  test('a normal backup still reads', () async {
    final f = gz(
      'ok.livenow',
      [
        header,
        jsonEncode({'t': 'countable_activities', 'c': ['id', 'name']}),
        jsonEncode(['a1', 'Run']),
        jsonEncode({'end': true}),
      ].join('\n'),
    );
    final chunks = await CompactBackupSource(f).chunks().toList();
    expect(chunks.single.rows.single, ['a1', 'Run']);
  });

  test('one endless line is refused instead of buffered', () async {
    final f = gz(
      'longline.livenow',
      '$header\n${jsonEncode({'t': 'actions', 'c': ['id']})}\n[${'"x",' * 3 * 1024 * 1024}"x"]\n',
    );
    final error = await drain(CompactBackupSource(f));
    expect(error, isA<BackupFormatException>());
  });

  test('garbage that is not gzip is refused', () async {
    final f = File('${dir.path}/junk.livenow')
      ..writeAsBytesSync(List.filled(2000, 7));
    final s = CompactBackupSource(f);
    expect(await drain(s), isA<Object>());
    await expectLater(s.header(), throwsA(isA<BackupFormatException>()));
  });

  test('a CSV folder meta file that is far too big is refused', () async {
    final meta = File('${dir.path}/_meta.csv')
      ..writeAsBytesSync(List.filled(kMaxBackupMetaBytes + 1, 0x61));
    final source = CsvFolderBackupSource({'_meta.csv': meta});
    await expectLater(source.header(), throwsA(isA<BackupFormatException>()));
  });

  test('a SQLite file with hostile column names is read as plain names', () async {
    final path = '${dir.path}/evil.sqlite';
    final raw = sqlite.sqlite3.open(path);
    raw.execute(
      'CREATE TABLE actions (id TEXT PRIMARY KEY, "name"", (SELECT 1)--" TEXT)',
    );
    raw.execute("INSERT INTO actions VALUES ('a1', 'x')");
    raw.execute('PRAGMA user_version = 16');
    raw.close();

    final source = SqliteBackupSource(File(path));
    expect((await source.header()).schemaVersion, 16);
    final chunks = await source.chunks().toList();
    expect(chunks.single.table, 'actions');
    expect(chunks.single.rows.single.first, 'a1');
  });

  test('a view named like a table is not read (only real tables are)', () async {
    final path = '${dir.path}/view.sqlite';
    final raw = sqlite.sqlite3.open(path);
    raw.execute('CREATE TABLE actions (id TEXT PRIMARY KEY)');
    raw.execute('CREATE VIEW metrics AS SELECT id FROM actions');
    raw.execute("INSERT INTO actions VALUES ('a1')");
    raw.close();

    final chunks = await SqliteBackupSource(File(path)).chunks().toList();
    expect(chunks.map((c) => c.table), ['actions']);
  });
}
