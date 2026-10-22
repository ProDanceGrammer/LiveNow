import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/time_codec.dart';
import '../data/sync/http_transport.dart';
import '../data/sync/hub_admin_client.dart';
import '../hub/hub_main.dart' show hubDirectory;
import '../hub/hub_runner.dart' show kHubLocalPairFile;
import '../data/sync/sync_backup.dart';
import '../data/sync/sync_peers.dart';
import '../data/sync/sync_server.dart';
import '../data/sync/sync_store.dart';
import '../domain/sync/sync_crypto.dart';
import '../domain/sync/sync_engine.dart';
import '../domain/sync/sync_models.dart';
import '../domain/sync/sync_protocol.dart';
import 'providers.dart';

/// The PC serves, the phone asks. A desktop that is connected to the always-on
/// hub asks too (it is a client of the hub, like the phone).
enum SyncRole { host, client }

final syncRoleProvider = Provider<SyncRole>((ref) {
  if (Platform.isIOS || Platform.isAndroid) return SyncRole.client;
  return ref.watch(hubConnectedProvider) ? SyncRole.client : SyncRole.host;
});

/// True on a desktop whose sync partner is the local hub
/// (`sync_state.hub_device_id` is set). Loaded at start by [startSyncForRole].
final hubConnectedProvider = NotifierProvider<HubConnected, bool>(
  HubConnected.new,
);

class HubConnected extends Notifier<bool> {
  @override
  bool build() => false;

  Future<void> refresh() async {
    final id = await ref.read(syncStoreProvider).getState(_hubIdKey);
    state = id != null && id.isNotEmpty;
  }

  void set(bool connected) => state = connected;
}

/// `sync_state` key holding the device id of the hub this desktop talks to.
const _hubIdKey = 'hub_device_id';

/// The hub's own data folder (where it leaves its local pairing text); tests
/// point it at a temp folder.
final hubDirectoryProvider = Provider<Future<Directory> Function()>(
  (ref) =>
      () => hubDirectory(const []),
);

/// Runs an external command; replaced in tests so no real process starts.
typedef ProcessRunner =
    Future<ProcessResult> Function(String exe, List<String> args);

final processRunnerProvider = Provider<ProcessRunner>(
  (ref) => (exe, args) => Process.run(exe, args),
);

/// The command that starts the hub's background job, or null where there is
/// none: Windows = the scheduled task from `claude_dev/hub/install_hub.ps1`,
/// macOS = the launchd agent `io.livenow.hub` from
/// `app/macos/hub/install_hub_mac.sh` (`launchctl kickstart -k gui/<uid>/...`).
Future<(String, List<String>)?> hubStartCommand(
  ProcessRunner run, {
  String? os,
}) async {
  os ??= Platform.operatingSystem;
  if (os == 'windows') {
    return ('schtasks', ['/run', '/tn', 'LiveNow Hub']);
  }
  if (os == 'macos') {
    final uid = (await run('id', ['-u'])).stdout.toString().trim();
    if (uid.isEmpty) return null;
    return ('launchctl', ['kickstart', '-k', 'gui/$uid/io.livenow.hub']);
  }
  return null;
}

/// Starts the hub through its background job; true when the system accepted the
/// request. Tests replace it (or [processRunnerProvider]).
final hubStarterProvider = Provider<Future<bool> Function()>((ref) {
  final run = ref.read(processRunnerProvider);
  return () async {
    try {
      final cmd = await hubStartCommand(run);
      if (cmd == null) return false;
      return (await run(cmd.$1, cmd.$2)).exitCode == 0;
    } on Object {
      return false;
    }
  };
});

/// Runs calls against the hub's admin routes through a short-lived transport.
final hubAdminProvider = Provider<HubAdminAccess>(HubAdminAccess.new);

class HubAdminAccess {
  HubAdminAccess(this._ref);
  final Ref _ref;

  /// The hub peer this desktop is paired with, or null.
  Future<SyncPeer?> peer() async {
    final id = await _ref.read(syncStoreProvider).getState(_hubIdKey);
    if (id == null || id.isEmpty) return null;
    return _ref.read(syncPeersProvider).get(id);
  }

  Future<T> run<T>(Future<T> Function(HubAdminClient hub) body) async {
    final p = await peer();
    if (p == null) throw const SyncAuthException('not connected to a hub');
    final t = await _ref.read(syncTransportFactoryProvider)(p);
    if (t is! HttpTransport) throw StateError('the hub needs a network link');
    try {
      return await body(HubAdminClient(t));
    } finally {
      t.close();
    }
  }
}

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

/// Conflicts the HUB found while merging (the desktop window shows them next
/// to its own); empty when no hub is connected or it cannot be reached.
final hubConflictsProvider = FutureProvider.autoDispose<List<SyncConflict>>((
  ref,
) async {
  ref.watch(syncRevisionProvider);
  if (!ref.watch(hubConnectedProvider)) return const [];
  try {
    return await ref.read(hubAdminProvider).run((h) => h.conflicts());
  } on Object {
    return const [];
  }
});

/// The devices paired with the hub (phones, and this window itself).
final hubPeersProvider = FutureProvider.autoDispose<List<HubPeerInfo>>((
  ref,
) async {
  ref.watch(syncRevisionProvider);
  if (!ref.watch(hubConnectedProvider)) return const [];
  return ref.read(hubAdminProvider).run((h) => h.peers());
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
  Timer? _periodic;
  StreamSubscription<Object?>? _changes;
  bool _observing = false;

  /// While the app is open it also syncs this often, so what another device
  /// sent to the hub arrives without reopening the app.
  static const periodicSync = Duration(seconds: 60);

  @override
  SyncStatus build() {
    ref.onDispose(() {
      _debounce?.cancel();
      _periodic?.cancel();
      _changes?.cancel();
      if (_observing) WidgetsBinding.instance.removeObserver(this);
    });
    return const SyncStatus();
  }

  /// The device this one syncs with: the hub when this desktop is connected
  /// to one (its old phone pairings stay in the table), else the only peer.
  Future<SyncPeer?> _peer() async {
    final hub = await ref.read(hubAdminProvider).peer();
    if (hub != null) return hub;
    return (await ref.read(syncPeersProvider).all()).firstOrNull;
  }

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
      _periodic = Timer.periodic(periodicSync, (_) {
        if (state.phase != SyncPhase.unpaired &&
            state.phase != SyncPhase.syncing) {
          unawaited(syncNow());
        }
      });
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
            'The PC (hub) is not reachable. Is it on, with the LiveNow hub '
            'or LiveNow running, and are both on the same Wi-Fi or Tailscale?',
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
  ///
  /// [asHub]: the device is the always-on hub of this PC (desktop only, never
  /// with [replace]): it becomes this desktop's only sync partner, the old
  /// phone pairings of the host days are forgotten (the data stays) and the
  /// desktop turns from a server into a client.
  Future<SyncReport?> pairAndReplace(
    PairingUri code, {
    bool replace = true,
    bool asHub = false,
  }) async {
    assert(!(asHub && replace), 'the hub never replaces the desktop data');
    final store = ref.read(syncStoreProvider);
    final db = ref.read(databaseProvider);
    final peer = await pairWithServer(
      code: code,
      peers: ref.read(syncPeersProvider),
      myDeviceId: await store.deviceId(),
      myName: ref.read(syncDeviceNameProvider),
    );
    if (asHub) {
      await store.setState(_hubIdKey, peer.deviceId);
      final peers = ref.read(syncPeersProvider);
      for (final p in await peers.all()) {
        if (p.deviceId == peer.deviceId) continue;
        await peers.remove(p.deviceId);
        await store.forgetPeer(p.deviceId);
      }
      await ref.read(syncHostControllerProvider.notifier).stop();
      ref.read(hubConnectedProvider.notifier).set(true);
    }
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
    if (asHub) {
      // The desktop was a server until now: start watching, resume and the
      // periodic sync like a phone does (this also runs the first sync).
      await autoStart();
      return null;
    }
    return syncNow();
  }

  /// Connects this desktop to the always-on hub on this PC: reads the one-time
  /// pairing text the hub left in its own folder and pairs with "Keep both".
  /// Throws a [FormatException] with a plain message when there is none (the
  /// hub is not running, or this desktop is already connected to it).
  Future<void> connectLocalHub() async {
    final dir = await ref.read(hubDirectoryProvider)();
    final file = File('${dir.path}${Platform.pathSeparator}$kHubLocalPairFile');
    if (!file.existsSync()) {
      throw const FormatException(
        'The hub is not running here, or this PC is already connected to it. '
        'Start the hub first.',
      );
    }
    final code = PairingUri.parse(await file.readAsString());
    await pairAndReplace(code, replace: false, asHub: true);
  }

  /// Forgets the PC or hub (its data stays on this device).
  Future<void> forget() async {
    final peer = await _peer();
    if (peer != null) await ref.read(syncPeersProvider).remove(peer.deviceId);
    final store = ref.read(syncStoreProvider);
    if ((await store.getState(_hubIdKey))?.isNotEmpty ?? false) {
      // A desktop without its hub serves phones itself again.
      await store.setState(_hubIdKey, '');
      ref.read(hubConnectedProvider.notifier).set(false);
      state = const SyncStatus();
      ref.read(syncRevisionProvider.notifier).bump();
      unawaited(ref.read(syncHostControllerProvider.notifier).autoStart());
      return;
    }
    state = const SyncStatus();
    ref.read(syncRevisionProvider.notifier).bump();
  }
}

/// Starts what this device's role needs; called once by the home shell.
Future<void> startSyncForRole(WidgetRef ref) async {
  // A desktop that was connected to the hub last time is a client now.
  if (!Platform.isIOS && !Platform.isAndroid) {
    await ref.read(hubConnectedProvider.notifier).refresh();
  }
  switch (ref.read(syncRoleProvider)) {
    case SyncRole.host:
      await ref.read(syncHostControllerProvider.notifier).autoStart();
    case SyncRole.client:
      await ref.read(syncClientProvider.notifier).autoStart();
  }
}
