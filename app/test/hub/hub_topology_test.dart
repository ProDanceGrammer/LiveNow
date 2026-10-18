import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/sync/http_transport.dart';
import 'package:livenow/data/sync/sync_peers.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/sync/sync_protocol.dart';
import 'package:livenow/hub/hub_runner.dart';

import '../domain/sync/sync_harness.dart';

void main() {
  setUpAll(() => HttpOverrides.global = null);

  late SyncDevice hubDb;
  late SyncDevice desktop;
  late SyncDevice phone;
  late HubRunner hub;
  late Directory dir;
  final transports = <HttpTransport>[];

  setUp(() async {
    hubDb = SyncDevice();
    desktop = SyncDevice();
    phone = SyncDevice();
    await hubDb.id;
    await desktop.id;
    await phone.id;
    dir = await Directory.systemTemp.createTemp('hub_topology_test');
    hub = HubRunner(
      db: hubDb.db,
      dir: dir,
      port: 0,
      deviceName: 'Test hub',
      hosts: () async => ['127.0.0.1'],
    );
    await hub.start();
  });

  tearDown(() async {
    for (final t in transports) {
      t.close();
    }
    transports.clear();
    await hub.stop();
    await hubDb.close();
    await desktop.close();
    await phone.close();
    await dir.delete(recursive: true);
  });

  Future<HttpTransport> pairWith(SyncDevice device, PairingUri code) async {
    final peers = SyncPeers(device.db);
    final peer = await pairWithServer(
      code: PairingUri(
        deviceId: code.deviceId,
        port: hub.server.port,
        hosts: code.hosts,
        secret: code.secret,
      ),
      peers: peers,
      myDeviceId: await device.id,
      myName: 'Device',
      connectTimeout: const Duration(milliseconds: 500),
    );
    final t = HttpTransport(
      peers: peers,
      server: peer,
      myDeviceId: await device.id,
      connectTimeout: const Duration(milliseconds: 500),
    );
    transports.add(t);
    return t;
  }

  Future<HttpTransport> pairDesktop() => pairWith(
    desktop,
    PairingUri.parse(File('${dir.path}${Platform.pathSeparator}$kHubLocalPairFile').readAsStringSync()),
  );

  Future<HttpTransport> pairPhone(HttpTransport adminT) async {
    final start = await adminT.call('/v1/admin/pairing/start', const {});
    final code = PairingUri.parse(start['uri']! as String);
    final pairing = pairWith(phone, code);
    for (var i = 0; i < 100; i++) {
      final r = await adminT.call('/v1/admin/pending', const {});
      if (r['pending'] != null) {
        await adminT.call('/v1/admin/answer', {'approved': true});
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return pairing;
  }

  Future<List<Map<String, Object?>>> stamps(SyncDevice d) =>
      d.rows('SELECT tbl, row_id, hlc, origin FROM sync_versions '
          "WHERE tbl = 'actions' ORDER BY row_id");

  test('the hub starts empty, the desktop pushes all history with its stamps', () async {
    final svc = ActionService(desktop.db);
    for (var i = 0; i < 12; i++) {
      await svc.createAction(name: 'Old $i');
    }
    final dT = await pairDesktop();
    expect(await hubDb.count('actions'), 0);

    // "Keep both": cursors for this hub start from 0 (a fresh pairing has none).
    await desktop.store.forgetPeer(dT.server.deviceId);
    final report = await desktop.engine.sync(dT);
    expect(report.pushed, greaterThanOrEqualTo(12));

    expect(await hubDb.count('actions'), 12);
    expect(await stamps(hubDb), await stamps(desktop)); // same hlc + origin
    expect(await hubDb.dump(), await desktop.dump());
  });

  test('desktop and phone edit offline, then meet through the hub', () async {
    final dT = await pairDesktop();
    final pT = await pairPhone(dT);
    final dSvc = ActionService(desktop.db);
    final pSvc = ActionService(phone.db);

    // Both start from one shared action.
    final shared = await dSvc.createAction(name: 'Shared');
    await desktop.engine.sync(dT);
    await phone.engine.sync(pT);
    expect(await phone.count('actions'), 1);

    // Offline: each side edits and adds things; the SAME action is edited on
    // both, the phone's edit being the later one.
    await dSvc.createAction(name: 'Only on the desktop');
    await desktop.exec(
      "UPDATE actions SET name = 'Shared (desktop)' WHERE id = '$shared'",
    );
    await tick();
    await pSvc.createAction(name: 'Only on the phone');
    await phone.exec(
      "UPDATE actions SET name = 'Shared (phone)' WHERE id = '$shared'",
    );

    // They reach the hub one after the other, then each picks up the rest.
    await desktop.engine.sync(dT);
    await phone.engine.sync(pT);
    await desktop.engine.sync(dT);

    expect(await hubDb.count('actions'), 3);
    expect(await hubDb.dump(), await desktop.dump());
    expect(await hubDb.dump(), await phone.dump());
    final names = [
      for (final r in await hubDb.rows('SELECT name FROM actions')) r['name'],
    ];
    expect(names, containsAll(['Only on the desktop', 'Only on the phone']));
    expect(names, contains('Shared (phone)')); // the later edit wins
    expect(names, isNot(contains('Shared (desktop)')));
  });

  test('the hub keeps serving after the desktop disconnects', () async {
    final dT = await pairDesktop();
    final pT = await pairPhone(dT);
    await ActionService(phone.db).createAction(name: 'Written on the phone');
    await phone.engine.sync(pT);
    // Nobody else is online; the hub holds the data.
    expect(await hubDb.count('actions'), 1);
    // Later the desktop (which was off) catches up.
    await desktop.engine.sync(dT);
    expect(await desktop.count('actions'), 1);
  });

  test('re-pairing with "Keep both" loses nothing on either side', () async {
    final dT = await pairDesktop();
    final pT = await pairPhone(dT);
    await ActionService(desktop.db).createAction(name: 'D1');
    await ActionService(phone.db).createAction(name: 'P1');
    await desktop.engine.sync(dT);
    await phone.engine.sync(pT);

    // Both edit offline, then the phone is re-paired (cursors forgotten).
    await ActionService(phone.db).createAction(name: 'P2 written unsynced');
    await ActionService(desktop.db).createAction(name: 'D2');
    await phone.store.forgetPeer(pT.server.deviceId);
    await desktop.engine.sync(dT);
    await phone.engine.sync(pT);
    await desktop.engine.sync(dT);

    for (final d in [hubDb, desktop, phone]) {
      expect(await d.count('actions'), 4);
    }
    expect(await hubDb.dump(), await phone.dump());
  });

  test('the hub writes its log and starts the backup folder setting', () async {
    final log = File('${dir.path}${Platform.pathSeparator}hub.log');
    expect(log.readAsStringSync(), contains('listening'));
    final s = jsonDecode(
      File('${dir.path}${Platform.pathSeparator}auto_backup.json')
          .readAsStringSync(),
    ) as Map;
    expect(s['enabled'], isTrue);
    expect(s['folder'], endsWith('backups'));
  });
}
