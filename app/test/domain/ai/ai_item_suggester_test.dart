import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/ai/llm_client.dart';
import 'package:livenow/domain/ai/ai_protocol.dart';
import 'package:livenow/domain/postpone_rules.dart';

import '../../data/ai/mock_llm_server.dart';
import 'ai_runner_support.dart';
import 'ai_test_support.dart' show Seed;

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

  test('each model call is a step of the status line with a growing %; times are learned', () async {
    await env.init(llm: llmClient());
    await chicken();
    translateAndPick(
      [
        {'n': 1, 'pick': 'c1', 'group': 'none', 'name': '', 'confidence': 0.9},
        {'n': 2, 'pick': 'new', 'group': 'g1', 'name': 'Чорнослив', 'confidence': 0.8},
      ],
      ['Курка (філе)', 'Чорнослив'],
    );
    late String jobId;
    final seen = <Map<String, dynamic>>[];
    Future<void> grab() async {
      final m = (await env.message(jobId, AiMessageKind.status))!;
      seen.add({...jsonDecode(m.contentJson) as Map<String, dynamic>, 'body': m.body});
    }

    env.extractor.onExtract = grab;
    llmServer.onChat = grab;
    jobId = await env.sendReceipt(
      receiptOf([
        rl('BANVIT FILETO', 278.85, qty: 0.845, unit: 'kg', unitPrice: 330),
        rl('TADIM ERIK KURUSU', 105.00, grams: 400),
      ]),
    );
    await env.drain();

    expect([for (final s in seen) s['step']], ['ocr', 'translate', 'categories']);
    expect(seen.first['v'], 2);
    expect(seen.first['body'], 'Reading the photo (OCR) · 0%');
    expect(seen.last['body'], startsWith('Matching categories · '));
    for (var i = 1; i < seen.length; i++) {
      expect(seen[i]['pct_from'] as num, greaterThanOrEqualTo(seen[i - 1]['pct_to'] as num));
    }
    // The run ended: the status is plain again, the step times are kept.
    final last = (await env.message(jobId, AiMessageKind.status))!;
    expect(jsonDecode(last.contentJson)['v'], 1);
    final timings = jsonDecode(await env.settings.get(AiSettingKey.stepTimings)) as Map;
    expect(timings.keys, containsAll(['ocr', 'lines', 'translate', 'categories', 'checks']));
  });

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
        rl('BANVIT FILETO', 278.85, qty: 0.845, unit: 'kg', unitPrice: 330),
        rl('TADIM ERIK KURUSU', 105.00, grams: 400),
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
    expect((await env.aliases.row('BANVIT FILETO'))!.categoryId, chickenId);
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
        rl('BANVIT FILETO', 278.81, qty: 0.845, unit: 'kg', unitPrice: 329.95),
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

  test('a name the glossary knows is not sent for translation', () async {
    await env.init(llm: llmClient());
    llmServer.enqueueJson({
      'items': [
        {'n': 1, 'pick': 'new', 'group': 'g1', 'name': '', 'confidence': 0.8},
      ],
    });
    final jobId = await env.sendReceipt(
      receiptOf([rl('PATATES', 88.94, qty: 3.015, unit: 'kg', unitPrice: 29.5)]),
    );
    await env.drain();
    final l = (await env.draft(jobId)).lines.single;
    expect(llmServer.chatRequests.length, 1, reason: 'only the decision, no translation');
    expect((l['ua_name'] as String).toLowerCase(), 'картопля');
  });

  test('a garbled translation (Greek letters) is dropped: the printed name stays', () async {
    await env.init(llm: llmClient());
    translateAndPick(
      [
        {'n': 1, 'pick': 'new', 'group': 'g1', 'name': '', 'confidence': 0.8},
      ],
      ['саκа сο'],
    );
    final jobId = await env.sendReceipt(receiptOf([rl('HARIBO CHAMMALLOHE', 65.0, grams: 100)]));
    await env.drain();
    final l = (await env.draft(jobId)).lines.single;
    expect(l['ua_name'] as String, isNot(contains('κ')));
    expect((l['ua_name'] as String).toLowerCase(), contains('haribo'));
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
      receiptOf([rl('BANVIT FILETO', 278.81, qty: 0.845, unit: 'kg', unitPrice: 329.95)]),
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
      receiptOf([rl('TADIM ERIK KURUSU', 105.00, grams: 400)]),
    );
    await env.drain();
    var q = (await env.message(jobId, AiMessageKind.question))!;
    var card = QuestionCard.fromJson(jsonDecode(q.contentJson) as Map<String, dynamic>);
    expect(card.questions.single.options, contains('Створити «TADIM ERIK KURUSU» у «Їжа»'));
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
      receiptOf([rl('BANVIT FILETO', 278.85, qty: 0.845, unit: 'kg', unitPrice: 330)]),
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

  test('an unknown pack weight is NOT guessed from the model: the list asks for it', () async {
    await env.init(llm: llmClient());
    final chickenId = await chicken();
    translateAndPick(
      [
        {'n': 1, 'pick': 'c1', 'group': 'none', 'name': '', 'grams': 500, 'confidence': 0.9},
      ],
      ['Курка (філе)'],
    );
    final jobId = await env.sendReceipt(receiptOf([rl('BANVIT FILETO', 165.00)]));
    await env.drain();
    final d = await env.draft(jobId);
    final l = d.lines.single;
    expect(l['category_id'], chickenId);
    expect(l['needs_answer'], isTrue, reason: 'no data on the receipt: ask');
    expect(l['quantity'], isNull, reason: 'no model estimate');
    expect(l['flags'], isNot(contains('weight_guess')));
    expect(await env.message(jobId, AiMessageKind.question), isNotNull);
  });

  Future<List<Map<String, dynamic>>> questionsOf(String jobId) async {
    final m = await env.message(jobId, AiMessageKind.question);
    if (m == null) return const [];
    final j = jsonDecode(m.contentJson) as Map<String, dynamic>;
    return [for (final q in j['questions'] as List) Map<String, dynamic>.from(q as Map)];
  }

  Future<({String dost, String mis})> milk() async => (
    dost: await env.budget.saveCategory(
      CategoryInputLike.leaf('Молоко Dost', 59, env.groupFood, env.tryAcc, env.monoAcc),
    ),
    mis: await env.budget.saveCategory(
      CategoryInputLike.leaf('Молоко Mis', 55, env.groupFood, env.tryAcc, env.monoAcc),
    ),
  );

  test('the model says "new" but the product exists at the paid price: it is reused', () async {
    await env.init(llm: llmClient());
    final m = await milk();
    final before = await env.count('budget_categories');
    translateAndPick(
      [
        {'n': 1, 'pick': 'new', 'group': 'g1', 'name': 'Молоко', 'confidence': 0.9},
      ],
      ['Молоко'],
    );
    final jobId = await env.sendReceipt(
      receiptOf([rl('XYZ TEJ 1L', 59.0, qty: 1, unit: 'kg', unitPrice: 59)]),
    );
    await env.drain();
    final l = (await env.draft(jobId)).lines.single;
    expect(l['category_id'], m.dost, reason: 'Молоко Dost costs 59 on the same accounts');
    expect(l['new_category'], isFalse);
    expect(l['needs_answer'], isFalse);
    expect(await questionsOf(jobId), isEmpty);
    expect(await env.count('budget_categories'), before, reason: 'nothing created');
  });

  test('similar milk at another price is asked, existing first and create last', () async {
    await env.init(llm: llmClient());
    final m = await milk();
    translateAndPick(
      [
        {'n': 1, 'pick': 'new', 'group': 'g1', 'name': 'Молоко', 'confidence': 0.9},
      ],
      ['Молоко'],
    );
    final jobId = await env.sendReceipt(
      receiptOf([rl('XYZ TEJ 1L', 61.5, qty: 1, unit: 'kg', unitPrice: 61.5)]),
    );
    await env.drain();
    final l = (await env.draft(jobId)).lines.single;
    expect(l['new_category'], isFalse, reason: 'nothing is made without a tap');
    expect(l['needs_answer'], isTrue);
    final q = (await questionsOf(jobId)).singleWhere((q) => q['id'] == 'cat:0');
    final options = (q['options'] as List).cast<String>();
    final ids = (q['option_ids'] as List).cast<String>();
    expect(options.take(2), everyElement(contains('Молоко')));
    expect(ids.take(2).toSet(), {m.dost, m.mis});
    expect(options.last, startsWith('Створити'), reason: 'create stays, as the last option');
    expect(ids.last, startsWith('create:'));
    expect(q['recommended'], 0, reason: 'the first existing one is recommended, not create');
    expect(q['text'], contains('схожі'));
  });

  test('every related category is offered (not just three) with price and accounts', () async {
    await env.init(llm: llmClient());
    final ids = <String>[];
    for (final (name, price) in [
      ('Молоко Dost', 59.0),
      ('Молоко Mis', 55.0),
      ('Молоко Sutas', 52.0),
      ('Молоко Pinar', 57.0),
      ('Молоко Torku', 49.0),
    ]) {
      ids.add(
        await env.budget.saveCategory(
          CategoryInputLike.leaf(name, price, env.groupFood, env.tryAcc, env.monoAcc),
        ),
      );
    }
    translateAndPick(
      [
        {'n': 1, 'pick': 'new', 'group': 'g1', 'name': 'Молоко', 'confidence': 0.9},
      ],
      ['Молоко'],
    );
    final jobId = await env.sendReceipt(
      receiptOf([rl('XYZ TEJ 1L', 61.5, qty: 1, unit: 'kg', unitPrice: 61.5)]),
    );
    await env.drain();
    final l = (await env.draft(jobId)).lines.single;
    final cands = (l['candidates'] as List).cast<Map>();
    expect(cands.map((c) => c['id']).toSet(), ids.toSet(), reason: 'all five, none cut off');
    expect(cands.first['count_acc'], isNotNull);
    expect(cands.first['price'], isNotNull);
    final q = (await questionsOf(jobId)).singleWhere((q) => q['id'] == 'cat:0');
    expect((q['options'] as List).length, 6, reason: 'five categories and Create');
  });

  test('no similar category at all: the model\'s new category is offered as before', () async {
    await env.init(llm: llmClient());
    await milk();
    translateAndPick(
      [
        {'n': 1, 'pick': 'new', 'group': 'g1', 'name': 'Чорнослив', 'confidence': 0.9},
      ],
      ['Чорнослив'],
    );
    final jobId = await env.sendReceipt(
      receiptOf([rl('XYZ ERIK 1L', 65.0, qty: 1, unit: 'kg', unitPrice: 65)]),
    );
    await env.drain();
    final l = (await env.draft(jobId)).lines.single;
    expect(l['new_category'], isTrue);
    expect(l['needs_answer'], isFalse);
  });

  test('a model that answers a list it was not given cannot overwrite the glossary names', () async {
    await env.init(llm: llmClient());
    // Only the second name is unknown to the glossary. The model answers for 1 AND 2
    // (it repeats its own word list): the whole reply is dropped.
    llmServer.enqueueJson({
      'items': [
        {'n': 1, 'ua': 'молоко'},
        {'n': 2, 'ua': 'лаваш'},
      ],
    });
    llmServer.enqueueJson({
      'items': [
        {'n': 1, 'pick': 'new', 'group': 'g1', 'name': '', 'confidence': 0.8},
        {'n': 2, 'pick': 'new', 'group': 'g1', 'name': '', 'confidence': 0.8},
      ],
    });
    final jobId = await env.sendReceipt(
      receiptOf([
        rl('PATATES', 88.94, qty: 3.015, unit: 'kg', unitPrice: 29.5),
        rl('XYZ TEJ 1L', 59.0, qty: 1, unit: 'kg', unitPrice: 59),
      ]),
    );
    await env.drain();
    final lines = (await env.draft(jobId)).lines;
    expect((lines[0]['ua_name'] as String).toLowerCase(), 'картопля');
    expect((lines[1]['ua_name'] as String).toLowerCase(), isNot('лаваш'));
  });

  /// The BIM receipt against a budget shaped like the real one: the receipt is
  /// Turkish, the categories Ukrainian, the model useless. The names and the
  /// existing categories must come from the code (glossary + resolver), and a model
  /// that answers badly must not take them away.
  Future<void> bimWithBadModel(
    void Function() modelReplies, {
    required bool down,
    required bool failed,
  }) async {
    await env.init(llm: llmClient());
    final seed = Seed(env.db);
    Future<String> leaf(String n, double p, {String? parent}) => seed.leaf(
      n,
      price: p,
      parentId: parent ?? env.groupFood,
      count: env.tryAcc,
      use: env.monoAcc,
    );
    final potato = await leaf('🥔 Картопля', 29.5);
    final cucumbers = await seed.group('🥒 Огірки', parentId: env.groupFood);
    await leaf('🥒 Огірки', 25, parent: cucumbers);
    await leaf('🥒 Огірки', 39, parent: cucumbers);
    await leaf('🍞 Хліб цільнозерновий', 130);
    final dost = await seed.group('🥛 Молоко Dost', parentId: env.groupFood);
    await leaf('🥛 Молоко Dost', 55, parent: dost);
    final dost59 = await leaf('🥛 Молоко Dost', 59, parent: dost);
    modelReplies();

    final jobId = await env.sendReceipt(
      receiptOf([
        rl('PATATES', 88.94, qty: 3.015, unit: 'kg', unitPrice: 29.5),
        rl('SALATALIK', 47.78, qty: 0.975, unit: 'kg', unitPrice: 49.0),
        rl('TAMBUGDAYEKMK5O0G', 65.0, grams: 500),
        rl('LiMON', 30.62, qty: 0.785, unit: 'kg', unitPrice: 39.0),
        rl('GUNLUK SUT 1L DOST', 59.0, qty: 1, unit: 'kg', unitPrice: 59),
      ]),
    );
    await env.drain();
    final d = await env.draft(jobId);
    final lines = d.lines;
    String ua(int i) => (lines[i]['ua_name'] as String? ?? '').toLowerCase();
    expect(ua(0), 'картопля');
    expect(ua(1), 'огірки');
    expect(ua(3), 'лимон');

    expect(lines[0]['category_id'], potato, reason: 'Картопля costs 29.5: reused');
    expect(lines[0]['needs_answer'], isFalse);
    expect(lines[1]['category_name'], contains('Огірки'), reason: 'found, not asked');
    expect(lines[1]['needs_answer'], isFalse);
    expect(lines[2]['category_name'], contains('цільнозерновий'));
    expect(lines[2]['needs_answer'], isFalse);
    expect(lines[4]['category_id'], dost59, reason: 'Молоко Dost 59 from the brand word');
    expect(lines[4]['needs_answer'], isFalse);
    // No lemon category exists: the one question, with the create option.
    expect(lines[3]['needs_answer'], isTrue);
    final qs = await questionsOf(jobId);
    final q = qs.singleWhere((q) => q['id'] == 'cat:3');
    expect((q['options'] as List).last, startsWith('Створити'));

    final ov = jsonDecode(jsonEncode(d.json['overrides'])) as Map<String, dynamic>;
    expect(ov['suggest_failed'] == true, down, reason: 'only a dead server gives the stage up');
    expect(ov['suggest_error'] != null, failed, reason: 'a failed call keeps its reason in the card');
  }

  test('BIM, model server answers HTTP 500: names and existing categories still come', () async {
    await bimWithBadModel(
      () => llmServer.enqueue(const MockReply.status(500)),
      down: true,
      failed: true,
    );
  });

  test('BIM, model answers prose with no JSON: nothing is lost, the reason is kept', () async {
    await bimWithBadModel(
      () {
        llmServer.enqueueContent('Sorry, I cannot help with that.');
        llmServer.enqueueContent('Still no JSON, sorry.');
      },
      down: false,
      failed: true,
    );
  });

  test('BIM, model answers for lines nobody asked about: ignored', () async {
    await bimWithBadModel(
      () => llmServer.enqueueJson({
        'items': [
          {'n': 9, 'pick': 'new', 'group': 'g1', 'name': 'Лаваш', 'confidence': 0.99},
        ],
      }),
      down: false,
      failed: false,
    );
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
