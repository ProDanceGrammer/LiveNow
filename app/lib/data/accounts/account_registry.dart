import 'dart:convert';
import 'dart:io';

import '../../core/ids.dart';
import '../../core/time_codec.dart';
import 'account_models.dart';

/// `accounts.json` could not be read and neither could its backup copy. The
/// app must NOT carry on as if there were no accounts (adoption would write a
/// new registry over it).
class AccountRegistryException implements Exception {
  const AccountRegistryException(this.message);
  final String message;
  @override
  String toString() => message;
}

String _join(String a, String b) => '$a${Platform.pathSeparator}$b';

/// The list of local accounts, kept in `accounts.json` in the app-support root.
/// Pure Dart over a root [Directory] (tests give it a temp folder).
///
/// Layout: the account that adopted the pre-accounts data has `dirName = '.'`
/// (the root itself, nothing moves); every other account lives in
/// `profiles/<id>/`.
class AccountRegistry {
  AccountRegistry._(this.root, this._accounts, this.lastAccountId);

  /// A registry with no accounts yet, not written until [save].
  AccountRegistry.empty(this.root) : _accounts = [], lastAccountId = null;

  final Directory root;
  final List<Account> _accounts;

  /// The account that signed in last (the picker starts on it).
  String? lastAccountId;

  List<Account> get accounts => List.unmodifiable(_accounts);

  static File fileIn(Directory root) => File(_join(root.path, 'accounts.json'));
  static File _backupIn(Directory root) =>
      File(_join(root.path, 'accounts.json.bak'));

  /// Null when there is no registry yet (an install from before accounts, or a
  /// new one); throws [AccountRegistryException] when it exists but cannot be
  /// read (the `.bak` copy is tried first).
  static Future<AccountRegistry?> load(Directory root) async {
    final main = fileIn(root);
    final bak = _backupIn(root);
    if (!await main.exists() && !await bak.exists()) return null;
    for (final f in [main, bak]) {
      if (!await f.exists()) continue;
      final parsed = _parse(root, await f.readAsString());
      if (parsed != null) return parsed;
    }
    throw const AccountRegistryException(
      'accounts.json is damaged and its backup copy could not be read.',
    );
  }

  static AccountRegistry? _parse(Directory root, String text) {
    Object? j;
    try {
      j = jsonDecode(text);
    } on Object {
      return null;
    }
    if (j is! Map || j['accounts'] is! List) return null;
    final accounts = <Account>[];
    for (final a in j['accounts'] as List) {
      final account = Account.fromJson(a);
      if (account != null && !accounts.any((x) => x.id == account.id)) {
        accounts.add(account);
      }
    }
    if (accounts.isEmpty) return null;
    final last = j['last'];
    return AccountRegistry._(
      root,
      accounts,
      last is String && accounts.any((a) => a.id == last) ? last : null,
    );
  }

  Account? byId(String? id) {
    for (final a in _accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  Account? get main {
    for (final a in _accounts) {
      if (a.isMain) return a;
    }
    return null;
  }

  /// Where the files of [account] live.
  Directory profileDir(Account account) => account.isMain
      ? root
      : Directory(_join(_join(root.path, 'profiles'), account.dirName));

  /// Writes the registry atomically: the previous file is kept as
  /// `accounts.json.bak`, the new one is written to a temp file and renamed.
  Future<void> save() async {
    await root.create(recursive: true);
    final main = fileIn(root);
    if (await main.exists()) {
      await main.copy(_backupIn(root).path);
    }
    final tmp = File('${main.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({
        'v': 1,
        if (lastAccountId != null) 'last': lastAccountId,
        'accounts': [for (final a in _accounts) a.toJson()],
      }),
      flush: true,
    );
    await tmp.rename(main.path);
  }

  /// Adds the account that adopts the data that existed before accounts (its
  /// folder is the root itself) and saves.
  Future<Account> addMain(String name) async {
    final account = Account(
      id: newId(),
      name: name.trim().isEmpty ? 'Me' : name.trim(),
      dirName: '.',
      syncAllowed: true,
      createdAt: dateTimeToDb(DateTime.now().toUtc())!,
    );
    _accounts.add(account);
    lastAccountId ??= account.id;
    await save();
    return account;
  }

  /// A new local-only account with its own folder under `profiles/`.
  Future<Account> create(String name) async {
    final id = newId();
    final account = Account(
      id: id,
      name: name.trim().isEmpty ? 'Account' : name.trim(),
      dirName: id,
      syncAllowed: false,
      createdAt: dateTimeToDb(DateTime.now().toUtc())!,
    );
    await profileDir(account).create(recursive: true);
    _accounts.add(account);
    await save();
    return account;
  }

  /// Replaces the stored account with the same id (a rename, a new password...).
  Future<void> update(Account account) async {
    final i = _accounts.indexWhere((a) => a.id == account.id);
    if (i < 0) throw StateError('unknown account');
    _accounts[i] = account;
    await save();
  }

  Future<void> setLast(String id) async {
    if (lastAccountId == id) return;
    lastAccountId = id;
    await save();
  }

  /// Removes a non-main account and ONLY its profile folder. The main account
  /// holds the data that predates accounts (and the root itself): it is never
  /// deleted here.
  Future<void> delete(String id) async {
    final account = byId(id);
    if (account == null) return;
    if (account.isMain) throw StateError('the main account cannot be deleted');
    final dir = profileDir(account);
    // Belt and braces: only ever delete something directly under profiles/.
    final profiles = _join(root.path, 'profiles');
    if (!dir.path.startsWith(profiles) || dir.path == profiles) {
      throw StateError('refusing to delete outside profiles/');
    }
    _accounts.removeWhere((a) => a.id == id);
    if (lastAccountId == id) lastAccountId = null;
    await save();
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
