/// The hub's worker for the receipt assistant. The apps only write message +
/// job rows (see [AiChatService]); [AiJobRunner.runNext] does ONE unit of work
/// for the oldest job that needs the hub and tells the caller whether it did
/// something, so the hub loop simply calls it again and again.
///
/// Design rules:
/// * deterministic first: parsers, rules and services decide; the model (when
///   there is one) only picks among candidate categories or reads a typed
///   correction, and its failure turns into a plain question, never a guess;
/// * crash-safe and idempotent: every row a job creates has an id derived with
///   `deriveId(job.id, role, index)` and is inserted if absent or updated in
///   place; the budget writes of one commit run in ONE transaction;
/// * the draft card (`ai_messages`, kind draft) is also the job's working state:
///   it keeps what was read and what the user decided, so an answer or an edit
///   only rebuilds it (no second OCR / model run);
/// * nothing is ever deleted (I7); money rows are written through the budget,
///   action and price-planner services only.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart'
    show BooleanExpressionOperators, InsertMode, OrderingTerm, Value, Variable;

import '../../core/ids.dart';
import '../../core/time_codec.dart';
import '../../data/ai/llm_client.dart';
import '../../data/ai/ocr_client.dart';
import '../../data/ai/receipt_extractors.dart' show OcrLlmExtractor;
import '../../data/database.dart';
import '../action_service.dart';
import '../budget_service.dart';
import 'action_creator.dart';
import 'action_matcher.dart';
import 'ai_alias_db_source.dart';
import 'ai_batch_service.dart';
import 'ai_draft_builder.dart';
import 'ai_protocol.dart';
import 'ai_screenshot_text.dart';
import 'ai_settings_store.dart';
import 'ai_transfer_text.dart';
import 'alias_source.dart';
import 'category_resolver.dart';
import 'invariant_validator.dart';
import 'model_prompts.dart';
import 'price_planner.dart';
import 'receipt_extractor.dart';
import 'receipt_fx_rules.dart';
import 'transfer_builder.dart';
import 'typed_expense.dart';

/// A job is given up after this many failed or interrupted attempts.
const kMaxJobAttempts = 3;

class AiJobRunner {
  AiJobRunner({
    required this.db,
    required this.extractor,
    this.llm,
    this.ocr,
    required this.settings,
    this.storeOriginal,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       _aliases = DbAliasSource(db),
       _rules = AiRulesMemory(db),
       _batches = AiBatchService(db),
       _budget = BudgetService(db),
       _actions = ActionService(db) {
    _builder = DraftBuilder(db: db, aliases: _aliases, rules: _rules, llm: llm);
    _planner = PricePlanner(db, _budget);
    _creator = ActionCreator(db, _actions);
    _matcher = ActionMatcher(db);
  }

  final AppDatabase db;
  final ReceiptExtractor extractor;
  final LlmClient? llm;
  final OcrClient? ocr;
  final AiSettingsStore settings;

  /// Saves the original photo on the hub (its own folder). Only after it
  /// returns is the photo row marked stored and its bytes dropped.
  final Future<void> Function(AiBlob blob)? storeOriginal;
  final DateTime Function() _clock;

  final DbAliasSource _aliases;
  final AiRulesMemory _rules;
  final AiBatchService _batches;
  final BudgetService _budget;
  final ActionService _actions;
  late final DraftBuilder _builder;
  late final PricePlanner _planner;
  late final ActionCreator _creator;
  late final ActionMatcher _matcher;

  DateTime? _lastStamp;

  /// This [runNext] gave up on an interrupted job (that counts as work done).
  bool _gaveUp = false;

  /// Strictly increasing creation times, so messages written in one run keep
  /// their order in the chat.
  String _stamp() {
    var t = _clock().toUtc();
    final last = _lastStamp;
    if (last != null && !t.isAfter(last)) {
      t = last.add(const Duration(milliseconds: 1));
    }
    _lastStamp = t;
    return dateTimeToDb(t)!;
  }

  // ===========================================================================
  // Entry point
  // ===========================================================================

  /// Does one unit of work. Order: (1) a job that was interrupted while running
  /// or committing, else the oldest queued job; (2) a waiting job (needs_input /
  /// draft_ready) with new user input; (3) nothing: false.
  Future<bool> runNext() async {
    _gaveUp = false;
    final job = await _nextRunnable();
    if (job != null) {
      await _guarded(job, resume: false);
      return true;
    }
    if (_gaveUp) return true;
    final waiting = await _nextWaitingWithInput();
    if (waiting != null) {
      await _guarded(waiting, resume: true);
      return true;
    }
    return false;
  }

  Future<AiJob?> _nextRunnable() async {
    final stuck =
        await (db.select(db.aiJobsTable)
              ..where(
                (t) => t.state.isIn([AiJobState.running, AiJobState.committing]),
              )
              ..orderBy([
                (t) => OrderingTerm.asc(t.createdAt),
                (t) => OrderingTerm.asc(t.id),
              ])
              ..limit(1))
            .getSingleOrNull();
    if (stuck != null) {
      // Nobody else runs jobs in this process, so this one was interrupted.
      final attempts = stuck.attempts + 1;
      if (attempts >= kMaxJobAttempts) {
        await _fail(
          stuck,
          'Не вдалося обробити після $kMaxJobAttempts спроб'
          '${stuck.error == null ? '' : ': ${stuck.error}'}.',
        );
        _gaveUp = true;
        return null;
      }
      await _setJob(stuck.id, attempts: attempts);
      return _job(stuck.id);
    }
    return (db.select(db.aiJobsTable)
          ..where((t) => t.state.equals(AiJobState.queued))
          ..orderBy([
            (t) => OrderingTerm.asc(t.createdAt),
            (t) => OrderingTerm.asc(t.id),
          ])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<AiJob?> _nextWaitingWithInput() async {
    final jobs =
        await (db.select(db.aiJobsTable)
              ..where((t) => t.state.isIn(AiJobState.waiting))
              ..orderBy([
                (t) => OrderingTerm.asc(t.createdAt),
                (t) => OrderingTerm.asc(t.id),
              ]))
            .get();
    for (final j in jobs) {
      if (!AiJobKind.recordsBatch(j.kind)) continue;
      final d = await _draftOf(j);
      if (d == null) continue;
      if ((await _pendingMessages(j, d)).isNotEmpty ||
          (await _unappliedAnswers(j, d)).isNotEmpty) {
        return j;
      }
    }
    return null;
  }

  Future<void> _guarded(AiJob job, {required bool resume}) async {
    try {
      if (resume) {
        await _resume(job);
      } else {
        await _start(job);
      }
    } on AiJobFailure catch (e) {
      await _fail(job, e.message);
    } on Object catch (e) {
      final fresh = await _job(job.id) ?? job;
      final attempts = fresh.attempts + 1;
      final text = _clip('$e');
      if (attempts >= kMaxJobAttempts) {
        await _setJob(job.id, attempts: attempts);
        await _fail(
          fresh,
          'Не вдалося обробити після $kMaxJobAttempts спроб: $text',
        );
        return;
      }
      // Try again later: a queued job stays queued, a waiting one waits again.
      await _setJob(
        job.id,
        state: resume ? job.state : AiJobState.queued,
        stage: resume ? job.stage : AiStage.queued,
        error: text,
        attempts: attempts,
      );
    }
  }

  static String _clip(String s) => s.length <= 300 ? s : '${s.substring(0, 300)}...';

  // ===========================================================================
  // Start (queued job)
  // ===========================================================================

  Future<void> _start(AiJob job) async {
    final stage = job.kind == AiJobKind.receipt ||
            job.kind == AiJobKind.screenshot ||
            job.kind == AiJobKind.photos
        ? AiStage.reading
        : AiStage.matching;
    await _setJob(job.id, state: AiJobState.running, stage: stage);
    await _status(job, stage);
    switch (job.kind) {
      case AiJobKind.receipt:
      case AiJobKind.bazaar:
        await _startDraftJob(job);
      case AiJobKind.photos:
        await _startPhotos(job);
      case AiJobKind.screenshot:
        await _startScreenshot(job);
      case AiJobKind.text:
        await _startText(job);
      default:
        throw AiJobFailure('Невідомий тип завдання: ${job.kind}.');
    }
  }

  /// [photo] is the receipt among the job's photos (default: the first) and
  /// [release] every photo of the job (default: the job's own blobs). [shots]
  /// are the bank screenshots sent in the same message ([solo]: the only
  /// receipt of it); default: those the hub left in the job's payload. After
  /// reading the receipt the one that fits its total is applied to the draft.
  Future<void> _startDraftJob(
    AiJob job, {
    AiBlob? photo,
    List<ScreenshotReading>? shots,
    bool solo = false,
    List<AiBlob> release = const [],
  }) async {
    final existing = await _draftOf(job);
    if (existing != null) {
      // A previous attempt got this far: no second extraction.
      await _status(job, AiStage.matching);
      final b = await _rebuild(job, existing);
      await _evaluate(job, b);
      return;
    }
    final payload = JobPayload.decode(job.payloadJson);
    final messageTime = await _messageTime(job, payload);
    final Map<String, dynamic> source;
    final blobs = <AiBlob>[];
    ScreenshotReading? screenshot;
    if (job.kind == AiJobKind.bazaar) {
      final text = payload.text ?? await _messageBody(payload.messageId) ?? '';
      source = {'text': text};
    } else {
      blobs.addAll(release.isNotEmpty ? release : await _blobsOf(job, payload));
      final first =
          photo ?? blobs.where((b) => (b.data ?? '').isNotEmpty).firstOrNull;
      if (first == null || (first.data ?? '').isEmpty) {
        throw const AiJobFailure('Фото чека не знайдено: надішліть його ще раз.');
      }
      final receipt = await extractor.extract(
        base64Decode(first.data!),
        mime: first.mime,
      );
      source = {'receipt': receipt.toJson()};
      screenshot = pickScreenshot(
        shots ?? [for (final s in payload.screenshots) ScreenshotReading.fromJson(s)],
        receipt.total,
        solo: shots != null ? solo : payload.receiptCount == 1,
      );
    }
    await _status(job, AiStage.matching);
    final b = await _builder.build(
      job: job,
      kind: job.kind,
      source: source,
      overrides: {
        if (screenshot != null && screenshot.hasAnything) 'screenshot': screenshot.toJson(),
      },
      messageTime: messageTime,
    );
    await _saveDraft(job, b.card);
    await _releasePhotos(blobs);
    await _evaluate(job, b);
  }

  Future<DraftBuild> _rebuild(AiJob job, DraftCard d) async {
    final payload = JobPayload.decode(job.payloadJson);
    return _builder.build(
      job: job,
      kind: d.jobKind,
      source: d.source,
      overrides: Map<String, dynamic>.from(d.overrides),
      messageTime: await _messageTime(job, payload),
      previous: d,
    );
  }

  // ===========================================================================
  // Decisions after a (re)build
  // ===========================================================================

  /// Saves the draft, refreshes the question card and chooses the next state:
  /// ask, wait for Confirm (draft-first), or commit.
  Future<void> _evaluate(AiJob job, DraftBuild b) async {
    final d = b.card;
    final open = b.questions.isNotEmpty;
    final pending = d.pendingLines.isNotEmpty;
    final sum = d.sum;
    final sumBad = pending && sum != null && !sum.ok;
    if (sumBad) d.confirmed = false;
    await _saveDraft(job, d);
    await _syncQuestions(job, b.questions);
    await _sumMessage(job, d, sumBad);

    if (sumBad) {
      await _wait(job, open);
      return;
    }
    // Auto mode writes what is certain. A line whose category is only the
    // model's guess (below 0.8) waits for the user's Confirm like a first receipt.
    final guessed = d.pendingLines.any(
      (l) => l.suggested && (l.confidence ?? 0) < autoSuggestConfidence,
    );
    final auto = !await settings.draftFirstActive() && !guessed;
    if (open) {
      // Auto mode: write the obvious lines now and ask about the rest.
      if (auto && d.blockers.isEmpty) {
        await _commit(job, d);
      } else {
        await _wait(job, true);
      }
      return;
    }
    if (auto || d.confirmed) {
      await _commit(job, d);
    } else {
      await _wait(job, false);
    }
  }

  /// A suggested category at or above this is written in auto mode without asking.
  static const double autoSuggestConfidence = 0.8;

  Future<void> _wait(AiJob job, bool needsInput) async {
    final stage = AiStage.waiting;
    await _setJob(
      job.id,
      state: needsInput ? AiJobState.needsInput : AiJobState.draftReady,
      stage: stage,
      error: null,
    );
    await _status(job, stage);
  }

  /// Writes a question card for the questions that are not already waiting for
  /// an answer. Round `n` of the job has the derived id `question|n`.
  Future<void> _syncQuestions(AiJob job, List<Question> needed) async {
    if (needed.isEmpty) return;
    final msgs = await _questionMessages(job);
    final waiting = <String>{};
    for (final m in msgs) {
      for (final q in _card(m).questions) {
        if (q.answer == null) waiting.add(q.id);
      }
    }
    final toAsk = [
      for (final q in needed)
        if (!waiting.contains(q.id)) q,
    ];
    if (toAsk.isEmpty) return;
    // The questions themselves are in the card (the widget lists them): a body
    // that repeated them showed every question twice.
    await _putMessage(
      deriveId(job.id, 'question', msgs.length),
      job,
      role: AiRole.assistant,
      kind: AiMessageKind.question,
      body: toAsk.length == 1 ? 'Потрібна ваша відповідь:' : 'Потрібні ваші відповіді:',
      contentJson: jsonEncode(QuestionCard(toAsk).toJson()),
    );
  }

  Future<void> _sumMessage(AiJob job, DraftCard d, bool bad) async {
    final id = deriveId(job.id, 'error-sum');
    if (bad) {
      final s = d.sum!;
      final text = s.expected == null
          ? 'Не вдалося прочитати суму чека: нічого не записано.'
          : 'Суми не збігаються: рядки дають ${fmtMoney(s.linesSum)}, '
                'у чеку ${fmtMoney(s.expected!)} (різниця ${fmtMoney(s.difference)}). '
                'Нічого не записано: виправте рядки.';
      await _putMessage(
        id,
        job,
        role: AiRole.assistant,
        kind: AiMessageKind.error,
        body: text,
      );
    } else if (await _message(id) != null) {
      await _putMessage(
        id,
        job,
        role: AiRole.assistant,
        kind: AiMessageKind.text,
        body: 'Суму перевірено: розбіжності немає.',
      );
    }
  }

  // ===========================================================================
  // Resume (waiting job with new input)
  // ===========================================================================

  Future<void> _resume(AiJob job) async {
    final d = await _draftOf(job);
    if (d == null) throw const AiJobFailure('Чернетку не знайдено.');
    await _setJob(job.id, state: AiJobState.running, stage: AiStage.matching);
    await _status(job, AiStage.matching);

    var userConfirmed = false;
    for (final m in await _pendingMessages(job, d)) {
      d.handled = [...d.handled, m.id];
      if (m.kind != AiMessageKind.confirm) continue;
      final decision = _decision(m);
      if (decision == null) continue;
      if (!decision.confirm) {
        await _rejectJob(job, d);
        return;
      }
      userConfirmed = true;
      for (final e in decision.edits) {
        final ov = _lineOv(d, e.index);
        if (e.categoryId != null) ov['category_id'] = e.categoryId;
        if (e.quantity != null) ov['quantity'] = e.quantity;
        if (e.unitPrice != null) ov['unit_price'] = e.unitPrice;
      }
    }
    if (userConfirmed) {
      d.confirmed = true;
      d.userConfirmed = true;
    }
    for (final entry in await _unappliedAnswers(job, d)) {
      final keep = await _applyAnswer(d, entry.question);
      d.applied = [...d.applied, entry.key];
      if (!keep) {
        await _cancelJob(job, d, 'Пропустив: нічого не записано.');
        return;
      }
    }
    final b = await _rebuild(job, d);
    if (userConfirmed && b.questions.isNotEmpty) {
      await _putMessage(
        deriveId(job.id, 'note', d.handled.length),
        job,
        role: AiRole.assistant,
        kind: AiMessageKind.text,
        body: 'Спочатку дайте відповідь на питання, потім я запишу чек.',
      );
    }
    await _evaluate(job, b);
  }

  Future<void> _rejectJob(AiJob job, DraftCard d) async {
    final wrote = d.lines.any((l) => l.committed);
    await _cancelJob(
      job,
      d,
      wrote
          ? 'Відхилено. Частину рядків уже записано: скасуйте пакет кнопкою Undo.'
          : 'Відхилено: нічого не записано.',
    );
  }

  Future<void> _cancelJob(AiJob job, DraftCard d, String text) async {
    await _saveDraft(job, d);
    await _putMessage(
      deriveId(job.id, 'note', 9999),
      job,
      role: AiRole.assistant,
      kind: AiMessageKind.text,
      body: text,
    );
    await _setJob(job.id, state: AiJobState.done, stage: AiStage.done, error: null);
    await _status(job, AiStage.done);
  }

  ConfirmDecision? _decision(AiMessage m) {
    try {
      final j = jsonDecode(m.contentJson);
      if (j is Map) return ConfirmDecision.fromJson(Map<String, dynamic>.from(j));
    } catch (_) {}
    return null;
  }

  Map<String, dynamic> _lineOv(DraftCard d, int index) {
    final lines = d.overrides['lines'] is Map
        ? Map<String, dynamic>.from(d.overrides['lines'] as Map)
        : <String, dynamic>{};
    final ov = lines['$index'] is Map
        ? Map<String, dynamic>.from(lines['$index'] as Map)
        : <String, dynamic>{};
    lines['$index'] = ov;
    d.overrides['lines'] = lines;
    return ov;
  }

  /// Turns the answer to [q] into learned rules / overrides on [d]. False: the
  /// answer means "do not record this".
  Future<bool> _applyAnswer(DraftCard d, Question q) async {
    final a = (q.answer ?? '').trim();
    final id = q.id;
    if (id.startsWith('weight:')) {
      final line = _lineOf(d, int.tryParse(id.substring(7)));
      if (line == null) return true;
      final w = parseWeightAnswer(a);
      if (w == null) return true; // asked again
      if (w.piece) {
        await _aliases.remember(line.name, unitOverride: 'piece');
      } else {
        await _aliases.remember(line.name, weightGramsDefault: w.grams);
      }
    } else if (id.startsWith('cat:')) {
      final line = _lineOf(d, int.tryParse(id.substring(4)));
      if (line == null) return true;
      // "Створити «Чорнослив» у «Їжа»": a NEW category under an existing group.
      final create = kCreateOption.firstMatch(a);
      if (create != null) {
        final group = await _groupByName(create.group(2)!);
        if (group != null) {
          final ov = _lineOv(d, line.index);
          ov['category_id'] = group.id;
          ov['new_name'] = create.group(1)!.trim();
          return true;
        }
      }
      final categoryId = await _categoryFromAnswer(line, a);
      if (categoryId == null) {
        // Nothing matches what was typed: say so and offer the nearest ones (the
        // next card has new text, so it is not the same question again).
        final miss = d.overrides['cat_miss'] is Map
            ? Map<String, dynamic>.from(d.overrides['cat_miss'] as Map)
            : <String, dynamic>{};
        miss['${line.index}'] = a;
        d.overrides['cat_miss'] = miss;
        return true;
      }
      // A group is not a product: only a real category is learned.
      if (!await _isGroup(categoryId)) {
        await _aliases.remember(line.name, categoryId: categoryId);
      }
      _lineOv(d, line.index)['category_id'] = categoryId;
    } else if (id == 'dup') {
      if (!_yes(a) && !RegExp('додати|add', caseSensitive: false).hasMatch(a)) {
        return false;
      }
      d.overrides['dup_ok'] = true;
    } else if (id == 'tender') {
      if (!_yes(a)) return false;
      d.overrides['tender_ok'] = true;
    } else if (id == 'mine') {
      final m = RegExp(r'\d{4}').firstMatch(a);
      if (m != null) d.overrides['mine_last4'] = m.group(0);
    } else if (id.startsWith('card:')) {
      final acc = await _accountFromAnswer(a);
      if (acc != null) {
        await _rules.set('card.${id.substring(5)}', {'account_id': acc.id});
      }
    } else if (id == 'cash_account') {
      final acc = await _accountFromAnswer(a);
      if (acc != null) {
        // Remembered per currency, and as the default for "готівкою" with no
        // currency, so the next message asks nothing.
        await _rules.set('cash.${acc.currency.toUpperCase()}', {'account_id': acc.id});
        await _rules.set('cash.default', {'account_id': acc.id});
      }
    } else if (id == 'pay_account') {
      final acc = await _accountFromAnswer(a);
      if (acc != null) d.overrides['use_account'] = acc.id;
    }
    return true;
  }

  DraftLine? _lineOf(DraftCard d, int? index) {
    for (final l in d.lines) {
      if (l.index == index) return l;
    }
    return null;
  }

  static bool _yes(String a) => RegExp(
    r'^(так|да|yes|y|ок|ok|добре|вірно|правильно|звісно)(?![\p{L}])',
    caseSensitive: false,
    unicode: true,
  ).hasMatch(a.trim());

  Future<String?> _categoryFromAnswer(DraftLine line, String answer) async {
    final key = normalizeReceiptText(answer);
    for (final c in line.candidates) {
      if (normalizeReceiptText(c.name) == key) return c.id;
    }
    // Free text: an existing category by name.
    final res = await CategoryResolver(db).resolve(answer, limit: 3);
    final best = res.best;
    if (best != null && best.score >= 0.7) return best.id;
    return null;
  }

  /// An existing group (a category with children) by its exact name.
  Future<BudgetCategory?> _groupByName(String name) async {
    final key = normalizeReceiptText(name);
    final all = await db.select(db.budgetCategoriesTable).get();
    final parents = {for (final c in all) ?c.parentId};
    for (final c in all) {
      if (parents.contains(c.id) && normalizeReceiptText(c.name) == key) return c;
    }
    return null;
  }

  /// A group: has children and none of them is a same-name price variant (those
  /// are wrappers, which are real products).
  Future<bool> _isGroup(String categoryId) async {
    final cat = await (db.select(db.budgetCategoriesTable)
          ..where((t) => t.id.equals(categoryId)))
        .getSingleOrNull();
    final kids = await (db.select(db.budgetCategoriesTable)
          ..where((t) => t.parentId.equals(categoryId)))
        .get();
    if (cat == null || kids.isEmpty) return false;
    final key = normalizeReceiptText(cat.name);
    return !kids.any((k) => normalizeReceiptText(k.name) == key);
  }

  Future<BudgetAccount?> _accountFromAnswer(String answer) async {
    final accounts = await db.select(db.budgetAccountsTable).get();
    final hit = matchAccountName(answer, accounts, (a) => a.name);
    return hit.length == 1 ? hit.first : null;
  }

  // ===========================================================================
  // Commit
  // ===========================================================================

  /// Writes every line that is ready (no open question) in ONE transaction:
  /// validate (I1-I4), plan prices, create transactions, journal the batch,
  /// write the result card and the job state. Nothing is written when the
  /// validator finds an error.
  Future<void> _commit(AiJob job, DraftCard d) async {
    final lines = [
      for (final l in d.lines)
        if (!l.committed && !l.skipped && !l.needsAnswer) l,
    ];
    if (d.blockers.isNotEmpty) {
      await _wait(job, true);
      return;
    }
    if (lines.isEmpty) {
      await _finish(job, d);
      return;
    }
    await _setJob(job.id, state: AiJobState.committing, stage: AiStage.saving);
    await _status(job, AiStage.saving);
    final payload = JobPayload.decode(job.payloadJson);
    final failure = await db.transaction<String?>(() async {
      // Plans + validation first: an error writes nothing.
      final plans = <int, PricePlan?>{};
      final planned = <PlannedTransaction>[];
      final newCats = <PlannedCategory>[];
      final moves = <PlannedMove>[];
      for (final l in lines) {
        final plan = await _planFor(l, d);
        plans[l.index] = plan;
        String? target = l.categoryId;
        if (plan != null) {
          if (plan.kind == PlanKind.reuseLeaf) {
            target = plan.leafId;
          } else {
            final temp = 'new:${l.index}';
            var parent = plan.newLeaf?.parentId;
            if (plan.kind == PlanKind.wrapper) {
              final wrap = 'wrap:${l.index}';
              newCats.add(PlannedCategory(id: wrap, parentId: plan.wrapper!.parentId));
              moves.add(PlannedMove(plan.oldLeafId!, wrap));
              parent = wrap;
            }
            newCats.add(
              PlannedCategory(
                id: temp,
                parentId: parent,
                accountCountId: plan.newLeaf?.accountCountId,
                accountUseId: plan.newLeaf?.accountUseId,
              ),
            );
            target = temp;
          }
        }
        planned.add(
          PlannedTransaction(
            name: txNameFor(d.merchant, l.displayName),
            categoryId: target,
            quantity: l.quantity ?? 0,
            amount: l.amount,
            date: d.at,
            rateCount: l.rateCount,
            rateInteract: l.rateInteract,
            // Only planned leaves are checked against how it was paid.
            accountCountId: plan == null ? null : l.countAccountId,
            accountUseId: plan == null ? null : d.useAccountId,
            checkDuplicate: false,
          ),
        );
      }
      final everything =
          lines.length == d.lines.where((l) => !l.skipped).length &&
          !d.lines.any((l) => l.committed);
      final result = await InvariantValidator(db).validate(
        transactions: planned,
        newCategories: newCats,
        moves: moves,
        expectedTotal: everything ? d.sum?.expected : null,
      );
      if (!result.ok) {
        return [for (final e in result.errors) '${e.code}: ${e.message}'].join('\n');
      }

      // Writes.
      final batchId = await _batches.startBatch(
        jobId: job.id,
        threadId: job.threadId,
        messageId: payload.messageId,
        summary: 'Чек ${d.merchant ?? ''}'.trim(),
      );
      d.batchId = batchId;
      final actionId = await _ensureAction(job, d, batchId);
      for (final l in lines) {
        final base = 10 + l.index * 10;
        final plan = plans[l.index];
        var leafId = l.categoryId!;
        if (plan != null) {
          final applied = await _planner.apply(plan);
          leafId = applied.leafId;
          // Journal in the order they happened (wrapper, move, new leaf): undo
          // runs it backwards, so the leaf goes first and the wrapper last.
          var k = 0;
          Future<void> created(String id) => _batches.record(
            batchId,
            position: base + k++,
            entityType: AiEntity.category,
            entityId: id,
          );
          final ids = applied.createdIds;
          if (plan.kind == PlanKind.wrapper &&
              ids.length == 2 &&
              applied.movedIds.isNotEmpty) {
            await created(ids[0]);
            await _batches.record(
              batchId,
              position: base + k++,
              entityType: AiEntity.category,
              entityId: applied.movedIds.first,
              op: AiOp.reparent,
              before: {'parent_id': plan.wrapper!.parentId},
            );
            await created(ids[1]);
          } else {
            for (final c in ids) {
              await created(c);
            }
          }
        }
        final txId = await _budget.createTransaction(
          id: deriveId(job.id, 'tx', l.index),
          categoryId: leafId,
          name: txNameFor(d.merchant, l.displayName),
          actionId: actionId,
          date: d.at,
          quantity: l.quantity,
          unitPrice: l.unitPrice,
          rateCount: l.rateCount,
          rateInteract: l.rateInteract,
          updateAccountRate: false,
        );
        await _batches.record(
          batchId,
          position: base + 9,
          entityType: AiEntity.transaction,
          entityId: txId,
        );
        final leaf = await (db.select(db.budgetCategoriesTable)
              ..where((t) => t.id.equals(leafId)))
            .getSingleOrNull();
        l.categoryId = leafId;
        l.categoryName = leaf?.name ?? l.categoryName;
        l.transactionId = txId;
        l.committed = true;
        // The user saw and confirmed this line: the next receipt with the same
        // printed name needs no model.
        if (d.userConfirmed && l.suggested) await _aliases.remember(l.name, categoryId: leafId);
      }
      if (d.userConfirmed && !d.counted) {
        await settings.incrementConfirmed();
        d.counted = true;
      }
      await _finish(job, d);
      return null;
    });
    if (failure != null) {
      d.confirmed = false;
      await _saveDraft(job, d);
      await _putMessage(
        deriveId(job.id, 'error-commit'),
        job,
        role: AiRole.assistant,
        kind: AiMessageKind.error,
        body: 'Нічого не записано.\n$failure',
      );
      await _wait(job, false);
    }
  }

  /// Result card, draft, and the final state (done, or waiting for answers).
  Future<void> _finish(AiJob job, DraftCard d) async {
    final allDone = d.lines.every((l) => l.committed || l.skipped);
    await _saveDraft(job, d);
    await _putResult(job, d);
    await _setJob(
      job.id,
      state: allDone ? AiJobState.done : AiJobState.needsInput,
      stage: allDone ? AiStage.done : AiStage.waiting,
      error: null,
    );
    await _status(job, allDone ? AiStage.done : AiStage.waiting);
  }

  /// The price plan of a line: null when the category is used as it is
  /// (snacks, budget / percent categories).
  Future<PricePlan?> _planFor(DraftLine l, DraftCard d) async {
    if (l.snacks || l.unit == 'month' || l.unit == 'percent') return null;
    final price = l.unitPrice;
    if (price == null || !(price > 0)) return null;
    if (l.oneOffGroupId != null) {
      return _planner.planOneOff(
        name: l.displayName,
        groupId: l.oneOffGroupId!,
        cost: price,
        accountCountId: l.countAccountId,
        accountUseId: d.useAccountId,
      );
    }
    return _planner.plan(
      categoryId: l.categoryId!,
      newPrice: price,
      accountCountId: l.countAccountId,
      accountUseId: d.useAccountId,
    );
  }

  /// The action of the purchase: the drafted one while it exists, else a fresh
  /// match, else a new «🛒 У магазин» / «🍓 Базар» (T4).
  Future<String> _ensureAction(AiJob job, DraftCard d, String batchId) async {
    final drafted = d.action;
    if (drafted != null && !drafted.isNew && drafted.id != null) {
      if (await (db.select(db.actionsTable)
              ..where((t) => t.id.equals(drafted.id!)))
          .getSingleOrNull() !=
          null) {
        return drafted.id!;
      }
    }
    final bazaar = d.jobKind == AiJobKind.bazaar;
    final m = await _matcher.match(d.at, bazaarMarker: bazaar ? 'базар' : null);
    if (m != null) return m.actionId;
    final id = await _creator.create(
      name: drafted?.name ?? (bazaar ? kBazaarActionName : kShopActionName),
      receiptUtc: d.at,
      id: deriveId(job.id, 'action'),
    );
    await _batches.record(
      batchId,
      position: 0,
      entityType: AiEntity.action,
      entityId: id,
    );
    return id;
  }

  // ===========================================================================
  // Messages: draft, result, status
  // ===========================================================================

  Future<void> _saveDraft(AiJob job, DraftCard d) => _putMessage(
    deriveId(job.id, 'draft'),
    job,
    role: AiRole.assistant,
    kind: AiMessageKind.draft,
    body: _draftText(d),
    contentJson: jsonEncode(d.toJson()),
  );

  Future<void> _putResult(AiJob job, DraftCard d) => _putMessage(
    deriveId(job.id, 'result'),
    job,
    role: AiRole.assistant,
    kind: AiMessageKind.result,
    body: _resultText(d),
    contentJson: jsonEncode({
      'v': 1,
      'batch_id': d.batchId,
      'currency': d.currency,
      'lines': [
        for (final l in d.lines)
          if (l.committed) l.toJson(),
      ],
      'open': d.lines.where((l) => !l.committed && !l.skipped).length,
    }),
  );

  static String _unitWord(String? u) => switch (u) {
    'kilogram' => 'кг',
    'piece' => 'шт',
    _ => '',
  };

  static String _lineText(DraftLine l, String currency) {
    final qty = l.quantity == null
        ? 'кількість ?'
        : '${fmtQty(l.quantity!)} ${_unitWord(l.unit)}'.trim();
    return '${l.name} → ${l.categoryName ?? '?'} → $qty → '
        '${fmtMoney(l.amount)} $currency';
  }

  String _draftText(DraftCard d) {
    final b = StringBuffer(
      d.jobKind == AiJobKind.bazaar
          ? 'Чернетка: базар'
          : 'Чернетка чека${d.merchant == null ? '' : ' ${d.merchant}'}',
    );
    for (final l in d.lines) {
      b.write('\n${l.index + 1}. ${_lineText(l, d.currency)}');
      if (l.skipped) b.write(' (пропущено)');
      if (l.newCategory) b.write(' [нова категорія]');
      if (l.priceChange) b.write(' [змінилась ціна]');
      if (l.needsAnswer) b.write(' [потрібна відповідь]');
    }
    final s = d.sum;
    if (s != null) {
      b.write(
        '\nРазом: ${fmtMoney(s.linesSum)} ${d.currency}'
        '${s.expected == null ? '' : ' (чек: ${fmtMoney(s.expected!)})'} '
        '${s.ok ? '✓' : '✗'}',
      );
    }
    final a = d.action;
    if (a != null) {
      b.write('\nДія: ${a.name}${a.isNew ? ' (буде створено)' : ''}');
    }
    return b.toString();
  }

  String _resultText(DraftCard d) {
    final done = [
      for (final l in d.lines)
        if (l.committed) l,
    ];
    final open = [
      for (final l in d.lines)
        if (!l.committed && !l.skipped) l,
    ];
    final b = StringBuffer(
      'Записано${d.batchId == null ? '' : ' (пакет ${d.batchId!.substring(0, 8)})'}:',
    );
    for (final l in done) {
      b.write('\n• ${_lineText(l, d.currency)}');
    }
    final total = done.fold(0.0, (a, l) => a + l.amount);
    b.write('\nРазом: ${fmtMoney(total)} ${d.currency}');
    if (d.notes.isNotEmpty) b.write('\nПрипущення: ${d.notes.join(' ')}');
    if (open.isNotEmpty) {
      b.write(
        '\nЩе чекають відповіді (${open.length}): '
        '${open.map((l) => l.name).join(', ')}',
      );
    }
    return b.toString();
  }

  /// ONE status line per job, updated in place; also `ai_jobs.stage`.
  Future<void> _status(AiJob job, String stage) async {
    await _setJob(job.id, stage: stage);
    await _putMessage(
      deriveId(job.id, 'status'),
      job,
      role: AiRole.assistant,
      kind: AiMessageKind.status,
      body: stage,
      contentJson: jsonEncode({'v': 1, 'stage': stage}),
    );
  }

  /// Insert if absent, else update in place (keeping its creation time).
  Future<void> _putMessage(
    String id,
    AiJob job, {
    required String role,
    required String kind,
    required String body,
    String contentJson = '{}',
  }) async {
    final existing = await _message(id);
    final now = _stamp();
    if (existing == null) {
      await db
          .into(db.aiMessagesTable)
          .insert(
            AiMessagesTableCompanion.insert(
              id: id,
              threadId: job.threadId,
              role: Value(role),
              kind: Value(kind),
              body: Value(body),
              contentJson: Value(contentJson),
              jobId: Value(job.id),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await (db.update(db.aiThreadsTable)..where((t) => t.id.equals(job.threadId)))
          .write(AiThreadsTableCompanion(updatedAt: Value(now)));
      return;
    }
    if (existing.body == body &&
        existing.kind == kind &&
        existing.contentJson == contentJson) {
      return;
    }
    await (db.update(db.aiMessagesTable)..where((t) => t.id.equals(id))).write(
      AiMessagesTableCompanion(
        kind: Value(kind),
        body: Value(body),
        contentJson: Value(contentJson),
        updatedAt: Value(now),
      ),
    );
  }

  Future<AiMessage?> _message(String id) => (db.select(
    db.aiMessagesTable,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<AiJob?> _job(String id) => (db.select(
    db.aiJobsTable,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Only the passed fields change; `error: null` clears the error text.
  Future<void> _setJob(
    String id, {
    String? state,
    String? stage,
    Object? error = _keep,
    int? attempts,
  }) async {
    await (db.update(db.aiJobsTable)..where((t) => t.id.equals(id))).write(
      AiJobsTableCompanion(
        state: state == null ? const Value.absent() : Value(state),
        stage: stage == null ? const Value.absent() : Value(stage),
        error: identical(error, _keep) ? const Value.absent() : Value(error as String?),
        attempts: attempts == null ? const Value.absent() : Value(attempts),
        updatedAt: Value(_stamp()),
      ),
    );
  }

  static const Object _keep = Object();

  Future<void> _fail(AiJob job, String message) async {
    await _putMessage(
      deriveId(job.id, 'error-fail'),
      job,
      role: AiRole.assistant,
      kind: AiMessageKind.error,
      body: message,
    );
    await _setJob(job.id, state: AiJobState.failed, stage: 'Failed', error: message);
    await _status(job, 'Failed');
  }

  // ===========================================================================
  // Reading rows
  // ===========================================================================

  Future<DraftCard?> _draftOf(AiJob job) async {
    final m = await _message(deriveId(job.id, 'draft'));
    if (m == null) return null;
    try {
      final j = jsonDecode(m.contentJson);
      if (j is Map) return DraftCard.fromJson(Map<String, dynamic>.from(j));
    } catch (_) {}
    return null;
  }

  Future<List<AiMessage>> _questionMessages(AiJob job) =>
      (db.select(db.aiMessagesTable)
            ..where(
              (t) =>
                  t.jobId.equals(job.id) & t.kind.equals(AiMessageKind.question),
            )
            ..orderBy([
              (t) => OrderingTerm.asc(t.createdAt),
              (t) => OrderingTerm.asc(t.id),
            ]))
          .get();

  QuestionCard _card(AiMessage m) {
    try {
      final j = jsonDecode(m.contentJson);
      if (j is Map) return QuestionCard.fromJson(Map<String, dynamic>.from(j));
    } catch (_) {}
    return const QuestionCard([]);
  }

  /// Answered questions of the job that were not applied yet.
  Future<List<({String key, Question question})>> _unappliedAnswers(
    AiJob job,
    DraftCard d,
  ) async {
    final out = <({String key, Question question})>[];
    for (final m in await _questionMessages(job)) {
      for (final q in _card(m).questions) {
        final key = '${m.id}:${q.id}';
        if (q.answer != null && !d.applied.contains(key)) {
          out.add((key: key, question: q));
        }
      }
    }
    return out;
  }

  /// User messages of the job (Confirm / Reject and typed answers) that were
  /// not processed yet, oldest first.
  Future<List<AiMessage>> _pendingMessages(AiJob job, DraftCard d) async {
    final payload = JobPayload.decode(job.payloadJson);
    final rows =
        await (db.select(db.aiMessagesTable)
              ..where(
                (t) =>
                    t.jobId.equals(job.id) &
                    t.role.equals(AiRole.user) &
                    t.kind.isIn([AiMessageKind.confirm, AiMessageKind.text]),
              )
              ..orderBy([
                (t) => OrderingTerm.asc(t.createdAt),
                (t) => OrderingTerm.asc(t.id),
              ]))
            .get();
    return [
      for (final m in rows)
        if (m.id != payload.messageId && !d.handled.contains(m.id)) m,
    ];
  }

  Future<DateTime> _messageTime(AiJob job, JobPayload payload) async {
    final id = payload.messageId;
    final m = id == null ? null : await _message(id);
    return dateTimeFromDb(m?.createdAt) ??
        dateTimeFromDb(job.createdAt) ??
        _clock().toUtc();
  }

  Future<String?> _messageBody(String? id) async =>
      id == null ? null : (await _message(id))?.body;

  Future<List<AiBlob>> _blobsOf(AiJob job, JobPayload payload) async {
    final out = <AiBlob>[];
    for (final id in payload.blobIds) {
      final b = await (db.select(
        db.aiBlobsTable,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (b != null) out.add(b);
    }
    if (out.isEmpty) {
      out.addAll(
        await (db.select(db.aiBlobsTable)
              ..where((t) => t.jobId.equals(job.id))
              ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
            .get(),
      );
    }
    return out;
  }

  /// The hub keeps the original: only AFTER [storeOriginal] succeeded the photo
  /// row is marked stored and its bytes dropped (that edit syncs, so every
  /// device frees its copy).
  Future<void> _releasePhotos(List<AiBlob> blobs) async {
    final store = storeOriginal;
    if (store == null) return;
    for (final b in blobs) {
      if (b.storedOnHubAt != null || (b.data ?? '').isEmpty) continue;
      await store(b);
      final now = _stamp();
      await (db.update(db.aiBlobsTable)..where((t) => t.id.equals(b.id))).write(
        AiBlobsTableCompanion(
          storedOnHubAt: Value(now),
          data: const Value(null),
          updatedAt: Value(now),
        ),
      );
    }
  }

  // ===========================================================================
  // A2. One message, several photos
  // ===========================================================================

  /// What a photo says when it is a bank screenshot (the amount charged in ₴
  /// and/or the bank's rate); null for a receipt. Without an OCR service the
  /// photos cannot be told apart, so each one counts as a receipt.
  Future<ScreenshotReading?> _screenshotReading(AiBlob b) async {
    try {
      final text = await _ocrText(base64Decode(b.data!), b.mime);
      final reading = parseBankScreenshot(text);
      return reading.hasAnything ? reading : null;
    } on AiJobFailure {
      return null;
    }
  }

  /// The photos of one message: a receipt and its bank screenshot in any
  /// order. The screenshot's amounts/rate go into the receipt's draft (the
  /// rates of that transaction only); a screenshot alone is applied to the
  /// receipt recorded earlier, as a separate screenshot job would.
  Future<void> _startPhotos(AiJob job) async {
    final payload = JobPayload.decode(job.payloadJson);
    final blobs = [
      for (final b in await _blobsOf(job, payload))
        if ((b.data ?? '').isNotEmpty) b,
    ];
    if (blobs.isEmpty) {
      throw const AiJobFailure('Фото не знайдено: надішліть їх ще раз.');
    }
    final receipts = <AiBlob>[];
    final shotBlobs = <AiBlob>[];
    final shots = <ScreenshotReading>[];
    for (final b in blobs) {
      final reading = await _screenshotReading(b);
      if (reading == null) {
        receipts.add(b);
      } else {
        shotBlobs.add(b);
        shots.add(reading);
      }
    }
    if (receipts.length == 1) {
      await _startDraftJob(
        job,
        photo: receipts.first,
        shots: shots,
        solo: true,
        release: blobs,
      );
      return;
    }
    if (receipts.isEmpty && shots.length == 1) {
      await _status(job, AiStage.matching);
      await _applyScreenshot(job, payload, blobs, shots.first);
      return;
    }
    // Several receipts, or several screenshots alone: one job each, so every
    // receipt has its own draft, Confirm and Undo. A receipt job gets all the
    // screenshots and takes the one whose amount fits its total.
    final kids = <({String kind, JobPayload payload})>[
      if (receipts.isNotEmpty)
        for (final r in receipts)
          (
            kind: AiJobKind.receipt,
            payload: JobPayload(
              messageId: payload.messageId,
              blobIds: [r.id],
              screenshots: [for (final s in shots) s.toJson()],
              receiptCount: receipts.length,
            ),
          )
      else
        for (final s in shotBlobs)
          (
            kind: AiJobKind.screenshot,
            payload: JobPayload(messageId: payload.messageId, blobIds: [s.id]),
          ),
    ];
    await _spawn(job, kids);
    final what = receipts.isNotEmpty
        ? '${receipts.length} чеків${shots.isEmpty ? '' : ' і ${shots.length} скріншотів'}'
        : '${shots.length} скріншотів';
    await _replyAndFinish(
      job,
      'Знайшов $what. Обробляю кожен чек окремо, по черзі.',
    );
    // The screenshots are already read; the receipts keep their bytes until
    // their own job is done.
    if (receipts.isNotEmpty) await _releasePhotos(shotBlobs);
  }

  /// Creates the follow-up jobs of [parent] in the same thread. Their ids are
  /// derived from the parent, so running this again adds nothing.
  Future<void> _spawn(
    AiJob parent,
    List<({String kind, JobPayload payload})> kids,
  ) async {
    for (var i = 0; i < kids.length; i++) {
      final now = _stamp();
      await db
          .into(db.aiJobsTable)
          .insert(
            AiJobsTableCompanion.insert(
              id: deriveId(parent.id, 'job', i),
              threadId: parent.threadId,
              kind: Value(kids[i].kind),
              state: const Value(AiJobState.queued),
              stage: const Value(AiStage.queued),
              payloadJson: Value(kids[i].payload.encode()),
              createdAt: now,
              updatedAt: now,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
  }

  // ===========================================================================
  // B. Bank screenshot
  // ===========================================================================

  Future<void> _startScreenshot(AiJob job) async {
    final payload = JobPayload.decode(job.payloadJson);
    final blobs = await _blobsOf(job, payload);
    final first = blobs.where((b) => (b.data ?? '').isNotEmpty).firstOrNull;
    if (first == null) {
      throw const AiJobFailure('Скріншот не знайдено: надішліть його ще раз.');
    }
    final bytes = base64Decode(first.data!);
    final text = await _ocrText(bytes, first.mime);
    await _status(job, AiStage.matching);
    final reading = parseBankScreenshot(text);
    if (!reading.hasAnything) {
      await _replyAndFinish(
        job,
        'Не вдалося прочитати суму та курс на скріншоті. '
        'Надішліть чіткіший знімок.',
      );
      await _releasePhotos(blobs);
      return;
    }
    await _applyScreenshot(job, payload, blobs, reading);
  }

  /// A late screenshot: new rates for the newest recorded receipt it fits.
  Future<void> _applyScreenshot(
    AiJob job,
    JobPayload payload,
    List<AiBlob> blobs,
    ScreenshotReading reading,
  ) async {
    final target = await _batchForScreenshot(job, reading);
    if (target == null) {
      await _replyAndFinish(
        job,
        'Не знайшов записаного чека, до якого належить цей скріншот'
        '${reading.countAmount == null ? '' : ' (сума ${fmtMoney(reading.countAmount!)})'}. '
        'Спочатку надішліть чек.',
      );
      await _releasePhotos(blobs);
      return;
    }

    final accounts = await db.select(db.budgetAccountsTable).get();
    final base = (await _budget.settings()).baseCurrency.toUpperCase();
    final market = <String, double>{};
    for (final a in accounts) {
      market.putIfAbsent(a.currency.toUpperCase(), () => a.rateToBase);
    }
    String? currencyOf(String? id) {
      for (final a in accounts) {
        if (a.id == id) return a.currency;
      }
      return null;
    }

    final txs = [
      for (final t in await _batchTransactions(target))
        if (currencyOf(t.accountCountId) != null && currencyOf(t.accountUseId) != null) t,
    ];
    final fxByPair = <String, ReceiptFx>{};
    ReceiptFx fxFor(BudgetTransaction t) => fxByPair.putIfAbsent(
      '${t.accountCountId}|${t.accountUseId}',
      () {
        final count = currencyOf(t.accountCountId)!;
        final use = currencyOf(t.accountUseId)!;
        final c = reading.countAmount;
        final u = reading.useAmount;
        if (c != null && u != null) {
          return recomputeWithScreenshot(
            countCurrency: count,
            useCurrency: use,
            countAmount: c,
            useAmount: u,
            marketEurRates: market,
            baseCurrency: base,
          );
        }
        return computeReceiptRates(
          countCurrency: count,
          useCurrency: use,
          screenshotRate: reading.rate,
          marketEurRates: market,
          baseCurrency: base,
        );
      },
    );
    final updates = [
      for (final t in txs)
        if (fxFor(t).resolved && fxFor(t).source == FxSource.screenshot) t,
    ];
    if (updates.isEmpty) {
      await _replyAndFinish(
        job,
        'У записаних рядках немає пари різних валют: курс зі скріншота не потрібен.',
      );
      await _releasePhotos(blobs);
      return;
    }

    await _setJob(job.id, state: AiJobState.committing, stage: AiStage.saving);
    await db.transaction(() async {
      final batch = await _batches.startBatch(
        jobId: job.id,
        threadId: job.threadId,
        messageId: payload.messageId,
        summary: 'Курс зі скріншота',
        index: 1,
      );
      var pos = 0;
      for (final t in updates) {
        final fx = fxFor(t);
        await _batches.record(
          batch,
          position: pos++,
          entityType: AiEntity.transaction,
          entityId: t.id,
          op: AiOp.update,
          before: {
            'name': t.name,
            'category_id': t.categoryId,
            'quantity': t.quantity,
            'unit_price': t.unitPrice,
            'rate_count': t.rateCount,
            'rate_interact': t.rateInteract,
          },
          after: {'rate_count': fx.rateCount, 'rate_interact': fx.rateInteract},
        );
        await _budget.updateTransaction(
          t.id,
          rateCount: fx.rateCount,
          rateInteract: fx.rateInteract,
          updateAccountRate: false,
        );
      }
      final shown = reading.rate ??
          (reading.useAmount! / reading.countAmount!);
      await _putMessage(
        deriveId(job.id, 'result'),
        job,
        role: AiRole.assistant,
        kind: AiMessageKind.result,
        body:
            'Курс зі скріншота застосовано: ${shown.toStringAsFixed(4)} '
            'до ${updates.length} записів (пакет ${batch.substring(0, 8)}). '
            'Курс рахунків не змінено.',
        contentJson: jsonEncode({
          'v': 1,
          'batch_id': batch,
          'updated': [for (final t in updates) t.id],
        }),
      );
      await _setJob(job.id, state: AiJobState.done, stage: AiStage.done, error: null);
      await _status(job, AiStage.done);
    });
    await _releasePhotos(blobs);
  }

  Future<String> _ocrText(Uint8List bytes, String mime) async {
    final client = ocr;
    if (client != null) return (await client.ocr(bytes, mime: mime)).text;
    final ex = extractor;
    if (ex is OcrLlmExtractor) {
      return (await ex.extractWithText(bytes, mime: mime)).ocrText;
    }
    throw const AiJobFailure('Немає служби OCR для скріншота.');
  }

  /// The newest committed, not undone receipt batch of the thread whose total
  /// matches the screenshot's shop amount (any newest one when it has none).
  Future<String?> _batchForScreenshot(AiJob job, ScreenshotReading r) async {
    final batches = await db
        .customSelect(
          'SELECT b.id AS id FROM ai_batches b JOIN ai_jobs j ON j.id = b.job_id '
          "WHERE b.thread_id = ? AND b.undone_at IS NULL AND j.id <> ? "
          "AND j.kind IN ('receipt', 'bazaar', 'photos') ORDER BY b.created_at DESC, b.id DESC",
          variables: [Variable.withString(job.threadId), Variable.withString(job.id)],
        )
        .get();
    for (final row in batches) {
      final id = row.read<String>('id');
      final c = r.countAmount;
      if (c == null) return id;
      final total = [
        for (final t in await _batchTransactions(id)) _amountOf(t),
      ].fold(0.0, (a, v) => a + v);
      final tol = (c * 0.005) > 1.0 ? c * 0.005 : 1.0;
      if ((total - c).abs() <= tol) return id;
    }
    return null;
  }

  Future<List<BudgetTransaction>> _batchTransactions(String batchId) async {
    final items = await _batches.items(batchId);
    final out = <BudgetTransaction>[];
    for (final it in items) {
      if (it.entityType != AiEntity.transaction || it.op != AiOp.insert) continue;
      final t = await (db.select(
        db.budgetTransactionsTable,
      )..where((x) => x.id.equals(it.entityId))).getSingleOrNull();
      if (t != null) out.add(t);
    }
    return out;
  }

  static double _amountOf(BudgetTransaction t) =>
      t.isAmount ? t.quantity : t.unitPrice * t.quantity;

  // ===========================================================================
  // D. Free text: transfer or a correction of the pending draft
  // ===========================================================================

  Future<void> _startText(AiJob job) async {
    final payload = JobPayload.decode(job.payloadJson);
    final text = (payload.text ?? await _messageBody(payload.messageId) ?? '').trim();
    final transfer = parseTransferText(text);
    if (transfer != null) {
      await _transfer(job, transfer);
      return;
    }
    final accounts = await db.select(db.budgetAccountsTable).get();
    final typed = parseTypedExpense(
      text,
      now: (await _messageTime(job, payload)).toLocal(),
      accountNames: [
        for (final a in accounts)
          a.name.replaceFirst(RegExp(r'^\s*\([^)]*\)\s*'), '').trim().toLowerCase(),
      ],
    );
    final target = await _pendingDraftJob(job);
    // While a draft waits, "рядок 2 ..." is a correction of it; a message that
    // reads like a purchase (a verb, cash, a currency, a day, an account, several
    // items) is a new one.
    if (typed != null && (target == null || typed.explicit)) {
      await _startTyped(job, typed, accounts);
      return;
    }
    if (target != null) {
      await _correct(job, text, target.job, target.draft);
      return;
    }
    await _replyAndFinish(
      job,
      'Не зрозумів. Надішліть фото чека, нотатку з базару або напишіть, '
      'наприклад: «купив каву 150 готівкою» чи «перевів 100 з ФОП на Monobank».',
    );
  }

  /// A purchase told in words: the same draft, questions and Confirm as a photo.
  Future<void> _startTyped(
    AiJob job,
    TypedExpense typed,
    List<BudgetAccount> accounts,
  ) async {
    final existing = await _draftOf(job);
    if (existing != null) {
      await _status(job, AiStage.matching);
      await _evaluate(job, await _rebuild(job, existing));
      return;
    }
    final payload = JobPayload.decode(job.payloadJson);
    final account = typed.accountIndex == null ? null : accounts[typed.accountIndex!];
    await _status(job, AiStage.matching);
    final b = await _builder.build(
      job: job,
      kind: AiJobKind.receipt,
      source: {
        'receipt': typed.toReceipt(typed.currency ?? 'TRY').toJson(),
        'typed': {
          'cash': typed.cash,
          'currency': typed.currency,
          'income': typed.income,
          'account_id': account?.id,
          'unparsed': typed.unparsed,
        },
      },
      overrides: {},
      messageTime: await _messageTime(job, payload),
    );
    // The typed message itself is the request, not an answer to handle later.
    final origin = payload.messageId;
    if (origin != null) b.card.handled = [...b.card.handled, origin];
    await _saveDraft(job, b.card);
    await _evaluate(job, b);
  }

  Future<void> _replyAndFinish(AiJob job, String text) async {
    await _putMessage(
      deriveId(job.id, 'reply'),
      job,
      role: AiRole.assistant,
      kind: AiMessageKind.text,
      body: text,
    );
    await _setJob(job.id, state: AiJobState.done, stage: AiStage.done, error: null);
    await _status(job, AiStage.done);
  }

  Future<void> _transfer(AiJob job, TransferRequest req) async {
    final accounts = await db.select(db.budgetAccountsTable).get();
    final from = matchAccountName(req.from, accounts, (a) => a.name);
    final to = matchAccountName(req.to, accounts, (a) => a.name);
    String names() => accounts.map((a) => a.name).join(', ');
    if (from.length != 1 || to.length != 1) {
      final which = from.length != 1 ? req.from : req.to;
      await _replyAndFinish(
        job,
        'Не вдалося однозначно знайти рахунок «$which». '
        'Рахунки: ${names()}.',
      );
      return;
    }
    final src = from.first;
    final dst = to.first;
    if (src.id == dst.id) {
      await _replyAndFinish(job, 'Потрібні два різні рахунки.');
      return;
    }
    final sameCurrency = src.currency.toUpperCase() == dst.currency.toUpperCase();
    final destAmount = sameCurrency
        ? req.amount
        : (req.amount / src.rateToBase * dst.rateToBase * 100).round() / 100;
    final at = _clock().toUtc();
    final payload = JobPayload.decode(job.payloadJson);
    await _setJob(job.id, state: AiJobState.committing, stage: AiStage.saving);
    await db.transaction(() async {
      final r = await TransferBuilder(db, _budget).create(
        sourceAccountId: src.id,
        destAccountId: dst.id,
        sourceAmount: req.amount,
        destAmount: destAmount,
        sourceRate: src.rateToBase,
        destRate: dst.rateToBase,
        date: at,
        namespaceId: job.id,
      );
      final batch = await _batches.startBatch(
        jobId: job.id,
        threadId: job.threadId,
        messageId: payload.messageId,
        summary: 'Переказ ${src.name} → ${dst.name}',
      );
      var pos = 0;
      for (final c in r.createdCategoryIds) {
        await _batches.record(
          batch,
          position: pos++,
          entityType: AiEntity.category,
          entityId: c,
        );
      }
      for (final id in [r.expenseId, r.incomeId]) {
        await _batches.record(
          batch,
          position: 10 + pos++,
          entityType: AiEntity.transaction,
          entityId: id,
        );
      }
      await _putMessage(
        deriveId(job.id, 'result'),
        job,
        role: AiRole.assistant,
        kind: AiMessageKind.result,
        body:
            'Переказ записано (пакет ${batch.substring(0, 8)}): '
            '${fmtMoney(req.amount)} ${src.currency} ${src.name} → '
            '${fmtMoney(destAmount)} ${dst.currency} ${dst.name}.'
            '${sameCurrency ? '' : ' Суму отримання пораховано за курсами рахунків.'}',
        contentJson: jsonEncode({
          'v': 1,
          'batch_id': batch,
          'transactions': [r.expenseId, r.incomeId],
        }),
      );
      await _setJob(job.id, state: AiJobState.done, stage: AiStage.done, error: null);
      await _status(job, AiStage.done);
    });
  }

  /// The newest draft of this thread that waits for the user.
  Future<({AiJob job, DraftCard draft})?> _pendingDraftJob(AiJob me) async {
    final jobs =
        await (db.select(db.aiJobsTable)
              ..where(
                (t) =>
                    t.threadId.equals(me.threadId) &
                    t.state.isIn(AiJobState.waiting) &
                    t.id.equals(me.id).not(),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
            .get();
    for (final j in jobs) {
      final d = await _draftOf(j);
      if (d != null) return (job: j, draft: d);
    }
    return null;
  }

  Future<void> _correct(AiJob me, String text, AiJob target, DraftCard d) async {
    final visible = d.lines;
    final intent = await _intentOf(text, visible);
    final line = intent.line == null || intent.line! > visible.length
        ? null
        : visible[intent.line! - 1];
    String? say;
    var apply = true;
    switch (intent.kind) {
      case CorrectionKind.confirm:
        d.confirmed = true;
        d.userConfirmed = true;
        say = 'Підтверджено.';
      case CorrectionKind.reject:
        await _rejectJob(target, d);
        await _replyAndFinish(me, 'Відхилено: нічого не записано.');
        return;
      case CorrectionKind.setCategory:
        if (line == null) {
          say = 'Вкажіть номер рядка, для якого змінити категорію.';
          apply = false;
        } else {
          final id = await _categoryFromAnswer(line, intent.text!);
          if (id == null) {
            say = 'Не знайшов категорію «${intent.text}».';
            apply = false;
          } else {
            await _aliases.remember(line.name, categoryId: id);
            _lineOv(d, line.index)['category_id'] = id;
            say = 'Категорію змінено, запам’ятав для «${line.name}».';
          }
        }
      case CorrectionKind.setQuantity:
      case CorrectionKind.setPrice:
        if (line == null) {
          say = 'Вкажіть номер рядка.';
          apply = false;
        } else {
          final key = intent.kind == CorrectionKind.setQuantity
              ? 'quantity'
              : 'unit_price';
          _lineOv(d, line.index)[key] = intent.number;
          say = 'Змінено.';
        }
      case CorrectionKind.deleteLine:
        if (line == null) {
          say = 'Вкажіть номер рядка, який прибрати.';
          apply = false;
        } else {
          _lineOv(d, line.index)['skip'] = true;
          say = 'Рядок «${line.name}» не буде записано.';
        }
      case CorrectionKind.rememberRule:
        await _rules.set('user_rule.${me.id}', {'text': intent.text});
        say = 'Запам’ятав: ${intent.text}';
        apply = false;
      default:
        say = 'Не зрозумів виправлення. Напишіть, наприклад: '
            '«рядок 2 категорія Снеки» або «видали рядок 3».';
        apply = false;
    }
    await _replyAndFinish(me, say);
    if (apply) {
      await _setJob(target.id, state: AiJobState.running, stage: AiStage.matching);
      await _evaluate(target, await _rebuild(target, d));
    }
  }

  /// Deterministic phrases first, then the model; null model / failure /
  /// nonsense gives `unknown` (a question), never a guess.
  Future<CorrectionIntent> _intentOf(String text, List<DraftLine> lines) async {
    final t = foldOf(text);
    if (RegExp(r'^(так|ок|ok|yes|confirm|підтверджую|підтвердити|записуй|записати)\W*$').hasMatch(t)) {
      return const CorrectionIntent(kind: CorrectionKind.confirm);
    }
    if (RegExp(r'^(ні|скасуй|скасувати|відхили|відхилити|reject|cancel|no)\W*$').hasMatch(t)) {
      return const CorrectionIntent(kind: CorrectionKind.reject);
    }
    final del = RegExp(r'(?:видали|прибери|delete|remove)\D*(\d+)').firstMatch(t);
    if (del != null) {
      return CorrectionIntent(kind: CorrectionKind.deleteLine, line: int.parse(del.group(1)!));
    }
    final client = llm;
    if (client == null) return CorrectionIntent.unknown;
    try {
      final reply = await client.runPrompt(
        correctionIntentPrompt(
          userText: text,
          lines: [
            for (final l in lines)
              '${l.name} — ${l.quantity == null ? '?' : fmtQty(l.quantity!)} — '
                  '${fmtMoney(l.amount)}',
          ],
        ),
      );
      return parseCorrectionIntent(reply, lineCount: lines.length);
    } on Object {
      return CorrectionIntent.unknown;
    }
  }

  static String foldOf(String s) => s.trim().toLowerCase();
}

/// What the user answered to a "weight of one pack?" question: grams, or "by
/// the piece". Null when nothing readable.
({double? grams, bool piece})? parseWeightAnswer(String answer) {
  final a = answer.trim().toLowerCase();
  if (RegExp(r'(шт|штук|piece|adet|поштучно)').hasMatch(a)) {
    return (grams: null, piece: true);
  }
  final m = RegExp(r'(\d+(?:[.,]\d+)?)\s*(кг|kg|г|гр|g|gr|мл|ml|л|l)?').firstMatch(a);
  if (m == null) return null;
  final v = double.tryParse(m.group(1)!.replaceAll(',', '.'));
  if (v == null || v <= 0) return null;
  final unit = m.group(2) ?? '';
  final grams = (unit == 'кг' || unit == 'kg' || unit == 'л' || unit == 'l')
      ? v * 1000
      : v;
  return (grams: grams, piece: false);
}
