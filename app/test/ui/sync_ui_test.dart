import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/sync/http_transport.dart';
import 'package:livenow/data/sync/sync_peers.dart';
import 'package:livenow/data/sync/sync_server.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/domain/sync/sync_models.dart';
import 'package:livenow/domain/sync/sync_protocol.dart';
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/sync_providers.dart';
import 'package:livenow/ui/widgets/action_editor.dart';
import 'package:livenow/ui/widgets/sync_conflicts_dialog.dart';
import 'package:livenow/ui/widgets/sync_settings_dialog.dart';

import '../domain/sync/sync_harness.dart';

void main() {
  setUpAll(() {
    HttpOverrides.global = null; // real sockets, not flutter_test's stub
    initPostponeTimeZoneData();
  });

  late SyncDevice me;

  Widget opener(Future<void> Function(BuildContext) dialog) => Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () => dialog(context),
        child: const Text('open'),
      ),
    ),
  );

  Future<void> pumpApp(
    WidgetTester tester,
    Widget home, {
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(me.db), ...overrides],
        child: MaterialApp(home: home),
      ),
    );
  }

  /// Lets real I/O (sockets, the database) and the continuations of futures
  /// started inside the widget zone run: alternates real waiting and pumping.
  Future<void> real(WidgetTester tester, [int ms = 300]) async {
    final end = DateTime.now().add(Duration(milliseconds: ms));
    do {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
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

  setUp(() async {
    me = SyncDevice();
    await me.id;
  });

  tearDown(() => me.close());

  group('PC panel', () {
    final overrides = [
      syncRoleProvider.overrideWithValue(SyncRole.host),
      syncServerPortProvider.overrideWithValue(0),
    ];

    testWidgets('pairing shows a code, a phone pairs, it can be removed', (
      tester,
    ) async {
      await pumpApp(
        tester,
        opener(SyncSettingsDialog.show),
        overrides: overrides,
      );
      await open(tester);
      expect(find.text('No phone is paired yet.'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('sync-pair-phone')));
      await real(tester);
      expect(find.byKey(const ValueKey('sync-qr')), findsOneWidget);
      expect(find.byKey(const ValueKey('sync-countdown')), findsOneWidget);
      expect(find.textContaining('valid for'), findsOneWidget);

      final shown = PairingUri.parse(
        tester
            .widget<SelectableText>(
              find.byKey(const ValueKey('sync-code-text')),
            )
            .data!,
      );
      expect(shown.deviceId, await tester.runAsync(() => me.id));

      // A phone pairs with the code on screen (loopback address).
      final phone = SyncDevice();
      await tester.runAsync(() => phone.id);
      final phoneId = (await tester.runAsync(() => phone.id))!;
      // The server lives in the widget zone (a button started it), so it only
      // advances while the test pumps: pair concurrently with pumping.
      final pairing = pairWithServer(
        code: PairingUri(
          deviceId: shown.deviceId,
          port: shown.port,
          hosts: const ['127.0.0.1'],
          secret: shown.secret,
        ),
        peers: SyncPeers(phone.db),
        myDeviceId: phoneId,
        myName: 'Test iPhone',
      );
      await real(tester, 1500);
      await pairing;
      await real(tester);
      expect(find.byKey(const ValueKey('sync-qr')), findsNothing);
      expect(find.text('Test iPhone'), findsOneWidget);
      expect(find.text('Paired with Test iPhone'), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('sync-remove-$phoneId')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const ValueKey('sync-confirm')));
      await real(tester);
      expect(find.text('Test iPhone'), findsNothing);
      expect(find.text('No phone is paired yet.'), findsOneWidget);

      await tester.runAsync(phone.close);
      await unmount(tester);
    });

    testWidgets('cancelling the pairing hides the code', (tester) async {
      await pumpApp(
        tester,
        opener(SyncSettingsDialog.show),
        overrides: overrides,
      );
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('sync-pair-phone')));
      await real(tester);
      expect(find.byKey(const ValueKey('sync-qr')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sync-pair-cancel')));
      await tester.pump();
      expect(find.byKey(const ValueKey('sync-qr')), findsNothing);
      expect(find.byKey(const ValueKey('sync-pair-phone')), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('the switch turns the server off', (tester) async {
      await pumpApp(
        tester,
        opener(SyncSettingsDialog.show),
        overrides: overrides,
      );
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('sync-pair-phone')));
      await real(tester);
      expect(find.textContaining('Listening for phones'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sync-enabled-switch')));
      await real(tester);
      expect(find.text('Not listening'), findsOneWidget);
      expect(find.byKey(const ValueKey('sync-qr')), findsNothing);
      await unmount(tester);
    });
  });

  group('phone panel', () {
    late SyncDevice pc;
    late SyncServer server;
    late Directory backups;

    setUp(() async {
      pc = SyncDevice();
      await pc.id;
      server = SyncServer(
        store: pc.store,
        host: pc.host,
        peers: SyncPeers(pc.db),
        deviceName: 'Home PC',
      );
      await server.start(port: 0);
      backups = Directory.systemTemp.createTempSync('livenow-backups');
    });

    tearDown(() async {
      await server.stop();
      await pc.close();
      if (backups.existsSync()) backups.deleteSync(recursive: true);
    });

    List<Override> overrides() => [
      syncRoleProvider.overrideWithValue(SyncRole.client),
      syncBackupDirectoryProvider.overrideWithValue(() async => backups),
    ];

    testWidgets('an invalid code is refused with a message', (tester) async {
      await pumpApp(
        tester,
        opener(SyncSettingsDialog.show),
        overrides: overrides(),
      );
      await open(tester);
      await tester.enterText(
        find.byKey(const ValueKey('sync-code-field')),
        'nope',
      );
      await tester.tap(find.byKey(const ValueKey('sync-pair-button')));
      await real(tester);
      expect(find.textContaining('not a LiveNow pairing code'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('pairing replaces the phone data, keeps a backup, then syncs', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await ActionService(pc.db).createAction(name: 'On the PC');
        await ActionService(me.db).createAction(name: 'Old phone data');
      });
      final code = (await tester.runAsync(
        () => server.startPairing(hosts: ['127.0.0.1']),
      ))!;

      await pumpApp(
        tester,
        opener(SyncSettingsDialog.show),
        overrides: overrides(),
      );
      await open(tester);
      await tester.enterText(
        find.byKey(const ValueKey('sync-code-field')),
        code.toString(),
      );
      await tester.tap(find.byKey(const ValueKey('sync-pair-button')));
      await real(tester, 100);
      // The phone has data of its own: it must be confirmed first.
      expect(find.text('Replace the data on this phone?'), findsOneWidget);
      expect(find.textContaining('1 actions'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sync-confirm')));
      await real(tester, 1500);
      await real(tester, 500);

      final names = (await tester.runAsync(
        () => me.rows('SELECT name FROM actions'),
      ))!;
      expect([for (final r in names) r['name']], ['On the PC']);
      final saved = backups.listSync().whereType<File>().toList();
      expect(saved, hasLength(1));
      expect(saved.single.path, contains('before-pairing'));
      expect(find.text('Home PC'), findsOneWidget);
      expect(find.textContaining('Last synced'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('a wrong code reports it and changes nothing', (tester) async {
      await tester.runAsync(
        () => ActionService(me.db).createAction(name: 'Mine'),
      );
      final real0 = (await tester.runAsync(
        () => server.startPairing(hosts: ['127.0.0.1']),
      ))!;
      final wrong = PairingUri(
        deviceId: real0.deviceId,
        port: real0.port,
        hosts: real0.hosts,
        secret: Uint8List.fromList(List<int>.generate(16, (i) => i)),
      );
      await pumpApp(
        tester,
        opener(SyncSettingsDialog.show),
        overrides: overrides(),
      );
      await open(tester);
      await tester.enterText(
        find.byKey(const ValueKey('sync-code-field')),
        wrong.toString(),
      );
      await tester.tap(find.byKey(const ValueKey('sync-pair-button')));
      await real(tester, 100);
      await tester.tap(find.byKey(const ValueKey('sync-confirm')));
      await real(tester, 800);
      expect(find.textContaining('wrong or has expired'), findsOneWidget);
      final names = (await tester.runAsync(
        () => me.rows('SELECT name FROM actions'),
      ))!;
      expect([for (final r in names) r['name']], ['Mine']);
      expect(backups.listSync(), isEmpty); // nothing was backed up or wiped
      await unmount(tester);
    });
  });

  group('conflicts', () {
    testWidgets('a lost version can be restored', (tester) async {
      final id = (await tester.runAsync(
        () => ActionService(me.db).createAction(name: 'Winner'),
      ))!;
      // The version that lost, as the merge would have kept it.
      final data = (await tester.runAsync(() async {
        final all = await me.store.changesSince(
          0,
          until: await me.store.currentSeq(),
        );
        return all.firstWhere((c) => c.table == 'actions').data!;
      }))!;
      await tester.runAsync(
        () => me.exec(
          'INSERT INTO sync_conflicts (tbl, row_id, label, detected_at, '
          'loser_hlc, loser_origin, winner_hlc, loser_json) '
          "VALUES ('actions', ?, 'Loser', '2026-10-10T10:00:00.000Z', "
          "'2026-10-10T09:00:00.000Z-0000-x', 'other', "
          "'2026-10-10T09:59:00.000Z-0000-y', ?)",
          [
            id,
            jsonEncode({...data, 'name': 'Loser'}),
          ],
        ),
      );
      await pumpApp(tester, opener(SyncConflictsDialog.show));
      await open(tester);
      await real(tester, 100);
      expect(find.text('Action "Loser"'), findsOneWidget);

      final cid = (await tester.runAsync(
        () => me.rows('SELECT id FROM sync_conflicts'),
      ))!.single['id'];
      await tester.tap(find.byKey(ValueKey('conflict-restore-$cid')));
      await real(tester);
      final row = (await tester.runAsync(
        () => me.rows('SELECT name FROM actions'),
      ))!;
      expect(row.single['name'], 'Loser');
      expect(find.text('Nothing to review.'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('editor guard', () {
    testWidgets('saving over a change from another device asks first', (
      tester,
    ) async {
      final id = (await tester.runAsync(
        () => ActionService(me.db).createAction(name: 'Original'),
      ))!;
      final row = (await tester.runAsync(
        () => (me.db.select(
          me.db.actionsTable,
        )..where((t) => t.id.equals(id))).getSingle(),
      ))!;
      await pumpApp(
        tester,
        opener((c) => ActionEditorDialog.show(c, existing: row)),
      );
      await open(tester);
      await real(tester, 100);

      // Another device renames it while the form is open.
      await tester.runAsync(() async {
        final all = await me.store.changesSince(
          0,
          until: await me.store.currentSeq(),
        );
        final mine = all.firstWhere((c) => c.table == 'actions');
        await me.store.apply([
          SyncChange(
            table: 'actions',
            rowId: id,
            hlc: '2099-01-01T00:00:00.000Z-0000-feed',
            origin: 'feed',
            deleted: false,
            data: {...mine.data!, 'name': 'From the phone'},
          ),
        ], unsyncedAfterSeq: 0);
      });
      await real(tester, 100);

      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Changed on another device'), findsOneWidget);

      // Cancel keeps the editor open and the other device's change.
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog).last,
          matching: find.text('Cancel'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Changed on another device'), findsNothing);
      expect(find.text('Save'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const ValueKey('overwrite-remote')));
      await real(tester, 400);
      final stamp = (await tester.runAsync(
        () => me.store.rowStamp('actions', id),
      ))!;
      expect(stamp.origin, await tester.runAsync(() => me.id));
      await unmount(tester);
    });

    testWidgets('a change made here while it is open does not ask', (
      tester,
    ) async {
      final id = (await tester.runAsync(
        () => ActionService(me.db).createAction(name: 'Original'),
      ))!;
      final row = (await tester.runAsync(
        () => (me.db.select(
          me.db.actionsTable,
        )..where((t) => t.id.equals(id))).getSingle(),
      ))!;
      await pumpApp(
        tester,
        opener((c) => ActionEditorDialog.show(c, existing: row)),
      );
      await open(tester);
      await real(tester, 100);
      await tester.runAsync(
        () => ActionService(me.db).toggleDone(id), // like a Start/Finish button
      );
      await real(tester, 100);
      await tester.tap(find.text('Save'));
      await real(tester, 400);
      expect(find.text('Changed on another device'), findsNothing);
      await unmount(tester);
    });
  });
}
