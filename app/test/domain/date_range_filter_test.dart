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
}
