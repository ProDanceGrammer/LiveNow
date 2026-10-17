import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/date_range_filter.dart';
import 'package:livenow/domain/postpone_rules.dart';

void main() {
  setUpAll(initPostponeTimeZoneData);

  // Istanbul is UTC+3 all year: local midnight = 21:00 UTC the day before.
  DateTime day(int d) => DateRangeFilter.dayStart(DateTime(2026, 10, d));

  test('dayStart is Istanbul midnight as UTC; dayOf reads it back', () {
    expect(day(12), DateTime.utc(2026, 10, 11, 21));
    expect(DateRangeFilter.dayOf(day(12)), DateTime(2026, 10, 12));
  });

  test('both ends are inclusive and count whole local days', () {
    final r = DateRangeFilter(from: day(12), until: day(13));
    expect(r.active, isTrue);
    expect(
      r.contains(DateTime.utc(2026, 10, 11, 20, 59)),
      isFalse,
    ); // 23:59 on the 11th
    expect(
      r.contains(DateTime.utc(2026, 10, 11, 21)),
      isTrue,
    ); // 00:00 on the 12th
    expect(
      r.contains(DateTime.utc(2026, 10, 13, 20, 59)),
      isTrue,
    ); // 23:59 on the 13th
    expect(
      r.contains(DateTime.utc(2026, 10, 13, 21)),
      isFalse,
    ); // 00:00 on the 14th
  });

  test('open ends: only from, only until, none', () {
    expect(DateRangeFilter(from: day(12)).contains(DateTime.utc(2030)), isTrue);
    expect(
      DateRangeFilter(from: day(12)).contains(DateTime.utc(2020)),
      isFalse,
    );
    expect(
      DateRangeFilter(until: day(12)).contains(DateTime.utc(2020)),
      isTrue,
    );
    expect(
      DateRangeFilter(until: day(12)).contains(DateTime.utc(2030)),
      isFalse,
    );
    const none = DateRangeFilter();
    expect(none.active, isFalse);
    expect(none.contains(DateTime.utc(1999)), isTrue);
  });

  test('from after until is empty; copyWith can clear an end', () {
    expect(DateRangeFilter(from: day(14), until: day(12)).isEmpty, isTrue);
    final r = DateRangeFilter(from: day(12), until: day(13));
    expect(r.copyWith(clearUntil: true).until, isNull);
    expect(r.copyWith(clearFrom: true).from, isNull);
    expect(r, DateRangeFilter(from: day(12), until: day(13)));
  });

  // ---- quick choices ---------------------------------------------------------

  /// Istanbul wall-clock [h]:[m] on y-m-d as the UTC instant.
  DateTime at(int y, int m, int d, [int h = 12, int min = 0]) =>
      DateTime.utc(y, m, d, h - 3, min);

  String fmt(DateTime utc) {
    final d = DateRangeFilter.dayOf(utc);
    String p(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)}';
  }

  /// "first..last" of [p] when today is [now].
  String range(DatePreset p, DateTime now) {
    final r = p.resolve(now);
    return '${fmt(r.from)}..${fmt(r.until)}';
  }

  group('DatePreset', () {
    test('Wednesday 21 Oct 2026: every choice', () {
      final now = at(2026, 10, 21);
      expect(<DatePreset, String>{
        for (final p in DatePreset.values) p: range(p, now),
      }, {
        DatePreset.yesterday: '2026-10-20..2026-10-20',
        DatePreset.today: '2026-10-21..2026-10-21',
        DatePreset.tomorrow: '2026-10-22..2026-10-22',
        DatePreset.lastWeek: '2026-10-12..2026-10-18',
        DatePreset.weekSoFar: '2026-10-19..2026-10-21',
        DatePreset.weekRest: '2026-10-22..2026-10-25',
        DatePreset.thisWeek: '2026-10-19..2026-10-25',
        DatePreset.nextWeek: '2026-10-26..2026-11-01',
        DatePreset.lastMonth: '2026-09-01..2026-09-30',
        DatePreset.monthSoFar: '2026-10-01..2026-10-21',
        DatePreset.monthRest: '2026-10-22..2026-10-31',
        DatePreset.thisMonth: '2026-10-01..2026-10-31',
        DatePreset.nextMonth: '2026-11-01..2026-11-30',
        DatePreset.lastYear: '2025-01-01..2025-12-31',
        DatePreset.yearSoFar: '2026-01-01..2026-10-21',
        DatePreset.yearRest: '2026-10-22..2026-12-31',
        DatePreset.thisYear: '2026-01-01..2026-12-31',
        DatePreset.nextYear: '2027-01-01..2027-12-31',
      });
    });

    test('there are 18 choices in four groups', () {
      expect(DatePreset.values, hasLength(18));
      expect({for (final p in DatePreset.values) p.group},
          {'Day', 'Week', 'Month', 'Year'});
      expect(DatePreset.values.map((p) => p.label).toSet(), hasLength(18));
    });

    test('on a Monday the week so far is that one day', () {
      final now = at(2026, 10, 19);
      expect(range(DatePreset.weekSoFar, now), '2026-10-19..2026-10-19');
      expect(range(DatePreset.weekRest, now), '2026-10-20..2026-10-25');
      expect(range(DatePreset.lastWeek, now), '2026-10-12..2026-10-18');
    });

    test('on a Sunday the rest of the week is empty, the next week starts tomorrow', () {
      final now = at(2026, 10, 25);
      expect(range(DatePreset.weekSoFar, now), '2026-10-19..2026-10-25');
      expect(range(DatePreset.weekRest, now), '2026-10-26..2026-10-25');
      expect(DatePreset.weekRest.resolve(now).from.isAfter(DatePreset.weekRest.resolve(now).until), isTrue);
      expect(range(DatePreset.nextWeek, now), '2026-10-26..2026-11-01');
    });

    test('the last day of a month: the rest is empty, 30- and 31-day months', () {
      final oct31 = at(2026, 10, 31);
      expect(range(DatePreset.monthRest, oct31), '2026-11-01..2026-10-31');
      expect(range(DatePreset.nextMonth, oct31), '2026-11-01..2026-11-30');
      expect(range(DatePreset.lastMonth, oct31), '2026-09-01..2026-09-30');
      // Back from a 31-day month to a 30-day one, and the other way round.
      expect(range(DatePreset.lastMonth, at(2026, 5, 31)), '2026-04-01..2026-04-30');
      expect(range(DatePreset.nextMonth, at(2026, 5, 31)), '2026-06-01..2026-06-30');
      expect(range(DatePreset.nextMonth, at(2026, 6, 30)), '2026-07-01..2026-07-31');
    });

    test('February: a normal year and a leap year', () {
      expect(range(DatePreset.nextMonth, at(2027, 1, 31)), '2027-02-01..2027-02-28');
      expect(range(DatePreset.nextMonth, at(2028, 1, 31)), '2028-02-01..2028-02-29');
      expect(range(DatePreset.lastMonth, at(2026, 3, 31)), '2026-02-01..2026-02-28');
      expect(range(DatePreset.thisMonth, at(2028, 2, 10)), '2028-02-01..2028-02-29');
    });

    test('around New Year: weeks and months cross the year, the rest of the year is empty', () {
      final dec31 = at(2026, 12, 31); // a Thursday
      expect(range(DatePreset.thisWeek, dec31), '2026-12-28..2027-01-03');
      expect(range(DatePreset.nextWeek, dec31), '2027-01-04..2027-01-10');
      expect(range(DatePreset.nextMonth, dec31), '2027-01-01..2027-01-31');
      expect(range(DatePreset.lastMonth, dec31), '2026-11-01..2026-11-30');
      expect(range(DatePreset.yearRest, dec31), '2027-01-01..2026-12-31');
      expect(range(DatePreset.nextYear, dec31), '2027-01-01..2027-12-31');

      final jan1 = at(2026, 1, 1);
      expect(range(DatePreset.lastMonth, jan1), '2025-12-01..2025-12-31');
      expect(range(DatePreset.lastYear, jan1), '2025-01-01..2025-12-31');
      expect(range(DatePreset.yesterday, jan1), '2025-12-31..2025-12-31');
      expect(range(DatePreset.lastWeek, jan1), '2025-12-22..2025-12-28');
    });

    test('the Istanbul day decides, not the UTC date', () {
      // 22:30 UTC on 21 Oct is 01:30 on 22 Oct in Istanbul.
      final now = DateTime.utc(2026, 10, 21, 22, 30);
      expect(range(DatePreset.today, now), '2026-10-22..2026-10-22');
      expect(range(DatePreset.yesterday, now), '2026-10-21..2026-10-21');
      // 20:59 UTC is still 23:59 on the 21st.
      expect(range(DatePreset.today, DateTime.utc(2026, 10, 21, 20, 59)), '2026-10-21..2026-10-21');
    });

    test('every choice gives local midnights as plain UTC instants', () {
      final now = at(2026, 10, 21);
      for (final p in DatePreset.values) {
        final r = p.resolve(now);
        for (final d in [r.from, r.until]) {
          expect(d.isUtc, isTrue, reason: p.name);
          expect(d.hour, 21, reason: p.name); // 00:00 Istanbul
          expect(d.minute, 0, reason: p.name);
        }
      }
    });
  });

  group('DateRangeFilter with a quick choice', () {
    final wednesday = at(2026, 10, 21);

    test('is active, resolves against the given day, and contains whole days', () {
      const f = DateRangeFilter(preset: DatePreset.thisWeek);
      expect(f.active, isTrue);
      final r = f.resolved(wednesday);
      expect(r.preset, isNull);
      expect(fmt(r.from!), '2026-10-19');
      expect(fmt(r.until!), '2026-10-25');
      expect(f.contains(at(2026, 10, 19, 0, 0), nowUtc: wednesday), isTrue);
      expect(f.contains(at(2026, 10, 25, 23, 59), nowUtc: wednesday), isTrue);
      expect(f.contains(at(2026, 10, 18, 23, 59), nowUtc: wednesday), isFalse);
      expect(f.contains(at(2026, 10, 26, 0, 0), nowUtc: wednesday), isFalse);
    });

    test('means a different week a week later', () {
      const f = DateRangeFilter(preset: DatePreset.lastWeek);
      final a = f.resolved(wednesday);
      final b = f.resolved(wednesday.add(const Duration(days: 7)));
      expect(fmt(a.from!), '2026-10-12');
      expect(fmt(b.from!), '2026-10-19');
    });

    test('an empty "rest of" on the last day matches nothing', () {
      const f = DateRangeFilter(preset: DatePreset.weekRest);
      final sunday = at(2026, 10, 25);
      expect(f.resolved(sunday).isEmpty, isTrue);
      expect(f.contains(at(2026, 10, 25), nowUtc: sunday), isFalse);
      expect(f.contains(at(2026, 10, 26), nowUtc: sunday), isFalse);
    });

    test('equality includes the choice; it is not the dates it resolves to', () {
      const a = DateRangeFilter(preset: DatePreset.today);
      const b = DateRangeFilter(preset: DatePreset.today);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(const DateRangeFilter(preset: DatePreset.tomorrow)));
      final today = a.resolved(wednesday);
      expect(a, isNot(today));
    });

    test('a choice replaces custom dates; changing a date turns a choice into a custom range', () {
      final custom = DateRangeFilter(from: day(12), until: day(13));
      final chosen = custom.copyWith(preset: DatePreset.thisMonth);
      expect(chosen.preset, DatePreset.thisMonth);
      expect(chosen.from, isNull);
      expect(chosen.until, isNull);

      // Touching From keeps the choice's other end (resolved for today).
      final edited = const DateRangeFilter(preset: DatePreset.thisMonth)
          .copyWith(from: day(5));
      expect(edited.preset, isNull);
      expect(edited.from, day(5));
      expect(edited.until, isNotNull);

      expect(chosen.copyWith(clearPreset: true), const DateRangeFilter());
      expect(chosen.copyWith(clearPreset: true).active, isFalse);
    });

    test('a custom filter is unchanged by resolved()', () {
      final custom = DateRangeFilter(from: day(12), until: day(13));
      expect(identical(custom.resolved(), custom), isTrue);
    });
  });
}
