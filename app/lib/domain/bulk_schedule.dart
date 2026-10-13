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

/// Moves every action by [shift], each keeping its own length. An all-day
/// action moves by whole days only (it stays on local midnight). Actions
/// without a start are skipped (counted).
BulkSchedule bulkShift(Iterable<ActionListItem> items, Duration shift) =>
    _apply(items, shift, (shift.inMinutes / 1440).round());

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
  return _apply(items, delta, days);
}

BulkSchedule _apply(
  Iterable<ActionListItem> items,
  Duration timedDelta,
  int allDayDays,
) {
  final changes = <ScheduleChange>[];
  var skipped = 0;
  for (final a in items) {
    final start = a.startAt;
    if (start == null) {
      skipped++;
      continue;
    }
    if (a.isAllDay) {
      if (allDayDays == 0) continue;
      changes.add(
        ScheduleChange(
          a.id,
          startAt: calendarAddDays(start, allDayDays),
          endAt: a.endAt == null ? null : calendarAddDays(a.endAt!, allDayDays),
        ),
      );
    } else {
      if (timedDelta == Duration.zero) continue;
      changes.add(
        ScheduleChange(
          a.id,
          startAt: start.add(timedDelta),
          endAt: a.endAt?.add(timedDelta),
        ),
      );
    }
  }
  return BulkSchedule(changes, skipped);
}
