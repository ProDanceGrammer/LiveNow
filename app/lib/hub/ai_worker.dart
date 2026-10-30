import 'dart:async';

import 'package:drift/drift.dart';

import '../core/error_log.dart';
import '../core/stream_utils.dart';
import '../core/time_codec.dart';
import '../data/ai/llm_client.dart';
import '../data/ai/ocr_client.dart';
import '../data/ai/receipt_extractors.dart';
import '../data/database.dart';
import '../domain/ai/ai_job_runner.dart';
import '../domain/ai/ai_protocol.dart';
import '../domain/ai/ai_settings_store.dart';
import 'ai_photo_store.dart';

/// One unit of work: true when it did something (the shape of
/// `AiJobRunner.runNext`).
typedef AiRunStep = Future<bool> Function();

/// Builds the step for ONE job from the settings read just before it, so a
/// changed model or URL takes effect without a restart.
typedef AiRunnerFactory = AiRunStep Function(AiSettingsSnapshot settings);

/// The hub's AI loop: runs queued jobs one at a time, only after the sync merge
/// that delivered them has finished. It wakes when `ai_jobs` / `ai_messages`
/// change and on a slow timer as a safety net, survives a failing runner
/// (error log + backoff), recovers jobs a crash left half-way, and purges old
/// photos once an hour.
class AiWorker {
  AiWorker({
    required this.db,
    required this.photos,
    AiRunnerFactory? runnerFactory,
    Future<bool> Function()? mergeBusy,
    this.safetyInterval = const Duration(seconds: 30),
    this.retentionInterval = const Duration(hours: 1),
    this.debounce = const Duration(milliseconds: 300),
    this.backoffBase = const Duration(seconds: 5),
    this.backoffMax = const Duration(minutes: 5),
    this.mergePoll = const Duration(milliseconds: 200),
    this.mergeWaitPolls = 300,
    void Function(String line)? log,
  }) : settings = AiSettingsStore(db),
       _log = log ?? ((_) {}) {
    _factory = runnerFactory ?? _productionRunner;
    _mergeBusy = mergeBusy ?? _syncMergeRunning;
  }

  final AppDatabase db;
  final AiPhotoStore photos;
  final AiSettingsStore settings;
  final Duration safetyInterval;
  final Duration retentionInterval;
  final Duration debounce;
  final Duration backoffBase;
  final Duration backoffMax;

  /// How often, and how many times, to look again while a merge runs; after
  /// that this round is skipped (the next wake or timer tries again).
  final Duration mergePoll;
  final int mergeWaitPolls;
  final void Function(String) _log;

  late final AiRunnerFactory _factory;
  late final Future<bool> Function() _mergeBusy;

  StreamSubscription<Object?>? _sub;
  Timer? _safety;
  Timer? _retention;
  Timer? _backoffTimer;
  bool _started = false;
  bool _stopped = false;
  bool _draining = false;
  bool _again = false;
  int _failures = 0;
  DateTime _blockedUntil = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastLogged;
  Future<void> _current = Future<void>.value();

  /// Recovers crashed jobs, then starts listening. Safe to call once.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _stopped = false;
    try {
      await recoverStuckJobs();
    } on Object catch (e, st) {
      await _report(e, st, 'AI worker: recovering stuck jobs');
    }
    _sub = debounced<Object?>(
      db
          .customSelect(
            'SELECT (SELECT COUNT(*) FROM ai_jobs) AS j, '
            '(SELECT COUNT(*) FROM ai_messages) AS m',
            readsFrom: {db.aiJobsTable, db.aiMessagesTable},
          )
          .watch(),
      debounce,
    ).listen((_) => wake());
    _safety = Timer.periodic(safetyInterval, (_) => wake());
    _retention = Timer.periodic(retentionInterval, (_) => purgeOldPhotos());
    unawaited(purgeOldPhotos());
    wake();
  }

  /// Stops listening and waits for the job in flight to end its step.
  Future<void> stop() async {
    _stopped = true;
    _started = false;
    _safety?.cancel();
    _retention?.cancel();
    _backoffTimer?.cancel();
    await _sub?.cancel();
    _sub = null;
    await _current;
  }

  /// Asks the loop to look for work (coalesced: at most one extra round).
  void wake() {
    if (_stopped) return;
    if (_draining) {
      _again = true;
      return;
    }
    _current = _drain();
  }

  /// A crash can leave a job in `running` / `committing`: make it eligible
  /// again (the runner counts the attempt). A stamped edit, so it syncs.
  Future<int> recoverStuckJobs() =>
      (db.update(db.aiJobsTable)..where(
            (t) => t.state.isIn([AiJobState.running, AiJobState.committing]),
          ))
          .write(
            AiJobsTableCompanion(
              state: const Value(AiJobState.queued),
              stage: const Value(AiStage.queued),
              updatedAt: Value(dateTimeToDb(DateTime.now())!),
            ),
          );

  /// Deletes photo files older than `photo_retention_days` (0 or less = keep).
  Future<int> purgeOldPhotos() async {
    try {
      final days = await settings.getInt(AiSettingKey.photoRetentionDays);
      if (days <= 0) return 0;
      return await photos.purgeOlderThan(Duration(days: days));
    } on Object catch (e, st) {
      await _report(e, st, 'AI worker: photo retention');
      return 0;
    }
  }

  Future<void> _drain() async {
    _draining = true;
    try {
      do {
        _again = false;
        if (_stopped || DateTime.now().isBefore(_blockedUntil)) break;
        await _drainOnce();
      } while (_again && !_stopped);
    } finally {
      _draining = false;
    }
  }

  Future<void> _drainOnce() async {
    try {
      // No jobs at all (the usual case on a hub that does not use the
      // assistant): nothing to build, nothing to ask.
      final any = await db
          .customSelect('SELECT 1 FROM ai_jobs LIMIT 1')
          .getSingleOrNull();
      if (any == null) return;
      if (!await _waitForMerge()) return;
      while (!_stopped) {
        final snapshot = await settings.load();
        final did = await _factory(snapshot)();
        if (!did) break;
        _failures = 0;
        if (!await _waitForMerge()) return;
      }
      _failures = 0;
      _lastLogged = null;
    } on Object catch (e, st) {
      await _report(e, st, 'AI worker: running a job');
      _failures++;
      var delay = backoffBase * (1 << (_failures - 1).clamp(0, 10));
      if (delay > backoffMax) delay = backoffMax;
      _blockedUntil = DateTime.now().add(delay);
      _backoffTimer?.cancel();
      if (!_stopped) _backoffTimer = Timer(delay, wake);
    }
  }

  /// True when no merge is running (waits a little while one is).
  Future<bool> _waitForMerge() async {
    for (var i = 0; i < mergeWaitPolls; i++) {
      if (_stopped) return false;
      if (!await _mergeBusy()) return true;
      await Future<void>.delayed(mergePoll);
    }
    return false;
  }

  /// The sync engine raises `sync_applying` for the length of a merge.
  Future<bool> _syncMergeRunning() async {
    final row = await db
        .customSelect('SELECT flag FROM sync_applying LIMIT 1')
        .getSingleOrNull();
    return (row?.read<int>('flag') ?? 0) != 0;
  }

  Future<void> _report(Object e, StackTrace st, String context) async {
    final line = '$context: $e';
    if (line != _lastLogged) {
      _lastLogged = line; // the same failure repeating is logged once
      _log(line);
      await ErrorLog.write(e, st, context: context);
    }
  }

  AiRunStep _productionRunner(AiSettingsSnapshot s) {
    final key = s.llmToken.isEmpty ? null : s.llmToken;
    final llm = LlmClient(baseUrl: s.llmUrl, model: s.llmModel, apiKey: key);
    final ocr = OcrClient(baseUrl: s.ocrUrl);
    final vlm = s.visionModel.isEmpty
        ? null
        : VlmExtractor(
            llm: LlmClient(
              baseUrl: s.llmUrl,
              model: s.visionModel,
              apiKey: key,
            ),
          );
    return AiJobRunner(
      db: db,
      extractor: HybridExtractor(
        primary: OcrLlmExtractor(ocr: ocr, llm: llm),
        vlm: vlm,
      ),
      llm: llm,
      ocr: ocr,
      settings: settings,
      storeOriginal: photos.storeBlobFromRow,
    ).runNext;
  }
}
