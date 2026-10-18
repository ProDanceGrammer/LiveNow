import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/sync/http_transport.dart';
import 'package:livenow/data/sync/hub_admin.dart';
import 'package:livenow/data/sync/sync_peers.dart';
import 'package:livenow/data/sync/sync_server.dart';
import 'package:livenow/domain/sync/sync_crypto.dart';
import 'package:livenow/domain/sync/sync_protocol.dart';

import '../domain/sync/sync_harness.dart';

void main() {
  // flutter_test replaces dart:io's HttpClient with a stub that answers 400.
  setUpAll(() => HttpOverrides.global = null);

  late SyncDevice hub;
  late SyncDevice desktop;
  late SyncDevice phone;
  late SyncServer server;
  late HubAdmin admin;
  late Directory dir;
  late File bootstrap;
  final transports = <HttpTransport>[];

  setUp(() async {
    hub = SyncDevice();
    desktop = SyncDevice();
    phone = SyncDevice();
    await hub.id;
    await desktop.id;
    await phone.id;
    dir = await Directory.systemTemp.createTemp('hub_admin_test');
    bootstrap = File('${dir.path}${Platform.pathSeparator}local_pair.txt');
    server = SyncServer(
      store: hub.store,
      host: hub.host,
      peers: SyncPeers(hub.db),
      deviceName: 'Test hub',
    );
    admin = HubAdmin(
      server: server,
      store: hub.store,
      peers: SyncPeers(hub.db),
      bootstrapFile: bootstrap,
      hosts: () async => ['127.0.0.1'],
    );
    await server.start(port: 0);
  });

  tearDown(() async {
    for (final t in transports) {
      t.close();
    }
    transports.clear();
    admin.dispose();
    await server.stop();
    await hub.close();
    await desktop.close();
    await phone.close();
    await dir.delete(recursive: true);
  });

  Future<PairingUri> localCode() async {
    final text = await bootstrap.readAsString();
    // The offer was written for this port-less hub: point it at the test port.
    final c = PairingUri.parse(text);
    return PairingUri(
      deviceId: c.deviceId,
      port: server.port,
      hosts: c.hosts,
      secret: c.secret,
    );
  }

  Future<HttpTransport> connect(
    SyncDevice device,
    PairingUri code, {
    String name = 'Device',
  }) async {
    final peers = SyncPeers(device.db);
    final peer = await pairWithServer(
      code: code,
      peers: peers,
      myDeviceId: await device.id,
      myName: name,
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

  Future<HttpTransport> pairDesktop() async {
    await admin.ensureBootstrap();
    return connect(desktop, await localCode(), name: 'Desktop');
  }

  test('the first local pairing needs no approval and makes the admin', () async {
    var asked = false;
    server.approvePairing = (_) async {
      asked = true;
      return false;
    };
    await admin.ensureBootstrap();
    expect(bootstrap.existsSync(), isTrue);

    final t = await connect(desktop, await localCode(), name: 'Desktop');
    expect(asked, isFalse);
    expect(
      await hub.store.getState(adminStateKey(await desktop.id)),
      '1',
    );
    // The file is gone, and no new one is written while an admin exists.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(bootstrap.existsSync(), isFalse);
    await admin.ensureBootstrap();
    expect(bootstrap.existsSync(), isFalse);

    final status = await t.call('/v1/admin/status', const {});
    expect(status['device'], await hub.id);
    expect(status['peers'], 1);
  });

  test('the bootstrap code works once only', () async {
    await admin.ensureBootstrap();
    final code = await localCode();
    await connect(desktop, code, name: 'Desktop');
    await expectLater(
      connect(phone, code, name: 'Late'),
      throwsA(isA<SyncAuthException>()),
    );
  });

  test('a paired phone that is not the admin cannot call admin routes', () async {
    final desktopT = await pairDesktop();
    final start = await desktopT.call('/v1/admin/pairing/start', const {});
    final code = PairingUri.parse(start['uri']! as String);
    // Approve from the desktop side while the phone pairs.
    final pairing = connect(phone, PairingUri(
      deviceId: code.deviceId,
      port: server.port,
      hosts: code.hosts,
      secret: code.secret,
    ), name: 'iPhone');
    await _approveNext(desktopT, true);
    final phoneT = await pairing;

    await expectLater(
      phoneT.call('/v1/admin/status', const {}),
      throwsA(isA<SyncAuthException>()),
    );
    // The desktop still can, and sees both devices.
    final peers = await desktopT.call('/v1/admin/peers', const {});
    final list = (peers['peers']! as List).cast<Map>();
    expect(list.map((p) => p['name']), containsAll(['Desktop', 'iPhone']));
    expect(
      list.firstWhere((p) => p['name'] == 'iPhone')['admin'],
      isFalse,
    );
  });

  test('declining the pairing refuses the phone; no answer refuses too', () async {
    final desktopT = await pairDesktop();
    final start = await desktopT.call('/v1/admin/pairing/start', const {});
    final code = PairingUri.parse(start['uri']! as String);
    final withPort = PairingUri(
      deviceId: code.deviceId,
      port: server.port,
      hosts: code.hosts,
      secret: code.secret,
    );
    final pairing = connect(phone, withPort, name: 'Stranger');
    // Attach the matcher before the answer arrives, so the failure has a listener.
    final refused = expectLater(pairing, throwsA(isA<SyncAuthException>()));
    await _approveNext(desktopT, false);
    await refused;
    expect(await SyncPeers(hub.db).get(await phone.id), isNull);
  });

  test('pending shows nothing when nobody is pairing', () async {
    final desktopT = await pairDesktop();
    final r = await desktopT.call('/v1/admin/pending', const {});
    expect(r['pending'], isNull);
  });

  test('admin paths look like unknown paths to everyone else', () async {
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final req = await client.postUrl(
      Uri.http('127.0.0.1:${server.port}', '/v1/admin/status'),
    );
    req.write('{}');
    final res = await req.close();
    // From loopback, but with no valid envelope: a bad request or refusal,
    // never data; and a GET is a plain 404.
    expect(res.statusCode, anyOf(400, 401, 404));
    await res.drain<void>();
    final get = await (await client.getUrl(
      Uri.http('127.0.0.1:${server.port}', '/v1/admin/status'),
    )).close();
    expect(get.statusCode, 404);
    await get.drain<void>();
  });

  test('an unknown admin route fails cleanly', () async {
    final desktopT = await pairDesktop();
    await expectLater(
      desktopT.call('/v1/admin/nothing', const {}),
      throwsA(isA<HttpException>()),
    );
    // The hub still answers afterwards.
    expect((await desktopT.call('/v1/admin/status', const {}))['wire'], isNotNull);
  });

  test('conflicts are listed, marked seen and a deleted loser restores to nothing', () async {
    final desktopT = await pairDesktop();
    await hub.exec(
      'INSERT INTO sync_conflicts (tbl, row_id, label, detected_at, '
      'loser_hlc, loser_origin, winner_hlc, loser_json) '
      "VALUES ('actions', 'a1', 'Lost edit', '2026-10-18T10:00:00.000000Z', "
      "'h1', 'phone', 'h2', NULL)",
    );
    final r = await desktopT.call('/v1/admin/conflicts', const {});
    final list = (r['conflicts']! as List).cast<Map<String, Object?>>();
    expect(list, hasLength(1));
    final c = conflictFromJson(list.single);
    expect(c.label, 'Lost edit');
    expect(c.seen, isFalse);

    expect(
      (await desktopT.call('/v1/admin/status', const {}))['unseenConflicts'],
      1,
    );
    await desktopT.call('/v1/admin/conflicts/seen', const {});
    expect(
      (await desktopT.call('/v1/admin/status', const {}))['unseenConflicts'],
      0,
    );

    final res = await desktopT.call('/v1/admin/conflicts/restore', {'id': c.id});
    expect(res['restored'], isFalse);
    expect(
      (await desktopT.call('/v1/admin/conflicts', const {}))['conflicts'],
      isEmpty,
    );
  });

  test('removing a phone forgets it and its keys stop working', () async {
    final desktopT = await pairDesktop();
    final start = await desktopT.call('/v1/admin/pairing/start', const {});
    final code = PairingUri.parse(start['uri']! as String);
    final pairing = connect(phone, PairingUri(
      deviceId: code.deviceId,
      port: server.port,
      hosts: code.hosts,
      secret: code.secret,
    ), name: 'iPhone');
    await _approveNext(desktopT, true);
    final phoneT = await pairing;
    expect((await phoneT.hello()).deviceId, await hub.id);

    await desktopT.call('/v1/admin/peers/remove', {'deviceId': await phone.id});
    await expectLater(phoneT.hello(), throwsA(isA<SyncAuthException>()));
  });
}

/// Waits for the hub to show a pending pairing request, then answers it.
Future<void> _approveNext(HttpTransport desktop, bool approved) async {
  for (var i = 0; i < 100; i++) {
    final r = await desktop.call('/v1/admin/pending', const {});
    if (r['pending'] != null) {
      await desktop.call('/v1/admin/answer', {'approved': approved});
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('the hub never showed a pending pairing request');
}
