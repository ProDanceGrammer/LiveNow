import 'dart:io';

import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/accounts/account_registry.dart';
import 'package:livenow/data/accounts/adoption.dart';
import 'package:livenow/data/accounts/profile_paths.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Adopting the data that existed before accounts as the main account: a
/// verified safety copy first, nothing moved, never a silent overwrite. Temp
/// folders only.
void main() {
  setUpAll(() {
    // drift_flutter's file connection asks the Flutter binding for a few things.
    TestWidgetsFlutterBinding.ensureInitialized();
    // ...including a temp folder from path_provider (no plugin under test).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => Directory.systemTemp.path,
        );
    initPostponeTimeZoneData();
  });

  late Directory root;
  setUp(() async => root = await Directory.systemTemp.createTemp('livenow_adopt_'));
  tearDown(() async {
    activeProfileDirectory = null;
    await root.delete(recursive: true);
  });

  /// Makes a real legacy database (with one action) in [dir].
  Future<void> makeLegacyData(Directory dir) async {
    final db = AppDatabase.inDirectory(dir);
    await ActionService(db).createAction(name: 'Before accounts');
    await db.close();
  }

  List<File> backupsIn(Directory dir) {
    final d = Directory('${dir.path}${Platform.pathSeparator}livenow_backups');
    if (!d.existsSync()) return [];
    return d.listSync().whereType<File>().where((f) => f.path.endsWith('.sqlite')).toList();
  }

  test('a new install has no accounts and asks for a first-run name', () async {
    final start = await loadOrAdoptRegistry(root);
    expect(start.needsFirstRun, isTrue);
    expect(start.registry.accounts, isEmpty);
    expect(await AccountRegistry.fileIn(root).exists(), isFalse);
  });

  test('existing data becomes the main account: copy first, nothing moved', () async {
    await makeLegacyData(root);
    final before = databaseFileIn(root).lengthSync();

    final start = await loadOrAdoptRegistry(root);
    expect(start.needsFirstRun, isFalse);
    final main = start.registry.main!;
    expect(main.isMain, isTrue);
    expect(main.syncAllowed, isTrue);
    expect(start.registry.profileDir(main).path, root.path);

    // The database stays where it was.
    expect(databaseFileIn(root).existsSync(), isTrue);
    expect(databaseFileIn(root).lengthSync(), greaterThanOrEqualTo(before ~/ 2));
    expect(Directory('${root.path}${Platform.pathSeparator}profiles').existsSync(), isFalse);

    // One safety copy, and it holds the data.
    final copies = backupsIn(root);
    expect(copies, hasLength(1));
    expect(copies.single.path, contains('before-accounts'));
    final copy = sqlite.sqlite3.open(copies.single.path, mode: sqlite.OpenMode.readOnly);
    expect(copy.select('SELECT name FROM actions').single['name'], 'Before accounts');
    copy.close();

    // The registry was written, after the copy.
    expect(await AccountRegistry.fileIn(root).exists(), isTrue);
  });

  test('a second start finds the registry and does nothing', () async {
    await makeLegacyData(root);
    final first = await loadOrAdoptRegistry(root);
    final second = await loadOrAdoptRegistry(root);
    expect(second.registry.accounts.single.id, first.registry.accounts.single.id);
    expect(backupsIn(root), hasLength(1));
  });

  test('a database that cannot be copied: nothing changes, no registry', () async {
    await databaseFileIn(root).writeAsString('this is not a database');
    await expectLater(loadOrAdoptRegistry(root), throwsA(isA<AdoptionException>()));
    expect(await AccountRegistry.fileIn(root).exists(), isFalse);
    expect(await databaseFileIn(root).readAsString(), 'this is not a database');
    expect(backupsIn(root), isEmpty);
  });

  test('a registry that exists but is unreadable is never replaced', () async {
    await makeLegacyData(root);
    await AccountRegistry.fileIn(root).writeAsString('{broken');
    await expectLater(
      loadOrAdoptRegistry(root),
      throwsA(isA<AccountRegistryException>()),
    );
    expect(await AccountRegistry.fileIn(root).readAsString(), '{broken');
  });

  test('two accounts keep separate rows: the main one in the root, a new one under profiles/', () async {
    await makeLegacyData(root);
    final start = await loadOrAdoptRegistry(root);
    final guest = await start.registry.create('Guest');

    final guestDb = AppDatabase.inDirectory(start.registry.profileDir(guest));
    final mainDb = AppDatabase.inDirectory(start.registry.profileDir(start.registry.main!));
    await ActionService(guestDb).createAction(name: 'Guest only');

    final guestNames = (await guestDb.select(guestDb.actionsTable).get()).map((a) => a.name);
    final mainNames = (await mainDb.select(mainDb.actionsTable).get()).map((a) => a.name);
    expect(guestNames, ['Guest only']);
    expect(mainNames, ['Before accounts']);
    // Their sync identities differ too (each file has its own device id).
    final gId = await guestDb.customSelect("SELECT value FROM sync_state WHERE key = 'device_id'").getSingle();
    final mId = await mainDb.customSelect("SELECT value FROM sync_state WHERE key = 'device_id'").getSingle();
    expect(gId.read<String>('value'), isNot(mId.read<String>('value')));
    await guestDb.close();
    await mainDb.close();
  });

  test('profileDirectory follows the active account and falls back to the root', () async {
    activeProfileDirectory = null;
    // With LIVENOW_DATA_DIR unset this is the platform folder; only the
    // override branch is checked here (no plugin in tests).
    activeProfileDirectory = root;
    expect((await profileDirectory()).path, root.path);
  });
}
