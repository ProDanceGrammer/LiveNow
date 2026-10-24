import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/capped_read.dart';
import 'package:livenow/core/text_rules.dart' show InvalidNameException;
import 'package:livenow/data/backup/backup_import_service.dart';
import 'package:livenow/data/backup/backup_sources.dart';
import 'package:livenow/data/backup/backup_writer.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/data/sync/sync_store.dart';
import 'package:livenow/domain/action_import_service.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/budget_io_service.dart';
import 'package:livenow/domain/budget_service.dart';
import 'package:livenow/domain/full_backup.dart';
import 'package:livenow/domain/growth_rules.dart';
import 'package:livenow/domain/metric_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/domain/template_import_service.dart';
import 'package:livenow/ui/account_icon_codec.dart';

/// Odd files from the file picker: wrong or no extension, empty, truncated,
/// huge, binary, BOM / UTF-16, invalid UTF-8, hostile gzip, odd paths, files
/// that cannot be read. A bad file must give a plain message and change
/// NOTHING.
void main() {
  setUpAll(initPostponeTimeZoneData);

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('livenow_files_'));
  tearDown(() => dir.deleteSync(recursive: true));

  File write(String name, List<int> bytes) {
    final f = File('${dir.path}${Platform.pathSeparator}$name');
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(bytes);
    return f;
  }

  AppDatabase memDb() => AppDatabase.forTesting(
    NativeDatabase.memory(
      setup: (raw) => raw.execute('PRAGMA foreign_keys = ON;'),
    ),
  );

  Future<Map<String, List<List<Object?>>>> snapshot(AppDatabase db) async {
    final out = <String, List<List<Object?>>>{};
    await for (final c in BackupWriter(db).chunks()) {
      out.putIfAbsent(c.table, () => []).addAll(c.rows);
    }
    return out;
  }

  Future<AppDatabase> seeded() async {
    final db = memDb();
    final goal = await MetricService(db).saveMetric(
      name: 'Health',
      kind: MetricKind.count,
      window: MetricWindow.week,
      target: 3,
      isMain: true,
    );
    await ActionService(db).createAction(name: 'Keep me', metricIds: [goal]);
    return db;
  }

  group('reading a picked text file', () {
    test('plain UTF-8, a UTF-8 BOM, and UTF-16 with a BOM all come out as text', () async {
      const text = 'name,icon\nЗдоров\'я,💪\n';
      expect(await readTextCapped(XFile(write('a.csv', utf8.encode(text)).path)), text);
      expect(
        await readTextCapped(
          XFile(write('bom.csv', [0xEF, 0xBB, 0xBF, ...utf8.encode(text)]).path),
        ),
        text,
      );
      final le = <int>[0xFF, 0xFE];
      final be = <int>[0xFE, 0xFF];
      for (final u in text.codeUnits) {
        le.addAll([u & 0xFF, u >> 8]);
        be.addAll([u >> 8, u & 0xFF]);
      }
      expect(await readTextCapped(XFile(write('le.csv', le).path)), text);
      expect(await readTextCapped(XFile(write('be.csv', be).path)), text);
    });

    test('a zero-byte file reads as empty text', () async {
      expect(await readTextCapped(XFile(write('empty.csv', const []).path)), '');
    });

    test('invalid UTF-8, a picture and binary garbage are "not a text file"', () async {
      final bad = <List<int>>[
        [0xC3, 0x28, 0x41, 0x42],
        [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0xFF, 0xFE, 0x00],
        List<int>.generate(4096, (i) => (i * 131 + 7) % 256 | 0x80),
        [0xFF, 0xFE, 0x41], // UTF-16 BOM and an odd number of bytes
      ];
      for (var i = 0; i < bad.length; i++) {
        await expectLater(
          readTextCapped(XFile(write('bad$i.csv', bad[i]).path)),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              anyOf(contains('not a text file'), contains('not a valid text file')),
            ),
          ),
          reason: 'case $i',
        );
      }
    });

    test('a file over the cap is refused by its size, before it is read', () async {
      final f = write('big.csv', List.filled(2000, 0x61));
      await expectLater(
        readTextCapped(XFile(f.path), maxBytes: 1000),
        throwsA(isA<FormatException>().having((e) => e.message, 'm', contains('too large'))),
      );
      expect(await readTextCapped(XFile(f.path), maxBytes: 2000), hasLength(2000));
    });

    test('a file just above kMaxImportFileBytes (sparse, never read) is refused fast', () async {
      final f = File('${dir.path}${Platform.pathSeparator}huge.csv')
        ..createSync();
      final raf = f.openSync(mode: FileMode.write);
      raf.truncateSync(kMaxImportFileBytes + 1);
      raf.closeSync();
      final sw = Stopwatch()..start();
      await expectLater(
        readTextCapped(XFile(f.path)),
        throwsA(isA<FormatException>().having((e) => e.message, 'm', contains('too large'))),
      );
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });

    test('a missing file is a plain message, not a raw file-system error', () async {
      await expectLater(
        readTextCapped(XFile('${dir.path}${Platform.pathSeparator}nope.csv')),
        throwsA(isA<FormatException>().having((e) => e.message, 'm', contains('could not be read'))),
      );
    });

    test('a file another program holds locked is a plain message', () async {
      if (!Platform.isWindows) return; // advisory locks elsewhere
      final f = write('locked.csv', utf8.encode('a,b\n1,2\n'));
      final raf = f.openSync(mode: FileMode.append);
      raf.lockSync(FileLock.exclusive);
      try {
        await expectLater(
          readTextCapped(XFile(f.path)),
          throwsA(isA<FormatException>()),
        );
      } finally {
        raf.unlockSync();
        raf.closeSync();
      }
    });

    test('a path with spaces, Cyrillic, emoji and a double extension reads fine', () async {
      final f = write('Мій бюджет 💸/звіт (копія).csv.txt', utf8.encode('x,y\n'));
      expect(await readTextCapped(XFile(f.path)), 'x,y\n');
    });

    test('a file with no extension reads (the content decides, not the name)', () async {
      expect(
        await readTextCapped(XFile(write('README', utf8.encode('hello')).path)),
        'hello',
      );
    });

    test('readFileTextCapped refuses a big pairing file and bad bytes', () async {
      final big = write('pair.txt', List.filled(20 * 1024, 0x61));
      await expectLater(
        readFileTextCapped(big, maxBytes: 16 * 1024),
        throwsA(isA<FormatException>()),
      );
      final bin = write('pair2.txt', [0xFF, 0x00, 0xC3, 0x28]);
      await expectLater(
        readFileTextCapped(bin, maxBytes: 16 * 1024),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        readFileTextCapped(
          File('${dir.path}${Platform.pathSeparator}missing.txt'),
          maxBytes: 16 * 1024,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('readBytesCapped enforces its cap before loading', () async {
      final f = write('pic.png', List.filled(3000, 1));
      await expectLater(
        readBytesCapped(XFile(f.path), maxBytes: 2000),
        throwsA(isA<FormatException>()),
      );
      expect(await readBytesCapped(XFile(f.path), maxBytes: 3000), hasLength(3000));
    });
  });

  group('importers: a bad file changes nothing', () {
    final nasty = <String, String>{
      'empty': '',
      'blanks': '   \n\n  ',
      'one word': 'garbage',
      'wrong header': 'a,b,c\n1,2,3\n',
      'JSON where CSV is expected': '{"x": 1}',
      'JSON array': '[1,2,3]',
      'NUL and controls': 'Name\u0000,Type\u0001\n\u0002,\u0003\n',
      'lone BOM': '﻿',
      'unterminated quote': 'Name,Type\n"never closed,1\n',
      'HTML': '<html><body><h1>Not a csv</h1></body></html>',
    };

    test('growth directions CSV', () async {
      for (final e in nasty.entries) {
        final db = await seeded();
        addTearDown(db.close);
        final before = await snapshot(db);
        try {
          await MetricService(db).importGrowthDirections(e.value);
        } on FormatException {
          // fine
        }
        expect(await snapshot(db), equals(before), reason: 'growth: ${e.key}');
      }
    });

    test('actions CSV', () async {
      for (final e in nasty.entries) {
        final db = await seeded();
        addTearDown(db.close);
        final before = await snapshot(db);
        try {
          await ActionImportService(db).importCsv(e.value);
        } on FormatException {
          // fine
        } on InvalidNameException {
          // fine
        }
        if (e.key == 'unterminated quote' || e.key == 'NUL and controls') {
          continue; // a valid "Name" header: the lenient parse imports a row
        }
        expect(await snapshot(db), equals(before), reason: 'actions: ${e.key}');
      }
    });

    test('templates CSV', () async {
      for (final e in nasty.entries) {
        final db = await seeded();
        addTearDown(db.close);
        final before = await snapshot(db);
        try {
          await TemplateImportService(db).importCsv(e.value);
        } on FormatException {
          // fine
        } on InvalidNameException {
          // fine
        }
        if (e.key == 'unterminated quote' || e.key == 'NUL and controls') {
          continue; // a valid "Name" header: the lenient parse imports a row
        }
        expect(await snapshot(db), equals(before), reason: 'templates: ${e.key}');
      }
    });

    test('budget JSON and CSVs', () async {
      final hostileJson = <String>[
        ...nasty.values,
        jsonEncode({'format': 'livenow-budget', 'version': 1, 'accounts': [1, 'x']}),
        jsonEncode({'format': 'livenow-budget', 'version': 1, 'accounts': [{}]}),
        jsonEncode({'format': 'livenow-budget', 'version': 1, 'categories': 'nope'}),
        jsonEncode({'format': 'livenow-budget', 'version': 1, 'transactions': [{'id': 5}]}),
        jsonEncode({'format': 'livenow-budget', 'version': 'x'}),
        jsonEncode({'format': 'livenow-budget', 'version': 1, 'settings': 5}),
      ];
      for (final text in hostileJson) {
        final db = await seeded();
        addTearDown(db.close);
        await BudgetService(db).saveAccount(
          name: 'Cash',
          currency: 'USD',
          rateToBase: 1,
        );
        final before = await snapshot(db);
        Object? err;
        try {
          await BudgetIoService(db).importJson(text);
        } on Object catch (e) {
          err = e;
        }
        expect(err, isA<FormatException>(), reason: 'json $text -> $err');
        expect(await snapshot(db), equals(before), reason: 'json $text');
      }
      for (final e in nasty.entries) {
        // The UI only calls the CSV importers for a file whose header
        // `detectBudgetCsv` recognises; these two have a plausible header.
        if (e.key == 'unterminated quote' || e.key == 'NUL and controls') continue;
        final db = await seeded();
        addTearDown(db.close);
        await BudgetService(db).saveAccount(
          name: 'Cash',
          currency: 'USD',
          rateToBase: 1,
        );
        final before = await snapshot(db);
        for (final run in <Future<Object?> Function()>[
          () => BudgetIoService(db).importNotionCsvs(accountsCsv: e.value),
          () => BudgetIoService(db).importNotionCsvs(categoriesCsv: e.value),
          () => BudgetIoService(db).importNotionCsvs(transactionsCsv: e.value),
        ]) {
          try {
            await run();
          } on FormatException {
            // fine
          }
        }
        expect(await snapshot(db), equals(before), reason: 'budget csv: ${e.key}');
      }
    });

    test('an 9 MB single cell does not hang or crash the CSV importers', () async {
      final db = await seeded();
      addTearDown(db.close);
      final before = await snapshot(db);
      final line = 'Name,Notes\n${'x' * (9 * 1024 * 1024)},1\n';
      final sw = Stopwatch()..start();
      try {
        await ActionImportService(db).importCsv(line);
      } on FormatException {
        // fine
      } on InvalidNameException {
        // fine: over the 500-character name cap, rolled back
      }
      try {
        await MetricService(db).importGrowthDirections(line);
      } on FormatException {
        // fine
      }
      expect(sw.elapsed, lessThan(const Duration(seconds: 30)));
      expect(await snapshot(db), equals(before));
    });
  });

  group('backup files', () {
    late AppDatabase db;
    late AppDatabase target;
    BackupImportService service(AppDatabase d) => BackupImportService(d, SyncStore(d));

    setUp(() async {
      db = await seeded();
      target = await seeded();
    });
    tearDown(() async {
      await db.close();
      await target.close();
    });

    Future<Object?> importInto(BackupSource s, {BackupImportMode mode = BackupImportMode.merge}) async {
      try {
        await service(target).import(s, mode: mode);
        return null;
      } on Object catch (e) {
        return e;
      }
    }

    test('a good file imports (control)', () async {
      final f = File('${dir.path}/ok.livenow');
      await BackupWriter(db).writeCompact(f);
      expect(await importInto(CompactBackupSource(f)), isNull);
    });

    test('a .livenow cut off (truncated gzip) is refused and changes nothing', () async {
      final f = File('${dir.path}/full.livenow');
      await BackupWriter(db).writeCompact(f);
      final bytes = f.readAsBytesSync();
      for (final keep in [bytes.length ~/ 2, bytes.length - 30, 20, 10, 3]) {
        final cut = write('cut$keep.livenow', bytes.sublist(0, keep));
        final before = await snapshot(target);
        final err = await importInto(CompactBackupSource(cut), mode: BackupImportMode.replace);
        expect(err, isA<BackupFormatException>(), reason: 'cut at $keep: $err');
        expect(await snapshot(target), equals(before), reason: 'cut at $keep');
      }
    });

    test('losing only the 8-byte gzip trailer keeps a complete file readable (the end line proves it)', () async {
      final f = File('${dir.path}/full.livenow');
      await BackupWriter(db).writeCompact(f);
      final bytes = f.readAsBytesSync();
      final cut = write('trailer.livenow', bytes.sublist(0, bytes.length - 8));
      final err = await importInto(CompactBackupSource(cut));
      expect(err, anyOf(isNull, isA<BackupFormatException>()), reason: '$err');
    });

    test('empty file, text file, CSV content and a PNG named .livenow are refused', () async {
      final cases = <String, List<int>>{
        'empty': const [],
        'text': utf8.encode('hello there'),
        'csv': utf8.encode('id,name\n1,Run\n'),
        'png': [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0],
        'zip': [0x50, 0x4B, 0x03, 0x04, 0, 0, 0, 0],
        'json': utf8.encode('{"format":"nope"}'),
      };
      for (final e in cases.entries) {
        final f = write('${e.key}.livenow', e.value);
        final before = await snapshot(target);
        final err = await importInto(CompactBackupSource(f), mode: BackupImportMode.replace);
        expect(err, isA<BackupFormatException>(), reason: '${e.key}: $err');
        expect(await snapshot(target), equals(before), reason: e.key);
      }
    });

    test('gzip of text that is not UTF-8 is refused as damaged', () async {
      final f = write('latin.livenow', gzip.encode([0xC3, 0x28, 0xFF, 0x0A, 0xFE]));
      final err = await importInto(CompactBackupSource(f));
      expect(err, isA<BackupFormatException>(), reason: '$err');
    });

    test('a UTF-16 text inside the gzip is refused', () async {
      final units = '{"format":"livenow-backup"}\n'.codeUnits;
      final f = write(
        'u16.livenow',
        gzip.encode([0xFF, 0xFE, for (final u in units) ...[u, 0]]),
      );
      final err = await importInto(CompactBackupSource(f));
      expect(err, isA<BackupFormatException>(), reason: '$err');
    });

    test('a CSV-folder file with the wrong content (gzip bytes named actions.csv) is refused cleanly', () async {
      final backup = File('${dir.path}/full.livenow');
      await BackupWriter(db).writeCompact(backup);
      final fake = write('actions.csv', backup.readAsBytesSync());
      final before = await snapshot(target);
      final err = await importInto(
        CsvFolderBackupSource({'actions.csv': fake}),
        mode: BackupImportMode.replace,
      );
      expect(err, isA<BackupFormatException>(), reason: '$err');
      expect(await snapshot(target), equals(before));
    });

    test('CSV files with no backup table names are not a backup (hasTables)', () {
      final f = write('stuff.csv', utf8.encode('a,b\n'));
      expect(CsvFolderBackupSource({'stuff.csv': f}).hasTables, isFalse);
      expect(CsvFolderBackupSource({'backup.livenow.csv': f}).hasTables, isFalse);
      expect(CsvFolderBackupSource({'ACTIONS.CSV': f}).hasTables, isTrue);
    });

    test('a SQLite-looking file that is random bytes is "not a LiveNow database"', () async {
      final rnd = Random(5);
      final f = write(
        'rnd.sqlite',
        List<int>.generate(8192, (_) => rnd.nextInt(256)),
      );
      final before = await snapshot(target);
      final err = await importInto(SqliteBackupSource(f), mode: BackupImportMode.replace);
      expect(err, isA<BackupFormatException>(), reason: '$err');
      expect(await snapshot(target), equals(before));
    });

    test('a gzip bomb (about 1.1 GB of lines from a tiny file) stops at the cap', () async {
      // Streamed through the encoder: the test never holds more than 1 MB.
      final f = File('${dir.path}/bomb.livenow');
      final sink = f.openWrite();
      final enc = gzip.encoder.startChunkedConversion(sink);
      final header = utf8.encode(
        '${jsonEncode({'format': kBackupFormat, 'version': kBackupVersion, 'schemaVersion': 16})}\n'
        '${jsonEncode({'t': 'actions', 'c': ['id']})}\n',
      );
      enc.add(header);
      final block = Uint8List(1024 * 1024)..fillRange(0, 1024 * 1024 - 1, 0x20);
      block[block.length - 1] = 0x0A;
      for (var i = 0; i < 1100; i++) {
        enc.add(block);
      }
      enc.close();
      await sink.close();
      expect(f.lengthSync(), lessThan(8 * 1024 * 1024));
      final sw = Stopwatch()..start();
      final err = await importInto(CompactBackupSource(f));
      expect(err, isA<BackupFormatException>(), reason: '$err');
      expect(sw.elapsed, lessThan(const Duration(seconds: 90)));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('one 9 MB line is refused as damaged (not buffered)', () async {
      final f = write(
        'line.livenow',
        gzip.encode(utf8.encode(
          '${jsonEncode({'format': kBackupFormat, 'version': kBackupVersion, 'schemaVersion': 16})}\n'
          '${'a' * (9 * 1024 * 1024)}\n',
        )),
      );
      final err = await importInto(CompactBackupSource(f));
      expect(err, isA<BackupFormatException>(), reason: '$err');
    });
  });

  group('account icon', () {
    // A real 1x1 PNG.
    final png1 = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
    );

    test('bytes over the 10 MB cap are refused without decoding', () async {
      await expectLater(
        encodeAccountIcon(Uint8List(kAccountIconMaxFileBytes + 1)),
        throwsA(isA<AccountIconException>()),
      );
    });

    test('empty, text and truncated image bytes are "not an image"', () async {
      for (final bytes in <Uint8List>[
        Uint8List(0),
        Uint8List.fromList(utf8.encode('not an image at all')),
        Uint8List.fromList(png1.sublist(0, 20)),
        Uint8List.fromList(List.filled(500, 0)),
      ]) {
        await expectLater(encodeAccountIcon(bytes), throwsA(isA<AccountIconException>()));
      }
    });

    test('a 1x1 image is scaled to the stored square and round-trips', () async {
      final text = await encodeAccountIcon(Uint8List.fromList(png1));
      expect(text.length, lessThan(kAccountIconMaxChars));
      final back = decodeAccountIcon(text);
      expect(back, isNotNull);
      expect(back!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    });

    test('stored icons that are empty, corrupt base64 or too long show nothing', () {
      expect(decodeAccountIcon(null), isNull);
      expect(decodeAccountIcon(''), isNull);
      expect(decodeAccountIcon('%%% not base64 %%%'), isNull);
      expect(decodeAccountIcon('A' * (kAccountIconMaxChars + 1)), isNull);
      // Valid base64 of junk is returned as bytes (the image widget shows its
      // error builder); it must at least not throw.
      expect(() => decodeAccountIcon(base64Encode([1, 2, 3])), returnsNormally);
    });
  });
}
