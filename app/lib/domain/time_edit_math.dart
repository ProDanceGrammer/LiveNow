// Pure date/time arithmetic behind the time-edit dialog. Works on "wall"
// values: a `DateTime.utc(...)` whose components ARE the wall-clock reading
// (conversion to/from real UTC instants happens in `ui/time_format.dart`).

enum TimeUnit { hour, minute, day, month, year }

/// Cursor order for Left/Right in a timed row: hours <-> minutes <-> day <->
/// month <-> year.
const List<TimeUnit> timedUnitOrder = [
  TimeUnit.hour,
  TimeUnit.minute,
  TimeUnit.day,
  TimeUnit.month,
  TimeUnit.year,
];

/// All-day rows only have the date segments.
const List<TimeUnit> dateUnitOrder = [
  TimeUnit.day,
  TimeUnit.month,
  TimeUnit.year,
];

const int _minYear = 1;
const int _maxYear = 9999;

/// The segment [dir] (-1 / +1) steps away from [from] in [order]; stays put at
/// either end (no wrap-around).
TimeUnit stepUnit(List<TimeUnit> order, TimeUnit from, int dir) {
  final i = order.indexOf(from);
  if (i < 0) return order.first;
  return order[(i + dir).clamp(0, order.length - 1)];
}

int daysInMonth(int year, int month) => DateTime.utc(year, month + 1, 0).day;

int unitValue(DateTime wall, TimeUnit unit) => switch (unit) {
  TimeUnit.hour => wall.hour,
  TimeUnit.minute => wall.minute,
  TimeUnit.day => wall.day,
  TimeUnit.month => wall.month,
  TimeUnit.year => wall.year,
};

/// Largest value a segment accepts for [wall] (day depends on the month).
int unitMax(DateTime wall, TimeUnit unit) => switch (unit) {
  TimeUnit.hour => 23,
  TimeUnit.minute => 59,
  TimeUnit.day => daysInMonth(wall.year, wall.month),
  TimeUnit.month => 12,
  TimeUnit.year => _maxYear,
};

int unitMin(TimeUnit unit) => switch (unit) {
  TimeUnit.hour || TimeUnit.minute => 0,
  TimeUnit.day || TimeUnit.month => 1,
  TimeUnit.year => _minYear,
};

/// Adds [delta] of [unit] with carry: minutes roll into hours, hours into
/// days, days into months/years. Months and years keep the other fields and
/// clamp the day to the target month's length (31 Jan + 1 month = 28/29 Feb).
DateTime addUnit(DateTime wall, TimeUnit unit, int delta) {
  switch (unit) {
    case TimeUnit.minute:
      return wall.add(Duration(minutes: delta));
    case TimeUnit.hour:
      return wall.add(Duration(hours: delta));
    case TimeUnit.day:
      return wall.add(Duration(days: delta));
    case TimeUnit.month:
      final total = wall.year * 12 + (wall.month - 1) + delta;
      return _withYearMonth(wall, total ~/ 12, total % 12 + 1);
    case TimeUnit.year:
      return _withYearMonth(wall, wall.year + delta, wall.month);
  }
}

/// Replaces one segment with [value], clamped to its valid range (typed
/// digits: 75 minutes becomes 59, day 31 in April becomes 30).
DateTime setUnit(DateTime wall, TimeUnit unit, int value) {
  final v = value.clamp(unitMin(unit), unitMax(wall, unit));
  switch (unit) {
    case TimeUnit.hour:
      return DateTime.utc(wall.year, wall.month, wall.day, v, wall.minute);
    case TimeUnit.minute:
      return DateTime.utc(wall.year, wall.month, wall.day, wall.hour, v);
    case TimeUnit.day:
      return DateTime.utc(wall.year, wall.month, v, wall.hour, wall.minute);
    case TimeUnit.month:
      return _withYearMonth(wall, wall.year, v);
    case TimeUnit.year:
      return _withYearMonth(wall, v, wall.month);
  }
}

DateTime _withYearMonth(DateTime wall, int year, int month) {
  final y = year.clamp(_minYear, _maxYear);
  final day = wall.day > daysInMonth(y, month)
      ? daysInMonth(y, month)
      : wall.day;
  return DateTime.utc(y, month, day, wall.hour, wall.minute);
}

/// Midnight of [wall]'s day (what an all-day action stores).
DateTime dateOnly(DateTime wall) =>
    DateTime.utc(wall.year, wall.month, wall.day);
