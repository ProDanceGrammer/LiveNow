import '../core/local_time.dart';
import '../data/queries.dart';
import 'action_service.dart' show ScheduleChange;

/// The schedule changes of a bulk date edit, and how many selected actions
/// had no start (they are left alone).
class BulkSchedule {
  const BulkSchedule(this.changes, this.skipped);

  final List<ScheduleChange> changes;
  final int skipped;
}

/// A signed "shift by": calendar [months] first (the day is clamped to the
/// target month, the time of day kept), then [days] (weeks x 7 + days) and
/// [hours].
class ShiftAmount {
  const ShiftAmount({this.months = 0, this.days = 0, this.hours = 0});

  final int months;
  final int days;
  final int hours;

  bool get isZero => months == 0 && days == 0 && hours == 0;

  ShiftAmount get negated =>
      ShiftAmount(months: -months, days: -days, hours: -hours);
}

/// Moves every action by [shift], each keeping its own length. An all-day
/// action moves by months and days only (it stays on local midnight; hours are
/// ignored). Actions without a start are skipped (counted).
BulkSchedule bulkShift(Iterable<ActionListItem> items, ShiftAmount shift) {
  DateTime timed(DateTime t) => calendarAddMonths(
    t,
    shift.months,
  ).add(Duration(days: shift.days, hours: shift.hours));
  DateTime allDay(DateTime t) =>
      calendarAddDays(calendarAddMonths(t, shift.months), shift.days);
  return _apply(items, timed, allDay, shift.isZero);
}

/// "Set date": [chosenStart] becomes the start of the EARLIEST selected action
/// (the leftmost on the calendar) and every other action moves by the same
/// amount, so the selection keeps its internal spacing. All-day actions move
/// by the whole-day difference. Actions without a start are skipped (counted).
BulkSchedule bulkSetDate(Iterable<ActionListItem> items, DateTime chosenStart) {
  DateTime? earliest;
  for (final a in items) {
    final s = a.startAt;
    if (s != null && (earliest == null || s.isBefore(earliest))) earliest = s;
  }
  if (earliest == null) return BulkSchedule(const [], items.length);
  final delta = chosenStart.difference(earliest);
  final days =
      (localDayStart(chosenStart)
                  .difference(localDayStart(earliest))
                  .inHours /
              24)
          .round();
  return _apply(
    items,
    (t) => t.add(delta),
    (t) => calendarAddDays(t, days),
    delta == Duration.zero && days == 0,
  );
}

/// Timed actions go through [timed], all-day ones through [allDay]; [noop]
/// means the whole edit changes nothing. An action whose moved start equals
/// its old start is left out.
BulkSchedule _apply(
  Iterable<ActionListItem> items,
  DateTime Function(DateTime) timed,
  DateTime Function(DateTime) allDay,
  bool noop,
) {
  final changes = <ScheduleChange>[];
  var skipped = 0;
  for (final a in items) {
    final start = a.startAt;
    if (start == null) {
      skipped++;
      continue;
    }
    if (noop) continue;
    final move = a.isAllDay ? allDay : timed;
    final newStart = move(start);
    if (newStart == start) continue;
    changes.add(
      ScheduleChange(
        a.id,
        startAt: newStart,
        // A timed action keeps its length even when a month end was clamped.
        endAt: a.endAt == null
            ? null
            : a.isAllDay
            ? move(a.endAt!)
            : newStart.add(a.endAt!.difference(start)),
      ),
    );
  }
  return BulkSchedule(changes, skipped);
}
