import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/duration_rules.dart';

void main() {
  final t0 = DateTime.utc(2026, 1, 1, 10);

  group('predictedDuration', () {
    const own = Duration(minutes: 25);

    test('countable average wins over everything', () {
      expect(
        predictedDuration(
          ownDuration: own,
          countableAverage: const Duration(minutes: 40),
          chainSamples: const [Duration(minutes: 10)],
        ),
        const Duration(minutes: 40),
      );
    });
    test('chain samples are averaged when there is no countable average', () {
      expect(
        predictedDuration(
          ownDuration: own,
          chainSamples: const [Duration(minutes: 10), Duration(minutes: 20)],
        ),
        const Duration(minutes: 15),
      );
    });
    test('a zero countable average falls through', () {
      expect(
        predictedDuration(
          ownDuration: own,
          countableAverage: Duration.zero,
          chainSamples: const [Duration(minutes: 10)],
        ),
        const Duration(minutes: 10),
      );
    });
    test('falls back to the own duration', () {
      expect(predictedDuration(ownDuration: own), own);
    });
  });

  group('computeActionDuration', () {
    test('scheduled uses end - start', () {
      expect(
        computeActionDuration(
          startAt: t0,
          endAt: t0.add(const Duration(minutes: 25)),
          legacyEstimatedMinutes: 90,
        ),
        const Duration(minutes: 25),
      );
    });
    test('zero gap is kept', () {
      expect(computeActionDuration(startAt: t0, endAt: t0), Duration.zero);
    });
    test('unscheduled uses legacy estimate, else default', () {
      expect(
        computeActionDuration(
          startAt: null,
          endAt: null,
          legacyEstimatedMinutes: 45,
        ),
        const Duration(minutes: 45),
      );
      expect(
        computeActionDuration(startAt: null, endAt: null),
        defaultActionDuration,
      );
      expect(
        computeActionDuration(
          startAt: null,
          endAt: null,
          legacyEstimatedMinutes: 0,
        ),
        defaultActionDuration,
      );
    });
    test('half-set or inverted range falls through', () {
      expect(
        computeActionDuration(startAt: t0, endAt: null),
        defaultActionDuration,
      );
      expect(
        computeActionDuration(
          startAt: t0,
          endAt: t0.subtract(const Duration(hours: 1)),
          legacyEstimatedMinutes: 5,
        ),
        const Duration(minutes: 5),
      );
    });
  });

  group('formatDuration', () {
    String f({int d = 0, int h = 0, int m = 0, int s = 0}) =>
        formatDuration(Duration(days: d, hours: h, minutes: m, seconds: s));
    test('basic examples', () {
      expect(f(s: 20), '20 sec');
      expect(f(m: 1), '1 min');
      expect(f(m: 53), '53 min');
      expect(f(h: 1, m: 23), '1 hour 23 min');
      expect(f(h: 7), '7 hours');
      expect(f(d: 2), '2 days');
    });
    test('singular/plural', () {
      expect(f(s: 1), '1 sec');
      expect(f(h: 1), '1 hour');
      expect(f(h: 2), '2 hours');
      expect(f(d: 1), '1 day');
      expect(f(d: 1, h: 1), '1 day 1 hour');
      expect(f(d: 3, h: 5), '3 days 5 hours');
    });
    test('two most significant units, skipping zero neighbours', () {
      expect(f(h: 1, s: 5), '1 hour');
      expect(f(d: 1, m: 30), '1 day');
      expect(f(h: 1, m: 23, s: 45), '1 hour 23 min');
    });
    test('seconds only show under a minute', () {
      expect(f(s: 59), '59 sec');
      expect(f(m: 1, s: 20), '1 min');
      expect(f(m: 20, s: 26), '20 min');
      expect(f(m: 59, s: 59), '59 min');
      expect(f(s: 60), '1 min');
    });
    test('zero and negative', () {
      expect(formatDuration(Duration.zero), '0 sec');
      expect(formatDuration(const Duration(seconds: -5)), '0 sec');
    });
  });
}
