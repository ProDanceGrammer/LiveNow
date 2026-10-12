import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../core/settings.dart';
import 'work_hours.dart';

/// Must be called once at app startup, before any postpone rule runs.
void initPostponeTimeZoneData() => tz_data.initializeTimeZones();

enum PostponeRule {
  plusOneHour,
  plusFiveHours,
  prolongThirtyMinutes,
  afterWork,
  morning,
  workingMorning,
  nextWeek,
  nextMondayMorning,
}

/// An action's schedule, always UTC (as stored in `actions.start_at` /
/// `actions.end_at`).
class ActionSchedule {
  final DateTime? startAt;
  final DateTime? endAt;

  const ActionSchedule({this.startAt, this.endAt});
}

/// Computes the action's next schedule for a postpone button press.
///
/// All rules but [PostponeRule.prolongThirtyMinutes] preserve the action's
/// existing duration (`endAt - startAt`) and are evaluated in
/// [AppSettings.timeZoneName] wall-clock time, then converted back to UTC.
ActionSchedule applyPostponeRule(
  PostponeRule rule,
  ActionSchedule current, {
  required DateTime nowUtc,
  WorkHours hours = WorkHours.defaults,
}) {
  final location = tz.getLocation(AppSettings.timeZoneName);
  final now = tz.TZDateTime.from(nowUtc, location);

  if (rule == PostponeRule.prolongThirtyMinutes) {
    final newEnd = (current.endAt ?? nowUtc).add(const Duration(minutes: 30));
    return ActionSchedule(startAt: current.startAt, endAt: newEnd);
  }

  final duration = (current.startAt != null && current.endAt != null)
      ? current.endAt!.difference(current.startAt!)
      : null;

  final newStartLocal = switch (rule) {
    PostponeRule.plusOneHour => _relativeBase(
      current.startAt,
      now,
      location,
    ).add(const Duration(hours: 1)),
    PostponeRule.plusFiveHours => _relativeBase(
      current.startAt,
      now,
      location,
    ).add(const Duration(hours: 5)),
    PostponeRule.nextWeek => _relativeBase(
      current.startAt,
      now,
      location,
    ).add(const Duration(days: 7)),
    PostponeRule.afterWork => _nextAtMinute(
      _relativeBase(current.startAt, now, location),
      hours.workEnd,
    ),
    PostponeRule.morning => _nextAtMinute(
      _relativeBase(current.startAt, now, location),
      hours.morning,
    ),
    PostponeRule.workingMorning => _nextWorkingAtMinute(
      _relativeBase(current.startAt, now, location),
      hours.morning,
    ),
    PostponeRule.nextMondayMorning => _nextWeekdayAt(
      _relativeBase(current.startAt, now, location),
      DateTime.monday,
      hours.morning,
    ),
    PostponeRule.prolongThirtyMinutes => throw StateError('handled above'),
  };

  final newStart = newStartLocal.toUtc();
  final newEnd = duration == null ? null : newStart.add(duration);
  return ActionSchedule(startAt: newStart, endAt: newEnd);
}

/// For the plain relative shifts (+1h, +5h, next week): always shift from
/// the action's existing start time, whatever it is — e.g. started at
/// 18:43, +1 hour becomes 19:43, full stop. Only an action with no start
/// at all falls back to "now" (there's nothing else to shift from).
tz.TZDateTime _relativeBase(
  DateTime? startAtUtc,
  tz.TZDateTime now,
  tz.Location location,
) {
  if (startAtUtc == null) return now;
  return tz.TZDateTime.from(startAtUtc, location);
}

/// [minutes] since midnight on [date]'s own calendar day.
tz.TZDateTime _atMinuteOnDate(tz.TZDateTime date, int minutes) {
  return tz.TZDateTime(
    date.location,
    date.year,
    date.month,
    date.day,
    minutes ~/ 60,
    minutes % 60,
  );
}

/// Calendar-day step (wall-clock safe, unlike adding 24 hours).
tz.TZDateTime _nextDay(tz.TZDateTime date) =>
    tz.TZDateTime(date.location, date.year, date.month, date.day + 1);

/// The time of day [minutes] on the base's own day if that is strictly after
/// the base, else on the next day. No "after now" floor: an overdue action
/// follows its own date.
tz.TZDateTime _nextAtMinute(tz.TZDateTime base, int minutes) {
  final sameDay = _atMinuteOnDate(base, minutes);
  return sameDay.isAfter(base)
      ? sameDay
      : _atMinuteOnDate(_nextDay(base), minutes);
}

/// Like [_nextAtMinute], then skips non-working weekdays.
tz.TZDateTime _nextWorkingAtMinute(tz.TZDateTime base, int minutes) {
  var candidate = _nextAtMinute(base, minutes);
  while (!AppSettings.workingWeekdays.contains(candidate.weekday)) {
    candidate = _atMinuteOnDate(_nextDay(candidate), minutes);
  }
  return candidate;
}

/// The next occurrence of [weekday] strictly after the base's date.
tz.TZDateTime _nextWeekdayAt(tz.TZDateTime base, int weekday, int minutes) {
  var date = _nextDay(base);
  while (date.weekday != weekday) {
    date = _nextDay(date);
  }
  return _atMinuteOnDate(date, minutes);
}
