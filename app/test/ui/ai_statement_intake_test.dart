import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/ai/ai_chat_service.dart';
import 'package:livenow/domain/ai/ai_protocol.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/ai_ui_providers.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/screens/ai_chat_screen.dart';
import 'package:livenow/ui/sync_providers.dart';
import 'package:livenow/ui/widgets/ai_incoming_file.dart';

import '../domain/ai/ai_test_support.dart';

class _Hub extends HubConnected {
  @override
  bool build() => true;
}

void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late String thread;

  final csv = Uint8List.fromList(utf8.encode('Date;Amount\n01.01.2026;-10\n'));
  final png = Uint8List.fromList([
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3, //
  ]);
  StatementPick file([String name = 'march.csv']) => (name: name, bytes: csv);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  Future<void> mount(
    WidgetTester tester, {
    Widget? home,
    StatementPick? picked,
    StatementPick? clipboardFile,
    StatementPick Function()? nextPick,
    int threads = 1,
  }) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = memoryDb();
    await tester.runAsync(() async {
      for (var i = 0; i < threads; i++) {
        final id = await AiChatService(db).createThread(title: 'Chat $i');
        if (i == 0) thread = id;
      }
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hubConnectedProvider.overrideWith(_Hub.new),
          aiStatementPickerProvider.overrideWithValue(
            () async => nextPick != null ? nextPick() : picked,
          ),
          aiClipboardStatementProvider.overrideWithValue(
            ClipboardStatement(
              has: () async => clipboardFile != null,
              read: () async => clipboardFile,
            ),
          ),
          aiClipboardPhotosProvider.overrideWithValue(
            ClipboardPhotos(has: () async => false, read: () async => const []),
          ),
          aiPhotoPickerProvider.overrideWithValue((s) async => [png]),
          aiPhotoPrepProvider.overrideWithValue(
            (b) async => (bytes: b, width: 10, height: 20),
          ),
        ],
        child: MaterialApp(home: home ?? AiChatScreen(threadId: thread)),
      ),
    );
    await settle(tester);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(db.close);
  }

  Future<List<AiMessage>> messages(WidgetTester tester) => tester
      .runAsync(
        () => (db.select(db.aiMessagesTable)..orderBy([
              (t) => OrderingTerm.asc(t.createdAt),
              (t) => OrderingTerm.asc(t.id),
            ]))
            .get(),
      )
      .then((v) => v!);

  Finder k(String key) => find.byKey(ValueKey(key));

  testWidgets('attach a statement: chip, Send makes one statement message', (
    tester,
  ) async {
    await mount(tester, picked: file());
    expect(k('ai-chat-pending-file-0'), findsNothing);
    await tester.tap(k('ai-chat-attach-statement'));
    await settle(tester);
    expect(k('ai-chat-pending-file-0'), findsOneWidget);
    expect(find.text('march.csv'), findsOneWidget);

    await tester.enterText(k('ai-chat-input'), 'card 6141');
    await tester.tap(k('ai-chat-send'));
    await settle(tester);
    expect(k('ai-chat-pending-file-0'), findsNothing);

    final msgs = await messages(tester);
    expect(msgs, hasLength(1));
    final content = jsonDecode(msgs.single.contentJson) as Map<String, dynamic>;
    expect(content['kind'], AiJobKind.statement);
    expect(content['file_name'], 'march.csv');
    expect(msgs.single.body, 'card 6141');
    final blob = (await tester.runAsync(
      () => db.select(db.aiBlobsTable).getSingle(),
    ))!;
    expect(blob.mime, 'text/csv');
    final job = (await tester.runAsync(
      () => db.select(db.aiJobsTable).getSingle(),
    ))!;
    expect(job.kind, AiJobKind.statement);
    expect(k('ai-file-${msgs.single.id}'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('the pending file can be removed; a new one replaces it', (
    tester,
  ) async {
    var n = 0;
    await mount(tester, nextPick: () => file('f${n++}.csv'));
    await tester.tap(k('ai-chat-attach-statement'));
    await settle(tester);
    expect(find.text('f0.csv'), findsOneWidget);
    await tester.tap(k('ai-chat-attach-statement'));
    await settle(tester);
    expect(find.text('f0.csv'), findsNothing);
    expect(find.text('f1.csv'), findsOneWidget);
    await tester.tap(k('ai-chat-pending-file-remove-0'));
    await tester.pump();
    expect(k('ai-chat-pending-file-0'), findsNothing);
    await finish(tester);
  });

  testWidgets('a wrong file is refused with no chip', (tester) async {
    await mount(tester, picked: (name: 'photo.csv', bytes: png));
    await tester.tap(k('ai-chat-attach-statement'));
    await settle(tester);
    expect(k('ai-chat-pending-file-0'), findsNothing);
    expect(find.textContaining('Only CSV'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('photos and a file: two messages, photos first', (tester) async {
    await mount(tester, picked: file());
    await tester.tap(k('ai-chat-attach'));
    await settle(tester);
    await tester.tap(k('ai-chat-attach-statement'));
    await settle(tester);
    expect(k('ai-chat-pending-0'), findsOneWidget);
    expect(k('ai-chat-pending-file-0'), findsOneWidget);
    await tester.enterText(k('ai-chat-input'), 'both');
    await tester.tap(k('ai-chat-send'));
    await settle(tester);

    final msgs = await messages(tester);
    expect(msgs, hasLength(2));
    String kindOf(AiMessage m) =>
        (jsonDecode(m.contentJson) as Map<String, dynamic>)['kind'] as String;
    expect(kindOf(msgs[0]), AiJobKind.photos);
    expect(msgs[0].body, 'both');
    expect(kindOf(msgs[1]), AiJobKind.statement);
    expect(msgs[1].body, '');
    expect(k('ai-chat-pending-0'), findsNothing);
    expect(k('ai-chat-pending-file-0'), findsNothing);
    await finish(tester);
  });

  testWidgets('"Paste file" in the text menu takes a clipboard file', (
    tester,
  ) async {
    await mount(tester, clipboardFile: file('pasted.xlsx'));
    // An xlsx must be a zip: the CSV bytes above are refused.
    await tester.tap(k('ai-chat-input'));
    await tester.pump();
    tester.state<EditableTextState>(find.byType(EditableText)).showToolbar();
    await settle(tester);
    expect(find.text('Paste file'), findsOneWidget);
    await tester.tap(find.text('Paste file'));
    await settle(tester);
    expect(k('ai-chat-pending-file-0'), findsNothing);
    expect(find.textContaining('Only CSV'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('"Paste file" with a real csv adds the chip', (tester) async {
    await mount(tester, clipboardFile: file('pasted.csv'));
    await tester.tap(k('ai-chat-input'));
    await tester.pump();
    tester.state<EditableTextState>(find.byType(EditableText)).showToolbar();
    await settle(tester);
    await tester.tap(find.text('Paste file'));
    await settle(tester);
    expect(k('ai-chat-pending-file-0'), findsOneWidget);
    await finish(tester);
  });

  Widget incomingHost() => Consumer(
    builder: (context, ref, _) => Scaffold(
      body: Center(
        child: TextButton(
          key: const ValueKey('open-picker'),
          onPressed: () => showIncomingFilePicker(context, ref, file('in.csv')),
          child: const Text('go'),
        ),
      ),
    ),
  );

  testWidgets('incoming file: choose a chat, it opens with the file chip', (
    tester,
  ) async {
    await mount(tester, home: incomingHost(), threads: 2);
    await tester.tap(k('open-picker'));
    await settle(tester);
    expect(find.text('Send to chat'), findsOneWidget);
    expect(k('ai-incoming-new'), findsOneWidget);
    await tester.tap(k('ai-incoming-thread-0'));
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(k('ai-chat-pending-file-0'), findsOneWidget);
    expect(find.text('in.csv'), findsOneWidget);
    expect(
      (await tester.runAsync(() => db.select(db.aiThreadsTable).get()))!,
      hasLength(2),
    );
    await finish(tester);
  });

  testWidgets('incoming file: New chat creates a thread and opens it', (
    tester,
  ) async {
    await mount(tester, home: incomingHost(), threads: 1);
    await tester.tap(k('open-picker'));
    await settle(tester);
    await tester.tap(k('ai-incoming-new'));
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(k('ai-chat-pending-file-0'), findsOneWidget);
    expect(
      (await tester.runAsync(() => db.select(db.aiThreadsTable).get()))!,
      hasLength(2),
    );
    await finish(tester);
  });
}
