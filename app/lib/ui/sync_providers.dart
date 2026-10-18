import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/time_codec.dart';
import '../data/sync/http_transport.dart';
import '../data/sync/sync_backup.dart';
import '../data/sync/sync_peers.dart';
import '../data/sync/sync_server.dart';
import '../data/sync/sync_store.dart';
import '../domain/sync/sync_crypto.dart';
import '../domain/sync/sync_engine.dart';
import '../domain/sync/sync_models.dart';
import '../domain/sync/sync_protocol.dart';
import 'providers.dart';

/// The PC serves, the phone asks.
enum SyncRole { host, client }

final syncRoleProvider = Provider<SyncRole>(
  (ref) =>
      Platform.isIOS || Platform.isAndroid ? SyncRole.client : SyncRole.host,
);

final syncStoreProvider = Provider<SyncStore>((ref) {
  final db = ref.watch(databaseProvider);
  return SyncStore(
    db,
    afterApply: (tables) async {
      if (tables.contains('metrics') ||
          tables.contains('metric_dependencies')) {
        await ref.read(metricServiceProvider).recomputeWeights();
      }
    },
  );
});

final syncPeersProvider = Provider<SyncPeers>(
  (ref) => SyncPeers(ref.watch(databaseProvider)),
);

final syncHostProvider = Provider<SyncHost>(
  (ref) => SyncHost(ref.watch(syncStoreProvider), kSyncWireVersion),
);

final syncEngineProvider = Provider<SyncEngine>(
  (ref) => SyncEngine(ref.watch(syncStoreProvider), kSyncWireVersion),
);

/// How the phone reaches its PC; tests swap in an in-process transport.
final syncTransportFactoryProvider =
    Provider<Future<SyncTransport> Function(SyncPeer)>((ref) {
      final peers = ref.watch(syncPeersProvider);
      final store = ref.watch(syncStoreProvider);
      return (peer) async => HttpTransport(
        peers: peers,
        server: peer,
        myDeviceId: await store.deviceId(),
      );
    });

/// Port the PC listens on (tests use 0 = any free port).
final syncServerPortProvider = Provider<int>((ref) => syncPort);

/// Folder for the pre-pairing backup; tests point it at a temp folder.
final syncBackupDirectoryProvider = Provider<Future<Directory> Function()>(
  (ref) => defaultBackupDirectory,
);

final syncDeviceNameProvider = Provider<String>((ref) {
  try {
    return Platform.localHostname;
  } on Object {
    return 'LiveNow device';
  }
});

/// Bumped whenever the sync data the UI shows (peers, conflicts, status)
/// changed behind Riverpod's back.
final syncRevisionProvider = NotifierProvider<_Revision, int>(_Revision.new);

class _Revision extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final syncPeerListProvider = FutureProvider.autoDispose<List<SyncPeer>>((ref) {
  ref.watch(syncRevisionProvider);
  return ref.watch(syncPeersProvider).all();
});

final syncConflictsProvider = FutureProvider.autoDispose<List<SyncConflict>>((
  ref,
) {
  ref.watch(syncRevisionProvider);
  return ref.watch(syncStoreProvider).conflicts();
});

final syncUnseenConflictsProvider = FutureProvider.autoDispose<int>((ref) {
  ref.watch(syncRevisionProvider);
  return ref.watch(syncStoreProvider).unseenConflictCount();
});

// ---- PC: the server -----------------------------------------------------------

class SyncHostState {
  const SyncHostState({
    this.running = false,
    this.port,
    this.pairing,
    this.pairingExpires,
    this.lastPaired,
    this.pendingPair,
    this.error,
  });

  final bool running;
  final int? port;

  /// A phone that knows the code and waits for the owner to approve it; the
  /// sync panel shows the approval dialog while this is set.
  final PairRequest? pendingPair;

  /// The code on screen while a phone is being paired.
  final PairingUri? pairing;
  final DateTime? pairingExpires;

  /// The phone that paired last (the dialog reacts to a new one).
  final SyncPeer? lastPaired;
  final String? error;

  SyncHostState copyWith({
    bool? running,
    int? port,
    PairingUri? pairing,
    DateTime? pairingExpires,
    SyncPeer? lastPaired,
    PairRequest? pendingPair,
    String? error,
    bool clearPairing = false,
    bool clearPendingPair = false,
    bool clearError = false,
  }) => SyncHostState(
    running: running ?? this.running,
    port: port ?? this.port,
    pairing: clearPairing ? null : (pairing ?? this.pairing),
    pairingExpires: clearPairing
        ? null
        : (pairingExpires ?? this.pairingExpires),
    lastPaired: lastPaired ?? this.lastPaired,
    pendingPair: clearPendingPair ? null : (pendingPair ?? this.pendingPair),
    error: clearError ? null : (error ?? this.error),
  );
}

final syncHostControllerProvider =
    NotifierProvider<SyncHostController, SyncHostState>(SyncHostController.new);

/// Owns the PC's [SyncServer]: it runs only while the app is open, and only
/// when a phone is paired or a pairing code is showing.
class SyncHostController extends Notifier<SyncHostState> {
  SyncServer? _server;
  StreamSubscription<SyncPeer>? _sub;
  Timer? _expiry;
  Completer<bool>? _approval;
  Timer? _approvalTimer;

  @override
  SyncHostState build() {
    ref.onDispose(() {
      _expiry?.cancel();
      _sub?.cancel();
      _server?.stop();
      _settleApproval(false);
    });
    return const SyncHostState();
  }

  /// The server asks here before it hands a phone the long-term key. The
  /// answer comes from the approval dialog ([answerPair]).
  Future<bool> _requestApproval(PairRequest request) {
    _settleApproval(false); // only one request at a time
    final c = Completer<bool>();
    _approval = c;
    state = state.copyWith(pendingPair: request);
    // Nobody answered (no panel open to show the dialog): the request lapses
    // and does not linger in the state.
    _approvalTimer = Timer(pairApprovalTimeout, () {
      if (identical(_approval, c)) answerPair(false);
    });
    return c.future;
  }

  void _settleApproval(bool ok) {
    _approvalTimer?.cancel();
    _approvalTimer = null;
    final c = _approval;
    _approval = null;
    if (c != null && !c.isCompleted) c.complete(ok);
  }

  /// The owner's answer to the approval dialog.
  void answerPair(bool approved) {
    _settleApproval(approved);
    state = state.copyWith(clearPendingPair: true);
  }

  Future<bool> enabled() async =>
      await ref.read(syncStoreProvider).getState('server_enabled') != '0';

  /// Starts the server at app start when sync is on and a phone is paired.
  Future<void> autoStart() async {
    if (!await enabled()) return;
    if ((await ref.read(syncPeersProvider).all()).isEmpty) return;
    await start();
  }

  Future<void> setEnabled(bool on) async {
    await ref
        .read(syncStoreProvider)
        .setState('server_enabled', on ? '1' : '0');
    if (on) {
      await autoStart();
    } else {
      await stop();
    }
    ref.read(syncRevisionProvider.notifier).bump();
  }

  Future<void> start() async {
    if (_server?.running ?? false) return;
    final server = SyncServer(
      store: ref.read(syncStoreProvider),
      host: ref.read(syncHostProvider),
      peers: ref.read(syncPeersProvider),
      deviceName: ref.read(syncDeviceNameProvider),
    )..approvePairing = _requestApproval;
    try {
      await server.start(port: ref.read(syncServerPortProvider));
    } on SocketException catch (e) {
      state = state.copyWith(
        error:
            'Could not listen for phones (${e.osError?.message ?? e.message})',
      );
      return;
    }
    _server = server;
    _sub = server.paired.listen((peer) {
      _expiry?.cancel();
      state = state.copyWith(lastPaired: peer, clearPairing: true);
      ref.read(syncRevisionProvider.notifier).bump();
    });
    state = state.copyWith(running: true, port: server.port, clearError: true);
  }

  Future<void> stop() async {
    _expiry?.cancel();
    _settleApproval(false);
    await _sub?.cancel();
    await _server?.stop();
    _server = null;
    state = const SyncHostState();
  }

  /// Opens a pairing window (starting the server if needed).
  Future<void> startPairing() async {
    await start();
    final server = _server;
    if (server == null) return;
    final code = await server.startPairing();
    final expires = DateTime.now().add(pairingLifetime);
    _expiry?.cancel();
    _expiry = Timer(pairingLifetime, cancelPairing);
    state = state.copyWith(pairing: code, pairingExpires: expires);
  }

  void cancelPairing() {
    _expiry?.cancel();
    _server?.cancelPairing();
    state = state.copyWith(clearPairing: true);
  }

  Future<void> removePeer(String deviceId) async {
    await ref.read(syncPeersProvider).remove(deviceId);
    // Its half-sent pages and cursors go too, so nothing of it lingers.
    await ref.read(syncStoreProvider).forgetPeer(deviceId);
    ref.read(syncRevisionProvider.notifier).bump();
  }
}

// ---- phone: the client ---------------------------------------------------------

enum SyncPhase { unpaired, idle, syncing, offline, error }

class SyncStatus {
  const SyncStatus({
    this.phase = SyncPhase.unpaired,
    this.peerName,
    this.lastSync,
    this.message,
    this.lastReport,
  });

  final SyncPhase phase;
  final String? peerName;
  final DateTime? lastSync;
  final String? message;
  final SyncReport? lastReport;

  SyncStatus copyWith({
    SyncPhase? phase,
    String? peerName,
    DateTime? lastSync,
    String? message,
    SyncReport? lastReport,
    bool clearMessage = false,
  }) => SyncStatus(
    phase: phase ?? this.phase,
    peerName: peerName ?? this.peerName,
    lastSync: lastSync ?? this.lastSync,
    message: clearMessage ? null : (message ?? this.message),
    lastReport: lastReport ?? this.lastReport,
  );
}

final syncClientProvider = NotifierProvider<SyncClientController, SyncStatus>(
  SyncClientController.new,
);

/// The phone's side: pairs with the PC and syncs with it on app start, on
/// resume, a few seconds after a local change, and on demand.
class SyncClientController extends Notifier<SyncStatus>
    with WidgetsBindingObserver {
  Timer? _debounce;
  StreamSubscription<Object?>? _changes;
  bool _observing = false;

  @override
  SyncStatus build() {
    ref.onDispose(() {
      _debounce?.cancel();
      _changes?.cancel();
      if (_observing) WidgetsBinding.instance.removeObserver(this);
    });
    return const SyncStatus();
  }

  Future<SyncPeer?> _peer() async =>
      (await ref.read(syncPeersProvider).all()).firstOrNull;

  /// Reloads who we are paired with and when we last synced.
  Future<void> refresh() async {
    final peer = await _peer();
    final last = await ref.read(syncStoreProvider).getState('last_sync');
    if (peer == null) {
      state = const SyncStatus();
    } else if (state.phase == SyncPhase.unpaired) {
      state = SyncStatus(
        phase: SyncPhase.idle,
        peerName: peer.name,
        lastSync: last == null ? null : dateTimeFromDb(last),
      );
    }
    ref.read(syncRevisionProvider.notifier).bump();
  }

  /// Syncs on app start, resume and after local changes (phone only).
  Future<void> autoStart() async {
    await refresh();
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
      _changes = ref
          .read(databaseProvider)
          .tableUpdates()
          .listen((_) => _scheduleSync());
    }
    if (state.phase != SyncPhase.unpaired) unawaited(syncNow());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `state` is the lifecycle here; the notifier's own is `this.state`.
    if (state == AppLifecycleState.resumed &&
        this.state.phase != SyncPhase.unpaired) {
      unawaited(syncNow());
    }
  }

  void _scheduleSync() {
    if (state.phase == SyncPhase.unpaired || state.phase == SyncPhase.syncing) {
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), () => unawaited(syncNow()));
  }

  Future<SyncReport?> syncNow() async {
    if (state.phase == SyncPhase.syncing) return null;
    final peer = await _peer();
    if (peer == null) {
      state = const SyncStatus();
      return null;
    }
    state = state.copyWith(
      phase: SyncPhase.syncing,
      peerName: peer.name,
      clearMessage: true,
    );
    SyncTransport? transport;
    try {
      transport = await ref.read(syncTransportFactoryProvider)(peer);
      final report = await ref.read(syncEngineProvider).sync(transport);
      final now = DateTime.now().toUtc();
      await ref
          .read(syncStoreProvider)
          .setState('last_sync', dateTimeToDb(now)!);
      state = state.copyWith(
        phase: SyncPhase.idle,
        lastSync: now,
        lastReport: report,
      );
      return report;
    } on SyncUnreachable {
      state = state.copyWith(
        phase: SyncPhase.offline,
        message:
            'The PC is not reachable. Is it on, with LiveNow open, on '
            'the same Wi-Fi?',
      );
    } on SyncAuthException catch (e) {
      state = state.copyWith(phase: SyncPhase.error, message: e.message);
    } on SyncVersionMismatch catch (e) {
      state = state.copyWith(phase: SyncPhase.error, message: e.toString());
    } on Object catch (e) {
      state = state.copyWith(phase: SyncPhase.error, message: '$e');
    } finally {
      // Do not leave an idle connection (and its timer) behind.
      if (transport is HttpTransport) transport.close();
      ref.read(syncRevisionProvider.notifier).bump();
    }
    return null;
  }

  /// Pairs with the PC that showed [code]. Pairing happens first (a failure
  /// changes nothing), then a backup of the local database is written (always,
  /// when there is data). With [replace] false (the default choice) nothing on
  /// the phone is deleted: the cursors for this PC start from 0, so ALL the
  /// phone's rows (every edit it never managed to send) go to the PC and the
  /// PC's rows come here, the newest edit of each row winning. With [replace]
  /// true the PC's data REPLACES this device's: wiped, then pulled from the PC.
  Future<SyncReport?> pairAndReplace(
    PairingUri code, {
    bool replace = true,
  }) async {
    final store = ref.read(syncStoreProvider);
    final db = ref.read(databaseProvider);
    final peer = await pairWithServer(
      code: code,
      peers: ref.read(syncPeersProvider),
      myDeviceId: await store.deviceId(),
      myName: ref.read(syncDeviceNameProvider),
    );
    final counts = await store.rowCounts();
    if (counts.values.any((n) => n > 0)) {
      final dir = await ref.read(syncBackupDirectoryProvider)();
      await backupDatabase(db, dir, label: 'before-pairing');
      await pruneBackups(dir);
    }
    if (replace) {
      await store.wipeForReplace();
    } else {
      // Keep every row and its change history; only forget how far the last
      // meeting with this PC got, so everything is exchanged again.
      await store.forgetPeer(peer.deviceId);
    }
    state = SyncStatus(phase: SyncPhase.idle, peerName: peer.name);
    return syncNow();
  }

  /// Forgets the PC (its data stays on the phone).
  Future<void> forget() async {
    final peer = await _peer();
    if (peer != null) await ref.read(syncPeersProvider).remove(peer.deviceId);
    state = const SyncStatus();
    ref.read(syncRevisionProvider.notifier).bump();
  }
}

/// Starts what this device's role needs; called once by the home shell.
Future<void> startSyncForRole(WidgetRef ref) async {
  switch (ref.read(syncRoleProvider)) {
    case SyncRole.host:
      await ref.read(syncHostControllerProvider.notifier).autoStart();
    case SyncRole.client:
      await ref.read(syncClientProvider.notifier).autoStart();
  }
}
