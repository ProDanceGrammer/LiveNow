import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../domain/sync/sync_crypto.dart';
import 'account_crypto.dart';
import 'account_models.dart';

/// How many one-time recovery codes a set holds.
const int kRecoveryCodeCount = 10;

// No 0/O or 1/I/L: they are read aloud and copied by hand.
const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

/// A new set: the codes to show ONCE (`XXXX-XXXX-XXXX-XXXX`, 80 bits each) and
/// the salted hashes to keep. The codes themselves are never stored.
Future<({List<String> codes, RecoveryCodeSet set})> newRecoveryCodes({
  int count = kRecoveryCodeCount,
}) async {
  final random = Random.secure();
  final salt = base64.encode(SyncCrypto.randomBytes(16));
  final codes = <String>[];
  for (var i = 0; i < count; i++) {
    final raw = [for (var j = 0; j < 16; j++) _alphabet[random.nextInt(_alphabet.length)]];
    codes.add([
      for (var g = 0; g < 4; g++) raw.sublist(g * 4, g * 4 + 4).join(),
    ].join('-'));
  }
  return (
    codes: codes,
    set: RecoveryCodeSet(
      salt: salt,
      hashes: [for (final c in codes) await recoveryHash(salt, c)],
    ),
  );
}

/// Upper-cases and strips everything but the code's letters and digits, so a
/// code typed with spaces, lower case or no dashes still matches.
String normalizeRecoveryCode(String code) =>
    code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

Future<String> recoveryHash(String salt, String code) async {
  final data = Uint8List.fromList(
    [...base64.decode(salt), ...utf8.encode(normalizeRecoveryCode(code))],
  );
  return base64.encode((await Sha256().hash(data)).bytes);
}

/// The stored hash that [code] matches, or null. Every hash is compared (no
/// early exit).
Future<String?> matchRecoveryCode(RecoveryCodeSet set, String code) async {
  final hash = await recoveryHash(set.salt, code);
  String? hit;
  for (final h in set.hashes) {
    if (AccountCrypto.constantTimeEquals(h, hash)) hit = h;
  }
  return hit;
}
