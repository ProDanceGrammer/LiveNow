/// App-wide scheduling defaults used by the postpone rules.
abstract final class AppSettings {
  static const int afterWorkHour = 18;
  static const int morningHour = 9;

  /// DateTime.weekday values: Monday = 1 ... Sunday = 7.
  static const Set<int> workingWeekdays = {1, 2, 3, 4, 5};

  static const String timeZoneName = 'Europe/Istanbul';
}
