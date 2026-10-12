import 'package:timezone/timezone.dart' as tz;

import '../core/settings.dart';

/// The single home for date/time text and UTC <-> wall-clock conversion in the
/// UI (cards, tiles, the editor's date fields, the time-edit dialog). "Wall"
/// values are `DateTime.utc(...)` objects whose components are the clock
/// reading in [AppSettings.timeZoneName]; see `domain/time_edit_math.dart`.

String twoDigits(int n) => n.toString().padLeft(2, '0');

tz.Location? _location() {
  try {
    return tz.getLocation(AppSettings.timeZoneName);
  } catch (_) {
    // Timezone database not initialised (bare widget tests): device time.
    return null;
  }
}

/// Wall-clock reading of the instant [utc] in the app time zone.
DateTime wallFromUtc(DateTime utc) {
  final loc = _location();
  final l = loc == null ? utc.toLocal() : tz.TZDateTime.from(utc, loc);
  return DateTime.utc(l.year, l.month, l.day, l.hour, l.minute);
}

/// The instant whose wall-clock reading in the app time zone is [wall].
DateTime utcFromWall(DateTime wall) {
  final loc = _location();
  if (loc == null) {
    return DateTime(
      wall.year,
      wall.month,
      wall.day,
      wall.hour,
      wall.minute,
    ).toUtc();
  }
  return tz.TZDateTime(
    loc,
    wall.year,
    wall.month,
    wall.day,
    wall.hour,
    wall.minute,
  ).toUtc();
}

/// `2026-10-02`.
String formatDate(DateTime wall) =>
    '${wall.year.toString().padLeft(4, '0')}-${twoDigits(wall.month)}-${twoDigits(wall.day)}';

/// `14:05`.
String formatTime(DateTime wall) =>
    '${twoDigits(wall.hour)}:${twoDigits(wall.minute)}';

/// `2026-10-02 14:05`, or just the date.
String formatDateTime(DateTime wall, {bool includeTime = true}) =>
    includeTime ? '${formatDate(wall)} ${formatTime(wall)}' : formatDate(wall);

/// Same as [formatClockTime] / [formatUtcDateTime] but from a UTC instant.
String formatClockTime(DateTime utc) => formatTime(wallFromUtc(utc));

String formatUtcDateTime(DateTime utc, {bool includeTime = true}) =>
    formatDateTime(wallFromUtc(utc), includeTime: includeTime);

bool sameWallDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// "start -> end" for a card: each side shows its date only when it is not
/// today, so a range entirely in the past never renders without a date.
/// [nowUtc] is injectable for tests. Null when [startUtc] is null.
/// All-day ranges show dates only.
String? formatTimeRange(
  DateTime? startUtc,
  DateTime? endUtc, {
  bool isAllDay = false,
  DateTime? nowUtc,
}) {
  if (startUtc == null) return null;
  final today = wallFromUtc(nowUtc ?? DateTime.now().toUtc());
  String side(DateTime utc) {
    final w = wallFromUtc(utc);
    if (isAllDay) return formatDate(w);
    return sameWallDay(w, today)
        ? formatTime(w)
        : '${formatDate(w)} ${formatTime(w)}';
  }

  final s = side(startUtc);
  return endUtc == null ? s : '$s → ${side(endUtc)}';
}

const _monthAbbr = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
];

String _shortDate(DateTime wall, DateTime? nowUtc) {
  final thisYear = wallFromUtc(nowUtc ?? DateTime.now().toUtc()).year;
  final y = wall.year == thisYear ? '' : " ${twoDigits(wall.year % 100)}'";
  return '${wall.day} ${_monthAbbr[wall.month - 1]}$y';
}

/// The days actions start in: `3 Oct - 12 Oct`, one date when both fall on the
/// same day, null when there is no start at all (year only when not current).
String? formatStartRange(
  DateTime? firstUtc,
  DateTime? lastUtc, {
  DateTime? nowUtc,
}) {
  if (firstUtc == null) return null;
  final a = wallFromUtc(firstUtc);
  final b = wallFromUtc(lastUtc ?? firstUtc);
  if (sameWallDay(a, b)) return _shortDate(a, nowUtc);
  return '${_shortDate(a, nowUtc)} - ${_shortDate(b, nowUtc)}';
}

/// Compact schedule for list rows: `3 Oct 13:00-14:40`; the year follows the
/// month as `'YY` only when it is not the current year (`3 Oct 27' 13:00-14:40`).
/// All-day = the date only; no end = the start time only; an end on another
/// day appends its date. Null when [startUtc] is null.
String? formatShortSchedule(
  DateTime? startUtc,
  DateTime? endUtc, {
  bool isAllDay = false,
  DateTime? nowUtc,
}) {
  if (startUtc == null) return null;
  String date(DateTime w) => _shortDate(w, nowUtc);

  final s = wallFromUtc(startUtc);
  if (isAllDay) return date(s);
  final head = '${date(s)} ${formatTime(s)}';
  if (endUtc == null) return head;
  final e = wallFromUtc(endUtc);
  return sameWallDay(s, e)
      ? '$head-${formatTime(e)}'
      : '$head-${date(e)} ${formatTime(e)}';
}
