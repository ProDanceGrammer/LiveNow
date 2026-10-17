import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../domain/full_backup.dart';
import '../sync/sync_schema.dart';

/// Where an import reads rows from. All three formats become the same stream
/// of [TableChunk]s, so one merge engine serves them.
abstract class BackupSource {
  /// Validates the file's first bytes and returns what it says about itself.
  Future<BackupHeader> header();

  /// The rows, in batches. Throws [BackupFormatException] for a file that is
  /// damaged or incomplete.
  Stream<TableChunk> chunks();
}

/// A backup file is untrusted input: these bounds stop a decompression bomb, one
/// endless line or a giant cell from eating all memory. Real backups are far
/// below them (5,000 actions with notes = about 1 MB unpacked).
const kMaxBackupUnpackedBytes = 1024 * 1024 * 1024; // 1 GiB of JSON in total
const kMaxBackupLineBytes = 8 * 1024 * 1024; // one row / header line
const kMaxBackupBatchBytes = 32 * 1024 * 1024; // rows held before a flush
const kMaxBackupCsvFileBytes = 1024 * 1024 * 1024;
const kMaxBackupMetaBytes = 1024 * 1024;

/// Passes bytes through while counting them; throws a [BackupFormatException]
/// as soon as the total or a single line passes its bound.
Stream<List<int>> _bounded(Stream<List<int>> bytes) async* {
  var total = 0;
  var line = 0;
  await for (final chunk in bytes) {
    total += chunk.length;
    if (total > kMaxBackupUnpackedBytes) {
      throw const BackupFormatException('The backup file is too large.');
    }
    for (final b in chunk) {
      if (b == 0x0A) {
        line = 0;
      } else if (++line > kMaxBackupLineBytes) {
        throw const BackupFormatException('The backup file is damaged.');
      }
    }
    yield chunk;
  }
}

Future<void> _checkFileSize(File file, int max) async {
  if (await file.length() > max) {
    throw const BackupFormatException('The backup file is too large.');
  }
}

/// The compact `.livenow` file (gzip of line-delimited JSON).
class CompactBackupSource implements BackupSource {
  CompactBackupSource(this.file);

  final File file;

  Stream<String> _lines() => _bounded(file.openRead().transform(gzip.decoder))
      .transform(utf8.decoder)
      .transform(const LineSplitter());

  @override
  Future<BackupHeader> header() async {
    try {
      final first = await _lines().firstWhere(
        (l) => l.isNotEmpty,
        orElse: () => '',
      );
      return parseHeaderLine(first);
    } on FormatException {
      throw const BackupFormatException('This is not a LiveNow backup file.');
    }
  }

  @override
  Stream<TableChunk> chunks() async* {
    var sawHeader = false;
    var ended = false;
    String? table;
    List<String> columns = const [];
    var rows = <List<Object?>>[];
    var heldChars = 0;

    TableChunk? flush() {
      heldChars = 0;
      if (table == null || rows.isEmpty) return null;
      final c = TableChunk(table, columns, rows);
      rows = <List<Object?>>[];
      return c;
    }

    try {
      await for (final line in _lines()) {
        if (line.isEmpty) continue;
        if (!sawHeader) {
          parseHeaderLine(line);
          sawHeader = true;
          continue;
        }
        if (line.startsWith('[')) {
          final row = (jsonDecode(line) as List).cast<Object?>();
          if (table == null || row.length != columns.length) {
            throw const BackupFormatException('A row in the backup is damaged.');
          }
          rows.add(row);
          heldChars += line.length;
          if (rows.length >= kBackupBatchRows ||
              heldChars >= kMaxBackupBatchBytes) {
            yield flush()!;
          }
          continue;
        }
        final c = flush();
        if (c != null) yield c;
        final obj = jsonDecode(line) as Map<String, dynamic>;
        if (obj['end'] == true) {
          ended = true;
        } else if (obj['t'] is String) {
          table = obj['t'] as String;
          columns = (obj['c'] as List).cast<String>();
        }
      }
    } on FormatException {
      throw const BackupFormatException('The backup file is damaged.');
    }
    final c = flush();
    if (c != null) yield c;
    if (!sawHeader) {
      throw const BackupFormatException('This is not a LiveNow backup file.');
    }
    if (!ended) {
      throw const BackupFormatException(
        'The backup file is incomplete (it was cut off).',
      );
    }
  }
}

/// A folder of `<table>.csv` files (+ optional `_meta.csv`), as written by
/// `BackupWriter.writeCsvFolder`. Cells arrive as strings (null = empty); the
/// columns' type affinity turns them back into numbers on insert.
class CsvFolderBackupSource implements BackupSource {
  /// [files] maps a file name (`actions.csv`) to the file.
  CsvFolderBackupSource(Map<String, File> files)
    : _files = {for (final e in files.entries) e.key.toLowerCase(): e.value};

  final Map<String, File> _files;

  /// True when at least one file is named like a backup table.
  bool get hasTables =>
      backupTableOrder.any((t) => _files.containsKey('$t.csv'));

  @override
  Future<BackupHeader> header() async {
    final meta = _files['_meta.csv'];
    if (meta == null) return const BackupHeader();
    await _checkFileSize(meta, kMaxBackupMetaBytes);
    final p = CsvRowParser();
    final rows = [...p.add(await meta.readAsString()), ...p.close()];
    int? schema;
    for (final r in rows) {
      if (r.length >= 2 && r[0] == 'schemaVersion') schema = int.tryParse(r[1]!);
      if (r.length >= 2 && r[0] == 'version') {
        final v = int.tryParse(r[1] ?? '');
        if (v != null && v > kBackupVersion) {
          throw const BackupFormatException(
            'This backup was made by a newer version of LiveNow.',
          );
        }
      }
    }
    return BackupHeader(schemaVersion: schema);
  }

  @override
  Stream<TableChunk> chunks() async* {
    for (final table in backupTableOrder) {
      final file = _files['$table.csv'];
      if (file == null) continue;
      await _checkFileSize(file, kMaxBackupCsvFileBytes);
      final parser = CsvRowParser();
      List<String>? columns;
      var rows = <List<Object?>>[];
      Iterable<List<String?>> handle(List<List<String?>> parsed) sync* {
        for (final r in parsed) {
          if (r.length == 1 && r[0] == null) continue; // a blank line
          yield r;
        }
      }

      TableChunk? take(List<List<String?>> parsed) {
        for (final r in handle(parsed)) {
          if (columns == null) {
            columns = [for (final c in r) c ?? ''];
            continue;
          }
          if (r.length != columns!.length) {
            throw BackupFormatException('A row in $table.csv is damaged.');
          }
          rows.add(r);
        }
        if (rows.length >= kBackupBatchRows) {
          final c = TableChunk(table, columns!, rows);
          rows = <List<Object?>>[];
          return c;
        }
        return null;
      }

      await for (final text in file.openRead().transform(utf8.decoder)) {
        final c = take(parser.add(text));
        if (c != null) yield c;
      }
      final c = take(parser.close());
      if (c != null) yield c;
      if (columns == null) {
        throw BackupFormatException('$table.csv is empty.');
      }
      if (rows.isNotEmpty) yield TableChunk(table, columns!, rows);
    }
  }
}

/// A SQLite copy of a LiveNow database (`.db` / `.sqlite`), opened read-only on
/// its own (never through the app's schema, so nothing in it is migrated).
class SqliteBackupSource implements BackupSource {
  SqliteBackupSource(this.file);

  final File file;

  sqlite.Database _open() {
    try {
      final db = sqlite.sqlite3.open(file.path, mode: sqlite.OpenMode.readOnly);
      // The file is somebody else's: its views, triggers and virtual tables
      // must not run, and a damaged page layout is refused rather than read.
      db.execute('PRAGMA trusted_schema = OFF');
      db.execute('PRAGMA cell_size_check = ON');
      return db;
    } catch (_) {
      throw const BackupFormatException('This is not a LiveNow database.');
    }
  }

  /// A column name taken from the file, quoted so it can only be a name.
  static String _q(String name) => '"${name.replaceAll('"', '""')}"';

  bool _hasTable(sqlite.Database db, String t) => db
      .select("SELECT 1 FROM sqlite_master WHERE type='table' AND name = ?", [t])
      .isNotEmpty;

  @override
  Future<BackupHeader> header() async {
    final db = _open();
    try {
      if (!_hasTable(db, 'actions')) {
        throw const BackupFormatException('This is not a LiveNow database.');
      }
      final v = db.select('PRAGMA user_version').first.values.first as int;
      return BackupHeader(schemaVersion: v);
    } on sqlite.SqliteException {
      throw const BackupFormatException('This is not a LiveNow database.');
    } finally {
      db.close();
    }
  }

  @override
  Stream<TableChunk> chunks() async* {
    final db = _open();
    try {
      for (final table in backupTableOrder) {
        if (!_hasTable(db, table)) continue;
        final skip = syncExcludedColumns[table] ?? const <String>{};
        final cols = [
          for (final r in db.select('PRAGMA table_info($table)'))
            if (!skip.contains(r['name'])) r['name'] as String,
        ];
        final pk = syncTables[table]!;
        String? last;
        while (true) {
          final result = db.select(
            'SELECT ${cols.map(_q).join(', ')} FROM $table '
            '${last == null ? '' : 'WHERE $pk > ? '}'
            'ORDER BY $pk LIMIT $kBackupBatchRows',
            [?last],
          );
          if (result.isEmpty) break;
          yield TableChunk(table, cols, [
            for (final r in result) [for (final c in cols) r[c]],
          ]);
          last = result.last[pk] as String;
          if (result.length < kBackupBatchRows) break;
          await Future<void>.delayed(Duration.zero);
        }
      }
    } on sqlite.SqliteException {
      throw const BackupFormatException('The database could not be read.');
    } finally {
      db.close();
    }
  }
}
