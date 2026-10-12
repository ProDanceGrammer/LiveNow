import 'package:timezone/timezone.dart' as tz;

import '../core/settings.dart';

/// A "from / until / between" date filter on calendar DAYS in
/// [AppSettings.timeZoneName]. Both ends are optional and INCLUSIVE: a
/// transaction at 23:30 on the `until` day is still inside. The ends are kept
/// as UTC instants of that day's local midnight.
class DateRangeFilter {
  /// Local midnight (as UTC) of the first day, or null = no lower limit.
  final DateTime? from;

  /// Local midnight (as UTC) of the LAST day, or null = no upper limit.
  final DateTime? until;

  const DateRangeFilter({this.from, this.until});

  bool get active => from != null || until != null;

  /// `from` after `until`: nothing can match (the UI says so).
  bool get isEmpty => from != null && until != null && from!.isAfter(until!);

  /// True when [instant] (UTC) falls on a day inside the range.
  bool contains(DateTime instant) {
    final f = from, u = until;
    if (f != null && instant.isBefore(f)) return false;
    if (u != null && !instant.isBefore(_nextDay(u))) return false;
    return true;
  }

  DateRangeFilter copyWith({
    DateTime? from,
    bool clearFrom = false,
    DateTime? until,
    bool clearUntil = false,
  }) => DateRangeFilter(
    from: clearFrom ? null : (from ?? this.from),
    until: clearUntil ? null : (until ?? this.until),
  );

  @override
  bool operator ==(Object other) =>
      other is DateRangeFilter && other.from == from && other.until == until;

  @override
  int get hashCode => Object.hash(from, until);

  /// The range day for a date the user picked in a date picker (only its
  /// year/month/day count): local midnight of that day, as UTC.
  static DateTime dayStart(DateTime picked) {
    final loc = tz.getLocation(AppSettings.timeZoneName);
    return tz.TZDateTime(loc, picked.year, picked.month, picked.day).toUtc();
  }

  /// The calendar day of a stored range end, for showing it again in a picker.
  static DateTime dayOf(DateTime utc) {
    final l = tz.TZDateTime.from(utc, tz.getLocation(AppSettings.timeZoneName));
    return DateTime(l.year, l.month, l.day);
  }

  static DateTime _nextDay(DateTime dayStartUtc) {
    final l = tz.TZDateTime.from(
      dayStartUtc,
      tz.getLocation(AppSettings.timeZoneName),
    );
    return tz.TZDateTime(l.location, l.year, l.month, l.day + 1).toUtc();
  }
}
