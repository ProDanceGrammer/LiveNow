import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/done_rule.dart';

void main() {
  group('unscheduled (no start_at at all)', () {
    test('mirrors the manual done flag when true', () {
      expect(
        isDoneBefore(startAt: null, endAt: null, isAllDay: false, done: true),
        isTrue,
      );
    });

    test('mirrors the manual done flag when false', () {
      expect(
        isDoneBefore(startAt: null, endAt: null, isAllDay: false, done: false),
        isFalse,
      );
    });
  });

  group('scheduled, not all-day (timed)', () {
    test('is done once end_at is in the past, regardless of the manual flag', () {
      final past = DateTime.now().toUtc().subtract(const Duration(hours: 1));
      expect(
        isDoneBefore(
          startAt: past.subtract(const Duration(hours: 1)),
          endAt: past,
          isAllDay: false,
          done: false,
        ),
        isTrue,
      );
    });

    test('is not done while end_at is still in the future, even if the manual flag is true', () {
      final future = DateTime.now().toUtc().add(const Duration(hours: 1));
      expect(
        isDoneBefore(
          startAt: DateTime.now().toUtc(),
          endAt: future,
          isAllDay: false,
          done: true,
        ),
        isFalse,
      );
    });

    test('is not done when scheduled but end_at is null', () {
      expect(
        isDoneBefore(
          startAt: DateTime.now().toUtc(),
          endAt: null,
          isAllDay: false,
          done: true,
        ),
        isFalse,
      );
    });
  });

  group('scheduled, all-day', () {
    test('mirrors the manual done flag when true, even with a past end_at', () {
      final past = DateTime.now().toUtc().subtract(const Duration(days: 1));
      expect(
        isDoneBefore(startAt: past, endAt: past, isAllDay: true, done: true),
        isTrue,
      );
    });

    test('mirrors the manual done flag when false, even with a past end_at', () {
      final past = DateTime.now().toUtc().subtract(const Duration(days: 1));
      expect(
        isDoneBefore(startAt: past, endAt: past, isAllDay: true, done: false),
        isFalse,
      );
    });
  });
}
