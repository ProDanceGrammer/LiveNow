import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/accounts/account_auth.dart';
import 'package:livenow/data/accounts/account_crypto.dart';
import 'package:livenow/data/accounts/account_models.dart';
import 'package:livenow/data/accounts/account_registry.dart';
import 'package:livenow/data/accounts/recovery_codes.dart';
import 'package:livenow/data/accounts/totp.dart';
import 'package:livenow/domain/sync/sync_crypto.dart';

/// The account layer: TOTP, recovery codes, key derivation, the registry file
/// and the sign-in rules. Pure Dart, temp folders only, never the real data.
void main() {
  group('base32 and TOTP (RFC 6238 vectors)', () {
    final secret = utf8.encode('12345678901234567890');

    test('base32 round trip and a known value', () {
      expect(base32Encode(utf8.encode('foobar')), 'MZXW6YTBOI');
      expect(base32Decode('MZXW6YTBOI'), utf8.encode('foobar'));
      expect(base32Decode('mzxw 6ytb-oi'), utf8.encode('foobar'));
      expect(base32Decode('not base32!'), isNull);
      final rnd = SyncCrypto.randomBytes(20);
      expect(base32Decode(base32Encode(rnd)), rnd);
    });

    test('the SHA-1 test vectors', () async {
      Future<String> at(int t) =>
          totpCodeForStep(secret, t ~/ 30, digits: 8);
      expect(await at(59), '94287082');
      expect(await at(1111111109), '07081804');
      expect(await at(1111111111), '14050471');
      expect(await at(1234567890), '89005924');
      expect(await at(2000000000), '69279037');
      expect(await at(20000000000), '65353130');
    });

    test('verify: the window is one step either side, a step works once', () async {
      final now = DateTime.fromMillisecondsSinceEpoch(1111111109 * 1000, isUtc: true);
      final step = totpStep(now);
      final code = await totpCodeForStep(secret, step);
      expect(await verifyTotp(secret, code, now), step);
      expect(await verifyTotp(secret, ' ${code.substring(0, 3)} ${code.substring(3)} ', now), step);
      // The previous and the next step still pass (a clock a little off).
      expect(await verifyTotp(secret, await totpCodeForStep(secret, step - 1), now), step - 1);
      expect(await verifyTotp(secret, await totpCodeForStep(secret, step + 1), now), step + 1);
      // Two steps away does not.
      expect(await verifyTotp(secret, await totpCodeForStep(secret, step + 2), now), isNull);
      // Used once: the same step (or an older one) is refused afterwards.
      expect(await verifyTotp(secret, code, now, lastStep: step), isNull);
      expect(await verifyTotp(secret, 'abcdef', now), isNull);
      expect(await verifyTotp(secret, '12345', now), isNull);
    });

    test('the otpauth link carries the secret and the issuer', () {
      final uri = totpUri(secret, 'Ann Lee');
      expect(uri, startsWith('otpauth://totp/LiveNow%3AAnn%20Lee?secret='));
      expect(uri, contains('secret=${base32Encode(secret)}'));
      expect(uri, contains('issuer=LiveNow'));
      expect(uri, contains('digits=6'));
    });
  });

  group('recovery codes', () {
    test('ten codes of 16 letters in groups of four, all different', () async {
      final r = await newRecoveryCodes();
      expect(r.codes, hasLength(10));
      expect(r.codes.toSet(), hasLength(10));
      for (final c in r.codes) {
        expect(c, matches(RegExp(r'^[A-Z2-9]{4}(-[A-Z2-9]{4}){3}$')));
        expect(c, isNot(matches(RegExp(r'[01OIL]'))));
      }
      expect(r.set.hashes, hasLength(10));
      // The codes themselves are not what is stored.
      expect(jsonEncode(r.set.toJson()), isNot(contains(r.codes.first)));
    });

    test('typed with lower case, spaces or no dashes still matches', () async {
      final r = await newRecoveryCodes(count: 2);
      final c = r.codes.first;
      expect(await matchRecoveryCode(r.set, c), isNotNull);
      expect(await matchRecoveryCode(r.set, c.toLowerCase()), isNotNull);
      expect(await matchRecoveryCode(r.set, c.replaceAll('-', ' ')), isNotNull);
      expect(await matchRecoveryCode(r.set, 'AAAA-AAAA-AAAA-AAAA'), isNull);
    });
  });

  group('key derivation and sealing', () {
    test('same password and salt give the same result, anything else does not', () async {
      final salt = AccountCrypto.newSalt();
      final a = await AccountCrypto.derive('hunter2', salt, 1000);
      final b = await AccountCrypto.derive('hunter2', salt, 1000);
      final c = await AccountCrypto.derive('hunter3', salt, 1000);
      final d = await AccountCrypto.derive('hunter2', AccountCrypto.newSalt(), 1000);
      expect(a.verifier, b.verifier);
      expect(a.key, b.key);
      expect(a.verifier, isNot(c.verifier));
      expect(a.verifier, isNot(d.verifier));
      expect(a.key, hasLength(32));
      // The stored verifier is not the key.
      expect(base64.encode(a.key), isNot(a.verifier));
    });

    test('seal / open round trip; a wrong key or a damaged value fails', () async {
      final key = SyncCrypto.randomBytes(32);
      final sealed = await AccountCrypto.seal(key, utf8.encode('secret'));
      expect(utf8.decode(await AccountCrypto.open(key, sealed)), 'secret');
      expect(
        () => AccountCrypto.open(SyncCrypto.randomBytes(32), sealed),
        throwsA(isA<SyncAuthException>()),
      );
      final raw = base64.decode(sealed)..[20] ^= 1;
      expect(
        () => AccountCrypto.open(key, base64.encode(raw)),
        throwsA(isA<SyncAuthException>()),
      );
      expect(() => AccountCrypto.open(key, 'AAAA'), throwsA(isA<SyncAuthException>()));
    });

    test('constant-time compare', () {
      expect(AccountCrypto.constantTimeEquals('abc', 'abc'), isTrue);
      expect(AccountCrypto.constantTimeEquals('abc', 'abd'), isFalse);
      expect(AccountCrypto.constantTimeEquals('abc', 'abcd'), isFalse);
    });
  });

  group('registry', () {
    late Directory root;
    setUp(() async => root = await Directory.systemTemp.createTemp('livenow_acc_'));
    tearDown(() => root.delete(recursive: true));

    test('no file = null; save then load keeps accounts and the last one', () async {
      expect(await AccountRegistry.load(root), isNull);
      final reg = AccountRegistry.empty(root);
      final main = await reg.addMain('Vasyl');
      final guest = await reg.create('Guest');
      await reg.setLast(guest.id);
      final back = (await AccountRegistry.load(root))!;
      expect(back.accounts.map((a) => a.name), ['Vasyl', 'Guest']);
      expect(back.lastAccountId, guest.id);
      expect(back.main!.id, main.id);
      expect(back.byId(guest.id)!.syncAllowed, isFalse);
      expect(back.byId(main.id)!.syncAllowed, isTrue);
    });

    test('the main account uses the root itself, the others profiles/<id>', () async {
      final reg = AccountRegistry.empty(root);
      final main = await reg.addMain('Me');
      final guest = await reg.create('Guest');
      expect(reg.profileDir(main).path, root.path);
      expect(reg.profileDir(guest).path,
          '${root.path}${Platform.pathSeparator}profiles${Platform.pathSeparator}${guest.id}');
      expect(await reg.profileDir(guest).exists(), isTrue);
    });

    test('a damaged accounts.json falls back to the backup copy; both bad throws', () async {
      final reg = AccountRegistry.empty(root);
      await reg.addMain('Me');
      await reg.create('Guest'); // the second save makes the .bak
      await AccountRegistry.fileIn(root).writeAsString('{not json');
      final back = (await AccountRegistry.load(root))!;
      expect(back.accounts, isNotEmpty);
      await File('${AccountRegistry.fileIn(root).path}.bak').writeAsString('garbage');
      expect(() => AccountRegistry.load(root), throwsA(isA<AccountRegistryException>()));
    });

    test('delete removes only that profile folder; the main account is protected', () async {
      final reg = AccountRegistry.empty(root);
      final main = await reg.addMain('Me');
      final guest = await reg.create('Guest');
      final other = await reg.create('Other');
      await File('${reg.profileDir(guest).path}${Platform.pathSeparator}x.txt').writeAsString('1');
      await File('${root.path}${Platform.pathSeparator}livenow.sqlite').writeAsString('db');
      await reg.delete(guest.id);
      expect(await reg.profileDir(guest).exists(), isFalse);
      expect(await reg.profileDir(other).exists(), isTrue);
      expect(await File('${root.path}${Platform.pathSeparator}livenow.sqlite').exists(), isTrue);
      expect(reg.byId(guest.id), isNull);
      expect(() => reg.delete(main.id), throwsStateError);
    });

    test('a folder name that climbs out of the root is refused on load', () {
      expect(Account.fromJson({'id': 'a', 'name': 'x', 'dir': '../evil'}), isNull);
      expect(Account.fromJson({'id': 'a', 'name': 'x', 'dir': r'C:\evil'}), isNull);
      expect(Account.fromJson({'id': 'a', 'name': 'x', 'dir': '/abs'}), isNull);
      expect(Account.fromJson({'id': 'a', 'name': 'x', 'dir': '.'}), isNotNull);
    });

    test('a damaged security block reads as no password, not an error', () {
      final a = Account.fromJson({
        'id': 'a',
        'name': 'x',
        'dir': 'a',
        'security': {'iter': 'many'},
      })!;
      expect(a.hasPassword, isFalse);
    });
  });

  group('sign-in rules', () {
    late Directory root;
    late AccountRegistry reg;
    late Account acc;
    var clock = DateTime.utc(2030, 1, 1, 12);
    late AccountAuth auth;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('livenow_auth_');
      reg = AccountRegistry.empty(root);
      acc = await reg.create('Ann');
      clock = DateTime.utc(2030, 1, 1, 12);
      auth = AccountAuth(reg, clock: () => clock, iterations: 1000);
    });
    tearDown(() => root.delete(recursive: true));

    Future<Uint8List> signedInKey(String password) async =>
        (await auth.checkPassword(acc.id, password)).key!;

    test('no password: nothing to check', () async {
      expect((await auth.checkPassword(acc.id, 'x')).status, CheckStatus.noPassword);
    });

    test('right and wrong passwords', () async {
      await auth.setPassword(acc.id, 'correct horse');
      expect((await auth.checkPassword(acc.id, 'wrong')).status, CheckStatus.wrong);
      final ok = await auth.checkPassword(acc.id, 'correct horse');
      expect(ok.ok, isTrue);
      expect(ok.key, hasLength(32));
      // The registry file never holds the password or the key.
      final text = await AccountRegistry.fileIn(root).readAsString();
      expect(text, isNot(contains('correct horse')));
      expect(text, isNot(contains(base64.encode(ok.key!))));
    });

    test('five wrong tries lock the account; the delay grows; it survives a restart', () async {
      await auth.setPassword(acc.id, 'pw');
      for (var i = 0; i < 4; i++) {
        expect((await auth.checkPassword(acc.id, 'bad')).status, CheckStatus.wrong);
      }
      final fifth = await auth.checkPassword(acc.id, 'bad');
      expect(fifth.status, CheckStatus.locked);
      expect(fifth.lockedUntil, clock.add(const Duration(seconds: 30)).toLocal());
      // Locked: even the RIGHT password is refused until the time passes.
      expect((await auth.checkPassword(acc.id, 'pw')).status, CheckStatus.locked);

      // A restart (a new registry and auth over the same file) does not reset it.
      final reg2 = (await AccountRegistry.load(root))!;
      final auth2 = AccountAuth(reg2, clock: () => clock, iterations: 1000);
      expect((await auth2.checkPassword(acc.id, 'pw')).status, CheckStatus.locked);

      clock = clock.add(const Duration(seconds: 31));
      expect((await auth2.checkPassword(acc.id, 'bad')).status, CheckStatus.locked);
      // The next wrong try doubled the delay to 60 s.
      clock = clock.add(const Duration(seconds: 59));
      expect((await auth2.checkPassword(acc.id, 'pw')).status, CheckStatus.locked);
      clock = clock.add(const Duration(seconds: 2));
      expect((await auth2.checkPassword(acc.id, 'pw')).ok, isTrue);
      // Success resets the counter.
      expect(reg2.byId(acc.id)!.security!.failCount, 0);
    });

    test('lockout delays: free tries, then 30 s doubling, capped at an hour', () {
      expect(AccountAuth.lockoutFor(4), Duration.zero);
      expect(AccountAuth.lockoutFor(5), const Duration(seconds: 30));
      expect(AccountAuth.lockoutFor(6), const Duration(seconds: 60));
      expect(AccountAuth.lockoutFor(7), const Duration(seconds: 120));
      expect(AccountAuth.lockoutFor(40), const Duration(hours: 1));
    });

    test('2FA: enabling needs a correct first code and hands out ten recovery codes', () async {
      await auth.setPassword(acc.id, 'pw');
      final key = await signedInKey('pw');
      final enrol = auth.beginTwoFactor('Ann');
      expect(enrol.uri, contains(enrol.typedKey));

      expect(await auth.enableTwoFactor(acc.id, key, enrol, '000000'), isNull);
      expect(reg.byId(acc.id)!.hasTwoFactor, isFalse);

      final code = await totpCodeForStep(enrol.secret, totpStep(clock));
      final recovery = await auth.enableTwoFactor(acc.id, key, enrol, code);
      expect(recovery, hasLength(10));
      expect(reg.byId(acc.id)!.hasTwoFactor, isTrue);
      expect(auth.recoveryCodesLeft(acc.id), 10);
      // The secret is stored sealed, never in the clear.
      final text = await AccountRegistry.fileIn(root).readAsString();
      expect(text, isNot(contains(enrol.typedKey)));
    });

    test('2FA sign-in: a code works once (no replay), a wrong one counts', () async {
      await auth.setPassword(acc.id, 'pw');
      final key = await signedInKey('pw');
      final enrol = auth.beginTwoFactor('Ann');
      final first = await totpCodeForStep(enrol.secret, totpStep(clock));
      await auth.enableTwoFactor(acc.id, key, enrol, first);

      // The code used to enrol cannot be used again to sign in.
      expect((await auth.checkSecondFactor(acc.id, key, first)).status, CheckStatus.wrong);

      clock = clock.add(const Duration(seconds: 30));
      final next = await totpCodeForStep(enrol.secret, totpStep(clock));
      final ok = await auth.checkSecondFactor(acc.id, key, next);
      expect(ok.ok, isTrue);
      expect(ok.kind, SecondFactorKind.authenticatorCode);
      // The same code again is a replay.
      expect((await auth.checkSecondFactor(acc.id, key, next)).status, CheckStatus.wrong);
    });

    test('recovery codes work once each, in any typing', () async {
      await auth.setPassword(acc.id, 'pw');
      final key = await signedInKey('pw');
      final enrol = auth.beginTwoFactor('Ann');
      final recovery = (await auth.enableTwoFactor(
        acc.id,
        key,
        enrol,
        await totpCodeForStep(enrol.secret, totpStep(clock)),
      ))!;
      final r = await auth.checkSecondFactor(acc.id, key, recovery[3].toLowerCase());
      expect(r.ok, isTrue);
      expect(r.kind, SecondFactorKind.recoveryCode);
      expect(auth.recoveryCodesLeft(acc.id), 9);
      expect(
        (await auth.checkSecondFactor(acc.id, key, recovery[3])).status,
        CheckStatus.wrong,
      );
      expect((await auth.checkSecondFactor(acc.id, key, recovery[4])).ok, isTrue);
    });

    test('changing the password keeps 2FA working (the secret is re-sealed)', () async {
      await auth.setPassword(acc.id, 'old');
      final oldKey = await signedInKey('old');
      final enrol = auth.beginTwoFactor('Ann');
      await auth.enableTwoFactor(
        acc.id,
        oldKey,
        enrol,
        await totpCodeForStep(enrol.secret, totpStep(clock)),
      );
      await auth.changePassword(acc.id, oldKey, 'new');
      expect((await auth.checkPassword(acc.id, 'old')).status, CheckStatus.wrong);
      final newKey = await signedInKey('new');
      clock = clock.add(const Duration(seconds: 60));
      final code = await totpCodeForStep(enrol.secret, totpStep(clock));
      expect((await auth.checkSecondFactor(acc.id, newKey, code)).ok, isTrue);
    });

    test('disable 2FA and remove the password; regenerate replaces the codes', () async {
      await auth.setPassword(acc.id, 'pw');
      final key = await signedInKey('pw');
      final enrol = auth.beginTwoFactor('Ann');
      final old = (await auth.enableTwoFactor(
        acc.id,
        key,
        enrol,
        await totpCodeForStep(enrol.secret, totpStep(clock)),
      ))!;
      final fresh = await auth.regenerateRecoveryCodes(acc.id);
      expect(fresh, hasLength(10));
      expect(
        (await auth.checkSecondFactor(acc.id, key, old.first)).status,
        CheckStatus.wrong,
      );
      await auth.disableTwoFactor(acc.id);
      expect(reg.byId(acc.id)!.hasTwoFactor, isFalse);
      expect(reg.byId(acc.id)!.hasPassword, isTrue);
      await auth.removePassword(acc.id);
      expect(reg.byId(acc.id)!.hasPassword, isFalse);
    });
  });
}
