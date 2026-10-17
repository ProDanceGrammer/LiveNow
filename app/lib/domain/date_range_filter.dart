import 'package:timezone/timezone.dart' as tz;

import '../core/settings.dart';

/// A quick choice for a date filter: whole calendar periods in
/// [AppSettings.timeZoneName] (weeks run Monday-Sunday), always relative to
/// TODAY. A saved view stores the choice, not its dates, so reopening it
/// applies the same choice with the new dates.
///
/// For a week, a month and a year there are five: last one, "so far" (the start
/// of the period up to today), "rest of" (tomorrow up to the period's end),
/// the whole current one, and the next one. "Rest of" on the period's last day
/// is empty (nothing left).
enum DatePreset {
  yesterday('Yesterday', 'Day'),
  today('Today', 'Day'),
  tomorrow('Tomorrow', 'Day'),
  lastWeek('Last week', 'Week'),
  weekSoFar('This week so far', 'Week'),
  weekRest('Rest of this week', 'Week'),
  thisWeek('This week', 'Week'),
  nextWeek('Next week', 'Week'),
  lastMonth('Last month', 'Month'),
  monthSoFar('This month so far', 'Month'),
  monthRest('Rest of this month', 'Month'),
  thisMonth('This month', 'Month'),
  nextMonth('Next month', 'Month'),
  lastYear('Last year', 'Year'),
  yearSoFar('This year so far', 'Year'),
  yearRest('Rest of this year', 'Year'),
  thisYear('This year', 'Year'),
  nextYear('Next year', 'Year');

  const DatePreset(this.label, this.group);

  /// Shown on the chip and in the menu.
  final String label;

  /// The menu heading: Day, Week, Month or Year.
  final String group;

  /// The first and the LAST day (local midnights as UTC) of this choice when
  /// today is the day containing [nowUtc]. `from` is after `until` for an
  /// empty "rest of" on the last day of its period.
  ({DateTime from, DateTime until}) resolve(DateTime nowUtc) {
    final loc = tz.getLocation(AppSettings.timeZoneName);
    final n = tz.TZDateTime.from(nowUtc, loc);
    DateTime day(int y, int m, int d) {
      final t = tz.TZDateTime(loc, y, m, d).toUtc();
      // A plain UTC DateTime (a TZDateTime never equals one).
      return DateTime.fromMillisecondsSinceEpoch(
        t.millisecondsSinceEpoch,
        isUtc: true,
      );
    }

    final today = day(n.year, n.month, n.day);
    DateTime offset(int days) => day(n.year, n.month, n.day + days);
    // Monday of this week, the Sunday after it.
    final back = n.weekday - DateTime.monday;
    DateTime monday(int weeks) => offset(-back + 7 * weeks);
    DateTime sunday(int weeks) => offset(-back + 7 * weeks + 6);
    // The first and the last day of the month [m] months from this one.
    DateTime first(int m) => day(n.year, n.month + m, 1);
    DateTime last(int m) => day(n.year, n.month + m + 1, 0);
    final tomorrow = offset(1);

    return switch (this) {
      DatePreset.yesterday => (from: offset(-1), until: offset(-1)),
      DatePreset.today => (from: today, until: today),
      DatePreset.tomorrow => (from: tomorrow, until: tomorrow),
      DatePreset.lastWeek => (from: monday(-1), until: sunday(-1)),
      DatePreset.weekSoFar => (from: monday(0), until: today),
      DatePreset.weekRest => (from: tomorrow, until: sunday(0)),
      DatePreset.thisWeek => (from: monday(0), until: sunday(0)),
      DatePreset.nextWeek => (from: monday(1), until: sunday(1)),
      DatePreset.lastMonth => (from: first(-1), until: last(-1)),
      DatePreset.monthSoFar => (from: first(0), until: today),
      DatePreset.monthRest => (from: tomorrow, until: last(0)),
      DatePreset.thisMonth => (from: first(0), until: last(0)),
      DatePreset.nextMonth => (from: first(1), until: last(1)),
      DatePreset.lastYear => (from: day(n.year - 1, 1, 1), until: day(n.year - 1, 12, 31)),
      DatePreset.yearSoFar => (from: day(n.year, 1, 1), until: today),
      DatePreset.yearRest => (from: tomorrow, until: day(n.year, 12, 31)),
      DatePreset.thisYear => (from: day(n.year, 1, 1), until: day(n.year, 12, 31)),
      DatePreset.nextYear => (from: day(n.year + 1, 1, 1), until: day(n.year + 1, 12, 31)),
    };
  }
}

/// A "from / until / between" date filter on calendar DAYS in
/// [AppSettings.timeZoneName]. Both ends are optional and INCLUSIVE: a
/// transaction at 23:30 on the `until` day is still inside. The ends are kept
/// as UTC instants of that day's local midnight.
///
/// Instead of dates it can hold a quick [preset] (Last week, Today ...): then
/// the dates are worked out from TODAY each time the filter is used
/// ([resolved]), so the choice stays right from one day to the next and a saved
/// view keeps meaning "last week" rather than one particular week.
class DateRangeFilter {
  /// Local midnight (as UTC) of the first day, or null = no lower limit.
  /// Ignored while [preset] is set.
  final DateTime? from;

  /// Local midnight (as UTC) of the LAST day, or null = no upper limit.
  /// Ignored while [preset] is set.
  final DateTime? until;

  /// A quick choice resolved against today, or null = the custom dates above.
  final DatePreset? preset;

  const DateRangeFilter({this.from, this.until, this.preset});

  bool get active => preset != null || from != null || until != null;

  /// The same filter with the preset (if any) turned into its dates for today,
  /// or for the day containing [nowUtc]. A custom filter is returned as it is.
  /// Callers that test many rows resolve once, then use the result.
  DateRangeFilter resolved([DateTime? nowUtc]) {
    final p = preset;
    if (p == null) return this;
    final r = p.resolve(nowUtc ?? DateTime.now().toUtc());
    return DateRangeFilter(from: r.from, until: r.until);
  }

  /// `from` after `until`: nothing can match (the UI says so).
  bool get isEmpty {
    final r = resolved();
    return r.from != null && r.until != null && r.from!.isAfter(r.until!);
  }

  /// True when [instant] (UTC) falls on a day inside the range.
  bool contains(DateTime instant, {DateTime? nowUtc}) {
    final r = resolved(nowUtc);
    final f = r.from, u = r.until;
    if (f != null && instant.isBefore(f)) return false;
    if (u != null && !instant.isBefore(_nextDay(u))) return false;
    return true;
  }

  /// A preset REPLACES any custom dates; [clearPreset] removes the preset and
  /// the dates it stood for; changing [from] / [until] of a preset filter turns
  /// it into a custom range seeded from the dates the preset resolves to now.
  DateRangeFilter copyWith({
    DateTime? from,
    bool clearFrom = false,
    DateTime? until,
    bool clearUntil = false,
    DatePreset? preset,
    bool clearPreset = false,
  }) {
    if (preset != null) return DateRangeFilter(preset: preset);
    if (clearPreset) return const DateRangeFilter();
    final base = resolved();
    return DateRangeFilter(
      from: clearFrom ? null : (from ?? base.from),
      until: clearUntil ? null : (until ?? base.until),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DateRangeFilter &&
      other.from == from &&
      other.until == until &&
      other.preset == preset;

  @override
  int get hashCode => Object.hash(from, until, preset);

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
