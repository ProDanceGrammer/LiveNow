import 'dart:async';
import 'dart:io';

import '../../domain/sync/sync_engine.dart';
import '../../domain/sync/sync_models.dart';
import '../../domain/sync/sync_protocol.dart';
import 'sync_peers.dart';
import 'sync_server.dart';
import 'sync_store.dart';

/// What the hub's owner can do from the desktop window: open a pairing code,
/// answer "Pair this phone?", list / remove paired devices and read / restore
/// sync conflicts. The hub has no window of its own, so the desktop app asks
/// through [SyncServer.admin] (loopback + the admin device only).
class HubAdmin {
  HubAdmin({
    required this.server,
    required this.store,
    required this.peers,
    this.deviceName = 'LiveNow hub',
    this.bootstrapFile,
    this.hosts,
  }) {
    server
      ..admin = handle
      ..approvePairing = _requestApproval;
  }

  final SyncServer server;
  final SyncStore store;
  final SyncPeers peers;
  final String deviceName;

  /// Where the one-time bootstrap pairing text is written (the hub's own
  /// folder); null = none (tests).
  final File? bootstrapFile;

  /// Addresses put into a pairing code (default: this machine's).
  final Future<List<String>> Function()? hosts;

  /// Routes of other hub features (the AI assistant's `ai-settings` /
  /// `ai-status`); it throws a FormatException for a route it does not know.
  AdminHandler? extraRoutes;

  PairRequest? _pending;
  Completer<bool>? _answer;
  Timer? _timeout;
  StreamSubscription<SyncPeer>? _sub;

  /// How long the first admin pairing offer stays open (the owner connects
  /// the desktop window once; until then the offer is renewed by [ensureBootstrap]).
  static const bootstrapLifetime = Duration(hours: 12);

  /// While no admin device exists, keeps a long-lived local offer open and its
  /// text in [bootstrapFile]; once one paired the file is removed.
  Future<void> ensureBootstrap() async {
    _sub ??= server.paired.listen((_) => _cleanupBootstrap());
    if (await _hasAdmin()) {
      _cleanupBootstrap();
      return;
    }
    final file = bootstrapFile;
    if (file == null) return;
    final uri = await server.startPairing(
      hosts: ['127.0.0.1'],
      lifetime: bootstrapLifetime,
      local: true,
    );
    await file.parent.create(recursive: true);
    await file.writeAsString(uri.toString());
  }

  Future<bool> _hasAdmin() async {
    for (final p in await peers.all()) {
      if (await store.getState(adminStateKey(p.deviceId)) == '1') return true;
    }
    return false;
  }

  void _cleanupBootstrap() {
    final file = bootstrapFile;
    if (file != null && file.existsSync()) {
      try {
        file.deleteSync();
      } on Object {
        // Best effort.
      }
    }
  }

  void dispose() {
    _timeout?.cancel();
    _sub?.cancel();
    _settle(false);
  }

  /// The server asks here before it gives a phone the key: it waits for the
  /// desktop window's answer (`pending` + `answer`) and refuses when none comes.
  Future<bool> _requestApproval(PairRequest request) {
    _settle(false); // one request at a time
    final c = Completer<bool>();
    _answer = c;
    _pending = request;
    _timeout = Timer(const Duration(seconds: 60), () {
      if (identical(_answer, c)) _settle(false);
    });
    return c.future;
  }

  void _settle(bool ok) {
    _timeout?.cancel();
    _timeout = null;
    final c = _answer;
    _answer = null;
    _pending = null;
    if (c != null && !c.isCompleted) c.complete(ok);
  }

  Future<Map<String, Object?>> handle(
    String route,
    Map<String, Object?> request,
  ) async {
    switch (route) {
      case 'status':
        return {
          'device': await store.deviceId(),
          'name': deviceName,
          'wire': kSyncWireVersion,
          'pairingOpen': server.pairingOpen,
          'peers': (await peers.all()).length,
          'unseenConflicts': await store.unseenConflictCount(),
        };
      case 'pairing/start':
        final uri = await server.startPairing(
          hosts: await hosts?.call(),
        );
        return {
          'uri': uri.toString(),
          'seconds': pairingLifetime.inSeconds,
        };
      case 'pairing/cancel':
        server.cancelPairing();
        return {};
      case 'pending':
        final p = _pending;
        return {
          'pending': p == null ? null : {'deviceId': p.deviceId, 'name': p.name},
        };
      case 'answer':
        _settle(request['approved'] == true);
        return {};
      case 'peers':
        return {
          'peers': [
            for (final p in await peers.all())
              {
                'deviceId': p.deviceId,
                'name': p.name,
                'admin':
                    await store.getState(adminStateKey(p.deviceId)) == '1',
              },
          ],
        };
      case 'peers/remove':
        final id = request['deviceId'];
        if (id is! String || id.isEmpty) throw const FormatException('id');
        await peers.remove(id);
        await store.forgetPeer(id);
        await store.setState(adminStateKey(id), '0');
        return {};
      case 'conflicts':
        return {
          'conflicts': [
            for (final c in await store.conflicts()) conflictToJson(c),
          ],
        };
      case 'conflicts/restore':
        final id = request['id'];
        if (id is! int) throw const FormatException('id');
        return {'restored': await store.restoreConflict(id)};
      case 'conflicts/seen':
        await store.markConflictsSeen();
        return {};
      default:
        final extra = extraRoutes;
        if (extra != null) return extra(route, request);
        throw const FormatException('unknown admin route');
    }
  }
}

Map<String, Object?> conflictToJson(SyncConflict c) => {
  'id': c.id,
  'table': c.table,
  'rowId': c.rowId,
  'label': c.label,
  'detectedAt': c.detectedAt,
  'loserHlc': c.loserHlc,
  'loserOrigin': c.loserOrigin,
  'winnerHlc': c.winnerHlc,
  'loserData': c.loserData,
  'seen': c.seen,
};

SyncConflict conflictFromJson(Map<String, Object?> j) => SyncConflict(
  id: j['id']! as int,
  table: j['table']! as String,
  rowId: j['rowId']! as String,
  label: j['label'] as String?,
  detectedAt: j['detectedAt']! as String,
  loserHlc: j['loserHlc']! as String,
  loserOrigin: j['loserOrigin']! as String,
  winnerHlc: j['winnerHlc']! as String,
  loserData: (j['loserData'] as Map?)?.cast<String, Object?>(),
  seen: j['seen']! as bool,
);
