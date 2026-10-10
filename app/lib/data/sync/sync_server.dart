import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../domain/sync/sync_crypto.dart';
import '../../domain/sync/sync_engine.dart';
import '../../domain/sync/sync_models.dart';
import '../../domain/sync/sync_protocol.dart';
import 'sync_peers.dart';
import 'sync_store.dart';

/// The one-time code shown to the phone while pairing.
class _Offer {
  _Offer(this.secret, this.key, this.expiresAt);
  final Uint8List secret;
  final Uint8List key;
  final DateTime expiresAt;
  int attempts = 0;
}

/// The PC side of the sync: a small HTTP server that answers encrypted
/// requests from paired phones (`/v1/hello`, `/v1/pull`, `/v1/push`) and
/// accepts a new phone through `/v1/pair` while a pairing code is showing.
/// Nothing is served in clear text and nothing without a known device key.
class SyncServer {
  SyncServer({
    required this.store,
    required this.host,
    required this.peers,
    this.deviceName = 'PC',
  });

  final SyncStore store;
  final SyncHost host;
  final SyncPeers peers;
  final String deviceName;

  HttpServer? _http;
  _Offer? _offer;
  final _paired = StreamController<SyncPeer>.broadcast();

  /// A phone finished pairing.
  Stream<SyncPeer> get paired => _paired.stream;

  bool get running => _http != null;
  int get port => _http!.port;

  /// Starts listening on all interfaces ([port] 0 = any free port).
  Future<void> start({int port = syncPort}) async {
    if (_http != null) return;
    final http = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _http = http;
    http.listen(_handle, onError: (_) {});
  }

  Future<void> stop() async {
    cancelPairing();
    final http = _http;
    _http = null;
    await http?.close(force: true);
  }

  /// Opens a pairing window and returns what goes into the QR code. [hosts]
  /// defaults to this machine's network addresses.
  Future<PairingUri> startPairing({List<String>? hosts}) async {
    final secret = SyncCrypto.randomBytes(16);
    _offer = _Offer(
      secret,
      await SyncCrypto.deriveKey(secret, 'livenow-pair-v1'),
      DateTime.now().add(pairingLifetime),
    );
    return PairingUri(
      deviceId: await store.deviceId(),
      port: port,
      hosts: hosts ?? await localAddresses(),
      secret: secret,
    );
  }

  void cancelPairing() => _offer = null;

  bool get pairingOpen =>
      _offer != null && DateTime.now().isBefore(_offer!.expiresAt);

  Future<void> _handle(HttpRequest req) async {
    var status = HttpStatus.ok;
    String body = '';
    try {
      if (req.method != 'POST') {
        status = HttpStatus.notFound;
      } else if (req.contentLength > 64 * 1024 * 1024) {
        status = HttpStatus.requestEntityTooLarge;
      } else {
        final text = await utf8.decoder.bind(req).join();
        body = switch (req.uri.path) {
          '/v1/pair' => await _pair(text),
          '/v1/hello' ||
          '/v1/pull' ||
          '/v1/push' => await _call(req.uri.path, text),
          _ => throw const _NotFound(),
        };
      }
    } on _NotFound {
      status = HttpStatus.notFound;
    } on SyncAuthException {
      status = HttpStatus.unauthorized; // never says why
    } on Object {
      status = HttpStatus.internalServerError;
    }
    req.response.statusCode = status;
    if (body.isNotEmpty) req.response.write(body);
    await req.response.close();
  }

  Future<String> _pair(String text) async {
    final offer = _offer;
    if (offer == null || DateTime.now().isAfter(offer.expiresAt)) {
      _offer = null;
      throw const SyncAuthException('no pairing open');
    }
    final env = SyncEnvelope.decode(text);
    final Map<String, Object?> request;
    try {
      request = await env.open(offer.key, '/v1/pair');
    } on SyncAuthException {
      if (++offer.attempts >= pairingMaxAttempts) _offer = null;
      rethrow;
    }
    // The code is single use: it is burned before the long-term key leaves.
    _offer = null;
    final key = SyncCrypto.randomBytes(32);
    final peer = SyncPeer(
      deviceId: env.deviceId,
      name: (request['name'] as String?) ?? 'Phone',
      key: key,
      lastCounter: 0,
      addresses: const [],
      port: null,
    );
    await peers.save(peer);
    _paired.add(peer);
    return SyncReply.seal(offer.key, '/v1/pair', env.counter, {
      'device': await store.deviceId(),
      'name': deviceName,
      'key': base64.encode(key),
    });
  }

  Future<String> _call(String path, String text) async {
    final env = SyncEnvelope.decode(text);
    final peer = await peers.get(env.deviceId);
    if (peer == null) throw const SyncAuthException('unknown device');
    if (env.counter <= peer.lastCounter) {
      throw const SyncAuthException('replay');
    }
    final request = await env.open(peer.key, path);
    // Recorded before the work starts: a copy of this request is a replay.
    await peers.setCounter(peer.deviceId, env.counter);

    final Map<String, Object?> answer = switch (path) {
      '/v1/hello' => (await host.hello()).toJson(),
      '/v1/pull' => (await host.pull(
        peer.deviceId,
        request['since']! as int,
        request['limit']! as int,
      )).toJson(),
      '/v1/push' => (await host.push(peer.deviceId, [
        for (final c in (request['changes']! as List))
          SyncChange.fromJson((c as Map).cast<String, Object?>()),
      ], last: request['last']! as bool)).toJson(),
      _ => throw const _NotFound(),
    };
    return SyncReply.seal(peer.key, path, env.counter, answer);
  }
}

class _NotFound implements Exception {
  const _NotFound();
}

/// This machine's IPv4 addresses, home-network ones first (a Tailscale 100.x
/// address, if present, comes after them), then the host name.
Future<List<String>> localAddresses() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
  );
  final all = [
    for (final i in interfaces)
      for (final a in i.addresses)
        if (!a.isLoopback && !a.isLinkLocal) a.address,
  ];
  int rank(String a) => a.startsWith('100.') ? 1 : 0;
  all.sort((a, b) => rank(a).compareTo(rank(b)));
  return [...all, Platform.localHostname];
}
