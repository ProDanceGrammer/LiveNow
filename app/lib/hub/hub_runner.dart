import 'dart:async';
import 'dart:io';

import '../data/backup/auto_backup.dart';
import '../data/database.dart';
import '../data/sync/hub_admin.dart';
import '../data/sync/sync_peers.dart';
import '../data/sync/sync_server.dart';
import '../data/sync/sync_store.dart';
import '../domain/metric_service.dart';
import '../domain/sync/sync_engine.dart';
import '../domain/sync/sync_protocol.dart';
import 'ai_admin_routes.dart';
import 'ai_hub_reads.dart';
import 'ai_photo_store.dart';
import 'ai_worker.dart';

/// The file the hub writes its one-time local pairing text to, until the
/// desktop window has connected.
const kHubLocalPairFile = 'local_pair.txt';

/// A tiny log (`hub.log`, one rotation at 512 KB): the hub has no window.
class HubLog {
  HubLog(this.file);
  final File? file;
  static const _max = 512 * 1024;

  void write(String line) {
    final f = file;
    if (f == null) return;
    try {
      f.parent.createSync(recursive: true);
      if (f.existsSync() && f.lengthSync() > _max) {
        final old = File('${f.path}.1');
        if (old.existsSync()) old.deleteSync();
        f.renameSync(old.path);
      }
      f.writeAsStringSync(
        '${DateTime.now().toIso8601String()} $line\n',
        mode: FileMode.append,
      );
    } on Object {
      // Logging must never stop the hub.
    }
  }
}

/// The always-on sync database: serves the paired devices (desktop window,
/// phones) from its OWN database, with no UI. Kept apart from the Flutter entry
/// point so a test can run it over an in-memory database.
class HubRunner {
  HubRunner({
    required this.db,
    required this.dir,
    this.port = syncPort,
    this.deviceName = 'LiveNow hub',
    this.hosts,
    this.backups = true,
  }) : log = HubLog(File('${dir.path}${Platform.pathSeparator}hub.log'));

  final AppDatabase db;
  final Directory dir;
  final int port;
  final String deviceName;
  final Future<List<String>> Function()? hosts;

  /// Automatic backups (every 5 h, the newest 5) into `<dir>/backups`.
  final bool backups;
  final HubLog log;

  late final SyncStore store;
  late final SyncPeers peers;
  late final SyncServer server;
  late final HubAdmin admin;

  /// The photo originals, `<dir>/ai_photos`.
  late final AiPhotoStore photos;

  /// Runs the assistant's jobs (idle while there are none).
  late final AiWorker aiWorker;
  AutoBackupScheduler? _backupScheduler;
  Timer? _renewal;

  Future<void> start() async {
    store = SyncStore(
      db,
      afterApply: (tables) async {
        // Derived weights are not synced; the hub keeps them right like every
        // device does.
        if (tables.contains('metrics') ||
            tables.contains('metric_dependencies')) {
          await MetricService(db).recomputeWeights();
        }
      },
    );
    peers = SyncPeers(db);
    server = SyncServer(
      store: store,
      host: SyncHost(store, kSyncWireVersion),
      peers: peers,
      deviceName: deviceName,
    );
    photos = AiPhotoStore(
      Directory('${dir.path}${Platform.pathSeparator}ai_photos'),
    );
    await photos.root.create(recursive: true);
    server.ai = AiHubReads(db: db, photos: photos);
    admin = HubAdmin(
      server: server,
      store: store,
      peers: peers,
      deviceName: deviceName,
      bootstrapFile: File('${dir.path}${Platform.pathSeparator}$kHubLocalPairFile'),
      hosts: hosts ?? localAddresses,
    );
    admin.extraRoutes = AiAdminRoutes(db).handle;
    aiWorker = AiWorker(db: db, photos: photos, log: log.write);
    // Throws a SocketException when the port is taken (another hub runs).
    await server.start(port: port);
    log.write('hub listening on port ${server.port}');
    await admin.ensureBootstrap();
    // The bootstrap offer lasts 12 h: renew it while no admin device exists.
    _renewal = Timer.periodic(const Duration(minutes: 30), (_) {
      admin.ensureBootstrap().catchError((Object e) {
        log.write('bootstrap renewal failed: $e');
      });
    });
    if (backups) await _startBackups();
    await aiWorker.start();
  }

  Future<void> _startBackups() async {
    final store = AutoBackupStore(
      File('${dir.path}${Platform.pathSeparator}auto_backup.json'),
    );
    var s = await store.load();
    if (!s.ready) {
      s = s.copyWith(
        enabled: true,
        folder: '${dir.path}${Platform.pathSeparator}backups',
      );
      await store.save(s);
    }
    final scheduler = AutoBackupScheduler(
      AutoBackupRunner(db, store),
      onResult: (r) => log.write(
        'backup ${r.outcome.name}${r.error == null ? '' : ': ${r.error}'}',
      ),
    );
    _backupScheduler = scheduler;
    await scheduler.reschedule();
  }

  Future<void> stop() async {
    _renewal?.cancel();
    await aiWorker.stop();
    _backupScheduler?.dispose();
    admin.dispose();
    await server.stop();
    log.write('hub stopped');
  }
}
