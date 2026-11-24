// The bank statement summary card: groups, expanding rows, Confirm.
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/time_codec.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/ai/ai_chat_service.dart';
import 'package:livenow/domain/ai/ai_protocol.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/widgets/ai_draft_card.dart';

import '../domain/ai/ai_test_support.dart';

Map<String, Object?> _content({String stage = 'ready'}) => {
  'type': 'statement',
  'v': 1,
  'stage': stage,
  'file_name': 'report.csv',
  'account_name': 'Monobank',
  'period': {'from': '2026-11-20T10:00:00', 'to': '2026-11-22T19:00:00'},
  'groups': [
    {
      'kind': 'purchase',
      'title': 'Продукти › Супермаркет',
      'count': 2,
      'totals': {'UAH': 420.5},
      'rows': [
        {'i': 3, 'at': '2026-11-22T18:00:00', 'details': 'Сільпо 123', 'amount': 300.0, 'currency': 'UAH'},
        {'i': 4, 'at': '2026-11-22T19:00:00', 'details': 'Сільпо 7', 'amount': 120.5, 'currency': 'UAH'},
      ],
    },
    {
      'kind': 'transfer',
      'title': 'ФОП → Monobank',
      'count': 1,
      'totals': {'UAH': 9000.0},
      'rows': [
        {'i': 1, 'at': '2026-11-20T10:00:00', 'details': 'З гривневого рахунку ФОП', 'amount': 9000.0, 'currency': 'UAH'},
      ],
    },
  ],
  'skipped_duplicates': [
    {'i': 8, 'at': '2026-11-23T10:00:00', 'details': 'Кіоск Тест', 'amount': 120.0, 'currency': 'UAH'},
  ],
  'cancelled': [
    {'i': 6, 'at': '2026-11-21T09:00:00', 'details': 'Тест Магазин', 'amount': 250.0, 'currency': 'UAH', 'reason': 'скасовано'},
    {'i': 7, 'at': '2026-11-21T09:00:10', 'details': 'Скасування. Тест Магазин', 'amount': 250.0, 'currency': 'UAH'},
  ],
  'warnings': <String>[],
};

void main() {
  late AppDatabase db;

  Future<AiMessage> seed(Map<String, Object?> json) async {
    final chat = AiChatService(db);
    final thread = await chat.createThread(title: 'Statements');
    final now = dateTimeToDb(DateTime.now())!;
    await db.into(db.aiMessagesTable).insert(
      AiMessagesTableCompanion.insert(
        id: 'draft1',
        threadId: thread,
        role: const Value(AiRole.assistant),
        kind: const Value(AiMessageKind.draft),
        body: const Value('Виписка'),
        contentJson: Value(jsonEncode(json)),
        createdAt: now,
        updatedAt: now,
      ),
    );
    return (db.select(db.aiMessagesTable)..where((t) => t.id.equals('draft1'))).getSingle();
  }

  Future<void> mount(WidgetTester tester, Map<String, Object?> json) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = memoryDb();
    final message = (await tester.runAsync(() => seed(json)))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: AiDraftCard(message: message, decision: null)),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(db.close);
  }

  testWidgets('groups with totals, rows on tap, collapsed lists, ONE Confirm that writes the confirm row', (tester) async {
    await mount(tester, _content());
    expect(find.byKey(const ValueKey('ai-stmt-card')), findsOneWidget);
    expect(find.text('report.csv  -  Monobank  -  20.11.2026 - 22.11.2026'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-stmt-group-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-stmt-group-1')), findsOneWidget);
    expect(find.text('Продукти › Супермаркет (2)'), findsOneWidget);
    expect(find.text('420.50 UAH'), findsOneWidget);
    expect(find.text('ФОП → Monobank (1)'), findsOneWidget);
    expect(find.text('Already recorded (1)'), findsOneWidget);
    expect(find.text('Cancelled (2)'), findsOneWidget);
    // Rows are hidden until the group is opened.
    expect(find.text('Сільпо 123'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('ai-stmt-group-0-header')));
    await tester.pump();
    expect(find.text('Сільпо 123'), findsOneWidget);
    expect(find.text('22.11'), findsNWidgets(2));
    expect(find.text('300 UAH'), findsOneWidget);
    expect(find.text('Кіоск Тест'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('ai-stmt-dups-header')));
    await tester.pump();
    expect(find.text('Кіоск Тест'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-stmt-group-0-header')));
    await tester.pump();
    expect(find.text('Сільпо 123'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('ai-stmt-confirm')));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    final rows = (await tester.runAsync(
      () => (db.select(db.aiMessagesTable)..where((t) => t.kind.equals(AiMessageKind.confirm))).get(),
    ))!;
    expect(rows, hasLength(1));
    final decision = ConfirmDecision.fromJson(jsonDecode(rows.single.contentJson) as Map<String, dynamic>);
    expect(decision.draftMessageId, 'draft1');
    expect(decision.confirm, isTrue);
    await finish(tester);
  });

  testWidgets('while questions are open there is no Confirm', (tester) async {
    await mount(tester, {..._content(stage: 'asking'), 'groups': const <Object>[]});
    expect(find.byKey(const ValueKey('ai-stmt-asking')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-stmt-confirm')), findsNothing);
    await finish(tester);
  });

  testWidgets('after the write the card shows the decision, not the buttons', (tester) async {
    await mount(tester, {..._content(stage: 'done'), 'confirmed': true});
    expect(find.byKey(const ValueKey('ai-stmt-confirm')), findsNothing);
    expect(find.text('Confirmed'), findsOneWidget);
    await finish(tester);
  });
}
