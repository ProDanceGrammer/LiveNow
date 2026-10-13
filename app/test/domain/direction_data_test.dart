import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/growth_rules.dart';
import 'package:livenow/domain/postpone_rules.dart';

GrowthMetric _m(String id, MetricKind kind, [MetricWindow? w]) => GrowthMetric(
  id: id,
  name: id,
  kind: kind,
  window: w,
  target: 1,
  isMain: false,
  weight: 0,
  importanceLevel: 0,
);

void main() {
  setUpAll(initPostponeTimeZoneData);

  // 2026-10-14 (Wednesday) noon UTC; a week window reaches back to 08 Oct.
  final now = DateTime.utc(2026, 10, 14, 12);
  final week = _m('week', MetricKind.count, MetricWindow.week);
  final month = _m('month', MetricKind.hours, MetricWindow.month);
  final flag = _m('flag', MetricKind.boolean);

  Set<String> run(List<(String, DateTime?)> links) => directionsNeedingData(
    metrics: [week, month, flag],
    links: links,
    nowUtc: now,
  );

  test('no links at all: every direction needs data', () {
    expect(run([]), {'week', 'month', 'flag'});
  });

  test('an action inside the period counts, one before it does not', () {
    final inside = DateTime.utc(2026, 10, 9, 9);
    final before = DateTime.utc(2026, 10, 7, 9);
    expect(run([('week', inside)]), {'month', 'flag'});
    expect(run([('week', before)]), {'week', 'month', 'flag'});
    // The same date is still inside a month window.
    expect(run([('month', before)]), {'week', 'flag'});
  });

  test('a future dated action counts, however far away', () {
    expect(run([('week', DateTime.utc(2030, 1, 1))]), {'month', 'flag'});
  });

  test('linked but undated actions do not count', () {
    expect(run([('week', null), ('month', null), ('flag', null)]), {
      'week',
      'month',
      'flag',
    });
  });

  test('a boolean needs only ANY dated linked action', () {
    expect(run([('flag', DateTime.utc(2020, 1, 1))]), {'week', 'month'});
  });

  test('links of unknown directions are ignored', () {
    expect(
      run([('gone', DateTime.utc(2026, 10, 14))]),
      {'week', 'month', 'flag'},
    );
  });

  test('a direction that depends on others is never white', () {
    // `month` has sub-directions: it takes its progress from them, so it is
    // not missing data of its own, even with no action at all.
    final needing = directionsNeedingData(
      metrics: [week, month, flag],
      links: const [],
      nowUtc: now,
      dependentIds: {'month'},
    );
    expect(needing, {'week', 'flag'});
  });
}
