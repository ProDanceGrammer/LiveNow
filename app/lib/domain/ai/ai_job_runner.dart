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
    show
        BooleanExpressionOperators,
        InsertMode,
        OrderingTerm,
        StringExpressionOperators,
        Value,
        Variable;

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
import 'receipt_memory.dart';
import 'category_resolver.dart';
import 'extracted_receipt.dart' show ExtractedReceipt, ReceiptLine, Tender;
import 'invariant_validator.dart';
import 'model_prompts.dart';
import 'price_planner.dart';
import 'job_progress.dart';
import 'receipt_extractor.dart';
import 'receipt_row_builder.dart' show rebuildReceipt;
import 'receipt_fx_rules.dart';
import 'sum_verifier.dart' show tenderFromAnswer;
import 'transfer_builder.dart';
import 'typed_expense.dart';

/// A job is given up after this many failed or interrupted attempts.
const kMaxJobAttempts = 3;

/// How long the model may work on one processing run of a job (the hub
/// starts on a message -> its reply or draft; a resumed job gets its own).
/// The hub gives its model clients this deadline; a timeout past it fails the
/// job at once (with Retry) instead of starting the same slow work again.
const kModelProcessingLimit = Duration(hours: 3);

class AiJobRunner {
  AiJobRunner({
    required this.db,
    required this.extractor,
    this.llm,
    this.ocr,
    required this.settings,
    this.storeOriginal,
    this.startService,
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

  /// Starts the OCR service ([ocr]) or the model server when a call to it was
  /// refused; true when it answers now. The hub passes its launcher; null (or
  /// false) = the job fails at once with Retry.
  final Future<bool> Function({required bool ocr})? startService;
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

  /// Does one unit of work. Order: (0) the user's Retry of failed jobs
  /// (requeues them); (1) a job that was interrupted while running
  /// or committing, else the oldest queued job; (2) a waiting job (needs_input /
  /// draft_ready) with new user input; (3) nothing: false.
  Future<bool> runNext() async {
    _gaveUp = false;
    if (await _applyRetries()) return true;
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

  /// The user's Retry on a failed job (a `retry` user row, see
  /// `AiChatService.retryJob`): the job goes back to the queue with a fresh
  /// attempt count and its error card is removed. A retry of a job that is not
  /// failed (pressed twice, already running again) is only marked handled.
  /// True when there was such a row.
  Future<bool> _applyRetries() async {
    final rows =
        await (db.select(db.aiMessagesTable)
              ..where(
                (t) =>
                    t.role.equals(AiRole.user) &
                    t.kind.equals(AiMessageKind.retry) &
                    t.contentJson.like('%"handled"%').not(),
              )
              ..orderBy([
                (t) => OrderingTerm.asc(t.createdAt),
                (t) => OrderingTerm.asc(t.id),
              ]))
            .get();
    if (rows.isEmpty) return false;
    await db.transaction(() async {
      for (final m in rows) {
        final jobId = m.jobId;
        final job = jobId == null ? null : await _job(jobId);
        if (job != null && job.state == AiJobState.failed) {
          await _setJob(
            job.id,
            state: AiJobState.queued,
            stage: AiStage.queued,
            error: null,
            attempts: 0,
          );
          await (db.delete(db.aiMessagesTable)
                ..where((t) => t.id.equals(deriveId(job.id, 'error-fail'))))
              .go();
          await _status(job, AiStage.queued);
        }
        await (db.update(db.aiMessagesTable)..where((t) => t.id.equals(m.id)))
            .write(
              AiMessagesTableCompanion(
                contentJson: Value(jsonEncode({'v': 1, 'handled': true})),
                updatedAt: Value(_stamp()),
              ),
            );
      }
    });
    return true;
  }

  /// Runs one step of [job]; true when it ended normally (its step times are
  /// then learned and saved).
  Future<bool> _guarded(
    AiJob job, {
    required bool resume,
    bool restarted = false,
    DateTime? began,
  }) async {
    // Its chat was deleted (the job went with it): nothing to do, and nothing
    // may be written back for it.
    if (await _job(job.id) == null) return false;
    final from = began ?? _clock();
    if (!restarted) {
      _progress = JobProgress(timings: await _loadTimings(), clock: _clock);
    }
    var ok = false;
    try {
      if (resume) {
        await _resume(job);
      } else {
        await _start(job);
      }
      ok = true;
    } on AiJobFailure catch (e) {
      await _fail(job, e.message);
    } on AiUnreachableException catch (e) {
      ok = await _serviceDown(job, e, resume: resume, restarted: restarted, began: from);
    } on AiTimeoutException catch (e) {
      if (_clock().difference(from) >= kModelProcessingLimit) {
        await _fail(
          await _job(job.id) ?? job,
          'Модель на хабі обробляла повідомлення понад '
          '${kModelProcessingLimit.inHours} год: ${_clip('$e')}',
        );
      } else {
        await _attemptFailed(job, e, resume: resume);
      }
    } on Object catch (e) {
      await _attemptFailed(job, e, resume: resume);
    }
    if (!restarted) await _endProgress(ok);
    return ok;
  }

  /// The steps of the current processing run (the status line's %).
  JobProgress? _progress;

  Future<StepTimings> _loadTimings() async =>
      StepTimings.decode(await settings.get(AiSettingKey.stepTimings));

  Future<void> _endProgress(bool ok) async {
    final p = _progress;
    _progress = null;
    if (p == null) return;
    if (!ok) {
      p.abandon();
      return;
    }
    p.finish();
    await settings.set(AiSettingKey.stepTimings, p.timings.encode());
  }

  /// Starts the next step of the run: the status line shows it with the % and
  /// the time it is expected to take (one write per step; the app moves the
  /// bar in between). `ai_jobs.stage` keeps the coarse [AiStage].
  Future<void> _step(AiJob job, String key, {String? detail, int units = 1}) async {
    final stage = _stageOf(key);
    final p = _progress;
    if (p == null) {
      await _status(job, stage);
      return;
    }
    final snap = p.begin(JobStep(key, detail: detail, units: units));
    await _setJob(job.id, stage: stage);
    await _putMessage(
      deriveId(job.id, 'status'),
      job,
      role: AiRole.assistant,
      kind: AiMessageKind.status,
      body: snap.text,
      contentJson: jsonEncode({'v': 2, 'stage': stage, ...snap.toJson()}),
    );
  }

  /// A slow call deep in the builder (a model call) begins: [total] calls of
  /// this kind are needed, this is call [done] + 1.
  Future<void> _reportStep(
    AiJob job,
    String key, {
    int done = 0,
    int total = 1,
    int units = 1,
  }) async {
    _progress?.replanCount(key, total - done, units: units);
    await _step(
      job,
      key,
      detail: total > 1 ? '${key == JobSteps.categories ? 'batch' : 'call'} ${done + 1} of $total' : null,
      units: units,
    );
  }

  StepReporter _reporterFor(AiJob job) =>
      (key, {done = 0, total = 1, units = 1}) =>
          _reportStep(job, key, done: done, total: total, units: units);

  static String _stageOf(String key) => switch (key) {
    JobSteps.ocr || JobSteps.lines => AiStage.reading,
    JobSteps.checks => AiStage.checking,
    JobSteps.startOcr || JobSteps.startModel => AiStage.queued,
    _ => AiStage.matching,
  };

  /// What a run of [job] is expected to do, before anything is known.
  List<JobStep> _stepsFor(AiJob job, {required bool resume}) {
    const guess = 8; // lines on a typical receipt
    const model = [
      JobStep(JobSteps.translate, units: guess),
      JobStep(JobSteps.categories, units: guess),
      JobStep(JobSteps.checks),
    ];
    if (resume) return const [JobStep(JobSteps.apply), JobStep(JobSteps.checks)];
    return switch (job.kind) {
      AiJobKind.photos => [
        for (var i = 0; i < JobPayload.decode(job.payloadJson).blobIds.length; i++)
          const JobStep(JobSteps.ocr),
        const JobStep(JobSteps.ocr),
        const JobStep(JobSteps.lines),
        ...model,
      ],
      AiJobKind.receipt => const [JobStep(JobSteps.ocr), JobStep(JobSteps.lines), ...model],
      AiJobKind.screenshot => const [JobStep(JobSteps.ocr), JobStep(JobSteps.payment)],
      AiJobKind.bazaar => const [JobStep(JobSteps.lines), ...model],
      _ => const [
        JobStep(JobSteps.message),
        JobStep(JobSteps.translate, units: 2),
        JobStep(JobSteps.categories, units: 2),
        JobStep(JobSteps.checks),
      ],
    };
  }

  /// An error that may pass (a bad reply, a crash): costs one attempt; the job
  /// fails after [kMaxJobAttempts].
  Future<void> _attemptFailed(AiJob job, Object e, {required bool resume}) async {
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

  /// The OCR service or the model server refused the call (stopped, PC just
  /// started, Ollama's updater stopped it). Not the job's fault, so no attempt
  /// is counted: the hub starts the service and the same step runs once more.
  /// When it cannot be started (or is refused again right after) the job
  /// fails at once, saying which service, with Retry; nothing waits.
  Future<bool> _serviceDown(
    AiJob job,
    AiUnreachableException e, {
    required bool resume,
    required bool restarted,
    required DateTime began,
  }) async {
    final ocrUrl = ocr?.baseUrl;
    // The clients put the full request URL first (`<base>/ocr: ...`).
    final isOcr = ocrUrl != null && e.message.startsWith('$ocrUrl/');
    final start = startService;
    if (!restarted && start != null) {
      if (!resume) await _step(job, isOcr ? JobSteps.startOcr : JobSteps.startModel);
      if (await start(ocr: isOcr)) {
        // Back to where this step began, then the same step again.
        await _setJob(
          job.id,
          state: resume ? job.state : AiJobState.queued,
          stage: resume ? job.stage : AiStage.queued,
        );
        final fresh = await _job(job.id);
        if (fresh == null) return false;
        return _guarded(fresh, resume: resume, restarted: true, began: began);
      }
    }
    final what = isOcr ? 'Сервіс розпізнавання (OCR)' : 'Сервер моделі (Ollama)';
    await _fail(
      await _job(job.id) ?? job,
      '$what на хабі не запущений, і хаб не зміг його запустити: ${_clip('$e')}',
    );
    return false;
  }

  /// The user's message named a group for this line: the pick is not learned.
  /// So is the category the message named for the receipt (until the user picks
  /// another one for the line).
  static bool _askedInGroup(DraftCard d, int index) {
    final m = d.overrides['in_group'];
    if (m is Map && m['$index'] != null) return true;
    final lines = d.overrides['lines'];
    final own = lines is Map && lines['$index'] is Map && (lines['$index'] as Map)['category_id'] != null;
    return !own && messagePlanOf(d.overrides)?['category'] != null;
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
    _progress?.plan(_stepsFor(job, resume: false));
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
    JobPayload? plan,
  }) async {
    final existing = await _draftOf(job);
    if (existing != null) {
      // A previous attempt got this far: no second extraction.
      await _step(job, JobSteps.lines);
      final b = await _rebuild(job, existing);
      await _evaluate(job, b);
      return;
    }
    final payload = JobPayload.decode(job.payloadJson);
    final messageTime = await _messageTime(job, payload);
    final Map<String, dynamic> source;
    final blobs = <AiBlob>[];
    ScreenshotReading? screenshot;
    var photoSha = '';
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
      await _step(job, JobSteps.ocr, detail: photo != null && release.length > 1 ? 'the receipt' : null);
      final receipt = await extractor.extract(
        base64Decode(first.data!),
        mime: first.mime,
      );
      source = {'receipt': receipt.toJson()};
      photoSha = first.sha256;
      screenshot = pickScreenshot(
        shots ?? [for (final s in payload.screenshots) ScreenshotReading.fromJson(s)],
        receipt.total,
        solo: shots != null ? solo : payload.receiptCount == 1,
      );
    }
    await _step(job, JobSteps.lines);
    // What the user's message said about this receipt ([plan] on the solo path,
    // else the parent's reading stored in this job's payload).
    final said = plan ?? payload;
    final b = await _builder.build(
      job: job,
      kind: job.kind,
      source: source,
      onStep: _reporterFor(job),
      overrides: {
        if (screenshot != null && screenshot.hasAnything) 'screenshot': screenshot.toJson(),
        if (photoSha.isNotEmpty) 'photo_sha': photoSha,
        if (job.kind != AiJobKind.bazaar &&
            (said.planCategory != null || said.planItem != null || said.planRecipient != null))
          'message_plan': {
            'category': said.planCategory,
            'item': said.planItem,
            'recipient': said.planRecipient,
          },
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
      onStep: _reporterFor(job),
    );
  }

  // ===========================================================================
  // Decisions after a (re)build
  // ===========================================================================

  /// Saves the draft, refreshes the question card and chooses the next state:
  /// ask, wait for Confirm (draft-first), or commit.
  Future<void> _evaluate(AiJob job, DraftBuild b) async {
    await _step(job, JobSteps.checks);
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
    // A photographed receipt is ALWAYS shown as an editable list first and written
    // only after the user's Confirm; typed purchases keep the auto mode.
    final reviewAlways = job.kind == AiJobKind.receipt ||
        job.kind == AiJobKind.screenshot ||
        job.kind == AiJobKind.photos;
    final auto = !reviewAlways && !await settings.draftFirstActive() && !guessed;
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
    _progress?.plan(_stepsFor(job, resume: true));
    await _step(job, JobSteps.apply);

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
        if (e.categoryId != null) {
          ov['category_id'] = e.categoryId;
          // Picked by hand in the list: the next receipt starts from it.
          final line = _lineOf(d, e.index);
          if (line != null &&
              e.newName == null &&
              !_askedInGroup(d, e.index) &&
              !await _isGroup(e.categoryId!)) {
            await _aliases.remember(line.name, categoryId: e.categoryId);
          }
          // A category chosen by hand replaces an earlier "create" request.
          if (e.newName == null) ov.remove('new_name');
        }
        if (e.newName != null && e.newName!.trim().isNotEmpty) ov['new_name'] = e.newName!.trim();
        if (e.quantity != null) ov['quantity'] = e.quantity;
        if (e.unitPrice != null) ov['unit_price'] = e.unitPrice;
        if (e.unit == 'piece' || e.unit == 'kilogram') ov['unit'] = e.unit;
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
        await _cancelJob(
          job,
          d,
          d.overrides['seen_left'] == true
              ? 'Цей чек уже записано: залишив як є, нічого нового не записано.'
              : 'Пропустив: нічого не записано.',
        );
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
      // A tapped option names its group by id (`create:<id>`): two groups can
      // share a name; typed text still finds it by name.
      final create = kCreateOption.firstMatch(a);
      if (create != null) {
        final aid = q.answerId;
        final group = aid != null && aid.startsWith('create:')
            ? await _categoryById(aid.substring(7))
            : await _groupByName(create.group(2)!);
        if (group != null) {
          final ov = _lineOv(d, line.index);
          ov['category_id'] = group.id;
          ov['new_name'] = create.group(1)!.trim();
          return true;
        }
      }
      // A tapped option is its id; only typed text is matched by name.
      final aid = q.answerId;
      final categoryId = aid != null && line.candidates.any((c) => c.id == aid)
          ? aid
          : await _categoryFromAnswer(line, a);
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
      // A group is not a product: only a real category is learned. A pick
      // inside a group the user named is asked again next time.
      if (!_askedInGroup(d, line.index) && !await _isGroup(categoryId)) {
        await _aliases.remember(line.name, categoryId: categoryId);
      }
      _lineOv(d, line.index)['category_id'] = categoryId;
    } else if (id == 'seen') {
      final pick = q.answerId ??
          (RegExp('залишити|leave', caseSensitive: false).hasMatch(a)
              ? 'seen:leave'
              : RegExp('змінити|edit', caseSensitive: false).hasMatch(a)
                  ? 'seen:edit'
                  : 'seen:again');
      if (pick == 'seen:leave') {
        d.overrides['seen_left'] = true;
        return false;
      }
      d.overrides['seen_ok'] = true;
      d.overrides['dup_ok'] = true; // answered once: the older duplicate check stays quiet
      if (pick == 'seen:edit') {
        // The saved rows are taken back (Undo of that batch); Confirm saves the
        // corrected receipt in their place.
        final batchId = d.seen?['batch_id']?.toString();
        if (batchId != null) await _batches.undoBatch(batchId);
      }
    } else if (id == 'dup') {
      if (!_yes(a) && !RegExp('додати|add', caseSensitive: false).hasMatch(a)) {
        return false;
      }
      d.overrides['dup_ok'] = true;
    } else if (id == 'tender') {
      if (!_yes(a)) return false;
      d.overrides['tender_ok'] = true;
    } else if (id == 'mine') {
      // A tapped option is `tender:<i>`; typed text (or an older phone's tapped
      // text) names the tender by its amount or its card's last-4.
      final receipt = d.source['receipt'];
      final tenders = [
        if (receipt is Map && receipt['tenders'] is List)
          for (final t in receipt['tenders'] as List)
            if (t is Map) Tender.fromJson(Map<String, dynamic>.from(t)),
      ];
      final aid = q.answerId;
      final tapped = aid != null && aid.startsWith('tender:')
          ? int.tryParse(aid.substring(7))
          : null;
      final i = tapped != null && tapped >= 0 && tapped < tenders.length
          ? tapped
          : tenderFromAnswer(tenders, a);
      if (i == null) {
        d.overrides['mine_miss'] = a;
      } else {
        d.overrides.remove('mine_miss');
        d.overrides['mine_tender'] = i;
        final last4 = tenders[i].last4;
        if (last4 != null) d.overrides['mine_last4'] = last4;
      }
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
      // The option as shown (`Група › Назва`) or the bare name.
      if (normalizeReceiptText(c.label) == key || normalizeReceiptText(c.name) == key) {
        return c.id;
      }
    }
    // Free text: an existing category by name.
    final res = await CategoryResolver(db).resolve(answer, limit: 3);
    final best = res.best;
    if (best != null && best.score >= 0.7) return best.id;
    return null;
  }

  Future<BudgetCategory?> _categoryById(String id) => (db.select(
    db.budgetCategoriesTable,
  )..where((c) => c.id.equals(id))).getSingleOrNull();

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
      // The same product twice at the same price creates its category ONCE.
      final createdBy = <String, int>{};
      final twinOf = <int, int>{};
      for (final l in lines) {
        final plan = await _planFor(l, d);
        String? target = l.categoryId;
        var twin = false;
        if (plan != null && plan.kind != PlanKind.reuseLeaf) {
          // Lines sharing the new leaf the message named create it once.
          final k = l.oneOffName != null
              ? 'shared|${l.oneOffName}|${l.oneOffGroupId}'
              : '${DraftBuilder.twinKey(l.name)}|${(l.unitPrice ?? 0).toStringAsFixed(4)}|${l.categoryId}|${l.oneOffGroupId}';
          final first = createdBy[k];
          if (first != null) {
            twinOf[l.index] = first;
            target = 'new:$first';
            twin = true;
          } else {
            createdBy[k] = l.index;
          }
        }
        plans[l.index] = twin ? null : plan;
        if (twin) {
          // nothing to plan: it uses the leaf its twin creates
        } else if (plan != null) {
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
            name: txNameOfLine(d.merchant, l, d.overrides, d.lines.length),
            categoryId: target,
            quantity: l.quantity ?? 0,
            amount: l.amount,
            date: d.at,
            rateCount: l.rateCount,
            rateInteract: l.rateInteract,
            // Only planned leaves are checked against how it was paid.
            accountCountId: plan == null && !twin ? null : l.countAccountId,
            accountUseId: plan == null && !twin ? null : d.useAccountId,
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
      final leafOf = <int, String>{};
      for (final l in lines) {
        final base = 10 + l.index * 10;
        final plan = plans[l.index];
        var leafId = l.categoryId ?? '';
        if (twinOf.containsKey(l.index) && leafOf.containsKey(twinOf[l.index])) {
          leafId = leafOf[twinOf[l.index]]!;
        } else if (plan != null) {
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
        leafOf[l.index] = leafId;
        final txId = await _budget.createTransaction(
          id: deriveId(job.id, 'tx', l.index),
          categoryId: leafId,
          name: txNameOfLine(d.merchant, l, d.overrides, d.lines.length),
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
        // The next receipt with this name starts from it (a price variant is
        // remembered as its product, the same-name wrapper).
        if (d.userConfirmed && l.name.trim().isNotEmpty && !_askedInGroup(d, l.index)) {
          var product = leaf;
          final parent = leaf?.parentId == null
              ? null
              : await (db.select(db.budgetCategoriesTable)
                    ..where((t) => t.id.equals(leaf!.parentId!)))
                  .getSingleOrNull();
          if (leaf != null &&
              parent != null &&
              normalizeReceiptText(parent.name) == normalizeReceiptText(leaf.name)) {
            product = parent;
          }
          if (product != null) await _aliases.remember(l.name, categoryId: product.id);
        }
      }
      if (d.jobKind != AiJobKind.bazaar) {
        await ReceiptMemory(db, _rules).remember(
          sha: d.overrides['photo_sha']?.toString(),
          fp: d.overrides['fp']?.toString(),
          jobId: job.id,
          batchId: batchId,
        );
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
    if (l.oneOffGroupId != null || l.oneOffName != null) {
      return _planner.planOneOff(
        name: l.oneOffName ?? l.displayName,
        groupId: l.oneOffGroupId,
        cost: price,
        accountCountId: l.countAccountId,
        accountUseId: d.useAccountId,
        anyPrice: l.oneOffName != null,
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
      // A job whose chat was deleted while it ran must not bring the chat back.
      if (await _job(job.id) == null) return;
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

  /// A failed job can run again when its input is still here: the typed text,
  /// or photo bytes not yet moved to the hub's store (a photo is released only
  /// after it was read, so a job that failed while reading keeps it).
  Future<bool> _canRetry(AiJob job) async {
    final payload = JobPayload.decode(job.payloadJson);
    if ((payload.text ?? '').trim().isNotEmpty) return true;
    final blobs = await _blobsOf(job, payload);
    return blobs.any((b) => (b.data ?? '').isNotEmpty);
  }

  Future<void> _fail(AiJob job, String message) async {
    await _putMessage(
      deriveId(job.id, 'error-fail'),
      job,
      role: AiRole.assistant,
      kind: AiMessageKind.error,
      body: message,
      contentJson: jsonEncode({'v': 1, 'retryable': await _canRetry(job)}),
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
  Future<({ScreenshotReading? reading, String rows})> _screenshotReading(
    AiBlob b, {
    required DateTime now,
  }) async {
    try {
      final read = await _readShot(base64Decode(b.data!), b.mime, now: now.toLocal());
      return (reading: read.reading.hasAnything ? read.reading : null, rows: read.rows);
    } on AiJobFailure {
      return (reading: null, rows: '');
    }
  }

  /// One model call: what the message says about the receipts sent with it (the
  /// category for all of them, whom it is for, what each receipt was). Null when
  /// there is no text or the reply is unusable: the receipts then go their usual
  /// way. A model server that is down is the job's problem (it is restarted).
  Future<MessagePlan?> _messagePlan(String? text, List<String> receiptRows) async {
    final client = llm;
    final message = text?.trim() ?? '';
    if (client == null || message.isEmpty || receiptRows.isEmpty) return null;
    try {
      final reply = await client.runPrompt(
        messagePlanPrompt(text: message, receipts: receiptRows),
      );
      final plan = parseMessagePlan(reply, receiptCount: receiptRows.length);
      return plan.isEmpty ? null : plan;
    } on Object catch (e) {
      if (e is AiUnreachableException || e is AiCancelledException) rethrow;
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
    final receiptRows = <String>[];
    final shotBlobs = <AiBlob>[];
    final shots = <ScreenshotReading>[];
    for (var i = 0; i < blobs.length; i++) {
      final b = blobs[i];
      await _step(job, JobSteps.ocr, detail: blobs.length > 1 ? 'photo ${i + 1} of ${blobs.length}' : null);
      final read = await _screenshotReading(b, now: await _messageTime(job, payload));
      final reading = read.reading;
      if (reading == null) {
        receipts.add(b);
        receiptRows.add(read.rows);
      } else {
        shotBlobs.add(b);
        shots.add(reading);
      }
    }
    // A screenshot belongs to a receipt only when its lira amount stands among
    // that receipt's printed amounts; every other one (hryvnia only, a transfer,
    // a purchase of another day) is a purchase of its own, never lost.
    final related = <int>[];
    final own = <int>[];
    for (var i = 0; i < shots.length; i++) {
      (receipts.isNotEmpty && _fitsReceipt(shots[i], receiptRows) ? related : own).add(i);
    }
    final relatedShots = [for (final i in related) shots[i]];
    final relatedBlobs = [for (final i in related) shotBlobs[i]];
    // The message may say where the receipts go (category), for whom and what
    // each one was: read once here, carried into each receipt's job.
    // Parts of the message that name a screenshot of its own (by its amount or
    // day) are about that screenshot, not the receipts: the receipts' plan reads
    // only what is left (nothing left = no plan).
    var receiptText = payload.text;
    if (receipts.isNotEmpty && own.isNotEmpty) {
      final placed = placeCaptions(
        payload.text,
        [for (final i in own) shots[i]],
        now: await _messageTime(job, payload),
        generic: false,
      );
      receiptText = placed.leftover.join('. ');
    }
    MessagePlan? plan;
    if (receipts.isNotEmpty && (receiptText ?? '').trim().isNotEmpty) {
      await _step(job, JobSteps.message);
      plan = await _messagePlan(receiptText, receiptRows);
    }
    if (receipts.length == 1 && own.isEmpty) {
      await _startDraftJob(
        job,
        photo: receipts.first,
        shots: relatedShots,
        solo: true,
        release: blobs,
        plan: plan == null
            ? null
            : JobPayload(
                planCategory: plan.category,
                planItem: plan.items[1],
                planRecipient: plan.recipient,
              ),
      );
      return;
    }
    // Screenshots of their own: the message may say what each one was (by its
    // sum or day, or one text for all of them when no receipt took it).
    final ownCaptions = own.isEmpty
        ? const <String?>[]
        : await _shotCaptions(
            job,
            payload,
            [for (final i in own) shots[i]],
            generic: receipts.isEmpty,
          );
    if (receipts.isEmpty && shots.length == 1) {
      await _applyScreenshot(job, payload, blobs, shots.first, caption: ownCaptions.first);
      return;
    }
    // Several receipts, or several screenshots: one job each, so every receipt
    // has its own draft, Confirm and Undo. A receipt job gets the screenshots
    // that fit a receipt and takes the one whose amount fits its total.
    final kids = <({String kind, JobPayload payload})>[
      for (var i = 0; i < receipts.length; i++)
        (
          kind: AiJobKind.receipt,
          payload: JobPayload(
            messageId: payload.messageId,
            blobIds: [receipts[i].id],
            screenshots: [for (final s in relatedShots) s.toJson()],
            receiptCount: receipts.length,
            planCategory: plan?.category,
            planItem: plan?.items[i + 1],
            planRecipient: plan?.recipient,
          ),
        ),
      for (var k = 0; k < own.length; k++)
        (
          kind: AiJobKind.screenshot,
          payload: JobPayload(
            messageId: payload.messageId,
            blobIds: [shotBlobs[own[k]].id],
            text: ownCaptions[k],
          ),
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
    // The screenshots that fit a receipt are already read; the receipts keep
    // their bytes until their own job is done, the others read their own photo.
    if (receipts.isNotEmpty) await _releasePhotos(relatedBlobs);
  }

  /// A screenshot fits a receipt when its lira amount is one of the amounts OCR
  /// read on that receipt (the tolerance of [pickScreenshot]).
  bool _fitsReceipt(ScreenshotReading shot, List<String> receiptRows) {
    final c = shot.countAmount;
    if (c == null) return false;
    final tol = c * 0.005 > 1.0 ? c * 0.005 : 1.0;
    for (final rows in receiptRows) {
      for (final m in RegExp(r'\d[\d.,]*\d|\d').allMatches(rows)) {
        final v = parseAmountText(m.group(0)!);
        if (v != null && (v - c).abs() <= tol) return true;
      }
    }
    return false;
  }

  /// What the message says about each of [shots]. The rules (amount, day, one
  /// generic text) first; message parts they could not place go to the model
  /// ONCE together with the screenshots still without a name, and every answer
  /// is checked: a part and a screenshot are used at most once.
  Future<List<String?>> _shotCaptions(
    AiJob job,
    JobPayload payload,
    List<ScreenshotReading> shots, {
    required bool generic,
  }) async {
    final now = await _messageTime(job, payload);
    final placed = placeCaptions(payload.text, shots, now: now, generic: generic);
    final captions = [...placed.captions];
    final client = llm;
    final open = [
      for (var i = 0; i < captions.length; i++)
        if (captions[i] == null) i,
    ];
    if (client == null || placed.leftover.isEmpty || open.isEmpty) return captions;
    String describe(ScreenshotReading r) {
      final d = r.date;
      return [
        'amount ${fmtMoney(r.shopAmount ?? r.useAmount ?? 0)}',
        if (d != null) 'day ${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
        if (r.merchant != null) 'shop ${r.merchant}',
      ].join(', ');
    }
    try {
      final reply = await client.runPrompt(
        messageShotsPrompt(
          parts: placed.leftover,
          shots: [for (final i in open) describe(shots[i])],
        ),
      );
      final pairs = parseMessageShots(reply, shotCount: open.length, partCount: placed.leftover.length);
      pairs.forEach((shot, part) => captions[open[shot]] = placed.leftover[part]);
    } on Object catch (e) {
      if (e is AiUnreachableException || e is AiCancelledException) rethrow;
    }
    return captions;
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
    final existing = await _draftOf(job);
    if (existing != null) {
      // A previous attempt already made the purchase draft.
      await _evaluate(job, await _rebuild(job, existing));
      return;
    }
    final bytes = base64Decode(first.data!);
    await _step(job, JobSteps.ocr);
    final now = await _messageTime(job, payload);
    final reading = (await _readShot(bytes, first.mime, now: now)).reading;
    if (!reading.hasAnything) {
      await _replyAndFinish(
        job,
        'Не вдалося прочитати суму та курс на скріншоті. '
        'Надішліть чіткіший знімок.',
      );
      await _releasePhotos(blobs);
      return;
    }
    await _applyScreenshot(
      job,
      payload,
      blobs,
      reading,
      caption: captionsForShots(payload.text, [reading], now: now).first,
    );
  }

  /// A bank screenshot that is a purchase of its own: one editable line named
  /// by the message ([caption]), else by the merchant on the screenshot (not
  /// translated); the shop amount in lira, the charged hryvnia and the rate
  /// from the screenshot, its day when readable. The category: the remembered
  /// one for that name, else the model, else a question. Confirm writes it.
  Future<void> _startShotPurchase(
    AiJob job,
    JobPayload payload,
    List<AiBlob> blobs,
    ScreenshotReading reading,
    String? caption,
  ) async {
    final existing = await _draftOf(job);
    if (existing != null) {
      await _evaluate(job, await _rebuild(job, existing));
      return;
    }
    final amount = reading.shopAmount;
    if (amount == null || amount <= 0) {
      await _replyAndFinish(
        job,
        'Не вдалося прочитати суму на скріншоті. Надішліть чіткіший знімок '
        'або напишіть покупку словами.',
      );
      await _releasePhotos(blobs);
      return;
    }
    final merchant = reading.merchant;
    final name = caption ?? merchant ?? (reading.incoming ? 'Надходження' : 'Оплата карткою');
    final date = reading.date;
    final receipt = ExtractedReceipt(
      // With the message's name the merchant goes before it in the
      // transaction's name; alone it IS the line.
      merchant: caption == null || reading.uahOnly ? null : merchant,
      invoiceDatetimeLocal: date == null ? null : isoLocalOf(date),
      currency: reading.countAmount != null ? 'TRY' : 'UAH',
      total: amount,
      tenders: [Tender(method: 'card', amount: amount)],
      lines: [ReceiptLine(raw: name, name: name, lineTotal: amount)],
    );
    final photo = blobs.where((b) => b.sha256.isNotEmpty).firstOrNull;
    final b = await _builder.build(
      job: job,
      kind: AiJobKind.receipt,
      onStep: _reporterFor(job),
      source: {
        'receipt': receipt.toJson(),
        'payment': true,
        // The user's words name it (and may name a group of categories).
        if (caption != null) 'named': true,
        // Money that came in (a top-up) is income.
        if (reading.incoming) 'income': true,
        // A merchant's name is a name, not a product to translate.
        if (caption == null) 'keep_names': true,
      },
      overrides: {
        'screenshot': reading.toJson(),
        if (photo != null) 'photo_sha': photo.sha256,
      },
      messageTime: await _messageTime(job, payload),
    );
    await _saveDraft(job, b.card);
    await _releasePhotos(blobs);
    await _evaluate(job, b);
  }

  /// A screenshot without a receipt in the same message: new rates for the
  /// newest recorded receipt it fits; when the message says what it was
  /// ([caption]: the text wins) or no recorded receipt fits, it is a purchase
  /// of its own.
  Future<void> _applyScreenshot(
    AiJob job,
    JobPayload payload,
    List<AiBlob> blobs,
    ScreenshotReading reading, {
    String? caption,
  }) async {
    await _step(job, JobSteps.payment);
    // A hryvnia-only screen (transfer, top-up) whose message part says "from X
    // to Y" is a transfer between the user's own accounts.
    if (reading.uahOnly && caption != null && await _screenshotTransfer(job, payload, blobs, reading, caption)) {
      return;
    }
    // A hryvnia-only screen is never the rate of a recorded receipt.
    final target = caption == null && !reading.uahOnly ? await _batchForScreenshot(job, reading) : null;
    if (target == null) {
      await _startShotPurchase(job, payload, blobs, reading, caption);
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

  /// A photo read for a bank screenshot. When the service offers Ukrainian the photo is read
  /// with it FIRST (a bank app's Cyrillic is lost by the default Latin recogniser): a bank
  /// screen keeps that reading (one pass); anything else (a paper receipt) is read again
  /// with the default recogniser (Turkish letters) and that reading stands. A service
  /// without Ukrainian, or a failed Ukrainian pass, keeps today's single default read.
  Future<({ScreenshotReading reading, String rows})> _readShot(
    Uint8List bytes,
    String mime, {
    required DateTime now,
  }) async {
    final client = ocr;
    if (client != null && (await client.healthInfo()).hasUkrainian) {
      try {
        final uk = await _ocrRead(bytes, mime, lang: kOcrLangUkrainian);
        final ukReading = parseBankScreenshot(uk.text, now: now);
        if (ukReading.bankScreen || ukReading.hasAnything) {
          return (reading: ukReading, rows: uk.rows);
        }
      } on AiBadResponseException {
        // The Ukrainian pass failed: the default reading below stands.
      }
    }
    final read = await _ocrRead(bytes, mime);
    return (reading: parseBankScreenshot(read.text, now: now), rows: read.rows);
  }

  /// The OCR text of a photo and its printed rows (tilt-corrected when the
  /// service gave word boxes), the latter for the model that reads the message.
  Future<({String text, String rows})> _ocrRead(
    Uint8List bytes,
    String mime, {
    String? lang,
  }) async {
    final client = ocr;
    if (client != null) {
      final r = await client.ocr(bytes, mime: mime, lang: lang);
      final rebuilt = r.words.isEmpty ? null : rebuildReceipt(r.words);
      return (text: r.text, rows: _headRows(rebuilt?.text ?? r.text));
    }
    final ex = extractor;
    if (ex is OcrLlmExtractor) {
      final text = (await ex.extractWithText(bytes, mime: mime)).ocrText;
      return (text: text, rows: _headRows(text));
    }
    throw const AiJobFailure('Немає служби OCR для скріншота.');
  }

  /// The first printed rows of a receipt (shop and items), each cut short.
  static String _headRows(String text) => [
    for (final l in text.split('\n'))
      if (l.trim().isNotEmpty) l.trim().length <= 60 ? l.trim() : l.trim().substring(0, 60),
  ].take(14).join('\n');

  /// The newest committed, not undone receipt batch of the thread whose total
  /// matches the screenshot's shop amount (any newest one when it has none).
  Future<String?> _batchForScreenshot(AiJob job, ScreenshotReading r) async {
    final batches = await db
        .customSelect(
          'SELECT b.id AS id FROM ai_batches b JOIN ai_jobs j ON j.id = b.job_id '
          "WHERE b.thread_id = ? AND b.undone_at IS NULL AND j.id <> ? "
          "AND j.kind IN ('receipt', 'bazaar', 'photos') "
          // A payment recorded from a screenshot already has its rate: the next
          // screenshot of the same sum is another purchase, not a fix of it.
          "AND NOT EXISTS (SELECT 1 FROM ai_messages m WHERE m.job_id = j.id "
          "AND m.kind = 'draft' AND m.content_json LIKE '%\"payment\":true%') "
          'ORDER BY b.created_at DESC, b.id DESC',
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
    await _step(job, JobSteps.message);
    final payload = JobPayload.decode(job.payloadJson);
    final text = (payload.text ?? await _messageBody(payload.messageId) ?? '').trim();
    final transfer = parseTransferText(text);
    if (transfer != null) {
      await _transfer(job, transfer, text);
      return;
    }
    final accounts = await db.select(db.budgetAccountsTable).get();
    // "9026 грн із ФОП на монобанк": no verb, but it is a transfer when BOTH
    // names are accounts (the model is not asked for a message this loose).
    final loose = parseTransferPart(text);
    if (loose != null && loose.amount != null) {
      final picked = await _pickAccounts(loose, text, accounts, ask: _Ask.never);
      if (picked.from.length == 1 && picked.to.length == 1 && picked.from.first.id != picked.to.first.id) {
        await _writeTransfer(job, picked.from.first, picked.to.first, amount: loose.amount!);
        return;
      }
    }
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
      await _evaluate(job, await _rebuild(job, existing));
      return;
    }
    final payload = JobPayload.decode(job.payloadJson);
    final account = typed.accountIndex == null ? null : accounts[typed.accountIndex!];
    final b = await _builder.build(
      job: job,
      kind: AiJobKind.receipt,
      onStep: _reporterFor(job),
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

  Future<void> _transfer(AiJob job, TransferRequest req, String text) async {
    final accounts = await db.select(db.budgetAccountsTable).get();
    final picked = await _pickAccounts(req, text, accounts, ask: _Ask.always);
    String names() => accounts.map((a) => a.name).join(', ');
    if (picked.from.length != 1 || picked.to.length != 1) {
      final which = picked.from.length != 1 ? req.from : req.to;
      await _replyAndFinish(
        job,
        'Не вдалося однозначно знайти рахунок «$which». '
        'Рахунки: ${names()}.',
      );
      return;
    }
    if (picked.from.first.id == picked.to.first.id) {
      await _replyAndFinish(job, 'Потрібні два різні рахунки.');
      return;
    }
    await _writeTransfer(job, picked.from.first, picked.to.first, amount: req.amount!);
  }

  /// A screenshot of a transfer or top-up with the message's "from X to Y": when
  /// both accounts are found, it is written at once (two transactions, Undo)
  /// with the screenshot's exact amount and day. False = not a transfer: the
  /// caption is then a purchase name.
  Future<bool> _screenshotTransfer(
    AiJob job,
    JobPayload payload,
    List<AiBlob> blobs,
    ScreenshotReading reading,
    String caption,
  ) async {
    final req = parseTransferPart(caption);
    final amount = reading.useAmount;
    if (req == null || amount == null) return false;
    final accounts = await db.select(db.budgetAccountsTable).get();
    // "кава з молоком на винос" has the same shape: the model is asked only when
    // the rules already found one of the two accounts.
    final picked = await _pickAccounts(req, caption, accounts, ask: _Ask.partial, currencyHint: 'UAH');
    if (picked.from.length != 1 || picked.to.length != 1 || picked.from.first.id == picked.to.first.id) {
      return false;
    }
    DateTime? at;
    final d = reading.date;
    if (d != null) {
      try {
        at = receiptLocalToUtc(isoLocalOf(d));
      } on FormatException {
        at = null;
      }
    }
    await _writeTransfer(
      job,
      picked.from.first,
      picked.to.first,
      amount: amount,
      amountCurrency: 'UAH',
      at: at,
    );
    await _releasePhotos(blobs);
    return true;
  }

  /// Both accounts of a transfer message: the rules ([resolveAccount]) first;
  /// when they leave a side at none or several, ONE model call may point at
  /// them (see [_Ask]), and only valid, distinct numbers are taken.
  Future<({List<BudgetAccount> from, List<BudgetAccount> to})> _pickAccounts(
    TransferRequest req,
    String text,
    List<BudgetAccount> accounts, {
    required _Ask ask,
    String? currencyHint,
  }) async {
    List<BudgetAccount> find(String typed, {String? hint}) => resolveAccount(
      typed,
      accounts,
      nameOf: (a) => a.name,
      currencyOf: (a) => a.currency,
      currencyHint: hint,
    );
    var from = find(req.from, hint: currencyHint);
    var to = find(req.to);
    final open = from.length != 1 || to.length != 1;
    final askModel = switch (ask) {
      _Ask.always => true,
      _Ask.partial => from.length == 1 || to.length == 1,
      _Ask.never => false,
    };
    final client = llm;
    if (open && askModel && client != null) {
      try {
        final reply = await client.runPrompt(
          accountPickPrompt(
            text: text,
            accounts: [for (final a in accounts) '${a.name}, ${a.currency}'],
          ),
        );
        final pick = parseAccountPick(reply, accountCount: accounts.length);
        if (from.length != 1 && pick.from != null) from = [accounts[pick.from!]];
        if (to.length != 1 && pick.to != null) to = [accounts[pick.to!]];
      } on Object catch (e) {
        if (e is AiUnreachableException || e is AiCancelledException) rethrow;
      }
    }
    return (from: from, to: to);
  }

  /// Writes a transfer as the two usual transactions in one undoable batch.
  /// [amount] is in the source account's currency, unless [amountCurrency] says
  /// it is in the destination's (a hryvnia screenshot of a top-up).
  Future<void> _writeTransfer(
    AiJob job,
    BudgetAccount src,
    BudgetAccount dst, {
    required double amount,
    String? amountCurrency,
    DateTime? at,
  }) async {
    final sameCurrency = src.currency.toUpperCase() == dst.currency.toUpperCase();
    double convert(double v, BudgetAccount from, BudgetAccount to) =>
        (v / from.rateToBase * to.rateToBase * 100).round() / 100;
    final inDest = !sameCurrency &&
        amountCurrency != null &&
        dst.currency.toUpperCase() == amountCurrency.toUpperCase();
    final sourceAmount = inDest ? convert(amount, dst, src) : amount;
    final destAmount = sameCurrency ? amount : (inDest ? amount : convert(amount, src, dst));
    final when = at ?? _clock().toUtc();
    final payload = JobPayload.decode(job.payloadJson);
    await _setJob(job.id, state: AiJobState.committing, stage: AiStage.saving);
    await db.transaction(() async {
      final r = await TransferBuilder(db, _budget).create(
        sourceAccountId: src.id,
        destAccountId: dst.id,
        sourceAmount: sourceAmount,
        destAmount: destAmount,
        sourceRate: src.rateToBase,
        destRate: dst.rateToBase,
        date: when,
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
            '${fmtMoney(sourceAmount)} ${src.currency} ${src.name} → '
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

/// When the model may be asked which account a transfer message means.
enum _Ask {
  /// The message is a transfer for sure (it has a verb).
  always,

  /// Only when the rules already found one of the two accounts.
  partial,

  /// Never: the rules decide.
  never,
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
