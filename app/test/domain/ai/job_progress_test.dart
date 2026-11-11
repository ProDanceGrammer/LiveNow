import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/ai/job_progress.dart';

void main() {
  late DateTime now;
  JobProgress progress([StepTimings? t]) =>
      JobProgress(timings: t ?? StepTimings(), clock: () => now);

  setUp(() => now = DateTime.utc(2026, 11, 10, 12));

  test('the bar is split by the estimates of the planned steps', () {
    final t = StepTimings();
    final p = progress(t)
      ..plan(const [
        JobStep(JobSteps.ocr),
        JobStep(JobSteps.categories, units: 8),
        JobStep(JobSteps.checks),
      ]);
    final total = t.estimateMs(JobSteps.ocr, 1) +
        t.estimateMs(JobSteps.categories, 8) +
        t.estimateMs(JobSteps.checks, 1);
    final a = p.begin(const JobStep(JobSteps.ocr, detail: 'photo 1 of 1'));
    expect(a.pctFrom, 0);
    expect(a.pctTo, closeTo(100 * t.estimateMs(JobSteps.ocr, 1) / total, 0.01));
    expect(a.text, 'Reading the photo (OCR) · photo 1 of 1 · 0%');
    now = now.add(const Duration(seconds: 8));
    final b = p.begin(const JobStep(JobSteps.categories, units: 8));
    expect(b.pctFrom, closeTo(a.pctTo, 0.01));
    expect(b.pctTo, greaterThan(b.pctFrom));
    final c = p.begin(const JobStep(JobSteps.checks));
    expect(c.pctTo, closeTo(100, 0.01));
  });

  test('inside a step the bar moves with time, at most to 95 % of it', () {
    final p = progress()..plan(const [JobStep(JobSteps.checks)]);
    final s = p.begin(const JobStep(JobSteps.translate, units: 5));
    final est = s.estimateMs;
    expect(s.percentAt(now), s.pctFrom);
    final half = s.percentAt(now.add(Duration(milliseconds: est ~/ 2)));
    expect(half, closeTo(s.pctFrom + (s.pctTo - s.pctFrom) * 0.5, 0.5));
    final late = s.percentAt(now.add(Duration(milliseconds: est * 10)));
    expect(late, closeTo(s.pctFrom + (s.pctTo - s.pctFrom) * 0.95, 0.01));
  });

  test('a skipped or re-planned step never sends the bar back', () {
    final p = progress()
      ..plan(const [
        JobStep(JobSteps.lines),
        JobStep(JobSteps.translate, units: 8),
        JobStep(JobSteps.categories, units: 8),
        JobStep(JobSteps.checks),
      ]);
    var last = p.begin(const JobStep(JobSteps.lines)).pctFrom;
    // Translation was not needed; the model reports 3 batches.
    p.replanCount(JobSteps.categories, 3, units: 8);
    for (var i = 0; i < 3; i++) {
      now = now.add(const Duration(seconds: 30));
      final s = p.begin(const JobStep(JobSteps.categories, units: 8));
      expect(s.pctFrom, greaterThanOrEqualTo(last));
      last = s.pctFrom;
    }
    now = now.add(const Duration(seconds: 30));
    final end = p.begin(const JobStep(JobSteps.checks));
    expect(end.pctFrom, greaterThanOrEqualTo(last));
    expect(end.pctTo, closeTo(100, 0.01));
  });

  test('step times are learned and survive encode / decode', () {
    final t = StepTimings();
    final seed = t.estimateMs(JobSteps.categories, 8);
    final p = progress(t)..plan(const []);
    p.begin(const JobStep(JobSteps.categories, units: 8));
    now = now.add(Duration(milliseconds: seed * 3));
    p.finish();
    expect(t.factor(JobSteps.categories), closeTo(3, 0.01));
    final back = StepTimings.decode(t.encode());
    expect(back.estimateMs(JobSteps.categories, 8), closeTo(seed * 3, 2));
    // The next run moves the average a part of the way (α 0.3).
    back.learn(JobSteps.categories, 8, seed);
    expect(back.factor(JobSteps.categories), closeTo(3 + 0.3 * (1 - 3), 0.01));
  });

  test('an abandoned run learns nothing; bad stored text is no timings', () {
    final t = StepTimings();
    final p = progress(t)..plan(const []);
    p.begin(const JobStep(JobSteps.ocr));
    now = now.add(const Duration(minutes: 9));
    p.abandon();
    expect(t.factor(JobSteps.ocr), isNull);
    expect(StepTimings.decode('nonsense').factor(JobSteps.ocr), isNull);
    expect(StepTimings.decode(null).estimateMs(JobSteps.ocr, 2), 16000);
  });

  test('a snapshot round-trips through the status JSON', () {
    final p = progress()..plan(const []);
    final s = p.begin(const JobStep(JobSteps.categories, detail: 'batch 2 of 3', units: 8));
    final back = ProgressSnapshot.fromJson(s.toJson())!;
    expect(back.label, 'Matching categories');
    expect(back.detail, 'batch 2 of 3');
    expect(back.estimateMs, s.estimateMs);
    expect(back.started, s.started);
    expect(ProgressSnapshot.fromJson(const {'v': 1, 'stage': 'Queued'}), isNull);
  });
}
