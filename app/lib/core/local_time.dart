import 'package:timezone/timezone.dart' as tz;

import 'settings.dart';

// Calendar-day arithmetic in AppSettings.timeZoneName. Shared by the calendar
// view (ui/) and the growth-direction windows (domain/), so it lives in core/.
// Callers must have initialised the timezone database (see
// initPostponeTimeZoneData).

tz.Location get _location => tz.getLocation(AppSettings.timeZoneName);

/// UTC instant of local midnight [days] days after the local midnight
/// [utcMidnight] (DST-safe: shifts calendar days, not 24 h blocks).
DateTime calendarAddDays(DateTime utcMidnight, int days) {
  final l = tz.TZDateTime.from(utcMidnight, _location);
  return tz.TZDateTime(_location, l.year, l.month, l.day + days).toUtc();
}

/// UTC instant of local midnight of the day containing [utc].
DateTime localDayStart(DateTime utc) {
  final l = tz.TZDateTime.from(utc, _location);
  return tz.TZDateTime(_location, l.year, l.month, l.day).toUtc();
}

/// UTC instant of local midnight of the day [months] calendar months before
/// the day containing [utc]; the day of month is clamped to the length of the
/// target month (31 March minus one month is the last day of February).
DateTime localDayStartMonthsBack(DateTime utc, int months) {
  final l = tz.TZDateTime.from(utc, _location);
  var year = l.year;
  var month = l.month - months;
  while (month < 1) {
    month += 12;
    year -= 1;
  }
  final lastDay = DateTime.utc(year, month + 1, 0).day;
  final day = l.day > lastDay ? lastDay : l.day;
  return tz.TZDateTime(_location, year, month, day).toUtc();
}
