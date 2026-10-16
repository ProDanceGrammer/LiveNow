import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/sync/http_transport.dart';
import 'package:livenow/data/sync/sync_peers.dart';
import 'package:livenow/data/sync/sync_server.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/sync/sync_engine.dart';
import 'package:livenow/domain/sync/sync_crypto.dart';
import 'package:livenow/domain/sync/sync_protocol.dart';

import 'sync_harness.dart';

void main() {
  // flutter_test replaces dart:io's HttpClient with a stub that answers 400.
  setUpAll(() => HttpOverrides.global = null);

  group('crypto', () {
    final key = SyncCrypto.randomBytes(32);

    test('seal then open returns the message', () async {
      final box = await SyncCrypto.seal(key, utf8.encode('hello'), 'ctx');
      final clear = await SyncCrypto.open(key, box.nonce, box.data, 'ctx');
      expect(utf8.decode(clear), 'hello');
    });

    test('a wrong key, a changed byte or other context is refused', () async {
      final box = await SyncCrypto.seal(key, utf8.encode('hello'), 'ctx');
      expect(
        SyncCrypto.open(SyncCrypto.randomBytes(32), box.nonce, box.data, 'ctx'),
        throwsA(isA<SyncAuthException>()),
      );
      final bent = Uint8List.fromList(box.data)..[0] ^= 1;
      expect(
        SyncCrypto.open(key, box.nonce, bent, 'ctx'),
        throwsA(isA<SyncAuthException>()),
      );
      expect(
        SyncCrypto.open(key, box.nonce, box.data, 'other'),
        throwsA(isA<SyncAuthException>()),
      );
    });

    test('key derivation is deterministic and context separated', () async {
      final secret = SyncCrypto.randomBytes(16);
      expect(
        await SyncCrypto.deriveKey(secret, 'a'),
        await SyncCrypto.deriveKey(secret, 'a'),
      );
      expect(
        await SyncCrypto.deriveKey(secret, 'a'),
        isNot(await SyncCrypto.deriveKey(secret, 'b')),
      );
    });
  });

  group('protocol', () {
    test('the pairing code survives a round trip', () {
      final code = PairingUri(
        deviceId: 'abc',
        port: 47653,
        hosts: const ['192.168.1.5', 'pc'],
        secret: SyncCrypto.randomBytes(16),
      );
      final back = PairingUri.parse(code.toString());
      expect(back.deviceId, 'abc');
      expect(back.port, 47653);
      expect(back.hosts, ['192.168.1.5', 'pc']);
      expect(back.secret, code.secret);
      expect(() => PairingUri.parse('https://x'), throwsFormatException);
    });

    test('an old or future timestamp is refused', () async {
      final key = SyncCrypto.randomBytes(32);
      final env = await SyncEnvelope.seal(
        key: key,
        path: '/v1/hello',
        deviceId: 'd',
        counter: 1,
        body: const {},
        now: DateTime.now().subtract(const Duration(minutes: 10)),
      );
      expect(env.open(key, '/v1/hello'), throwsA(isA<SyncAuthException>()));
    });

    test('an envelope is bound to its path', () async {
      final key = SyncCrypto.randomBytes(32);
      final env = await SyncEnvelope.seal(
        key: key,
        path: '/v1/pull',
        deviceId: 'd',
        counter: 1,
        body: const {},
      );
      expect(env.open(key, '/v1/push'), throwsA(isA<SyncAuthException>()));
      expect(await env.open(key, '/v1/pull'), isEmpty);
    });
  });

  group('over a real socket', () {
    late SyncDevice pc;
    late SyncDevice phone;
    late SyncServer server;

    setUp(() async {
      pc = SyncDevice();
      phone = SyncDevice();
      await pc.id;
      await phone.id;
      server = SyncServer(
        store: pc.store,
        host: pc.host,
        peers: SyncPeers(pc.db),
        deviceName: 'Test PC',
      );
      await server.start(port: 0);
    });

    tearDown(() async {
      await server.stop();
      await pc.close();
      await phone.close();
    });

    Future<(SyncPeer, HttpTransport)> pair({String name = 'Phone'}) async {
      final code = await server.startPairing(hosts: ['127.0.0.1']);
      final peers = SyncPeers(phone.db);
      final peer = await pairWithServer(
        code: PairingUri.parse(code.toString()),
        peers: peers,
        myDeviceId: await phone.id,
        myName: name,
        connectTimeout: const Duration(milliseconds: 500),
      );
      return (
        peer,
        HttpTransport(
          peers: peers,
          server: peer,
          myDeviceId: await phone.id,
          connectTimeout: const Duration(milliseconds: 500),
        ),
      );
    }

    test('pairing stores the key on both sides and burns the code', () async {
      final (peer, _) = await pair();
      expect(peer.deviceId, await pc.id);
      expect(peer.name, 'Test PC');
      final theirs = await SyncPeers(pc.db).get(await phone.id);
      expect(theirs!.key, peer.key);
      expect(theirs.name, 'Phone');
      expect(server.pairingOpen, isFalse);
    });

    test('the PC replaces the phone, then both sides keep merging', () async {
      await ActionService(pc.db).createAction(name: 'On the PC');
      await ActionService(phone.db).createAction(name: 'Old phone data');
      final (_, transport) = await pair();

      await phone.store.wipeForReplace();
      expect(await phone.count('actions'), 0);
      final first = await phone.engine.sync(transport);
      expect(first.pulled, greaterThan(0));
      expect(await phone.dump(), equals(await pc.dump()));

      await ActionService(phone.db).createAction(name: 'Made on the phone');
      await tick();
      await ActionService(pc.db).createAction(name: 'Made on the PC');
      await phone.engine.sync(transport);
      expect(await phone.dump(), equals(await pc.dump()));
      expect(await pc.count('actions'), 3);
    });

    test(
      'a wrong pairing secret is refused and the code dies after five',
      () async {
        final code = await server.startPairing(hosts: ['127.0.0.1']);
        final bad = PairingUri(
          deviceId: code.deviceId,
          port: code.port,
          hosts: code.hosts,
          secret: SyncCrypto.randomBytes(16),
        );
        for (var i = 0; i < pairingMaxAttempts; i++) {
          expect(
            pairWithServer(
              code: bad,
              peers: SyncPeers(phone.db),
              myDeviceId: await phone.id,
              myName: 'Intruder',
            ),
            throwsA(isA<SyncAuthException>()),
          );
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(server.pairingOpen, isFalse);
        // Even the right secret no longer works.
        await expectLater(
          pairWithServer(
            code: code,
            peers: SyncPeers(phone.db),
            myDeviceId: await phone.id,
            myName: 'Late',
          ),
          throwsA(isA<SyncAuthException>()),
        );
        expect(await SyncPeers(pc.db).all(), isEmpty);
      },
    );

    test('a pairing code works once', () async {
      final code = await server.startPairing(hosts: ['127.0.0.1']);
      await pairWithServer(
        code: code,
        peers: SyncPeers(phone.db),
        myDeviceId: await phone.id,
        myName: 'First',
      );
      final other = SyncDevice();
      await other.id;
      await expectLater(
        pairWithServer(
          code: code,
          peers: SyncPeers(other.db),
          myDeviceId: await other.id,
          myName: 'Second',
        ),
        throwsA(isA<SyncAuthException>()),
      );
      await other.close();
    });

    test('a stranger, a replayed request and a bent request get 401', () async {
      final (peer, transport) = await pair();
      await transport.hello(); // counter 1 is used

      Future<int> post(String body, [String path = '/v1/hello']) async {
        final client = HttpClient();
        final req = await client.postUrl(
          Uri.http('127.0.0.1:${server.port}', path),
        );
        req.write(body);
        final res = await req.close();
        await res.drain<void>();
        client.close(force: true);
        return res.statusCode;
      }

      Future<SyncEnvelope> make(int counter, {String? as, Uint8List? key}) =>
          SyncEnvelope.seal(
            key: key ?? peer.key,
            path: '/v1/hello',
            deviceId: as ?? 'phone-id',
            counter: counter,
            body: const {},
          );

      // The phone's real id, a fresh counter: accepted.
      final id = await phone.id;
      final good = await make(50, as: id);
      expect(await post(good.encode()), 200);
      // The very same bytes again: replay.
      expect(await post(good.encode()), 401);
      // An older counter, even if freshly sealed.
      expect(await post((await make(10, as: id)).encode()), 401);
      // A device the PC has never paired.
      expect(await post((await make(60, as: 'stranger')).encode()), 401);
      // The right device but a key that is not the shared one.
      expect(
        await post(
          (await make(70, as: id, key: SyncCrypto.randomBytes(32))).encode(),
        ),
        401,
      );
      // A flipped byte inside the cipher text.
      final env = await make(80, as: id);
      final bent = SyncEnvelope(
        deviceId: env.deviceId,
        counter: env.counter,
        timeMs: env.timeMs,
        nonce: env.nonce,
        data: Uint8List.fromList(env.data)..[0] ^= 1,
      );
      expect(await post(bent.encode()), 401);
      // Garbage, and a path that does not exist.
      expect(await post('not json'), 401);
      expect(await post(good.encode(), '/v1/nope'), 404);
    });

    test('the server says nothing to a plain GET', () async {
      final client = HttpClient();
      final req = await client.getUrl(
        Uri.http('127.0.0.1:${server.port}', '/'),
      );
      final res = await req.close();
      expect(res.statusCode, 404);
      expect(await utf8.decoder.bind(res).join(), isEmpty);
      client.close(force: true);
    });

    test('an unreachable PC is reported, a dead address is skipped', () async {
      final (peer, _) = await pair();
      final peers = SyncPeers(phone.db);
      // Only a dead address: unreachable.
      await peers.setAddresses(peer.deviceId, ['203.0.113.1']);
      final dead = HttpTransport(
        peers: peers,
        server: (await peers.get(peer.deviceId))!,
        myDeviceId: await phone.id,
        connectTimeout: const Duration(milliseconds: 300),
      );
      await expectLater(dead.hello(), throwsA(isA<SyncUnreachable>()));

      // A dead address first, a live one second: works and is remembered.
      await peers.setAddresses(peer.deviceId, ['203.0.113.1', '127.0.0.1']);
      final ok = HttpTransport(
        peers: peers,
        server: (await peers.get(peer.deviceId))!,
        myDeviceId: await phone.id,
        connectTimeout: const Duration(milliseconds: 300),
      );
      expect((await ok.hello()).deviceId, await pc.id);
      expect((await peers.get(peer.deviceId))!.addresses.first, '127.0.0.1');
    });

    test('hello reports the sync version of the PC', () async {
      final (_, transport) = await pair();
      final hello = await transport.hello();
      expect(hello.schemaVersion, kSyncWireVersion);
    });
  });
}
