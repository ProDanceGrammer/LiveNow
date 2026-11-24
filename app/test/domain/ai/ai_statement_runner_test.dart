// A bank statement file in the chat, end to end (hub runner): questions, ONE
// summary, ONE Confirm, ONE batch Undo. Every name and amount is invented.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/ids.dart';
import 'package:livenow/data/database.dart' show AiBatchItemsTableCompanion;
import 'package:livenow/domain/ai/action_matcher.dart' show receiptLocalToUtc;
import 'package:livenow/domain/ai/ai_batch_service.dart';
import 'package:livenow/domain/ai/ai_protocol.dart';
import 'package:livenow/domain/budget_rules.dart' show BudgetUnit;
import 'package:livenow/domain/postpone_rules.dart';

import 'ai_runner_support.dart';
import 'ai_test_support.dart' show Seed;

const _header =
    'Дата i час операції;Деталі операції;MCC;Сума в валюті картки (UAH);Сума в валюті операції;'
    'Валюта;Курс;Сума комісій (UAH);Сума кешбеку (UAH);Залишок після операції';

const _topUp = '20.11.2026 10:00:00;З гривневого рахунку ФОП;4829;9000.00;9000.00;UAH;—;—;—;9000.00';
const _jar = '20.11.2026 11:00:00;Поповнення «Готівка TRY»;4829;-1000.00;-1000.00;UAH;—;—;—;8000.00';
const _undoneIn = '21.11.2026 09:00:10;Скасування. Тест Магазин;5411;250.00;250.00;UAH;—;—;—;8250.00';
const _undoneOut = '21.11.2026 09:00:00;Тест Магазин;5411;-250.00;-250.00;UAH;—;—;—;8000.00';
const _cafe = '21.11.2026 12:00:00;Sunset Cafe;5812;-45.17;-50.00;TRY;0.9034;—;—;7954.83';
const _shop = '22.11.2026 18:00:00;Сільпо 123;5411;-300.00;-300.00;UAH;—;—;—;7654.83';
const _person = '22.11.2026 19:00:00;Олег К.;4829;-700.00;-700.00;UAH;—;—;—;6954.83';
const _kiosk = '23.11.2026 10:00:00;Кіоск Тест;5499;-120.00;-120.00;UAH;—;—;—;6834.83';
const _october = '10.10.2026 10:00:00;Старий Магазин;5499;-80.00;-80.00;UAH;—;—;—;100.00';

String _csv(List<String> rows) => [_header, ...rows].join('\n');

const _all = [_topUp, _jar, _undoneIn, _undoneOut, _cafe, _shop, _person, _kiosk];

void main() {
  late RunnerEnv env;
  late String market;
  late String cafeCat;
  late String rent;

  setUpAll(() {
    HttpOverrides.global = null;
    initPostponeTimeZoneData();
  });
  setUp(() async {
    env = RunnerEnv();
    await env.init();
    final seed = Seed(env.db);
    final products = await seed.group('Продукти');
    market = await seed.leaf('Супермаркет', price: 1, parentId: products, unit: BudgetUnit.piece);
    await seed.leaf('Овочі', price: 1, parentId: products, unit: BudgetUnit.piece);
    cafeCat = await seed.leaf('Кафе', price: 1, unit: BudgetUnit.piece);
    rent = await seed.leaf('Оренда', price: 1, unit: BudgetUnit.piece);
    await env.aliases.remember('Sunset Cafe', categoryId: cafeCat);
    // Already recorded (for example from a screenshot): the kiosk row.
    await env.budget.createTransaction(
      categoryId: cafeCat,
      name: 'Кіоск Тест',
      date: receiptLocalToUtc('2026-11-23T10:00:00'),
      quantity: 1,
      unitPrice: 120,
    );
  });
  tearDown(() => env.close());

  Future<String> send(List<String> rows, {String caption = '', String? text}) async {
    final sent = await env.chat.sendStatement(
      env.thread,
      fileName: 'report.csv',
      bytes: Uint8List.fromList(utf8.encode(text ?? _csv(rows))),
      caption: caption,
    );
    return sent.jobId!;
  }

  /// Unanswered questions of the job: (message id, question).
  Future<List<({String message, Map<String, dynamic> q})>> open(String job) async {
    final out = <({String message, Map<String, dynamic> q})>[];
    for (final m in await env.messages(job, AiMessageKind.question)) {
      for (final q in (jsonDecode(m.contentJson)['questions'] as List)) {
        final map = Map<String, dynamic>.from(q as Map);
        if (map['answer'] == null) out.add((message: m.id, q: map));
      }
    }
    return out;
  }

  Future<void> answer(String job, String idPrefix, String text, {String? optionId}) async {
    final q = (await open(job)).firstWhere((e) => (e.q['id'] as String).startsWith(idPrefix));
    await env.chat.answerQuestion(q.message, q.q['id'] as String, text, optionId: optionId);
    await env.drain();
  }

  Future<Map<String, dynamic>> content(String job) async =>
      jsonDecode((await env.message(job, AiMessageKind.draft))!.contentJson) as Map<String, dynamic>;

  /// Account question, merchant group question and the person: answered.
  Future<String> firstRun() async {
    final job = await send(_all);
    await env.drain();
    expect((await env.job(job)).state, AiJobState.needsInput);
    final first = await open(job);
    expect(first.map((e) => e.q['id']), ['acct'], reason: 'nothing else before the account is known');
    expect((first.single.q['options'] as List).first, startsWith('Monobank'), reason: 'card-currency accounts first');
    await answer(job, 'acct', 'Monobank', optionId: env.monoAcc);
    return job;
  }

  test('questions: account first, then a group question for the MCC hint and the person', () async {
    final job = await firstRun();
    expect((await env.job(job)).state, AiJobState.needsInput);
    final qs = await open(job);
    final ids = qs.map((e) => e.q['id'] as String).toList();
    expect(ids.where((i) => i.startsWith('g:')), hasLength(1), reason: 'MCC 5411 -> group "Продукти": asked inside it');
    expect(ids.where((i) => i.startsWith('p:')), hasLength(1));
    expect(ids.where((i) => i.startsWith('m:')), isEmpty, reason: 'the cafe has a learned alias');
    final g = qs.firstWhere((e) => (e.q['id'] as String).startsWith('g:')).q;
    expect(g['text'], contains('Продукти'));
    expect(g['option_ids'], contains(market));
    final p = qs.firstWhere((e) => (e.q['id'] as String).startsWith('p:')).q;
    expect(p['option_ids'], contains('acct:${env.fopAcc}'), reason: 'my own account is offered');
    expect(p['option_ids'], isNot(contains('keep')), reason: 'nothing remembered yet');
    // The draft so far has no Confirm to press: it asks.
    expect((await content(job))['stage'], 'asking');
  });

  test('answers -> ONE summary; Confirm writes everything with fixed ids; Undo reverts all', () async {
    final job = await firstRun();
    await answer(job, 'g:', 'Супермаркет', optionId: market);
    await answer(job, 'p:', 'Оренда', optionId: rent);
    expect((await env.job(job)).state, AiJobState.draftReady, reason: (await env.job(job)).error);
    final c = await content(job);
    expect(c['stage'], 'ready');
    expect(c['type'], 'statement');
    expect(c['account_name'], 'Monobank');
    final groups = (c['groups'] as List).cast<Map>();
    final kinds = groups.map((g) => g['kind']).toList();
    expect(kinds.where((k) => k == 'purchase'), hasLength(3)); // cafe, market, rent
    expect(kinds.where((k) => k == 'transfer'), hasLength(2));
    expect((c['cancelled'] as List), hasLength(2), reason: 'the reversal pair');
    final dup = (c['skipped_duplicates'] as List).cast<Map>();
    expect(dup.map((d) => d['details']), ['Кіоск Тест']);
    final cafeGroup = groups.firstWhere((g) => g['category_id'] == cafeCat);
    expect((cafeGroup['totals'] as Map)['TRY'], 50.0, reason: 'the TRY purchase stays in lira');
    final row = (cafeGroup['rows'] as List).single as Map;
    expect(row['rate_count'], 50.0);
    expect(row['rate_interact'], 45.17);
    expect(await env.count('budget_transactions'), 1, reason: 'only the seeded kiosk one: nothing written before Confirm');

    await env.confirm(job);
    expect((await env.job(job)).state, AiJobState.done, reason: (await env.job(job)).error);
    final txs = await env.transactions();
    expect(txs, hasLength(1 + 3 + 4), reason: 'kiosk + cafe, market, rent + two transfers of two legs');
    final cafeTx = txs.firstWhere((t) => t.id == deriveId(job, 'stmt', 5));
    expect(cafeTx.categoryId, cafeCat);
    expect(cafeTx.unitPrice, 50.0);
    expect(cafeTx.quantity, 1.0);
    expect(cafeTx.rateCount, 50.0);
    expect(cafeTx.rateInteract, 45.17);
    expect(cafeTx.occurredAt, startsWith('2026-11-21T09:00'), reason: '12:00 in the app zone (Istanbul), as UTC');
    final ids = txs.map((t) => t.id).toSet();
    expect(ids, containsAll([deriveId(job, 'transfer-in', 1), deriveId(job, 'transfer-out', 1)]));
    expect(ids, containsAll([deriveId(job, 'transfer-in', 2), deriveId(job, 'transfer-out', 2)]));
    // The cross-currency jar: hryvnia out, lira in by the accounts' rates.
    final lira = txs.firstWhere((t) => t.id == deriveId(job, 'transfer-in', 2));
    expect(lira.quantity, closeTo(818.18, 0.01));

    // What was learned.
    expect((await env.rules.get('stmt.account.${(await content(job))['state']['signature']}'))?['account_id'], env.monoAcc);
    expect(
      (await env.rules.withPrefix('stmt.party.')).values.single['category_id'],
      rent,
    );
    expect((await env.aliases.lookup('сільпо 123')), isNull, reason: 'a pick inside a group is not learned');

    // Same job again (a crash while writing): nothing new.
    await env.db.customStatement("UPDATE ai_jobs SET state = 'committing' WHERE id = '$job'");
    await env.drain();
    expect(await env.count('budget_transactions'), 8);
    expect((await env.job(job)).state, AiJobState.done);

    // ONE Undo takes it all back.
    final batch = (await env.db.select(env.db.aiBatchesTable).get()).single;
    final undo = await AiBatchService(env.db).undoBatch(batch.id);
    expect(undo.transactions, 7);
    expect(await env.count('budget_transactions'), 1, reason: 'the seeded kiosk transaction stays');
  });

  test('a file sent again is all "already recorded": nothing new is written', () async {
    final job = await firstRun();
    await answer(job, 'g:', 'Супермаркет', optionId: market);
    await answer(job, 'p:', 'Оренда', optionId: rent);
    await env.confirm(job);
    final before = await env.count('budget_transactions');
    final again = await send(_all);
    await env.drain();
    // The account is remembered, every real row is found: no question, no Confirm.
    expect(await open(again), isEmpty);
    expect((await env.job(again)).state, AiJobState.done);
    final c = await content(again);
    expect((c['skipped_duplicates'] as List).length, 6, reason: 'every real row is already recorded');
    expect((c['cancelled'] as List).length, 2);
    expect((c['groups'] as List), isEmpty);
    expect((await env.message(again, AiMessageKind.text))!.body, contains('уже записано 6'));
    expect(await env.count('budget_transactions'), before);
  });

  test('the same person in a later statement: "same as last time?" and the remembered category', () async {
    final job = await firstRun();
    await answer(job, 'g:', 'Супермаркет', optionId: market);
    await answer(job, 'p:', 'Оренда', optionId: rent);
    await env.confirm(job);

    final later = await send(['24.11.2026 09:00:00;Олег К.;4829;-710.00;-710.00;UAH;—;—;—;5000.00']);
    await env.drain();
    final qs = await open(later);
    expect(qs.map((e) => (e.q['id'] as String)[0]), ['p']);
    final p = qs.single.q;
    expect(p['option_ids'], contains('keep'), reason: '"same as last time?"');
    expect(p['text'], contains('Минулого разу'));
    expect(p['text'], contains('Оренда'));
    await answer(later, 'p:', 'так', optionId: 'keep');
    final c = await content(later);
    expect((c['groups'] as List).single['category_id'], rent);
    await env.confirm(later);
    expect((await env.transactions()).where((t) => t.categoryId == rent), hasLength(2));
  });

  test('a person can be answered with a transfer to my own account', () async {
    final job = await firstRun();
    await answer(job, 'g:', 'Супермаркет', optionId: market);
    await answer(job, 'p:', 'ФОП', optionId: 'acct:${env.fopAcc}');
    final groups = ((await content(job))['groups'] as List).cast<Map>();
    expect(groups.where((g) => g['kind'] == 'transfer'), hasLength(3));
    await env.confirm(job);
    expect((await env.rules.withPrefix('stmt.party.')).values.single['account_id'], env.fopAcc);
  });

  test('a typed answer that matches nothing is asked again, saying so', () async {
    final job = await firstRun();
    await answer(job, 'p:', 'щось зовсім невідоме');
    final p = (await open(job)).firstWhere((e) => (e.q['id'] as String).startsWith('p:')).q;
    expect(p['text'], contains('Не знайшов «щось зовсім невідоме»'));
  });

  test('columns that cannot be read: the reply lists the headers found and what is missing', () async {
    final job = await send(const [], text: 'колір;розмір;вага\nчервоний;L;3');
    await env.drain();
    expect((await env.job(job)).state, AiJobState.done);
    final reply = (await env.message(job, AiMessageKind.text))!.body;
    expect(reply, contains('колір | розмір | вага'));
    expect(reply, contains('Не знайдено'));
    expect(await env.count('budget_transactions'), 1);
  });

  test('"за листопад" keeps November rows only', () async {
    final job = await send([_october, _shop, _kiosk], caption: 'за листопад');
    await env.drain();
    await answer(job, 'acct', 'Monobank', optionId: env.monoAcc);
    final state = (await content(job))['state'] as Map;
    expect(state['rows'], hasLength(2));
  });

  const ride1 = '24.11.2026 08:00:00;Міський транспорт;4131;-45.17;-50.00;TRY;0.9034;—;—;900.00';
  const ride2 = '24.11.2026 08:01:00;Міський транспорт;4131;-45.17;-50.00;TRY;0.9034;—;—;854.83';
  const ride3 = '24.11.2026 18:00:00;Міський транспорт;4131;-45.17;-50.00;TRY;0.9034;—;—;809.66';

  test('one recorded transaction answers ONE row: two of three equal rides are left', () async {
    await env.budget.createTransaction(
      categoryId: cafeCat,
      name: 'Проїзд',
      date: receiptLocalToUtc('2026-11-24T08:02:00'),
      quantity: 1,
      unitPrice: 50,
    );
    final job = await send([ride1, ride2, ride3]);
    await env.drain();
    await answer(job, 'acct', 'Monobank', optionId: env.monoAcc);
    expect((await content(job))['skipped_duplicates'], hasLength(1));
  });

  test('a recorded receipt (an AI batch of lines) counts as its sum', () async {
    final now = DateTime.now().toUtc().toIso8601String();
    final at = receiptLocalToUtc('2026-11-24T08:00:00');
    for (final (i, price) in [30.0, 20.0].indexed) {
      final tx = await env.budget.createTransaction(
        categoryId: cafeCat,
        name: 'line $i',
        date: at,
        quantity: 1,
        unitPrice: price,
      );
      await env.db.into(env.db.aiBatchItemsTable).insert(
            AiBatchItemsTableCompanion.insert(
              id: newId(),
              batchId: 'batch-receipt',
              entityType: AiEntity.transaction,
              entityId: tx,
              createdAt: now,
              updatedAt: now,
            ),
          );
    }
    final job = await send([ride1]);
    await env.drain();
    await answer(job, 'acct', 'Monobank', optionId: env.monoAcc);
    expect((await content(job))['skipped_duplicates'], hasLength(1));
  });
}
