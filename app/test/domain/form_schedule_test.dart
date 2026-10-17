import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/form_schedule.dart';

DateTime t(int h, [int m = 0, int s = 0]) => DateTime.utc(2026, 10, 18, h, m, s);

void main() {
  group('defaultNewActionSchedule', () {
    test('starts now, to the minute, and lasts an hour', () {
      final d = defaultNewActionSchedule(
        DateTime.utc(2026, 10, 18, 14, 7, 42, 123, 456),
      );
      expect(d.start, DateTime.utc(2026, 10, 18, 14, 7));
      expect(d.end, DateTime.utc(2026, 10, 18, 15, 7));
    });

    test('crosses midnight and month ends', () {
      final d = defaultNewActionSchedule(DateTime.utc(2026, 10, 31, 23, 30, 5));
      expect(d.start, DateTime.utc(2026, 10, 31, 23, 30));
      expect(d.end, DateTime.utc(2026, 11, 1, 0, 30));
    });
  });

  group('formStartNow', () {
    test('starts now and keeps the current length', () {
      final r = formStartNow(start: t(9), end: t(10, 30), nowUtc: t(14, 5, 9));
      expect(r.start, t(14, 5, 9));
      expect(r.end, t(15, 35, 9)); // 90 minutes after now
    });

    test('without times it is an hour', () {
      final r = formStartNow(start: null, end: null, nowUtc: t(14));
      expect(r.end.difference(r.start), const Duration(hours: 1));
    });

    test('an inverted or half-set range counts as an hour', () {
      expect(
        formStartNow(start: t(12), end: t(11), nowUtc: t(14)).end,
        t(15),
      );
      expect(formStartNow(start: t(12), end: null, nowUtc: t(14)).end, t(15));
    });
  });

  group('formFinishNow', () {
    test('ends now and keeps a start that already happened', () {
      final r = formFinishNow(start: t(13), end: t(16), nowUtc: t(14, 30));
      expect(r.start, t(13));
      expect(r.end, t(14, 30));
    });

    test('a start still ahead is back-projected by the current length', () {
      final r = formFinishNow(start: t(20), end: t(21, 30), nowUtc: t(14));
      expect(r.start, t(12, 30)); // 90 minutes before now
      expect(r.end, t(14));
    });

    test('no start: back-projected by an hour', () {
      final r = formFinishNow(start: null, end: null, nowUtc: t(14));
      expect(r.start, t(13));
      expect(r.end, t(14));
    });

    test('a start exactly now is kept (a zero-length run)', () {
      final r = formFinishNow(start: t(14), end: t(15), nowUtc: t(14));
      expect(r.start, t(14));
      expect(r.end, t(14));
    });
  });
}
