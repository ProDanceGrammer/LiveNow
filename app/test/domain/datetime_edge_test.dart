import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/local_time.dart';
import 'package:livenow/core/time_codec.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/budget_rules.dart';
import 'package:livenow/domain/date_range_filter.dart';
import 'package:livenow/domain/duration_rules.dart';
import 'package:livenow/domain/growth_rules.dart';
import 'package:livenow/domain/plan_rules.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/domain/sync/change_validation.dart';
import 'package:livenow/domain/sync/hlc.dart';
import 'package:livenow/domain/sync/sync_models.dart';
import 'package:timezone/timezone.dart' as tz;

// Date and time edge cases. Every test passes its own "now"; none reads the
// wall clock, so they hold at any time of day.
//
// The app is fixed to Europe/Istanbul (UTC+3, no DST since 2016). The pure
// rules read AppSettings.timeZoneName (a const) and take no tz location, so a
// DST zone cannot be injected: see the last group.

/// The UTC instant of an Istanbul wall-clock time (UTC+3 all year).
DateTime ist(int y, int m, int d, [int h = 0, int mi = 0]) =>
    DateTime.utc(y, m, d, h - 3, mi);

PlanItemData _monthly(
  MonthlyRule rule,
  DateTime start, {
  DateTime? end,
}) => PlanItemData(
  id: 'p',
  name: 'Plan',
  kind: PlanKind.monthly,
  startDate: start,
  endDate: end,
  forever: end == null,
  monthly: rule,
);

List<String> _keys(PlanItemData item, DateTime from, DateTime to) => [
  for (final o in occurrencesInRange(item, from, to)) o.key,
];

void main() {
  setUpAll(initPostponeTimeZoneData);

  group('plan rules around Feb 29', () {
    test('monthly day 29/30/31 is clamped to the month length (leap and not)', () {
      for (final (day, leap, plain) in [
        (29, '2024-02-29#0', '2025-02-28#0'),
        (30, '2024-02-29#0', '2025-02-28#0'),
        (31, '2024-02-29#0', '2025-02-28#0'),
      ]) {
        final item = _monthly(
          MonthlyRule(day: day),
          planDate(2024, 1, 1),
        );
        expect(
          _keys(item, planDate(2024, 2, 1), planDate(2024, 2, 29)),
          [leap],
          reason: 'day $day in leap Feb',
        );
        expect(
          _keys(item, planDate(2025, 2, 1), planDate(2025, 2, 28)),
          [plain],
          reason: 'day $day in plain Feb',
        );
      }
    });

    test('monthly day 31 across a whole year lands on each month end', () {
      final item = _monthly(MonthlyRule(day: 31), planDate(2024, 1, 1));
      final days = [
        for (final o in occurrencesInRange(
          item,
          planDate(2024, 1, 1),
          planDate(2024, 12, 31),
        ))
          o.date.day,
      ];
      expect(days, [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]);
    });

    test('yearly (every 12 months) rule born on Feb 29 follows the month length', () {
      final item = _monthly(
        MonthlyRule(everyMonths: 12, day: 29),
        planDate(2024, 2, 29),
      );
      expect(
        _keys(item, planDate(2024, 1, 1), planDate(2029, 12, 31)),
        [
          '2024-02-29#0',
          '2025-02-28#0',
          '2026-02-28#0',
          '2027-02-28#0',
          '2028-02-29#0',
          '2029-02-28#0',
        ],
      );
    });

    test('last-day rule and last Sunday in Feb of leap / non-leap years', () {
      final last = _monthly(
        const MonthlyRule(mode: MonthlyMode.lastDay),
        planDate(2024, 1, 1),
      );
      expect(_keys(last, planDate(2024, 2, 1), planDate(2024, 2, 29)), [
        '2024-02-29#0',
      ]);
      expect(_keys(last, planDate(2025, 2, 1), planDate(2025, 2, 28)), [
        '2025-02-28#0',
      ]);
      final lastSunday = _monthly(
        const MonthlyRule(
          mode: MonthlyMode.nthWeekday,
          nth: -1,
          weekday: DateTime.sunday,
        ),
        planDate(2024, 1, 1),
      );
      expect(_keys(lastSunday, planDate(2024, 2, 1), planDate(2024, 2, 29)), [
        '2024-02-25#0',
      ]);
      expect(_keys(lastSunday, planDate(2025, 2, 1), planDate(2025, 2, 28)), [
        '2025-02-23#0',
      ]);
    });

    test('a cycle of every day produces Feb 29 and the 366-day year is whole', () {
      final item = PlanItemData(
        id: 'c',
        name: 'Daily',
        kind: PlanKind.cycle,
        startDate: planDate(2024, 1, 1),
        forever: true,
        cycle: const CycleRule(
          cycleDays: 1,
          occurrences: [CycleOccurrence(day: 0, startMin: 600)],
        ),
      );
      final all = occurrencesInRange(
        item,
        planDate(2024, 1, 1),
        planDate(2024, 12, 31),
      );
      expect(all, hasLength(366));
      expect(all.any((o) => o.key == '2024-02-29#0'), isTrue);
      expect(
        occurrencesInRange(item, planDate(2025, 1, 1), planDate(2025, 12, 31)),
        hasLength(365),
      );
    });

    test('a 7-day cycle keeps its weekday across Feb 29 and the year boundary', () {
      // Starts Monday 2024-02-26; cycle day 0 = Monday.
      final item = PlanItemData(
        id: 'c',
        name: 'Weekly',
        kind: PlanKind.cycle,
        startDate: planDate(2024, 2, 26),
        forever: true,
        cycle: const CycleRule(
          occurrences: [CycleOccurrence(day: 0, startMin: 540)],
        ),
      );
      final all = occurrencesInRange(
        item,
        planDate(2024, 2, 26),
        planDate(2025, 1, 31),
      );
      expect(all.every((o) => o.date.weekday == DateTime.monday), isTrue);
      expect(all.map((o) => o.key), contains('2024-12-30#0'));
      expect(all.map((o) => o.key), contains('2025-01-06#0'));
    });

    test('an occurrence at 23:30 for 2 h ends on the next local day / year', () {
      final item = PlanItemData(
        id: 'c',
        name: 'Late',
        kind: PlanKind.cycle,
        startDate: planDate(2023, 12, 31),
        forever: true,
        cycle: const CycleRule(
          cycleDays: 1,
          occurrences: [
            CycleOccurrence(day: 0, startMin: 23 * 60 + 30, durationMin: 120),
          ],
        ),
      );
      final o = occurrencesInRange(
        item,
        planDate(2023, 12, 31),
        planDate(2023, 12, 31),
      ).single;
      expect(o.startUtc, ist(2023, 12, 31, 23, 30));
      expect(o.endUtc, ist(2024, 1, 1, 1, 30));
      expect(planDateOf(o.endUtc), planDate(2024, 1, 1));
    });

    test('plan date keys survive years 1, 1970, 2038, 2100 and 9999', () {
      for (final y in [1, 1970, 2038, 2100, 9999]) {
        final d = planDate(y, 2, 28);
        expect(planDateFromKey(planDateKey(d)), d);
      }
    });
  });

  group('postpone rules', () {
    ActionSchedule at(DateTime start, {int minutes = 60}) =>
        ActionSchedule(startAt: start, endAt: start.add(Duration(minutes: minutes)));
    final now = ist(2024, 2, 20, 12);

    test('next week from Feb 29 (leap) and from Feb 28 (non-leap)', () {
      final a = applyPostponeRule(
        PostponeRule.nextWeek,
        at(ist(2024, 2, 29, 10)),
        nowUtc: now,
      );
      expect(a.startAt, ist(2024, 3, 7, 10));
      final b = applyPostponeRule(
        PostponeRule.nextWeek,
        at(ist(2025, 2, 28, 10)),
        nowUtc: now,
      );
      expect(b.startAt, ist(2025, 3, 7, 10));
    });

    test('+1 hour across midnight, month end and New Year keeps the length', () {
      final r = applyPostponeRule(
        PostponeRule.plusOneHour,
        at(ist(2023, 12, 31, 23, 30), minutes: 45),
        nowUtc: now,
      );
      expect(r.startAt, ist(2024, 1, 1, 0, 30));
      expect(r.endAt, ist(2024, 1, 1, 1, 15));
    });

    test('morning rule on Dec 31 evening goes to Jan 1 09:00', () {
      final r = applyPostponeRule(
        PostponeRule.morning,
        at(ist(2023, 12, 31, 20)),
        nowUtc: now,
      );
      expect(r.startAt, ist(2024, 1, 1, 9));
    });

    test('next Monday morning from Sunday Dec 31 and from Monday Jan 1', () {
      final fromSunday = applyPostponeRule(
        PostponeRule.nextMondayMorning,
        at(ist(2023, 12, 31, 10)),
        nowUtc: now,
      );
      expect(fromSunday.startAt, ist(2024, 1, 1, 9));
      final fromMonday = applyPostponeRule(
        PostponeRule.nextMondayMorning,
        at(ist(2024, 1, 1, 10)),
        nowUtc: now,
      );
      expect(fromMonday.startAt, ist(2024, 1, 8, 9));
    });

    test('working morning skips the weekend over Feb 29 2028 (Tuesday)', () {
      // Friday 2028-02-25 evening -> Monday 2028-02-28.
      final r = applyPostponeRule(
        PostponeRule.workingMorning,
        at(ist(2028, 2, 25, 20)),
        nowUtc: now,
      );
      expect(r.startAt, ist(2028, 2, 28, 9));
    });

    test('there is no +1 month / +1 year postpone rule (nothing to clamp)', () {
      expect(
        PostponeRule.values.where(
          (r) => r.name.contains('onth') && r != PostponeRule.workingMorning
              && r != PostponeRule.nextMondayMorning,
        ),
        isEmpty,
      );
    });

    test('an action with no schedule postpones from "now"', () {
      final r = applyPostponeRule(
        PostponeRule.plusOneHour,
        const ActionSchedule(),
        nowUtc: ist(2024, 12, 31, 23, 30),
      );
      expect(r.startAt, ist(2025, 1, 1, 0, 30));
      expect(r.endAt, isNull);
    });
  });

  group('growth / treemap windows', () {
    test('week window is the last 7 local days including today, across Feb 29', () {
      expect(
        windowStart(ist(2024, 3, 3, 15), MetricWindow.week),
        ist(2024, 2, 26),
      );
      expect(
        windowStart(ist(2024, 3, 6, 0, 30), MetricWindow.week),
        ist(2024, 2, 29),
      );
    });

    test('month window clamps the day to the target month length', () {
      expect(
        windowStart(ist(2025, 3, 31, 12), MetricWindow.month),
        ist(2025, 2, 28),
      );
      expect(
        windowStart(ist(2024, 3, 31, 12), MetricWindow.month),
        ist(2024, 2, 29),
      );
      expect(
        windowStart(ist(2024, 1, 31, 12), MetricWindow.month),
        ist(2023, 12, 31),
      );
    });

    test('year and 5-year windows on a leap day clamp to Feb 28', () {
      final leapDay = ist(2024, 2, 29, 12);
      expect(windowStart(leapDay, MetricWindow.year), ist(2023, 2, 28));
      expect(windowStart(leapDay, MetricWindow.fiveYears), ist(2019, 2, 28));
      // 2028 -> 2023 and 2027 are both non-leap; 2032 -> 2027.
      expect(
        windowStart(ist(2028, 2, 29, 12), MetricWindow.fiveYears),
        ist(2023, 2, 28),
      );
    });

    test('a window that starts in the previous year', () {
      expect(
        windowStart(ist(2025, 1, 2, 12), MetricWindow.week),
        ist(2024, 12, 27),
      );
      expect(
        windowStart(ist(2025, 1, 15, 12), MetricWindow.month),
        ist(2024, 12, 15),
      );
    });

    test('just before and just after local midnight pick different days', () {
      // 23:59:59 Istanbul = 20:59:59Z; 00:00:00 = 21:00:00Z.
      final before = DateTime.utc(2024, 2, 28, 20, 59, 59);
      final after = DateTime.utc(2024, 2, 28, 21);
      expect(localDayStart(before), ist(2024, 2, 28));
      expect(localDayStart(after), ist(2024, 2, 29));
    });
  });

  group('budget periods', () {
    test('a 3 month period across the year boundary', () {
      final p = BudgetPeriod(asOf: ist(2025, 12, 15, 12));
      expect(p.factStart, ist(2025, 9, 15, 12));
      expect(p.planEnd, ist(2026, 3, 15, 12));
    });

    test('month end clamping: Nov 30 + 3 months, Jan 31 + 1 month', () {
      expect(
        BudgetPeriod(asOf: ist(2023, 11, 30, 12)).planEnd,
        ist(2024, 2, 29, 12),
      );
      expect(
        BudgetPeriod(asOf: ist(2024, 11, 30, 12)).planEnd,
        ist(2025, 2, 28, 12),
      );
      expect(
        BudgetPeriod(asOf: ist(2025, 1, 31, 12), months: 1).planEnd,
        ist(2025, 2, 28, 12),
      );
      expect(
        BudgetPeriod(asOf: ist(2025, 3, 31, 12), months: 12).factStart,
        ist(2024, 3, 31, 12),
      );
    });

    test('months between Dec 1 and Jan 1 is exactly one, Feb 29 -> Mar 29 too', () {
      expect(monthsBetween(ist(2025, 12, 1), ist(2026, 1, 1)), 1.0);
      expect(monthsBetween(ist(2024, 2, 29), ist(2024, 3, 29)), 1.0);
      expect(monthsBetween(ist(2024, 1, 1), ist(2025, 1, 1)), 12.0);
      expect(monthsBetween(ist(2025, 1, 1), ist(2024, 1, 1)), 0);
    });

    test('a category active across Dec 31 counts both years', () {
      expect(
        activeMonths(
          ist(2025, 11, 1),
          ist(2026, 2, 1),
          ist(2025, 6, 1),
          ist(2026, 6, 1),
        ),
        3.0,
      );
    });

    test('calendarAddMonths is reversible in the clamping direction only', () {
      final jan31 = ist(2025, 1, 31, 9);
      final feb = calendarAddMonths(jan31, 1);
      expect(feb, ist(2025, 2, 28, 9));
      // Documented: Jan 31 -> Feb 28 -> Mar 28 (does not return to 31).
      expect(calendarAddMonths(feb, 1), ist(2025, 3, 28, 9));
      // Huge shifts do not throw.
      expect(calendarAddMonths(jan31, 12 * 500), ist(2525, 1, 31, 9));
    });
  });

  group('week handling (Monday start, Istanbul)', () {
    test('This week on Dec 31 and Jan 1 spans the year boundary', () {
      // Tue 2024-12-31
      var r = DatePreset.thisWeek.resolve(ist(2024, 12, 31, 12));
      expect(r.from, ist(2024, 12, 30));
      expect(r.until, ist(2025, 1, 5));
      // Wed 2025-01-01
      r = DatePreset.thisWeek.resolve(ist(2025, 1, 1, 12));
      expect(r.from, ist(2024, 12, 30));
      expect(r.until, ist(2025, 1, 5));
    });

    test('Sunday belongs to the week that started on the previous Monday', () {
      // Sun 2023-12-31
      final r = DatePreset.thisWeek.resolve(ist(2023, 12, 31, 23, 59));
      expect(r.from, ist(2023, 12, 25));
      expect(r.until, ist(2023, 12, 31));
      final next = DatePreset.nextWeek.resolve(ist(2023, 12, 31, 23, 59));
      expect(next.from, ist(2024, 1, 1));
    });

    test('rest of the week on its last day is empty; last week over Feb 29', () {
      final sunday = DatePreset.weekRest.resolve(ist(2024, 3, 3, 10));
      expect(sunday.from.isAfter(sunday.until), isTrue);
      final last = DatePreset.lastWeek.resolve(ist(2024, 3, 6, 10));
      expect(last.from, ist(2024, 2, 26));
      expect(last.until, ist(2024, 3, 3));
    });

    test('month and year presets in Feb of a leap year and on Dec 31', () {
      expect(
        DatePreset.thisMonth.resolve(ist(2024, 2, 10)).until,
        ist(2024, 2, 29),
      );
      expect(
        DatePreset.thisMonth.resolve(ist(2025, 2, 10)).until,
        ist(2025, 2, 28),
      );
      final y = DatePreset.yearRest.resolve(ist(2024, 12, 31, 10));
      expect(y.from.isAfter(y.until), isTrue);
      expect(DatePreset.nextYear.resolve(ist(2024, 12, 31, 10)).from,
          ist(2025, 1, 1));
    });
  });

  group('durations', () {
    test('mixed units: minutes, hours, days, weeks', () {
      final start = ist(2024, 2, 27, 9);
      expect(
        computeActionDuration(
          startAt: start,
          endAt: start.add(const Duration(days: 7, hours: 3, minutes: 5)),
        ),
        const Duration(days: 7, hours: 3, minutes: 5),
      );
      expect(formatDuration(const Duration(days: 7, hours: 3, minutes: 5)),
          '7 days 3 hours');
      expect(formatDuration(const Duration(days: 14)), '14 days');
      expect(formatDuration(const Duration(hours: 25, minutes: 1)),
          '1 day 1 hour');
      expect(formatDuration(const Duration(minutes: 90, seconds: 30)),
          '1 hour 30 min');
      expect(formatDuration(const Duration(seconds: 59)), '59 sec');
      expect(formatDuration(const Duration(minutes: -5)), '0 sec');
    });

    test('a 10-year duration is kept and formatted without overflow', () {
      final start = ist(2020, 1, 1);
      final end = ist(2030, 1, 1);
      final d = computeActionDuration(startAt: start, endAt: end);
      expect(d.inDays, 3653);
      expect(formatDuration(d), '3653 days');
    });

    test('end before start falls back to the legacy estimate, then 60 min', () {
      final start = ist(2024, 1, 1, 10);
      final end = ist(2024, 1, 1, 9);
      expect(
        computeActionDuration(
          startAt: start,
          endAt: end,
          legacyEstimatedMinutes: 25,
        ),
        const Duration(minutes: 25),
      );
      expect(
        computeActionDuration(startAt: start, endAt: end),
        defaultActionDuration,
      );
      expect(
        computeActionDuration(
          startAt: start,
          endAt: end,
          legacyEstimatedMinutes: -5,
        ),
        defaultActionDuration,
      );
    });

    test('an action across midnight, month end and New Year keeps its length', () {
      final start = ist(2023, 12, 31, 23);
      final end = ist(2024, 1, 1, 2);
      expect(
        computeActionDuration(startAt: start, endAt: end),
        const Duration(hours: 3),
      );
    });
  });

  group('time codec extremes', () {
    test('1970, 2038, 2100, year 1 and 9999 round-trip with fixed width', () {
      for (final d in [
        DateTime.utc(1970),
        DateTime.utc(2038, 1, 19, 3, 14, 8),
        DateTime.utc(2100, 12, 31, 23, 59, 59, 999, 999),
        DateTime.utc(1, 1, 1),
        DateTime.utc(9999, 12, 31, 23, 59, 59, 999, 999),
      ]) {
        final text = dateTimeToDb(d)!;
        expect(text.length, 27, reason: text);
        expect(dateTimeFromDb(text), d);
      }
    });

    test('text order equals chronological order across the extremes', () {
      final ds = [
        DateTime.utc(1),
        DateTime.utc(1969, 12, 31, 23, 59, 59),
        DateTime.utc(1970),
        DateTime.utc(2000, 2, 29),
        DateTime.utc(2038, 1, 19, 3, 14, 7),
        DateTime.utc(2038, 1, 19, 3, 14, 8),
        DateTime.utc(2100),
        DateTime.utc(9999, 12, 31),
      ];
      final texts = ds.map(dateTimeToDb).toList();
      expect([...texts]..sort(), texts);
    });

    test('a local zone value converts to the same UTC text', () {
      final z = tz.TZDateTime(
        tz.getLocation('America/New_York'),
        2024,
        3,
        10,
        3,
      );
      expect(dateTimeToDb(z), dateTimeToDb(z.toUtc()));
    });

    test('years outside 0001..9999 keep the fixed width (clamped)', () {
      for (final d in [DateTime.utc(10000), DateTime.utc(275000), DateTime.utc(0)]) {
        final text = dateTimeToDb(d)!;
        expect(text.length, 27, reason: text);
        expect(RegExp(r'^\d{4}-').hasMatch(text), isTrue, reason: text);
        expect(DateTime.parse(text).isUtc, isTrue);
      }
      expect(
        dateTimeToDb(DateTime.utc(10000))!.compareTo(
          dateTimeToDb(DateTime.utc(9999, 12, 31))!,
        ),
        greaterThanOrEqualTo(0),
      );
    });
  });

  group('sync clock', () {
    late AppDatabase db;
    late ActionService service;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      service = ActionService(db);
    });
    tearDown(() => db.close());

    Future<String> hlcOf(String id) async {
      final rows = await db
          .customSelect(
            "SELECT hlc FROM sync_versions WHERE tbl='actions' AND row_id=?",
            variables: [Variable.withString(id)],
          )
          .get();
      return rows.single.read<String>('hlc');
    }

    test('stamps never go down when the wall clock goes backwards', () async {
      final a = await service.createAction(name: 'a');
      final first = await hlcOf(a);
      // The device clock jumps back a day: the stored high-water mark is now
      // a day ahead of "now".
      final future = DateTime.now().toUtc().add(const Duration(days: 1));
      await db.customStatement(
        'UPDATE sync_clock SET last_wall = ?, counter = 0 WHERE id = 1',
        [_wall(future)],
      );
      final stamps = <String>[first];
      for (var i = 0; i < 5; i++) {
        final id = await service.createAction(name: 'b$i');
        stamps.add(await hlcOf(id));
      }
      for (var i = 1; i < stamps.length; i++) {
        expect(compareHlc(stamps[i], stamps[i - 1]), greaterThan(0),
            reason: '${stamps[i - 1]} -> ${stamps[i]}');
      }
      // The wall part stays at the high-water mark, only the counter moves.
      expect(stamps.last.substring(0, 24), _wall(future));
    });

    test('the counter rolling past ffff still orders after the previous stamp', () async {
      final future = DateTime.now().toUtc().add(const Duration(hours: 2));
      await db.customStatement(
        'UPDATE sync_clock SET last_wall = ?, counter = 65534 WHERE id = 1',
        [_wall(future)],
      );
      final stamps = <String>[];
      for (var i = 0; i < 4; i++) {
        stamps.add(await hlcOf(await service.createAction(name: 'n$i')));
      }
      for (var i = 1; i < stamps.length; i++) {
        expect(compareHlc(stamps[i], stamps[i - 1]), greaterThan(0),
            reason: '${stamps[i - 1]} -> ${stamps[i]}');
      }
      for (final s in stamps) {
        expect(validateChange(_change(s), now: DateTime.now()), isNull,
            reason: s);
      }
    });
  });

  group('validateChange stamp boundary', () {
    final now = DateTime.utc(2026, 10, 17, 12);

    test('exactly 24 h ahead is accepted, one millisecond more is refused', () {
      final edge = now.add(maxStampFuture);
      expect(validateChange(_change(_stampAt(edge)), now: now), isNull);
      expect(
        validateChange(
          _change(_stampAt(edge.add(const Duration(milliseconds: 1)))),
          now: now,
        ),
        'clock stamp in the future',
      );
      expect(
        validateChange(
          _change(_stampAt(edge.subtract(const Duration(milliseconds: 1)))),
          now: now,
        ),
        isNull,
      );
    });

    test('a stamp far in the past, 1970 and year 2100 behave', () {
      expect(validateChange(_change(_stampAt(DateTime.utc(1970))), now: now),
          isNull);
      expect(validateChange(_change(_stampAt(DateTime.utc(2100))), now: now),
          'clock stamp in the future');
      // A stamp with an impossible date is refused, not thrown on.
      expect(
        validateChange(
          _change('2026-13-45T25:61:61.000Z-0001-devA'),
          now: now,
        ),
        'clock stamp',
      );
      expect(
        validateChange(
          _change('2026-02-30T10:00:00.000Z-0001-devA'),
          now: now,
        ),
        isNotNull,
        reason: 'Feb 30 is not a date',
      );
    });

    test('a stamp on Feb 29 of a leap year is accepted, of a plain year refused', () {
      expect(
        validateChange(_change('2024-02-29T10:00:00.000Z-0001-devA'), now: now),
        isNull,
      );
      expect(
        validateChange(_change('2025-02-29T10:00:00.000Z-0001-devA'), now: now),
        isNotNull,
      );
    });

    test('the local clock may be set back: "now" before every stamp refuses far ones', () {
      final skewed = DateTime.utc(2020);
      expect(
        validateChange(_change(_stampAt(DateTime.utc(2026, 10, 10))), now: skewed),
        'clock stamp in the future',
      );
    });
  });

  group('time zone handling', () {
    test('the rules are fixed to Istanbul: no DST shift, UTC+3 all year', () {
      final loc = tz.getLocation('Europe/Istanbul');
      for (final m in [1, 3, 6, 10, 12]) {
        expect(tz.TZDateTime(loc, 2024, m, 15, 12).timeZoneOffset,
            const Duration(hours: 3));
      }
      // So +1 day in wall-clock and in 24 h blocks agree.
      expect(calendarAddDays(ist(2024, 3, 30), 1), ist(2024, 3, 31));
      expect(calendarAddDays(ist(2024, 10, 26), 1), ist(2024, 10, 27));
    });

    test('plan instants on the dates DST zones switch are plain', () {
      // 2024-03-10 (US spring forward) and 2024-10-27 (EU fall back).
      final item = PlanItemData(
        id: 'c',
        name: 'Daily',
        kind: PlanKind.cycle,
        startDate: planDate(2024, 3, 9),
        forever: true,
        cycle: const CycleRule(
          cycleDays: 1,
          occurrences: [
            CycleOccurrence(day: 0, startMin: 2 * 60 + 30, durationMin: 60),
          ],
        ),
      );
      for (final o in occurrencesInRange(
        item,
        planDate(2024, 3, 9),
        planDate(2024, 3, 11),
      )) {
        expect(o.endUtc.difference(o.startUtc), const Duration(hours: 1));
        expect(o.startUtc.hour, 23);
      }
      final p = applyPostponeRule(
        PostponeRule.plusOneHour,
        ActionSchedule(
          startAt: ist(2024, 10, 27, 1, 30),
          endAt: ist(2024, 10, 27, 2, 30),
        ),
        nowUtc: ist(2024, 10, 20),
      );
      expect(p.startAt, ist(2024, 10, 27, 2, 30));
    });

    test('calendar helpers accept TZDateTime of other zones as input', () {
      final ny = tz.TZDateTime(
        tz.getLocation('America/New_York'),
        2024,
        3,
        10,
        3,
      );
      // A DST-zone input is just an instant for them.
      expect(localDayStart(ny), ist(2024, 3, 10));
      expect(() => windowStart(ny, MetricWindow.month), returnsNormally);
      expect(
        () => applyPostponeRule(
          PostponeRule.morning,
          ActionSchedule(startAt: ny, endAt: ny.add(const Duration(hours: 1))),
          nowUtc: ny,
        ),
        returnsNormally,
      );
      final london = tz.TZDateTime(
        tz.getLocation('Europe/London'),
        2024,
        3,
        31,
        1,
        30, // does not exist: clocks jump 01:00 -> 02:00
      );
      expect(() => dateTimeToDb(london), returnsNormally);
    });
  });
}

String _wall(DateTime utc) {
  final t = dateTimeToDb(utc)!; // yyyy-MM-ddTHH:mm:ss.ffffffZ
  return '${t.substring(0, 23)}Z';
}

String _stampAt(DateTime utc) => '${_wall(utc)}-0001-devA';

SyncChange _change(String hlc) => SyncChange(
  table: 'actions',
  rowId: 'row1',
  hlc: hlc,
  origin: 'devA',
  deleted: false,
  data: {'id': 'row1', 'name': 'x'},
  seq: 1,
);
