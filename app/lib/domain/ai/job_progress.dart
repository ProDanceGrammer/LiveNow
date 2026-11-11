import 'dart:convert';
import 'dart:math' as math;

/// Told before each slow call deep inside the work (a model call): [key] is a
/// step key of [JobSteps], [done] of [total] calls of that kind, [units] the
/// items in this call.
typedef StepReporter =
    Future<void> Function(String key, {int done, int total, int units});

/// Step keys and their texts (English, like the stages).
abstract final class JobSteps {
  static const startOcr = 'start_ocr';
  static const startModel = 'start_model';
  static const ocr = 'ocr';
  static const lines = 'lines';
  static const translate = 'translate';
  static const categories = 'categories';
  static const choice = 'choice';
  static const checks = 'checks';
  static const apply = 'apply';
  static const payment = 'payment';
  static const message = 'message';

  static String label(String key) => switch (key) {
    startOcr => "Starting the hub's OCR service",
    startModel => "Starting the hub's model server",
    ocr => 'Reading the photo (OCR)',
    lines => 'Reading receipt lines',
    translate => 'Translating names',
    categories => 'Matching categories',
    choice => 'Choosing a category',
    checks => 'Checking sums',
    apply => 'Applying your answer',
    payment => 'Matching the payment',
    message => 'Reading your message',
    _ => key,
  };
}

/// One planned step: [units] scale its time estimate (photos, names, items).
class JobStep {
  const JobStep(this.key, {this.detail, this.units = 1});

  final String key;
  final String? detail;
  final int units;
}

/// How long the steps take on THIS hub: a seed per step (fixed + per unit),
/// times a learned factor (an average of actual / seed, α 0.3). Saved in the
/// hub-local `ai_settings`, so the first jobs guess and later ones fit the PC.
class StepTimings {
  StepTimings([Map<String, double>? factors]) : _factors = {...?factors};

  final Map<String, double> _factors;

  static const _alpha = 0.3;

  /// (fixed ms, ms per unit) before anything was learned.
  static (int, int) seed(String key) => switch (key) {
    JobSteps.startOcr => (20000, 0),
    JobSteps.startModel => (30000, 0),
    JobSteps.ocr => (0, 8000),
    JobSteps.translate => (20000, 3000),
    JobSteps.categories => (40000, 6000),
    JobSteps.choice => (25000, 0),
    _ => (1000, 0),
  };

  static int _seedMs(String key, int units) {
    final (fixed, per) = seed(key);
    return fixed + per * math.max(units, 1);
  }

  int estimateMs(String key, int units) =>
      math.max(200, (_seedMs(key, units) * (_factors[key] ?? 1.0)).round());

  void learn(String key, int units, int actualMs) {
    final ratio = (actualMs / _seedMs(key, units)).clamp(0.02, 50.0);
    final old = _factors[key];
    _factors[key] = old == null ? ratio : old + _alpha * (ratio - old);
  }

  double? factor(String key) => _factors[key];

  String encode() => jsonEncode(_factors);

  factory StepTimings.decode(String? text) {
    if (text == null || text.trim().isEmpty) return StepTimings();
    try {
      final j = jsonDecode(text);
      if (j is! Map) return StepTimings();
      return StepTimings({
        for (final e in j.entries)
          if (e.value is num && (e.value as num) > 0) '${e.key}': (e.value as num).toDouble(),
      });
    } catch (_) {
      return StepTimings();
    }
  }
}

/// What the status line shows: the step, its share of the bar and when it
/// began, so a phone can move the bar between two writes.
class ProgressSnapshot {
  const ProgressSnapshot({
    required this.key,
    required this.label,
    this.detail,
    required this.pctFrom,
    required this.pctTo,
    required this.started,
    required this.estimateMs,
  });

  final String key;
  final String label;
  final String? detail;
  final double pctFrom;
  final double pctTo;
  final DateTime started;
  final int estimateMs;

  /// The text for the chat (also what an older app shows).
  String get text =>
      [label, if (detail != null && detail!.isNotEmpty) detail!, '${pctFrom.floor()}%'].join(' · ');

  Map<String, dynamic> toJson() => {
    'step': key,
    'label': label,
    if (detail != null) 'detail': detail,
    'pct_from': double.parse(pctFrom.toStringAsFixed(1)),
    'pct_to': double.parse(pctTo.toStringAsFixed(1)),
    'started': started.toUtc().toIso8601String(),
    'estimate_ms': estimateMs,
  };

  static ProgressSnapshot? fromJson(Map<String, dynamic> j) {
    final key = j['step'];
    final from = j['pct_from'];
    final to = j['pct_to'];
    final started = DateTime.tryParse('${j['started']}');
    final est = j['estimate_ms'];
    if (key is! String || from is! num || to is! num || started == null || est is! num) {
      return null;
    }
    return ProgressSnapshot(
      key: key,
      label: j['label'] is String ? j['label'] as String : JobSteps.label(key),
      detail: j['detail'] is String ? j['detail'] as String : null,
      pctFrom: from.toDouble(),
      pctTo: to.toDouble(),
      started: started,
      estimateMs: est.toInt(),
    );
  }

  /// The bar at [now]: from [pctFrom] towards [pctTo] by the time spent, never
  /// past 95 % of the step (a slow step waits there instead of lying).
  double percentAt(DateTime now) {
    final spent = now.difference(started).inMilliseconds;
    final f = estimateMs <= 0 ? 0.95 : (spent / estimateMs).clamp(0.0, 0.95);
    return pctFrom + (pctTo - pctFrom) * f;
  }
}

/// The steps of one processing run. The remaining share of the bar (100 −
/// what is done) is split among the steps still planned by their estimates,
/// so the bar never goes back when the plan changes.
class JobProgress {
  JobProgress({required this.timings, required this._clock});

  final StepTimings timings;
  final DateTime Function() _clock;

  final List<JobStep> _planned = [];
  JobStep? _current;
  DateTime? _currentStart;
  double _pct = 0;
  double _currentTo = 0;

  /// Replaces what is still to come (after the current step).
  void plan(List<JobStep> steps) {
    _planned
      ..clear()
      ..addAll(steps);
  }

  /// Planned steps of [key] after the current one become [count] of them
  /// (a model reports how many calls a stage really needs).
  void replanCount(String key, int count, {int units = 1}) {
    final at = _planned.indexWhere((s) => s.key == key);
    _planned.removeWhere((s) => s.key == key);
    if (count <= 0) return;
    final insert = at < 0 ? 0 : math.min(at, _planned.length);
    _planned.insertAll(insert, [for (var i = 0; i < count; i++) JobStep(key, units: units)]);
  }

  /// Ends the current step (its time is learned) and starts [step]. Planned
  /// steps before the first of the same key are dropped (they were skipped).
  ProgressSnapshot begin(JobStep step) {
    _finishCurrent();
    final at = _planned.indexWhere((s) => s.key == step.key);
    if (at >= 0) _planned.removeRange(0, at + 1);
    final now = _clock();
    final est = timings.estimateMs(step.key, step.units);
    final rest = est + _planned.fold<int>(0, (a, s) => a + timings.estimateMs(s.key, s.units));
    _current = step;
    _currentStart = now;
    _currentTo = _pct + (100 - _pct) * est / rest;
    return ProgressSnapshot(
      key: step.key,
      label: JobSteps.label(step.key),
      detail: step.detail,
      pctFrom: _pct,
      pctTo: _currentTo,
      started: now,
      estimateMs: est,
    );
  }

  /// The run ended normally: the last step's time is learned too.
  void finish() {
    _finishCurrent();
    _planned.clear();
  }

  /// The run ended badly: what was measured so far is not learned.
  void abandon() {
    _current = null;
    _currentStart = null;
    _planned.clear();
  }

  double get percent => _pct;

  void _finishCurrent() {
    final s = _current;
    final t = _currentStart;
    if (s != null && t != null) {
      timings.learn(s.key, s.units, _clock().difference(t).inMilliseconds);
      _pct = _currentTo;
    }
    _current = null;
    _currentStart = null;
  }
}
