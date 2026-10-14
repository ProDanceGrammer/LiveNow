import 'package:timezone/timezone.dart' as tz;

import '../../core/settings.dart';
import '../../domain/duration_rules.dart';

export '../../core/local_time.dart' show calendarAddDays, localDayStart;

/// Pixel height of one hour in the time grid; 10 minutes = 8 px.
const double kHourHeight = 48;
const double kPxPerMinute = kHourHeight / 60;

/// Drag/resize granularity and the shortest a timed event may become.
const int kSnapMinutes = 10;
const int kMinDurationMinutes = 10;

/// Zoom levels of the time grid, as "how many hours of a day fit the
/// viewport" (fewer hours = bigger blocks).
const List<int> kCalendarZoomHours = [3, 6, 9, 12, 16, 24];
const int kCalendarDefaultZoomHours = 12;

/// The zoom level after [current] one step in [direction]: positive zooms in
/// (fewer hours), negative zooms out (more hours). Stops at the ends; a
/// [current] that isn't a level first snaps to the nearest one.
int stepZoomHours(int current, int direction) {
  var nearest = 0;
  for (var i = 1; i < kCalendarZoomHours.length; i++) {
    if ((kCalendarZoomHours[i] - current).abs() <
        (kCalendarZoomHours[nearest] - current).abs()) {
      nearest = i;
    }
  }
  final next = (nearest - direction.sign).clamp(
    0,
    kCalendarZoomHours.length - 1,
  );
  return kCalendarZoomHours[next];
}

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

/// The minutes a dragged block has moved: the pointer's vertical travel
/// [pointerDy] PLUS how far the grid has scrolled since the drag began
/// ([scrollDelta], positive = scrolled down). A mouse wheel turning during the
/// drag moves the grid under a pointer that did not move, and the block must
/// follow the content, not stay behind with the pointer travel alone.
int dragMinuteDelta(
  double pointerDy,
  double scrollDelta, {
  double pxPerMinute = kPxPerMinute,
}) => snapMinutes(pointerDy + scrollDelta, pxPerMinute: pxPerMinute);

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

// `calendarAddDays` and `localDayStart` live in core/local_time.dart (the
// growth-direction rules need them too); re-exported below for the calendar.

/// Zero-based day column of [utc] relative to [rangeStartUtc] (may be
/// negative or beyond the range).
int dayIndexOf(DateTime utc, DateTime rangeStartUtc) {
  final a = tz.TZDateTime.from(utc, _location);
  final b = tz.TZDateTime.from(rangeStartUtc, _location);
  return DateTime.utc(
    a.year,
    a.month,
    a.day,
  ).difference(DateTime.utc(b.year, b.month, b.day)).inDays;
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
/// [lane] of [laneCount] equal-width side-by-side lanes, and is drawn
/// [span] lanes wide: it expands rightwards over every lane that stays free
/// for its whole duration.
class LaneAssignment<T> {
  final T event;
  final int lane;
  final int laneCount;
  final int span;

  const LaneAssignment(this.event, this.lane, this.laneCount, [this.span = 1]);
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

  final sorted = [...events]
    ..sort((a, b) {
      final c = startOf(a).compareTo(startOf(b));
      return c != 0 ? c : effEnd(b).compareTo(effEnd(a));
    });

  final out = <LaneAssignment<T>>[];
  var cluster = <(T, int, DateTime, DateTime)>[];
  final laneEnds = <DateTime>[];
  DateTime? clusterEnd;

  void flush() {
    final lanes = laneEnds.length;
    for (final (e, lane, s, end) in cluster) {
      var span = 1;
      // Grow over the next lanes while nobody there overlaps [s, end).
      while (lane + span < lanes &&
          !cluster.any(
            (o) => o.$2 == lane + span && o.$3.isBefore(end) && o.$4.isAfter(s),
          )) {
        span++;
      }
      out.add(LaneAssignment(e, lane, lanes, span));
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
    cluster.add((e, lane, s, end));
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
/// [dayDelta] day columns and [minuteDelta] minutes (already snapped). The
/// moved edge shifts in app-time-zone wall-clock time (so DST days keep the
/// pointer's wall-clock time), the opposite edge stays put and the duration
/// never drops below [kMinDurationMinutes]. A start-only action first gets an
/// end from [computeActionDuration].
CalendarSchedule resizedSchedule({
  required DateTime startAt,
  DateTime? endAt,
  required bool fromTop,
  int dayDelta = 0,
  required int minuteDelta,
  int? legacyEstimatedMinutes,
}) {
  const minLen = Duration(minutes: kMinDurationMinutes);
  final end =
      endAt ?? startAt.add(_durationOf(startAt, null, legacyEstimatedMinutes));

  DateTime shifted(DateTime utc) {
    final l = tz.TZDateTime.from(utc, _location);
    return tz.TZDateTime(
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
  }

  if (fromTop) {
    var newStart = shifted(startAt);
    final latest = end.subtract(minLen);
    if (newStart.isAfter(latest)) newStart = latest;
    return (startAt: newStart, endAt: end);
  }
  var newEnd = shifted(end);
  final earliest = startAt.add(minLen);
  if (newEnd.isBefore(earliest)) newEnd = earliest;
  return (startAt: startAt, endAt: newEnd);
}

/// The result of [snapToNeighbours]: the (possibly shifted) schedule and the
/// neighbour edge it locked onto (null = no snap).
typedef SnapResult = ({CalendarSchedule schedule, DateTime? snappedTo});

/// Magnet: besides the 10-minute grid, a dragged event locks exactly onto the
/// edges of OTHER events (their start / end instants, [neighbourEdges] sorted
/// ascending) when it comes within [thresholdPx] of one, so actions line up one
/// after another and off-grid times (10:05, 23:59) are reachable.
///
/// [moveWhole] true (a move): the start or the end - whichever is closest to an
/// edge - snaps and BOTH shift by the same amount (the length is kept).
/// false (a resize): only the moved edge snaps ([movedEdgeIsStart]), the other
/// one stays, and a snap that would shorten the event below
/// [kMinDurationMinutes] is dropped.
/// The threshold is constant on screen: `thresholdPx / pxPerMinute` minutes,
/// never above [kSnapMinutes] (it must not swallow the grid) and at least 1.
SnapResult snapToNeighbours({
  required CalendarSchedule schedule,
  required bool moveWhole,
  bool movedEdgeIsStart = true,
  required List<DateTime> neighbourEdges,
  required double pxPerMinute,
  double thresholdPx = 8,
}) {
  if (neighbourEdges.isEmpty) return (schedule: schedule, snappedTo: null);
  final thr = Duration(
    seconds: ((thresholdPx / pxPerMinute).clamp(1.0, kSnapMinutes.toDouble()) *
            60)
        .round(),
  );

  DateTime? nearest(DateTime t) {
    // Binary search for the first edge >= t, then compare it with its
    // predecessor.
    var lo = 0, hi = neighbourEdges.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (neighbourEdges[mid].isBefore(t)) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    DateTime? best;
    for (final i in [lo - 1, lo]) {
      if (i < 0 || i >= neighbourEdges.length) continue;
      final e = neighbourEdges[i];
      if (best == null ||
          e.difference(t).abs() < best.difference(t).abs()) {
        best = e;
      }
    }
    if (best == null || best.difference(t).abs() > thr) return null;
    return best;
  }

  final s = schedule.startAt, e = schedule.endAt;
  if (moveWhole) {
    final a = nearest(s), b = nearest(e);
    final da = a?.difference(s), db = b?.difference(e);
    Duration? shift;
    DateTime? hit;
    if (da != null && (db == null || da.abs() <= db.abs())) {
      shift = da;
      hit = a;
    } else if (db != null) {
      shift = db;
      hit = b;
    }
    if (shift == null || shift == Duration.zero && hit == null) {
      return (schedule: schedule, snappedTo: null);
    }
    return (
      schedule: (startAt: s.add(shift), endAt: e.add(shift)),
      snappedTo: hit,
    );
  }
  final edge = movedEdgeIsStart ? s : e;
  final hit = nearest(edge);
  if (hit == null) return (schedule: schedule, snappedTo: null);
  final newStart = movedEdgeIsStart ? hit : s;
  final newEnd = movedEdgeIsStart ? e : hit;
  if (newEnd.difference(newStart) < const Duration(minutes: kMinDurationMinutes)) {
    return (schedule: schedule, snappedTo: null);
  }
  return (schedule: (startAt: newStart, endAt: newEnd), snappedTo: hit);
}
