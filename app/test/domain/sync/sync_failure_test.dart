import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/sync/http_transport.dart';
import 'package:livenow/data/sync/sync_peers.dart';
import 'package:livenow/data/sync/sync_server.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/sync/sync_engine.dart';
import 'package:livenow/domain/sync/sync_models.dart';
import 'package:livenow/domain/sync/sync_protocol.dart';
import 'package:livenow/ui/sync_providers.dart' show offlineSkipTicks;

import 'sync_harness.dart';

/// The network misbehaving: a peer that drops mid-reply, trickles, floods,
/// goes away and comes back, or loses the reply of a push.
void main() {
  setUpAll(() => HttpOverrides.global = null);

  /// A raw TCP "server" that reads one request then runs [behave] on the socket.
  Future<ServerSocket> fake(
    Future<void> Function(Socket s) behave,
  ) async {
    final ss = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    ss.listen((s) async {
      final buf = <int>[];
      final done = Completer<void>();
      s.listen(
        (d) {
          buf.addAll(d);
          final text = String.fromCharCodes(buf);
          if (!done.isCompleted && text.contains('\r\n\r\n')) done.complete();
        },
        onError: (_) {},
        onDone: () {},
      );
      await done.future;
      try {
        await behave(s);
      } on Object {
        // The client may have hung up on us already.
      }
    });
    return ss;
  }

  Future<String> post(
    ServerSocket ss, {
    int maxBytes = 1000,
    Duration deadline = const Duration(milliseconds: 600),
    Duration header = const Duration(milliseconds: 600),
  }) {
    final client = HttpClient();
    return postFirstReachable(
      client,
      const Duration(milliseconds: 500),
      ['127.0.0.1'],
      ss.port,
      '/v1/hello',
      '{}',
      maxResponseBytes: maxBytes,
      responseDeadline: deadline,
      headerTimeout: header,
    ).whenComplete(() => client.close(force: true));
  }

  test('the periodic sync backs off while the other device stays unreachable', () {
    expect(
      [for (var i = 0; i <= 8; i++) offlineSkipTicks(i)],
      [0, 1, 3, 7, 14, 14, 14, 14, 14],
    );
  });

  group('a reply that goes wrong (client side)', () {
    test('the connection drops in the middle of the body: unreachable', () async {
      final ss = await fake((s) async {
        s.write('HTTP/1.1 200 OK\r\ncontent-length: 1000\r\n\r\n0123456789');
        await s.flush();
        s.destroy();
      });
      addTearDown(() => ss.close());
      await expectLater(post(ss), throwsA(isA<SyncUnreachable>()));
    });

    test('a chunked reply cut off without its end: unreachable', () async {
      final ss = await fake((s) async {
        s.write(
          'HTTP/1.1 200 OK\r\ntransfer-encoding: chunked\r\n\r\n'
          '5\r\nhello\r\n',
        );
        await s.flush();
        s.destroy();
      });
      addTearDown(() => ss.close());
      await expectLater(post(ss), throwsA(isA<SyncUnreachable>()));
    });

    test('a trickling body hits the total deadline, however alive it looks', () async {
      final ss = await fake((s) async {
        s.write('HTTP/1.1 200 OK\r\ntransfer-encoding: chunked\r\n\r\n');
        for (var i = 0; i < 40; i++) {
          s.write('1\r\nx\r\n');
          await s.flush();
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        s.destroy();
      });
      addTearDown(() => ss.close());
      final sw = Stopwatch()..start();
      await expectLater(
        post(ss, deadline: const Duration(milliseconds: 400)),
        throwsA(isA<SyncUnreachable>()),
      );
      expect(sw.elapsed, lessThan(const Duration(seconds: 3)));
    });

    test('a reply that never starts is cut by the header timeout', () async {
      final ss = await fake((s) async {
        await Future<void>.delayed(const Duration(seconds: 5));
      });
      addTearDown(() => ss.close());
      await expectLater(
        post(ss, header: const Duration(milliseconds: 300)),
        throwsA(isA<SyncUnreachable>()),
      );
    });

    test('a reply over the cap is refused while it streams', () async {
      var sent = 0;
      final ss = await fake((s) async {
        s.write('HTTP/1.1 200 OK\r\ntransfer-encoding: chunked\r\n\r\n');
        final chunk = 'a' * 400;
        for (var i = 0; i < 1000; i++) {
          s.write('190\r\n$chunk\r\n');
          sent += 400;
          await s.flush();
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        s.destroy();
      });
      addTearDown(() => ss.close());
      await expectLater(post(ss), throwsA(isA<HttpException>()));
      expect(sent, lessThan(400 * 1000), reason: 'reading stopped early');
    });

    test('a declared length over the cap is refused before reading', () async {
      final ss = await fake((s) async {
        s.write('HTTP/1.1 200 OK\r\ncontent-length: 5000\r\n\r\nabc');
        await s.flush();
        await Future<void>.delayed(const Duration(milliseconds: 200));
        s.destroy();
      });
      addTearDown(() => ss.close());
      await expectLater(post(ss), throwsA(isA<HttpException>()));
    });

    test('a reply that is not UTF-8 is an error, not a crash', () async {
      final ss = await fake((s) async {
        s.add([
          ...'HTTP/1.1 200 OK\r\ncontent-length: 3\r\n\r\n'.codeUnits,
          0xff,
          0xfe,
          0xfd,
        ]);
        await s.flush();
        s.destroy();
      });
      addTearDown(() => ss.close());
      await expectLater(post(ss), throwsA(isA<HttpException>()));
    });

    test('a good small reply still passes', () async {
      final ss = await fake((s) async {
        s.write('HTTP/1.1 200 OK\r\ncontent-length: 2\r\n\r\nok');
        await s.flush();
        s.destroy();
      });
      addTearDown(() => ss.close());
      expect(await post(ss), 'ok');
    });

    test('a connection closed before any header is unreachable, not an error', () async {
      final ss = await fake((s) async => s.destroy());
      addTearDown(() => ss.close());
      await expectLater(post(ss), throwsA(isA<SyncUnreachable>()));
    });
  });

  group('offline, online and a lost reply (real server)', () {
    late SyncDevice pc;
    late SyncDevice phone;
    late SyncServer server;
    late SyncPeers phonePeers;
    late SyncPeer peer;
    late String phoneId;
    final transports = <HttpTransport>[];

    HttpTransport transport() {
      final t = HttpTransport(
        peers: phonePeers,
        server: peer,
        myDeviceId: phoneId,
        connectTimeout: const Duration(milliseconds: 500),
      );
      transports.add(t);
      return t;
    }

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
      phonePeers = SyncPeers(phone.db);
      peer = await pairWithServer(
        code: PairingUri.parse(code.toString()),
        peers: phonePeers,
        myDeviceId: phoneId,
        myName: 'Phone',
        connectTimeout: const Duration(milliseconds: 500),
      );
    });

    tearDown(() async {
      for (final t in transports) {
        t.close();
      }
      transports.clear();
      await server.stop();
      await pc.close();
      await phone.close();
    });

    test('offline then online: the next sync catches up, nothing doubled', () async {
      final t = transport();
      await ActionService(phone.db).createAction(name: 'Made offline');
      final port = server.port;
      await server.stop();

      await expectLater(phone.engine.sync(t), throwsA(isA<SyncUnreachable>()));
      // Repeated while offline: still the same clean error.
      await expectLater(phone.engine.sync(t), throwsA(isA<SyncUnreachable>()));
      expect(await pc.count('actions'), 0);

      await server.start(port: port);
      await phone.engine.sync(t);
      expect(await pc.count('actions'), 1);
      expect(await phone.dump(), equals(await pc.dump()));
      // And a second sync changes nothing.
      await phone.engine.sync(t);
      expect(await pc.count('actions'), 1);
    });

    test('the reply to a push is lost: sending again is idempotent', () async {
      final svc = ActionService(phone.db);
      for (var i = 0; i < 3; i++) {
        await svc.createAction(name: 'Row $i');
      }
      final real = transport();
      final flaky = _LosesFirstPushReply(real);
      await expectLater(phone.engine.sync(flaky), throwsA(isA<SyncUnreachable>()));
      // The PC applied it all even though the phone never heard.
      expect(await pc.count('actions'), 3);

      await phone.engine.sync(flaky);
      expect(await pc.count('actions'), 3);
      expect(await phone.count('actions'), 3);
      expect(await phone.dump(), equals(await pc.dump()));
    });

    test('flapping: every other request fails, the sync still converges', () async {
      final svc = ActionService(phone.db);
      for (var i = 0; i < 5; i++) {
        await svc.createAction(name: 'Flap $i');
        await ActionService(pc.db).createAction(name: 'PC $i');
      }
      final flaky = _Flapping(transport());
      for (var i = 0; i < 80; i++) {
        try {
          await phone.engine.sync(flaky);
        } on SyncUnreachable {
          continue;
        }
      }
      expect(await pc.count('actions'), 10);
      expect(await phone.count('actions'), 10);
      expect(await phone.dump(), equals(await pc.dump()));
    });
  });
}

/// The PC answers the first push, the answer is "lost" on the way back.
class _LosesFirstPushReply implements SyncTransport {
  _LosesFirstPushReply(this.inner);
  final SyncTransport inner;
  bool _lost = false;

  @override
  Future<SyncHello> hello() => inner.hello();

  @override
  Future<SyncPullPage> pull(int sinceSeq, {int limit = 500}) =>
      inner.pull(sinceSeq, limit: limit);

  @override
  Future<ApplyResult> push(List<SyncChange> changes, {required bool last}) async {
    final r = await inner.push(changes, last: last);
    if (!_lost) {
      _lost = true;
      throw const SyncUnreachable();
    }
    return r;
  }
}

/// Randomly (seeded) fails calls before they reach the PC or after it answered.
class _Flapping implements SyncTransport {
  _Flapping(this.inner);
  final SyncTransport inner;
  final _rnd = Random(3);

  Future<T> _go<T>(Future<T> Function() f) async {
    if (_rnd.nextDouble() < 0.3) throw const SyncUnreachable();
    final r = await f();
    if (_rnd.nextDouble() < 0.3) throw const SyncUnreachable();
    return r;
  }

  @override
  Future<SyncHello> hello() => _go(inner.hello);

  @override
  Future<SyncPullPage> pull(int sinceSeq, {int limit = 500}) =>
      _go(() => inner.pull(sinceSeq, limit: limit));

  @override
  Future<ApplyResult> push(List<SyncChange> changes, {required bool last}) =>
      _go(() => inner.push(changes, last: last));
}
