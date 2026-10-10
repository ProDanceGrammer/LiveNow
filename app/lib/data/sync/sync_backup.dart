import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../database.dart';

/// Where backups go: `livenow_backups` in the documents folder (the data
/// folder when `LIVENOW_DATA_DIR` is set, so automated runs stay isolated).
Future<Directory> defaultBackupDirectory() async {
  final override = Platform.environment['LIVENOW_DATA_DIR'];
  final base = override != null && override.isNotEmpty
      ? Directory(override)
      : await getApplicationDocumentsDirectory();
  return Directory('${base.path}${Platform.pathSeparator}livenow_backups')
      .create(recursive: true);
}

/// Writes a consistent copy of the whole database into [dir] (`VACUUM INTO`:
/// safe while the app runs and the WAL journal is in use) and returns its path.
Future<String> backupDatabase(
  AppDatabase db,
  Directory dir, {
  String label = 'backup',
  DateTime? now,
}) async {
  final t = (now ?? DateTime.now()).toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp =
      '${t.year}${two(t.month)}${two(t.day)}-'
      '${two(t.hour)}${two(t.minute)}${two(t.second)}';
  final path =
      '${dir.path}${Platform.pathSeparator}livenow-$label-$stamp.sqlite';
  await db.customStatement("VACUUM INTO '${path.replaceAll("'", "''")}'");
  return path;
}

/// Deletes backups in [dir] older than [keep]; returns how many went.
Future<int> pruneBackups(
  Directory dir, {
  Duration keep = const Duration(days: 30),
  DateTime? now,
}) async {
  final limit = (now ?? DateTime.now()).subtract(keep);
  var removed = 0;
  await for (final f in dir.list()) {
    if (f is File &&
        f.path.endsWith('.sqlite') &&
        (await f.lastModified()).isBefore(limit)) {
      await f.delete();
      removed++;
    }
  }
  return removed;
}
