import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/data/sync/http_transport.dart';
import 'package:livenow/data/sync/hub_admin_client.dart';
import 'package:livenow/data/sync/sync_peers.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/sync_providers.dart';
import 'package:livenow/ui/widgets/ai_hub_settings.dart';

/// A transport that answers the hub's admin routes from memory.
class _FakeHub extends HttpTransport {
  _FakeHub(AppDatabase db)
    : super(
        peers: SyncPeers(db),
        server: SyncPeer(
          deviceId: 'hub',
          name: 'Hub',
          key: Uint8List(32),
          lastCounter: 0,
          addresses: const ['127.0.0.1'],
          port: 1,
        ),
        myDeviceId: 'me',
      );

  final saved = <Map<String, Object?>>[];
  bool failSave = false;

  @override
  Future<Map<String, Object?>> call(String path, Map<String, Object?> body) async {
    if (path.endsWith('ai-status')) {
      return {
        'llm_ok': true,
        'ocr_ok': false,
        'queue': {'queued': 2, 'running': 1},
        'last_error': null,
      };
    }
    if (body.containsKey('values')) {
      if (failSave) throw const FormatException('bad url');
      saved.add(Map<String, Object?>.from(body['values']! as Map));
    }
    return {
      'llm_url': 'http://127.0.0.1:11434',
      'llm_model': 'qwen2.5:3b-instruct',
      'ocr_url': 'http://127.0.0.1:47655',
      'vision_model': '',
      'draft_first_count': '5',
      'photo_retention_days': '90',
      'llm_token_set': true,
    };
  }
}

void main() {
  late AppDatabase db;
  late _FakeHub hub;

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    hub = _FakeHub(db);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hubAdminProvider.overrideWith((ref) => _FakeAccess(ref, hub)),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: AiHubSettings())),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('shows the hub settings and its status; the token is never shown', (
    tester,
  ) async {
    await mount(tester);
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('ai-settings-llm-model'))).controller!.text,
      'qwen2.5:3b-instruct',
    );
    // Only "set" is known: the token field is empty and says to type to replace.
    expect(tester.widget<TextField>(find.byKey(const ValueKey('ai-settings-token'))).controller!.text, '');
    expect(find.text('Token (set; type to replace)'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('ai-settings-status'))).data,
      allOf(contains('Model server: reachable'), contains('OCR service: not reachable'), contains('2 queued')),
    );
  });

  testWidgets('Save sends the values, and the token only when typed', (tester) async {
    await mount(tester);
    await tester.enterText(find.byKey(const ValueKey('ai-settings-draft-count')), '8');
    await tester.tap(find.byKey(const ValueKey('ai-settings-save')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(hub.saved.single['draft_first_count'], '8');
    expect(hub.saved.single.containsKey('llm_token'), isFalse);

    await tester.enterText(find.byKey(const ValueKey('ai-settings-token')), 'secret');
    await tester.tap(find.byKey(const ValueKey('ai-settings-save')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(hub.saved.last['llm_token'], 'secret');
  });

  testWidgets('a refused value is shown and nothing claims to be saved', (tester) async {
    await mount(tester);
    hub.failSave = true;
    await tester.tap(find.byKey(const ValueKey('ai-settings-save')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const ValueKey('ai-settings-error')), findsOneWidget);
    expect(hub.saved, isEmpty);
  });
}

/// Runs the admin client over the fake transport (no real pairing).
class _FakeAccess extends HubAdminAccess {
  _FakeAccess(super.ref, this.t);
  final HttpTransport t;

  @override
  Future<T> run<T>(Future<T> Function(HubAdminClient hub) body) =>
      body(HubAdminClient(t));
}
