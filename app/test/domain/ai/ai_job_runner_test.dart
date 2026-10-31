import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/ids.dart';
import 'package:livenow/data/ai/llm_client.dart';
import 'package:livenow/data/ai/ocr_client.dart';
import 'package:livenow/data/ai/receipt_extractors.dart';
import 'package:livenow/domain/ai/ai_batch_service.dart';
import 'package:livenow/domain/ai/ai_protocol.dart';
import 'package:livenow/domain/ai/extracted_receipt.dart';
import 'package:livenow/domain/ai/receipt_extractor.dart';
import 'package:livenow/domain/postpone_rules.dart';

import '../../data/ai/mock_llm_server.dart';
import 'ai_runner_support.dart';

/// E1 (BIM, card 6141): five lines, 391.50 TRY.
List<ReceiptLine> e1Lines() => [
  rl('HAŞHAŞLI ÇÖREK 150 G', 48.00),
  rl('EKMEK KÖY 600G', 64.00),
  rl('SALAM HİNDİ FIST.50G', 65.00, qty: 2, unit: 'ad', unitPrice: 32.5, grams: 50),
  rl('KURU KAYISI 250 G', 162.50),
  rl('MISIR CİPSİ 200G', 52.00),
];

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

  /// The shop action the BIM receipt falls into (19:40 local = 16:40Z).
  Future<String> bazaarAction() => env.actions.createAction(
    name: '🍓 Базар',
    startAt: DateTime.utc(2026, 10, 8, 16, 0),
    endAt: DateTime.utc(2026, 10, 8, 17, 0),
  );

  group('A. receipt', () {
    test('E1: OCR text + model JSON end to end -> draft with categories, quantities, sum ok', () async {
      await env.init(
        llm: llmClient(),
        realExtractor: OcrLlmExtractor(
          ocr: OcrClient(baseUrl: ocrServer.url),
          llm: llmClient(),
        ),
      );
      ocrServer.reply = ocrReply([
        'BIM BIRLESIK MAGAZALAR',
        'HASHASLI COREK 150 G  48,00',
        'EKMEK KOY 600G  64,00',
        'TOPLAM 112,00',
      ]);
      llmServer.enqueueJson(
        receiptOf([
          rl('HAŞHAŞLI ÇÖREK 150 G', 48.00),
          rl('EKMEK KÖY 600G', 64.00),
        ]).toJson(),
      );
      await bazaarAction();
      final jobId = await env.sendReceipt();

      expect(await env.runner.runNext(), isTrue);
      expect(await env.runner.runNext(), isFalse, reason: 'draft-first: waits for Confirm');

      final job = await env.job(jobId);
      expect(job.state, AiJobState.draftReady);
      expect(job.stage, AiStage.waiting);
      final d = await env.draft(jobId);
      final lines = d.lines;
      expect(lines.length, 2);
      expect(lines[0]['category_name'], contains('Снеки'));
      expect(lines[0]['quantity'], 48);
      expect(lines[0]['unit_price'], 1);
      expect(lines[1]['category_name'], contains('Хліб'));
      expect(lines[1]['quantity'], closeTo(0.6, 1e-9));
      expect(lines[1]['unit_price'], closeTo(106.6667, 1e-3));
      expect(d.sum['ok'], isTrue);
      expect(d.json['action']['new'], isFalse, reason: 'ties to the running Базар action');
      expect(await env.count('budget_transactions'), 0, reason: 'nothing written yet');
      // photo: stored on the hub, bytes dropped (that edit syncs to the phone)
      final blob = await env.db.select(env.db.aiBlobsTable).getSingle();
      expect(blob.storedOnHubAt, isNotNull);
      expect(blob.data, isNull);
      expect(env.stored, [blob.id]);
      // exactly one status line, showing the last stage
      final status = await env.messages(jobId, AiMessageKind.status);
      expect(status, hasLength(1));
      expect(status.single.body, AiStage.waiting);
    });

    test('draft-first: Confirm commits exactly once, counts the receipt, writes rates', () async {
      await env.init();
      final actionId = await bazaarAction();
      final jobId = await env.sendReceipt(receiptOf(e1Lines()));
      await env.drain();
      final d = await env.draft(jobId);
      expect(d.lines.length, 5);
      expect(d.sum['ok'], isTrue);
      expect(d.lines[2]['quantity'], closeTo(0.1, 1e-9));
      expect(d.lines[2]['unit_price'], closeTo(650, 1e-6));
      expect(d.lines[3]['quantity'], closeTo(0.25, 1e-9));

      await env.chat.confirmDraft(d.messageId);
      expect(await env.runner.runNext(), isTrue);
      expect(await env.runner.runNext(), isFalse);

      expect((await env.job(jobId)).state, AiJobState.done);
      final txs = await env.transactions();
      expect(txs.length, 5);
      expect(txs.every((t) => t.actionId == actionId), isTrue);
      expect(txs.every((t) => t.rateCount == 36 && t.rateInteract == 44), isTrue);
      expect(
        txs.fold(0.0, (a, t) => a + t.unitPrice * t.quantity),
        closeTo(391.5, 0.02),
      );
      // the account rates are untouched (rates live on the transactions)
      final mono = await (env.db.select(env.db.budgetAccountsTable)
            ..where((t) => t.id.equals(env.monoAcc)))
          .getSingle();
      expect(mono.rateToBase, 44);
      expect(await env.count('ai_batches'), 1);
      expect(await env.settings.confirmedCount(), 1);
      final result = await env.message(jobId, AiMessageKind.result);
      expect(result!.body, contains('Записано'));
      expect(result.body, contains('391.50'));
    });

    test('crash/resume: running the commit again yields the same rows, no duplicates', () async {
      await env.init(autoMode: true);
      await bazaarAction();
      final jobId = await env.sendReceipt(receiptOf(e1Lines()));
      await env.drain();
      expect((await env.job(jobId)).state, AiJobState.done);
      final before = await env.transactions();
      final ids = {for (final t in before) t.id};
      expect(ids, {for (var i = 0; i < 5; i++) deriveId(jobId, 'tx', i)});
      final items = await env.count('ai_batch_items');

      // "Killed after half": last two transactions and their journal are gone,
      // the draft forgot it committed them, the job was left committing.
      final batch = (await env.db.select(env.db.aiBatchesTable).getSingle()).id;
      for (final i in [3, 4]) {
        await env.db.customStatement(
          'DELETE FROM budget_transactions WHERE id = ?',
          [deriveId(jobId, 'tx', i)],
        );
        await env.db.customStatement(
          'DELETE FROM ai_batch_items WHERE batch_id = ? AND position = ?',
          [batch, 10 + i * 10 + 9],
        );
      }
      final m = (await env.message(jobId, AiMessageKind.draft))!;
      final json = jsonDecode(m.contentJson) as Map<String, dynamic>;
      for (final l in json['lines'] as List) {
        final line = l as Map<String, dynamic>;
        if (line['i'] == 3 || line['i'] == 4) line['committed'] = false;
      }
      await env.db.customStatement(
        'UPDATE ai_messages SET content_json = ? WHERE id = ?',
        [jsonEncode(json), m.id],
      );
      await env.db.customStatement(
        "UPDATE ai_jobs SET state = 'committing', attempts = 0 WHERE id = ?",
        [jobId],
      );

      expect(await env.runner.runNext(), isTrue);
      final after = await env.transactions();
      expect({for (final t in after) t.id}, ids);
      expect(after.length, 5);
      expect(await env.count('ai_batches'), 1);
      expect(await env.count('ai_batch_items'), items);
      expect((await env.job(jobId)).state, AiJobState.done);
      expect((await env.job(jobId)).attempts, 1);
      // and once more, fully done: nothing to do, nothing changes
      expect(await env.runner.runNext(), isFalse);
      expect(await env.count('budget_transactions'), 5);
    });

    test('crash/resume: a running job restarts without a second extraction', () async {
      await env.init();
      await bazaarAction();
      final jobId = await env.sendReceipt(receiptOf(e1Lines()));
      await env.drain();
      expect(env.extractor.calls, 1);
      await env.db.customStatement(
        "UPDATE ai_jobs SET state = 'running' WHERE id = ?",
        [jobId],
      );
      expect(await env.runner.runNext(), isTrue);
      expect(env.extractor.calls, 1, reason: 'the stored draft carries what was read');
      expect((await env.job(jobId)).state, AiJobState.draftReady);
      expect(await env.count('ai_messages', "kind = 'draft'"), 1);
      expect(await env.count('ai_messages', "kind = 'status'"), 1);
    });

    test('U7: an unknown weight asks; the answer is learned and completes the job', () async {
      await env.init();
      await bazaarAction();
      final jobId = await env.sendReceipt(
        receiptOf([rl('KURU KAYISI 250 G', 162.50), rl('SAKA SU', 20.00)]),
      );
      await env.drain();
      var job = await env.job(jobId);
      expect(job.state, AiJobState.needsInput);
      final q = (await env.message(jobId, AiMessageKind.question))!;
      final card = QuestionCard.fromJson(jsonDecode(q.contentJson) as Map<String, dynamic>);
      expect(card.questions.single.id, 'weight:1');
      expect(card.questions.single.options, contains('1 кг'));
      var d = await env.draft(jobId);
      expect(d.lines[1]['needs_answer'], isTrue);
      expect(d.lines[1]['quantity'], isNull);

      await env.chat.answerQuestion(q.id, 'weight:1', '1 кг');
      await env.drain();
      job = await env.job(jobId);
      expect(job.state, AiJobState.draftReady);
      d = await env.draft(jobId);
      expect(d.lines[1]['needs_answer'], isFalse);
      expect(d.lines[1]['quantity'], closeTo(1.0, 1e-9));
      final alias = await env.aliases.row('SAKA SU');
      expect(alias!.weightGramsDefault, 1000);

      await env.chat.confirmDraft(d.messageId);
      await env.drain();
      expect((await env.job(jobId)).state, AiJobState.done);
      expect((await env.transactions()).length, 2);
    });

    test('Q1: auto-commit mode writes the obvious lines and asks about the rest', () async {
      await env.init(autoMode: true);
      await bazaarAction();
      final jobId = await env.sendReceipt(
        receiptOf([rl('KURU KAYISI 250 G', 162.50), rl('SAKA SU', 20.00)]),
      );
      await env.drain();
      var job = await env.job(jobId);
      expect(job.state, AiJobState.needsInput);
      expect((await env.transactions()).length, 1, reason: 'only the obvious line');
      final batches = await env.db.select(env.db.aiBatchesTable).get();
      expect(batches, hasLength(1));
      final result = await env.message(jobId, AiMessageKind.result);
      expect(result!.body, contains('Курага'));
      expect(result.body, contains('Ще чекають'));

      final q = (await env.message(jobId, AiMessageKind.question))!;
      await env.chat.answerQuestion(q.id, 'weight:1', '1 кг');
      await env.drain();
      job = await env.job(jobId);
      expect(job.state, AiJobState.done);
      expect((await env.transactions()).length, 2);
      expect(await env.count('ai_batches'), 1, reason: 'the SAME batch');
      expect(await env.count('ai_batch_items'), 2, reason: 'one transaction per line');
      expect(await env.settings.confirmedCount(), 0, reason: 'nobody confirmed a draft');
    });

    test('I2: a sum mismatch commits nothing and says by how much', () async {
      await env.init(autoMode: true);
      await bazaarAction();
      final r = receiptOf(e1Lines(), total: 400.00);
      final jobId = await env.sendReceipt(r);
      await env.drain();
      final job = await env.job(jobId);
      expect(job.state, AiJobState.draftReady);
      expect(await env.count('budget_transactions'), 0);
      final err = (await env.message(jobId, AiMessageKind.error))!;
      expect(err.body, contains('391.50'));
      expect(err.body, contains('400.00'));
      expect(err.body, contains('-8.50'));
      // Confirm does not force it through.
      final d = await env.draft(jobId);
      await env.chat.confirmDraft(d.messageId);
      await env.drain();
      expect(await env.count('budget_transactions'), 0);
      expect((await env.job(jobId)).state, AiJobState.draftReady);
    });

    test('I6: a receipt that was already recorded asks instead of inserting', () async {
      await env.init(autoMode: true);
      await bazaarAction();
      final first = await env.sendReceipt(receiptOf(e1Lines()));
      await env.drain();
      expect((await env.job(first)).state, AiJobState.done);
      final second = await env.sendReceipt();
      await env.drain();
      final job = await env.job(second);
      expect(job.state, AiJobState.needsInput);
      expect(await env.count('budget_transactions'), 5);
      final q = (await env.message(second, AiMessageKind.question))!;
      final card = QuestionCard.fromJson(jsonDecode(q.contentJson) as Map<String, dynamic>);
      expect(card.questions.single.id, 'dup');

      // "Skip": done, still nothing new.
      await env.chat.answerQuestion(q.id, 'dup', 'Пропустити');
      await env.drain();
      expect((await env.job(second)).state, AiJobState.done);
      expect(await env.count('budget_transactions'), 5);
    });

    test('I6: "add anyway" records the duplicate on purpose', () async {
      await env.init(autoMode: true);
      await bazaarAction();
      await env.sendReceipt(receiptOf(e1Lines()));
      await env.drain();
      final second = await env.sendReceipt();
      await env.drain();
      final q = (await env.message(second, AiMessageKind.question))!;
      await env.chat.answerQuestion(q.id, 'dup', 'Все одно додати');
      await env.drain();
      expect((await env.job(second)).state, AiJobState.done);
      expect(await env.count('budget_transactions'), 10);
    });

    test('E2: a split tender records only the user lines', () async {
      await env.init(autoMode: true);
      await bazaarAction();
      await env.aliases.remember('PEYNIR 400G', categoryId: env.bread);
      await env.aliases.remember('ZEYTIN 500G', categoryId: env.salami);
      final jobId = await env.sendReceipt(
        receiptOf(
          [
            rl('PEYNIR 400G', 99.95),
            rl('ZEYTIN 500G', 95.50),
            rl('SAKIZ A', 25.00),
            rl('SAKIZ B', 25.00),
            rl('MAKARNA 500G', 99.00),
          ],
          total: 344.45,
          tenders: const [
            Tender(method: 'card', last4: '1111', amount: 149.00),
            Tender(method: 'card', last4: '6141', amount: 195.45),
          ],
        ),
      );
      await env.drain();
      expect((await env.job(jobId)).state, AiJobState.done);
      final d = await env.draft(jobId);
      expect([for (final l in d.lines) l['i']], [0, 1]);
      expect(d.sum['expected'], 195.45);
      final txs = await env.transactions();
      expect(txs.length, 2);
      expect(
        txs.fold(0.0, (a, t) => a + t.unitPrice * t.quantity),
        closeTo(195.45, 0.02),
      );
    });

    test('E3: a changed price creates the wrapper; the batch undoes it as a whole', () async {
      await env.init(autoMode: true);
      await bazaarAction();
      final seed = await env.budget.settings();
      expect(seed.baseCurrency, 'EUR');
      final apple = await env.budget.saveCategory(
        CategoryInputLike.leaf('Яблука Granny Smith', 159.95, env.groupFood, env.tryAcc, env.monoAcc),
      );
      await env.aliases.remember('ELMA GRANNY SMITH', categoryId: apple);
      final jobId = await env.sendReceipt(
        receiptOf([
          rl('ELMA GRANNY SMITH', 113.44, qty: 1.135, unit: 'kg', unitPrice: 99.95),
        ]),
      );
      await env.drain();
      expect((await env.job(jobId)).state, AiJobState.done);
      final d = await env.draft(jobId);
      expect(d.lines.single['price_change'], isTrue);
      expect(d.lines.single['new_category'], isTrue);

      final cats = await (env.db.select(env.db.budgetCategoriesTable)
            ..where((t) => t.name.equals('Яблука Granny Smith')))
          .get();
      expect(cats.length, 3, reason: 'wrapper + old leaf + new leaf');
      final wrapper = cats.firstWhere((c) => c.price == null);
      final old = cats.firstWhere((c) => c.id == apple);
      expect(old.parentId, wrapper.id);
      expect(wrapper.parentId, env.groupFood);
      final tx = (await env.transactions()).single;
      expect(tx.quantity, closeTo(1.135, 1e-9));
      final newLeaf = cats.firstWhere((c) => c.parentId == wrapper.id && c.id != apple);
      expect(tx.categoryId, newLeaf.id);
      expect(newLeaf.price, closeTo(99.947, 1e-3));

      final batchId = (await env.db.select(env.db.aiBatchesTable).getSingle()).id;
      final undo = await AiBatchService(env.db).undoBatch(batchId);
      expect(undo.skipped, isEmpty);
      expect(await env.count('budget_transactions'), 0);
      final left = await (env.db.select(env.db.budgetCategoriesTable)
            ..where((t) => t.name.equals('Яблука Granny Smith')))
          .get();
      expect(left.single.id, apple);
      expect(left.single.parentId, env.groupFood);
    });

    test('a Confirm with edits applies them to the lines before the commit', () async {
      await env.init();
      await bazaarAction();
      final jobId = await env.sendReceipt(receiptOf(e1Lines()));
      await env.drain();
      final d = await env.draft(jobId);
      await env.chat.confirmDraft(d.messageId, edits: const [LineEdit(index: 2, quantity: 0.2)]);
      await env.drain();
      expect((await env.job(jobId)).state, AiJobState.done);
      final salami = (await env.transactions()).where((t) => t.categoryId != null).firstWhere(
        (t) => (t.quantity - 0.2).abs() < 1e-9,
      );
      expect(salami.unitPrice, closeTo(325, 1e-6), reason: 'amount kept, price follows the quantity');
    });

    test('Reject writes nothing and finishes the job', () async {
      await env.init();
      await bazaarAction();
      final jobId = await env.sendReceipt(receiptOf(e1Lines()));
      await env.drain();
      final d = await env.draft(jobId);
      await env.chat.rejectDraft(d.messageId);
      await env.drain();
      expect((await env.job(jobId)).state, AiJobState.done);
      expect(await env.count('budget_transactions'), 0);
      expect(await env.count('ai_batches'), 0);
      expect(await env.settings.confirmedCount(), 0);
    });

    test('an unknown card asks once and remembers the account as a rule', () async {
      await env.init(autoMode: true);
      await bazaarAction();
      final r = receiptOf(
        [rl('KURU KAYISI 250 G', 162.50)],
        tenders: const [Tender(method: 'card', last4: '9999', amount: 162.50)],
      );
      final jobId = await env.sendReceipt(r);
      await env.drain();
      expect((await env.job(jobId)).state, AiJobState.needsInput);
      expect(await env.count('budget_transactions'), 0);
      final q = (await env.message(jobId, AiMessageKind.question))!;
      final card = QuestionCard.fromJson(jsonDecode(q.contentJson) as Map<String, dynamic>);
      expect(card.questions.single.id, 'card:9999');
      await env.chat.answerQuestion(q.id, 'card:9999', 'Monobank');
      await env.drain();
      expect((await env.job(jobId)).state, AiJobState.done);
      expect((await env.rules.get('card.9999'))!['account_id'], env.monoAcc);
      expect(await env.count('budget_transactions'), 1);
    });

    test('model: picks among ambiguous candidates; a failing model becomes a question', () async {
      await env.init(autoMode: true, llm: llmClient());
      await bazaarAction();
      final gouda = await env.budget.saveCategory(
        CategoryInputLike.leaf('Сир Гауда', 500, env.groupFood, env.tryAcc, env.monoAcc),
      );
      await env.budget.saveCategory(
        CategoryInputLike.leaf('Сир Едам', 450, env.groupFood, env.tryAcc, env.monoAcc),
      );

      // 1. the name is already Ukrainian (no translation call); the model chooses
      // c1 with confidence
      llmServer.enqueueJson({
        'items': [
          {'n': 1, 'pick': 'c1', 'group': 'none', 'name': '', 'confidence': 0.9},
        ],
      });
      final a = await env.sendReceipt(receiptOf([rl('Сир 200 г', 100.00, name: 'Сир 200 г')], at: '2026-10-08T19:40:00'));
      await env.drain();
      expect((await env.job(a)).state, AiJobState.done);
      var d = await env.draft(a);
      expect(d.lines.single['category_id'], isNotNull);
      final tx = (await env.transactions()).single;
      expect(tx.categoryId, gouda);

      // 2. the model server has nothing to say (500): deterministic fallback
      final b = await env.sendReceipt(
        receiptOf([rl('Сир 300 г', 150.00, name: 'Сир 300 г')], at: '2026-10-09T10:00:00'),
      );
      await env.drain();
      expect((await env.job(b)).state, AiJobState.needsInput);
      d = await env.draft(b);
      expect(d.lines.single['needs_answer'], isTrue);
      final q = (await env.message(b, AiMessageKind.question))!;
      final card = QuestionCard.fromJson(jsonDecode(q.contentJson) as Map<String, dynamic>);
      expect(card.questions.single.id, 'cat:0');
      expect(card.questions.single.options, containsAll(['Сир Гауда', 'Сир Едам']));
      expect(await env.count('budget_transactions'), 1, reason: 'nothing guessed');

      // The user picks one; it becomes an alias and the job completes.
      await env.chat.answerQuestion(q.id, 'cat:0', 'Сир Едам');
      await env.drain();
      expect((await env.job(b)).state, AiJobState.done);
      expect(await env.count('budget_transactions'), 2);
      expect((await env.aliases.row('Сир 300 г'))!.categoryId, isNotNull);
    });

    test('a job fails after 3 attempts with an error row', () async {
      await env.init();
      env.extractor.error = const ReceiptExtractionException('OCR found no text');
      final jobId = await env.sendReceipt(receiptOf(e1Lines()));
      expect(await env.runner.runNext(), isTrue);
      expect((await env.job(jobId)).state, AiJobState.queued);
      expect((await env.job(jobId)).attempts, 1);
      expect(await env.runner.runNext(), isTrue);
      expect(await env.runner.runNext(), isTrue);
      final job = await env.job(jobId);
      expect(job.state, AiJobState.failed);
      expect(job.attempts, 3);
      expect(job.error, contains('OCR found no text'));
      final err = (await env.message(jobId, AiMessageKind.error))!;
      expect(err.body, contains('3'));
      expect(await env.runner.runNext(), isFalse);
      expect(env.extractor.calls, 3);
    });

    test('a job interrupted 3 times is given up on pickup', () async {
      await env.init();
      final jobId = await env.sendReceipt(receiptOf(e1Lines()));
      await env.db.customStatement(
        "UPDATE ai_jobs SET state = 'running', attempts = 2 WHERE id = ?",
        [jobId],
      );
      expect(await env.runner.runNext(), isTrue, reason: 'giving up is work too');
      expect(await env.runner.runNext(), isFalse);
      final job = await env.job(jobId);
      expect(job.state, AiJobState.failed);
      expect(await env.message(jobId, AiMessageKind.error), isNotNull);
      expect(env.extractor.calls, 0);
    });
  });

  group('C. bazaar', () {
    test('a checklist note: items, herbs by the piece, the Базар action, cash TRY', () async {
      await env.init(autoMode: true);
      final seed = env.budget;
      Future<String> leaf(String n, double p, {bool piece = false}) => seed.saveCategory(
        CategoryInputLike.leaf(n, p, env.groupFood, env.tryAcc, env.tryAcc, piece: piece),
      );
      await leaf('Кабачки', 30);
      await leaf('Морква', 20);
      await leaf('Зелень', 20, piece: true);
      final now = DateTime.now().toUtc();
      final action = await env.actions.createAction(
        name: '🍓 Базар +Мама',
        startAt: now.subtract(const Duration(minutes: 3)),
        endAt: now.add(const Duration(minutes: 50)),
      );
      final sent = await env.chat.sendText(
        env.thread,
        '- [x] Кабачки 65/30=2,167\n- [x] Морква 20\n- [ ] Груші 80\n- [x] Зелень 20',
      );
      final jobId = sent.jobId!;
      expect((await env.job(jobId)).kind, AiJobKind.bazaar);
      await env.drain();
      expect((await env.job(jobId)).state, AiJobState.done);
      final txs = await env.transactions();
      expect(txs.length, 3);
      expect(txs.every((t) => t.actionId == action), isTrue, reason: 'T5');
      final byName = {for (final t in txs) t.name: t};
      expect(byName['Базар Кабачки']!.quantity, closeTo(2.167, 1e-9));
      expect(byName['Базар Морква']!.quantity, 1);
      expect(byName['Базар Зелень']!.quantity, 1);
      // cash TRY on both sides: the real market rate twice, never a placeholder 1
      expect(txs.every((t) => t.rateCount == 36 && t.rateInteract == 36), isTrue);
      expect(txs.every((t) => t.accountUseId == env.tryAcc), isTrue);
    });
  });

  group('D. text', () {
    test('a transfer text writes the two linked transactions, undoable', () async {
      await env.init();
      final sent = await env.chat.sendText(env.thread, 'перевів 12582.50 з ФОП на Monobank');
      await env.drain();
      expect((await env.job(sent.jobId!)).state, AiJobState.done);
      final txs = await env.transactions();
      expect(txs.length, 2);
      expect(txs.map((t) => t.isIncome).toSet(), {true, false});
      expect(txs.map((t) => t.quantity).toSet(), {12582.5});
      expect(txs.every((t) => t.rateInteract == 44), isTrue, reason: 'each account real rate');
      expect(txs.map((t) => t.id).toSet(), {
        deriveId(sent.jobId!, 'transfer-out'),
        deriveId(sent.jobId!, 'transfer-in'),
      });
      final batchId = (await env.db.select(env.db.aiBatchesTable).getSingle()).id;
      final undo = await AiBatchService(env.db).undoBatch(batchId);
      expect(undo.transactions, 2);
      expect(await env.count('budget_transactions'), 0);
    });

    test('an unknown account name is a question, never a guess', () async {
      await env.init();
      final sent = await env.chat.sendText(env.thread, 'перевів 100 з Невідомий на Monobank');
      await env.drain();
      final job = await env.job(sent.jobId!);
      expect(job.state, AiJobState.done);
      expect(await env.count('budget_transactions'), 0);
      expect((await env.message(sent.jobId!, AiMessageKind.text))!.body, contains('Невідомий'));
    });

    test('a typed correction edits the pending draft; "так" confirms it', () async {
      await env.init();
      await bazaarAction();
      final jobId = await env.sendReceipt(receiptOf(e1Lines()));
      await env.drain();

      final del = await env.chat.sendText(env.thread, 'видали рядок 1');
      await env.drain();
      expect((await env.job(del.jobId!)).state, AiJobState.done);
      var d = await env.draft(jobId);
      expect(d.lines[0]['skipped'], isTrue);
      expect(d.sum['ok'], isTrue, reason: 'the expected total drops with the line');
      expect((await env.job(jobId)).state, AiJobState.draftReady);

      final ok = await env.chat.sendText(env.thread, 'так');
      await env.drain();
      expect((await env.job(ok.jobId!)).state, AiJobState.done);
      expect((await env.job(jobId)).state, AiJobState.done);
      expect((await env.transactions()).length, 4);
      d = await env.draft(jobId);
      expect(d.lines.where((l) => l['committed'] == true).length, 4);
    });

    test('model: a typed correction is read into an intent; unparseable text asks', () async {
      await env.init(llm: llmClient());
      await bazaarAction();
      final jobId = await env.sendReceipt(receiptOf(e1Lines()));
      await env.drain();
      llmServer.enqueueJson({
        'intent': 'set_category',
        'line': 1,
        'text': 'Курага',
        'number': null,
        'unit': null,
      });
      final fix = await env.chat.sendText(env.thread, 'перший рядок це курага');
      await env.drain();
      expect((await env.job(fix.jobId!)).state, AiJobState.done);
      final d = await env.draft(jobId);
      expect(d.lines[0]['category_name'], contains('Курага'));
      expect(d.lines[0]['snacks'], isFalse);

      // The model answers nonsense: a short question, nothing changes.
      llmServer.enqueueJson({'intent': 'dance', 'line': null, 'text': null, 'number': null, 'unit': null});
      final junk = await env.chat.sendText(env.thread, 'щось незрозуміле');
      await env.drain();
      final reply = (await env.message(junk.jobId!, AiMessageKind.text))!;
      expect(reply.body, contains('Не зрозумів'));
      expect(await env.count('budget_transactions'), 0);
    });

    test('text with no pending draft and no transfer asks what to do', () async {
      await env.init();
      final sent = await env.chat.sendText(env.thread, 'привіт');
      await env.drain();
      expect((await env.job(sent.jobId!)).state, AiJobState.done);
      expect((await env.message(sent.jobId!, AiMessageKind.text))!.body, contains('Не зрозумів'));
    });
  });

  group('A2. one message, several photos', () {
    // Photo 1 is a receipt (no hryvnia amount, no rate), photo 2 the bank screenshot.
    Object ocrFor(List<int> image) => image.first == 2
        ? ocrReply(['Monobank', 'Сума 361,64 ₴', 'У валюті 391,50 TL', 'курс 0,9237'])
        : ocrReply(['BIM', 'EKMEK KÖY 600G 64,00', 'TOPLAM 391,50 TL']);

    test('a receipt and its screenshot in one message record with the bank rate', () async {
      await env.init(autoMode: true, ocr: OcrClient(baseUrl: ocrServer.url));
      ocrServer.replyFor = ocrFor;
      await bazaarAction();
      env.extractor.receipt = receiptOf(e1Lines());
      final job = await env.sendPhotos([1, 2]);
      await env.drain();
      expect((await env.job(job)).state, AiJobState.done, reason: (await env.job(job)).error);
      final txs = await env.transactions();
      expect(txs, hasLength(5));
      for (final t in txs) {
        expect(t.rateCount, 36);
        expect(t.rateInteract, closeTo(36 * 0.9237, 1e-6));
      }
      final mono = await (env.db.select(env.db.budgetAccountsTable)
            ..where((t) => t.id.equals(env.monoAcc)))
          .getSingle();
      expect(mono.rateToBase, 44, reason: 'a screenshot rate belongs to the transactions only');
      expect(await env.count('ai_batches'), 1, reason: 'one batch, not a receipt batch plus a rate batch');
      expect(env.extractor.calls, 1, reason: 'the screenshot is never read as a receipt');
      expect(env.stored, hasLength(2), reason: 'both originals go to the hub');
    });

    test('the order of the photos does not matter, and the draft shows the bank rate', () async {
      await env.init(ocr: OcrClient(baseUrl: ocrServer.url)); // draft-first
      ocrServer.replyFor = ocrFor;
      await bazaarAction();
      env.extractor.receipt = receiptOf(e1Lines());
      final job = await env.sendPhotos([2, 1]);
      await env.drain();
      expect((await env.job(job)).state, AiJobState.draftReady);
      expect((await env.draft(job)).json['fx_source'], 'screenshot');
      expect(await env.count('budget_transactions'), 0, reason: 'nothing is written before Confirm');
    });

    test('a receipt alone is still a receipt', () async {
      await env.init(autoMode: true, ocr: OcrClient(baseUrl: ocrServer.url));
      ocrServer.replyFor = ocrFor;
      await bazaarAction();
      env.extractor.receipt = receiptOf(e1Lines());
      final job = await env.sendPhotos([1]);
      await env.drain();
      expect((await env.job(job)).state, AiJobState.done);
      final txs = await env.transactions();
      expect(txs, hasLength(5));
      expect(txs.first.rateInteract, isNot(closeTo(36 * 0.9237, 1e-3)), reason: 'market rate, no screenshot');
    });

    test('a screenshot alone is applied to the receipt recorded earlier', () async {
      await env.init(autoMode: true, ocr: OcrClient(baseUrl: ocrServer.url));
      ocrServer.replyFor = ocrFor;
      await bazaarAction();
      await env.sendReceipt(receiptOf(e1Lines()));
      await env.drain();
      final job = await env.sendPhotos([2]);
      await env.drain();
      expect((await env.job(job)).state, AiJobState.done);
      for (final t in await env.transactions()) {
        expect(t.rateInteract, closeTo(36 * 0.9237, 1e-6));
      }
      expect(await env.count('ai_batches'), 2);
    });

    test('two receipts and two screenshots: one job per receipt, each with ITS screenshot', () async {
      await env.init(ocr: OcrClient(baseUrl: ocrServer.url)); // draft-first
      // Photos 1 and 3 are receipts, 2 and 4 their screenshots (4 comes first
      // for the second receipt's amount: 200,00 TL).
      ocrServer.replyFor = (image) => switch (image.first) {
        2 => ocrReply(['Сума 361,64 ₴', 'У валюті 391,50 TL', 'курс 0,9237']),
        4 => ocrReply(['Сума 180,00 ₴', 'У валюті 200,00 TL', 'курс 0,9000']),
        _ => ocrReply(['BIM', 'TOPLAM']),
      };
      await bazaarAction();
      env.extractor.queue
        ..add(receiptOf(e1Lines())) // 391,50
        ..add(receiptOf([rl('SAKA SU', 200.0)])); // 200,00
      final parent = await env.sendPhotos([1, 4, 3, 2]); // shuffled on purpose
      await env.drain();

      expect((await env.job(parent)).state, AiJobState.done);
      expect((await env.message(parent, AiMessageKind.text))!.body, contains('2 чеків'));
      final first = deriveId(parent, 'job', 0);
      final second = deriveId(parent, 'job', 1);
      for (final id in [first, second]) {
        expect((await env.job(id)).kind, AiJobKind.receipt);
        expect(
          {(await env.job(id)).state},
          anyOf({AiJobState.draftReady}, {AiJobState.needsInput}),
          reason: 'its own draft, waiting for Confirm',
        );
      }
      Map<String, dynamic> shotOf(DraftCardView d) =>
          Map<String, dynamic>.from((d.json['overrides'] as Map)['screenshot'] as Map);
      final a = await env.draft(first);
      final b = await env.draft(second);
      expect(a.json['fx_source'], 'screenshot');
      expect(b.json['fx_source'], 'screenshot');
      expect(shotOf(a)['count'], 391.5, reason: 'the 391,50 screenshot belongs to the 391,50 receipt');
      expect(shotOf(b)['count'], 200.0);
      expect(await env.count('budget_transactions'), 0, reason: 'nothing before Confirm');
      expect(env.extractor.calls, 2);
      expect(env.stored, hasLength(4), reason: 'all four originals end up on the hub');
    });

    test('splitting a message twice creates the child jobs only once', () async {
      await env.init(autoMode: true, ocr: OcrClient(baseUrl: ocrServer.url));
      ocrServer.replyFor = ocrFor;
      env.extractor.receipt = receiptOf(e1Lines());
      final parent = await env.sendPhotos([1, 3]);
      await env.drain();
      await env.db.customStatement("UPDATE ai_jobs SET state = 'queued' WHERE id = '$parent'");
      await env.drain();
      expect(await env.count('ai_jobs', "kind = 'receipt'"), 2);
    });

    test('several screenshots alone become one screenshot job each', () async {
      await env.init(autoMode: true, ocr: OcrClient(baseUrl: ocrServer.url));
      ocrServer.replyFor = (_) => ocrReply(['Сума 100,00 ₴', 'У валюті 110,00 TL', 'курс 0,9091']);
      final parent = await env.sendPhotos([2, 4]);
      await env.drain();
      expect((await env.job(parent)).state, AiJobState.done);
      expect(await env.count('ai_jobs', "kind = 'screenshot' AND state = 'done'"), 2);
    });

    test('without an OCR service every photo is read as a receipt', () async {
      await env.init(autoMode: true);
      await bazaarAction();
      env.extractor.receipt = receiptOf(e1Lines());
      final job = await env.sendPhotos([1]);
      await env.drain();
      expect((await env.job(job)).state, AiJobState.done);
      expect(await env.count('budget_transactions'), 5);
    });
  });

  group('B. screenshot', () {
    test('a late bank screenshot recomputes the rates as a new undoable batch', () async {
      await env.init(
        autoMode: true,
        ocr: OcrClient(baseUrl: ocrServer.url),
      );
      await bazaarAction();
      final receiptJob = await env.sendReceipt(receiptOf(e1Lines()));
      await env.drain();
      expect((await env.job(receiptJob)).state, AiJobState.done);
      final rateBefore = {
        for (final t in await env.transactions()) t.id: t.rateInteract,
      };

      ocrServer.reply = ocrReply([
        'Monobank',
        'Сума 361,64 ₴',
        'У валюті 391,50 TL',
        'курс 0,9237',
      ]);
      final shot = await env.sendScreenshot();
      await env.drain();
      final job = await env.job(shot);
      expect(job.state, AiJobState.done, reason: job.error ?? (await env.message(shot, AiMessageKind.text))?.body);
      final txs = await env.transactions();
      expect(txs.every((t) => t.rateCount == 36), isTrue);
      for (final t in txs) {
        expect(t.rateInteract, closeTo(36 * 0.9237, 1e-6));
      }
      final mono = await (env.db.select(env.db.budgetAccountsTable)
            ..where((t) => t.id.equals(env.monoAcc)))
          .getSingle();
      expect(mono.rateToBase, 44, reason: 'a screenshot rate belongs to the transactions only');
      expect(await env.count('ai_batches'), 2);
      final items = await env.db.select(env.db.aiBatchItemsTable).get();
      expect(items.where((i) => i.op == AiOp.update).length, 5);
      expect((await env.message(shot, AiMessageKind.result))!.body, contains('0.9237'));

      // Undoing the screenshot batch puts the previous rates back.
      final batch = await (env.db.select(env.db.aiBatchesTable)
            ..where((t) => t.jobId.equals(shot)))
          .getSingle();
      await AiBatchService(env.db).undoBatch(batch.id);
      for (final t in await env.transactions()) {
        expect(t.rateInteract, rateBefore[t.id]);
      }
    });

    test('a screenshot with no matching receipt says so and changes nothing', () async {
      await env.init(ocr: OcrClient(baseUrl: ocrServer.url));
      ocrServer.reply = ocrReply(['Сума 100,00 ₴', 'У валюті 110,00 TL', 'курс 0,9091']);
      final shot = await env.sendScreenshot();
      await env.drain();
      expect((await env.job(shot)).state, AiJobState.done);
      expect((await env.message(shot, AiMessageKind.text))!.body, contains('Не знайшов'));
      expect(await env.count('ai_batches'), 0);
    });
  });
}
