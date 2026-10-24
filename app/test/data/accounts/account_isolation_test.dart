import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/accounts/account_auth.dart';
import 'package:livenow/data/accounts/account_models.dart';
import 'package:livenow/data/accounts/account_registry.dart';
import 'package:livenow/data/accounts/profile_paths.dart';
import 'package:livenow/data/accounts/totp.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/accounts/account_gate.dart';
import 'package:livenow/ui/accounts/account_session.dart';

/// One account can never reach another's data: separate database files, folder
/// names that cannot climb out, deleted accounts that are really gone, and a
/// password / second factor / lockout that never hands out a key by mistake.
/// Temp folders only.
void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => Directory.systemTemp.path,
        );
    initPostponeTimeZoneData();
  });

  late Directory root;
  const iterations = 1000;

  setUp(() async => root = await Directory.systemTemp.createTemp('livenow_iso_'));
  tearDown(() async {
    activeProfileDirectory = null;
    await root.delete(recursive: true);
  });

  group('databases', () {
    test('rows written in account B are invisible to account A (and the main root)', () async {
      final reg = AccountRegistry.empty(root);
      final main = await reg.addMain('Main');
      final b = await reg.create('B');
      final c = await reg.create('C');
      final dbMain = AppDatabase.inDirectory(reg.profileDir(main));
      final dbB = AppDatabase.inDirectory(reg.profileDir(b));
      final dbC = AppDatabase.inDirectory(reg.profileDir(c));
      addTearDown(() async {
        await dbMain.close();
        await dbB.close();
        await dbC.close();
      });
      await ActionService(dbB).createAction(name: 'B private');
      await ActionService(dbMain).createAction(name: 'Main private');

      Future<List<String>> names(AppDatabase d) async => [
        for (final r in await d.customSelect('SELECT name FROM actions').get())
          r.read<String>('name'),
      ];
      expect(await names(dbB), ['B private']);
      expect(await names(dbMain), ['Main private']);
      expect(await names(dbC), isEmpty);
      expect(
        databaseFileInPath(reg.profileDir(b)),
        isNot(databaseFileInPath(reg.profileDir(main))),
      );
      // The main account IS the root; a profile is a separate folder below it.
      expect(reg.profileDir(main).path, root.path);
      expect(reg.profileDir(b).path, startsWith('${root.path}${Platform.pathSeparator}profiles'));
    });

    test('a default AppDatabase opens the signed-in account folder, captured at creation', () async {
      final reg = AccountRegistry.empty(root);
      await reg.addMain('Main');
      final b = await reg.create('B');
      activeProfileDirectory = reg.profileDir(b);
      final db = AppDatabase();
      addTearDown(db.close);
      await ActionService(db).createAction(name: 'in B');
      // A later switch does not redirect the instance that already exists.
      activeProfileDirectory = root;
      expect(
        (await db.customSelect('SELECT name FROM actions').get()).single.read<String>('name'),
        'in B',
      );
      expect(File(databaseFileInPath(reg.profileDir(b))).existsSync(), isTrue);
    });
  });

  group('folder names', () {
    Account? parse(String dir) =>
        Account.fromJson({'id': 'x', 'name': 'N', 'dir': dir, 'sync': true});

    test('names that could leave profiles/ are refused', () {
      for (final bad in [
        '..',
        '../x',
        r'..\x',
        'a/../b',
        r'a\..\..\b',
        '/etc',
        r'\windows',
        'C:',
        r'C:\Users',
        'c:/x',
        '',
        'x:y',
        '....//',
      ]) {
        expect(parse(bad), isNull, reason: 'dir "$bad"');
      }
    });

    test('ordinary names pass, and only "." is the main account', () {
      expect(parse('0190-abc')!.isMain, isFalse);
      expect(parse('.')!.isMain, isTrue);
      expect(parse('.hidden')!.isMain, isFalse);
    });

    test('a registry file with a hostile entry loses just that entry', () async {
      await reg2(root, [
        {'id': 'ok', 'name': 'Fine', 'dir': '.', 'sync': true, 'created': ''},
        {'id': 'evil', 'name': 'Evil', 'dir': '../../outside', 'created': ''},
        {'id': 'abs', 'name': 'Abs', 'dir': '/tmp/x', 'created': ''},
      ]);
      final r = (await AccountRegistry.load(root))!;
      expect(r.accounts.map((a) => a.id), ['ok']);
    });

    test('a registry whose every account is hostile is damaged, never "no accounts"', () async {
      await reg2(root, [
        {'id': 'evil', 'name': 'Evil', 'dir': '..', 'created': ''},
      ]);
      await expectLater(
        AccountRegistry.load(root),
        throwsA(isA<AccountRegistryException>()),
      );
    });
  });

  group('removing an account', () {
    test('its folder and entry are gone, nothing else is touched, it cannot sign in', () async {
      final reg = AccountRegistry.empty(root);
      final main = await reg.addMain('Main');
      final b = await reg.create('B');
      final keep = await reg.create('Keep');
      final bDir = reg.profileDir(b);
      await File('${bDir.path}${Platform.pathSeparator}secret.txt').writeAsString('s');
      await File('${root.path}${Platform.pathSeparator}main.txt').writeAsString('m');
      await File('${reg.profileDir(keep).path}${Platform.pathSeparator}k.txt').writeAsString('k');
      final auth = AccountAuth(reg, iterations: iterations);
      await auth.setPassword(b.id, 'correct horse');

      await reg.delete(b.id);
      expect(bDir.existsSync(), isFalse);
      expect(File('${root.path}${Platform.pathSeparator}main.txt').existsSync(), isTrue);
      expect(File('${reg.profileDir(keep).path}${Platform.pathSeparator}k.txt').existsSync(), isTrue);
      expect(reg.byId(b.id), isNull);
      expect((await AccountRegistry.load(root))!.byId(b.id), isNull);
      expect(reg.main, isNotNull);
      expect(main.isMain, isTrue);
      // Unreachable by id: no key, no check.
      await expectLater(
        auth.checkPassword(b.id, 'correct horse'),
        throwsA(isA<StateError>()),
      );
    });

    test('the main account (the root itself) can never be deleted', () async {
      final reg = AccountRegistry.empty(root);
      final main = await reg.addMain('Main');
      await File('${root.path}${Platform.pathSeparator}main.txt').writeAsString('m');
      await expectLater(reg.delete(main.id), throwsA(isA<StateError>()));
      expect(File('${root.path}${Platform.pathSeparator}main.txt').existsSync(), isTrue);
    });

    test('deleting an unknown id does nothing', () async {
      final reg = AccountRegistry.empty(root);
      await reg.addMain('Main');
      await reg.delete('no-such-id');
      expect(reg.accounts, hasLength(1));
    });
  });

  group('password, second factor, lockout', () {
    late AccountRegistry reg;
    late Account a;
    var now = DateTime.utc(2026, 10, 24, 12);
    late AccountAuth auth;

    setUp(() async {
      now = DateTime.utc(2026, 10, 24, 12);
      reg = AccountRegistry.empty(root);
      a = await reg.addMain('Ann');
      auth = AccountAuth(reg, iterations: iterations, clock: () => now);
      await auth.setPassword(a.id, 'correct horse');
    });

    test('a wrong password never returns a key', () async {
      final r = await auth.checkPassword(a.id, 'nope');
      expect(r.ok, isFalse);
      expect(r.key, isNull);
      expect(r.status, CheckStatus.wrong);
    });

    test('a locked account refuses even the right password, until the delay passes', () async {
      for (var i = 0; i < AccountAuth.freeAttempts; i++) {
        await auth.checkPassword(a.id, 'bad$i');
      }
      final locked = await auth.checkPassword(a.id, 'correct horse');
      expect(locked.status, CheckStatus.locked);
      expect(locked.key, isNull);
      expect(locked.lockedUntil, isNotNull);

      // A restart does not help: a fresh AccountAuth over the saved registry.
      final again = AccountRegistry.load(root);
      final reloaded = AccountAuth((await again)!, iterations: iterations, clock: () => now);
      expect((await reloaded.checkPassword(a.id, 'correct horse')).status, CheckStatus.locked);

      now = now.add(const Duration(minutes: 2));
      final ok = await reloaded.checkPassword(a.id, 'correct horse');
      expect(ok.ok, isTrue);
      expect(ok.key, isNotNull);
    });

    test('the delay grows with each further wrong try, capped at an hour', () {
      expect(AccountAuth.lockoutFor(4), Duration.zero);
      expect(AccountAuth.lockoutFor(5), const Duration(seconds: 30));
      expect(AccountAuth.lockoutFor(6), const Duration(seconds: 60));
      expect(AccountAuth.lockoutFor(500), const Duration(hours: 1));
    });

    test('an authenticator code works once: replaying it is refused', () async {
      final key = (await auth.checkPassword(a.id, 'correct horse')).key!;
      final enrol = auth.beginTwoFactor('Ann');
      final first = await totpCodeForStep(enrol.secret, totpStep(now));
      await auth.enableTwoFactor(a.id, key, enrol, first);

      final next = await totpCodeForStep(enrol.secret, totpStep(now) + 1);
      now = now.add(const Duration(seconds: 30));
      final ok = await auth.checkSecondFactor(a.id, key, next);
      expect(ok.ok, isTrue);
      // The very same code again (even moments later) is a replay.
      final replay = await auth.checkSecondFactor(a.id, key, next);
      expect(replay.ok, isFalse);
      // So is the enrolment code.
      expect((await auth.checkSecondFactor(a.id, key, first)).ok, isFalse);
    });

    test('a wrong second factor with a right password still opens nothing and counts', () async {
      final key = (await auth.checkPassword(a.id, 'correct horse')).key!;
      final enrol = auth.beginTwoFactor('Ann');
      await auth.enableTwoFactor(
        a.id,
        key,
        enrol,
        await totpCodeForStep(enrol.secret, totpStep(now)),
      );
      for (var i = 0; i < AccountAuth.freeAttempts; i++) {
        expect((await auth.checkSecondFactor(a.id, key, '00000$i')).ok, isFalse);
      }
      final r = await auth.checkSecondFactor(a.id, key, '123456');
      expect(r.status, CheckStatus.locked);
      // The password is refused as well now: one shared lockout.
      expect((await auth.checkPassword(a.id, 'correct horse')).status, CheckStatus.locked);
    });

    test('an account created with a password is closed until its first sign-in', () async {
      final b = await reg.create('B');
      await auth.setPassword(b.id, 'another long one');
      expect(reg.byId(b.id)!.hasPassword, isTrue);
      expect((await auth.checkPassword(b.id, '')).ok, isFalse);
      expect((await auth.checkPassword(b.id, 'correct horse')).ok, isFalse);
    });

    test('an account without a password reports noPassword, never a key', () async {
      final b = await reg.create('B');
      final r = await auth.checkPassword(b.id, 'anything');
      expect(r.status, CheckStatus.noPassword);
      expect(r.key, isNull);
    });

    test('a damaged security block reads as no password (documented: never locks the owner out)', () {
      final acc = Account.fromJson({
        'id': 'x',
        'name': 'N',
        'dir': 'abc',
        'security': {'iter': 0, 'salt': 1},
      })!;
      expect(acc.hasPassword, isFalse);
    });
  });

  group('the gate', () {
    testWidgets('sign-out clears the active folder; each sign-in gets a fresh provider scope', (tester) async {
      final reg = AccountRegistry.empty(root);
      await tester.runAsync(() async {
        await reg.addMain('Main');
        await reg.create('Guest');
      });
      final counter = NotifierProvider<_Counter, int>(_Counter.new);
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      Future<void> settle([int n = 8]) async {
        for (var i = 0; i < n; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      await tester.pumpWidget(
        AccountGate(
          initialTheme: ThemeMode.light,
          root: root,
          kdfIterations: iterations,
          appBuilder: (context, account) => MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => Column(
                  children: [
                    Text('${account.name}:${ref.watch(counter)}', key: const ValueKey('state')),
                    TextButton(
                      key: const ValueKey('bump'),
                      onPressed: () => ref.read(counter.notifier).bump(),
                      child: const Text('bump'),
                    ),
                    TextButton(
                      key: const ValueKey('out'),
                      onPressed: AccountSessionScope.maybeOf(context)!.signOut,
                      child: const Text('out'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await settle();
      expect((tester.widget(find.byKey(const ValueKey('state'))) as Text).data, 'Main:0');
      await tester.tap(find.byKey(const ValueKey('bump')));
      await tester.pump();
      expect((tester.widget(find.byKey(const ValueKey('state'))) as Text).data, 'Main:1');
      expect(activeProfileDirectory, isNotNull);

      await tester.tap(find.byKey(const ValueKey('out')));
      await settle(3);
      expect(activeProfileDirectory, isNull);
      expect(find.byKey(const ValueKey('state')), findsNothing);

      // Back in as the same account: the old scope is gone, state starts at 0.
      final main = reg.main!;
      await tester.tap(find.byKey(ValueKey('account-card-${main.id}')));
      await settle();
      expect((tester.widget(find.byKey(const ValueKey('state'))) as Text).data, 'Main:0');
    });
  });
}

String databaseFileInPath(Directory dir) =>
    '${dir.path}${Platform.pathSeparator}livenow.sqlite';

Future<void> reg2(Directory root, List<Map<String, Object?>> accounts) async {
  await root.create(recursive: true);
  await AccountRegistry.fileIn(root).writeAsString(
    jsonEncode({'v': 1, 'accounts': accounts}),
  );
}

class _Counter extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}
