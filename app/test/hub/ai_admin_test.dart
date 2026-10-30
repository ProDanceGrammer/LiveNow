import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/sync/http_transport.dart';
import 'package:livenow/data/sync/hub_admin.dart';
import 'package:livenow/data/sync/hub_admin_client.dart';
import 'package:livenow/data/sync/sync_peers.dart';
import 'package:livenow/data/sync/sync_server.dart';
import 'package:livenow/domain/ai/ai_protocol.dart';
import 'package:livenow/domain/ai/ai_settings_store.dart';
import 'package:livenow/domain/sync/sync_crypto.dart';
import 'package:livenow/domain/sync/sync_protocol.dart';
import 'package:livenow/hub/ai_admin_routes.dart';

import '../data/ai/mock_llm_server.dart';
import '../domain/sync/sync_harness.dart';

void main() {
  setUpAll(() => HttpOverrides.global = null);

  late SyncDevice hub;
  late SyncDevice desktop;
  late SyncServer server;
  late HubAdmin admin;
  late Directory dir;
  late File bootstrap;
  late AiAdminRoutes routes;
  HttpTransport? transport;

  setUp(() async {
    hub = SyncDevice();
    desktop = SyncDevice();
    await hub.id;
    await desktop.id;
    dir = await Directory.systemTemp.createTemp('ai_admin_test');
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
    routes = AiAdminRoutes(
      hub.db,
      healthTimeout: const Duration(milliseconds: 500),
    );
    admin.extraRoutes = routes.handle;
    await server.start(port: 0);
  });

  tearDown(() async {
    transport?.close();
    transport = null;
    admin.dispose();
    await server.stop();
    await hub.close();
    await desktop.close();
    await dir.delete(recursive: true);
  });

  Future<HubAdminClient> pairDesktop() async {
    await admin.ensureBootstrap();
    final c = PairingUri.parse(await bootstrap.readAsString());
    final peers = SyncPeers(desktop.db);
    final peer = await pairWithServer(
      code: PairingUri(
        deviceId: c.deviceId,
        port: server.port,
        hosts: c.hosts,
        secret: c.secret,
      ),
      peers: peers,
      myDeviceId: await desktop.id,
      myName: 'Desktop',
      connectTimeout: const Duration(milliseconds: 500),
    );
    transport = HttpTransport(
      peers: peers,
      server: peer,
      myDeviceId: await desktop.id,
      connectTimeout: const Duration(milliseconds: 500),
    );
    return HubAdminClient(transport!);
  }

  test('a peer that is not the admin is rejected', () async {
    final client = await pairDesktop();
    await hub.store.setState(adminStateKey(await desktop.id), '0');
    await expectLater(
      client.fetchAiSettings(),
      throwsA(isA<SyncAuthException>()),
    );
    await expectLater(client.fetchAiStatus(), throwsA(isA<SyncAuthException>()));
    await expectLater(
      client.saveAiSettings({AiSettingKey.llmModel: 'x'}),
      throwsA(isA<SyncAuthException>()),
    );
  });

  test('settings round-trip; the token is never returned', () async {
    final client = await pairDesktop();
    var s = await client.fetchAiSettings();
    expect(s['llm_token_set'], isFalse);
    expect(s[AiSettingKey.draftFirstCount], 5);

    s = await client.saveAiSettings({
      AiSettingKey.llmUrl: 'http://192.168.1.20:11434',
      AiSettingKey.llmModel: 'qwen2.5:3b',
      AiSettingKey.llmToken: 'super-secret-token',
      AiSettingKey.photoRetentionDays: 30,
      AiSettingKey.draftFirstCount: '2',
    });
    expect(s[AiSettingKey.llmUrl], 'http://192.168.1.20:11434');
    expect(s[AiSettingKey.llmModel], 'qwen2.5:3b');
    expect(s['llm_token_set'], isTrue);
    expect(s.containsKey(AiSettingKey.llmToken), isFalse);
    expect(s[AiSettingKey.photoRetentionDays], 30);
    expect(s[AiSettingKey.draftFirstCount], 2);
    expect(s.toString(), isNot(contains('super-secret-token')));
    expect(
      (await client.fetchAiStatus()).toString(),
      isNot(contains('super-secret-token')),
    );

    // The token is stored on the hub, and an empty value clears it.
    expect(
      await routes.settings.get(AiSettingKey.llmToken),
      'super-secret-token',
    );
    s = await client.saveAiSettings({AiSettingKey.llmToken: ''});
    expect(s['llm_token_set'], isFalse);
  });

  test('an invalid value is rejected and nothing is saved', () async {
    for (final bad in <Map<String, Object?>>[
      {AiSettingKey.llmUrl: 'http://example.com:11434'},
      {AiSettingKey.llmUrl: 'ftp://127.0.0.1/'},
      {AiSettingKey.ocrUrl: 'not a url'},
      {AiSettingKey.photoRetentionDays: 'abc'},
      {AiSettingKey.draftFirstCount: -1},
      {'unknown_key': 'x'},
    ]) {
      await expectLater(
        routes.handle('ai-settings', {
          'values': {AiSettingKey.llmModel: 'changed', ...bad},
        }),
        throwsA(isA<FormatException>()),
        reason: '$bad',
      );
    }
    expect(
      await routes.settings.get(AiSettingKey.llmModel),
      AiSettingsStore.defaults[AiSettingKey.llmModel],
      reason: 'the rejected "changed" was not saved: the default is still served',
    );
  });

  test('over the wire an invalid URL fails as an error, not a crash', () async {
    final client = await pairDesktop();
    await expectLater(
      client.saveAiSettings({AiSettingKey.llmUrl: 'http://8.8.8.8:11434'}),
      throwsA(isA<HttpException>()),
    );
    final s = await client.fetchAiSettings();
    expect(s[AiSettingKey.llmUrl], isNot(contains('8.8.8.8')));
  });

  test('status: reachability, queue counts, models and the last error', () async {
    final llm = await MockLlmServer.start();
    final ocr = await MockOcrServer.start();
    addTearDown(llm.close);
    addTearDown(ocr.close);
    final client = await pairDesktop();
    await client.saveAiSettings({
      AiSettingKey.llmUrl: llm.url,
      AiSettingKey.ocrUrl: ocr.url,
      AiSettingKey.llmModel: 'qwen',
      AiSettingKey.visionModel: 'llava',
    });
    for (final (id, state, err) in [
      ('a', AiJobState.queued, null),
      ('b', AiJobState.queued, null),
      ('c', AiJobState.failed, 'OCR service unreachable'),
    ]) {
      await hub.db.customStatement(
        'INSERT INTO ai_jobs (id, thread_id, state, error, created_at, updated_at) '
        "VALUES (?, 't', ?, ?, '2026-10-30T10:00:00.000000Z', "
        "'2026-10-30T10:00:00.000000Z')",
        [id, state, err],
      );
    }

    var st = await client.fetchAiStatus();
    expect(st['llm_ok'], isTrue);
    expect(st['ocr_ok'], isTrue);
    expect(st['llm_model'], 'qwen');
    expect(st['vision_model'], 'llava');
    final q = st['queue']! as Map;
    expect(q[AiJobState.queued], 2);
    expect(q[AiJobState.failed], 1);
    expect(q[AiJobState.done], 0);
    expect((st['last_error']! as Map)['error'], 'OCR service unreachable');

    await ocr.close();
    st = await client.fetchAiStatus();
    expect(st['llm_ok'], isTrue);
    expect(st['ocr_ok'], isFalse);
  });

  test('status with nothing configured still answers', () async {
    final st = await routes.handle('ai-status', const {});
    expect(st['queue'], isA<Map>());
    expect(st['last_error'], isNull);
    expect(st['llm_ok'], isA<bool>());
  });
}
