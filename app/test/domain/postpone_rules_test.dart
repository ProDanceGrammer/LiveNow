import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/postpone_rules.dart';

// Europe/Istanbul has had a fixed UTC+3 offset (no DST) since 2016, so every
// "local" instant below is just UTC-3h — no timezone package needed to build
// the fixtures, only to exercise the code under test.
//
// Calendar anchor used throughout: 2024-01-01 is a Monday.
//   Mon 01-01, Tue 01-02, Wed 01-03, Thu 01-04, Fri 01-05,
//   Sat 01-06, Sun 01-07, Mon 01-08.

DateTime istanbul(int y, int m, int d, [int h = 0, int min = 0]) =>
    DateTime.utc(y, m, d, h - 3, min);

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
    test('before 18:00 today -> today 18:00', () {
      final now = istanbul(2024, 1, 1, 10);
      final next = applyPostponeRule(
        PostponeRule.afterWork,
        const ActionSchedule(),
        nowUtc: now,
      );
      expect(next.startAt, istanbul(2024, 1, 1, 18));
    });

    test('after 18:00 today -> tomorrow 18:00', () {
      final now = istanbul(2024, 1, 1, 20);
      final next = applyPostponeRule(
        PostponeRule.afterWork,
        const ActionSchedule(),
        nowUtc: now,
      );
      expect(next.startAt, istanbul(2024, 1, 2, 18));
    });
  });

  test('morning always means tomorrow 09:00, any weekday', () {
    final now = istanbul(2024, 1, 5, 22); // Friday night
    final next = applyPostponeRule(
      PostponeRule.morning,
      const ActionSchedule(),
      nowUtc: now,
    );
    expect(next.startAt, istanbul(2024, 1, 6, 9)); // Saturday, not skipped
  });

  test('workingMorning skips the weekend: Friday -> Monday 09:00', () {
    final now = istanbul(2024, 1, 5, 10); // Friday
    final next = applyPostponeRule(
      PostponeRule.workingMorning,
      const ActionSchedule(),
      nowUtc: now,
    );
    expect(next.startAt, istanbul(2024, 1, 8, 9)); // Monday
  });

  group('nextMondayMorning', () {
    test('on a Monday, jumps to next week (never today)', () {
      final now = istanbul(2024, 1, 1, 8); // Monday, before 09:00
      final next = applyPostponeRule(
        PostponeRule.nextMondayMorning,
        const ActionSchedule(),
        nowUtc: now,
      );
      expect(next.startAt, istanbul(2024, 1, 8, 9));
    });

    test('mid-week, jumps to the coming Monday', () {
      final now = istanbul(2024, 1, 3, 12); // Wednesday
      final next = applyPostponeRule(
        PostponeRule.nextMondayMorning,
        const ActionSchedule(),
        nowUtc: now,
      );
      expect(next.startAt, istanbul(2024, 1, 8, 9));
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
}
