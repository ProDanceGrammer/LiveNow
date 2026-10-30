import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../domain/sync/network_rules.dart';
import '../../domain/sync/sync_crypto.dart';
import '../../domain/sync/sync_engine.dart';
import '../../domain/sync/sync_models.dart';
import '../../domain/sync/sync_protocol.dart';
import 'sync_peers.dart';
import 'sync_store.dart';

/// The one-time code shown to the phone while pairing.
class _Offer {
  _Offer(this.secret, this.key, this.expiresAt, {this.local = false});
  final Uint8List secret;
  final Uint8List key;
  final DateTime expiresAt;

  /// The hub's bootstrap offer (written to a file only its owner can read): a
  /// request that arrives from this very machine with this secret is approved
  /// at once and becomes the admin device.
  final bool local;
  int attempts = 0;
}

/// Prefix of the routes only the local admin device may call (the hub's
/// pairing, approval, peers and conflicts, driven from the desktop window).
const adminPrefix = '/v1/admin/';

/// The `sync_state` key flagging [deviceId] as the admin device.
String adminStateKey(String deviceId) => 'admin:$deviceId';

/// Handles one authenticated admin call ([route] is the part after the prefix).
typedef AdminHandler =
    Future<Map<String, Object?>> Function(
      String route,
      Map<String, Object?> request,
    );

/// Largest request body per route, counted while it streams in (the phone's
/// client sends chunked bodies, so no length is declared up front). Only a
/// push can be big: one page of changes with their notes.
const _maxBody = {
  '/v1/pair': 64 * 1024,
  '/v1/hello': 64 * 1024,
  '/v1/pull': 64 * 1024,
  '/v1/push': 32 * 1024 * 1024,
  '/v1/ai/history': 64 * 1024,
  '/v1/ai/blob': 64 * 1024,
};

/// What the hub answers to the two read routes of the AI chat archive (the
/// plain desktop host has none and answers `{error: unavailable}`).
abstract class AiReadHandler {
  /// `{messages: [rows], more: bool}`.
  Future<Map<String, Object?>> history(
    String threadId,
    String? before,
    int limit,
  );

  /// `{mime, data (base64)}` or `{error: not_found}`.
  Future<Map<String, Object?>> blob(String blobId);
}

/// Whole-request deadline for reading a body: a trickle (slowloris) is cut.
const _smallBodyDeadline = Duration(seconds: 20);
const _pushBodyDeadline = Duration(minutes: 2);

/// Requests handled at once; more are refused rather than queued.
const _maxInFlight = 16;

/// Failed pairing guesses (from anyone) after which the offer is burned. One
/// source is banned long before this (see [FailureThrottle]).
const _offerFailureCap = 100;

/// A phone that proved it knows the pairing code and asks to be paired.
class PairRequest {
  const PairRequest({required this.deviceId, required this.name});
  final String deviceId;
  final String name;
}

/// The PC side of the sync: a small HTTP server that answers encrypted
/// requests from paired phones (`/v1/hello`, `/v1/pull`, `/v1/push`) and
/// accepts a new phone through `/v1/pair` while a pairing code is showing.
/// Nothing is served in clear text and nothing without a known device key, and
/// only clients on a private / VPN / hotspot address are answered at all.
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

  /// Asked before a phone gets the long-term key: knowing the code is not
  /// enough (it may have been photographed), the owner must say yes. Null =
  /// approve at once (tests); the app always sets it.
  Future<bool> Function(PairRequest request)? approvePairing;

  /// The admin routes (the hub sets it; null = every admin path is a 404).
  AdminHandler? admin;

  /// The AI archive routes (the hub sets it; null = "unavailable").
  AiReadHandler? ai;

  HttpServer? _http;
  _Offer? _offer;
  int _inFlight = 0;
  final _throttle = FailureThrottle();
  final _paired = StreamController<SyncPeer>.broadcast();

  /// A phone finished pairing.
  Stream<SyncPeer> get paired => _paired.stream;

  bool get running => _http != null;
  int get port => _http!.port;

  /// Starts listening on all interfaces ([port] 0 = any free port). Clients
  /// outside the private ranges are dropped in [_handle].
  Future<void> start({int port = syncPort}) async {
    if (_http != null) return;
    final http = await HttpServer.bind(InternetAddress.anyIPv4, port);
    http.idleTimeout = const Duration(seconds: 30);
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
  ///
  /// [lifetime] defaults to [pairingLifetime]; with [local] the offer is the
  /// hub's bootstrap one (see [_Offer.local]) and its holder should keep it
  /// private (a file in the hub's own folder).
  Future<PairingUri> startPairing({
    List<String>? hosts,
    Duration? lifetime,
    bool local = false,
  }) async {
    final secret = SyncCrypto.randomBytes(16);
    _offer = _Offer(
      secret,
      await SyncCrypto.deriveKey(secret, 'livenow-pair-v1'),
      DateTime.now().add(lifetime ?? pairingLifetime),
      local: local,
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
    final source = req.connectionInfo?.remoteAddress.address ?? '';
    var status = HttpStatus.ok;
    String body = '';
    if (!isPrivateAddress(source) || _throttle.isBanned(source)) {
      // A stranger, or a source that keeps failing: answered like an unknown
      // path, so it learns nothing and costs nothing.
      status = HttpStatus.notFound;
    } else if (_inFlight >= _maxInFlight) {
      status = HttpStatus.serviceUnavailable;
    } else {
      _inFlight++;
      try {
        if (req.method != 'POST') {
          status = HttpStatus.notFound;
        } else {
          final path = req.uri.path;
          final isAdmin = path.startsWith(adminPrefix);
          // Admin calls are answered only to this very machine, and only when
          // the hub set a handler: anything else looks like an unknown path.
          if (isAdmin && (admin == null || !_isLoopback(source))) {
            throw const _NotFound();
          }
          final max = isAdmin ? 64 * 1024 : _maxBody[path];
          if (max == null) throw const _NotFound();
          final text = await _readBody(req, max, path == '/v1/push');
          body = path == '/v1/pair'
              ? await _pair(text, source)
              : await _call(path, text);
          _throttle.succeeded(source);
        }
      } on _NotFound {
        status = HttpStatus.notFound;
      } on _TooLarge {
        status = HttpStatus.requestEntityTooLarge;
      } on _BadRequest {
        status = HttpStatus.badRequest;
      } on TimeoutException {
        status = HttpStatus.requestTimeout;
      } on SyncAuthException {
        _throttle.failed(source);
        status = HttpStatus.unauthorized; // never says why
      } on Object {
        status = HttpStatus.internalServerError;
      } finally {
        _inFlight--;
      }
    }
    try {
      req.response.statusCode = status;
      if (body.isNotEmpty) req.response.write(body);
      await req.response.close();
    } on Object {
      // The client went away.
    }
  }

  /// Reads the body while counting its bytes, so an endless or oversized
  /// stream is cut as soon as it passes [max] (before anything is decoded or
  /// authenticated), and a slow trickle hits the deadline.
  Future<String> _readBody(HttpRequest req, int max, bool big) async {
    if (req.contentLength > max) throw const _TooLarge();
    Future<Uint8List> read() async {
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in req) {
        bytes.add(chunk);
        if (bytes.length > max) throw const _TooLarge();
      }
      return bytes.takeBytes();
    }

    final raw = await read().timeout(
      big ? _pushBodyDeadline : _smallBodyDeadline,
    );
    try {
      return utf8.decode(raw);
    } on FormatException {
      throw const _BadRequest();
    }
  }

  Future<String> _pair(String text, String source) async {
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
      // One source is banned by the throttle; only a flood from many sources
      // burns the code for everyone.
      if (++offer.attempts >= _offerFailureCap) _offer = null;
      rethrow;
    }
    // The code is single use: it is burned before the long-term key leaves.
    _offer = null;
    final name = _cleanName(request['name']);
    // The hub's bootstrap offer, used from this machine: its owner is the one
    // who can read the file, so there is nobody to ask, and the device becomes
    // the admin device.
    final bootstrap = offer.local && _isLoopback(source);
    if (offer.local && !bootstrap) {
      throw const SyncAuthException('local pairing from elsewhere');
    }
    if (bootstrap) {
      await store.setState(adminStateKey(env.deviceId), '1');
    } else if (approvePairing != null) {
      final approved = await _ask(
        PairRequest(deviceId: env.deviceId, name: name),
      ).timeout(pairApprovalTimeout, onTimeout: () => false);
      // Declined, or nobody answered: the phone just sees a refusal.
      if (!approved) throw const SyncAuthException('pairing declined');
    }
    final key = SyncCrypto.randomBytes(32);
    final peer = SyncPeer(
      deviceId: env.deviceId,
      name: name,
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

  /// Asks the owner; anything that goes wrong in the callback (it throws, or
  /// returns a failed future) counts as "no". Async on purpose: the error is
  /// absorbed here, so no failed future is ever left without a listener.
  Future<bool> _ask(PairRequest request) async {
    try {
      return await approvePairing!(request);
    } on Object {
      return false;
    }
  }

  Future<String> _call(String path, String text) async {
    final env = SyncEnvelope.decode(text);
    final peer = await peers.get(env.deviceId);
    if (peer == null) throw const SyncAuthException('unknown device');
    if (env.counter <= peer.lastCounter) {
      throw const SyncAuthException('replay');
    }
    final request = await env.open(peer.key, path);
    // Recorded before the work starts, in one atomic statement: of several
    // copies of this request only the first wins; the rest are replays.
    if (!await peers.advanceCounter(peer.deviceId, env.counter)) {
      throw const SyncAuthException('replay');
    }

    final Map<String, Object?> answer = switch (path) {
      '/v1/hello' => (await host.hello()).toJson(),
      '/v1/pull' => (await host.pull(
        peer.deviceId,
        _intField(request, 'since', min: 0),
        _intField(request, 'limit', min: 1, max: 1000),
      )).toJson(),
      '/v1/push' => (await host.push(peer.deviceId, _changes(request),
          last: _boolField(request, 'last'))).toJson(),
      '/v1/ai/history' => await _aiHistory(request),
      '/v1/ai/blob' => await _aiBlob(request),
      _ when path.startsWith(adminPrefix) => await _adminCall(
        path.substring(adminPrefix.length),
        peer,
        request,
      ),
      _ => throw const _NotFound(),
    };
    return SyncReply.seal(peer.key, path, env.counter, answer);
  }

  Future<Map<String, Object?>> _aiHistory(Map<String, Object?> m) async {
    final thread = m['thread_id'];
    final before = m['before'];
    if (thread is! String || thread.isEmpty || thread.length > 100) {
      throw const _BadRequest();
    }
    if (before != null && (before is! String || before.length > 100)) {
      throw const _BadRequest();
    }
    final limit = _intField(m, 'limit', min: 1, max: 100);
    final handler = ai;
    if (handler == null) return const {'error': 'unavailable'};
    return handler.history(thread, before as String?, limit);
  }

  Future<Map<String, Object?>> _aiBlob(Map<String, Object?> m) async {
    final id = m['blob_id'];
    if (id is! String || id.isEmpty || id.length > 100) {
      throw const _BadRequest();
    }
    final handler = ai;
    if (handler == null) return const {'error': 'unavailable'};
    return handler.blob(id);
  }

  /// A route only the admin device may call (the call is already
  /// authenticated; here it must also be the flagged device).
  Future<Map<String, Object?>> _adminCall(
    String route,
    SyncPeer peer,
    Map<String, Object?> request,
  ) async {
    if (await store.getState(adminStateKey(peer.deviceId)) != '1') {
      throw const SyncAuthException('not the admin device');
    }
    return admin!(route, request);
  }

  static bool _isLoopback(String address) =>
      InternetAddress.tryParse(address)?.isLoopback ?? false;

  static int _intField(
    Map<String, Object?> m,
    String key, {
    required int min,
    int? max,
  }) {
    final v = m[key];
    if (v is! int || v < min || (max != null && v > max)) {
      throw const _BadRequest();
    }
    return v;
  }

  static bool _boolField(Map<String, Object?> m, String key) {
    final v = m[key];
    if (v is! bool) throw const _BadRequest();
    return v;
  }

  static List<SyncChange> _changes(Map<String, Object?> m) {
    final list = m['changes'];
    if (list is! List) throw const _BadRequest();
    try {
      return [
        for (final c in list)
          SyncChange.fromJson((c as Map).cast<String, Object?>()),
      ];
    } on Object {
      throw const _BadRequest();
    }
  }

  /// A peer's display name: trimmed, control characters dropped, short.
  static String _cleanName(Object? raw) {
    final s = raw is String
        ? raw.replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), '').trim()
        : '';
    if (s.isEmpty) return 'Phone';
    return s.length > 60 ? s.substring(0, 60) : s;
  }
}

class _NotFound implements Exception {
  const _NotFound();
}

class _TooLarge implements Exception {
  const _TooLarge();
}

class _BadRequest implements Exception {
  const _BadRequest();
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
