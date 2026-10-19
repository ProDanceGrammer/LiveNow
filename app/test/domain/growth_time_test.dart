import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/growth_rules.dart';
import 'package:livenow/domain/growth_time.dart';
import 'package:livenow/domain/postpone_rules.dart';

LinkedActionFact _fact(
  String metric,
  DateTime at, {
  int minutes = 60,
  bool done = true,
}) => LinkedActionFact(
  metricId: metric,
  isDone: done,
  windowTime: at,
  duration: Duration(minutes: minutes),
);

GrowthMetric _metric(
  String id,
  String name, {
  MetricKind kind = MetricKind.count,
}) => GrowthMetric(id: id, name: name, kind: kind);

void main() {
  setUpAll(initPostponeTimeZoneData);

  // Monday 19 Oct 2026, 13:00 in Istanbul (UTC+3).
  final now = DateTime.utc(2026, 10, 19, 10);

  group('TreemapPeriod', () {
    test('windows are the directions\' rolling Istanbul-midnight ones', () {
      // Week = the last 7 calendar days including today: from 13 Oct 00:00
      // Istanbul = 12 Oct 21:00 UTC.
      expect(
        TreemapPeriod.week.since(now),
        windowStart(now, MetricWindow.week),
      );
      expect(
        TreemapPeriod.week.since(now)!.toUtc(),
        DateTime.utc(2026, 10, 12, 21),
      );
      expect(
        TreemapPeriod.month.since(now),
        windowStart(now, MetricWindow.month),
      );
      expect(
        TreemapPeriod.year.since(now),
        windowStart(now, MetricWindow.year),
      );
      expect(
        TreemapPeriod.fiveYears.since(now),
        windowStart(now, MetricWindow.fiveYears),
      );
      expect(TreemapPeriod.all.since(now), isNull);
    });

    test('byName reads a saved name and ignores unknown ones', () {
      expect(TreemapPeriod.byName('year'), TreemapPeriod.year);
      expect(TreemapPeriod.byName('nope'), isNull);
      expect(TreemapPeriod.byName(null), isNull);
    });
  });

  group('timeSpentPerDirection', () {
    test('sums the durations of finished actions per direction', () {
      final t = timeSpentPerDirection(
        [
          _fact('a', now.subtract(const Duration(days: 1)), minutes: 90),
          _fact('a', now.subtract(const Duration(days: 2)), minutes: 30),
          _fact('b', now.subtract(const Duration(days: 1)), minutes: 45),
        ],
        nowUtc: now,
        period: TreemapPeriod.week,
      );
      expect(t['a'], const Duration(minutes: 120));
      expect(t['b'], const Duration(minutes: 45));
    });

    test('only finished actions count', () {
      final t = timeSpentPerDirection(
        [
          _fact('a', now.subtract(const Duration(days: 1)), done: false),
          _fact('b', now.subtract(const Duration(days: 1))),
        ],
        nowUtc: now,
        period: TreemapPeriod.week,
      );
      expect(t.containsKey('a'), isFalse); // not done: no time at all
      expect(t['b'], const Duration(hours: 1));
    });

    test('the week starts at Istanbul midnight, to the second', () {
      final edge = DateTime.utc(2026, 10, 12, 21); // 13 Oct 00:00 Istanbul
      final t = timeSpentPerDirection(
        [
          _fact('in', edge),
          _fact('out', edge.subtract(const Duration(seconds: 1))),
        ],
        nowUtc: now,
        period: TreemapPeriod.week,
      );
      expect(t.containsKey('in'), isTrue);
      expect(t.containsKey('out'), isFalse);
    });

    test('a longer period takes in older actions, all time takes everything', () {
      final old = DateTime.utc(2020, 1, 1);
      final lastMonth = now.subtract(const Duration(days: 20));
      final facts = [_fact('a', old), _fact('b', lastMonth)];
      Map<String, Duration> over(TreemapPeriod p) =>
          timeSpentPerDirection(facts, nowUtc: now, period: p);
      expect(over(TreemapPeriod.week), isEmpty);
      expect(over(TreemapPeriod.month).keys, ['b']);
      expect(over(TreemapPeriod.year).keys, ['b']);
      expect(over(TreemapPeriod.fiveYears).keys, ['b']);
      expect(over(TreemapPeriod.all).keys, unorderedEquals(['a', 'b']));
    });

    test('an action linked to two directions counts in both', () {
      final at = now.subtract(const Duration(days: 1));
      final t = timeSpentPerDirection(
        [_fact('a', at, minutes: 50), _fact('b', at, minutes: 50)],
        nowUtc: now,
        period: TreemapPeriod.month,
      );
      expect(t['a'], const Duration(minutes: 50));
      expect(t['b'], const Duration(minutes: 50));
    });

    test('no facts, no time', () {
      expect(
        timeSpentPerDirection(
          const [],
          nowUtc: now,
          period: TreemapPeriod.all,
        ),
        isEmpty,
      );
    });
  });

  group('filterDirections', () {
    final all = [
      _metric('1', 'Reading', kind: MetricKind.hours),
      _metric('2', 'Run', kind: MetricKind.count),
      _metric('3', 'Я дихав повітрям', kind: MetricKind.boolean),
    ];

    test('no filter keeps everything in order', () {
      expect(filterDirections(all).map((m) => m.id), ['1', '2', '3']);
    });

    test('the search is a trimmed, case-insensitive contains', () {
      expect(filterDirections(all, query: '  READ ').map((m) => m.id), ['1']);
      expect(filterDirections(all, query: 'я ДИХАВ').map((m) => m.id), ['3']);
      expect(filterDirections(all, query: 'zzz'), isEmpty);
    });

    test('the type filter and the search combine', () {
      expect(
        filterDirections(all, kind: MetricKind.count).map((m) => m.id),
        ['2'],
      );
      expect(
        filterDirections(
          all,
          kind: MetricKind.count,
          query: 'read',
        ),
        isEmpty,
      );
    });
  });
}
