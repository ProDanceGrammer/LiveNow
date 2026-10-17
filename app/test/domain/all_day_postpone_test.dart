import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/all_day_postpone.dart';
import 'package:livenow/domain/postpone_rules.dart';

// Istanbul is UTC+3 all year (no DST since 2016): local midnight = 21:00 UTC the
// day before. 2024-01-01 is a Monday.
DateTime midnight(int y, int m, int d) => DateTime.utc(y, m, d - 1, 21);

void main() {
  setUpAll(initPostponeTimeZoneData);

  group('allDayToMonday: the next Monday AFTER the card\'s day', () {
    final cases = <String, (DateTime, DateTime)>{
      'Monday goes a week ahead (never the same day)': (
        midnight(2024, 1, 1),
        midnight(2024, 1, 8),
      ),
      'Tuesday': (midnight(2024, 1, 2), midnight(2024, 1, 8)),
      'Wednesday': (midnight(2024, 1, 3), midnight(2024, 1, 8)),
      'Thursday': (midnight(2024, 1, 4), midnight(2024, 1, 8)),
      'Friday': (midnight(2024, 1, 5), midnight(2024, 1, 8)),
      'Saturday': (midnight(2024, 1, 6), midnight(2024, 1, 8)),
      'Sunday goes to tomorrow': (midnight(2024, 1, 7), midnight(2024, 1, 8)),
    };
    for (final e in cases.entries) {
      test(e.key, () => expect(allDayToMonday(e.value.$1), e.value.$2));
    }

    test('across a month and a year end', () {
      // Wed 31 Jan 2024 -> Mon 5 Feb; Fri 29 Dec 2023 -> Mon 1 Jan 2024.
      expect(allDayToMonday(midnight(2024, 1, 31)), midnight(2024, 2, 5));
      expect(allDayToMonday(midnight(2023, 12, 29)), midnight(2024, 1, 1));
    });

    test('the Istanbul day decides, not the UTC date', () {
      // 22:30 UTC on Sunday 7 Jan is already 01:30 on MONDAY 8 Jan in Istanbul:
      // the next Monday after that day is 15 Jan.
      expect(
        allDayToMonday(DateTime.utc(2024, 1, 7, 22, 30)),
        midnight(2024, 1, 15),
      );
      // 20:59 UTC on Sunday 7 Jan is still Sunday 23:59 in Istanbul: tomorrow.
      expect(
        allDayToMonday(DateTime.utc(2024, 1, 7, 20, 59)),
        midnight(2024, 1, 8),
      );
    });

    test('a start that is not exactly midnight still counts as its day', () {
      // Wednesday 15:00 local = 12:00 UTC.
      expect(
        allDayToMonday(DateTime.utc(2024, 1, 3, 12)),
        midnight(2024, 1, 8),
      );
    });
  });

  group('allDayPlusSevenDays: the same weekday next week', () {
    test('a plain day', () {
      expect(
        allDayPlusSevenDays(midnight(2024, 1, 3)),
        midnight(2024, 1, 10),
      );
    });

    test('across a month and a year end', () {
      expect(
        allDayPlusSevenDays(midnight(2024, 1, 29)),
        midnight(2024, 2, 5),
      );
      expect(
        allDayPlusSevenDays(midnight(2023, 12, 28)),
        midnight(2024, 1, 4),
      );
    });

    test('a leap day', () {
      expect(
        allDayPlusSevenDays(midnight(2024, 2, 26)),
        midnight(2024, 3, 4),
      );
    });

    test('the Istanbul day decides, not the UTC date', () {
      // 22:30 UTC on 1 Jan is 01:30 on 2 Jan in Istanbul: +7 days = 9 Jan.
      expect(
        allDayPlusSevenDays(DateTime.utc(2024, 1, 1, 22, 30)),
        midnight(2024, 1, 9),
      );
    });

    test('the result is always a local midnight and 7 weekdays later', () {
      for (var d = 1; d <= 31; d++) {
        final start = midnight(2024, 1, d);
        final moved = allDayPlusSevenDays(start);
        expect(moved.difference(start), const Duration(days: 7), reason: '$d');
        expect(moved.hour, 21, reason: '$d'); // 00:00 Istanbul
        expect(moved.minute, 0);
      }
    });
  });
}
