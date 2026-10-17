import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/domain/work_hours.dart';

// Europe/Istanbul has had a fixed UTC+3 offset (no DST) since 2016, so every
// "local" instant below is just UTC-3h — no timezone package needed to build
// the fixtures, only to exercise the code under test.
//
// Calendar anchor used throughout: 2024-01-01 is a Monday.
//   Mon 01-01, Tue 01-02, Wed 01-03, Thu 01-04, Fri 01-05,
//   Sat 01-06, Sun 01-07, Mon 01-08.

DateTime istanbul(int y, int m, int d, [int h = 0, int min = 0]) =>
    DateTime.utc(y, m, d, h - 3, min);

ActionSchedule hourLong(DateTime start) =>
    ActionSchedule(startAt: start, endAt: start.add(const Duration(hours: 1)));

void main() {
  setUpAll(initPostponeTimeZoneData);

  group('plusOneHour', () {
    test('shifts a future start further out (duration preserved)', () {
      final now = istanbul(2024, 1, 1, 9);
      final current = ActionSchedule(
        startAt: istanbul(2024, 1, 5, 10),
        endAt: istanbul(2024, 1, 5, 11, 30),
      );
      final next = applyPostponeRule(
        PostponeRule.plusOneHour,
        current,
        nowUtc: now,
      );
      expect(next.startAt, istanbul(2024, 1, 5, 11));
      expect(next.endAt, istanbul(2024, 1, 5, 12, 30));
    });

    test('shifts from the exact existing start even if it is overdue', () {
      // e.g. started at 18:43 and never finished; +1 hour must become
      // 19:43, not "now + 1 hour".
      final now = istanbul(2024, 1, 1, 11);
      final current = ActionSchedule(startAt: istanbul(2023, 12, 31, 18, 43));
      final next = applyPostponeRule(
        PostponeRule.plusOneHour,
        current,
        nowUtc: now,
      );
      expect(next.startAt, istanbul(2023, 12, 31, 19, 43));
      expect(next.endAt, isNull);
    });

    test('an unscheduled action shifts from now', () {
      final now = istanbul(2024, 1, 1, 9);
      final next = applyPostponeRule(
        PostponeRule.plusOneHour,
        const ActionSchedule(),
        nowUtc: now,
      );
      expect(next.startAt, istanbul(2024, 1, 1, 10));
    });
  });

  test('plusFiveHours shifts by five hours', () {
    final now = istanbul(2024, 1, 1, 9);
    final current = ActionSchedule(startAt: istanbul(2024, 1, 1, 9));
    final next = applyPostponeRule(
      PostponeRule.plusFiveHours,
      current,
      nowUtc: now,
    );
    expect(next.startAt, istanbul(2024, 1, 1, 14));
  });

  group('prolongThirtyMinutes', () {
    test('extends the end only, leaving start untouched', () {
      final current = ActionSchedule(
        startAt: istanbul(2024, 1, 1, 9),
        endAt: istanbul(2024, 1, 1, 10),
      );
      final next = applyPostponeRule(
        PostponeRule.prolongThirtyMinutes,
        current,
        nowUtc: istanbul(2024, 1, 1, 9, 30),
      );
      expect(next.startAt, current.startAt);
      expect(next.endAt, istanbul(2024, 1, 1, 10, 30));
    });

    test('with no end yet, extends 30 minutes from now', () {
      final now = istanbul(2024, 1, 1, 9, 30);
      final next = applyPostponeRule(
        PostponeRule.prolongThirtyMinutes,
        const ActionSchedule(),
        nowUtc: now,
      );
      expect(next.endAt, istanbul(2024, 1, 1, 10));
    });
  });

  group('afterWork (18:00)', () {
    test('start before 18:00 -> same day 18:00, duration kept', () {
      final next = applyPostponeRule(
        PostponeRule.afterWork,
        hourLong(istanbul(2024, 1, 2, 10)),
        nowUtc: istanbul(2024, 1, 1, 9),
      );
      expect(next.startAt, istanbul(2024, 1, 2, 18));
      expect(next.endAt, istanbul(2024, 1, 2, 19));
    });

    test('start at/after 18:00 -> next day 18:00', () {
      for (final h in [18, 20]) {
        final next = applyPostponeRule(
          PostponeRule.afterWork,
          hourLong(istanbul(2024, 1, 2, h)),
          nowUtc: istanbul(2024, 1, 1, 9),
        );
        expect(next.startAt, istanbul(2024, 1, 3, 18));
      }
    });

    test('unscheduled uses now as base', () {
      final early = applyPostponeRule(
        PostponeRule.afterWork,
        const ActionSchedule(),
        nowUtc: istanbul(2024, 1, 1, 10),
      );
      expect(early.startAt, istanbul(2024, 1, 1, 18));
      final late = applyPostponeRule(
        PostponeRule.afterWork,
        const ActionSchedule(),
        nowUtc: istanbul(2024, 1, 1, 20),
      );
      expect(late.startAt, istanbul(2024, 1, 2, 18));
    });
  });

  group('morning (09:00)', () {
    test('start before 09:00 -> same day 09:00, duration kept', () {
      final next = applyPostponeRule(
        PostponeRule.morning,
        hourLong(istanbul(2024, 1, 12, 8)),
        nowUtc: istanbul(2024, 1, 3, 10),
      );
      expect(next.startAt, istanbul(2024, 1, 12, 9));
      expect(next.endAt, istanbul(2024, 1, 12, 10));
    });

    test('start after 09:00 -> next day 09:00', () {
      final next = applyPostponeRule(
        PostponeRule.morning,
        hourLong(istanbul(2024, 1, 12, 14)),
        nowUtc: istanbul(2024, 1, 3, 10),
      );
      expect(next.startAt, istanbul(2024, 1, 13, 9));
    });

    test('double press: 08:00 -> same day 09:00 -> next day 09:00', () {
      final now = istanbul(2024, 1, 3, 10);
      final first = applyPostponeRule(
        PostponeRule.morning,
        hourLong(istanbul(2024, 1, 12, 8)),
        nowUtc: now,
      );
      expect(first.startAt, istanbul(2024, 1, 12, 9));
      final second = applyPostponeRule(
        PostponeRule.morning,
        first,
        nowUtc: now,
      );
      expect(second.startAt, istanbul(2024, 1, 13, 9));
      expect(second.endAt, istanbul(2024, 1, 13, 10));
    });

    test('overdue action follows its own date, not now', () {
      final next = applyPostponeRule(
        PostponeRule.morning,
        hourLong(istanbul(2024, 1, 1, 8)),
        nowUtc: istanbul(2024, 1, 3, 10),
      );
      expect(next.startAt, istanbul(2024, 1, 1, 9));
    });

    test('unscheduled uses now; any weekday (Friday night -> Saturday)', () {
      final next = applyPostponeRule(
        PostponeRule.morning,
        const ActionSchedule(),
        nowUtc: istanbul(2024, 1, 5, 22),
      );
      expect(next.startAt, istanbul(2024, 1, 6, 9));
    });

    test('month rollover is wall-clock safe', () {
      final next = applyPostponeRule(
        PostponeRule.morning,
        hourLong(istanbul(2024, 1, 31, 23)),
        nowUtc: istanbul(2024, 1, 3, 10),
      );
      expect(next.startAt, istanbul(2024, 2, 1, 9));
    });
  });

  group('workingMorning with custom working days', () {
    test('Saturday works: Friday afternoon -> Saturday morning', () {
      final next = applyPostponeRule(
        PostponeRule.workingMorning,
        hourLong(istanbul(2024, 1, 5, 10)),
        nowUtc: istanbul(2024, 1, 1, 9),
        hours: const WorkHours(workingWeekdays: {1, 2, 3, 4, 5, 6}),
      );
      expect(next.startAt, istanbul(2024, 1, 6, 9));
    });

    test('only Wednesday works: Monday -> Wednesday', () {
      final next = applyPostponeRule(
        PostponeRule.workingMorning,
        hourLong(istanbul(2024, 1, 1, 10)),
        nowUtc: istanbul(2024, 1, 1, 9),
        hours: const WorkHours(workingWeekdays: {3}),
      );
      expect(next.startAt, istanbul(2024, 1, 3, 9));
    });

    test('JSON round-trip; an empty or damaged list falls back to Mon-Fri', () {
      const h = WorkHours(workingWeekdays: {1, 3, 7});
      expect(WorkHours.fromJson(h.toJson()), h);
      expect(
        WorkHours.fromJson({'workingWeekdays': <int>[]}).workingWeekdays,
        {1, 2, 3, 4, 5},
      );
      expect(
        WorkHours.fromJson({'workingWeekdays': 'x'}).workingWeekdays,
        {1, 2, 3, 4, 5},
      );
    });
  });

  group('workingMorning', () {
    test('Friday after 09:00 -> Monday 09:00', () {
      final next = applyPostponeRule(
        PostponeRule.workingMorning,
        hourLong(istanbul(2024, 1, 5, 10)),
        nowUtc: istanbul(2024, 1, 1, 9),
      );
      expect(next.startAt, istanbul(2024, 1, 8, 9));
      expect(next.endAt, istanbul(2024, 1, 8, 10));
    });

    test('Friday before 09:00 -> same Friday 09:00', () {
      final next = applyPostponeRule(
        PostponeRule.workingMorning,
        hourLong(istanbul(2024, 1, 5, 8)),
        nowUtc: istanbul(2024, 1, 1, 9),
      );
      expect(next.startAt, istanbul(2024, 1, 5, 9));
    });

    test('Saturday early -> Monday (non-working same day skipped)', () {
      final next = applyPostponeRule(
        PostponeRule.workingMorning,
        hourLong(istanbul(2024, 1, 6, 8)),
        nowUtc: istanbul(2024, 1, 1, 9),
      );
      expect(next.startAt, istanbul(2024, 1, 8, 9));
    });

    test('unscheduled uses now (Friday 10:00 -> Monday)', () {
      final next = applyPostponeRule(
        PostponeRule.workingMorning,
        const ActionSchedule(),
        nowUtc: istanbul(2024, 1, 5, 10),
      );
      expect(next.startAt, istanbul(2024, 1, 8, 9));
    });

    test('overdue action follows its own date', () {
      final next = applyPostponeRule(
        PostponeRule.workingMorning,
        hourLong(istanbul(2024, 1, 1, 8)),
        nowUtc: istanbul(2024, 1, 5, 10),
      );
      expect(next.startAt, istanbul(2024, 1, 1, 9));
    });
  });

  group('nextMondayMorning', () {
    test('on a Monday, jumps to next week (never today)', () {
      final next = applyPostponeRule(
        PostponeRule.nextMondayMorning,
        hourLong(istanbul(2024, 1, 1, 8)),
        nowUtc: istanbul(2024, 1, 1, 7),
      );
      expect(next.startAt, istanbul(2024, 1, 8, 9));
      expect(next.endAt, istanbul(2024, 1, 8, 10));
    });

    test('mid-week start -> the coming Monday', () {
      final next = applyPostponeRule(
        PostponeRule.nextMondayMorning,
        hourLong(istanbul(2024, 1, 3, 12)),
        nowUtc: istanbul(2024, 1, 1, 7),
      );
      expect(next.startAt, istanbul(2024, 1, 8, 9));
    });

    test('unscheduled uses now', () {
      final next = applyPostponeRule(
        PostponeRule.nextMondayMorning,
        const ActionSchedule(),
        nowUtc: istanbul(2024, 1, 3, 12),
      );
      expect(next.startAt, istanbul(2024, 1, 8, 9));
    });

    test('overdue action follows its own date', () {
      final next = applyPostponeRule(
        PostponeRule.nextMondayMorning,
        hourLong(istanbul(2023, 12, 20, 8)),
        nowUtc: istanbul(2024, 1, 3, 12),
      );
      expect(next.startAt, istanbul(2023, 12, 25, 9));
    });
  });

  group('nextWeek (+7 days)', () {
    test('a future action moves another 7 days out', () {
      final now = istanbul(2024, 1, 1, 9);
      final current = ActionSchedule(startAt: istanbul(2024, 1, 10, 9));
      final next = applyPostponeRule(
        PostponeRule.nextWeek,
        current,
        nowUtc: now,
      );
      expect(next.startAt, istanbul(2024, 1, 17, 9));
    });

    test('an overdue habit still moves 7 days from its own last start', () {
      final now = istanbul(2024, 1, 8, 9);
      final current = ActionSchedule(startAt: istanbul(2023, 12, 1, 9));
      final next = applyPostponeRule(
        PostponeRule.nextWeek,
        current,
        nowUtc: now,
      );
      expect(next.startAt, istanbul(2023, 12, 8, 9));
    });
  });

  group('edge cases', () {
    test('Morning at exactly 09:00 goes to the NEXT day (strictly after the start)', () {
      final next = applyPostponeRule(
        PostponeRule.morning,
        hourLong(istanbul(2024, 1, 2, 9)),
        nowUtc: istanbul(2024, 1, 2, 8),
      );
      expect(next.startAt, istanbul(2024, 1, 3, 9));
      expect(next.endAt, istanbul(2024, 1, 3, 10));
    });

    test('Next working morning at exactly 09:00 on Friday goes to Monday', () {
      final next = applyPostponeRule(
        PostponeRule.workingMorning,
        hourLong(istanbul(2024, 1, 5, 9)),
        nowUtc: istanbul(2024, 1, 5, 8),
      );
      expect(next.startAt, istanbul(2024, 1, 8, 9));
    });

    test('After work at 17:59 is today 18:00, at exactly 18:00 it is tomorrow', () {
      DateTime? at(int h, int m) => applyPostponeRule(
        PostponeRule.afterWork,
        hourLong(istanbul(2024, 1, 2, h, m)),
        nowUtc: istanbul(2024, 1, 2, 8),
      ).startAt;
      expect(at(17, 59), istanbul(2024, 1, 2, 18));
      expect(at(18, 0), istanbul(2024, 1, 3, 18));
    });

    test('Next Monday morning from a Sunday is tomorrow, even at 23:30', () {
      for (final start in [istanbul(2024, 1, 7, 8), istanbul(2024, 1, 7, 23, 30)]) {
        final next = applyPostponeRule(
          PostponeRule.nextMondayMorning,
          hourLong(start),
          nowUtc: istanbul(2024, 1, 6, 8),
        );
        expect(next.startAt, istanbul(2024, 1, 8, 9), reason: '$start');
      }
    });

    test('Next working morning from a Saturday or Sunday is Monday', () {
      for (final day in [6, 7]) {
        final next = applyPostponeRule(
          PostponeRule.workingMorning,
          hourLong(istanbul(2024, 1, day, 12)),
          nowUtc: istanbul(2024, 1, 5, 8),
        );
        expect(next.startAt, istanbul(2024, 1, 8, 9), reason: 'day $day');
      }
    });

    // Istanbul is 3 hours ahead of UTC: 22:00 UTC on 1 Jan is already 01:00 on
    // 2 Jan there. Every other fixture keeps the same date in both zones.
    test('the Istanbul date, not the UTC date, decides the day', () {
      final start = DateTime.utc(2024, 1, 1, 22); // 01:00 Tuesday 2 Jan Istanbul
      final schedule = ActionSchedule(
        startAt: start,
        endAt: start.add(const Duration(hours: 1)),
      );
      DateTime? run(PostponeRule rule) => applyPostponeRule(
        rule,
        schedule,
        nowUtc: DateTime.utc(2024, 1, 1, 20),
      ).startAt;

      // Morning: 09:00 on 2 Jan Istanbul (= 06:00 UTC), not on 1 Jan.
      expect(run(PostponeRule.morning), DateTime.utc(2024, 1, 2, 6));
      // After work: 18:00 on 2 Jan Istanbul (= 15:00 UTC).
      expect(run(PostponeRule.afterWork), DateTime.utc(2024, 1, 2, 15));
      // Working morning: Tuesday 2 Jan is a working day, 09:00 that day.
      expect(run(PostponeRule.workingMorning), DateTime.utc(2024, 1, 2, 6));
      // Next Monday morning: Monday 8 Jan 09:00 Istanbul.
      expect(run(PostponeRule.nextMondayMorning), DateTime.utc(2024, 1, 8, 6));
      // +1 h and next week keep the wall clock: 02:00 Istanbul, and 9 Jan 01:00.
      expect(run(PostponeRule.plusOneHour), DateTime.utc(2024, 1, 1, 23));
      expect(run(PostponeRule.nextWeek), DateTime.utc(2024, 1, 8, 22));
    });

    test('Saturday 22:30 UTC is already Sunday in Istanbul: working morning is Monday', () {
      final start = DateTime.utc(2024, 1, 6, 22, 30); // 01:30 Sunday 7 Jan Istanbul
      final next = applyPostponeRule(
        PostponeRule.workingMorning,
        ActionSchedule(startAt: start, endAt: start.add(const Duration(hours: 1))),
        nowUtc: DateTime.utc(2024, 1, 6, 12),
      );
      expect(next.startAt, DateTime.utc(2024, 1, 8, 6)); // Monday 09:00 Istanbul
    });
  });

  group('working hours', () {
    const custom = WorkHours(
      workStart: 9 * 60,
      workEnd: 17 * 60 + 30,
      morning: 8 * 60 + 15,
    );

    test('after work lands at the configured end of work', () {
      final next = applyPostponeRule(
        PostponeRule.afterWork,
        hourLong(istanbul(2024, 1, 2, 10)),
        nowUtc: istanbul(2024, 1, 2, 9),
        hours: custom,
      );
      expect(next.startAt, istanbul(2024, 1, 2, 17, 30));
    });

    test('morning uses its own time, not the start of work', () {
      final next = applyPostponeRule(
        PostponeRule.morning,
        hourLong(istanbul(2024, 1, 2, 10)),
        nowUtc: istanbul(2024, 1, 2, 9),
        hours: custom,
      );
      // 08:15 today is before the 10:00 start, so it is tomorrow's.
      expect(next.startAt, istanbul(2024, 1, 3, 8, 15));
    });

    test(
      'next working morning skips the weekend; next Monday uses the morning',
      () {
        final fri = hourLong(istanbul(2024, 1, 5, 12));
        expect(
          applyPostponeRule(
            PostponeRule.workingMorning,
            fri,
            nowUtc: istanbul(2024, 1, 5, 9),
            hours: custom,
          ).startAt,
          istanbul(2024, 1, 8, 8, 15),
        );
        expect(
          applyPostponeRule(
            PostponeRule.nextMondayMorning,
            fri,
            nowUtc: istanbul(2024, 1, 5, 9),
            hours: custom,
          ).startAt,
          istanbul(2024, 1, 8, 8, 15),
        );
      },
    );

    test('the defaults keep the old 18:00 / 09:00 behaviour', () {
      final next = applyPostponeRule(
        PostponeRule.afterWork,
        hourLong(istanbul(2024, 1, 2, 10)),
        nowUtc: istanbul(2024, 1, 2, 9),
      );
      expect(next.startAt, istanbul(2024, 1, 2, 18));
    });

    test('WorkHours: validation, formatting and a damaged saved value', () {
      expect(WorkHours.defaults.problem, isNull);
      expect(const WorkHours(workStart: 600, workEnd: 600).problem, isNotNull);
      expect(const WorkHours(workEnd: 24 * 60 + 5).problem, isNotNull);
      expect(WorkHours.format(8 * 60 + 5), '08:05');
      expect(WorkHours.fromJson(custom.toJson()), custom);
      expect(WorkHours.fromJson('junk'), WorkHours.defaults);
      expect(
        WorkHours.fromJson({'workStart': 700, 'workEnd': 100}),
        WorkHours.defaults,
      );
      expect(
        WorkHours.fromJson({'workEnd': 'x'}).workEnd,
        WorkHours.defaults.workEnd,
      );
    });
  });
}
