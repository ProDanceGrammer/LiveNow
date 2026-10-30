import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/time_codec.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/ai/ai_batch_service.dart';
import 'package:livenow/domain/ai/ai_chat_service.dart';
import 'package:livenow/domain/ai/ai_protocol.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/ai_ui_providers.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/screens/ai_chat_screen.dart';
import 'package:livenow/ui/screens/ai_threads_screen.dart';
import 'package:livenow/ui/screens/budget_screen.dart';
import 'package:livenow/ui/sync_providers.dart';

import '../domain/ai/ai_test_support.dart';

class _Hub extends HubConnected {
  _Hub(this.on);
  final bool on;
  @override
  bool build() => on;
}

void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late AiChatService chat;
  late String thread;
  var seq = 0;

  /// Runs a widget test, then unmounts the tree (Drift's zero-duration cancel
  /// timer must fire inside the test) and closes the database.
  void uiTest(String name, Future<void> Function(WidgetTester) body) =>
      testWidgets(name, (tester) async {
        await body(tester);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 1));
        await tester.runAsync(db.close);
      });
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  Future<void> mount(
    WidgetTester tester,
    Widget home, {
    Size size = const Size(1400, 900),
    bool hub = true,
    Future<void> Function()? seed,
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = memoryDb();
    chat = AiChatService(db);
    await tester.runAsync(() async {
      thread = await chat.createThread(title: 'Receipts');
      await seed?.call();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hubConnectedProvider.overrideWith(() => _Hub(hub)),
          ...overrides,
        ],
        child: MaterialApp(home: home),
      ),
    );
    await settle(tester);
  }

  Future<int> count(WidgetTester tester, String table) async =>
      (await tester.runAsync(
        () async => (await db
            .customSelect('SELECT COUNT(*) AS n FROM $table')
            .getSingle()).read<int>('n'),
      ))!;

  Future<String> insertMessage({
    required String kind,
    String role = AiRole.assistant,
    String body = '',
    Map<String, Object?> json = const {},
    String? jobId,
    String? createdAt,
  }) async {
    final id = 'm${seq++}$kind';
    final now = createdAt ?? dateTimeToDb(DateTime.now())!;
    await db.into(db.aiMessagesTable).insert(
      AiMessagesTableCompanion.insert(
        id: id,
        threadId: thread,
        role: Value(role),
        kind: Value(kind),
        body: Value(body),
        contentJson: Value(jsonEncode(json)),
        jobId: Value(jobId),
        createdAt: now,
        updatedAt: now,
      ),
    );
    return id;
  }

  Future<String> insertJob(String state, String stage, {String? id}) async {
    final jobId = id ?? 'job${seq++}';
    final now = dateTimeToDb(DateTime.now())!;
    await db.into(db.aiJobsTable).insert(
      AiJobsTableCompanion.insert(
        id: jobId,
        threadId: thread,
        state: Value(state),
        stage: Value(stage),
        createdAt: now,
        updatedAt: now,
      ),
    );
    return jobId;
  }

  final draftJson = <String, Object?>{
    'v': 1,
    'job_kind': 'receipt',
    'merchant': 'Migros',
    'currency': 'TRY',
    'at': '2026-10-29T10:00:00Z',
    'lines': [
      {
        'i': 0,
        'name': 'Milk',
        'category_name': 'Dairy',
        'quantity': 2,
        'unit_price': 30,
        'amount': 60,
        'price_change': true,
      },
      {
        'i': 1,
        'name': 'Pears',
        'category_name': 'Fruit',
        'quantity': 1,
        'unit_price': 60,
        'amount': 60,
        'new_category': true,
        'needs_answer': true,
        'questions': ['cat:1'],
      },
    ],
    'sum': {'lines_sum': 120, 'expected': 120, 'difference': 0, 'ok': true},
    'action': {'name': 'Shop', 'new': true},
    'fx_source': 'market',
  };

  uiTest('Budget shows the chat button and opens the threads screen', (
    tester,
  ) async {
    await mount(tester, const BudgetScreen());
    expect(find.byKey(const ValueKey('ai-chat-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('budget-fab')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-chat-button')));
    await settle(tester);
    expect(find.byKey(const ValueKey('ai-threads-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-new-thread')), findsOneWidget);
    expect(find.text('Receipts'), findsOneWidget);
  });

  uiTest('unpaired device sees the hub-required state', (tester) async {
    await mount(tester, const AiThreadsScreen(), hub: false);
    expect(find.byKey(const ValueKey('ai-hub-required')), findsOneWidget);
    expect(find.text('Connect a hub in Settings to use the assistant'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('ai-new-thread')), findsNothing);
  });

  uiTest('chat screen without a hub shows the same state', (tester) async {
    await mount(tester, AiChatScreen(threadId: 'x'), hub: false);
    expect(find.byKey(const ValueKey('ai-hub-required')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-chat-input')), findsNothing);
  });

  uiTest('new chat button creates a thread', (tester) async {
    await mount(tester, const AiThreadsScreen());
    await tester.tap(find.byKey(const ValueKey('ai-new-thread')));
    await settle(tester);
    expect(await count(tester, 'ai_threads'), 2);
    expect(find.byKey(const ValueKey('ai-chat-input')), findsOneWidget);
  });

  uiTest('sending text creates a message and a job', (tester) async {
    await mount(tester, AiChatScreenForTest.of(() => thread));
    await tester.enterText(
      find.byKey(const ValueKey('ai-chat-input')),
      'moved 100 from FOP to Mono',
    );
    await tester.tap(find.byKey(const ValueKey('ai-chat-send')));
    await settle(tester);
    expect(await count(tester, 'ai_messages'), 1);
    expect(await count(tester, 'ai_jobs'), 1);
    expect(find.text('moved 100 from FOP to Mono'), findsOneWidget);
  });

  uiTest('sending a photo creates message, blob and job', (tester) async {
    final picked = <AiPhotoSource>[];
    await mount(
      tester,
      AiChatScreenForTest.of(() => thread),
      overrides: [
        aiPhotoPickerProvider.overrideWithValue((s) async {
          picked.add(s);
          return Uint8List.fromList([1, 2, 3, 4]);
        }),
        aiPhotoPrepProvider.overrideWithValue(
          (b) async => (bytes: b, width: 10, height: 20),
        ),
      ],
    );
    await tester.tap(
      find.byKey(const ValueKey('ai-chat-attach-photo-kind-screenshot')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-chat-attach')));
    await settle(tester);
    expect(picked, [AiPhotoSource.file]);
    expect(await count(tester, 'ai_blobs'), 1);
    expect(await count(tester, 'ai_jobs'), 1);
    final kind = (await tester.runAsync(
      () async => (await db.select(db.aiJobsTable).getSingle()).kind,
    ))!;
    expect(kind, AiJobKind.screenshot);
    expect(find.byType(Image), findsOneWidget);
  });

  uiTest('status line follows the status message', (tester) async {
    late String msgId;
    await mount(
      tester,
      AiChatScreenForTest.of(() => thread),
      seed: () async {
        final job = await insertJob(AiJobState.running, AiStage.reading);
        msgId = await insertMessage(
          kind: AiMessageKind.status,
          body: AiStage.reading,
          jobId: job,
        );
      },
    );
    expect(find.byKey(const ValueKey('ai-status-line')), findsOneWidget);
    expect(find.text('Reading receipt'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.runAsync(
      () =>
          (db.update(db.aiMessagesTable)..where((t) => t.id.equals(msgId)))
              .write(const AiMessagesTableCompanion(body: Value('Matching categories'))),
    );
    await settle(tester);
    expect(find.text('Matching categories'), findsOneWidget);
  });

  uiTest('waiting-for-hub badge when jobs are queued and sync is offline', (
    tester,
  ) async {
    await mount(
      tester,
      AiChatScreenForTest.of(() => thread),
      seed: () => insertJob(AiJobState.queued, AiStage.queued),
      overrides: [
        aiHubUnreachableProvider.overrideWithValue(true),
      ],
    );
    expect(find.byKey(const ValueKey('ai-waiting-for-hub')), findsOneWidget);
  });

  uiTest('draft card renders lines and badges, Confirm sends the edits', (
    tester,
  ) async {
    late String draftId;
    late String catId;
    await mount(
      tester,
      AiChatScreenForTest.of(() => thread),
      seed: () async {
        final seed = Seed(db);
        final group = await seed.group('Food');
        catId = await seed.leaf('Cheese', price: 10, parentId: group);
        final job = await insertJob(AiJobState.draftReady, AiStage.waiting);
        draftId = await insertMessage(
          kind: AiMessageKind.draft,
          json: draftJson,
          jobId: job,
        );
      },
    );
    expect(find.text('Milk  ->  Dairy'), findsOneWidget);
    expect(find.text('price change'), findsOneWidget);
    expect(find.text('new category'), findsOneWidget);
    expect(find.text('needs answer'), findsOneWidget);
    expect(find.text('Lines add up to 120 TRY'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-draft-line-1')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ai-draft-line-0')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('ai-line-qty')), '3');
    await tester.enterText(find.byKey(const ValueKey('ai-line-price')), '25,5');
    await tester.tap(find.byKey(const ValueKey('ai-line-category')));
    await tester.pumpAndSettle();
    await settle(tester);
    await tester.tap(find.byKey(ValueKey('pick-category-$catId')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-line-save')));
    await tester.pumpAndSettle();
    expect(find.text('Milk  ->  Cheese'), findsOneWidget);
    expect(find.text('edited'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ai-draft-confirm')));
    await settle(tester);
    final row = (await tester.runAsync(
      () => (db.select(db.aiMessagesTable)
            ..where((t) => t.kind.equals(AiMessageKind.confirm)))
          .getSingle(),
    ))!;
    final d = ConfirmDecision.fromJson(
      jsonDecode(row.contentJson) as Map<String, dynamic>,
    );
    expect(d.draftMessageId, draftId);
    expect(d.confirm, isTrue);
    expect(d.edits, hasLength(1));
    expect(d.edits.single.index, 0);
    expect(d.edits.single.categoryId, catId);
    expect(d.edits.single.quantity, 3);
    expect(d.edits.single.unitPrice, 25.5);
    // The card now shows the decision instead of the buttons.
    expect(find.byKey(const ValueKey('ai-draft-confirm')), findsNothing);
  });

  uiTest('Reject writes a reject decision', (tester) async {
    await mount(
      tester,
      AiChatScreenForTest.of(() => thread),
      seed: () async {
        final job = await insertJob(AiJobState.draftReady, AiStage.waiting);
        await insertMessage(
          kind: AiMessageKind.draft,
          json: draftJson,
          jobId: job,
        );
      },
    );
    await tester.tap(find.byKey(const ValueKey('ai-draft-reject')));
    await settle(tester);
    final row = (await tester.runAsync(
      () => (db.select(db.aiMessagesTable)
            ..where((t) => t.kind.equals(AiMessageKind.confirm)))
          .getSingle(),
    ))!;
    expect(
      ConfirmDecision.fromJson(jsonDecode(row.contentJson) as Map<String, dynamic>)
          .confirm,
      isFalse,
    );
  });

  uiTest('question chips answer and write the answer', (tester) async {
    late String qId;
    await mount(
      tester,
      AiChatScreenForTest.of(() => thread),
      seed: () async {
        final job = await insertJob(AiJobState.needsInput, AiStage.waiting);
        qId = await insertMessage(
          kind: AiMessageKind.question,
          jobId: job,
          json: const QuestionCard([
            Question(
              id: 'weight:1',
              text: 'How heavy is the cheese?',
              options: ['500 g', '1 kg'],
              recommended: 1,
            ),
            Question(id: 'acc', text: 'Which card?', options: ['Visa']),
          ]).toJson(),
        );
      },
    );
    expect(find.text('1. How heavy is the cheese?'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-question-input-1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-question-chip-0-1')));
    await settle(tester);
    final card = (await tester.runAsync(
      () => (db.select(db.aiMessagesTable)..where((t) => t.id.equals(qId)))
          .getSingle(),
    ))!;
    final qs = QuestionCard.fromJson(
      jsonDecode(card.contentJson) as Map<String, dynamic>,
    ).questions;
    expect(qs[0].answer, '1 kg');
    expect(qs[1].answer, isNull);
    expect(find.text('Answer: 1 kg'), findsOneWidget);
  });

  uiTest('result card Undo batch removes the transaction', (tester) async {
    late String batchId;
    await mount(
      tester,
      AiChatScreenForTest.of(() => thread),
      seed: () async {
        final seed = Seed(db);
        final group = await seed.group('Food');
        final leaf = await seed.leaf('Cheese', price: 10, parentId: group);
        final tx = await seed.budget.createTransaction(categoryId: leaf);
        final job = await insertJob(AiJobState.done, AiStage.done);
        final batches = AiBatchService(db);
        batchId = await batches.startBatch(jobId: job, threadId: thread);
        await batches.record(
          batchId,
          position: 0,
          entityType: AiEntity.transaction,
          entityId: tx,
        );
        await insertMessage(
          kind: AiMessageKind.result,
          jobId: job,
          json: {
            'batch_id': batchId,
            'summary': 'Recorded 1 transaction',
            'lines': [
              {'name': 'Cheese', 'category_name': 'Cheese', 'amount': 10},
            ],
          },
        );
      },
    );
    expect(await count(tester, 'budget_transactions'), 1);
    expect(find.text('Recorded - created by assistant'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-result-undo')));
    await settle(tester);
    await settle(tester);
    expect(await count(tester, 'budget_transactions'), 0);
    expect(find.byKey(const ValueKey('ai-result-undone')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-result-undo')), findsNothing);
    await tester.pump(const Duration(seconds: 10));
  });

  uiTest('load older shows older messages from the local database', (
    tester,
  ) async {
    await mount(
      tester,
      AiChatScreenForTest.of(() => thread),
      seed: () async {
        for (var i = 0; i < 105; i++) {
          final t = dateTimeToDb(
            DateTime.utc(2026, 1, 1).add(Duration(minutes: i)),
          )!;
          await insertMessage(
            kind: AiMessageKind.text,
            body: 'msg $i',
            createdAt: t,
          );
        }
      },
    );
    expect(find.text('msg 0'), findsNothing);
    final older = find.byKey(const ValueKey('ai-load-older'));
    for (var i = 0; i < 30 && older.evaluate().isEmpty; i++) {
      await tester.drag(find.byKey(const ValueKey('ai-chat-list')), const Offset(0, 800));
      await tester.pump();
    }
    await settle(tester);
    // Reaching the top loads older messages by itself (scroll listener).
    expect(find.text('msg 0'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-chat-list')), findsOneWidget);
  });

  for (final size in const [Size(800, 600), Size(1400, 900)]) {
    uiTest('no overflow with a draft at ${size.width.toInt()}x'
        '${size.height.toInt()}', (tester) async {
      await mount(
        tester,
        AiChatScreenForTest.of(() => thread),
        size: size,
        seed: () async {
          final job = await insertJob(AiJobState.draftReady, AiStage.waiting);
          await insertMessage(
            kind: AiMessageKind.draft,
            json: draftJson,
            jobId: job,
          );
          await insertMessage(kind: AiMessageKind.text, body: 'hello');
        },
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('ai-draft-confirm')), findsOneWidget);
    });
  }
}

/// The thread id is created inside [mount], so the screen is built lazily.
class AiChatScreenForTest extends StatelessWidget {
  const AiChatScreenForTest._(this._id);
  static Widget of(String Function() id) => AiChatScreenForTest._(id);
  final String Function() _id;

  @override
  Widget build(BuildContext context) => AiChatScreen(threadId: _id());
}
