import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import '../../domain/full_backup.dart';
import '../database.dart';
import '../sync/sync_backup.dart' show blankDeviceLocalSyncTables;
import '../sync/sync_schema.dart';

/// Writes the user data in the three backup formats. Rows are read in
/// id-ordered batches and streamed out, so memory stays flat however big the
/// database is. The derived caches (`syncExcludedColumns`) are left out: the
/// import rebuilds them. The device-local `sync_*` tables are never exported
/// (`sync_peers` holds the pairing keys).
class BackupWriter {
  BackupWriter(this.db);

  final AppDatabase db;

  Future<List<String>> _columns(String table) async {
    final skip = syncExcludedColumns[table] ?? const <String>{};
    final info = await db.customSelect('PRAGMA table_info($table)').get();
    return [
      for (final r in info)
        if (!skip.contains(r.read<String>('name'))) r.read<String>('name'),
    ];
  }

  /// Every table as batches of at most [kBackupBatchRows] rows, parents first.
  /// A table's first chunk is always an empty one carrying its columns, so an
  /// empty table still gets its header.
  Stream<TableChunk> chunks() async* {
    for (final table in backupTableOrder) {
      final cols = await _columns(table);
      if (cols.isEmpty) continue; // a table this schema version does not have
      yield TableChunk(table, cols, const []);
      final pk = syncTables[table]!;
      String? last;
      while (true) {
        final rows = await db
            .customSelect(
              'SELECT ${cols.join(', ')} FROM $table '
              '${last == null ? '' : 'WHERE $pk > ? '}'
              'ORDER BY $pk LIMIT $kBackupBatchRows',
              variables: [if (last != null) Variable.withString(last)],
            )
            .get();
        if (rows.isEmpty) break;
        yield TableChunk(table, cols, [
          for (final r in rows) [for (final c in cols) r.data[c]],
        ]);
        last = rows.last.data[pk] as String;
        if (rows.length < kBackupBatchRows) break;
        // Let the UI thread draw a frame between batches.
        await Future<void>.delayed(Duration.zero);
      }
    }
  }

  /// The compact `.livenow` file: gzip of line-delimited JSON (a header line,
  /// then per table a `{"t","c"}` line followed by one JSON array per row, and
  /// a closing `{"end"}` line that proves the file is complete). Written to a
  /// `.tmp` file and renamed, so a crash never leaves a half file under the
  /// real name. Returns the number of rows written.
  Future<int> writeCompact(File out, {DateTime? now}) async {
    final tmp = File('${out.path}.tmp');
    if (await tmp.exists()) await tmp.delete();
    final raw = tmp.openWrite();
    final gz = GZipCodec(level: 3).encoder.startChunkedConversion(raw);
    var total = 0;
    try {
      void line(String s) => gz.add(utf8.encode('$s\n'));
      line(encodeHeaderLine(db.schemaVersion, now ?? DateTime.now()));
      String? current;
      await for (final c in chunks()) {
        if (c.table != current) {
          current = c.table;
          line(encodeTableLine(c.table, c.columns));
        }
        for (final row in c.rows) {
          line(jsonEncode(row));
        }
        total += c.rows.length;
        await raw.flush();
      }
      line(encodeEndLine(total));
      gz.close();
      await raw.close();
    } catch (_) {
      try {
        await raw.close();
      } catch (_) {}
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    }
    try {
      if (await out.exists()) await out.delete();
      await tmp.rename(out.path);
    } catch (_) {
      // The finished temp file must not be left behind (it would sit in the
      // backup folder for good); the previous backup, if any, is still there
      // unless it was the thing that could not be replaced.
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      rethrow;
    }
    return total;
  }

  /// One `<table>.csv` per table in [dir] (+ `_meta.csv` with the schema
  /// version). Returns the files written.
  Future<List<File>> writeCsvFolder(Directory dir, {DateTime? now}) async {
    await dir.create(recursive: true);
    final files = <File>[];
    String path(String name) => '${dir.path}${Platform.pathSeparator}$name';

    final meta = File(path('_meta.csv'));
    await meta.writeAsString(
      '${csvLine(['key', 'value'])}\n'
      '${csvLine(['format', kBackupFormat])}\n'
      '${csvLine(['version', kBackupVersion])}\n'
      '${csvLine(['schemaVersion', db.schemaVersion])}\n'
      '${csvLine(['exportedAt', (now ?? DateTime.now()).toUtc().toIso8601String()])}\n',
    );
    files.add(meta);

    String? current;
    IOSink? sink;
    try {
      await for (final c in chunks()) {
        if (c.table != current) {
          await sink?.close();
          current = c.table;
          final f = File(path('${c.table}.csv'));
          files.add(f);
          sink = f.openWrite();
          sink.writeln(csvLine(c.columns));
        }
        for (final row in c.rows) {
          sink!.writeln(csvLine(row));
        }
        await sink!.flush();
      }
    } finally {
      await sink?.close();
    }
    return files;
  }

  /// A compacted copy of the database file (`VACUUM INTO`) with the
  /// device-local sync tables emptied (pairing keys, device id, cursors).
  Future<void> writeSqliteCopy(File out) async {
    final tmp = File('${out.path}.tmp');
    if (await tmp.exists()) await tmp.delete();
    await db.customStatement("VACUUM INTO '${tmp.path.replaceAll("'", "''")}'");
    blankDeviceLocalSyncTables(tmp.path);
    try {
      if (await out.exists()) await out.delete();
      await tmp.rename(out.path);
    } catch (_) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      rethrow;
    }
  }
}
