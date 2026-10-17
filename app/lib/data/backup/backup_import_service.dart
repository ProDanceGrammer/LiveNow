import 'dart:io';

import 'package:drift/drift.dart' show TableUpdate, Variable;

import '../../domain/full_backup.dart';
import '../database.dart';
import '../sync/sync_backup.dart';
import '../sync/sync_schema.dart';
import '../sync/sync_store.dart';
import 'backup_sources.dart';

enum BackupImportMode {
  /// Add the rows that are missing, and replace a row only when the file's copy
  /// is newer (`updated_at`). Nothing is deleted.
  merge,

  /// Empty every user table first (after a safety copy), then load the file.
  replace,
}

class TableImportCount {
  /// Rows inserted or overwritten by a newer copy.
  int written = 0;

  /// Rows that were already here (and not older than the file's copy).
  int kept = 0;
}

class BackupImportSummary {
  BackupImportSummary(this.tables, this.repairs, this.safetyCopy);

  final Map<String, TableImportCount> tables;

  /// References/cycles fixed so the data stays valid.
  final int repairs;

  /// The automatic copy of the previous data (Replace only).
  final String? safetyCopy;

  int get written => tables.values.fold(0, (a, c) => a + c.written);
  int get kept => tables.values.fold(0, (a, c) => a + c.kept);
}

/// Loads a backup (any [BackupSource]) into the live database in ONE
/// transaction: a damaged, incomplete or too-new file changes nothing. The
/// triggers stay on, so the rows count as local edits and paired devices
/// converge to the imported data.
class BackupImportService {
  BackupImportService(this.db, this.syncStore, {this.afterImport});

  final AppDatabase db;
  final SyncStore syncStore;

  /// Recomputes the derived caches that live outside this service (growth
  /// direction weights).
  final Future<void> Function()? afterImport;

  Future<BackupImportSummary> import(
    BackupSource source, {
    BackupImportMode mode = BackupImportMode.merge,
    Directory? safetyBackupDir,
  }) async {
    final header = await source.header();
    final fileSchema = header.schemaVersion;
    if (fileSchema != null && fileSchema > db.schemaVersion) {
      throw const BackupFormatException(
        'This backup was made by a newer version of LiveNow. Update the app first.',
      );
    }

    String? safetyCopy;
    if (mode == BackupImportMode.replace && safetyBackupDir != null) {
      safetyCopy = await backupDatabase(
        db,
        safetyBackupDir,
        label: 'before-import',
      );
      // Safety copies must not pile up for ever (they hold all the data).
      await pruneBackups(safetyBackupDir);
    }

    final counts = <String, TableImportCount>{};
    var repairs = 0;
    final columnCache = <String, List<String>>{};
    await db.transaction(() async {
      await db.customStatement('PRAGMA defer_foreign_keys = ON');
      if (mode == BackupImportMode.replace) {
        for (final t in backupTableOrder.reversed) {
          await db.customStatement('DELETE FROM $t');
        }
      }
      await for (final chunk in source.chunks()) {
        if (!syncTables.containsKey(chunk.table)) continue; // not ours
        await _apply(chunk, counts, columnCache);
      }
      repairs = (await syncStore.repairAfterBulkWrite(counts.keys.toSet()))
          .length;
    });

    // Derived caches, then tell the live streams (raw statements do not).
    await db.backfillNotesText();
    await afterImport?.call();
    db.notifyUpdates({for (final t in backupTableOrder) TableUpdate(t)});
    return BackupImportSummary(counts, repairs, safetyCopy);
  }

  Future<List<String>> _tableColumns(
    String table,
    Map<String, List<String>> cache,
  ) async {
    final hit = cache[table];
    if (hit != null) return hit;
    final skip = syncExcludedColumns[table] ?? const <String>{};
    final info = await db.customSelect('PRAGMA table_info($table)').get();
    return cache[table] = [
      for (final r in info)
        if (!skip.contains(r.read<String>('name'))) r.read<String>('name'),
    ];
  }

  Variable<Object> _variable(Object? v) => switch (v) {
    null => const Variable<Object>(null),
    int i => Variable<int>(i) as Variable<Object>,
    double d => Variable<double>(d) as Variable<Object>,
    bool b => Variable<int>(b ? 1 : 0) as Variable<Object>,
    String s => Variable<String>(s) as Variable<Object>,
    _ => Variable<String>(v.toString()) as Variable<Object>,
  };

  Future<void> _apply(
    TableChunk chunk,
    Map<String, TableImportCount> counts,
    Map<String, List<String>> cache,
  ) async {
    final table = chunk.table;
    final count = counts.putIfAbsent(table, TableImportCount.new);
    if (chunk.rows.isEmpty) return;
    final known = (await _tableColumns(table, cache)).toSet();
    // Columns this schema does not have are ignored; columns the file lacks
    // fall back to their defaults.
    final use = <int>[
      for (var i = 0; i < chunk.columns.length; i++)
        if (known.contains(chunk.columns[i])) i,
    ];
    final cols = [for (final i in use) chunk.columns[i]];
    final pk = syncTables[table]!;
    if (!cols.contains(pk)) {
      throw BackupFormatException('The backup has no "$pk" column for $table.');
    }
    final newerWins = cols.contains('updated_at');
    final sets = [
      for (final c in cols)
        if (c != pk) '$c = excluded.$c',
    ];
    final sql =
        'INSERT OR IGNORE INTO $table (${cols.join(', ')}) '
        'VALUES (${List.filled(cols.length, '?').join(', ')})'
        '${newerWins && sets.isNotEmpty ? ' ON CONFLICT($pk) DO UPDATE SET ${sets.join(', ')} '
                  'WHERE excluded.updated_at > $table.updated_at' : ''}';
    for (final row in chunk.rows) {
      final changed = await db.customUpdate(
        sql,
        variables: [for (final i in use) _variable(row[i])],
      );
      if (changed > 0) {
        count.written++;
      } else {
        count.kept++;
      }
    }
  }
}
