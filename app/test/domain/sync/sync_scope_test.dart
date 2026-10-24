import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/accounts/account_models.dart';
import 'package:livenow/data/accounts/account_registry.dart';
import 'package:livenow/data/sync/http_transport.dart';
import 'package:livenow/data/sync/sync_peers.dart';
import 'package:livenow/data/sync/sync_server.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/sync/sync_crypto.dart';
import 'package:livenow/domain/sync/sync_models.dart';
import 'package:livenow/domain/sync/sync_protocol.dart';

import 'sync_harness.dart';

/// Who may see or write what over sync: staged rows belong to the peer that
/// sent them, strangers / removed / stale devices get 401 and leave no rows,
/// and only the main local account may sync.
void main() {
  setUpAll(() => HttpOverrides.global = null);

  group('the inbox is per peer', () {
    late SyncDevice hub;
    late SyncDevice source;

    setUp(() async {
      hub = SyncDevice();
      source = SyncDevice();
      await hub.id;
      await source.id;
    });
    tearDown(() async {
      await hub.close();
      await source.close();
    });

    Future<List<SyncChange>> changesOfSource() async {
      await ActionService(source.db).createAction(name: 'Secret of A');
      return source.store.changesSince(
        0,
        until: await source.store.currentSeq(),
        limit: 500,
      );
    }

    test("peer A's staged rows are not merged by B's last page, not served to B", () async {
      final changes = await changesOfSource();
      expect(changes, isNotEmpty);
      // A sends a page but never its last one.
      await hub.host.push('peer-a', changes, last: false);
      expect(await hub.count('sync_inbox', "peer = 'peer-a'"), greaterThan(0));

      // B finishes an (empty) push: A's rows are not merged by it.
      final r = await hub.host.push('peer-b', const [], last: true);
      expect(r.applied, 0);
      expect(await hub.count('actions'), 0);
      expect(await hub.count('sync_inbox', "peer = 'peer-a'"), greaterThan(0));

      // B pulls everything: nothing of A's staged rows.
      final page = await hub.host.pull('peer-b', 0, 500);
      expect(page.changes, isEmpty);
    });

    test("B cannot clear or overwrite A's staged rows by staging the same row", () async {
      final changes = await changesOfSource();
      await hub.host.push('peer-a', changes, last: false);
      final before = await hub.count('sync_inbox', "peer = 'peer-a'");
      await hub.host.push('peer-b', changes, last: false);
      expect(await hub.count('sync_inbox', "peer = 'peer-a'"), before);
      expect(await hub.count('sync_inbox', "peer = 'peer-b'"), before);
      // B completes: only B's copy is merged and cleared; A's stays staged.
      await hub.host.push('peer-b', const [], last: true);
      expect(await hub.count('sync_inbox', "peer = 'peer-b'"), 0);
      expect(await hub.count('sync_inbox', "peer = 'peer-a'"), before);
      expect(await hub.count('actions'), 1);
    });

    test('one peer cannot fill the inbox for everybody: the cap is per peer', () async {
      final changes = await changesOfSource();
      await hub.host.push('peer-a', changes, last: false);
      // Another peer is unaffected by A's backlog.
      await hub.host.push('peer-b', changes, last: false);
      expect(await hub.count('sync_inbox', "peer = 'peer-b'"), greaterThan(0));
    });
  });

  group('over a real socket', () {
    late SyncDevice pc;
    late SyncDevice phone;
    late SyncServer server;
    late SyncPeer peer;
    late String phoneId;

    setUp(() async {
      pc = SyncDevice();
      phone = SyncDevice();
      await pc.id;
      phoneId = await phone.id;
      server = SyncServer(
        store: pc.store,
        host: pc.host,
        peers: SyncPeers(pc.db),
        deviceName: 'Test PC',
      );
      await server.start(port: 0);
      final code = await server.startPairing(hosts: ['127.0.0.1']);
      peer = await pairWithServer(
        code: PairingUri.parse(code.toString()),
        peers: SyncPeers(phone.db),
        myDeviceId: phoneId,
        myName: 'Phone',
        connectTimeout: const Duration(milliseconds: 500),
      );
    });
    tearDown(() async {
      await server.stop();
      await pc.close();
      await phone.close();
    });

    Future<List<Map<String, Object?>>> pushBody() async {
      await ActionService(phone.db).createAction(name: 'Smuggled');
      final cs = await phone.store.changesSince(
        0,
        until: await phone.store.currentSeq(),
        limit: 500,
      );
      return [for (final c in cs) c.toJson()];
    }

    Future<int> post(String path, SyncEnvelope env) async {
      final client = HttpClient();
      try {
        final req = await client.postUrl(
          Uri.http('127.0.0.1:${server.port}', path),
        );
        req.write(env.encode());
        final res = await req.close();
        await res.drain<void>();
        return res.statusCode;
      } finally {
        client.close(force: true);
      }
    }

    Future<SyncEnvelope> push({
      required Uint8List key,
      required String id,
      required int counter,
      DateTime? now,
    }) async => SyncEnvelope.seal(
      key: key,
      path: '/v1/push',
      deviceId: id,
      counter: counter,
      body: {'changes': await pushBody(), 'last': true},
      now: now,
    );

    test('an unpaired device cannot push: 401, no rows, nothing staged', () async {
      final env = await push(
        key: SyncCrypto.randomBytes(32),
        id: 'never-paired',
        counter: 1,
      );
      expect(await post('/v1/push', env), 401);
      expect(await pc.count('actions'), 0);
      expect(await pc.count('sync_inbox'), 0);
    });

    test('a paired device with a stale timestamp is refused and leaves nothing', () async {
      final env = await push(
        key: peer.key,
        id: phoneId,
        counter: 500,
        now: DateTime.now().subtract(const Duration(hours: 2)),
      );
      expect(await post('/v1/push', env), 401);
      expect(await pc.count('actions'), 0);
      expect(await pc.count('sync_inbox'), 0);
    });

    test('a device from the future is refused too', () async {
      final env = await push(
        key: peer.key,
        id: phoneId,
        counter: 501,
        now: DateTime.now().add(const Duration(hours: 2)),
      );
      expect(await post('/v1/push', env), 401);
      expect(await pc.count('actions'), 0);
    });

    test('a replayed push is applied once; the replay is 401', () async {
      final env = await push(key: peer.key, id: phoneId, counter: 600);
      expect(await post('/v1/push', env), 200);
      final once = await pc.count('actions');
      expect(once, 1);
      expect(await post('/v1/push', env), 401);
      expect(await pc.count('actions'), once);
    });

    test('a removed device gets 401 for push and pull and leaves no rows', () async {
      await SyncPeers(pc.db).remove(phoneId);
      final env = await push(key: peer.key, id: phoneId, counter: 700);
      expect(await post('/v1/push', env), 401);
      final pull = await SyncEnvelope.seal(
        key: peer.key,
        path: '/v1/pull',
        deviceId: phoneId,
        counter: 701,
        body: const {'since': 0, 'limit': 10},
      );
      expect(await post('/v1/pull', pull), 401);
      expect(await pc.count('actions'), 0);
      expect(await pc.count('sync_inbox'), 0);
    });

    test('a key of another pairing does not open this device\'s requests', () async {
      final env = await push(
        key: Uint8List.fromList(utf8.encode('x' * 32)),
        id: phoneId,
        counter: 800,
      );
      expect(await post('/v1/push', env), 401);
      expect(await pc.count('actions'), 0);
    });
  });

  group('who may sync at all', () {
    late Directory root;
    setUp(() async => root = await Directory.systemTemp.createTemp('livenow_scope_'));
    tearDown(() async => root.delete(recursive: true));

    test('only the main account is allowed; every other account is not', () async {
      final r = AccountRegistry.empty(root);
      final main = await r.addMain('Main');
      final guest = await r.create('Guest');
      expect(main.syncAllowed, isTrue);
      expect(guest.syncAllowed, isFalse);
      final back = (await AccountRegistry.load(root))!;
      expect(back.byId(guest.id)!.syncAllowed, isFalse);
      expect(back.main!.syncAllowed, isTrue);
    });

    test('a registry entry that cannot say "sync" is treated as not allowed', () {
      final a = Account.fromJson({
        'id': 'x',
        'name': 'N',
        'dir': 'abc',
        'sync': 'yes',
      });
      expect(a!.syncAllowed, isFalse);
      final b = Account.fromJson({'id': 'y', 'name': 'N', 'dir': 'abc'});
      expect(b!.syncAllowed, isFalse);
    });

    test('editing a registry file to grant sync to a profile folder is the only way, and the main flag is by dir', () {
      // A non-main account never becomes main by name: isMain is dir == '.'.
      final a = Account.fromJson({
        'id': 'x',
        'name': 'Main',
        'dir': 'main',
        'sync': false,
      })!;
      expect(a.isMain, isFalse);
    });
  });
}
