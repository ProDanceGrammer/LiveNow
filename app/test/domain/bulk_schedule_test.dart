import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/queries.dart';
import 'package:livenow/domain/bulk_schedule.dart';
import 'package:livenow/domain/postpone_rules.dart';

ActionListItem _a(
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

void main() {
  setUpAll(initPostponeTimeZoneData);

  // Istanbul is UTC+3: 09:00 local = 06:00 UTC.
  final mon = DateTime.utc(2026, 10, 5, 6); // Mon 5 Oct 09:00
  final wed = DateTime.utc(2026, 10, 7, 11); // Wed 7 Oct 14:00
  final items = [
    _a('a', start: mon, end: mon.add(const Duration(hours: 1))),
    _a('b', start: wed, end: wed.add(const Duration(hours: 2))),
    _a('day', start: DateTime.utc(2026, 10, 5, 21), allDay: true), // 6 Oct
    _a('none'),
  ];

  ScheduleChangeLookup lookup(BulkSchedule r) => ScheduleChangeLookup(r);

  test('Shift by moves everything, each keeping its length', () {
    final r = bulkShift(items, const Duration(days: 1, hours: 2));
    final c = lookup(r);
    expect(c('a').startAt, mon.add(const Duration(days: 1, hours: 2)));
    expect(c('a').endAt, mon.add(const Duration(days: 1, hours: 3)));
    expect(c('b').endAt!.difference(c('b').startAt!), const Duration(hours: 2));
    // The all-day action only moves whole days (1 day here), staying midnight.
    expect(c('day').startAt, DateTime.utc(2026, 10, 6, 21));
    expect(r.skipped, 1); // 'none' has no start
  });

  test('Shift by with a zero amount changes nothing', () {
    expect(bulkShift(items, Duration.zero).changes, isEmpty);
  });

  test('Set date: the earliest action starts at the chosen moment', () {
    // Choose Fri 9 Oct 10:30 (07:30 UTC): the earliest (a, Mon 09:00) moves
    // there and b keeps its 2 d 5 h distance from it.
    final chosen = DateTime.utc(2026, 10, 9, 7, 30);
    final r = bulkSetDate(items, chosen);
    final c = lookup(r);
    expect(c('a').startAt, chosen);
    expect(c('a').endAt, chosen.add(const Duration(hours: 1)));
    expect(
      c('b').startAt!.difference(c('a').startAt!),
      wed.difference(mon),
    );
    // all-day: whole-day difference between the chosen day and Mon (4 days)
    expect(c('day').startAt, DateTime.utc(2026, 10, 9, 21));
    expect(r.skipped, 1);
  });

  test('Set date with nothing scheduled skips everything', () {
    final r = bulkSetDate([_a('x'), _a('y')], mon);
    expect(r.changes, isEmpty);
    expect(r.skipped, 2);
  });

  test('Set date to where the earliest already is changes nothing', () {
    expect(bulkSetDate(items, mon).changes, isEmpty);
  });
}

class ScheduleChangeLookup {
  ScheduleChangeLookup(this.r);
  final BulkSchedule r;
  dynamic call(String id) => r.changes.firstWhere((c) => c.id == id);
}
