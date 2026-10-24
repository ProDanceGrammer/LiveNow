import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/accounts/account_auth.dart';
import 'package:livenow/data/accounts/account_registry.dart';
import 'package:livenow/data/accounts/profile_paths.dart';
import 'package:livenow/ui/accounts/account_gate.dart';
import 'package:livenow/ui/accounts/account_settings.dart';
import 'package:livenow/ui/accounts/idle_lock.dart';

/// The idle lock: an account with a password signs itself out after a quiet
/// spell (the "minute" is shortened to one second here), activity resets the
/// wait, Off and passwordless accounts never lock. Temp folders only.
void main() {
  late Directory root;
  const iterations = 1000;
  const unit = Duration(seconds: 1);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('livenow_idle_');
  });
  tearDown(() async {
    activeProfileDirectory = null;
    await root.delete(recursive: true);
  });

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

  Widget standIn(BuildContext context, account) => const MaterialApp(
    home: Scaffold(body: Text('APP', key: ValueKey('app'))),
  );

  Future<void> mount(
    WidgetTester tester, {
    Widget Function(BuildContext, dynamic)? app,
  }) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AccountGate(
        initialTheme: ThemeMode.light,
        root: root,
        kdfIterations: iterations,
        idleUnit: unit,
        appBuilder: app ?? standIn,
      ),
    );
    await settle(tester);
  }

  /// Registry with one main account; a password when [password] is set.
  Future<dynamic> seed(WidgetTester tester, {String? password}) async {
    return tester.runAsync(() async {
      final r = AccountRegistry.empty(root);
      final a = await r.addMain('Ann');
      if (password != null) {
        await AccountAuth(r, iterations: iterations).setPassword(a.id, password);
      }
      return a;
    });
  }

  Future<void> signIn(WidgetTester tester, dynamic a) async {
    await tester.tap(find.byKey(ValueKey('account-card-${a.id}')));
    await settle(tester, 2);
    await tester.enterText(
      find.byKey(const ValueKey('account-password-field')),
      'correct horse',
    );
    await tester.tap(find.byKey(const ValueKey('account-password-ok')));
    await until(tester, find.byKey(const ValueKey('app')));
  }

  group('the saved choice', () {
    test('absent, damaged or unknown reads as 30; a saved one comes back', () async {
      expect(await loadIdleLockMinutes(root), 30);
      await saveIdleLockMinutes(root, 5);
      expect(await loadIdleLockMinutes(root), 5);
      await saveIdleLockMinutes(root, 0);
      expect(await loadIdleLockMinutes(root), 0);
      File('${root.path}/idle_lock.json').writeAsStringSync('{broken');
      expect(await loadIdleLockMinutes(root), 30);
      File('${root.path}/idle_lock.json').writeAsStringSync('{"minutes": 7}');
      expect(await loadIdleLockMinutes(root), 30);
    });

    test('saving into a missing folder does not throw', () async {
      await saveIdleLockMinutes(Directory('${root.path}/nope/deeper'), 15);
      expect(await loadIdleLockMinutes(Directory('${root.path}/nope/deeper')), 15);
    });
  });

  testWidgets('locks at the timeout (default 30) and shows the password prompt', (tester) async {
    final a = await seed(tester, password: 'correct horse');
    await mount(tester);
    await signIn(tester, a);
    expect(activeProfileDirectory, isNotNull);

    await tester.pump(unit * 29);
    expect(find.byKey(const ValueKey('app')), findsOneWidget);
    await tester.pump(unit * 2);
    await settle(tester, 2);
    expect(find.byKey(const ValueKey('app')), findsNothing);
    expect(find.text('Who is using LiveNow?'), findsOneWidget);
    expect(activeProfileDirectory, isNull);

    // The gate asks for the password again.
    await tester.tap(find.byKey(ValueKey('account-card-${a.id}')));
    await settle(tester, 2);
    expect(find.byKey(const ValueKey('account-password-field')), findsOneWidget);
  });

  testWidgets('pointer and key activity reset the wait', (tester) async {
    final a = await seed(tester, password: 'correct horse');
    await tester.runAsync(() => saveIdleLockMinutes(root, 5));
    await mount(tester);
    await signIn(tester, a);

    await tester.pump(unit * 4);
    await tester.tapAt(const Offset(500, 700));
    await tester.pump(unit * 4);
    await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump(unit * 4);
    expect(find.byKey(const ValueKey('app')), findsOneWidget);

    await tester.pump(unit * 2);
    await settle(tester, 2);
    expect(find.byKey(const ValueKey('app')), findsNothing);
  });

  testWidgets('Off never locks', (tester) async {
    final a = await seed(tester, password: 'correct horse');
    await tester.runAsync(() => saveIdleLockMinutes(root, 0));
    await mount(tester);
    await signIn(tester, a);
    await tester.pump(unit * 600);
    expect(find.byKey(const ValueKey('app')), findsOneWidget);
  });

  testWidgets('an account without a password never locks', (tester) async {
    await seed(tester);
    await mount(tester);
    await until(tester, find.byKey(const ValueKey('app')));
    expect(find.byKey(const ValueKey('app')), findsOneWidget);
    await tester.pump(unit * 600);
    expect(find.byKey(const ValueKey('app')), findsOneWidget);
  });

  testWidgets('the lockout state is not reset by a lock', (tester) async {
    final a = await seed(tester, password: 'correct horse');
    await tester.runAsync(() => saveIdleLockMinutes(root, 5));
    await mount(tester);
    await signIn(tester, a);
    await tester.pump(unit * 6);
    await settle(tester, 2);
    expect(find.text('Who is using LiveNow?'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('account-card-${a.id}')));
    await settle(tester, 2);
    for (var i = 0; i < 5; i++) {
      await tester.enterText(
        find.byKey(const ValueKey('account-password-field')),
        'bad$i',
      );
      await tester.tap(find.byKey(const ValueKey('account-password-ok')));
      await tester.pump();
      await until(
        tester,
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.errorText != null,
        ),
        max: 80,
      );
      await settle(tester, 1);
    }
    expect(find.textContaining('Too many wrong tries'), findsOneWidget);
    final reloaded = (await tester.runAsync(
      () => AccountRegistry.load(root),
    ))!;
    expect(reloaded.accounts.single.security!.failCount, 5);
    expect(reloaded.accounts.single.security!.lockedUntilMs, greaterThan(0));
  });

  testWidgets('Settings: the choice is shown (30) and Off is saved to the profile folder', (tester) async {
    final a = await seed(tester, password: 'correct horse');
    await mount(
      tester,
      app: (context, account) => MaterialApp(
        home: Scaffold(
          body: ListView(children: const [AccountSettingsSection()]),
        ),
      ),
    );
    await signIn(tester, a);
    await until(tester, find.byKey(const ValueKey('account-idle-lock-menu')));
    expect(find.text('30 min'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('account-idle-lock-menu')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Off').last);
    await settle(tester, 3);
    expect(find.text('Off'), findsOneWidget);
    expect(await tester.runAsync(() => loadIdleLockMinutes(root)), 0);
    // And it holds: no lock however long it is quiet.
    await tester.pump(unit * 600);
    expect(find.byKey(const ValueKey('account-idle-lock-menu')), findsOneWidget);
  });
}
