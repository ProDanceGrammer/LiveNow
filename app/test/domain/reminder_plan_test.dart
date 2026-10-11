import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/reminder_plan.dart';

ReminderSource a(
  String id, {
  DateTime? s,
  DateTime? e,
  bool allDay = false,
  String name = 'x',
}) =>
    ReminderSource(id: id, name: name, startAt: s, endAt: e, isAllDay: allDay);

void main() {
  final now = DateTime.utc(2026, 10, 11, 12);
  DateTime t(int minutes) => now.add(Duration(minutes: minutes));

  test('start and end moments, soonest first', () {
    final plan = planReminders([
      a('b', s: t(30), e: t(60)),
      a('a', s: t(10), e: t(20)),
    ], now);
    expect(
      [for (final m in plan) (m.actionId, m.kind)],
      [
        ('a', ReminderKind.start),
        ('a', ReminderKind.end),
        ('b', ReminderKind.start),
        ('b', ReminderKind.end),
      ],
    );
  });

  test('a running action only gets its end; past moments are dropped', () {
    final plan = planReminders([a('r', s: t(-30), e: t(15))], now);
    expect([for (final m in plan) m.kind], [ReminderKind.end]);
    expect(planReminders([a('p', s: t(-60), e: t(-10))], now), isEmpty);
  });

  test('all-day and unscheduled actions get nothing', () {
    expect(
      planReminders([a('d', s: t(10), e: null, allDay: true), a('n')], now),
      isEmpty,
    );
  });

  test('an end equal to the start is one notification', () {
    final plan = planReminders([a('z', s: t(5), e: t(5))], now);
    expect(plan.length, 1);
    expect(plan.single.kind, ReminderKind.start);
  });

  test('the limit keeps only the nearest', () {
    final many = [
      for (var i = 0; i < 30; i++) a('id$i', s: t(i + 1), e: t(i + 2)),
    ];
    final plan = planReminders(many, now, limit: 5);
    expect(plan.length, 5);
    expect(plan.first.at, t(1));
  });

  test('notification ids are stable, positive and differ per kind', () {
    final m1 = ReminderMoment(
      actionId: 'abc',
      kind: ReminderKind.start,
      at: t(1),
      title: 't',
    );
    final m2 = ReminderMoment(
      actionId: 'abc',
      kind: ReminderKind.end,
      at: t(1),
      title: 't',
    );
    expect(m1.notificationId, m1.notificationId);
    expect(m1.notificationId, isNot(m2.notificationId));
    expect(m1.notificationId, inInclusiveRange(0, 0x7FFFFFFF));
  });
}
