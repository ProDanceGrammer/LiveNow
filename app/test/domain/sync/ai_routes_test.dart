import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/sync/http_transport.dart';
import 'package:livenow/data/sync/sync_peers.dart';
import 'package:livenow/data/sync/sync_server.dart';
import 'package:livenow/domain/sync/sync_crypto.dart';
import 'package:livenow/domain/sync/sync_protocol.dart';
import 'package:livenow/hub/ai_hub_reads.dart';
import 'package:livenow/hub/ai_photo_store.dart';

import 'sync_harness.dart';

const _id1 = '11111111-1111-1111-1111-111111111111';

void main() {
  setUpAll(() => HttpOverrides.global = null);

  group('AiPhotoStore', () {
    late Directory dir;
    late AiPhotoStore store;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('ai_photos_test');
      store = AiPhotoStore(Directory('${dir.path}/ai_photos'));
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('saves atomically and reads back with the mime', () async {
      await store.save(_id1, Uint8List.fromList([1, 2, 3]), 'image/jpeg');
      expect((await store.read(_id1))!.data, [1, 2, 3]);
      expect((await store.read(_id1))!.mime, 'image/jpeg');
      // No temp file is left behind.
      final names = store.root.listSync().map((e) => e.path).toList();
      expect(names.where((n) => n.endsWith('.tmp')), isEmpty);
      expect(names.single.endsWith('$_id1.jpg'), isTrue);
      // A png under the same id replaces the jpg.
      await store.save(_id1, Uint8List.fromList([9]), 'image/png');
      expect((await store.read(_id1))!.mime, 'image/png');
      expect(store.root.listSync(), hasLength(1));
      expect(await store.exists(_id1), isTrue);
      await store.delete(_id1);
      expect(await store.exists(_id1), isFalse);
      expect(await store.read(_id1), isNull);
    });

    test('ids with separators or dots are rejected', () async {
      for (final bad in ['../evil', '..\\evil', 'a/b', 'abcdefgh.jpg', '']) {
        expect(isSafeBlobId(bad), isFalse, reason: bad);
        await expectLater(
          store.save(bad, Uint8List.fromList([1]), 'image/jpeg'),
          throwsArgumentError,
        );
        expect(await store.read(bad), isNull);
        expect(await store.exists(bad), isFalse);
      }
      expect(dir.listSync().whereType<File>(), isEmpty);
    });

    test('purges by age', () async {
      await store.save(_id1, Uint8List.fromList([1]), 'image/jpeg');
      const id2 = '22222222-2222-2222-2222-222222222222';
      await store.save(id2, Uint8List.fromList([2]), 'image/png');
      File('${store.root.path}/$_id1.jpg').setLastModifiedSync(
        DateTime.now().subtract(const Duration(days: 40)),
      );
      expect(await store.purgeOlderThan(const Duration(days: 30)), 1);
      expect(await store.exists(_id1), isFalse);
      expect(await store.exists(id2), isTrue);
    });
  });

  group('over a real socket', () {
    late SyncDevice pc;
    late SyncDevice phone;
    late SyncServer server;
    late Directory dir;
    late AiPhotoStore photos;
    late HttpTransport transport;
    late SyncPeer peer;

    Future<void> msg(String id, String thread, String at) => pc.exec(
      "INSERT INTO ai_messages (id, thread_id, body, created_at, updated_at) "
      "VALUES (?, ?, ?, ?, ?)",
      [id, thread, 'text $id', at, at],
    );

    setUp(() async {
      pc = SyncDevice();
      phone = SyncDevice();
      await pc.id;
      await phone.id;
      dir = Directory.systemTemp.createTempSync('ai_routes_test');
      photos = AiPhotoStore(Directory('${dir.path}/ai_photos'));
      server = SyncServer(
        store: pc.store,
        host: pc.host,
        peers: SyncPeers(pc.db),
      )..ai = AiHubReads(db: pc.db, photos: photos);
      await server.start(port: 0);
      final code = await server.startPairing(hosts: ['127.0.0.1']);
      final peers = SyncPeers(phone.db);
      peer = await pairWithServer(
        code: PairingUri.parse(code.toString()),
        peers: peers,
        myDeviceId: await phone.id,
        myName: 'Phone',
        connectTimeout: const Duration(milliseconds: 500),
      );
      transport = HttpTransport(
        peers: peers,
        server: peer,
        myDeviceId: await phone.id,
        connectTimeout: const Duration(milliseconds: 500),
      );
    });

    tearDown(() async {
      transport.close();
      await server.stop();
      await pc.close();
      await phone.close();
      dir.deleteSync(recursive: true);
    });

    test('history pages one thread newest first, with a cursor', () async {
      for (var i = 1; i <= 5; i++) {
        await msg('m$i-aaaaaaaa', 'T1', '2026-01-0${i}T00:00:00.000000Z');
      }
      await msg('x-aaaaaaaaaa', 'T2', '2026-01-03T00:00:00.000000Z');

      final p1 = await transport.fetchAiHistory('T1', limit: 2);
      expect(p1.messages.map((m) => m['id']), ['m4-aaaaaaaa', 'm5-aaaaaaaa']);
      expect(p1.more, isTrue);
      expect(p1.messages.first['thread_id'], 'T1');

      final p2 = await transport.fetchAiHistory(
        'T1',
        limit: 2,
        before: p1.messages.first['created_at']! as String,
      );
      expect(p2.messages.map((m) => m['id']), ['m2-aaaaaaaa', 'm3-aaaaaaaa']);
      expect(p2.more, isTrue);

      final p3 = await transport.fetchAiHistory(
        'T1',
        before: p2.messages.first['created_at']! as String,
      );
      expect(p3.messages.map((m) => m['id']), ['m1-aaaaaaaa']);
      expect(p3.more, isFalse);

      final none = await transport.fetchAiHistory('nope');
      expect(none.messages, isEmpty);
      expect(none.more, isFalse);
    });

    test('blob: ok, missing, traversal id', () async {
      await photos.save(_id1, Uint8List.fromList([5, 6, 7]), 'image/png');
      final ok = await transport.fetchAiBlob(_id1);
      expect(ok!.mime, 'image/png');
      expect(ok.data, [5, 6, 7]);
      expect(
        await transport.fetchAiBlob('22222222-2222-2222-2222-222222222222'),
        isNull,
      );
      File('${dir.path}/secret.jpg').writeAsBytesSync([1]);
      expect(await transport.fetchAiBlob('../secret'), isNull);
      expect(await transport.fetchAiBlob('..%2fsecret'), isNull);
    });

    test('a host without the assistant says unavailable', () async {
      server.ai = null;
      await expectLater(
        transport.fetchAiBlob(_id1),
        throwsA(isA<AiUnavailable>()),
      );
      await expectLater(
        transport.fetchAiHistory('T1'),
        throwsA(isA<AiUnavailable>()),
      );
    });

    test('a bad limit is a 400', () async {
      await expectLater(
        transport.fetchAiHistory('T1', limit: 101),
        throwsA(isA<HttpException>()),
      );
      await expectLater(
        transport.fetchAiHistory('T1', limit: 0),
        throwsA(isA<HttpException>()),
      );
    });

    Future<int> rawPost(String path, String body) async {
      final client = HttpClient();
      try {
        final req = await client.postUrl(
          Uri.http('127.0.0.1:${server.port}', path),
        );
        req.write(body);
        final res = await req.close();
        await res.drain<void>();
        return res.statusCode;
      } finally {
        client.close(force: true);
      }
    }

    test('an unpaired caller is refused', () async {
      final env = await SyncEnvelope.seal(
        key: SyncCrypto.randomBytes(32),
        path: '/v1/ai/blob',
        deviceId: 'stranger',
        counter: 1,
        body: {'blob_id': _id1},
      );
      expect(await rawPost('/v1/ai/blob', env.encode()), 401);
    });

    test('the body cap is enforced', () async {
      try {
        expect(await rawPost('/v1/ai/history', 'x' * (100 * 1024)), 413);
      } on HttpException {
        // cut off by the server: fine
      } on SocketException {
        // reset by the server: fine
      }
      expect(base64.encode([1]), isNotEmpty);
      // Still served afterwards.
      expect((await transport.fetchAiHistory('T1')).messages, isEmpty);
    });

    test('a replayed ai request is refused', () async {
      final env = await SyncEnvelope.seal(
        key: peer.key,
        path: '/v1/ai/blob',
        deviceId: await phone.id,
        counter: 500,
        body: {'blob_id': _id1},
      );
      expect(await rawPost('/v1/ai/blob', env.encode()), 200);
      expect(await rawPost('/v1/ai/blob', env.encode()), 401);
    });
  });
}
