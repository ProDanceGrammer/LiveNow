import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/time_edit_math.dart';

void main() {
  DateTime w(int y, int mo, int d, [int h = 0, int mi = 0]) =>
      DateTime.utc(y, mo, d, h, mi);

  group('addUnit carry', () {
    test('minutes roll into the next hour and back', () {
      expect(
        addUnit(w(2026, 10, 2, 14, 59), TimeUnit.minute, 1),
        w(2026, 10, 2, 15, 0),
      );
      expect(
        addUnit(w(2026, 10, 2, 15, 0), TimeUnit.minute, -1),
        w(2026, 10, 2, 14, 59),
      );
    });

    test('hours roll into the next day', () {
      expect(
        addUnit(w(2026, 10, 2, 23, 30), TimeUnit.hour, 1),
        w(2026, 10, 3, 0, 30),
      );
    });

    test('days roll into the next month and year', () {
      expect(addUnit(w(2026, 10, 31), TimeUnit.day, 1), w(2026, 11, 1));
      expect(
        addUnit(w(2026, 12, 31, 8, 5), TimeUnit.day, 1),
        w(2027, 1, 1, 8, 5),
      );
      expect(addUnit(w(2026, 3, 1), TimeUnit.day, -1), w(2026, 2, 28));
    });

    test('months roll into the next year and clamp the day', () {
      expect(addUnit(w(2026, 12, 15), TimeUnit.month, 1), w(2027, 1, 15));
      expect(addUnit(w(2026, 1, 15), TimeUnit.month, -1), w(2025, 12, 15));
      expect(addUnit(w(2026, 1, 31), TimeUnit.month, 1), w(2026, 2, 28));
      expect(addUnit(w(2028, 1, 31), TimeUnit.month, 1), w(2028, 2, 29));
      expect(
        addUnit(w(2026, 3, 31, 9, 15), TimeUnit.month, -1),
        w(2026, 2, 28, 9, 15),
      );
    });

    test('years clamp 29 Feb', () {
      expect(addUnit(w(2028, 2, 29), TimeUnit.year, 1), w(2029, 2, 28));
      expect(addUnit(w(2028, 2, 29), TimeUnit.year, 4), w(2032, 2, 29));
    });
  });

  group('setUnit clamps', () {
    test('minutes and hours', () {
      expect(
        setUnit(w(2026, 10, 2, 14, 30), TimeUnit.minute, 75),
        w(2026, 10, 2, 14, 59),
      );
      expect(
        setUnit(w(2026, 10, 2, 14, 30), TimeUnit.hour, 25),
        w(2026, 10, 2, 23, 30),
      );
    });

    test('day is limited by the month length', () {
      expect(setUnit(w(2026, 4, 10), TimeUnit.day, 31), w(2026, 4, 30));
      expect(setUnit(w(2026, 2, 10), TimeUnit.day, 0), w(2026, 2, 1));
    });

    test('changing the month clamps the day', () {
      expect(setUnit(w(2026, 1, 31), TimeUnit.month, 2), w(2026, 2, 28));
      expect(setUnit(w(2026, 1, 31), TimeUnit.month, 13), w(2026, 12, 31));
    });

    test('changing the year keeps the rest', () {
      expect(
        setUnit(w(2026, 10, 2, 7, 8), TimeUnit.year, 2030),
        w(2030, 10, 2, 7, 8),
      );
    });
  });

  group('segment order', () {
    test('hours <-> minutes <-> day <-> month <-> year, no wrap', () {
      var u = TimeUnit.hour;
      final seen = [u];
      for (var i = 0; i < 6; i++) {
        u = stepUnit(timedUnitOrder, u, 1);
        seen.add(u);
      }
      expect(seen, [
        TimeUnit.hour,
        TimeUnit.minute,
        TimeUnit.day,
        TimeUnit.month,
        TimeUnit.year,
        TimeUnit.year,
        TimeUnit.year,
      ]);
      expect(stepUnit(timedUnitOrder, TimeUnit.hour, -1), TimeUnit.hour);
    });

    test('all-day rows have the date segments only', () {
      expect(stepUnit(dateUnitOrder, TimeUnit.day, -1), TimeUnit.day);
      expect(stepUnit(dateUnitOrder, TimeUnit.day, 1), TimeUnit.month);
    });
  });
}
