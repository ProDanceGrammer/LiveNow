import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../domain/sync/sync_crypto.dart';

/// PBKDF2 iterations for a NEW password (stored per account, so it can be raised
/// later). Pure-Dart PBKDF2 is slow, so this is a compromise between the
/// recommended 600,000 and a sign-in that takes seconds; it runs in an isolate.
const int kAccountKdfIterations = 200000;

/// What a password turns into: the part that is stored (as a hash) to check a
/// later attempt, and the AES key that is never stored.
class DerivedAccountKey {
  const DerivedAccountKey({required this.verifier, required this.key});

  /// Base64 SHA-256 of the first 32 derived bytes.
  final String verifier;

  /// The last 32 derived bytes: the AES-256-GCM key for the account's secrets
  /// (and, later, the database key).
  final Uint8List key;
}

/// Key derivation and sealing for the account layer. Everything is pure Dart.
class AccountCrypto {
  static Uint8List newSalt() => SyncCrypto.randomBytes(16);

  /// Derives the verifier and the AES key from [password]. Runs in an isolate:
  /// hundreds of thousands of HMAC rounds in pure Dart would freeze the UI.
  static Future<DerivedAccountKey> derive(
    String password,
    Uint8List salt,
    int iterations,
  ) => Isolate.run(() => _derive(password, salt, iterations));

  static Future<DerivedAccountKey> _derive(
    String password,
    Uint8List salt,
    int iterations,
  ) async {
    final key = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 512,
    ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
    final bytes = Uint8List.fromList(await key.extractBytes());
    final hash = await Sha256().hash(bytes.sublist(0, 32));
    return DerivedAccountKey(
      verifier: base64.encode(hash.bytes),
      key: Uint8List.fromList(bytes.sublist(32)),
    );
  }

  /// Compares in constant time (no early exit on the first wrong byte).
  static bool constantTimeEquals(String a, String b) {
    final x = utf8.encode(a);
    final y = utf8.encode(b);
    var diff = x.length ^ y.length;
    for (var i = 0; i < x.length && i < y.length; i++) {
      diff |= x[i] ^ y[i];
    }
    return diff == 0;
  }

  /// Encrypts [plain] with [key] (AES-256-GCM, [aad] bound in); returns one
  /// base64 string holding nonce + cipher text + tag.
  static Future<String> seal(
    Uint8List key,
    List<int> plain, {
    String aad = 'livenow-account',
  }) async {
    final box = await SyncCrypto.seal(key, plain, aad);
    return base64.encode([...box.nonce, ...box.data]);
  }

  /// Reverses [seal]; throws [SyncAuthException] for a wrong key or a damaged
  /// value.
  static Future<Uint8List> open(
    Uint8List key,
    String sealed, {
    String aad = 'livenow-account',
  }) {
    final raw = base64.decode(sealed);
    if (raw.length < 12 + 16) throw const SyncAuthException('bad value');
    return SyncCrypto.open(
      key,
      Uint8List.fromList(raw.sublist(0, 12)),
      Uint8List.fromList(raw.sublist(12)),
      aad,
    );
  }
}
