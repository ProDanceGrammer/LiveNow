import 'package:timezone/timezone.dart' as tz;

import '../../core/settings.dart';
import '../../domain/duration_rules.dart';

/// Pixel height of one hour in the time grid; 10 minutes = 8 px.
const double kHourHeight = 48;
const double kPxPerMinute = kHourHeight / 60;

/// Drag/resize granularity and the shortest a timed event may become.
const int kSnapMinutes = 10;
const int kMinDurationMinutes = 10;

/// A start/end pair, both UTC.
typedef CalendarSchedule = ({DateTime startAt, DateTime endAt});

tz.Location get _location => tz.getLocation(AppSettings.timeZoneName);

// ---- pixels <-> minutes ----------------------------------------------------

/// A vertical drag distance [dy] in px, rounded to the nearest multiple of
/// [kSnapMinutes] minutes (half-steps round away from zero; negatives are
/// symmetric).
int snapMinutes(double dy, {double pxPerMinute = kPxPerMinute}) {
  final steps = (dy / pxPerMinute / kSnapMinutes).round();
  return steps * kSnapMinutes;
}

double minutesToPx(num minutes, {double pxPerMinute = kPxPerMinute}) =>
    minutes * pxPerMinute;

double pxToMinutes(double px, {double pxPerMinute = kPxPerMinute}) =>
    px / pxPerMinute;

// ---- day boundaries (in AppSettings.timeZoneName) --------------------------

/// Minutes since local midnight (whole minutes) of [utc].
int minutesOfDay(DateTime utc) {
  final l = tz.TZDateTime.from(utc, _location);
  return l.hour * 60 + l.minute;
}

/// UTC instant of local midnight [days] days after the local midnight [utcMidnight]
/// (DST-safe: shifts calendar days, not 24 h blocks).
DateTime calendarAddDays(DateTime utcMidnight, int days) {
  final l = tz.TZDateTime.from(utcMidnight, _location);
  return tz.TZDateTime(_location, l.year, l.month, l.day + days).toUtc();
}

/// UTC instant of local midnight of the day containing [utc].
DateTime localDayStart(DateTime utc) {
  final l = tz.TZDateTime.from(utc, _location);
  return tz.TZDateTime(_location, l.year, l.month, l.day).toUtc();
}

/// Zero-based day column of [utc] relative to [rangeStartUtc] (may be
/// negative or beyond the range).
int dayIndexOf(DateTime utc, DateTime rangeStartUtc) {
  final a = tz.TZDateTime.from(utc, _location);
  final b = tz.TZDateTime.from(rangeStartUtc, _location);
  return DateTime.utc(a.year, a.month, a.day)
      .difference(DateTime.utc(b.year, b.month, b.day))
      .inDays;
}

/// Where the range starts for [dayCount] columns: 7 -> Monday of the week
/// containing [nowUtc]; 2..6 -> today. Returned as a UTC instant of local
/// midnight.
DateTime calendarAnchorStart(DateTime nowUtc, int dayCount) {
  final now = tz.TZDateTime.from(nowUtc, _location);
  final back = dayCount == 7 ? now.weekday - DateTime.monday : 0;
  return tz.TZDateTime(_location, now.year, now.month, now.day - back).toUtc();
}

// ---- lane packing ----------------------------------------------------------

/// Where one event sits among overlapping neighbours: it occupies lane
/// [lane] of [laneCount] equal-width side-by-side lanes.
class LaneAssignment<T> {
  final T event;
  final int lane;
  final int laneCount;

  const LaneAssignment(this.event, this.lane, this.laneCount);
}

/// Assigns overlapping timed events of one day to side-by-side lanes.
/// Events that chain-overlap share a cluster and its lane count; separate
/// clusters lay out independently at full width. An event shorter than
/// [kMinDurationMinutes] counts as that long (its minimum drawn size).
/// Results come back in start order.
List<LaneAssignment<T>> packLanes<T>(
  List<T> events, {
  required DateTime Function(T) startOf,
  required DateTime Function(T) endOf,
}) {
  const minLen = Duration(minutes: kMinDurationMinutes);
  DateTime effEnd(T e) {
    final s = startOf(e);
    final end = endOf(e);
    return end.isBefore(s.add(minLen)) ? s.add(minLen) : end;
  }

  final sorted = [...events]..sort((a, b) {
      final c = startOf(a).compareTo(startOf(b));
      return c != 0 ? c : effEnd(b).compareTo(effEnd(a));
    });

  final out = <LaneAssignment<T>>[];
  var cluster = <(T, int)>[];
  final laneEnds = <DateTime>[];
  DateTime? clusterEnd;

  void flush() {
    for (final (e, lane) in cluster) {
      out.add(LaneAssignment(e, lane, laneEnds.length));
    }
    cluster = [];
    laneEnds.clear();
    clusterEnd = null;
  }

  for (final e in sorted) {
    final s = startOf(e);
    if (clusterEnd != null && !s.isBefore(clusterEnd!)) flush();
    var lane = laneEnds.indexWhere((end) => !s.isBefore(end));
    final end = effEnd(e);
    if (lane == -1) {
      laneEnds.add(end);
      lane = laneEnds.length - 1;
    } else {
      laneEnds[lane] = end;
    }
    cluster.add((e, lane));
    if (clusterEnd == null || end.isAfter(clusterEnd!)) clusterEnd = end;
  }
  flush();
  return out;
}

// ---- move / resize ---------------------------------------------------------

Duration _durationOf(DateTime startAt, DateTime? endAt, int? legacyMinutes) =>
    computeActionDuration(
      startAt: startAt,
      endAt: endAt,
      legacyEstimatedMinutes: legacyMinutes,
    );

/// New schedule after dragging the whole block by [dayDelta] day columns and
/// [minuteDelta] minutes (already snapped). The wall-clock time is shifted in
/// the app time zone and the duration is preserved; a start-only action gets
/// an end from [computeActionDuration].
CalendarSchedule movedSchedule({
  required DateTime startAt,
  DateTime? endAt,
  required int dayDelta,
  required int minuteDelta,
  int? legacyEstimatedMinutes,
}) {
  final duration = _durationOf(startAt, endAt, legacyEstimatedMinutes);
  final l = tz.TZDateTime.from(startAt, _location);
  final newStart = tz.TZDateTime(
    _location,
    l.year,
    l.month,
    l.day + dayDelta,
    l.hour,
    l.minute + minuteDelta,
    l.second,
    l.millisecond,
    l.microsecond,
  ).toUtc();
  return (startAt: newStart, endAt: newStart.add(duration));
}

/// New schedule after dragging the top ([fromTop] true) or bottom edge by
/// [minuteDelta] minutes (already snapped). The opposite edge stays put and
/// the duration never drops below [kMinDurationMinutes]. A start-only action
/// first gets an end from [computeActionDuration].
CalendarSchedule resizedSchedule({
  required DateTime startAt,
  DateTime? endAt,
  required bool fromTop,
  required int minuteDelta,
  int? legacyEstimatedMinutes,
}) {
  const minLen = Duration(minutes: kMinDurationMinutes);
  final end =
      endAt ?? startAt.add(_durationOf(startAt, null, legacyEstimatedMinutes));
  final delta = Duration(minutes: minuteDelta);

  if (fromTop) {
    var newStart = startAt.add(delta);
    final latest = end.subtract(minLen);
    if (newStart.isAfter(latest)) newStart = latest;
    return (startAt: newStart, endAt: end);
  }
  var newEnd = end.add(delta);
  final earliest = startAt.add(minLen);
  if (newEnd.isBefore(earliest)) newEnd = earliest;
  return (startAt: startAt, endAt: newEnd);
}
