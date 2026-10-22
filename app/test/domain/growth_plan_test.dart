import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/date_range_filter.dart';
import 'package:livenow/domain/growth_plan.dart';
import 'package:livenow/domain/growth_rules.dart';
import 'package:livenow/domain/growth_time.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/domain/saved_views.dart'
    show dateRangeFromJson, dateRangeToJson;

/// The Treemap's planned-hours mode (what the owner typed on the hours
/// directions, per day / week / month / year, against the hours available) and
/// the custom date range of the time-spent mode.
void main() {
  setUpAll(initPostponeTimeZoneData);

  // Monday 19 Oct 2026, 13:00 in Istanbul (UTC+3).
  final now = DateTime.utc(2026, 10, 19, 10);

  GrowthMetric hours(
    String id,
    double target, {
    MetricWindow window = MetricWindow.week,
    MetricKind kind = MetricKind.hours,
  }) => GrowthMetric(
    id: id,
    name: id,
    kind: kind,
    window: kind == MetricKind.boolean ? null : window,
    target: target,
  );

  PlanRange oneDay() => resolvePlanRange(
    span: PlanSpan.day,
    range: const DateRangeFilter(),
    nowUtc: now,
  )!;

  group('turning a plan into hours', () {
    test('a window length stands for its average number of days', () {
      expect(windowDays(MetricWindow.week), 7);
      expect(windowDays(MetricWindow.month), closeTo(30.4375, 1e-9));
      expect(windowDays(MetricWindow.year), closeTo(365.25, 1e-9));
      expect(windowDays(MetricWindow.fiveYears), closeTo(1826.25, 1e-9));
    });

    test('target / window x days: 56 h a week is 8 h a day and 56 h in a week', () {
      final sleep = hours('sleep', 56);
      expect(plannedHours(sleep, 1), closeTo(8, 1e-9));
      expect(plannedHours(sleep, 7), closeTo(56, 1e-9));
      expect(plannedHours(hours('m', 30.4375, window: MetricWindow.month), 1), closeTo(1, 1e-9));
      expect(plannedHours(hours('y', 365.25, window: MetricWindow.year), 10), closeTo(10, 1e-9));
      expect(plannedHours(hours('f', 1826.25, window: MetricWindow.fiveYears), 1), closeTo(1, 1e-9));
    });

    test('only hours directions with a window and a target are plannable', () {
      expect(isPlannable(hours('a', 5)), isTrue);
      expect(isPlannable(hours('b', 0)), isFalse);
      expect(isPlannable(hours('c', 5, kind: MetricKind.count)), isFalse);
      expect(isPlannable(hours('d', 5, kind: MetricKind.boolean)), isFalse);
      expect(plannedHours(hours('c', 5, kind: MetricKind.count), 7), 0);
    });
  });

  group('the spans', () {
    PlanRange span(PlanSpan s) => resolvePlanRange(
      span: s,
      range: const DateRangeFilter(),
      nowUtc: now,
    )!;

    test('day is today; week 7 days; a month and a year are the real windows', () {
      expect(span(PlanSpan.day).days, 1);
      expect(span(PlanSpan.week).days, 7);
      // 19 Sep .. 19 Oct inclusive; 19 Oct 2025 .. 19 Oct 2026 inclusive.
      expect(span(PlanSpan.month).days, 31);
      expect(span(PlanSpan.year).days, 366);
    });

    test('every span ends today (its last day is the start of today)', () {
      for (final s in PlanSpan.values) {
        expect(span(s).until, localDayStartOf(now));
      }
    });

    test('a custom range counts its days inclusively', () {
      final r = resolvePlanRange(
        span: PlanSpan.day,
        range: DateRangeFilter(
          from: DateRangeFilter.dayStart(DateTime(2026, 10, 1)),
          until: DateRangeFilter.dayStart(DateTime(2026, 10, 10)),
        ),
        nowUtc: now,
      )!;
      expect(r.days, 10);
      // The same single day on both ends is one day.
      final one = resolvePlanRange(
        span: PlanSpan.week,
        range: DateRangeFilter(
          from: DateRangeFilter.dayStart(DateTime(2026, 3, 29)),
          until: DateRangeFilter.dayStart(DateTime(2026, 3, 29)),
        ),
        nowUtc: now,
      )!;
      expect(one.days, 1);
    });

    test('a range open at one end, or empty, cannot be planned', () {
      expect(
        resolvePlanRange(
          span: PlanSpan.day,
          range: DateRangeFilter(from: DateRangeFilter.dayStart(DateTime(2026, 10, 1))),
          nowUtc: now,
        ),
        isNull,
      );
      expect(
        resolvePlanRange(
          span: PlanSpan.day,
          range: DateRangeFilter(
            from: DateRangeFilter.dayStart(DateTime(2026, 10, 10)),
            until: DateRangeFilter.dayStart(DateTime(2026, 10, 1)),
          ),
          nowUtc: now,
        ),
        isNull,
      );
    });
  });

  group('the plan and the overplanned check', () {
    // The owner's day: sleep 8, job 8, friends 3, family 1, sport 2, reading 2,
    // games 3 = 27 h, entered as weekly targets (x 7).
    final week = [
      hours('a-sleep', 56),
      hours('b-job', 56),
      hours('c-friends', 21),
      hours('d-family', 7),
      hours('e-sport', 14),
      hours('f-reading', 14),
      hours('g-games', 21),
    ];

    test('27 h planned in a 24 h day: 3 h over, every plan 11 % too big', () {
      final p = buildPlan(metrics: week, included: null, range: oneDay());
      expect(p.total, closeTo(27, 1e-9));
      expect(p.available, 24);
      expect(p.overplanned, isTrue);
      expect(p.over, closeTo(3, 1e-9));
      expect(p.shrinkFraction, closeTo(3 / 27, 1e-9));
      expect(p.free, 0);
    });

    test('the biggest plans come first, ties by id, so the order never shuffles', () {
      final p = buildPlan(metrics: week.reversed, included: null, range: oneDay());
      expect(p.blocks.map((b) => b.metric.id), [
        'a-sleep',
        'b-job',
        'c-friends',
        'g-games',
        'e-sport',
        'f-reading',
        'd-family',
      ]);
      expect(p.biggest().map((b) => b.metric.id), ['a-sleep', 'b-job', 'c-friends']);
      expect(p.biggest(1).single.metric.id, 'a-sleep');
    });

    test('fewer hours available per day (16 awake hours) is over by more', () {
      final p = buildPlan(metrics: week, included: null, range: oneDay(), hoursPerDay: 16);
      expect(p.available, 16);
      expect(p.over, closeTo(11, 1e-9));
    });

    test('the same plan fits a longer span by the same ratio (a week: 189 of 168)', () {
      final range = resolvePlanRange(
        span: PlanSpan.week,
        range: const DateRangeFilter(),
        nowUtc: now,
      )!;
      final p = buildPlan(metrics: week, included: null, range: range);
      expect(p.total, closeTo(189, 1e-9));
      expect(p.available, 168);
      expect(p.over, closeTo(21, 1e-9));
    });

    test('only the chosen directions count; nothing chosen is an empty plan', () {
      final p = buildPlan(
        metrics: week,
        included: {'a-sleep', 'b-job', 'c-friends'},
        range: oneDay(),
      );
      expect(p.total, closeTo(19, 1e-9));
      expect(p.overplanned, isFalse);
      expect(p.free, closeTo(5, 1e-9));
      expect(p.shrinkFraction, 0);
      final none = buildPlan(metrics: week, included: <String>{}, range: oneDay());
      expect(none.blocks, isEmpty);
      expect(none.total, 0);
    });

    test('directions that are not hours directions are never in the plan', () {
      final p = buildPlan(
        metrics: [
          hours('h', 14),
          hours('c', 5, kind: MetricKind.count),
          hours('b', 1, kind: MetricKind.boolean),
          hours('zero', 0),
        ],
        included: null,
        range: oneDay(),
      );
      expect(p.blocks.map((b) => b.metric.id), ['h']);
    });

    test('a block takes its share of the available hours', () {
      final p = buildPlan(metrics: week, included: null, range: oneDay());
      expect(p.share(p.blocks.first), closeTo(8 / 24, 1e-9)); // sleep
    });

    test('hours read short: 8 h, 5.5 h, 45 min', () {
      expect(formatHours(8), '8 h');
      expect(formatHours(5.5), '5.5 h');
      expect(formatHours(2.04), '2 h');
      expect(formatHours(0.75), '45 min');
      expect(formatHours(0), '0 h');
    });
  });

  group('saved-view codec of a date range', () {
    test('a quick preset is saved by NAME, so reopening resolves today\'s dates', () {
      final r = DateRangeFilter(preset: DatePreset.values.first);
      final json = dateRangeToJson(r);
      expect(json, {'preset': DatePreset.values.first.name});
      expect(dateRangeFromJson(json).preset, DatePreset.values.first);
    });

    test('custom dates survive; an unknown preset or junk means no range', () {
      final r = DateRangeFilter(
        from: DateRangeFilter.dayStart(DateTime(2026, 10, 1)),
        until: DateRangeFilter.dayStart(DateTime(2026, 10, 10)),
      );
      final back = dateRangeFromJson(dateRangeToJson(r));
      // dayStart returns a TZDateTime: compare instants, not objects.
      expect(back.from!.millisecondsSinceEpoch, r.from!.millisecondsSinceEpoch);
      expect(back.until!.millisecondsSinceEpoch, r.until!.millisecondsSinceEpoch);
      expect(dateRangeFromJson({'preset': 'from-another-build'}).active, isFalse);
      expect(dateRangeFromJson('junk').active, isFalse);
      expect(dateRangeFromJson(null).active, isFalse);
    });
  });

  group('time spent over a custom range', () {
    LinkedActionFact done(String metric, DateTime at, {int minutes = 60, bool isDone = true}) =>
        LinkedActionFact(
          metricId: metric,
          isDone: isDone,
          windowTime: at,
          duration: Duration(minutes: minutes),
        );

    // Istanbul is UTC+3: local 23:00 on 10 Oct is 20:00Z, local 00:30 on 11 Oct
    // is 21:30Z on the 10th.
    // Built in setUp: the timezone database must be initialised first.
    late DateRangeFilter range;
    setUp(() {
      range = DateRangeFilter(
        from: DateRangeFilter.dayStart(DateTime(2026, 10, 1)),
        until: DateRangeFilter.dayStart(DateTime(2026, 10, 10)),
      );
    });

    test('days inside count, the whole last day included, the next day not', () {
      final t = timeSpentPerDirection(
        [
          done('m', DateTime.utc(2026, 9, 30, 20, 59), minutes: 1), // 30 Sep 23:59 local: out
          done('m', DateTime.utc(2026, 9, 30, 21), minutes: 10), // 1 Oct 00:00 local: in
          done('m', DateTime.utc(2026, 10, 5, 9), minutes: 20),
          done('m', DateTime.utc(2026, 10, 10, 20), minutes: 30), // 10 Oct 23:00 local: in
          done('m', DateTime.utc(2026, 10, 10, 21, 30), minutes: 99), // 11 Oct 00:30 local: out
        ],
        nowUtc: now,
        period: TreemapPeriod.week,
        range: range,
      );
      expect(t['m'], const Duration(minutes: 60));
    });

    test('the range replaces the period (an older range works though the period is a week)', () {
      final facts = [done('m', DateTime.utc(2026, 10, 5, 9))];
      expect(
        timeSpentPerDirection(facts, nowUtc: now, period: TreemapPeriod.week)['m'],
        isNull,
      );
      expect(
        timeSpentPerDirection(facts, nowUtc: now, period: TreemapPeriod.week, range: range)['m'],
        const Duration(minutes: 60),
      );
    });

    test('an inactive range changes nothing; not-done actions never count', () {
      final facts = [done('m', DateTime.utc(2026, 10, 18, 9)), done('m', DateTime.utc(2026, 10, 18, 9), isDone: false)];
      final plain = timeSpentPerDirection(facts, nowUtc: now, period: TreemapPeriod.week);
      final withEmpty = timeSpentPerDirection(
        facts,
        nowUtc: now,
        period: TreemapPeriod.week,
        range: const DateRangeFilter(),
      );
      expect(withEmpty, plain);
      expect(plain['m'], const Duration(minutes: 60));
    });

    test('an empty range (from after until) and open-ended ranges', () {
      final facts = [done('m', DateTime.utc(2026, 10, 5, 9))];
      final inverted = DateRangeFilter(
        from: DateRangeFilter.dayStart(DateTime(2026, 10, 10)),
        until: DateRangeFilter.dayStart(DateTime(2026, 10, 1)),
      );
      expect(
        timeSpentPerDirection(facts, nowUtc: now, period: TreemapPeriod.all, range: inverted),
        isEmpty,
      );
      final fromOnly = DateRangeFilter(from: DateRangeFilter.dayStart(DateTime(2026, 10, 1)));
      expect(
        timeSpentPerDirection(facts, nowUtc: now, period: TreemapPeriod.all, range: fromOnly)['m'],
        const Duration(minutes: 60),
      );
    });
  });
}

/// Istanbul midnight of the day containing [utc] (the same helper the app uses).
DateTime localDayStartOf(DateTime utc) => DateRangeFilter.dayStart(
  DateRangeFilter.dayOf(utc),
);
