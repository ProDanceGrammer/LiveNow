// Bug 2026-11-19: four Monobank screenshots and a message that tells what each
// one was. The OCR texts are invented look-alikes of real dumps (see
// ai_bank_screens_test.dart).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/ids.dart';
import 'package:livenow/data/ai/llm_client.dart';
import 'package:livenow/data/ai/ocr_client.dart';
import 'package:livenow/domain/ai/ai_batch_service.dart';
import 'package:livenow/domain/ai/ai_protocol.dart';
import 'package:livenow/domain/budget_rules.dart' show BudgetUnit;
import 'package:livenow/domain/postpone_rules.dart';

import '../../data/ai/mock_llm_server.dart';
import 'ai_job_runner_test.dart' show e1Lines;
import 'ai_runner_support.dart';
import 'ai_test_support.dart' show Seed;

List<String> _rows(String text) => text.split('\n');

final _gift = _rows(
  '16:091\nneTpo P.\nepeka3 Ha kapTky\n18nmconaqa2026,22:23\n-3 491.00 ∞\n'
  'KoMeHT\nOncTa#TerW\n3aBaHTaKWTWpan\n3anMok\n2 150.30 会\n'
  'BuTpaTWnw177153aniBpoky\n7482号\n3 741 \ndah  cep  Bep  KOB',
);
final _mom = _rows(
  '16:091\nnaBno K.\nepeka3 Ha kapTky\n18nmcToaqa2026,22:22\n-3 071.00 \n'
  'HoBe KoMeHT\nOncTa#TerW\n3aBaHTaKWTWpan\n3anMok\n4 180.20 会\n'
  'BuTpaTWnw177153aniBpoky\n7482号\n3 741 \ndah  cep  Bep  KOB',
);
final _topUp = _rows(
  '16:091\n3 rpMBHeBoro paxyHKy XYZ\nOnOBHeHHA KapTKW\n18ncTonaqa2026,22:19\n'
  '9 026.87 会\nOnncTa#TerW\n3aBaHTaKWTwpann\n3anMWok\n7701.20号\n'
  'BinkpMTW eno3WT\nocTaBWTW 3anMTaHHy',
);
// A lira payment with its rate: a screenshot that was understood before.
final _transport = ['Sunset Cafe', '18 листопада 2026, 21:10', 'Сума 45,17 ₴', 'У валюті 50,00 TL', 'курс 0,9034'];

const _message = '9026 грн із Фоп на монобанг гривневу карту. 3071 подарунок мамі. '
    '3491 кафе і ресторани.';

void main() {
  late RunnerEnv env;
  late MockLlmServer llmServer;
  late MockOcrServer ocrServer;

  setUpAll(() {
    HttpOverrides.global = null;
    initPostponeTimeZoneData();
  });
  setUp(() async {
    env = RunnerEnv();
    llmServer = await MockLlmServer.start();
    ocrServer = await MockOcrServer.start();
  });
  tearDown(() async {
    await env.close();
    await llmServer.close();
    await ocrServer.close();
  });

  LlmClient llmClient() => LlmClient(
    baseUrl: llmServer.url,
    model: 'm',
    requestTimeout: const Duration(seconds: 5),
    maxRetries: 0,
    retryBaseDelay: Duration.zero,
  );

  /// Photos 2/4/6/8 = transport / 3491 / top-up / 3071.
  Object ocrOf(List<int> image) => switch (image.first) {
    2 => ocrReply(_transport),
    4 => ocrReply(_gift),
    6 => ocrReply(_topUp),
    8 => ocrReply(_mom),
    _ => ocrReply(['BIM', 'EKMEK KOY 600G 64,00', 'TOPLAM 391,50 TL']),
  };

  Future<({String cafe, String rest, String parent})> seedCafes() async {
    final seed = Seed(env.db);
    final group = await seed.group('🍽 Кафе та ресторани');
    final cafe = await seed.leaf('Кафе', price: 1, parentId: group, unit: BudgetUnit.piece);
    final rest = await seed.leaf('Ресторани', price: 1, parentId: group, unit: BudgetUnit.piece);
    return (cafe: cafe, rest: rest, parent: group);
  }

  Future<String> sendFour() async {
    await env.rules.set('card.default', {'account_id': env.monoAcc});
    ocrServer.replyFor = ocrOf;
    return env.sendPhotos([2, 4, 6, 8], caption: _message);
  }

  test('four screenshots: each is a job of its own; nothing is read as a paper receipt', () async {
    await env.init(ocr: OcrClient(baseUrl: ocrServer.url));
    final cafes = await seedCafes();
    final parent = await sendFour();
    await env.drain();

    expect((await env.message(parent, AiMessageKind.text))!.body, contains('Знайшов 4 скріншотів'));
    expect(env.extractor.calls, 0, reason: 'no screenshot goes to the receipt reader');
    expect(await env.count('ai_jobs', "kind = 'receipt'"), 0);
    final kid = [for (var i = 0; i < 4; i++) deriveId(parent, 'job', i)];

    // Transport: as before, the shop names it; the lira amount and the rate stay.
    final transport = await env.draft(kid[0]);
    expect(transport.lines.single['name'], 'Sunset Cafe');
    expect(transport.lines.single['amount'], 50.0);
    expect(transport.json['currency'], 'TRY');

    // 3491: "кафе і ресторани" is a group: asked inside it; hryvnia, its own day.
    final cafe = await env.draft(kid[1]);
    expect(cafe.lines.single['name'], 'кафе і ресторани');
    expect(cafe.lines.single['amount'], 3491.0);
    expect(cafe.json['currency'], 'UAH');
    expect(cafe.json['at'], startsWith('2026-11-18T19:23'), reason: 'the screenshot day, not an action\'s');
    final q = jsonDecode((await env.message(kid[1], AiMessageKind.question))!.contentJson)['questions'] as List;
    expect((q.single as Map)['option_ids'], [cafes.cafe, cafes.rest, 'create:${cafes.parent}']);

    // 3071: a gift for mom, in hryvnia.
    final gift = await env.draft(kid[3]);
    expect(gift.lines.single['name'], 'подарунок мамі');
    expect(gift.lines.single['amount'], 3071.0);
    expect(gift.json['currency'], 'UAH');
    expect(gift.json['at'], startsWith('2026-11-18T19:22'));
    expect(gift.json['at'], isNot(startsWith('2026-10')));
    expect(gift.notes.join(' '), isNot(contains('Час чека не прочитано')));
    for (final k in [kid[1], kid[3]]) {
      expect((await env.draft(k)).json['source']['payment'], isTrue);
    }
  });

  test('the top-up is written at once as a transfer: amount and day of the screenshot, Undo', () async {
    await env.init(ocr: OcrClient(baseUrl: ocrServer.url));
    final parent = await sendFour();
    await env.drain();

    final job = deriveId(parent, 'job', 2);
    expect((await env.job(job)).state, AiJobState.done, reason: (await env.job(job)).error);
    final txs = await env.transactions();
    expect(txs, hasLength(2), reason: 'the other three are drafts waiting for Confirm');
    expect(txs.map((t) => t.isIncome).toSet(), {true, false});
    expect(txs.map((t) => t.quantity).toSet(), {9026.87}, reason: 'the screenshot sum, not the message\'s 9026');
    expect(txs.map((t) => t.id).toSet(), {deriveId(job, 'transfer-out'), deriveId(job, 'transfer-in')});
    for (final t in txs) {
      expect(t.occurredAt, startsWith('2026-11-18T19:19'), reason: '22:19 local, the screenshot day');
    }
    final out = txs.firstWhere((t) => !t.isIncome);
    final inc = txs.firstWhere((t) => t.isIncome);
    expect(out.accountUseId, env.fopAcc);
    expect(inc.accountUseId, env.monoAcc);
    final batch = (await env.db.select(env.db.aiBatchesTable).get()).single;
    final undo = await AiBatchService(env.db).undoBatch(batch.id);
    expect(undo.transactions, 2);
    expect(await env.count('budget_transactions'), 0);
  });

  test('without a message the top-up is an income draft, not a transfer', () async {
    await env.init(ocr: OcrClient(baseUrl: ocrServer.url));
    ocrServer.replyFor = ocrOf;
    final job = await env.sendPhotos([6]);
    await env.drain();
    expect((await env.job(job)).state, anyOf(AiJobState.draftReady, AiJobState.needsInput));
    final d = await env.draft(job);
    expect(d.lines.single['amount'], 9026.87);
    expect(d.json['currency'], 'UAH');
    expect(d.json['source']['income'], isTrue);
    expect(await env.count('budget_transactions'), 0);
  });

  test('a receipt and an unrelated screenshot: the screenshot is not lost', () async {
    await env.init(ocr: OcrClient(baseUrl: ocrServer.url));
    ocrServer.replyFor = ocrOf;
    env.extractor.receipt = receiptOf(e1Lines());
    final parent = await env.sendPhotos([1, 4]);
    await env.drain();
    expect((await env.message(parent, AiMessageKind.text))!.body, contains('1 чеків і 1 скріншотів'));
    expect(await env.count('ai_jobs', "kind = 'receipt'"), 1);
    expect(await env.count('ai_jobs', "kind = 'screenshot'"), 1);
    final shot = deriveId(parent, 'job', 1);
    expect((await env.draft(shot)).lines.single['amount'], 3491.0);
    final receipt = await env.draft(deriveId(parent, 'job', 0));
    expect(receipt.json['fx_source'], isNot('screenshot'), reason: 'the hryvnia screen is no rate of the receipt');
  });

  test('a receipt keeps the screenshot that shows its total', () async {
    await env.init(ocr: OcrClient(baseUrl: ocrServer.url));
    ocrServer.replyFor = (image) => image.first == 2
        ? ocrReply(['Сума 361,64 ₴', 'У валюті 391,50 TL', 'курс 0,9237'])
        : ocrOf(image);
    env.extractor.receipt = receiptOf(e1Lines());
    final parent = await env.sendPhotos([1, 2, 4]);
    await env.drain();
    expect(await env.count('ai_jobs', "kind = 'receipt'"), 1);
    expect(await env.count('ai_jobs', "kind = 'screenshot'"), 1, reason: 'only the 3491 one stands alone');
    expect((await env.draft(deriveId(parent, 'job', 0))).json['fx_source'], 'screenshot');
  });

  group('Ukrainian second reading of a bank screenshot', () {
    // What the default (Latin) recogniser keeps of a Cyrillic screen: the amount line only.
    final lost = ['16:09', '-3 491.00', '18 2026, 22:23'];
    // What the Ukrainian recogniser reads (invented names and sums).
    final cyrillic = _rows(
      '16:09\nПетро Р.\nПереказ на картку\n18 листопада 2026, 22:23\n-3 491.00 ₴\n'
      'Коментар\nОпис та #теги\nЗалишок\n12 150.30 ₴',
    );

    test('a bank screen is read again once with lang uk, and that reading is used', () async {
      ocrServer.healthLangs = ['default', 'uk'];
      ocrServer.replyForLang = (_, lang) => ocrReply(lang == 'uk' ? cyrillic : lost);
      await env.init(ocr: OcrClient(baseUrl: ocrServer.url));
      final job = await env.sendPhotos([4]);
      await env.drain();
      expect(ocrServer.callsWithLang('uk'), greaterThan(0));
      expect(ocrServer.callsWithLang('uk'), ocrServer.callsWithLang(null),
          reason: 'every default reading of a bank screen gets exactly one Ukrainian pass');
      expect(ocrServer.requests.where((r) => r.lang != null && r.lang != 'uk'), isEmpty);
      final d = await env.draft(job);
      expect(d.lines.single['amount'], 3491.0);
      expect(d.json['at'], startsWith('2026-11-18T19:23'), reason: 'the date only the Ukrainian reading has');
    });

    test('a receipt is never read again', () async {
      ocrServer.healthLangs = ['default', 'uk'];
      ocrServer.replyForLang = (_, lang) => ocrReply(['BIM', 'EKMEK KOY 600G 64,00', 'TOPLAM 391,50 TL']);
      env.extractor.receipt = receiptOf(e1Lines());
      await env.init(ocr: OcrClient(baseUrl: ocrServer.url));
      await env.sendPhotos([1]);
      await env.drain();
      expect(ocrServer.callsWithLang(null), greaterThan(0));
      expect(ocrServer.callsWithLang('uk'), 0);
    });

    test('a worse Ukrainian reading is discarded', () async {
      ocrServer.healthLangs = ['default', 'uk'];
      // The first reading has amount AND date; the Ukrainian one only an amount.
      ocrServer.replyForLang = (_, lang) =>
          ocrReply(lang == 'uk' ? ['-3 491.00 ₴'] : _gift);
      await env.init(ocr: OcrClient(baseUrl: ocrServer.url));
      final job = await env.sendPhotos([4]);
      await env.drain();
      expect(ocrServer.callsWithLang('uk'), greaterThan(0));
      final d = await env.draft(job);
      expect(d.lines.single['amount'], 3491.0);
      expect(d.json['at'], startsWith('2026-11-18T19:23'), reason: 'the first reading, with its date, was kept');
    });

    test('no lang uk when the service does not offer it', () async {
      ocrServer.healthLangs = null; // an older service: no "langs" field
      ocrServer.replyForLang = (_, lang) => ocrReply(_gift);
      await env.init(ocr: OcrClient(baseUrl: ocrServer.url));
      final job = await env.sendPhotos([4]);
      await env.drain();
      expect(ocrServer.callsWithLang(null), greaterThan(0));
      expect(ocrServer.callsWithLang('uk'), 0);
      expect((await env.draft(job)).lines.single['amount'], 3491.0);
    });
  });

  group('the model as a fallback', () {
    const typed = 'перевів 100 з Невідомий на Monobank';

    Future<List<int>> indexes() async {
      final all = await env.db.select(env.db.budgetAccountsTable).get();
      return [
        all.indexWhere((a) => a.id == env.fopAcc) + 1,
        all.indexWhere((a) => a.id == env.monoAcc) + 1,
      ];
    }

    test('an unresolved account asks the model once and uses its valid pick', () async {
      await env.init(llm: llmClient());
      final i = await indexes();
      llmServer.enqueueJson({'from': i[0], 'to': i[1]});
      final sent = await env.chat.sendText(env.thread, typed);
      await env.drain();
      expect(llmServer.chatRequests, hasLength(1));
      expect(utf8.decode(llmServer.chatRequests.single.body), contains('account_pick'));
      final txs = await env.transactions();
      expect(txs, hasLength(2));
      expect(txs.firstWhere((t) => !t.isIncome).accountUseId, env.fopAcc);
      expect((await env.job(sent.jobId!)).state, AiJobState.done);
    });

    test('an invalid pick is not believed: the reply lists the accounts', () async {
      await env.init(llm: llmClient());
      llmServer.enqueueJson({'from': 99, 'to': (await indexes())[1]});
      final sent = await env.chat.sendText(env.thread, typed);
      await env.drain();
      expect(llmServer.chatRequests, hasLength(1));
      expect(await env.count('budget_transactions'), 0);
      final body = (await env.message(sent.jobId!, AiMessageKind.text))!.body;
      expect(body, contains('Невідомий'));
      expect(body, contains('Рахунки:'));
    });

    test('typed text without a verb is a transfer when both names are accounts', () async {
      await env.init();
      final sent = await env.chat.sendText(env.thread, '9026 грн із Фоп на монобанг гривневу карту');
      await env.drain();
      expect((await env.job(sent.jobId!)).state, AiJobState.done);
      final txs = await env.transactions();
      expect(txs, hasLength(2));
      expect(txs.map((t) => t.quantity).toSet(), {9026.0});
    });

    test('"кава з молоком на винос" is never a transfer, and the model is not asked', () async {
      await env.init(llm: llmClient());
      final sent = await env.chat.sendText(env.thread, 'кава з молоком на винос');
      await env.drain();
      expect(await env.count('budget_transactions'), 0);
      expect(utf8.decode(llmServer.requests.expand((r) => r.body).toList(), allowMalformed: true),
          isNot(contains('account_pick')));
      expect((await env.job(sent.jobId!)).state, isNot(AiJobState.failed));
    });

    test('message parts the rules cannot place go to the model once, validated', () async {
      await env.init(ocr: OcrClient(baseUrl: ocrServer.url), llm: llmClient());
      await env.rules.set('card.default', {'account_id': env.monoAcc});
      ocrServer.replyFor = ocrOf;
      // "обід" has no amount and "кава 9" fits no sum: both are left over; the
      // model pairs the shots (open: 1 = 3491, 2 = 3071) with the parts.
      llmServer.enqueueJson({
        'pairs': [
          {'shot': 1, 'part': 1},
          {'shot': 2, 'part': 2},
          {'shot': 2, 'part': 1}, // the screenshot already has a part: ignored
          {'shot': 5, 'part': 1}, // out of range: ignored
        ],
      });
      llmServer.enqueueJson({'items': <Object>[]});
      llmServer.enqueueJson({'items': <Object>[]});
      final parent = await env.sendPhotos([4, 8], caption: 'кава 9; обід 8');
      await env.drain();
      expect(llmServer.chatRequests.first.json.toString(), contains('message_shots'));
      expect((await env.draft(deriveId(parent, 'job', 0))).lines.single['name'], 'кава');
      expect((await env.draft(deriveId(parent, 'job', 1))).lines.single['name'], 'обід');
    });
  });
}
