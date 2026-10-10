import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// A message that failed authentication (wrong key, tampered, replayed,
/// stale). The cause is deliberately not told to the other side.
class SyncAuthException implements Exception {
  const SyncAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// AES-256-GCM with the request context bound in as associated data, plus the
/// key derivation for pairing. Pure and platform independent.
class SyncCrypto {
  static final _aes = AesGcm.with256bits();
  static final _random = Random.secure();

  static Uint8List randomBytes(int n) =>
      Uint8List.fromList([for (var i = 0; i < n; i++) _random.nextInt(256)]);

  /// A 256-bit key from a short secret (the pairing code in the QR).
  static Future<Uint8List> deriveKey(Uint8List secret, String info) async {
    final key = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: SecretKey(secret),
      nonce: utf8.encode('livenow-sync'),
      info: utf8.encode(info),
    );
    return Uint8List.fromList(await key.extractBytes());
  }

  /// Encrypts [plain]; returns the nonce and the cipher text with its tag.
  static Future<({Uint8List nonce, Uint8List data})> seal(
    Uint8List key,
    List<int> plain,
    String aad,
  ) async {
    final nonce = randomBytes(12);
    final box = await _aes.encrypt(
      plain,
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: utf8.encode(aad),
    );
    return (
      nonce: nonce,
      data: Uint8List.fromList([...box.cipherText, ...box.mac.bytes]),
    );
  }

  /// Decrypts and authenticates; throws [SyncAuthException] on any failure.
  static Future<Uint8List> open(
    Uint8List key,
    Uint8List nonce,
    Uint8List data,
    String aad,
  ) async {
    if (data.length < 16) throw const SyncAuthException('bad message');
    try {
      final clear = await _aes.decrypt(
        SecretBox(
          data.sublist(0, data.length - 16),
          nonce: nonce,
          mac: Mac(data.sublist(data.length - 16)),
        ),
        secretKey: SecretKey(key),
        aad: utf8.encode(aad),
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const SyncAuthException('bad message');
    }
  }
}
