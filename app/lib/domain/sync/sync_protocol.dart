import 'dart:convert';
import 'dart:typed_data';

import 'sync_crypto.dart';

/// Port the PC listens on.
const syncPort = 47653;

/// How far a request's timestamp may be from the receiver's clock.
const syncMaxClockSkew = Duration(minutes: 5);

/// How long a pairing code stays valid, and how many wrong tries it survives.
const pairingLifetime = Duration(minutes: 5);
const pairingMaxAttempts = 5;

/// What the QR code (or the typed code) carries: who to talk to and the
/// one-time secret that proves the phone saw the PC's screen.
class PairingUri {
  const PairingUri({
    required this.deviceId,
    required this.port,
    required this.hosts,
    required this.secret,
  });

  final String deviceId;
  final int port;
  final List<String> hosts;
  final Uint8List secret;

  @override
  String toString() => Uri(
    scheme: 'livenow',
    host: 'pair',
    queryParameters: {
      'd': deviceId,
      'p': '$port',
      'h': hosts.join(','),
      's': base64Url.encode(secret).replaceAll('=', ''),
    },
  ).toString();

  static PairingUri parse(String text) {
    final uri = Uri.tryParse(text.trim());
    final q = uri?.queryParameters ?? const {};
    if (uri == null ||
        uri.scheme != 'livenow' ||
        uri.host != 'pair' ||
        q['d'] == null ||
        q['p'] == null ||
        q['s'] == null) {
      throw const FormatException('Not a LiveNow pairing code');
    }
    final secret = base64Url.decode(base64Url.normalize(q['s']!));
    return PairingUri(
      deviceId: q['d']!,
      port: int.parse(q['p']!),
      hosts: [
        for (final h in (q['h'] ?? '').split(','))
          if (h.isNotEmpty) h,
      ],
      secret: Uint8List.fromList(secret),
    );
  }
}

/// A request as it travels: who sent it, a counter that only ever grows (so a
/// recorded request cannot be replayed) and a timestamp, all authenticated
/// together with the path, plus the encrypted JSON body.
class SyncEnvelope {
  const SyncEnvelope({
    required this.deviceId,
    required this.counter,
    required this.timeMs,
    required this.nonce,
    required this.data,
  });

  final String deviceId;
  final int counter;
  final int timeMs;
  final Uint8List nonce;
  final Uint8List data;

  static String requestAad(String path, String device, int counter, int t) =>
      '$path|$device|$counter|$t';

  String encode() => jsonEncode({
    'd': deviceId,
    'c': counter,
    't': timeMs,
    'n': base64.encode(nonce),
    'x': base64.encode(data),
  });

  static SyncEnvelope decode(String text) {
    try {
      final j = jsonDecode(text) as Map<String, dynamic>;
      return SyncEnvelope(
        deviceId: j['d'] as String,
        counter: j['c'] as int,
        timeMs: j['t'] as int,
        nonce: base64.decode(j['n'] as String),
        data: base64.decode(j['x'] as String),
      );
    } on Object {
      throw const SyncAuthException('bad message');
    }
  }

  /// Seals [body] for [path].
  static Future<SyncEnvelope> seal({
    required Uint8List key,
    required String path,
    required String deviceId,
    required int counter,
    required Map<String, Object?> body,
    DateTime? now,
  }) async {
    final t = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final box = await SyncCrypto.seal(
      key,
      utf8.encode(jsonEncode(body)),
      requestAad(path, deviceId, counter, t),
    );
    return SyncEnvelope(
      deviceId: deviceId,
      counter: counter,
      timeMs: t,
      nonce: box.nonce,
      data: box.data,
    );
  }

  /// Authenticates and decrypts; rejects a timestamp outside the allowed skew.
  Future<Map<String, Object?>> open(
    Uint8List key,
    String path, {
    DateTime? now,
  }) async {
    final skew = ((now ?? DateTime.now()).millisecondsSinceEpoch - timeMs)
        .abs();
    if (skew > syncMaxClockSkew.inMilliseconds) {
      throw const SyncAuthException('clock');
    }
    final clear = await SyncCrypto.open(
      key,
      nonce,
      data,
      requestAad(path, deviceId, counter, timeMs),
    );
    return (jsonDecode(utf8.decode(clear)) as Map).cast<String, Object?>();
  }
}

/// The answer to a request, bound to that request's path and counter.
class SyncReply {
  static String _aad(String path, int counter) => '$path|reply|$counter';

  static Future<String> seal(
    Uint8List key,
    String path,
    int counter,
    Map<String, Object?> body,
  ) async {
    final box = await SyncCrypto.seal(
      key,
      utf8.encode(jsonEncode(body)),
      _aad(path, counter),
    );
    return jsonEncode({
      'n': base64.encode(box.nonce),
      'x': base64.encode(box.data),
    });
  }

  static Future<Map<String, Object?>> open(
    Uint8List key,
    String path,
    int counter,
    String text,
  ) async {
    try {
      final j = jsonDecode(text) as Map<String, dynamic>;
      final clear = await SyncCrypto.open(
        key,
        base64.decode(j['n'] as String),
        base64.decode(j['x'] as String),
        _aad(path, counter),
      );
      return (jsonDecode(utf8.decode(clear)) as Map).cast<String, Object?>();
    } on SyncAuthException {
      rethrow;
    } on Object {
      throw const SyncAuthException('bad message');
    }
  }
}
