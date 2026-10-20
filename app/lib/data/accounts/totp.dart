import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../domain/sync/sync_crypto.dart';

/// Time-based one-time passwords (RFC 6238, HMAC-SHA1, 30 s, 6 digits): the
/// codes of Google Authenticator, Authy, 1Password and friends.
const int kTotpPeriodSeconds = 30;
const int kTotpDigits = 6;

const _b32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

/// A fresh 160-bit authenticator secret.
Uint8List newTotpSecret() => SyncCrypto.randomBytes(20);

/// RFC 4648 base32 without padding (how authenticator apps show a secret).
String base32Encode(List<int> bytes) {
  final out = StringBuffer();
  var buffer = 0;
  var bits = 0;
  for (final b in bytes) {
    buffer = (buffer << 8) | b;
    bits += 8;
    while (bits >= 5) {
      out.write(_b32[(buffer >> (bits - 5)) & 31]);
      bits -= 5;
    }
    buffer &= (1 << bits) - 1;
  }
  if (bits > 0) out.write(_b32[(buffer << (5 - bits)) & 31]);
  return out.toString();
}

/// Reads base32 (case, spaces, dashes and `=` are ignored); null when a
/// character is not base32.
Uint8List? base32Decode(String text) {
  final clean = text.toUpperCase().replaceAll(RegExp(r'[\s=-]'), '');
  final out = <int>[];
  var buffer = 0;
  var bits = 0;
  for (final c in clean.split('')) {
    final v = _b32.indexOf(c);
    if (v < 0) return null;
    buffer = (buffer << 5) | v;
    bits += 5;
    if (bits >= 8) {
      out.add((buffer >> (bits - 8)) & 255);
      bits -= 8;
      buffer &= (1 << bits) - 1;
    }
  }
  return Uint8List.fromList(out);
}

/// The 30-second step number of [time].
int totpStep(DateTime time, {int period = kTotpPeriodSeconds}) =>
    time.toUtc().millisecondsSinceEpoch ~/ 1000 ~/ period;

/// The code for [step] (the RFC's HOTP truncation of HMAC-SHA1).
Future<String> totpCodeForStep(
  List<int> secret,
  int step, {
  int digits = kTotpDigits,
}) async {
  final counter = ByteData(8)..setUint64(0, step);
  final mac = await Hmac.sha1().calculateMac(
    counter.buffer.asUint8List(),
    secretKey: SecretKey(secret),
  );
  final h = mac.bytes;
  final offset = h[h.length - 1] & 0x0f;
  final binary =
      ((h[offset] & 0x7f) << 24) |
      (h[offset + 1] << 16) |
      (h[offset + 2] << 8) |
      h[offset + 3];
  var mod = 1;
  for (var i = 0; i < digits; i++) {
    mod *= 10;
  }
  return (binary % mod).toString().padLeft(digits, '0');
}

/// Checks [code] around [now] (one step either side, for a clock a little off).
/// Returns the step that matched, or null. A step at or before [lastStep] is
/// refused, so a code works once.
Future<int?> verifyTotp(
  List<int> secret,
  String code,
  DateTime now, {
  int lastStep = 0,
}) async {
  final typed = code.replaceAll(RegExp(r'\s'), '');
  if (typed.length != kTotpDigits) return null;
  final current = totpStep(now);
  int? hit;
  // Every candidate is computed (no early exit on a match), so the time taken
  // does not tell which step was right.
  for (var s = current - 1; s <= current + 1; s++) {
    final expected = await totpCodeForStep(secret, s);
    if (expected == typed && s > lastStep) hit ??= s;
  }
  return hit;
}

/// The `otpauth://` link an authenticator app reads from a QR code.
String totpUri(List<int> secret, String accountName, {String issuer = 'LiveNow'}) {
  final label = Uri.encodeComponent('$issuer:$accountName');
  return 'otpauth://totp/$label?secret=${base32Encode(secret)}'
      '&issuer=${Uri.encodeComponent(issuer)}'
      '&algorithm=SHA1&digits=$kTotpDigits&period=$kTotpPeriodSeconds';
}
