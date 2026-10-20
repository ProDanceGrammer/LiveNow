import 'dart:io';

import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../database.dart';
import '../sync/sync_backup.dart' show backupDatabase;
import 'account_registry.dart';

/// The safety copy of the existing data could not be made or did not verify, so
/// nothing was changed (no `accounts.json` was written).
class AdoptionException implements Exception {
  const AdoptionException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What the account gate starts from.
class AccountsStart {
  const AccountsStart(this.registry, {required this.needsFirstRun});

  final AccountRegistry registry;

  /// A new install: there are no accounts and no data yet, so the first-run
  /// screen asks for a name and creates the main account.
  final bool needsFirstRun;
}

/// The database file of a profile folder (drift's `livenow` + `.sqlite`).
File databaseFileIn(Directory dir) =>
    File('${dir.path}${Platform.pathSeparator}livenow.sqlite');

/// Loads the registry; when there is none yet it ADOPTS the data that existed
/// before accounts did as the main account, WITHOUT moving anything: the main
/// account's folder is the root itself.
///
/// Before `accounts.json` is written one safety copy of the database is made
/// (`VACUUM INTO` into `livenow_backups`) and verified (it opens and passes
/// `integrity_check`); if that fails an [AdoptionException] is thrown and
/// nothing is changed. A second call finds the registry and does nothing.
/// A registry that exists but cannot be read throws [AccountRegistryException]
/// (it is never silently replaced).
Future<AccountsStart> loadOrAdoptRegistry(Directory root) async {
  final existing = await AccountRegistry.load(root);
  if (existing != null) return AccountsStart(existing, needsFirstRun: false);

  final registry = AccountRegistry.empty(root);
  if (!await databaseFileIn(root).exists()) {
    return AccountsStart(registry, needsFirstRun: true);
  }
  await _safetyCopy(root);
  await registry.addMain('Me');
  return AccountsStart(registry, needsFirstRun: false);
}

Future<void> _safetyCopy(Directory root) async {
  final backups = await Directory(
    '${root.path}${Platform.pathSeparator}livenow_backups',
  ).create(recursive: true);
  String path;
  final db = AppDatabase.inDirectory(root);
  try {
    path = await backupDatabase(db, backups, label: 'before-accounts');
  } on Object catch (e) {
    throw AdoptionException(
      'The safety copy of your data could not be made ($e). Nothing was '
      'changed.',
    );
  } finally {
    await db.close();
  }
  _verifyCopy(path);
}

void _verifyCopy(String path) {
  sqlite.Database? copy;
  try {
    copy = sqlite.sqlite3.open(path, mode: sqlite.OpenMode.readOnly);
    final check = copy.select('PRAGMA integrity_check');
    final ok = check.length == 1 && check.first.values.first == 'ok';
    final tables = copy.select(
      "SELECT count(*) AS n FROM sqlite_master WHERE type = 'table'",
    );
    if (!ok || (tables.first['n'] as int) < 1) {
      throw const AdoptionException('The safety copy failed its check.');
    }
  } on AdoptionException {
    rethrow;
  } on Object catch (e) {
    throw AdoptionException('The safety copy could not be opened ($e).');
  } finally {
    copy?.close();
  }
}
