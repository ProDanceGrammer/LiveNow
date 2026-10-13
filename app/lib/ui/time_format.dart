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

/// `02-10-2026` (day first).
String formatDate(DateTime wall) =>
    '${twoDigits(wall.day)}-${twoDigits(wall.month)}-${wall.year.toString().padLeft(4, '0')}';

/// `14:05`.
String formatTime(DateTime wall) =>
    '${twoDigits(wall.hour)}:${twoDigits(wall.minute)}';

/// `02-10-2026 14:05`, or just the date.
String formatDateTime(DateTime wall, {bool includeTime = true}) =>
    includeTime ? '${formatDate(wall)} ${formatTime(wall)}' : formatDate(wall);

/// Same as [formatClockTime] / [formatUtcDateTime] but from a UTC instant.
String formatClockTime(DateTime utc) => formatTime(wallFromUtc(utc));

String formatUtcDateTime(DateTime utc, {bool includeTime = true}) =>
    formatDateTime(wallFromUtc(utc), includeTime: includeTime);

bool sameWallDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// "start -> end" for a card: a side shows its date only when it is not today,
/// and an end on the same date as the start shows its time only
/// (`20-12-2026 12:00 → 14:00`), so a date is never printed twice.
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
  String side(DateTime w) {
    if (isAllDay) return formatDate(w);
    return sameWallDay(w, today)
        ? formatTime(w)
        : '${formatDate(w)} ${formatTime(w)}';
  }

  final s = wallFromUtc(startUtc);
  if (endUtc == null) return side(s);
  final e = wallFromUtc(endUtc);
  // Same date as the start: the end needs only its time.
  final endText = !isAllDay && sameWallDay(s, e) ? formatTime(e) : side(e);
  return '${side(s)} → $endText';
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

/// Compact schedule for list rows: `03-10-2026 13:00 → 14:40`. All-day = the
/// date only; no end = the start only; an end on another day appends its date
/// (`03-10-2026 13:00 → 04-10-2026 09:00`). Null when [startUtc] is null.
String? formatShortSchedule(
  DateTime? startUtc,
  DateTime? endUtc, {
  bool isAllDay = false,
  DateTime? nowUtc,
}) {
  if (startUtc == null) return null;
  final s = wallFromUtc(startUtc);
  if (isAllDay) return formatDate(s);
  final head = formatDateTime(s);
  if (endUtc == null) return head;
  final e = wallFromUtc(endUtc);
  return sameWallDay(s, e)
      ? '$head → ${formatTime(e)}'
      : '$head → ${formatDateTime(e)}';
}
