import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/accounts/account_auth.dart';
import 'package:livenow/data/accounts/account_registry.dart';
import 'package:livenow/data/accounts/profile_paths.dart';
import 'package:livenow/data/accounts/totp.dart';
import 'package:livenow/ui/accounts/account_gate.dart';
import 'package:livenow/ui/accounts/account_providers.dart';
import 'package:livenow/ui/accounts/account_session.dart';
import 'package:livenow/ui/accounts/account_settings.dart';

/// The account gate: first run, auto sign-in, the picker, passwords, 2FA, the
/// lockout, the keyed scope on a switch, and sync only for the main account.
/// A temp root and a stand-in app: never the real data.
void main() {
  late Directory root;
  const iterations = 1000;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('livenow_gate_');
  });
  tearDown(() async {
    activeProfileDirectory = null;
    await root.delete(recursive: true);
  });

  /// Real time for the file I/O and the key-derivation isolate, between pumps.
  Future<void> settle(WidgetTester tester, [int rounds = 8]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> until(WidgetTester tester, Finder f, {int max = 40}) async {
    for (var i = 0; i < max && f.evaluate().isEmpty; i++) {
      await settle(tester, 1);
    }
  }

  /// A stand-in for the app: shows the account, its folder and whether sync is
  /// allowed, and has a Sign out button like Settings has.
  Widget standIn(BuildContext context, account) => MaterialApp(
    home: Scaffold(
      body: Consumer(
        builder: (context, ref, _) => Column(
          children: [
            Text('APP ${account.name}', key: const ValueKey('app-name')),
            Text(
              'DIR ${activeProfileDirectory?.path.replaceAll(root.path, '<root>')}',
              key: const ValueKey('app-dir'),
            ),
            Text(
              'SYNC ${ref.watch(syncAllowedProvider)}',
              key: const ValueKey('app-sync'),
            ),
            TextButton(
              key: const ValueKey('app-signout'),
              onPressed: AccountSessionScope.maybeOf(context)!.signOut,
              child: const Text('sign out'),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AccountGate(
        initialTheme: ThemeMode.light,
        root: root,
        kdfIterations: iterations,
        appBuilder: standIn,
      ),
    );
    await settle(tester);
  }

  Future<AccountRegistry> reg() async =>
      (await AccountRegistry.load(root))!;

  Text text(WidgetTester t, String key) =>
      t.widget<Text>(find.byKey(ValueKey(key)));

  testWidgets('a new install asks for a name, then opens the app', (tester) async {
    await mount(tester);
    expect(find.byKey(const ValueKey('first-run-name')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('first-run-name')), 'Ann');
    await tester.tap(find.byKey(const ValueKey('first-run-ok')));
    await until(tester, find.byKey(const ValueKey('app-name')));
    expect(text(tester, 'app-name').data, 'APP Ann');
    expect(text(tester, 'app-dir').data, 'DIR <root>');
    expect(text(tester, 'app-sync').data, 'SYNC true');
    final r = await tester.runAsync(reg);
    expect(r!.accounts.single.isMain, isTrue);
  });

  testWidgets('one account without a password opens straight in (no picker)', (tester) async {
    await tester.runAsync(() => AccountRegistry.empty(root).addMain('Me'));
    await mount(tester);
    expect(find.byKey(const ValueKey('app-name')), findsOneWidget);
    expect(find.text('Who is using LiveNow?'), findsNothing);
  });

  testWidgets('sign out shows the picker; another account gets its own folder and no sync', (tester) async {
    final guest = (await tester.runAsync(() async {
      final r = AccountRegistry.empty(root);
      await r.addMain('Main');
      return r.create('Guest');
    }))!;
    await mount(tester);
    // The last (and first) account has no password: straight in.
    expect(text(tester, 'app-name').data, 'APP Main');
    expect(text(tester, 'app-sync').data, 'SYNC true');

    await tester.tap(find.byKey(const ValueKey('app-signout')));
    await settle(tester, 3);
    expect(find.text('Who is using LiveNow?'), findsOneWidget);
    expect(activeProfileDirectory, isNull);
    expect(find.byKey(ValueKey('account-card-${guest.id}')), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('account-card-${guest.id}')));
    await until(tester, find.byKey(const ValueKey('app-name')));
    expect(text(tester, 'app-name').data, 'APP Guest');
    expect(text(tester, 'app-dir').data, contains('profiles'));
    expect(text(tester, 'app-dir').data, contains(guest.id));
    // Sync belongs to the main account only.
    expect(text(tester, 'app-sync').data, 'SYNC false');
    // The picker remembers who signed in last.
    expect((await tester.runAsync(reg))!.lastAccountId, guest.id);
  });

  testWidgets('a password: wrong first, then right; the app opens', (tester) async {
    final a = (await tester.runAsync(() async {
      final r = AccountRegistry.empty(root);
      final a = await r.addMain('Ann');
      await AccountAuth(r, iterations: iterations).setPassword(a.id, 'correct horse');
      return a;
    }))!;
    await mount(tester);
    expect(find.text('Who is using LiveNow?'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('account-card-${a.id}')));
    await settle(tester, 2);
    await tester.enterText(find.byKey(const ValueKey('account-password-field')), 'nope');
    await tester.tap(find.byKey(const ValueKey('account-password-ok')));
    await until(tester, find.text('Wrong password.'));
    expect(find.text('Wrong password.'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('account-password-field')), 'correct horse');
    await tester.tap(find.byKey(const ValueKey('account-password-ok')));
    await until(tester, find.byKey(const ValueKey('app-name')));
    expect(text(tester, 'app-name').data, 'APP Ann');
  });

  testWidgets('too many wrong passwords lock the account', (tester) async {
    final a = (await tester.runAsync(() async {
      final r = AccountRegistry.empty(root);
      final a = await r.addMain('Ann');
      await AccountAuth(r, iterations: iterations).setPassword(a.id, 'correct horse');
      return a;
    }))!;
    await mount(tester);
    await tester.tap(find.byKey(ValueKey('account-card-${a.id}')));
    await settle(tester, 2);
    for (var i = 0; i < 5; i++) {
      await tester.enterText(find.byKey(const ValueKey('account-password-field')), 'bad$i');
      await tester.tap(find.byKey(const ValueKey('account-password-ok')));
      // One pump clears the previous error; then wait for THIS attempt's answer
      // (the derivation runs in an isolate).
      await tester.pump();
      await until(
        tester,
        find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              w.decoration?.errorText != null,
        ),
        max: 80,
      );
      await settle(tester, 1);
    }
    expect(find.textContaining('Too many wrong tries'), findsOneWidget);
    // Even the right password is refused during the delay.
    await tester.enterText(find.byKey(const ValueKey('account-password-field')), 'correct horse');
    await tester.tap(find.byKey(const ValueKey('account-password-ok')));
    await settle(tester, 4);
    expect(find.byKey(const ValueKey('app-name')), findsNothing);
  });

  testWidgets('2FA: the password is followed by a code; a wrong code is refused', (tester) async {
    final setup = (await tester.runAsync(() async {
      final r = AccountRegistry.empty(root);
      final a = await r.addMain('Ann');
      final auth = AccountAuth(r, iterations: iterations);
      await auth.setPassword(a.id, 'correct horse');
      final key = (await auth.checkPassword(a.id, 'correct horse')).key!;
      final enrol = auth.beginTwoFactor('Ann');
      final first = await totpCodeForStep(enrol.secret, totpStep(DateTime.now()));
      await auth.enableTwoFactor(a.id, key, enrol, first);
      return (a, enrol);
    }))!;
    final a = setup.$1;
    final enrol = setup.$2;

    await mount(tester);
    await tester.tap(find.byKey(ValueKey('account-card-${a.id}')));
    await settle(tester, 2);
    await tester.enterText(find.byKey(const ValueKey('account-password-field')), 'correct horse');
    await tester.tap(find.byKey(const ValueKey('account-password-ok')));
    await until(tester, find.byKey(const ValueKey('account-code-field')));

    await tester.enterText(find.byKey(const ValueKey('account-code-field')), '000000');
    await tester.tap(find.byKey(const ValueKey('account-code-ok')));
    await until(tester, find.textContaining('Wrong code'));
    expect(find.textContaining('Wrong code'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-name')), findsNothing);

    // The next 30-second code (the enrolment code itself is used up).
    final code = await tester.runAsync(
      () => totpCodeForStep(enrol.secret, totpStep(DateTime.now()) + 1),
    );
    await tester.enterText(find.byKey(const ValueKey('account-code-field')), code!);
    await tester.tap(find.byKey(const ValueKey('account-code-ok')));
    await until(tester, find.byKey(const ValueKey('app-name')));
    expect(text(tester, 'app-name').data, 'APP Ann');
  });

  testWidgets('Add account on the picker creates a local account and opens it', (tester) async {
    (await tester.runAsync(() async {
      final r = AccountRegistry.empty(root);
      final a = await r.addMain('Ann');
      await AccountAuth(r, iterations: iterations).setPassword(a.id, 'correct horse');
      return a;
    }))!;
    await mount(tester);

    await tester.tap(find.byKey(const ValueKey('account-add')));
    await settle(tester, 2);
    await tester.enterText(find.byKey(const ValueKey('account-new-name')), 'Bob');
    await tester.enterText(find.byKey(const ValueKey('account-new-password')), 'short');
    await tester.enterText(find.byKey(const ValueKey('account-new-repeat')), 'short');
    await tester.tap(find.byKey(const ValueKey('account-new-ok')));
    await settle(tester, 2);
    expect(find.textContaining('at least 8'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('account-new-password')), 'longer password');
    await tester.enterText(find.byKey(const ValueKey('account-new-repeat')), 'longer password');
    await tester.tap(find.byKey(const ValueKey('account-new-ok')));
    await until(tester, find.byKey(const ValueKey('app-name')));
    expect(text(tester, 'app-name').data, 'APP Bob');
    final after = (await tester.runAsync(reg))!;
    expect(after.accounts.map((x) => x.name), ['Ann', 'Bob']);
    expect(after.accounts.last.syncAllowed, isFalse);
    expect(after.accounts.last.hasPassword, isTrue);
  });

  testWidgets('a damaged registry stops with a message and never overwrites it', (tester) async {
    await tester.runAsync(() => AccountRegistry.fileIn(root).writeAsString('{broken'));
    await mount(tester);
    expect(find.byKey(const ValueKey('account-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('first-run-name')), findsNothing);
    expect(
      await tester.runAsync(() => AccountRegistry.fileIn(root).readAsString()),
      '{broken',
    );
  });

  testWidgets('Settings: rename, and delete a second account (only its folder goes)', (tester) async {
    final guest = (await tester.runAsync(() async {
      final r = AccountRegistry.empty(root);
      await r.addMain('Main');
      final g = await r.create('Guest');
      await File('${r.profileDir(g).path}${Platform.pathSeparator}mine.txt').writeAsString('x');
      await File('${root.path}${Platform.pathSeparator}main_data.txt').writeAsString('y');
      await r.setLast(g.id);
      return g;
    }))!;
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AccountGate(
        initialTheme: ThemeMode.light,
        root: root,
        kdfIterations: iterations,
        appBuilder: (context, account) => MaterialApp(
          home: Scaffold(body: ListView(children: const [AccountSettingsSection()])),
        ),
      ),
    );
    await settle(tester);
    expect(find.text('Guest'), findsOneWidget);
    expect(find.byKey(const ValueKey('account-delete')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('account-rename')));
    await settle(tester, 2);
    await tester.enterText(find.byKey(const ValueKey('account-rename-field')), 'Visitor');
    await tester.tap(find.byKey(const ValueKey('account-rename-ok')));
    await until(
      tester,
      find.descendant(
        of: find.byKey(const ValueKey('account-current')),
        matching: find.text('Visitor'),
      ),
    );
    expect((await tester.runAsync(reg))!.byId(guest.id)!.name, 'Visitor');

    // A wrong confirmation name deletes nothing.
    await tester.tap(find.byKey(const ValueKey('account-delete')));
    await settle(tester, 2);
    await tester.enterText(find.byKey(const ValueKey('account-delete-field')), 'Guest');
    await tester.tap(find.byKey(const ValueKey('account-delete-ok')));
    await settle(tester, 4);
    expect((await tester.runAsync(reg))!.byId(guest.id), isNotNull);

    await tester.tap(find.byKey(const ValueKey('account-delete')));
    await settle(tester, 2);
    await tester.enterText(find.byKey(const ValueKey('account-delete-field')), 'Visitor');
    await tester.tap(find.byKey(const ValueKey('account-delete-ok')));
    // Signing out, a short wait for the database to close, then the folder goes.
    for (var i = 0; i < 20; i++) {
      await settle(tester, 1);
      final gone = await tester.runAsync(
        () async => (await AccountRegistry.load(root))!.byId(guest.id) == null,
      );
      if (gone == true) break;
    }
    await settle(tester, 3);
    final after = (await tester.runAsync(reg))!;
    expect(after.byId(guest.id), isNull);
    expect(after.accounts.map((a) => a.name), ['Main']);
    final dirs = await tester.runAsync(() async => (
      Directory('${root.path}${Platform.pathSeparator}profiles${Platform.pathSeparator}${guest.id}').exists(),
      File('${root.path}${Platform.pathSeparator}main_data.txt').exists(),
    ).$1.then((g) async => (g, await File('${root.path}${Platform.pathSeparator}main_data.txt').exists())));
    expect(dirs!.$1, isFalse);
    expect(dirs.$2, isTrue);
  });

  testWidgets('Settings: set a password, turn on 2FA, new codes, remove', (tester) async {
    await tester.runAsync(() => AccountRegistry.empty(root).addMain('Ann'));
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AccountGate(
        initialTheme: ThemeMode.light,
        root: root,
        kdfIterations: iterations,
        appBuilder: (context, account) => MaterialApp(
          home: Scaffold(body: ListView(children: const [AccountSettingsSection()])),
        ),
      ),
    );
    await settle(tester);
    expect(find.byKey(const ValueKey('account-current')), findsOneWidget);
    // Main account: no delete.
    expect(find.byKey(const ValueKey('account-delete')), findsNothing);
    // No password yet: no 2FA entry.
    expect(find.byKey(const ValueKey('account-2fa-on')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('account-set-password')));
    await settle(tester, 2);
    await tester.enterText(find.byKey(const ValueKey('account-pw-new')), 'correct horse');
    await tester.enterText(find.byKey(const ValueKey('account-pw-repeat')), 'correct horse');
    await tester.tap(find.byKey(const ValueKey('account-pw-ok')));
    await until(tester, find.byKey(const ValueKey('account-2fa-on')));
    expect(find.byKey(const ValueKey('account-change-password')), findsOneWidget);

    // 2FA: confirm the password, scan, give the first code, get ten codes.
    await tester.tap(find.byKey(const ValueKey('account-2fa-on')));
    await settle(tester, 2);
    await tester.enterText(find.byKey(const ValueKey('account-password-field')), 'correct horse');
    await tester.tap(find.byKey(const ValueKey('account-password-ok')));
    await until(tester, find.byKey(const ValueKey('account-2fa-key')));
    final typed = tester.widget<SelectableText>(find.byKey(const ValueKey('account-2fa-key'))).data!;
    final secret = base32Decode(typed)!;
    final code = await tester.runAsync(
      () => totpCodeForStep(secret, totpStep(DateTime.now())),
    );
    await tester.enterText(find.byKey(const ValueKey('account-2fa-code')), code!);
    await tester.tap(find.byKey(const ValueKey('account-2fa-verify')));
    await until(tester, find.byKey(const ValueKey('account-recovery-codes')));
    final shown = tester.widget<SelectableText>(find.byKey(const ValueKey('account-recovery-codes'))).data!;
    expect(shown.split('\n'), hasLength(10));
    await tester.tap(find.byKey(const ValueKey('account-recovery-done')));
    await settle(tester, 3);
    expect((await tester.runAsync(reg))!.accounts.single.hasTwoFactor, isTrue);
    expect(find.byKey(const ValueKey('account-2fa-off')), findsOneWidget);
    expect(find.text('10 unused codes left'), findsOneWidget);
  });
}
