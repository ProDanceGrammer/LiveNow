import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../accounts/profile_paths.dart';
import '../database.dart';

/// The tables that belong to THIS device, not to the user's data: the pairing
/// keys (`sync_peers`), the device id and cursors, and the change log. A copy of
/// the database that leaves the app must not carry them: the keys let whoever
/// holds the file impersonate the paired phone.
const deviceLocalSyncTables = [
  'sync_peers',
  'sync_state',
  'sync_inbox',
  'sync_conflicts',
  'sync_versions',
  'sync_clock',
];

/// Empties [deviceLocalSyncTables] in the database COPY at [path] and compacts
/// it. Plain `sqlite3`, never the app's schema (nothing is migrated or stamped).
void blankDeviceLocalSyncTables(String path) {
  final copy = sqlite.sqlite3.open(path);
  try {
    for (final t in deviceLocalSyncTables) {
      try {
        copy.execute('DELETE FROM $t');
      } catch (_) {
        // The table may not exist in an older schema.
      }
    }
    copy.execute('VACUUM');
  } finally {
    copy.close();
  }
}

/// Where backups go: `livenow_backups` in the app's own data folder, next to
/// the database (not in Documents, which Windows often syncs to OneDrive). With
/// `LIVENOW_DATA_DIR` set it goes into that folder, so automated runs stay
/// isolated. Backups an older version left in Documents are moved here once.
Future<Directory> defaultBackupDirectory() async {
  // The signed-in account's own folder (the root while no account is active).
  final base = await profileDirectory();
  final dir = await Directory(
    '${base.path}${Platform.pathSeparator}livenow_backups',
  ).create(recursive: true);
  // The one-time move of old Documents backups belongs to the real data only:
  // not to an isolated run and not to a second account's folder.
  final override = Platform.environment['LIVENOW_DATA_DIR'];
  if ((override != null && override.isNotEmpty) ||
      activeProfileDirectory != null) {
    return dir;
  }
  try {
    final docs = await getApplicationDocumentsDirectory();
    await moveLegacyBackups(
      Directory('${docs.path}${Platform.pathSeparator}livenow_backups'),
      dir,
    );
  } catch (_) {
    // Best effort: a failed move leaves the old files where they were.
  }
  return dir;
}

/// Moves the `.sqlite` backups of [from] into [to] (rename, else copy and
/// delete), strips the pairing keys from each moved copy, and removes [from]
/// when it is empty. A file that already exists in [to] is left alone.
Future<int> moveLegacyBackups(Directory from, Directory to) async {
  if (!await from.exists() || from.absolute.path == to.absolute.path) return 0;
  var moved = 0;
  await for (final f in from.list()) {
    if (f is! File || !f.path.endsWith('.sqlite')) continue;
    final target = File('${to.path}${Platform.pathSeparator}${f.uri.pathSegments.last}');
    if (await target.exists()) continue;
    try {
      await f.rename(target.path);
    } on FileSystemException {
      await f.copy(target.path);
      await f.delete();
    }
    try {
      blankDeviceLocalSyncTables(target.path);
    } catch (_) {
      // Not a readable database: leave it as it is.
    }
    moved++;
  }
  if (await from.list().isEmpty) await from.delete();
  return moved;
}

/// Writes a consistent copy of the whole database into [dir] (`VACUUM INTO`:
/// safe while the app runs and the WAL journal is in use) and returns its path.
/// The copy has no pairing keys or other device-local sync data.
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
  blankDeviceLocalSyncTables(path);
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
