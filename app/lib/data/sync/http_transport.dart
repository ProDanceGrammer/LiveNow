import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../domain/sync/network_rules.dart';
import '../../domain/sync/sync_crypto.dart';
import '../../domain/sync/sync_engine.dart';
import '../../domain/sync/sync_models.dart';
import '../../domain/sync/sync_protocol.dart';
import 'sync_peers.dart';

/// None of the paired device's addresses answered (not on the same network?).
class SyncUnreachable implements Exception {
  const SyncUnreachable();
  @override
  String toString() => 'The other device could not be reached.';
}

/// The phone side: encrypted requests to the PC's [SyncServer]. Tries the
/// stored addresses in turn and keeps the one that worked first.
class HttpTransport implements SyncTransport {
  HttpTransport({
    required this.peers,
    required this.server,
    required this.myDeviceId,
    HttpClient? client,
    this.connectTimeout = const Duration(seconds: 3),
  }) : _client = client ?? HttpClient();

  final SyncPeers peers;

  /// The paired PC (its key and addresses).
  final SyncPeer server;
  final String myDeviceId;
  final Duration connectTimeout;
  final HttpClient _client;

  void close() => _client.close(force: true);

  @override
  Future<SyncHello> hello() async =>
      SyncHello.fromJson(await _call('/v1/hello', const {}));

  @override
  Future<SyncPullPage> pull(int sinceSeq, {int limit = 500}) async =>
      SyncPullPage.fromJson(
        await _call('/v1/pull', {'since': sinceSeq, 'limit': limit}),
      );

  @override
  Future<ApplyResult> push(
    List<SyncChange> changes, {
    required bool last,
  }) async => ApplyResult.fromJson(
    await _call('/v1/push', {
      'changes': [for (final c in changes) c.toJson()],
      'last': last,
    }),
  );

  /// One authenticated, encrypted request to the server (the hub's admin
  /// routes use it; sync itself goes through hello / pull / push).
  Future<Map<String, Object?>> call(String path, Map<String, Object?> body) =>
      _call(path, body);

  /// Calls from this device to one peer run one after the other: each takes
  /// the next request counter from the stored one, so two at once (a sync and
  /// an admin poll of the hub) would send the same counter and the server
  /// would refuse the second as a replay.
  static final _queues = <String, Future<void>>{};

  Future<Map<String, Object?>> _call(
    String path,
    Map<String, Object?> body,
  ) async {
    final key = '$myDeviceId>${server.deviceId}';
    final previous = _queues[key] ?? Future<void>.value();
    final mine = Completer<void>();
    final tail = previous.then((_) => mine.future);
    _queues[key] = tail;
    await previous;
    try {
      return await _send(path, body);
    } finally {
      mine.complete();
      if (identical(_queues[key], tail)) _queues.remove(key);
    }
  }

  Future<Map<String, Object?>> _send(
    String path,
    Map<String, Object?> body,
  ) async {
    final current = await peers.get(server.deviceId);
    if (current == null) throw const SyncAuthException('not paired');
    // The counter is stored before the request leaves: it only ever grows.
    final counter = current.lastCounter + 1;
    await peers.setCounter(current.deviceId, counter);
    final env = await SyncEnvelope.seal(
      key: current.key,
      path: path,
      deviceId: myDeviceId,
      counter: counter,
      body: body,
    );
    final answer = await _post(
      current.addresses,
      current.port ?? syncPort,
      path,
      env.encode(),
      onReached: (address) async {
        if (current.addresses.first != address) {
          await peers.setAddresses(current.deviceId, [
            address,
            ...current.addresses.where((a) => a != address),
          ]);
        }
      },
    );
    return SyncReply.open(current.key, path, counter, answer);
  }

  Future<String> _post(
    List<String> addresses,
    int port,
    String path,
    String body, {
    Future<void> Function(String address)? onReached,
  }) => postFirstReachable(
    _client,
    connectTimeout,
    addresses,
    port,
    path,
    body,
    onReached: onReached,
  );
}

/// POSTs [body] to the first of [addresses] that answers.
Future<String> postFirstReachable(
  HttpClient client,
  Duration connectTimeout,
  List<String> addresses,
  int port,
  String path,
  String body, {
  Future<void> Function(String address)? onReached,
}) async {
  client.connectionTimeout = connectTimeout;
  for (final address in addresses) {
    try {
      final req = await client.postUrl(Uri.http('$address:$port', path));
      req.headers.contentType = ContentType.json;
      req.write(body);
      final res = await req.close().timeout(const Duration(minutes: 2));
      final text = await utf8.decoder.bind(res).join();
      if (res.statusCode == HttpStatus.unauthorized) {
        throw const SyncAuthException(
          'The other device refused this one. Pair them again; also check '
          'that both clocks are right.',
        );
      }
      if (res.statusCode != HttpStatus.ok) {
        throw HttpException('Sync failed (${res.statusCode})');
      }
      await onReached?.call(address);
      return text;
    } on SocketException {
      continue;
    } on TimeoutException {
      continue;
    } on HandshakeException {
      continue;
    }
  }
  throw const SyncUnreachable();
}

/// Pairs this device with the PC that showed [code]: proves knowledge of the
/// one-time secret, receives the long-term key and stores the PC as a peer.
Future<SyncPeer> pairWithServer({
  required PairingUri code,
  required SyncPeers peers,
  required String myDeviceId,
  required String myName,
  HttpClient? client,
  Duration connectTimeout = const Duration(seconds: 3),
}) async {
  // A code may only point at a machine on a local, VPN or hotspot network. A
  // forged QR naming a public host would make this phone wipe itself and take
  // data from a stranger's server.
  final hosts = [...code.hosts.where(isAllowedPairingHost)];
  if (hosts.isEmpty) {
    throw const FormatException(
      'This code points outside your local network, so it is refused.',
    );
  }
  final http = client ?? HttpClient();
  try {
    final key = await SyncCrypto.deriveKey(code.secret, 'livenow-pair-v1');
    final env = await SyncEnvelope.seal(
      key: key,
      path: '/v1/pair',
      deviceId: myDeviceId,
      counter: 0,
      body: {'name': myName},
    );
    final answer = await postFirstReachable(
      http,
      connectTimeout,
      hosts,
      code.port,
      '/v1/pair',
      env.encode(),
    );
    final reply = await SyncReply.open(key, '/v1/pair', 0, answer);
    // The PC that answers must be the one the code named.
    if (reply['device'] != code.deviceId) {
      throw const SyncAuthException('The PC is not the one in the code.');
    }
    final peer = SyncPeer(
      deviceId: reply['device']! as String,
      name: reply['name']! as String,
      key: base64.decode(reply['key']! as String),
      lastCounter: 0,
      addresses: hosts,
      port: code.port,
    );
    await peers.save(peer);
    return peer;
  } finally {
    if (client == null) http.close(force: true);
  }
}
