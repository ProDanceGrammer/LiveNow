import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../data/database.dart';
import '../domain/sync/sync_protocol.dart';
import 'hub_runner.dart';

/// `livenow.exe --hub [--hub-dir PATH] [--hub-port N]`: the sync hub, with no
/// window (nothing is ever drawn, so the runner never shows its window).
bool isHubMode(List<String> args) => args.contains('--hub');

String? _option(List<String> args, String name) {
  final i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}

/// The hub's own data folder: `--hub-dir`, else `LIVENOW_HUB_DIR`, else
/// `LIVENOW_DATA_DIR` (isolated test runs), else a `hub` folder inside the
/// app-support folder (never the desktop app's data). The desktop window uses
/// the same rule to find the hub's local pairing text.
Future<Directory> hubDirectory(List<String> args) async {
  final given = _option(args, '--hub-dir');
  if (given != null && given.isNotEmpty) return Directory(given);
  final hubEnv = Platform.environment['LIVENOW_HUB_DIR'];
  if (hubEnv != null && hubEnv.isNotEmpty) return Directory(hubEnv);
  final env = Platform.environment['LIVENOW_DATA_DIR'];
  if (env != null && env.isNotEmpty) return Directory(env);
  final base = await getApplicationSupportDirectory();
  return Directory('${base.path}${Platform.pathSeparator}hub');
}

Future<void> runHub(List<String> args) async {
  final dir = await hubDirectory(args);
  await dir.create(recursive: true);
  databaseDirectoryOverride = dir;
  final port = int.tryParse(_option(args, '--hub-port') ?? '') ?? syncPort;
  final log = HubLog(File('${dir.path}${Platform.pathSeparator}hub.log'));
  log.write('hub starting (data: ${dir.path}, port: $port)');
  String name;
  try {
    name = 'LiveNow hub (${Platform.localHostname})';
  } on Object {
    name = 'LiveNow hub';
  }
  final db = AppDatabase();
  final hub = HubRunner(db: db, dir: dir, port: port, deviceName: name);
  try {
    await hub.start();
  } on SocketException catch (e) {
    // The port is taken: another hub is already running. A quiet, clean exit
    // (code 0) so the scheduled task does not treat it as a crash.
    log.write('cannot listen on $port (${e.message}); exiting');
    await db.close();
    exit(0);
  } on Object catch (e, st) {
    log.write('hub failed: $e\n$st');
    await db.close();
    exit(1);
  }
  ProcessSignal.sigint.watch().listen((_) async {
    await hub.stop();
    await db.close();
    exit(0);
  });
}
