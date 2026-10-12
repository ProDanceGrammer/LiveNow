import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/queries.dart';
import 'package:livenow/domain/all_actions_summary.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/time_format.dart';

ActionListItem item(
  String id, {
  DateTime? start,
  DateTime? end,
  bool allDay = false,
}) => ActionListItem(
  id: id,
  name: id,
  done: false,
  startAt: start,
  endAt: end,
  isAllDay: allDay,
);

DateTime t(int day, int h, [int m = 0, int s = 0]) =>
    DateTime.utc(2026, 10, day, h, m, s);

void main() {
  setUpAll(initPostponeTimeZoneData);

  test('adds only timed actions, seconds included; counts the rest', () {
    final s = summarizeActions([
      item('a', start: t(3, 9), end: t(3, 10, 20)), // 1 h 20 min
      item('b', start: t(5, 9), end: t(5, 9, 40, 30)), // 40 min 30 s
      item('allday', start: t(4, 0), allDay: true),
      item('open'),
      item('noEnd', start: t(6, 9)),
      item('reversed', start: t(7, 12), end: t(7, 11)),
    ]);
    expect(s.count, 6);
    expect(s.total, const Duration(hours: 2, minutes: 0, seconds: 30));
    expect(s.withoutTime, 4);
  });

  test('start range covers every action that starts, all-day included', () {
    final s = summarizeActions([
      item('x', start: t(9, 9), end: t(9, 10)),
      item('y', start: t(3, 9), end: t(3, 10)),
      item('allday', start: t(12, 0), allDay: true),
      item('open'),
    ]);
    expect(s.firstStart, t(3, 9));
    expect(s.lastStart, t(12, 0));
    expect(summarizeActions(const []).firstStart, isNull);
  });

  test('total formats in hours and minutes (days folded)', () {
    expect(formatTotalDuration(const Duration(hours: 31, minutes: 20)),
        '31 h 20 min');
    expect(formatTotalDuration(const Duration(minutes: 45)), '45 min');
    expect(formatTotalDuration(const Duration(hours: 2)), '2 h');
    expect(formatTotalDuration(Duration.zero), '0 min');
    expect(formatTotalDuration(const Duration(days: 2, hours: 3)), '51 h');
  });

  test('start range text: a range, one day, none; year only when not current',
      () {
    final now = t(12, 9);
    expect(formatStartRange(t(3, 9), t(12, 9), nowUtc: now), '3 Oct - 12 Oct');
    expect(formatStartRange(t(3, 9), t(3, 18), nowUtc: now), '3 Oct');
    expect(formatStartRange(null, null, nowUtc: now), isNull);
    expect(
      formatStartRange(DateTime.utc(2025, 12, 30, 9), t(12, 9), nowUtc: now),
      "30 Dec 25' - 12 Oct",
    );
  });
}
