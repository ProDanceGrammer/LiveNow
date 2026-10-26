import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/settings.dart';
import 'package:livenow/core/zone_info.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/calendar_zone_service.dart';
import 'package:livenow/domain/plan_rules.dart';
import 'package:livenow/domain/postpone_rules.dart';

/// Timezones: a plan row read in its own zone, the zone helpers (flag, city,
/// offset), the app's own zone setting and the extra calendar zones.
void main() {
  setUpAll(initPostponeTimeZoneData);

  // The app's own zone in these tests is Europe/Istanbul (UTC+3 all year).
  DateTime d(int y, int m, int day) => planDate(y, m, day);

  PlanItemData daily(CycleOccurrence row, {DateTime? start}) => PlanItemData(
    id: 'p',
    name: 'Call',
    kind: PlanKind.cycle,
    startDate: start ?? d(2026, 10, 19),
    forever: true,
    cycle: CycleRule(cycleDays: 1, occurrences: [row]),
  );

  group('a plan row in its own zone', () {
    test('09:00 in New York follows New York daylight saving', () {
      final item = daily(
        const CycleOccurrence(day: 0, startMin: 540, tz: 'America/New_York'),
      );
      final o = occurrencesInRange(item, d(2026, 10, 30), d(2026, 11, 3));
      String hhmm(DateTime u) => u.toIso8601String().substring(11, 16);
      final byDate = {for (final x in o) x.key.split('#').first: hhmm(x.startUtc)};
      // EDT (UTC-4) until 1 Nov, then EST (UTC-5).
      expect(byDate['2026-10-30'], '13:00');
      expect(byDate['2026-10-31'], '13:00');
      expect(byDate['2026-11-02'], '14:00');
    });

    test('a row without a zone is read in the app\'s own zone', () {
      final item = daily(const CycleOccurrence(day: 0, startMin: 540));
      final o = occurrencesInRange(item, d(2026, 10, 20), d(2026, 10, 20)).single;
      expect(o.startUtc, DateTime.utc(2026, 10, 20, 6)); // 09:00 +03:00
      expect(identical(o.displayed(), o), isTrue);
    });

    test('displayed() puts it where it falls in the app\'s zone', () {
      final item = daily(
        const CycleOccurrence(day: 0, startMin: 540, tz: 'America/New_York'),
      );
      final o = occurrencesInRange(item, d(2026, 10, 20), d(2026, 10, 20)).single;
      final shown = o.displayed();
      expect(shown.date, d(2026, 10, 20));
      expect(shown.startMin, 16 * 60); // 13:00Z = 16:00 in Istanbul
      expect(shown.key, o.key); // identity stays that of the row
      expect(shown.tz, 'America/New_York');
    });

    test('a row that lands on the next date here keeps its own key', () {
      // 20:00 in Los Angeles on 19 Oct (PDT, UTC-7) = 06:00 on 20 Oct here.
      final item = daily(
        const CycleOccurrence(day: 0, startMin: 20 * 60, tz: 'America/Los_Angeles'),
      );
      final o = occurrencesInRange(item, d(2026, 10, 19), d(2026, 10, 19)).single;
      expect(o.key, '2026-10-19#0');
      final shown = o.displayed();
      expect(shown.date, d(2026, 10, 20));
      expect(shown.startMin, 6 * 60);
      // Dragging it to 06:30 here is 20:30 in Los Angeles.
      expect(o.rowMinutesFor(shown.date, 6 * 60 + 30), 20 * 60 + 30);
    });

    test('an unknown zone name falls back to the app\'s own zone', () {
      final item = daily(
        const CycleOccurrence(day: 0, startMin: 540, tz: 'Mars/Olympus'),
      );
      final o = occurrencesInRange(item, d(2026, 10, 20), d(2026, 10, 20)).single;
      expect(o.startUtc, DateTime.utc(2026, 10, 20, 6));
    });

    test('the zone survives the stored JSON; none stores nothing', () {
      const withZone = CycleOccurrence(day: 1, startMin: 60, tz: 'Asia/Tokyo');
      expect(withZone.toJson()['tz'], 'Asia/Tokyo');
      expect(CycleOccurrence.fromJson(withZone.toJson()).tz, 'Asia/Tokyo');
      expect(const CycleOccurrence(day: 1, startMin: 60).toJson(), isNot(contains('tz')));

      const m = MonthlyRule(startMin: 600, tz: 'Europe/London');
      expect(MonthlyRule.fromJson(m.toJson()).tz, 'Europe/London');
    });

    test('a monthly rule reads its time in its zone', () {
      final item = PlanItemData(
        id: 'm',
        name: 'Report',
        kind: PlanKind.monthly,
        startDate: d(2026, 1, 1),
        monthly: const MonthlyRule(day: 15, startMin: 600, tz: 'Asia/Tokyo'),
      );
      final o = occurrencesInRange(item, d(2026, 10, 1), d(2026, 10, 31)).single;
      expect(o.startUtc, DateTime.utc(2026, 10, 15, 1)); // 10:00 +09:00
    });

    test('the summary names the city of a row\'s own zone', () {
      final item = daily(
        const CycleOccurrence(day: 0, startMin: 540, tz: 'America/New_York'),
      );
      expect(describePlan(item), 'Daily: 09:00 (New York)');
    });
  });

  group('zone helpers', () {
    test('flag and city', () {
      expect(zoneFlag('America/New_York'), '🇺🇸');
      expect(zoneFlag('Europe/Kyiv'), '🇺🇦');
      expect(zoneFlag('Mars/Olympus'), '');
      expect(zoneCity('America/Argentina/Buenos_Aires'), 'Buenos Aires');
      expect(zoneDefaultLabel('Europe/Kyiv'), '🇺🇦 Kyiv');
      expect(zoneDefaultLabel('Mars/Olympus'), 'Olympus');
    });

    test('offset at an instant, with daylight saving', () {
      final summer = DateTime.utc(2026, 7, 1);
      final winter = DateTime.utc(2026, 12, 1);
      expect(formatZoneOffset(zoneOffset('America/New_York', summer)), 'UTC-4');
      expect(formatZoneOffset(zoneOffset('America/New_York', winter)), 'UTC-5');
      expect(formatZoneOffset(zoneOffset('Asia/Kolkata', winter)), 'UTC+5:30');
      expect(formatZoneOffset(zoneOffset('Europe/Istanbul', winter)), 'UTC+3');
    });
  });

  group('the app\'s own zone', () {
    test('an unknown name is refused and changes nothing', () {
      final before = AppSettings.timeZoneName;
      expect(AppSettings.setTimeZoneName('Mars/Olympus'), isFalse);
      expect(AppSettings.timeZoneName, before);
    });

    test('a known name switches the zone the day arithmetic uses', () {
      final before = AppSettings.timeZoneName;
      addTearDown(() => AppSettings.setTimeZoneName(before));
      expect(AppSettings.setTimeZoneName('America/New_York'), isTrue);
      // 09:00 local is now 13:00Z (EDT) instead of 06:00Z.
      expect(planInstant(d(2026, 10, 20), 540), DateTime.utc(2026, 10, 20, 13));
    });
  });

  group('CalendarZoneService', () {
    late AppDatabase db;
    late CalendarZoneService service;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      service = CalendarZoneService(db);
    });
    tearDown(() => db.close());

    Future<List<CalendarZone>> rows() => service.watch().first;

    test('adds with the default label, in order, once per zone', () async {
      final a = await service.add('America/New_York');
      expect(await service.add('America/New_York'), a, reason: 'no duplicate');
      await service.add('Asia/Tokyo', label: '  Tokyo office ');
      final list = await rows();
      expect(list.map((z) => z.tz), ['America/New_York', 'Asia/Tokyo']);
      expect(list.map((z) => z.label), ['🇺🇸 New York', 'Tokyo office']);
    });

    test('at most three', () async {
      await service.add('America/New_York');
      await service.add('Asia/Tokyo');
      await service.add('Europe/London');
      expect(
        () => service.add('Australia/Sydney'),
        throwsA(isA<CalendarZoneLimitException>()),
      );
    });

    test('rename, a blank name restores the default, remove + restore', () async {
      final id = await service.add('Asia/Tokyo');
      await service.rename(id, '🇯🇵 HQ');
      expect((await rows()).single.label, '🇯🇵 HQ');
      await service.rename(id, '   ');
      expect((await rows()).single.label, '🇯🇵 Tokyo');

      final gone = await service.remove(id);
      expect(await rows(), isEmpty);
      await service.restore(gone!);
      expect((await rows()).single.id, id);
    });
  });
}
