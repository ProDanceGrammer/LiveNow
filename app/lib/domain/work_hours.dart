import '../core/settings.dart';

/// The user's working day, as minutes since local midnight. Postpone rules
/// read it: "after work" lands at [workEnd], the "morning" postpones at
/// [morning] (which may differ from [workStart]: a day can start at 09:00 and
/// still be postponed to 08:00).
class WorkHours {
  final int workStart;
  final int workEnd;
  final int morning;

  /// ISO weekdays (1 = Monday .. 7 = Sunday) that count as working days.
  final Set<int> workingWeekdays;

  const WorkHours({
    this.workStart = AppSettings.workStartMinutes,
    this.workEnd = AppSettings.afterWorkHour * 60,
    this.morning = AppSettings.morningHour * 60,
    this.workingWeekdays = AppSettings.workingWeekdays,
  });

  static const defaults = WorkHours();

  /// null when valid, else why not: the day must end after it starts, and
  /// every value must be a time of day.
  String? get problem {
    bool ok(int m) => m >= 0 && m < 24 * 60;
    if (!ok(workStart) || !ok(workEnd) || !ok(morning)) {
      return 'Times must be within one day.';
    }
    if (workEnd <= workStart) return 'Work must end after it starts.';
    if (workingWeekdays.isEmpty) return 'Pick at least one working day.';
    return null;
  }

  WorkHours copyWith({
    int? workStart,
    int? workEnd,
    int? morning,
    Set<int>? workingWeekdays,
  }) => WorkHours(
    workStart: workStart ?? this.workStart,
    workEnd: workEnd ?? this.workEnd,
    morning: morning ?? this.morning,
    workingWeekdays: workingWeekdays ?? this.workingWeekdays,
  );

  /// "09:00" for minutes-since-midnight [m].
  static String format(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  Map<String, Object?> toJson() => {
    'workStart': workStart,
    'workEnd': workEnd,
    'morning': morning,
    'workingWeekdays': (workingWeekdays.toList()..sort()),
  };

  /// Reads a saved value; anything missing, mistyped or invalid falls back to
  /// the defaults (a damaged file must never break postponing).
  factory WorkHours.fromJson(Object? json) {
    if (json is! Map) return defaults;
    int? read(String key) {
      final v = json[key];
      return v is int ? v : null;
    }

    final days = json['workingWeekdays'];
    final weekdays = days is List
        ? {
            for (final d in days)
              if (d is int && d >= 1 && d <= 7) d,
          }
        : null;
    final h = WorkHours(
      workingWeekdays: (weekdays == null || weekdays.isEmpty)
          ? defaults.workingWeekdays
          : weekdays,
      workStart: read('workStart') ?? defaults.workStart,
      workEnd: read('workEnd') ?? defaults.workEnd,
      morning: read('morning') ?? defaults.morning,
    );
    return h.problem == null ? h : defaults;
  }

  @override
  bool operator ==(Object other) =>
      other is WorkHours &&
      other.workStart == workStart &&
      other.workEnd == workEnd &&
      other.morning == morning &&
      other.workingWeekdays.length == workingWeekdays.length &&
      other.workingWeekdays.containsAll(workingWeekdays);

  @override
  int get hashCode => Object.hash(
    workStart,
    workEnd,
    morning,
    Object.hashAllUnordered(workingWeekdays),
  );
}
