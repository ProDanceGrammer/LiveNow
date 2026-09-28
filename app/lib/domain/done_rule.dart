/// Whether an action counts as "done" for filtering/board-column purposes —
/// the Notion prototype's "Done Before" formula (`dev/Actions-Template-Function-Reference.md`):
/// an unscheduled action just mirrors the manual `done` flag; a scheduled,
/// non-all-day action is derived live from its end time vs. now (so Start/
/// Finish/Postpone/quick-edit all recompute it just by moving `endAt`); a
/// scheduled, all-day action mirrors the manual flag too, since a whole-day
/// window doesn't have a meaningful "is it over yet" answer.
bool isDoneBefore({
  required DateTime? startAt,
  required DateTime? endAt,
  required bool isAllDay,
  required bool done,
}) {
  if (startAt == null) return done;
  if (!isAllDay) return endAt != null && endAt.isBefore(DateTime.now().toUtc());
  return done;
}
