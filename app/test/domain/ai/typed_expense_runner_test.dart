import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/ai/ai_draft.dart';
import 'package:livenow/domain/ai/ai_protocol.dart';
import 'package:livenow/domain/postpone_rules.dart';

import 'ai_runner_support.dart';

/// "купив хліб 40 готівкою": the same draft / questions / Confirm as a photo.
void main() {
  late RunnerEnv env;

  setUpAll(() {
    HttpOverrides.global = null;
    initPostponeTimeZoneData();
  });
  setUp(() async {
    env = RunnerEnv();
    await env.init();
  });
  tearDown(() => env.close());

  Future<String> say(String text) async {
    final sent = await env.chat.sendText(env.thread, text);
    await env.drain();
    return sent.jobId!;
  }

  Future<DraftCard> card(String jobId) async =>
      DraftCard.fromJson((await env.draft(jobId)).json);

  Future<QuestionCard?> openQuestion(String jobId) async {
    final m = await env.message(jobId, AiMessageKind.question);
    if (m == null) return null;
    final q = QuestionCard.fromJson(jsonDecode(m.contentJson) as Map<String, dynamic>);
    return q.questions.any((x) => x.answer == null) ? q : null;
  }

  test('a currency that leaves one account needs no question; the draft is ready', () async {
    final id = await say('купив хліб 40 лір готівкою');
    expect(await openQuestion(id), isNull);
    final d = await card(id);
    expect(d.useAccountId, env.tryAcc);
    expect(d.currency, 'TRY');
    expect(d.lines.single.categoryId, env.bread);
    expect(d.lines.single.amount, 40);
    expect((await env.job(id)).state, AiJobState.draftReady);
    expect(await env.count('budget_transactions'), 0, reason: 'draft first');
  });

  test('cash with no currency is asked once and then remembered', () async {
    final first = await say('хліб 40 готівкою');
    final q = (await openQuestion(first))!;
    expect(q.questions.single.id, 'cash_account');
    expect(q.questions.single.options, containsAll(['Готівка TRY', 'Monobank', 'ФОП']));
    final m = (await env.message(first, AiMessageKind.question))!;
    await env.chat.answerQuestion(m.id, 'cash_account', 'Готівка TRY');
    await env.drain();
    expect(await openQuestion(first), isNull);
    final d = await card(first);
    expect(d.useAccountId, env.tryAcc);
    expect(d.currency, 'TRY');

    final second = await say('хліб 30 готівкою');
    expect(await openQuestion(second), isNull, reason: 'the cash account is remembered');
    expect((await card(second)).useAccountId, env.tryAcc);
  });

  test('an account named in the text is used, and its currency is the default', () async {
    final id = await say('хліб 40 з monobank');
    expect(await openQuestion(id), isNull);
    final d = await card(id);
    expect(d.useAccountId, env.monoAcc);
    expect(d.currency, 'UAH');
    expect(d.lines.single.name, 'Хліб', reason: 'the account words are not part of the item');
  });

  test('no account and not cash: asked which account, answer is used', () async {
    final id = await say('хліб 40');
    final q = (await openQuestion(id))!;
    expect(q.questions.single.id, 'pay_account');
    final m = (await env.message(id, AiMessageKind.question))!;
    await env.chat.answerQuestion(m.id, 'pay_account', 'ФОП');
    await env.drain();
    expect(await openQuestion(id), isNull);
    expect((await card(id)).useAccountId, env.fopAcc);

    // Confirm writes the transaction on that account.
    final dm = (await env.draft(id)).messageId;
    await env.chat.confirmDraft(dm);
    await env.drain();
    expect((await env.job(id)).state, AiJobState.done);
    final tx = await env.transactions();
    expect(tx.length, 1);
    expect(tx.single.accountUseId, env.fopAcc);
  });

  test('several items and "вчора": one draft, the day is yesterday', () async {
    final id = await say('хліб 40, вода 20 вчора з monobank');
    final d = await card(id);
    expect(d.lines.length, 2);
    expect(d.useAccountId, env.monoAcc);
    final age = DateTime.now().toUtc().difference(d.at);
    expect(age.inHours, inInclusiveRange(10, 40), reason: 'noon yesterday, Istanbul time');
  });

  test('while a draft waits, a correction stays a correction', () async {
    final receiptJob = await env.sendReceipt(receiptOf([rl('EKMEK KÖY 600G', 64.00)]));
    await env.drain();
    expect((await env.job(receiptJob)).state, AiJobState.draftReady);

    final id = await say('рядок 2 категорія снеки');
    final reply = (await env.message(id, AiMessageKind.text))!;
    expect(reply.body, contains('виправлення'));
    expect(await env.message(id, AiMessageKind.draft), isNull, reason: 'no new draft');

    // ... but a message that reads like a purchase starts a new draft.
    final purchase = await say('купив хліб 40 лір готівкою');
    expect(await env.message(purchase, AiMessageKind.draft), isNotNull);
  });

  test('a message that says income, matched to an expense category, is held weakly', () async {
    final id = await say('отримав хліб 40 лір');
    final d = await card(id);
    final l = d.lines.single;
    expect(l.suggested, isTrue);
    expect(l.confidence, closeTo(0.3, 1e-9));
    expect(d.notes.join(' '), contains('дохід'));
  });

  test('chatter is still "не зрозумів", with a purchase example', () async {
    final id = await say('привіт, як справи');
    final reply = (await env.message(id, AiMessageKind.text))!;
    expect(reply.body, contains('Не зрозумів'));
    expect(reply.body, contains('купив каву'));
  });
}
