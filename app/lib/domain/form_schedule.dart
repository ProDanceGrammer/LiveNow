import 'duration_rules.dart';

// Times of a NEW action's form (nothing is saved yet). Pure; the action editor
// feeds the results into its Start / End fields.

/// What a new action starts with when nothing else says so: now (to the minute),
/// for [defaultActionDuration] (60 minutes).
({DateTime start, DateTime end}) defaultNewActionSchedule(DateTime nowUtc) {
  final start = DateTime.utc(
    nowUtc.year,
    nowUtc.month,
    nowUtc.day,
    nowUtc.hour,
    nowUtc.minute,
  );
  return (start: start, end: start.add(defaultActionDuration));
}

/// The form's "Start" button: starts now and keeps the current length (60
/// minutes when there is none), like `ActionService.start` does for a saved
/// action.
({DateTime start, DateTime end}) formStartNow({
  required DateTime? start,
  required DateTime? end,
  required DateTime nowUtc,
}) {
  final length = computeActionDuration(startAt: start, endAt: end);
  return (start: nowUtc, end: nowUtc.add(length));
}

/// The form's "Finish" button: ends now. A start that already happened is kept;
/// no start, or one still ahead, is back-projected by the current length (60
/// minutes when there is none), like `ActionService.finish`.
({DateTime start, DateTime end}) formFinishNow({
  required DateTime? start,
  required DateTime? end,
  required DateTime nowUtc,
}) {
  final keep = start != null && !start.isAfter(nowUtc);
  final length = computeActionDuration(startAt: start, endAt: end);
  return (start: keep ? start : nowUtc.subtract(length), end: nowUtc);
}
