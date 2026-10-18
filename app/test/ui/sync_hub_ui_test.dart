import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/sync/http_transport.dart';
import 'package:livenow/data/sync/sync_peers.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/domain/sync/sync_protocol.dart';
import 'package:livenow/hub/hub_runner.dart';
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/sync_providers.dart';
import 'package:livenow/ui/widgets/sync_settings_dialog.dart';

import '../domain/sync/sync_harness.dart';

void main() {
  setUpAll(() {
    HttpOverrides.global = null; // real sockets, not flutter_test's stub
    initPostponeTimeZoneData();
  });

  late SyncDevice me; // the desktop window's own database
  late SyncDevice hubDb;
  late HubRunner hub;
  late Directory hubDir;
  late Directory backups;

  Widget opener(Future<void> Function(BuildContext) dialog) => Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () => dialog(context),
        child: const Text('open'),
      ),
    ),
  );

  List<Override> overrides() => [
    databaseProvider.overrideWithValue(me.db),
    hubDirectoryProvider.overrideWithValue(() async => hubDir),
    syncBackupDirectoryProvider.overrideWithValue(() async => backups),
    syncServerPortProvider.overrideWithValue(0),
  ];

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: MaterialApp(home: opener(SyncSettingsDialog.show)),
      ),
    );
  }

  Future<void> real(WidgetTester tester, [int ms = 300]) async {
    final end = DateTime.now().add(Duration(milliseconds: ms));
    do {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      // Advance the fake clock too: the panel's timers (the pairing poll) run
      // in the widget zone.
      await tester.pump(const Duration(milliseconds: 25));
    } while (DateTime.now().isBefore(end));
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> unmount(WidgetTester tester) async {
    resetStackedDialogsForTest();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
    await real(tester, 200);
  }

  /// Connects the desktop window to the hub through the real button.
  Future<void> connect(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const ValueKey('sync-hub-connect')));
    await tester.tap(find.byKey(const ValueKey('sync-hub-connect')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('sync-confirm')));
    await real(tester, 1500);
    await real(tester, 500);
  }

  setUp(() async {
    me = SyncDevice();
    hubDb = SyncDevice();
    await me.id;
    await hubDb.id;
    hubDir = Directory.systemTemp.createTempSync('livenow-hub');
    backups = Directory.systemTemp.createTempSync('livenow-backups');
    hub = HubRunner(
      db: hubDb.db,
      dir: hubDir,
      port: 0,
      deviceName: 'Test hub',
      hosts: () async => ['127.0.0.1'],
    );
    await hub.start();
    // The local pairing text names the real port.
  });

  tearDown(() async {
    await hub.stop();
    await me.close();
    await hubDb.close();
    for (final d in [hubDir, backups]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  testWidgets('connect to the local hub: data is sent, the window becomes a client', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await ActionService(me.db).createAction(name: 'On the desktop');
      // An old phone pairing from the days this window was the server.
      await me.exec(
        "INSERT INTO sync_peers (device_id, name, key, last_counter, addresses, "
        "port, created_at) VALUES ('old-phone', 'Old phone', 'AAAA', 0, '[]', "
        "NULL, '2026-10-01T00:00:00.000000Z')",
      );
    });
    await pumpApp(tester);
    await open(tester);
    expect(find.byKey(const ValueKey('sync-hub-connect')), findsOneWidget);

    await connect(tester);

    // The desktop's data reached the hub; nothing was deleted here.
    expect(await tester.runAsync(() => hubDb.count('actions')), 1);
    expect(await tester.runAsync(() => me.count('actions')), 1);
    // It now talks to the hub only; the old phone pairing is forgotten.
    final peers = (await tester.runAsync(
      () => me.rows('SELECT device_id FROM sync_peers'),
    ))!;
    expect(peers, hasLength(1));
    expect(peers.single['device_id'], await tester.runAsync(() => hubDb.id));
    // The panel switched to the hub view.
    expect(find.text('Disconnect hub'), findsOneWidget);
    expect(find.text('Paired phones'), findsOneWidget);
    expect(find.byKey(const ValueKey('sync-hub-connect')), findsNothing);
    await unmount(tester);
  });

  testWidgets('without a running hub the connect button explains why', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final f = File('${hubDir.path}${Platform.pathSeparator}$kHubLocalPairFile');
      if (f.existsSync()) f.deleteSync();
    });
    await pumpApp(tester);
    await open(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('sync-hub-connect')));
    await tester.tap(find.byKey(const ValueKey('sync-hub-connect')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('sync-confirm')));
    await real(tester, 400);
    expect(find.byKey(const ValueKey('sync-hub-error')), findsOneWidget);
    expect(find.textContaining('Start the hub first'), findsOneWidget);
    // Nothing changed: still not a client.
    expect(find.byKey(const ValueKey('sync-hub-connect')), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a phone is paired from the desktop window through the hub', (
    tester,
  ) async {
    await pumpApp(tester);
    await open(tester);
    await connect(tester);
    await real(tester, 1000); // the list is read from the hub
    expect(find.text('No phone is paired with the hub yet.'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('sync-pair-phone')));
    await tester.tap(find.byKey(const ValueKey('sync-pair-phone')));
    await real(tester, 800);
    expect(find.byKey(const ValueKey('sync-qr')), findsOneWidget);
    final code = PairingUri.parse(
      tester
          .widget<SelectableText>(find.byKey(const ValueKey('sync-code-text')))
          .data!,
    );
    expect(code.deviceId, await tester.runAsync(() => hubDb.id));

    // The phone enters the code; the hub asks the desktop window.
    final phone = SyncDevice();
    final phoneId = (await tester.runAsync(() => phone.id))!;
    // Started in the widget zone (not runAsync): `real` pumps while it runs.
    final pairing = pairWithServer(
      code: PairingUri(
        deviceId: code.deviceId,
        port: hub.server.port,
        hosts: const ['127.0.0.1'],
        secret: code.secret,
      ),
      peers: SyncPeers(phone.db),
      myDeviceId: phoneId,
      myName: 'iPhone 15',
      connectTimeout: const Duration(milliseconds: 500),
    );
    await real(tester, 2500);
    expect(find.text('Pair this phone?'), findsOneWidget);
    expect(find.textContaining('iPhone 15'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sync-pair-approve')));
    await real(tester, 1500);
    final peer = await pairing;
    expect(peer.deviceId, code.deviceId);

    // The list shows the phone now, and the code is gone.
    await real(tester, 800);
    expect(find.byKey(const ValueKey('sync-qr')), findsNothing);
    expect(find.text('iPhone 15'), findsOneWidget);
    expect(
      await tester.runAsync(
        () => hubDb.rows("SELECT name FROM sync_peers WHERE name = 'iPhone 15'"),
      ),
      hasLength(1),
    );
    await tester.runAsync(phone.close);
    await unmount(tester);
  });

  testWidgets('disconnecting from the hub makes this window a server again', (
    tester,
  ) async {
    await pumpApp(tester);
    await open(tester);
    await connect(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('sync-forget')));
    await tester.tap(find.byKey(const ValueKey('sync-forget')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('sync-confirm')));
    await real(tester, 800);
    expect(find.byKey(const ValueKey('sync-hub-connect')), findsOneWidget);
    expect(find.text('Disconnect hub'), findsNothing);
    await unmount(tester);
  });
}
