import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/queries.dart';

ActionListItem item({DateTime? start, DateTime? end, bool allDay = false}) =>
    ActionListItem(
      id: 'a',
      name: 'a',
      done: false,
      startAt: start,
      endAt: end,
      isAllDay: allDay,
    );

void main() {
  final now = DateTime.utc(2026, 10, 13, 12);
  DateTime t(int h, [int m = 0]) => DateTime.utc(2026, 10, 13, h, m);

  test('running = started and not yet ended (start <= now < end)', () {
    expect(item(start: t(11), end: t(13)).isRunningAt(now), isTrue);
    expect(item(start: t(12), end: t(13)).isRunningAt(now), isTrue); // starts now
    expect(item(start: t(11), end: t(12)).isRunningAt(now), isFalse); // ends now
    expect(item(start: t(9), end: t(11)).isRunningAt(now), isFalse); // past
    expect(item(start: t(13), end: t(14)).isRunningAt(now), isFalse); // future
  });

  test('all-day, unscheduled and open-ended actions are never running', () {
    expect(item(start: t(0), allDay: true).isRunningAt(now), isFalse);
    expect(item().isRunningAt(now), isFalse);
    expect(item(start: t(11)).isRunningAt(now), isFalse);
    expect(item(end: t(13)).isRunningAt(now), isFalse);
  });
}
