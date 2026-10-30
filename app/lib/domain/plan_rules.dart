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

/// The app's zone; an unknown name (a damaged `time_zone.txt`) falls back to UTC
/// instead of throwing, which would hide every plan block.
tz.Location get _loc {
  try {
    return tz.getLocation(AppSettings.timeZoneName);
  } on Object {
    return tz.UTC;
  }
}

/// The instant of [minutes] after local midnight of [date] (minutes may exceed
/// 1440: the time then falls on a later day).
DateTime planInstant(DateTime date, int minutes, [String? zone]) =>
    tz.TZDateTime(
      zone == null ? _loc : _zoneOrMain(zone),
      date.year,
      date.month,
      date.day,
      0,
      minutes,
    ).toUtc();

/// A row's own timezone; the main one when its name is not in the database
/// (a plan synced from a newer version must still generate something).
tz.Location _zoneOrMain(String zone) {
  try {
    return tz.getLocation(zone);
  } on Object {
    return _loc;
  }
}

/// A whole number from stored JSON; null for a missing, NaN or infinite value
/// (`1e999` decodes to Infinity, and `Infinity.toInt()` throws).
int? _int(Object? v) => v is num && v.isFinite ? v.toInt() : null;

/// A time-of-day in minutes from stored JSON, kept within a week of midnight so
/// date arithmetic can never overflow (a stored 1 << 62 must not throw).
int _minutes(Object? v, int fallback) =>
    (v is num && v.isFinite ? v.toInt() : fallback).clamp(0, 24 * 60 * 7);

int _daysBetween(DateTime a, DateTime b) => b.difference(a).inDays;

int _daysInMonth(int y, int m) => DateTime.utc(y, m + 1, 0).day;

int _monthIndex(DateTime d) => d.year * 12 + (d.month - 1);

/// A Previous / Next action created together with each occurrence: [minutes]
/// long, starting [gapMinutes] after the main action ends (next) or ending
/// [gapMinutes] before it starts (previous). A template ([templateId]) brings its
/// name, directions and notes; [name] (else the template's) names it; every id
/// in [txTemplateIds] makes a transaction (Budget transaction templates).
class PlanCompanion {
  const PlanCompanion({
    this.name,
    this.templateId,
    this.minutes = 30,
    this.gapMinutes = 0,
    this.txTemplateIds = const [],
  });

  final String? name;
  final String? templateId;
  final int minutes;
  final int gapMinutes;
  final List<String> txTemplateIds;

  Map<String, Object?> toJson() => {
    if (name != null) 'name': name,
    if (templateId != null) 'templateId': templateId,
    'minutes': minutes,
    'gapMinutes': gapMinutes,
    if (txTemplateIds.isNotEmpty) 'tx': txTemplateIds,
  };

  static PlanCompanion fromJson(Map<String, Object?> j) => PlanCompanion(
    name: j['name'] as String?,
    templateId: j['templateId'] as String?,
    minutes: (_int(j['minutes']) ?? 30).clamp(1, 24 * 60),
    gapMinutes: (_int(j['gapMinutes']) ?? 0).clamp(0, 7 * 24 * 60),
    txTemplateIds: [
      for (final t in (j['tx'] as List? ?? const []))
        if (t is String) t,
    ],
  );
}

/// What an occurrence brings besides itself: [prev] / [next] companion actions
/// and the transactions ([txTemplateIds]) of the main action.
class PlanExtras {
  const PlanExtras({
    this.prev = const [],
    this.next = const [],
    this.txTemplateIds = const [],
  });

  final List<PlanCompanion> prev;
  final List<PlanCompanion> next;
  final List<String> txTemplateIds;

  bool get isEmpty => prev.isEmpty && next.isEmpty && txTemplateIds.isEmpty;

  /// Entries merged into the JSON of the occurrence / monthly rule.
  Map<String, Object?> toJson() => {
    if (prev.isNotEmpty) 'prev': [for (final c in prev) c.toJson()],
    if (next.isNotEmpty) 'next': [for (final c in next) c.toJson()],
    if (txTemplateIds.isNotEmpty) 'tx': txTemplateIds,
  };

  static PlanExtras fromJson(Map<String, Object?> j) {
    List<PlanCompanion> list(Object? v) => [
      for (final c in (v as List? ?? const []))
        if (c is Map) PlanCompanion.fromJson(Map<String, Object?>.from(c)),
    ];
    return PlanExtras(
      prev: list(j['prev']),
      next: list(j['next']),
      txTemplateIds: [
        for (final t in (j['tx'] as List? ?? const []))
          if (t is String) t,
      ],
    );
  }
}

/// One occurrence of a cycle: on cycle day [day] (0-based) at [startMin].
class CycleOccurrence {
  const CycleOccurrence({
    required this.day,
    required this.startMin,
    this.durationMin,
    this.name,
    this.templateId,
    this.extras = const PlanExtras(),
    this.allDay = false,
    this.tz,
  });

  final int day;
  final int startMin;
  final PlanExtras extras;

  /// The IANA timezone [startMin] is read in (e.g. "America/New_York": 09:00
  /// there every day, following its daylight saving); null = the app's own.
  final String? tz;

  /// An all-day row: it makes an all-day action on its day (the time, length and
  /// Previous / Next actions do not apply; transactions still do).
  final bool allDay;

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
    if (allDay) 'allDay': true,
    if (tz != null) 'tz': tz,
    ...extras.toJson(),
  };

  static CycleOccurrence fromJson(Map<String, Object?> j) => CycleOccurrence(
    day: _int(j['day']) ?? 0,
    startMin: _minutes(j['startMin'], 0),
    durationMin: _int(j['durationMin'])?.clamp(1, 24 * 60 * 7).toInt(),
    name: j['name'] as String?,
    templateId: j['templateId'] as String?,
    extras: PlanExtras.fromJson(j),
    allDay: j['allDay'] == true,
    tz: j['tz'] as String?,
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
    cycleDays: (_int(j['cycleDays']) ?? 7).clamp(1, 3650),
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
    this.extras = const PlanExtras(),
    this.allDay = false,
    this.tz,
  });

  final PlanExtras extras;

  /// See [CycleOccurrence.tz].
  final String? tz;

  /// See [CycleOccurrence.allDay].
  final bool allDay;

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
    if (allDay) 'allDay': true,
    if (tz != null) 'tz': tz,
    ...extras.toJson(),
  };

  static MonthlyRule fromJson(Map<String, Object?> j) => MonthlyRule(
    everyMonths: (_int(j['everyMonths']) ?? 1).clamp(1, 99999),
    mode: MonthlyMode.values.firstWhere(
      (m) => m.name == j['mode'],
      orElse: () => MonthlyMode.dayOfMonth,
    ),
    day: (_int(j['day']) ?? 1).clamp(1, 31),
    nth: _int(j['nth']) ?? 1,
    weekday: (_int(j['weekday']) ?? 1).clamp(1, 7),
    startMin: _minutes(j['startMin'], 9 * 60),
    durationMin: _int(j['durationMin'])?.clamp(1, 24 * 60 * 7).toInt(),
    name: j['name'] as String?,
    extras: PlanExtras.fromJson(j),
    allDay: j['allDay'] == true,
    tz: j['tz'] as String?,
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
    this.collectionIds = const [],
  });

  final String id;
  final String name;
  final String? templateId;
  final PlanKind kind;

  /// The plan collections the item belongs to (ids; deleted ones may linger).
  final List<String> collectionIds;

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

/// The ids of the plan items whose ghost blocks planning mode draws. [collections]
/// maps an existing collection id to whether it is visible. An item is shown
/// when it belongs to NO existing collection (ids of deleted collections do not
/// count) or to at least one visible one.
Set<String> visiblePlanItemIds(
  Iterable<PlanItemData> items,
  Map<String, bool> collections,
) {
  final out = <String>{};
  for (final i in items) {
    final mine = [for (final c in i.collectionIds) if (collections.containsKey(c)) c];
    if (mine.isEmpty || mine.any((c) => collections[c] == true)) out.add(i.id);
  }
  return out;
}

/// Reads the `collections` column (a JSON list of ids; anything else = none).
List<String> decodeCollectionIds(String? json) {
  if (json == null || json.isEmpty) return const [];
  try {
    final v = jsonDecode(json);
    if (v is List) return [for (final x in v) if (x is String) x];
  } catch (_) {
    // A damaged value means "no collection".
  }
  return const [];
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
    this.extras = const PlanExtras(),
    this.allDay = false,
    this.tz,
  });

  /// The timezone of the row this came from (null = the app's own): [date] and
  /// [startMin] are read there, so on the calendar use [displayed].
  final String? tz;

  /// This occurrence as the calendar shows it: [date] and [startMin] in the
  /// app's own timezone (the same object when the row has no zone of its own).
  /// [key] and [planItemId] stay those of the row.
  PlanOccurrence displayed() {
    if (tz == null || allDay) return this;
    final shownDate = planDateOf(startUtc);
    return PlanOccurrence(
      planItemId: planItemId,
      key: key,
      date: shownDate,
      startUtc: startUtc,
      endUtc: endUtc,
      name: name,
      templateId: templateId,
      index: index,
      startMin: startUtc.difference(planInstant(shownDate, 0)).inMinutes,
      durationMin: durationMin,
      ownName: ownName,
      extras: extras,
      allDay: allDay,
      tz: tz,
    );
  }

  /// [minutes] after midnight of [shownDate] (the app's own zone) expressed as
  /// minutes after the midnight of this row's own date in its own zone, which
  /// is what a stored override / rule holds.
  int rowMinutesFor(DateTime shownDate, int minutes) {
    if (tz == null) return minutes;
    final rowDate = planDateFromKey(key.split('#').first);
    return planInstant(shownDate, minutes)
        .difference(planInstant(rowDate, 0, tz))
        .inMinutes;
  }

  /// Previous / Next companions and transactions of this occurrence's row.
  final PlanExtras extras;

  /// An all-day occurrence: [startUtc] is its day's local midnight, [endUtc] the
  /// same instant, [startMin] / [durationMin] are 0.
  final bool allDay;

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
    PlanExtras extras,
    bool allDay,
    String? zone,
  ) {
    final key = '${planDateKey(date)}#$index';
    final o = byKey[key];
    if (o != null && o.skipped) return;
    // An all-day row has no time of its own: midnight, no length.
    final start = allDay ? 0 : (o?.startMin ?? startMin);
    final dur = allDay
        ? 0
        : (o?.durationMin ?? durationMin ?? defaultMinutes).clamp(1, 24 * 60 * 7);
    out.add(
      PlanOccurrence(
        planItemId: item.id,
        key: key,
        date: date,
        startUtc: planInstant(date, start, zone),
        endUtc: planInstant(date, start + dur, zone),
        allDay: allDay,
        name: o?.name ?? name ?? item.name,
        templateId: templateId ?? item.templateId,
        index: index,
        startMin: start,
        durationMin: dur,
        ownName: (o?.name ?? name) != null,
        extras: extras,
        tz: zone,
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
        add(date, i, o.startMin, o.durationMin, o.name, o.templateId, o.extras, o.allDay, o.tz);
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
      add(date, 0, rule.startMin, rule.durationMin, rule.name, null, rule.extras, rule.allDay, rule.tz);
    }
  }
  out.sort((a, b) {
    final c = a.startUtc.compareTo(b.startUtc);
    return c != 0 ? c : a.index.compareTo(b.index);
  });
  return out;
}

/// "09:00" or "09:00 (New York)" for a row read in its own timezone.
String planTimeIn(int minutes, String? zone) => zone == null
    ? planTime(minutes)
    : '${planTime(minutes)} (${zone.split('/').last.replaceAll('_', ' ')})';

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
    return '$every: $when ${m.allDay ? 'all day' : planTimeIn(m.startMin, m.tz)}';
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
        1 => o.allDay ? 'all day' : planTimeIn(o.startMin, o.tz),
        7 =>
          '${_weekdayNames[(startWeekday + o.day) % 7]} '
              '${o.allDay ? 'all day' : planTimeIn(o.startMin, o.tz)}',
        _ =>
          'day ${o.day + 1} ${o.allDay ? 'all day' : planTimeIn(o.startMin, o.tz)}',
      },
  ];
  return '$head: ${parts.join(', ')}';
}
