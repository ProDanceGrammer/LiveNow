import 'duration_rules.dart';

/// "Set after previous actions" / "Set before next action": where an action
/// lands relative to the actions it is chained to. Pure; the action editor
/// feeds the result into its form (nothing is written until Save).

/// What the maths need to know about a neighbour.
class ChainNeighbor {
  const ChainNeighbor({
    required this.startAt,
    required this.endAt,
    this.isAllDay = false,
  });

  final DateTime? startAt;
  final DateTime? endAt;
  final bool isAllDay;

  /// Neighbours without a time, and all-day ones, take no part.
  bool get counts => startAt != null && !isAllDay;

  DateTime get effectiveEnd => endAt ?? startAt!.add(defaultActionDuration);
}

/// The action's length: end - start when both are set, else one hour.
Duration _length(DateTime? start, DateTime? end) =>
    (start != null && end != null && end.isAfter(start))
    ? end.difference(start)
    : defaultActionDuration;

/// Starts when the LATEST previous action ends, keeping the length. Null when
/// no previous action has a time.
({DateTime start, DateTime end})? scheduleAfterPrevious(
  Iterable<ChainNeighbor> previous, {
  required DateTime? currentStart,
  required DateTime? currentEnd,
}) {
  DateTime? latest;
  for (final p in previous) {
    if (!p.counts) continue;
    final e = p.effectiveEnd;
    if (latest == null || e.isAfter(latest)) latest = e;
  }
  if (latest == null) return null;
  return (start: latest, end: latest.add(_length(currentStart, currentEnd)));
}

/// Ends when the EARLIEST next action starts, keeping the length. Null when no
/// next action has a time.
({DateTime start, DateTime end})? scheduleBeforeNext(
  Iterable<ChainNeighbor> next, {
  required DateTime? currentStart,
  required DateTime? currentEnd,
}) {
  DateTime? earliest;
  for (final n in next) {
    if (!n.counts) continue;
    if (earliest == null || n.startAt!.isBefore(earliest)) {
      earliest = n.startAt;
    }
  }
  if (earliest == null) return null;
  return (
    start: earliest.subtract(_length(currentStart, currentEnd)),
    end: earliest,
  );
}

/// Where a NEW action of [length] goes directly before ([before]) or after the
/// current one: it ends exactly when the current action starts / starts exactly
/// when it ends. An action without a start, or an all-day one, has no time to be
/// next to: null (the new action then has no schedule either).
({DateTime start, DateTime end})? adjacentSchedule({
  required bool before,
  required DateTime? startAt,
  required DateTime? endAt,
  required bool isAllDay,
  required Duration length,
}) {
  if (isAllDay || startAt == null) return null;
  if (before) {
    return (start: startAt.subtract(length), end: startAt);
  }
  final end = endAt ?? startAt.add(computeActionDuration(startAt: startAt, endAt: null));
  return (start: end, end: end.add(length));
}
