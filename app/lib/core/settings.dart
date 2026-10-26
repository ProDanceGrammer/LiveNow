import 'package:timezone/timezone.dart' as tz;

/// App-wide scheduling defaults used by the postpone rules.
abstract final class AppSettings {
  static const int afterWorkHour = 18;
  static const int morningHour = 9;

  /// When the working day starts by default (minutes since midnight).
  static const int workStartMinutes = 9 * 60;

  /// DateTime.weekday values: Monday = 1 ... Sunday = 7.
  static const Set<int> workingWeekdays = {1, 2, 3, 4, 5};

  /// The zone used when the device's own cannot be read (and in tests).
  static const String defaultTimeZoneName = 'Europe/Istanbul';

  static String _timeZoneName = defaultTimeZoneName;

  /// The zone whose wall clock defines days, midnight, reminders and the
  /// postpone rules: the computer's own, or the one chosen in Settings
  /// (`data/time_zone_setup.dart` sets it at start-up). Read at call time.
  static String get timeZoneName => _timeZoneName;

  /// Switches the zone; false (and no change) for a name the timezone database
  /// does not know. The timezone database must be initialised first.
  static bool setTimeZoneName(String name) {
    try {
      tz.getLocation(name);
    } on Object {
      return false;
    }
    _timeZoneName = name;
    return true;
  }
}
