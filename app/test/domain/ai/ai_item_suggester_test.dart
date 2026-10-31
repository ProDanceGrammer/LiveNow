import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/ai/llm_client.dart';
import 'package:livenow/domain/ai/ai_protocol.dart';
import 'package:livenow/domain/postpone_rules.dart';

import '../../data/ai/mock_llm_server.dart';
import 'ai_runner_support.dart';

/// First chats: nothing is learned yet, and the printed names are Turkish while
/// the categories are Ukrainian. The model translates and suggests; the program
/// validates the suggestion against the real categories.
void main() {
  late RunnerEnv env;
  late MockLlmServer llmServer;

  setUpAll(() {
    HttpOverrides.global = null;
    initPostponeTimeZoneData();
  });
  setUp(() async {
    env = RunnerEnv();
    llmServer = await MockLlmServer.start();
  });
  tearDown(() async {
    await env.close();
    await llmServer.close();
  });

  LlmClient llmClient() => LlmClient(
    baseUrl: llmServer.url,
    model: 'm',
    requestTimeout: const Duration(seconds: 5),
    maxRetries: 0,
    retryBaseDelay: Duration.zero,
  );

  Future<String> chicken() => env.budget.saveCategory(
    CategoryInputLike.leaf('Курка (грудка)', 330, env.groupFood, env.tryAcc, env.monoAcc),
  );

  void translateAndPick(List<Map<String, Object?>> picks, List<String> ua) {
    llmServer.enqueueJson({
      'items': [
        for (var i = 0; i < ua.length; i++) {'n': i + 1, 'ua': ua[i]},
      ],
    });
    llmServer.enqueueJson({'items': picks});
  }

  test('translated, pre-filled with a suggestion and a new leaf: no questions', () async {
    await env.init(llm: llmClient());
    final chickenId = await chicken();
    translateAndPick(
      [
        {'n': 1, 'pick': 'c1', 'group': 'none', 'name': '', 'confidence': 0.9},
        {'n': 2, 'pick': 'new', 'group': 'g1', 'name': 'Чорнослив', 'confidence': 0.8},
      ],
      ['Курка (філе)', 'Чорнослив'],
    );
    final jobId = await env.sendReceipt(
      receiptOf([
        rl('BANVIT PILIC BONFILE', 278.85, qty: 0.845, unit: 'kg', unitPrice: 330),
        rl('TADIM KURU ERIK', 105.00, grams: 400),
      ]),
    );
    await env.drain();

    expect((await env.job(jobId)).state, AiJobState.draftReady);
    expect(await env.message(jobId, AiMessageKind.question), isNull, reason: 'nothing to ask');
    final d = await env.draft(jobId);
    final chickenLine = d.lines[0];
    expect(chickenLine['category_id'], chickenId);
    expect(chickenLine['ua_name'], 'Курка (філе)');
    expect(chickenLine['flags'], contains('suggested'));
    expect(chickenLine['needs_answer'], isFalse);
    final prune = d.lines[1];
    expect(prune['ua_name'], 'Чорнослив');
    expect(prune['new_category'], isTrue);
    expect(prune['one_off_group_id'], env.groupFood);
    expect(prune['needs_answer'], isFalse);
    expect(llmServer.chatRequests.length, 2, reason: 'one translation, one decision');
    expect(await env.count('budget_transactions'), 0, reason: 'draft first: nothing written');

    // Confirm creates the new leaf under the group, named in Ukrainian, and the
    // suggested lines become aliases so the next receipt needs no model.
    await env.chat.confirmDraft(d.messageId);
    await env.drain();
    expect((await env.job(jobId)).state, AiJobState.done);
    expect(llmServer.chatRequests.length, 2, reason: 'rebuilds do not ask the model again');
    expect(await env.count('budget_categories', "name LIKE '%Чорнослив%'"), 1);
    final tx = await env.transactions();
    expect(tx.length, 2);
    expect(tx.any((t) => t.name.contains('Чорнослив')), isTrue);
    expect((await env.aliases.row('BANVIT PILIC BONFILE'))!.categoryId, chickenId);
  });

  test('a low-confidence or invented pick is asked, with the translation in the question', () async {
    await env.init(llm: llmClient());
    await chicken();
    translateAndPick(
      [
        {'n': 1, 'pick': 'c1', 'group': 'none', 'name': '', 'confidence': 0.1},
        {'n': 2, 'pick': 'c7', 'group': 'g9', 'name': '', 'confidence': 0.99},
      ],
      ['Курка (філе)', 'Щось'],
    );
    final jobId = await env.sendReceipt(
      receiptOf([
        rl('BANVIT PILIC BONFILE', 278.81, qty: 0.845, unit: 'kg', unitPrice: 329.95),
        rl('XYZ UNKNOWN THING', 50.00, grams: 100),
      ]),
    );
    await env.drain();
    final d = await env.draft(jobId);
    expect(d.lines[0]['needs_answer'], isTrue, reason: 'confidence 0.1 is below the bar');
    expect(d.lines[1]['needs_answer'], isTrue, reason: 'c7 / g9 were never offered');
    expect(d.lines[1]['ua_name'], 'Щось', reason: 'the translation is kept anyway');
    final q = (await env.message(jobId, AiMessageKind.question))!;
    expect(q.contentJson, contains('Щось'));
  });

  test('a name typed in Cyrillic is never sent for translation', () async {
    await env.init(llm: llmClient());
    llmServer.enqueueJson({
      'items': [
        {'n': 1, 'pick': 'new', 'group': 'g1', 'name': '', 'confidence': 0.8},
      ],
    });
    final sent = await env.chat.sendText(env.thread, 'купив цвяхи 50 лір готівкою');
    await env.drain();
    final l = (await env.draft(sent.jobId!)).lines.single;
    expect(llmServer.chatRequests.length, 1, reason: 'only the decision, no translation');
    expect(l['ua_name'], 'Цвяхи');
    expect(l['new_category'], isTrue);
  });

  test('tabs and doubled spaces in a model-written name are squeezed', () async {
    await env.init(llm: llmClient());
    await chicken();
    translateAndPick(
      [
        {'n': 1, 'pick': 'new', 'group': 'g1', 'name': 'Здорові \t питнесь', 'confidence': 0.8},
      ],
      ['Соуси \t  компанії'],
    );
    final jobId = await env.sendReceipt(
      receiptOf([rl('MELIS KORNISON TURSU', 109.95, grams: 300)]),
    );
    await env.drain();
    final l = (await env.draft(jobId)).lines.single;
    expect(l['ua_name'], 'Здорові питнесь', reason: 'a new leaf takes the picked name, squeezed');
  });

  test('a model that cannot be reached falls back to questions and is not retried', () async {
    await env.init(llm: llmClient());
    await chicken();
    final jobId = await env.sendReceipt(
      receiptOf([rl('BANVIT PILIC BONFILE', 278.81, qty: 0.845, unit: 'kg', unitPrice: 329.95)]),
    );
    await env.drain();
    final d = await env.draft(jobId);
    expect(d.lines.single['needs_answer'], isTrue);
    expect(jsonDecode(jsonEncode(d.json['overrides']))['suggest_failed'], isTrue);
    final before = llmServer.chatRequests.length;
    expect(before, greaterThanOrEqualTo(1));
    final q = (await env.message(jobId, AiMessageKind.question))!;
    await env.chat.answerQuestion(q.id, 'cat:0', 'Курка (грудка)');
    await env.drain();
    expect(
      llmServer.chatRequests.length,
      before,
      reason: 'a failed suggestion is not re-asked on every rebuild',
    );
    expect((await env.job(jobId)).state, AiJobState.draftReady);
  });

  test('an unmatched typed answer gets a visible reply; "create" makes a new leaf', () async {
    await env.init(); // no model at all: the user decides
    final jobId = await env.sendReceipt(
      receiptOf([rl('TADIM KURU ERIK', 105.00, grams: 400)]),
    );
    await env.drain();
    var q = (await env.message(jobId, AiMessageKind.question))!;
    var card = QuestionCard.fromJson(jsonDecode(q.contentJson) as Map<String, dynamic>);
    expect(card.questions.single.options, contains('Створити «TADIM KURU ERIK» у «Їжа»'));
    expect(q.body, isNot(contains('TADIM')), reason: 'the card lists the question, the body does not');

    // Nothing is called "щось інше": not dropped, not the same card again.
    await env.chat.answerQuestion(q.id, 'cat:0', 'щось інше');
    await env.drain();
    final cards = await env.messages(jobId, AiMessageKind.question);
    expect(cards.length, 2);
    q = cards.last;
    card = QuestionCard.fromJson(jsonDecode(q.contentJson) as Map<String, dynamic>);
    expect(card.questions.single.text, contains('Не знайшов категорію «щось інше»'));
    expect(card.questions.single.options, contains('Створити «щось інше» у «Їжа»'));

    await env.chat.answerQuestion(q.id, 'cat:0', 'Створити «щось інше» у «Їжа»');
    await env.drain();
    expect((await env.job(jobId)).state, AiJobState.draftReady);
    final d = await env.draft(jobId);
    expect(d.lines.single['ua_name'], 'щось інше');
    expect(d.lines.single['new_category'], isTrue);
    await env.chat.confirmDraft(d.messageId);
    await env.drain();
    expect((await env.job(jobId)).state, AiJobState.done);
    expect(await env.count('budget_categories', "name LIKE '%щось інше%'"), 1);
  });

  test('auto mode holds a low-confidence guess for Confirm and writes a sure one', () async {
    await env.init(autoMode: true, llm: llmClient());
    final chickenId = await chicken();
    translateAndPick(
      [
        {'n': 1, 'pick': 'c1', 'group': 'none', 'name': '', 'confidence': 0.55},
      ],
      ['Курка (філе)'],
    );
    final jobId = await env.sendReceipt(
      receiptOf([rl('BANVIT PILIC BONFILE', 278.85, qty: 0.845, unit: 'kg', unitPrice: 330)]),
    );
    await env.drain();
    expect((await env.job(jobId)).state, AiJobState.draftReady);
    expect(await env.count('budget_transactions'), 0, reason: 'a guess is not written alone');
    final d = await env.draft(jobId);
    await env.chat.confirmDraft(d.messageId);
    await env.drain();
    expect((await env.job(jobId)).state, AiJobState.done);
    expect((await env.transactions()).single.categoryId, chickenId);
  });

  test('an unknown pack weight is estimated and flagged, not asked', () async {
    await env.init(llm: llmClient());
    final chickenId = await chicken();
    translateAndPick(
      [
        {'n': 1, 'pick': 'c1', 'group': 'none', 'name': '', 'grams': 500, 'confidence': 0.9},
      ],
      ['Курка (філе)'],
    );
    final jobId = await env.sendReceipt(receiptOf([rl('BANVIT PILIC BONFILE', 165.00)]));
    await env.drain();
    final d = await env.draft(jobId);
    final l = d.lines.single;
    expect(l['category_id'], chickenId);
    expect(l['needs_answer'], isFalse, reason: 'no weight question');
    expect(l['quantity'], closeTo(0.5, 1e-9));
    expect(l['unit_price'], closeTo(330, 1e-6));
    expect(l['flags'], containsAll(['weight_guess', 'suggested']));
    expect(await env.message(jobId, AiMessageKind.question), isNull);
  });

  test('lines a rule already places never reach the model', () async {
    await env.init(llm: llmClient());
    final jobId = await env.sendReceipt(
      receiptOf([rl('EKMEK KÖY 600G', 64.00)]), // learned alias -> Хліб
    );
    await env.drain();
    final d = await env.draft(jobId);
    expect(d.lines.single['category_id'], env.bread);
    expect(d.lines.single['flags'], isNot(contains('suggested')));
    expect(llmServer.chatRequests, isEmpty);
  });
}
