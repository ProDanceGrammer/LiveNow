import 'dart:convert';

import 'package:timezone/timezone.dart' as tz;

import '../core/settings.dart';

/// Planning (pure, no database): what a plan item generates in a range of days.
///
/// A PLAN ITEM repeats either on a CYCLE of N days (a week = 7, "every day" = 1,
/// "2 days on, 1 day off" = 3 ...), each cycle day holding any number of
/// occurrences (name, start time, duration), or on a MONTHLY rule (a day of the
/// month, the Nth weekday, the last day, every N months). Dates are Istanbul
/// local calendar dates, carried as `DateTime.utc(y, m, d)` ("date only"); times
/// are minutes after local midnight. Only calendar-day arithmetic is used, never
/// `Duration(hours: 24)`.

enum PlanKind { cycle, monthly }

enum MonthlyMode { dayOfMonth, nthWeekday, lastDay }

/// A local calendar date as a UTC-midnight `DateTime` (compares and sorts).
DateTime planDate(int y, int m, int d) => DateTime.utc(y, m, d);

String planDateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime planDateFromKey(String key) {
  final p = key.split('-');
  return DateTime.utc(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

/// The local date of an instant.
DateTime planDateOf(DateTime utc) {
  final l = tz.TZDateTime.from(utc.toUtc(), _loc);
  return DateTime.utc(l.year, l.month, l.day);
}

tz.Location get _loc => tz.getLocation(AppSettings.timeZoneName);

/// The instant of [minutes] after local midnight of [date] (minutes may exceed
/// 1440: the time then falls on a later day).
DateTime planInstant(DateTime date, int minutes) =>
    tz.TZDateTime(_loc, date.year, date.month, date.day, 0, minutes).toUtc();

int _daysBetween(DateTime a, DateTime b) => b.difference(a).inDays;

int _daysInMonth(int y, int m) => DateTime.utc(y, m + 1, 0).day;

int _monthIndex(DateTime d) => d.year * 12 + (d.month - 1);

/// One occurrence of a cycle: on cycle day [day] (0-based) at [startMin].
class CycleOccurrence {
  const CycleOccurrence({
    required this.day,
    required this.startMin,
    this.durationMin,
    this.name,
    this.templateId,
  });

  final int day;
  final int startMin;

  /// Null = the plan item's default duration (the template's average).
  final int? durationMin;

  /// Null = the plan item's name.
  final String? name;
  final String? templateId;

  Map<String, Object?> toJson() => {
    'day': day,
    'startMin': startMin,
    if (durationMin != null) 'durationMin': durationMin,
    if (name != null) 'name': name,
    if (templateId != null) 'templateId': templateId,
  };

  static CycleOccurrence fromJson(Map<String, Object?> j) => CycleOccurrence(
    day: (j['day'] as num?)?.toInt() ?? 0,
    startMin: (j['startMin'] as num?)?.toInt() ?? 0,
    durationMin: (j['durationMin'] as num?)?.toInt(),
    name: j['name'] as String?,
    templateId: j['templateId'] as String?,
  );
}

class CycleRule {
  const CycleRule({this.cycleDays = 7, this.occurrences = const []});

  final int cycleDays;
  final List<CycleOccurrence> occurrences;

  Map<String, Object?> toJson() => {
    'cycleDays': cycleDays,
    'occurrences': [for (final o in occurrences) o.toJson()],
  };

  static CycleRule fromJson(Map<String, Object?> j) => CycleRule(
    cycleDays: ((j['cycleDays'] as num?)?.toInt() ?? 7).clamp(1, 3650),
    occurrences: [
      for (final o in (j['occurrences'] as List? ?? const []))
        if (o is Map) CycleOccurrence.fromJson(Map<String, Object?>.from(o)),
    ],
  );
}

class MonthlyRule {
  const MonthlyRule({
    this.everyMonths = 1,
    this.mode = MonthlyMode.dayOfMonth,
    this.day = 1,
    this.nth = 1,
    this.weekday = DateTime.monday,
    this.startMin = 9 * 60,
    this.durationMin,
    this.name,
  });

  /// Every N months (1..99999) counted from the plan's start month.
  final int everyMonths;
  final MonthlyMode mode;

  /// `dayOfMonth`: 1..31 (clamped to the month's length).
  final int day;

  /// `nthWeekday`: 1..4, or -1 for the last one.
  final int nth;

  /// `nthWeekday`: 1 = Monday .. 7 = Sunday.
  final int weekday;
  final int startMin;
  final int? durationMin;
  final String? name;

  Map<String, Object?> toJson() => {
    'everyMonths': everyMonths,
    'mode': mode.name,
    'day': day,
    'nth': nth,
    'weekday': weekday,
    'startMin': startMin,
    if (durationMin != null) 'durationMin': durationMin,
    if (name != null) 'name': name,
  };

  static MonthlyRule fromJson(Map<String, Object?> j) => MonthlyRule(
    everyMonths: ((j['everyMonths'] as num?)?.toInt() ?? 1).clamp(1, 99999),
    mode: MonthlyMode.values.firstWhere(
      (m) => m.name == j['mode'],
      orElse: () => MonthlyMode.dayOfMonth,
    ),
    day: ((j['day'] as num?)?.toInt() ?? 1).clamp(1, 31),
    nth: (j['nth'] as num?)?.toInt() ?? 1,
    weekday: ((j['weekday'] as num?)?.toInt() ?? 1).clamp(1, 7),
    startMin: (j['startMin'] as num?)?.toInt() ?? 9 * 60,
    durationMin: (j['durationMin'] as num?)?.toInt(),
    name: j['name'] as String?,
  );
}

/// What the generator needs of a plan item (the stored row, decoded).
class PlanItemData {
  const PlanItemData({
    required this.id,
    required this.name,
    this.templateId,
    required this.kind,
    required this.startDate,
    this.endDate,
    this.forever = false,
    this.paused = false,
    this.cycle,
    this.monthly,
  });

  final String id;
  final String name;
  final String? templateId;
  final PlanKind kind;

  /// First day of the pattern (cycle day 0 / first month), a [planDate].
  final DateTime startDate;

  /// Last day (inclusive); null = no end. [forever] wins over it.
  final DateTime? endDate;
  final bool forever;
  final bool paused;
  final CycleRule? cycle;
  final MonthlyRule? monthly;

  /// The `rule` column.
  String get ruleJson =>
      jsonEncode(kind == PlanKind.cycle ? cycle?.toJson() : monthly?.toJson());

  static ({CycleRule? cycle, MonthlyRule? monthly}) decodeRule(
    PlanKind kind,
    String json,
  ) {
    try {
      final j = jsonDecode(json);
      if (j is Map) {
        final m = Map<String, Object?>.from(j);
        return kind == PlanKind.cycle
            ? (cycle: CycleRule.fromJson(m), monthly: null)
            : (cycle: null, monthly: MonthlyRule.fromJson(m));
      }
    } catch (_) {
      // A damaged rule generates nothing.
    }
    return (cycle: null, monthly: null);
  }
}

/// "This day only" edits of one occurrence (or its removal).
class PlanOverrideData {
  const PlanOverrideData({
    required this.date,
    required this.index,
    this.startMin,
    this.durationMin,
    this.name,
    this.skipped = false,
  });

  final DateTime date;
  final int index;
  final int? startMin;
  final int? durationMin;
  final String? name;
  final bool skipped;
}

/// One generated occurrence.
class PlanOccurrence {
  const PlanOccurrence({
    required this.planItemId,
    required this.key,
    required this.date,
    required this.startUtc,
    required this.endUtc,
    required this.name,
    this.templateId,
    required this.index,
    required this.startMin,
    required this.durationMin,
    this.ownName = false,
  });

  final String planItemId;

  /// `YYYY-MM-DD#index`: stable across navigation and re-confirmations.
  final String key;
  final DateTime date;
  final DateTime startUtc;
  final DateTime endUtc;
  final String name;
  final String? templateId;
  final int index;
  final int startMin;
  final int durationMin;

  /// True when the occurrence (or its override) names itself; false = it shows
  /// the plan item's label and a confirmed action takes its TEMPLATE's name.
  final bool ownName;
}

/// The occurrences of [item] on the local dates [from]..[to] (both inclusive,
/// [planDate]s), overrides applied, ordered by start. [defaultMinutes] is the
/// duration of an occurrence that has none of its own (the template's average,
/// else its manual time, else 60 - the service decides).
List<PlanOccurrence> occurrencesInRange(
  PlanItemData item,
  DateTime from,
  DateTime to, {
  List<PlanOverrideData> overrides = const [],
  int defaultMinutes = 60,
}) {
  if (item.paused || to.isBefore(from)) return const [];
  final first = from.isBefore(item.startDate) ? item.startDate : from;
  final last = !item.forever && item.endDate != null && item.endDate!.isBefore(to)
      ? item.endDate!
      : to;
  if (last.isBefore(first)) return const [];

  final byKey = {
    for (final o in overrides) '${planDateKey(o.date)}#${o.index}': o,
  };
  final out = <PlanOccurrence>[];

  void add(
    DateTime date,
    int index,
    int startMin,
    int? durationMin,
    String? name,
    String? templateId,
  ) {
    final key = '${planDateKey(date)}#$index';
    final o = byKey[key];
    if (o != null && o.skipped) return;
    final start = o?.startMin ?? startMin;
    final dur = (o?.durationMin ?? durationMin ?? defaultMinutes).clamp(1, 24 * 60 * 7);
    out.add(
      PlanOccurrence(
        planItemId: item.id,
        key: key,
        date: date,
        startUtc: planInstant(date, start),
        endUtc: planInstant(date, start + dur),
        name: o?.name ?? name ?? item.name,
        templateId: templateId ?? item.templateId,
        index: index,
        startMin: start,
        durationMin: dur,
        ownName: (o?.name ?? name) != null,
      ),
    );
  }

  if (item.kind == PlanKind.cycle) {
    final rule = item.cycle;
    if (rule == null || rule.occurrences.isEmpty) return const [];
    final n = rule.cycleDays < 1 ? 1 : rule.cycleDays;
    // Which cycle-day buckets hold what (index = position in the list).
    final byDay = <int, List<int>>{};
    for (var i = 0; i < rule.occurrences.length; i++) {
      byDay.putIfAbsent(rule.occurrences[i].day % n, () => []).add(i);
    }
    var date = first;
    while (!date.isAfter(last)) {
      final k = _daysBetween(item.startDate, date);
      for (final i in byDay[k % n] ?? const <int>[]) {
        final o = rule.occurrences[i];
        add(date, i, o.startMin, o.durationMin, o.name, o.templateId);
      }
      date = DateTime.utc(date.year, date.month, date.day + 1);
    }
  } else {
    final rule = item.monthly;
    if (rule == null) return const [];
    final every = rule.everyMonths < 1 ? 1 : rule.everyMonths;
    final startMi = _monthIndex(item.startDate);
    final fromMi = _monthIndex(first);
    final lastMi = _monthIndex(last);
    var step = fromMi <= startMi ? 0 : ((fromMi - startMi) / every).ceil();
    for (;; step++) {
      final mi = startMi + step * every;
      if (mi > lastMi) break;
      final y = mi ~/ 12, m = mi % 12 + 1;
      final dim = _daysInMonth(y, m);
      int? day;
      switch (rule.mode) {
        case MonthlyMode.dayOfMonth:
          day = rule.day > dim ? dim : rule.day;
        case MonthlyMode.lastDay:
          day = dim;
        case MonthlyMode.nthWeekday:
          if (rule.nth == -1) {
            for (var d = dim; d >= 1; d--) {
              if (DateTime.utc(y, m, d).weekday == rule.weekday) {
                day = d;
                break;
              }
            }
          } else {
            var seen = 0;
            for (var d = 1; d <= dim; d++) {
              if (DateTime.utc(y, m, d).weekday == rule.weekday &&
                  ++seen == rule.nth) {
                day = d;
                break;
              }
            }
          }
      }
      if (day == null) continue; // e.g. no 5th Monday this month
      final date = DateTime.utc(y, m, day);
      if (date.isBefore(first) || date.isAfter(last)) continue;
      add(date, 0, rule.startMin, rule.durationMin, rule.name, null);
    }
  }
  out.sort((a, b) {
    final c = a.startUtc.compareTo(b.startUtc);
    return c != 0 ? c : a.index.compareTo(b.index);
  });
  return out;
}

String planTime(int minutes) {
  final m = minutes % (24 * 60);
  return '${(m ~/ 60).toString().padLeft(2, '0')}:'
      '${(m % 60).toString().padLeft(2, '0')}';
}

const _weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _ordinal(int n) => switch (n) {
  1 => '1st',
  2 => '2nd',
  3 => '3rd',
  _ => '${n}th',
};

/// A one-line summary of a plan item for lists: "Weekly: Mon 09:00, Thu 09:30",
/// "Every 3 days: day 1 08:00", "Every 2 months: 2nd Thu 18:00".
String describePlan(PlanItemData item) {
  if (item.kind == PlanKind.monthly) {
    final m = item.monthly;
    if (m == null) return 'Monthly';
    final every = m.everyMonths == 1 ? 'Every month' : 'Every ${m.everyMonths} months';
    final when = switch (m.mode) {
      MonthlyMode.dayOfMonth => 'day ${m.day}',
      MonthlyMode.lastDay => 'last day',
      MonthlyMode.nthWeekday =>
        '${m.nth == -1 ? 'last' : _ordinal(m.nth)} ${_weekdayNames[m.weekday - 1]}',
    };
    return '$every: $when ${planTime(m.startMin)}';
  }
  final c = item.cycle;
  if (c == null || c.occurrences.isEmpty) return 'Nothing planned';
  final head = switch (c.cycleDays) {
    1 => 'Daily',
    7 => 'Weekly',
    _ => 'Every ${c.cycleDays} days',
  };
  final startWeekday = item.startDate.weekday - 1;
  final sorted = [...c.occurrences]
    ..sort((a, b) {
      final d = a.day.compareTo(b.day);
      return d != 0 ? d : a.startMin.compareTo(b.startMin);
    });
  final parts = [
    for (final o in sorted)
      switch (c.cycleDays) {
        1 => planTime(o.startMin),
        7 => '${_weekdayNames[(startWeekday + o.day) % 7]} ${planTime(o.startMin)}',
        _ => 'day ${o.day + 1} ${planTime(o.startMin)}',
      },
  ];
  return '$head: ${parts.join(', ')}';
}
