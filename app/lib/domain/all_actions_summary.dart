import '../data/queries.dart' show ActionListItem;

/// What the All list shows above its rows while a search or filter narrows
/// it: how many actions were found, how long the timed ones last in total, and
/// when they start.
class AllActionsSummary {
  const AllActionsSummary({
    required this.count,
    required this.total,
    required this.withoutTime,
    this.firstStart,
    this.lastStart,
  });

  final int count;

  /// Sum of `end - start` over the actions that have BOTH (all-day and
  /// unscheduled ones have no real length and are not added; overlapping
  /// actions are simply added up).
  final Duration total;

  /// Found actions left out of [total] (all-day, no start or no end).
  final int withoutTime;

  /// Earliest / latest start over every found action that has one.
  final DateTime? firstStart;
  final DateTime? lastStart;
}

AllActionsSummary summarizeActions(Iterable<ActionListItem> items) {
  var count = 0, withoutTime = 0;
  var totalMicros = 0;
  DateTime? first, last;
  for (final a in items) {
    count++;
    final start = a.startAt;
    final end = a.endAt;
    if (start != null) {
      if (first == null || start.isBefore(first)) first = start;
      if (last == null || start.isAfter(last)) last = start;
    }
    if (!a.isAllDay && start != null && end != null && !end.isBefore(start)) {
      totalMicros += end.difference(start).inMicroseconds;
    } else {
      withoutTime++;
    }
  }
  return AllActionsSummary(
    count: count,
    total: Duration(microseconds: totalMicros),
    withoutTime: withoutTime,
    firstStart: first,
    lastStart: last,
  );
}

/// `31 h 20 min` (days are folded into hours), `45 min`, `2 h`, `0 min`.
String formatTotalDuration(Duration d) {
  final minutes = d.inSeconds ~/ 60;
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m min';
}
