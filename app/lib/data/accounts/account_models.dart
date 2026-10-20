/// One local account (profile). Pure data + JSON, no I/O.
///
/// The security block is only ever read and written by `AccountAuth`; a damaged
/// or newer block reads as "no password" rather than throwing, so a bad file can
/// never lock the owner out of the app's start.
class Account {
  const Account({
    required this.id,
    required this.name,
    required this.dirName,
    required this.syncAllowed,
    required this.createdAt,
    this.security,
  });

  /// A stable UUID, separate from the display name (a later server account maps
  /// to it).
  final String id;
  final String name;

  /// `.` = the app-support root itself (the account that adopted the data that
  /// existed before accounts did); anything else is a folder under `profiles/`.
  final String dirName;

  /// Only the main account may use hub / QR pairing for now.
  final bool syncAllowed;

  final String createdAt;
  final AccountSecurity? security;

  bool get isMain => dirName == '.';
  bool get hasPassword => security != null;
  bool get hasTwoFactor => security?.totp != null;

  Account copyWith({
    String? name,
    AccountSecurity? security,
    bool clearSecurity = false,
  }) => Account(
    id: id,
    name: name ?? this.name,
    dirName: dirName,
    syncAllowed: syncAllowed,
    createdAt: createdAt,
    security: clearSecurity ? null : (security ?? this.security),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'dir': dirName,
    'sync': syncAllowed,
    'created': createdAt,
    if (security != null) 'security': security!.toJson(),
  };

  static Account? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final name = j['name'];
    final dir = j['dir'];
    if (id is! String || id.isEmpty) return null;
    if (name is! String || dir is! String || dir.isEmpty) return null;
    // A folder name must never climb out of the app-support root.
    if (dir != '.' && (dir.contains('..') || dir.startsWith('/') ||
        dir.startsWith(r'\') || dir.contains(':'))) {
      return null;
    }
    return Account(
      id: id,
      name: name,
      dirName: dir,
      syncAllowed: j['sync'] == true,
      createdAt: j['created'] is String ? j['created'] as String : '',
      security: AccountSecurity.fromJson(j['security']),
    );
  }
}

/// The password check, the optional 2FA secret and the recovery codes.
class AccountSecurity {
  const AccountSecurity({
    required this.iterations,
    required this.salt,
    required this.verifier,
    this.totp,
    this.recovery,
    this.failCount = 0,
    this.lockedUntilMs = 0,
  });

  /// PBKDF2 iterations used for this account (stored, so it can be raised later).
  final int iterations;

  /// Base64 salt of the password derivation.
  final String salt;

  /// Base64 SHA-256 of the first half of the derived key. The second half (the
  /// AES key) is never stored, so the verifier does not reveal it.
  final String verifier;

  final TotpSecret? totp;
  final RecoveryCodeSet? recovery;

  /// Wrong attempts since the last success, and the time before which no
  /// attempt is accepted (ms since epoch). Persisted: restarting the app is not
  /// a way around the delay.
  final int failCount;
  final int lockedUntilMs;

  AccountSecurity copyWith({
    TotpSecret? totp,
    bool clearTotp = false,
    RecoveryCodeSet? recovery,
    bool clearRecovery = false,
    int? failCount,
    int? lockedUntilMs,
  }) => AccountSecurity(
    iterations: iterations,
    salt: salt,
    verifier: verifier,
    totp: clearTotp ? null : (totp ?? this.totp),
    recovery: clearRecovery ? null : (recovery ?? this.recovery),
    failCount: failCount ?? this.failCount,
    lockedUntilMs: lockedUntilMs ?? this.lockedUntilMs,
  );

  Map<String, Object?> toJson() => {
    'iter': iterations,
    'salt': salt,
    'verifier': verifier,
    if (totp != null) 'totp': totp!.toJson(),
    if (recovery != null) 'recovery': recovery!.toJson(),
    if (failCount > 0) 'fails': failCount,
    if (lockedUntilMs > 0) 'locked': lockedUntilMs,
  };

  static AccountSecurity? fromJson(Object? j) {
    if (j is! Map) return null;
    final iter = j['iter'];
    final salt = j['salt'];
    final verifier = j['verifier'];
    if (iter is! int || iter < 1 || salt is! String || verifier is! String) {
      return null;
    }
    return AccountSecurity(
      iterations: iter,
      salt: salt,
      verifier: verifier,
      totp: TotpSecret.fromJson(j['totp']),
      recovery: RecoveryCodeSet.fromJson(j['recovery']),
      failCount: j['fails'] is int ? j['fails'] as int : 0,
      lockedUntilMs: j['locked'] is int ? j['locked'] as int : 0,
    );
  }
}

/// The authenticator secret, sealed with the password-derived key.
class TotpSecret {
  const TotpSecret({required this.sealed, this.lastStep = 0});

  /// Base64 of nonce + cipher text + tag (AES-256-GCM).
  final String sealed;

  /// The last accepted 30-second step: a code is good once.
  final int lastStep;

  TotpSecret copyWith({int? lastStep}) =>
      TotpSecret(sealed: sealed, lastStep: lastStep ?? this.lastStep);

  Map<String, Object?> toJson() => {'sealed': sealed, 'step': lastStep};

  static TotpSecret? fromJson(Object? j) {
    if (j is! Map || j['sealed'] is! String) return null;
    return TotpSecret(
      sealed: j['sealed'] as String,
      lastStep: j['step'] is int ? j['step'] as int : 0,
    );
  }
}

/// Salted hashes of the unused one-time recovery codes.
class RecoveryCodeSet {
  const RecoveryCodeSet({required this.salt, required this.hashes});

  final String salt;
  final List<String> hashes;

  RecoveryCodeSet without(String hash) => RecoveryCodeSet(
    salt: salt,
    hashes: [
      for (final h in hashes)
        if (h != hash) h,
    ],
  );

  Map<String, Object?> toJson() => {'salt': salt, 'hashes': hashes};

  static RecoveryCodeSet? fromJson(Object? j) {
    if (j is! Map || j['salt'] is! String || j['hashes'] is! List) return null;
    return RecoveryCodeSet(
      salt: j['salt'] as String,
      hashes: [
        for (final h in j['hashes'] as List)
          if (h is String) h,
      ],
    );
  }
}
