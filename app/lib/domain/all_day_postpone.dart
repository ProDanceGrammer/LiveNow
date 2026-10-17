import 'package:timezone/timezone.dart' as tz;

import '../core/local_time.dart';
import '../core/settings.dart';

// The two postpone buttons of an ALL-DAY card in the week strip. An all-day
// action is a whole day (start = that day's local midnight, no end), so these
// move it by whole days and give back a local midnight: unlike the timed
// "next Monday morning" rule they never put a time on it.
//
// Both count from the card's OWN day (never from today), in the app's time zone
// (Istanbul). Callers must have initialised the timezone database.

/// The same weekday one week later: the local midnight 7 calendar days after the
/// local day containing [startUtc].
DateTime allDayPlusSevenDays(DateTime startUtc) =>
    calendarAddDays(localDayStart(startUtc), 7);

/// The next Monday strictly AFTER the local day containing [startUtc], at local
/// midnight: from a Wednesday the coming Monday, from a Sunday tomorrow, from a
/// Monday the Monday a week later (never the same day).
DateTime allDayToMonday(DateTime startUtc) {
  final local = tz.TZDateTime.from(
    startUtc,
    tz.getLocation(AppSettings.timeZoneName),
  );
  var ahead = (DateTime.monday - local.weekday + 7) % 7;
  if (ahead == 0) ahead = 7;
  return calendarAddDays(localDayStart(startUtc), ahead);
}
