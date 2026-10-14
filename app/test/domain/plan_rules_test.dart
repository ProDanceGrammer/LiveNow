import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/plan_rules.dart';
import 'package:livenow/domain/postpone_rules.dart';

/// The recurrence engine: cycles (weekly, daily, N times a day, 2-on-1-off,
/// per-day variants), monthly rules, ends, overrides, pause.
void main() {
  setUpAll(initPostponeTimeZoneData);

  // Europe/Istanbul is UTC+3 all year: local 09:00 == 06:00Z.
  DateTime d(int y, int m, int day) => planDate(y, m, day);
  String keys(List<PlanOccurrence> l) => l.map((o) => o.key).join(' ');

  PlanItemData cycle(
    CycleRule rule, {
    DateTime? start,
    DateTime? end,
    bool forever = false,
    bool paused = false,
  }) => PlanItemData(
    id: 'p',
    name: 'Plan',
    kind: PlanKind.cycle,
    startDate: start ?? d(2026, 10, 19), // a Monday
    endDate: end,
    forever: forever,
    paused: paused,
    cycle: rule,
  );

  PlanItemData monthly(MonthlyRule rule, {DateTime? start, DateTime? end}) =>
      PlanItemData(
        id: 'm',
        name: 'Monthly',
        kind: PlanKind.monthly,
        startDate: start ?? d(2026, 1, 1),
        endDate: end,
        monthly: rule,
      );

  group('cycle', () {
    test('each Thursday = cycle 7 with one occurrence on day 3', () {
      final item = cycle(
        const CycleRule(
          cycleDays: 7,
          occurrences: [CycleOccurrence(day: 3, startMin: 18 * 60, durationMin: 60)],
        ),
      );
      final out = occurrencesInRange(item, d(2026, 10, 19), d(2026, 11, 8));
      expect(keys(out), '2026-10-22#0 2026-10-29#0 2026-11-05#0');
      expect(out.first.startUtc, DateTime.utc(2026, 10, 22, 15)); // 18:00 local
      expect(out.first.endUtc, DateTime.utc(2026, 10, 22, 16));
      expect(out.first.name, 'Plan');
    });

    test('every day, three times a day at their own times', () {
      final item = cycle(
        const CycleRule(
          cycleDays: 1,
          occurrences: [
            CycleOccurrence(day: 0, startMin: 8 * 60),
            CycleOccurrence(day: 0, startMin: 13 * 60),
            CycleOccurrence(day: 0, startMin: 20 * 60),
          ],
        ),
      );
      final out = occurrencesInRange(item, d(2026, 10, 19), d(2026, 10, 20));
      expect(out, hasLength(6));
      expect(
        out.map((o) => o.startMin),
        [8 * 60, 13 * 60, 20 * 60, 8 * 60, 13 * 60, 20 * 60],
      );
      // Default duration when an occurrence has none.
      expect(out.first.durationMin, 60);
      expect(
        occurrencesInRange(
          item,
          d(2026, 10, 19),
          d(2026, 10, 19),
          defaultMinutes: 25,
        ).first.durationMin,
        25,
      );
    });

    test('2 days one pattern, 1 day another, again 2 / 1 (cycle of 3)', () {
      final item = cycle(
        const CycleRule(
          cycleDays: 3,
          occurrences: [
            CycleOccurrence(day: 0, startMin: 600, name: 'A'),
            CycleOccurrence(day: 1, startMin: 600, name: 'A'),
            CycleOccurrence(day: 2, startMin: 900, name: 'B'),
          ],
        ),
      );
      final out = occurrencesInRange(item, d(2026, 10, 19), d(2026, 10, 27));
      expect(out.map((o) => o.name).join(), 'AABAABAAB');
      expect(out.map((o) => o.startMin).take(3), [600, 600, 900]);
    });

    test('a breakfast week: a different name and time on every weekday', () {
      final item = cycle(
        const CycleRule(
          cycleDays: 7,
          occurrences: [
            CycleOccurrence(day: 0, startMin: 540, durationMin: 60, name: 'Breakfast cooking'),
            CycleOccurrence(day: 1, startMin: 570, durationMin: 30, name: 'Breakfast cooks GF'),
            CycleOccurrence(day: 2, startMin: 570, durationMin: 30, name: 'Breakfast cooks GF'),
            CycleOccurrence(day: 3, startMin: 540, durationMin: 60, name: 'Breakfast cooking'),
          ],
        ),
      );
      final out = occurrencesInRange(item, d(2026, 10, 19), d(2026, 11, 1));
      // Two weeks, four days each.
      expect(out, hasLength(8));
      expect(out[1].name, 'Breakfast cooks GF');
      expect(out[1].startMin, 570);
      expect(out[1].durationMin, 30);
      expect(out[4].key, '2026-10-26#0');
    });

    test('a short list is stretched by the cycle length: 5 listed days, cycle 7', () {
      final item = cycle(
        CycleRule(
          cycleDays: 7,
          occurrences: [
            for (var i = 0; i < 5; i++) CycleOccurrence(day: i, startMin: 540),
          ],
        ),
      );
      final out = occurrencesInRange(item, d(2026, 10, 19), d(2026, 11, 1));
      expect(out, hasLength(10)); // Sat/Sun are free in both weeks
    });

    test('starts at start_date, ends at end_date (inclusive); forever ignores the end', () {
      const rule = CycleRule(
        cycleDays: 1,
        occurrences: [CycleOccurrence(day: 0, startMin: 600)],
      );
      final bounded = cycle(rule, start: d(2026, 10, 21), end: d(2026, 10, 23));
      expect(
        keys(occurrencesInRange(bounded, d(2026, 10, 1), d(2026, 10, 31))),
        '2026-10-21#0 2026-10-22#0 2026-10-23#0',
      );
      final forever = cycle(
        rule,
        start: d(2026, 10, 21),
        end: d(2026, 10, 22),
        forever: true,
      );
      expect(occurrencesInRange(forever, d(2026, 10, 21), d(2026, 10, 25)), hasLength(5));
    });

    test('a paused item and an empty cycle generate nothing', () {
      const rule = CycleRule(occurrences: [CycleOccurrence(day: 0, startMin: 600)]);
      expect(occurrencesInRange(cycle(rule, paused: true), d(2026, 10, 19), d(2026, 10, 30)), isEmpty);
      expect(occurrencesInRange(cycle(const CycleRule()), d(2026, 10, 19), d(2026, 10, 30)), isEmpty);
    });

    test('overrides: this day only (time / name / duration) and a skipped day', () {
      final item = cycle(
        const CycleRule(
          cycleDays: 1,
          occurrences: [CycleOccurrence(day: 0, startMin: 600, durationMin: 30)],
        ),
      );
      final out = occurrencesInRange(
        item,
        d(2026, 10, 19),
        d(2026, 10, 21),
        overrides: [
          PlanOverrideData(date: d(2026, 10, 20), index: 0, startMin: 660, durationMin: 45, name: 'Moved'),
          PlanOverrideData(date: d(2026, 10, 21), index: 0, skipped: true),
        ],
      );
      expect(out, hasLength(2));
      expect(out[1].startMin, 660);
      expect(out[1].durationMin, 45);
      expect(out[1].name, 'Moved');
    });

    test('a block that runs past midnight ends on the next local day', () {
      final item = cycle(
        const CycleRule(
          cycleDays: 1,
          occurrences: [CycleOccurrence(day: 0, startMin: 23 * 60, durationMin: 8 * 60, name: 'Sleep')],
        ),
      );
      final o = occurrencesInRange(item, d(2026, 10, 19), d(2026, 10, 19)).single;
      expect(o.startUtc, DateTime.utc(2026, 10, 19, 20));
      expect(o.endUtc, DateTime.utc(2026, 10, 20, 4)); // 07:00 local next day
    });

    test('the range can start long after the start date', () {
      final item = cycle(
        const CycleRule(
          cycleDays: 7,
          occurrences: [CycleOccurrence(day: 0, startMin: 600)],
        ),
        start: d(2026, 1, 5), // a Monday
      );
      final out = occurrencesInRange(item, d(2026, 10, 19), d(2026, 10, 26));
      expect(keys(out), '2026-10-19#0 2026-10-26#0');
    });
  });

  group('monthly', () {
    test('day 15 every month, clamped to short months (31 -> 28/30)', () {
      final fifteenth = monthly(const MonthlyRule(day: 15));
      expect(
        keys(occurrencesInRange(fifteenth, d(2026, 2, 1), d(2026, 4, 30))),
        '2026-02-15#0 2026-03-15#0 2026-04-15#0',
      );
      final thirtyFirst = monthly(const MonthlyRule(day: 31));
      expect(
        keys(occurrencesInRange(thirtyFirst, d(2026, 2, 1), d(2026, 4, 30))),
        '2026-02-28#0 2026-03-31#0 2026-04-30#0',
      );
    });

    test('the last day of the month', () {
      final item = monthly(const MonthlyRule(mode: MonthlyMode.lastDay));
      expect(
        keys(occurrencesInRange(item, d(2026, 1, 1), d(2026, 2, 28))),
        '2026-01-31#0 2026-02-28#0',
      );
      // A leap year.
      expect(
        keys(occurrencesInRange(item, d(2028, 2, 1), d(2028, 2, 29))),
        '2028-02-29#0',
      );
    });

    test('the 2nd Thursday, the last Friday', () {
      final second = monthly(
        const MonthlyRule(mode: MonthlyMode.nthWeekday, nth: 2, weekday: DateTime.thursday),
      );
      expect(
        keys(occurrencesInRange(second, d(2026, 10, 1), d(2026, 12, 31))),
        '2026-10-08#0 2026-11-12#0 2026-12-10#0',
      );
      final lastFriday = monthly(
        const MonthlyRule(mode: MonthlyMode.nthWeekday, nth: -1, weekday: DateTime.friday),
      );
      expect(
        keys(occurrencesInRange(lastFriday, d(2026, 10, 1), d(2026, 11, 30))),
        '2026-10-30#0 2026-11-27#0',
      );
    });

    test('every N months counts from the start month, up to 99999', () {
      final every3 = monthly(const MonthlyRule(everyMonths: 3, day: 10));
      expect(
        keys(occurrencesInRange(every3, d(2026, 1, 1), d(2026, 12, 31))),
        '2026-01-10#0 2026-04-10#0 2026-07-10#0 2026-10-10#0',
      );
      final huge = monthly(const MonthlyRule(everyMonths: 99999, day: 10));
      expect(
        keys(occurrencesInRange(huge, d(2026, 1, 1), d(2026, 12, 31))),
        '2026-01-10#0',
      );
      // Far in the future: nothing, and no long loop.
      expect(occurrencesInRange(huge, d(2030, 1, 1), d(2030, 12, 31)), isEmpty);
      // A range that begins mid-pattern still finds the right months.
      expect(
        keys(occurrencesInRange(every3, d(2026, 8, 1), d(2026, 10, 31))),
        '2026-10-10#0',
      );
    });

    test('start and end dates bound a monthly rule', () {
      final item = monthly(
        const MonthlyRule(day: 15),
        start: d(2026, 3, 20),
        end: d(2026, 5, 31),
      );
      expect(
        keys(occurrencesInRange(item, d(2026, 1, 1), d(2026, 12, 31))),
        '2026-04-15#0 2026-05-15#0',
      );
    });

    test('time and duration come from the rule', () {
      final item = monthly(
        const MonthlyRule(day: 1, startMin: 14 * 60, durationMin: 90, name: 'Rent'),
      );
      final o = occurrencesInRange(item, d(2026, 6, 1), d(2026, 6, 1)).single;
      expect(o.name, 'Rent');
      expect(o.startUtc, DateTime.utc(2026, 6, 1, 11));
      expect(o.endUtc, DateTime.utc(2026, 6, 1, 12, 30));
    });
  });

  group('json', () {
    test('rules survive a round trip; a damaged rule generates nothing', () {
      final item = cycle(
        const CycleRule(
          cycleDays: 3,
          occurrences: [CycleOccurrence(day: 1, startMin: 600, durationMin: 20, name: 'X', templateId: 't')],
        ),
      );
      final back = PlanItemData.decodeRule(PlanKind.cycle, item.ruleJson);
      expect(back.cycle!.cycleDays, 3);
      expect(back.cycle!.occurrences.single.name, 'X');
      expect(back.cycle!.occurrences.single.templateId, 't');
      final broken = PlanItemData.decodeRule(PlanKind.cycle, 'not json');
      expect(broken.cycle, isNull);
      final m = PlanItemData.decodeRule(
        PlanKind.monthly,
        monthly(const MonthlyRule(everyMonths: 2, mode: MonthlyMode.lastDay)).ruleJson,
      );
      expect(m.monthly!.everyMonths, 2);
      expect(m.monthly!.mode, MonthlyMode.lastDay);
    });

    test('date keys round trip', () {
      expect(planDateKey(d(2026, 3, 5)), '2026-03-05');
      expect(planDateFromKey('2026-03-05'), d(2026, 3, 5));
      expect(planDateOf(DateTime.utc(2026, 10, 19, 21, 30)), d(2026, 10, 20)); // 00:30 local
    });
  });

  group('describePlan', () {
    test('weekly, daily, every N days and monthly summaries', () {
      expect(
        describePlan(
          cycle(
            const CycleRule(
              cycleDays: 7,
              occurrences: [
                CycleOccurrence(day: 3, startMin: 570),
                CycleOccurrence(day: 0, startMin: 540),
              ],
            ),
          ),
        ),
        'Weekly: Mon 09:00, Thu 09:30',
      );
      expect(
        describePlan(
          cycle(
            const CycleRule(
              cycleDays: 1,
              occurrences: [
                CycleOccurrence(day: 0, startMin: 480),
                CycleOccurrence(day: 0, startMin: 1200),
              ],
            ),
          ),
        ),
        'Daily: 08:00, 20:00',
      );
      expect(
        describePlan(
          cycle(
            const CycleRule(
              cycleDays: 3,
              occurrences: [CycleOccurrence(day: 2, startMin: 900)],
            ),
          ),
        ),
        'Every 3 days: day 3 15:00',
      );
      expect(
        describePlan(
          monthly(
            const MonthlyRule(
              everyMonths: 2,
              mode: MonthlyMode.nthWeekday,
              nth: 2,
              weekday: DateTime.thursday,
              startMin: 1080,
            ),
          ),
        ),
        'Every 2 months: 2nd Thu 18:00',
      );
      expect(describePlan(monthly(const MonthlyRule(mode: MonthlyMode.lastDay))), 'Every month: last day 09:00');
      expect(describePlan(cycle(const CycleRule())), 'Nothing planned');
    });
  });
}
