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
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/ai/ai_protocol.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/ai_ui_providers.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/screens/ai_chat_screen.dart';
import 'package:livenow/ui/screens/ai_threads_screen.dart';
import 'package:livenow/ui/screens/budget_screen.dart';
import 'package:livenow/ui/sync_providers.dart';
import 'package:livenow/ui/time_format.dart';
import 'package:livenow/ui/widgets/action_editor.dart';

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

  uiTest('a chat is deleted for good after a confirmation; Cancel keeps it', (tester) async {
    await mount(tester, const AiThreadsScreen(), seed: () async {
      await chat.sendText(thread, 'купив молоко 59');
    });
    expect(find.text('Archive'), findsNothing);
    await tester.tap(find.byKey(ValueKey('ai-thread-menu-$thread')));
    await tester.pumpAndSettle();
    expect(find.text('Archive'), findsNothing, reason: 'there is no archive any more');
    await tester.tap(find.byKey(ValueKey('ai-thread-delete-$thread')));
    await tester.pumpAndSettle();
    expect(find.text('Delete chat?'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ai-thread-delete-cancel')));
    await settle(tester);
    expect(await count(tester, 'ai_threads'), 1);
    expect(await count(tester, 'ai_messages'), 1);

    await tester.tap(find.byKey(ValueKey('ai-thread-menu-$thread')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('ai-thread-delete-$thread')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-thread-delete-confirm')));
    await settle(tester);
    expect(await count(tester, 'ai_threads'), 0);
    expect(await count(tester, 'ai_messages'), 0);
    expect(await count(tester, 'ai_jobs'), 0);
    expect(find.byKey(const ValueKey('ai-threads-empty')), findsOneWidget);
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

  List<Override> twoPhotos(List<AiPhotoSource> picked) => [
    aiPhotoPickerProvider.overrideWithValue((s) async {
      picked.add(s);
      return [
        Uint8List.fromList([1, 2, 3, 4]),
        Uint8List.fromList([5, 6, 7, 8]),
      ];
    }),
    aiPhotoPrepProvider.overrideWithValue(
      (b) async => (bytes: b, width: 10, height: 20),
    ),
  ];

  uiTest('photos wait in the composer and go out with the text as ONE message', (
    tester,
  ) async {
    final picked = <AiPhotoSource>[];
    await mount(
      tester,
      AiChatScreenForTest.of(() => thread),
      overrides: twoPhotos(picked),
    );
    // There is no receipt / bank screenshot switch any more.
    expect(find.text('Receipt'), findsNothing);
    expect(find.text('Bank screenshot'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('ai-chat-attach')));
    await settle(tester);
    expect(picked, [AiPhotoSource.file]);
    expect(find.byKey(const ValueKey('ai-chat-pending-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-chat-pending-1')), findsOneWidget);
    expect(await count(tester, 'ai_jobs'), 0, reason: 'picking sends nothing');

    await tester.enterText(
      find.byKey(const ValueKey('ai-chat-input')),
      'BIM, card 6141',
    );
    await tester.tap(find.byKey(const ValueKey('ai-chat-send')));
    await settle(tester);
    expect(await count(tester, 'ai_messages'), 1);
    expect(await count(tester, 'ai_blobs'), 2);
    expect(await count(tester, 'ai_jobs'), 1);
    final kind = (await tester.runAsync(
      () async => (await db.select(db.aiJobsTable).getSingle()).kind,
    ))!;
    expect(kind, AiJobKind.photos);
    expect(find.byKey(const ValueKey('ai-chat-pending-0')), findsNothing);
    expect(find.text('BIM, card 6141'), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(2), reason: 'both photos in one bubble');
  });

  uiTest('a pending photo can be removed, and photos alone can be sent', (
    tester,
  ) async {
    await mount(
      tester,
      AiChatScreenForTest.of(() => thread),
      overrides: twoPhotos([]),
    );
    await tester.tap(find.byKey(const ValueKey('ai-chat-attach')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('ai-chat-pending-remove-0')));
    await tester.pump();
    expect(find.byKey(const ValueKey('ai-chat-pending-1')), findsNothing);
    expect(find.byKey(const ValueKey('ai-chat-pending-0')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ai-chat-send')));
    await settle(tester);
    expect(await count(tester, 'ai_blobs'), 1);
    expect(await count(tester, 'ai_jobs'), 1);
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

  uiTest('a v2 status shows the step, a live % and its time, and a bar', (tester) async {
    final started = DateTime.now().toUtc().subtract(const Duration(seconds: 30));
    late String job;
    await mount(
      tester,
      AiChatScreenForTest.of(() => thread),
      seed: () async {
        job = await insertJob(AiJobState.running, AiStage.matching);
        await insertMessage(
          kind: AiMessageKind.status,
          body: 'Matching categories · batch 2 of 3 · 20%',
          jobId: job,
          json: {
            'v': 2,
            'stage': AiStage.matching,
            'step': 'categories',
            'label': 'Matching categories',
            'detail': 'batch 2 of 3',
            'pct_from': 20.0,
            'pct_to': 60.0,
            'started': started.toIso8601String(),
            'estimate_ms': 60000,
          },
        );
      },
    );
    // Half of the step's 60 s are gone: 20 + 40 * 0.5.
    expect(find.textContaining('Matching categories · batch 2 of 3 · 40% · 0:3'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(find.byKey(const ValueKey('ai-status-bar')));
    expect(bar.value, closeTo(0.4, 0.01));

    // Done: no bar, the plain text.
    await tester.runAsync(() async {
      await (db.update(db.aiJobsTable)..where((t) => t.id.equals(job)))
          .write(const AiJobsTableCompanion(state: Value(AiJobState.done)));
    });
    await settle(tester);
    expect(find.byKey(const ValueKey('ai-status-bar')), findsNothing);
    expect(find.text('Matching categories · batch 2 of 3 · 20%'), findsOneWidget);
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
    expect(find.text('Milk'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('ai-cell-cat-0')), matching: find.text('Dairy')), findsOneWidget);
    expect(find.text('price change'), findsOneWidget);
    expect(find.text('new category'), findsOneWidget);
    expect(find.text('needs answer'), findsOneWidget);
    expect(find.text('Lines add up to 120 TRY'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-draft-line-1')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ai-line-name-0')));
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
    expect(find.descendant(of: find.byKey(const ValueKey('ai-cell-cat-0')), matching: find.text('Cheese')), findsOneWidget);
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

  uiTest('a translated, suggested line shows the Ukrainian name, the printed one and badges', (
    tester,
  ) async {
    await mount(
      tester,
      AiChatScreenForTest.of(() => thread),
      seed: () async {
        final job = await insertJob(AiJobState.draftReady, AiStage.waiting);
        await insertMessage(
          kind: AiMessageKind.draft,
          json: {
            ...draftJson,
            'lines': [
              {
                'i': 0,
                'name': 'BANVIT PILIC BONFILE',
                'ua_name': 'Курка (філе)',
                'category_name': 'Курка (грудка)',
                'quantity': 0.5,
                'unit_price': 330,
                'amount': 165,
                'confidence': 0.87,
                'flags': ['suggested', 'weight_guess'],
              },
            ],
            'sum': {'lines_sum': 165, 'expected': 165, 'difference': 0, 'ok': true},
          },
          jobId: job,
        );
      },
    );
    expect(find.text('Курка (філе)'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('ai-cell-cat-0')), matching: find.text('Курка (грудка)')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-line-printed-0')), findsOneWidget);
    expect(find.text('BANVIT PILIC BONFILE'), findsOneWidget);
    expect(find.text('suggested 87%'), findsOneWidget);
    expect(find.text('weight estimated'), findsOneWidget);
  });

  /// Taps Confirm and returns the decision the card sent.
  Future<ConfirmDecision> sentDecision(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('ai-draft-confirm')));
    await settle(tester);
    final row = (await tester.runAsync(
      () => (db.select(db.aiMessagesTable)
            ..where((t) => t.kind.equals(AiMessageKind.confirm)))
          .getSingle(),
    ))!;
    return ConfirmDecision.fromJson(jsonDecode(row.contentJson) as Map<String, dynamic>);
  }

  Future<void> seedDraft() async {
    final job = await insertJob(AiJobState.draftReady, AiStage.waiting);
    await insertMessage(kind: AiMessageKind.draft, json: draftJson, jobId: job);
  }

  uiTest('tapping the quantity edits it in place; the price follows, the amount stays', (tester) async {
    await mount(tester, AiChatScreenForTest.of(() => thread), seed: seedDraft);
    await tester.tap(find.byKey(const ValueKey('ai-cell-qty-0')));
    await tester.pump();
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('ai-cell-qty-0-field')), '4');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    // 60 / 4 = 15 per unit; the printed amount of the line is still 60.
    expect(find.descendant(of: find.byKey(const ValueKey('ai-cell-price-0')), matching: find.text('15')), findsOneWidget);
    expect(find.text('= 60'), findsWidgets);
    expect(find.text('Confirm (1 edited)'), findsOneWidget);
    final d = await sentDecision(tester);
    expect(d.edits.single.index, 0);
    expect(d.edits.single.quantity, 4);
    expect(d.edits.single.unitPrice, 15);
  });

  uiTest('tapping the price edits it; the quantity follows. The unit chip toggles kg / pcs', (tester) async {
    await mount(tester, AiChatScreenForTest.of(() => thread), seed: seedDraft);
    await tester.tap(find.byKey(const ValueKey('ai-cell-price-0')));
    await tester.pump();
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('ai-cell-price-0-field')), '20');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.descendant(of: find.byKey(const ValueKey('ai-cell-qty-0')), matching: find.text('3')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('ai-cell-unit-0')), matching: find.text('kg')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-cell-unit-0')));
    await tester.pump();
    expect(find.descendant(of: find.byKey(const ValueKey('ai-cell-unit-0')), matching: find.text('pcs')), findsOneWidget);
    final d = await sentDecision(tester);
    expect(d.edits.single.unitPrice, 20);
    expect(d.edits.single.quantity, 3);
    expect(d.edits.single.unit, 'piece');
  });

  uiTest('a new action shows the span Confirm will create; it is not tappable', (tester) async {
    await mount(tester, AiChatScreenForTest.of(() => thread), seed: seedDraft);
    final at = DateTime.utc(2026, 10, 29, 10);
    final when = formatShortSchedule(
      at.subtract(const Duration(minutes: 20)),
      at.add(const Duration(minutes: 20)),
    );
    expect(find.text('Action: Shop (new) · $when'), findsOneWidget);
    expect(
      find.ancestor(of: find.byKey(const ValueKey('ai-draft-action')), matching: find.byType(InkWell)),
      findsNothing,
    );
  });

  uiTest('an existing action shows its live dates and opens its edit menu on tap', (tester) async {
    final start = DateTime.utc(2026, 11, 7, 16, 45);
    final end = DateTime.utc(2026, 11, 7, 17, 30);
    await mount(tester, AiChatScreenForTest.of(() => thread), seed: () async {
      final actionId = await ActionService(db).createAction(
        name: 'Process returns',
        startAt: start,
        endAt: end,
      );
      final job = await insertJob(AiJobState.draftReady, AiStage.waiting);
      await insertMessage(
        kind: AiMessageKind.draft,
        json: {
          ...draftJson,
          'action': {'id': actionId, 'name': 'old name', 'new': false},
        },
        jobId: job,
      );
    });
    final label = find.byKey(const ValueKey('ai-draft-action'));
    // The live name, not the one stored in the draft.
    expect(find.text('Action: Process returns · ${formatShortSchedule(start, end)}'), findsOneWidget);
    await tester.ensureVisible(label);
    await tester.tap(label);
    await settle(tester);
    expect(find.byType(ActionEditorDialog), findsOneWidget);
  });

  uiTest('the category chooser: an offered one, a searched one, and a new one in a group', (tester) async {
    late String groupId, milk;
    await mount(
      tester,
      AiChatScreenForTest.of(() => thread),
      seed: () async {
        final seed = Seed(db);
        groupId = await seed.group('Food');
        await seed.leaf('Cheese', price: 10, parentId: groupId);
        milk = await seed.leaf('Milk Dost', price: 59, parentId: groupId);
        final job = await insertJob(AiJobState.draftReady, AiStage.waiting);
        await insertMessage(
          kind: AiMessageKind.draft,
          json: {
            ...draftJson,
            'lines': [
              {
                'i': 0,
                'name': 'SUT',
                'quantity': 1,
                'unit_price': 60,
                'amount': 60,
                'needs_answer': true,
                'candidates': [
                  {'id': milk, 'name': 'Milk Dost', 'parent': 'Food', 'price': 59, 'unit': 'kilogram', 'use_acc': 'Card'},
                ],
              },
            ],
            'sum': {'lines_sum': 60, 'expected': 60, 'difference': 0, 'ok': true},
          },
          jobId: job,
        );
      },
    );
    // Undecided: tapping the category cell offers the assistant's list with prices.
    await tester.tap(find.byKey(const ValueKey('ai-cell-cat-0')));
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.byKey(const ValueKey('ai-category-chooser')), findsOneWidget);
    expect(find.textContaining('59.00'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-chooser-offer-0')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const ValueKey('ai-cell-cat-0')), matching: find.text('Milk Dost')), findsOneWidget);

    // By typing: finds Cheese.
    await tester.tap(find.byKey(const ValueKey('ai-cell-cat-0')));
    await tester.pumpAndSettle();
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('ai-chooser-search')), 'chee');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-chooser-result-0')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const ValueKey('ai-cell-cat-0')), matching: find.text('Cheese')), findsOneWidget);

    // A name that exists nowhere: create it in the group.
    await tester.tap(find.byKey(const ValueKey('ai-cell-cat-0')));
    await tester.pumpAndSettle();
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('ai-chooser-search')), 'Prunes');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-chooser-create')));
    await tester.pumpAndSettle();
    expect(find.text('Prunes (new)'), findsOneWidget);

    final d = await sentDecision(tester);
    expect(d.edits.single.categoryId, groupId, reason: 'the group the new category goes in');
    expect(d.edits.single.newName, 'Prunes');
  });

  uiTest('a receipt that was saved before shows the saved lines', (tester) async {
    await mount(
      tester,
      AiChatScreenForTest.of(() => thread),
      seed: () async {
        final job = await insertJob(AiJobState.needsInput, AiStage.waiting);
        await insertMessage(
          kind: AiMessageKind.draft,
          json: {
            ...draftJson,
            'seen': {
              'batch_id': 'b1',
              'job_id': 'j0',
              'at': '2026-10-08T16:40:00Z',
              'merchant': 'BIM',
              'lines': [
                {'name': 'Milk', 'category': 'Dairy', 'quantity': 3, 'unit_price': 20},
                {'name': 'Bread', 'category': 'Bakery', 'quantity': 1, 'unit_price': 15},
              ],
            },
          },
          jobId: job,
        );
      },
    );
    expect(find.byKey(const ValueKey('ai-seen')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-seen-line-0')), findsOneWidget);
    expect(find.textContaining('Milk  ->  Dairy'), findsOneWidget);
    expect(find.textContaining('= 60'), findsWidgets);
    expect(find.byKey(const ValueKey('ai-seen-line-1')), findsOneWidget);
  });

  uiTest('choosing a category for one line applies it to the lines with the same name', (tester) async {
    late String cheese;
    await mount(
      tester,
      AiChatScreenForTest.of(() => thread),
      seed: () async {
        final seed = Seed(db);
        final group = await seed.group('Food');
        cheese = await seed.leaf('Cheese', price: 10, parentId: group);
        final job = await insertJob(AiJobState.draftReady, AiStage.waiting);
        Map<String, dynamic> line(int i) => {
          'i': i,
          'name': 'PEYNIR',
          'quantity': 1,
          'unit_price': 60,
          'amount': 60,
          'needs_answer': true,
          'candidates': [],
        };
        await insertMessage(
          kind: AiMessageKind.draft,
          json: {
            ...draftJson,
            'lines': [line(0), line(1)],
            'sum': {'lines_sum': 120, 'expected': 120, 'difference': 0, 'ok': true},
          },
          jobId: job,
        );
      },
    );
    expect(find.text('Lines with the same name share one category.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-cell-cat-0')));
    await tester.pumpAndSettle();
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('ai-chooser-search')), 'chee');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-chooser-result-0')));
    await tester.pumpAndSettle();
    for (final i in [0, 1]) {
      expect(
        find.descendant(of: find.byKey(ValueKey('ai-cell-cat-$i')), matching: find.text('Cheese')),
        findsOneWidget,
      );
    }
    final d = await sentDecision(tester);
    expect(d.edits.map((e) => e.index), [0, 1]);
    expect(d.edits.every((e) => e.categoryId == cheese), isTrue);
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

  uiTest('a failed job shows Retry; tapping it writes a retry row and hides the button', (
    tester,
  ) async {
    late String errId;
    late String job;
    await mount(
      tester,
      AiChatScreenForTest.of(() => thread),
      seed: () async {
        job = await insertJob(AiJobState.failed, 'Failed');
        errId = await insertMessage(
          kind: AiMessageKind.error,
          body: 'OCR service unreachable',
          json: {'v': 1, 'retryable': true},
          jobId: job,
          createdAt: '2026-01-01T00:00:00.000000Z', // before the Retry row (now)
        );
      },
    );
    final retry = find.byKey(ValueKey('ai-error-retry-$errId'));
    expect(retry, findsOneWidget);
    await tester.tap(retry);
    await settle(tester);
    final row = (await tester.runAsync(
      () => (db.select(db.aiMessagesTable)
            ..where((t) => t.kind.equals(AiMessageKind.retry)))
          .getSingle(),
    ))!;
    expect(row.jobId, job);
    expect(row.role, AiRole.user);
    expect(retry, findsNothing, reason: 'already retried: the hub requeues it');
  });

  uiTest('an error that cannot be retried has no Retry button', (tester) async {
    late String errId;
    await mount(
      tester,
      AiChatScreenForTest.of(() => thread),
      seed: () async {
        final job = await insertJob(AiJobState.failed, 'Failed');
        errId = await insertMessage(
          kind: AiMessageKind.error,
          body: 'Photo not found',
          json: {'v': 1, 'retryable': false},
          jobId: job,
        );
      },
    );
    expect(find.byKey(ValueKey('ai-error-retry-$errId')), findsNothing);
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

  /// A draft with ONE open category question about line 1, whose two offered
  /// categories are called the same and differ only by their group.
  Future<String> seedCategoryQuestion() async {
    final job = await insertJob(AiJobState.needsInput, AiStage.waiting);
    await insertMessage(
      kind: AiMessageKind.draft,
      jobId: job,
      json: {
        ...draftJson,
        'lines': [
          {
            'i': 1,
            'raw': 'LiMON %1.',
            'name': 'LiMON',
            'ua_name': 'лимон',
            'quantity': 0.785,
            'unit': 'kilogram',
            'unit_price': 39,
            'amount': 30.62,
            'needs_answer': true,
            'questions': ['cat:1'],
            'candidates': [
              {'id': 'c-a', 'name': 'Лимон', 'parent': 'Їжа', 'price': 80, 'unit': 'kilogram'},
              {'id': 'c-b', 'name': 'Лимон', 'parent': 'Побут', 'price': 120, 'unit': 'piece'},
            ],
          },
        ],
        'sum': {'lines_sum': 30.62, 'expected': 30.62, 'difference': 0, 'ok': true},
      },
    );
    return insertMessage(
      kind: AiMessageKind.question,
      jobId: job,
      json: const QuestionCard([
        Question(
          id: 'cat:1',
          text: 'Яка категорія для «лимон» (30.62 TRY)?',
          options: ['Їжа › Лимон', 'Побут › Лимон'],
          optionIds: ['c-a', 'c-b'],
          recommended: 0,
        ),
      ]).toJson(),
    );
  }

  Future<Question> answeredQuestion(WidgetTester tester, String qId) async {
    final card = (await tester.runAsync(
      () => (db.select(db.aiMessagesTable)..where((t) => t.id.equals(qId))).getSingle(),
    ))!;
    return QuestionCard.fromJson(
      jsonDecode(card.contentJson) as Map<String, dynamic>,
    ).questions.single;
  }

  uiTest('two options that read alike are answered by their own ids', (tester) async {
    late String qId;
    await mount(
      tester,
      AiChatScreenForTest.of(() => thread),
      seed: () async => qId = await seedCategoryQuestion(),
    );
    expect(find.text('Їжа › Лимон'), findsOneWidget);
    expect(find.text('Побут › Лимон'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-question-chip-0-1')));
    await settle(tester);
    final q = await answeredQuestion(tester, qId);
    expect(q.answer, 'Побут › Лимон');
    expect(q.answerId, 'c-b', reason: 'the second option, not the first one of that name');
  });

  uiTest('a question shows its line and opens the details to check and choose', (
    tester,
  ) async {
    late String qId;
    await mount(
      tester,
      AiChatScreenForTest.of(() => thread),
      seed: () async => qId = await seedCategoryQuestion(),
    );
    final line = tester.widget<Text>(find.byKey(const ValueKey('ai-question-line-0')));
    expect(line.data, contains('LiMON'));
    expect(line.data, contains('0.785 kg × 39.00 = 30.62 TRY'));

    await tester.tap(find.byKey(const ValueKey('ai-question-open-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai-line-details')), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const ValueKey('ai-line-details')), matching: find.textContaining('120.00')),
      findsOneWidget,
      reason: 'the usual price of option 2',
    );
    // The same hint is on the option row itself, no sheet needed.
    expect(find.byKey(const ValueKey('ai-question-info-0-1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-detail-choice-1')));
    await settle(tester);
    final q = await answeredQuestion(tester, qId);
    expect(q.answerId, 'c-b');
    expect(q.answer, 'Побут › Лимон');
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
