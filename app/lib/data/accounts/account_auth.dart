import 'dart:convert';
import 'dart:typed_data';

import 'account_crypto.dart';
import 'account_models.dart';
import 'account_registry.dart';
import 'recovery_codes.dart';
import 'totp.dart';

enum CheckStatus { ok, wrong, locked, noPassword }

class PasswordCheck {
  const PasswordCheck(this.status, {this.key, this.lockedUntil});
  final CheckStatus status;

  /// The password-derived AES key, only when [status] is ok.
  final Uint8List? key;

  /// When the next attempt is accepted, only when [status] is locked.
  final DateTime? lockedUntil;

  bool get ok => status == CheckStatus.ok;
}

enum SecondFactorKind { authenticatorCode, recoveryCode }

class SecondFactorCheck {
  const SecondFactorCheck(this.status, {this.kind, this.lockedUntil});
  final CheckStatus status;
  final SecondFactorKind? kind;
  final DateTime? lockedUntil;
  bool get ok => status == CheckStatus.ok;
}

/// A secret ready to be shown (QR + typed key) and confirmed with a first code.
class TotpEnrollment {
  const TotpEnrollment(this.secret, this.uri);
  final Uint8List secret;
  final String uri;
  String get typedKey => base32Encode(secret);
}

/// Passwords, the second factor and the sign-in lockout of the local accounts.
///
/// The password stretches (PBKDF2) into two halves: one is stored as a hash to
/// CHECK a later attempt, the other is an AES key that is never stored and
/// seals the 2FA secret, so the registry file alone does not give the secret
/// away. Honest limit: until the profile databases are encrypted too, this is a
/// privacy gate between people sharing a login, not protection against someone
/// who reads the files.
class AccountAuth {
  AccountAuth(
    this.registry, {
    DateTime Function()? clock,
    this.iterations = kAccountKdfIterations,
  }) : _now = clock ?? DateTime.now;

  final AccountRegistry registry;
  final int iterations;
  final DateTime Function() _now;

  /// Wrong attempts before the first delay, then 30 s doubling up to an hour.
  static const freeAttempts = 5;
  static Duration lockoutFor(int failCount) {
    if (failCount < freeAttempts) return Duration.zero;
    final doublings = (failCount - freeAttempts).clamp(0, 7);
    final seconds = 30 * (1 << doublings);
    return Duration(seconds: seconds > 3600 ? 3600 : seconds);
  }

  Account _account(String id) {
    final a = registry.byId(id);
    if (a == null) throw StateError('unknown account');
    return a;
  }

  DateTime? _lockedUntil(AccountSecurity s) {
    final until = DateTime.fromMillisecondsSinceEpoch(s.lockedUntilMs);
    return s.lockedUntilMs > 0 && until.isAfter(_now()) ? until : null;
  }

  Future<void> _store(String id, AccountSecurity? s) async {
    final a = _account(id);
    await registry.update(
      s == null ? a.copyWith(clearSecurity: true) : a.copyWith(security: s),
    );
  }

  Future<AccountSecurity> _fail(String id, AccountSecurity s) async {
    final fails = s.failCount + 1;
    final delay = lockoutFor(fails);
    final next = s.copyWith(
      failCount: fails,
      lockedUntilMs: delay == Duration.zero
          ? 0
          : _now().add(delay).millisecondsSinceEpoch,
    );
    await _store(id, next);
    return next;
  }

  Future<AccountSecurity> _clearFails(String id, AccountSecurity s) async {
    if (s.failCount == 0 && s.lockedUntilMs == 0) return s;
    final next = s.copyWith(failCount: 0, lockedUntilMs: 0);
    await _store(id, next);
    return next;
  }

  // ---- password -------------------------------------------------------------

  /// Gives a passwordless account its first password.
  Future<void> setPassword(String id, String password) async {
    final salt = AccountCrypto.newSalt();
    final d = await AccountCrypto.derive(password, salt, iterations);
    await _store(
      id,
      AccountSecurity(
        iterations: iterations,
        salt: base64.encode(salt),
        verifier: d.verifier,
      ),
    );
  }

  /// Checks [password]; a wrong one counts towards the lockout.
  Future<PasswordCheck> checkPassword(String id, String password) async {
    final s = _account(id).security;
    if (s == null) return const PasswordCheck(CheckStatus.noPassword);
    final locked = _lockedUntil(s);
    if (locked != null) {
      return PasswordCheck(CheckStatus.locked, lockedUntil: locked);
    }
    final d = await AccountCrypto.derive(
      password,
      Uint8List.fromList(base64.decode(s.salt)),
      s.iterations,
    );
    if (!AccountCrypto.constantTimeEquals(d.verifier, s.verifier)) {
      final next = await _fail(id, s);
      final until = _lockedUntil(next);
      return until == null
          ? const PasswordCheck(CheckStatus.wrong)
          : PasswordCheck(CheckStatus.locked, lockedUntil: until);
    }
    await _clearFails(id, s);
    return PasswordCheck(CheckStatus.ok, key: d.key);
  }

  /// Replaces the password; the 2FA secret is re-sealed with the new key (the
  /// recovery codes and the enrolment stay). [oldKey] comes from a successful
  /// [checkPassword].
  Future<void> changePassword(
    String id,
    Uint8List oldKey,
    String newPassword,
  ) async {
    final s = _account(id).security;
    if (s == null) throw StateError('no password to change');
    final salt = AccountCrypto.newSalt();
    final d = await AccountCrypto.derive(newPassword, salt, iterations);
    TotpSecret? totp = s.totp;
    if (totp != null) {
      final secret = await AccountCrypto.open(oldKey, totp.sealed);
      totp = TotpSecret(
        sealed: await AccountCrypto.seal(d.key, secret),
        lastStep: totp.lastStep,
      );
    }
    await _store(
      id,
      AccountSecurity(
        iterations: iterations,
        salt: base64.encode(salt),
        verifier: d.verifier,
        totp: totp,
        recovery: s.recovery,
      ),
    );
  }

  /// Drops the password AND the second factor (the caller has checked both).
  Future<void> removePassword(String id) => _store(id, null);

  // ---- second factor --------------------------------------------------------

  /// A new secret to show; nothing is stored until [enableTwoFactor].
  TotpEnrollment beginTwoFactor(String accountName) {
    final secret = newTotpSecret();
    return TotpEnrollment(secret, totpUri(secret, accountName));
  }

  /// Turns 2FA on once [firstCode] (from the authenticator) matches the new
  /// secret; returns the ten recovery codes, to be shown exactly once. Null when
  /// the code is wrong.
  Future<List<String>?> enableTwoFactor(
    String id,
    Uint8List key,
    TotpEnrollment enrollment,
    String firstCode,
  ) async {
    final s = _account(id).security;
    if (s == null) throw StateError('2FA needs a password first');
    final step = await verifyTotp(enrollment.secret, firstCode, _now());
    if (step == null) return null;
    final codes = await newRecoveryCodes();
    await _store(
      id,
      s.copyWith(
        totp: TotpSecret(
          sealed: await AccountCrypto.seal(key, enrollment.secret),
          lastStep: step,
        ),
        recovery: codes.set,
      ),
    );
    return codes.codes;
  }

  /// Checks the second factor: an authenticator code (6 digits), or else one of
  /// the recovery codes (which is then used up). Wrong tries count towards the
  /// same lockout as the password.
  Future<SecondFactorCheck> checkSecondFactor(
    String id,
    Uint8List key,
    String code,
  ) async {
    final s = _account(id).security;
    final totp = s?.totp;
    if (s == null || totp == null) {
      return const SecondFactorCheck(CheckStatus.noPassword);
    }
    final locked = _lockedUntil(s);
    if (locked != null) {
      return SecondFactorCheck(CheckStatus.locked, lockedUntil: locked);
    }
    final typed = code.replaceAll(RegExp(r'\s'), '');
    if (RegExp(r'^\d{6}$').hasMatch(typed)) {
      final secret = await AccountCrypto.open(key, totp.sealed);
      final step = await verifyTotp(
        secret,
        typed,
        _now(),
        lastStep: totp.lastStep,
      );
      if (step != null) {
        await _store(
          id,
          s.copyWith(
            totp: totp.copyWith(lastStep: step),
            failCount: 0,
            lockedUntilMs: 0,
          ),
        );
        return const SecondFactorCheck(
          CheckStatus.ok,
          kind: SecondFactorKind.authenticatorCode,
        );
      }
    } else if (s.recovery != null) {
      final hash = await matchRecoveryCode(s.recovery!, code);
      if (hash != null) {
        await _store(
          id,
          s.copyWith(
            recovery: s.recovery!.without(hash),
            failCount: 0,
            lockedUntilMs: 0,
          ),
        );
        return const SecondFactorCheck(
          CheckStatus.ok,
          kind: SecondFactorKind.recoveryCode,
        );
      }
    }
    final next = await _fail(id, s);
    final until = _lockedUntil(next);
    return until == null
        ? const SecondFactorCheck(CheckStatus.wrong)
        : SecondFactorCheck(CheckStatus.locked, lockedUntil: until);
  }

  /// Turns 2FA off (the caller has checked the password and a code).
  Future<void> disableTwoFactor(String id) async {
    final s = _account(id).security;
    if (s == null) return;
    await _store(id, s.copyWith(clearTotp: true, clearRecovery: true));
  }

  /// A fresh set of recovery codes (the old ones stop working); shown once.
  Future<List<String>> regenerateRecoveryCodes(String id) async {
    final s = _account(id).security;
    if (s == null || s.totp == null) throw StateError('2FA is not on');
    final codes = await newRecoveryCodes();
    await _store(id, s.copyWith(recovery: codes.set));
    return codes.codes;
  }

  /// How many recovery codes are left.
  int recoveryCodesLeft(String id) =>
      _account(id).security?.recovery?.hashes.length ?? 0;
}
