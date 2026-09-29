import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/growth_rules.dart';
import 'package:livenow/domain/postpone_rules.dart';

void main() {
  setUpAll(initPostponeTimeZoneData);

  // Europe/Istanbul is UTC+3 all year, so local midnight = 21:00Z the day before.
  DateTime utc(int y, int mo, int d, [int h = 0, int mi = 0]) =>
      DateTime.utc(y, mo, d, h, mi);

  group('windowStart (rolling, day-aligned in Istanbul)', () {
    final now = utc(2026, 9, 29, 10); // 13:00 local on 29 Sep

    test('week = last 7 calendar days including today', () {
      expect(windowStart(now, MetricWindow.week), utc(2026, 9, 22, 21));
    });
    test('month = one calendar month back', () {
      expect(windowStart(now, MetricWindow.month), utc(2026, 8, 28, 21));
    });
    test('month clamps to the end of a shorter month', () {
      final mar31 = utc(2026, 3, 31, 10);
      expect(windowStart(mar31, MetricWindow.month), utc(2026, 2, 27, 21));
    });
    test('year and five years', () {
      expect(windowStart(now, MetricWindow.year), utc(2025, 9, 28, 21));
      expect(windowStart(now, MetricWindow.fiveYears), utc(2021, 9, 28, 21));
    });
    test('just after local midnight the day has already rolled over', () {
      final justAfter = utc(2026, 9, 29, 21, 5); // 00:05 local on 30 Sep
      expect(windowStart(justAfter, MetricWindow.week), utc(2026, 9, 23, 21));
    });
  });

  group('progress and urgency (the essay\'s worked examples)', () {
    test('12.5 h of a 7 h target is 178.57%, uncapped', () {
      expect(progressPercent(12.5, 7), 178.57);
    });
    test('zero and non-positive targets', () {
      expect(progressPercent(3, 0), 0);
      expect(progressPercent(3, -2), 0);
      expect(progressPercent(0, 5), 0);
    });
    test('urgency U = W x (90 - P) / 90', () {
      expect(urgencyOf(1000, 90), 0);
      expect(urgencyOf(10, 120), closeTo(-3.33, 0.01));
      expect(urgencyOf(500, 80), closeTo(55.56, 0.01));
      expect(urgencyOf(700, 95), closeTo(-38.89, 0.01));
    });
  });

  group('importance level and weight', () {
    // "X depends on Y" = Y leads to X.
    // R (main) <- A <- B, and C leads to both B and R.
    MetricEdge dep(String metric, String dependsOn) =>
        (metricId: metric, dependsOnId: dependsOn);
    final graph = GrowthGraph([
      dep('R', 'A'),
      dep('A', 'B'),
      dep('B', 'C'),
      dep('R', 'C'),
    ]);
    final ids = ['R', 'A', 'B', 'C', 'X'];
    final levels = importanceLevels(ids, {'R'}, graph);
    final weights = directionWeights(ids, {'R'}, graph, levels);

    test('levels fall by one per hop to the nearest main; orphans are 0', () {
      expect(levels, {'R': 10, 'A': 9, 'B': 8, 'C': 9, 'X': 0});
    });
    test('C is 1 hop from R via the shortcut, not 3 via B', () {
      expect(levels['C'], 9);
    });
    test(
      'a main weighs 1000; a child 9 x 10 = 90; a grandchild 8 x 19 = 152',
      () {
        expect(weights['R'], 1000);
        expect(weights['A'], 90);
        expect(weights['B'], 152);
      },
    );
    test('shared ancestors are counted once: C = 9 x (8 + 9 + 10)', () {
      expect(weights['C'], 243);
    });
    test('a direction with no path to a main weighs 0', () {
      expect(weights['X'], 0);
    });
    test('level never drops below 1 once connected to a main', () {
      final edges = [for (var i = 0; i < 14; i++) dep('n$i', 'n${i + 1}')];
      final g = GrowthGraph(edges);
      final chain = [for (var i = 0; i <= 14; i++) 'n$i'];
      final l = importanceLevels(chain, {'n0'}, g);
      expect(l['n0'], 10);
      expect(l['n9'], 1);
      expect(l['n14'], 1);
    });
    test('two main goals both count as ancestors', () {
      final g = GrowthGraph([dep('M1', 'S'), dep('M2', 'S')]);
      final l = importanceLevels(['M1', 'M2', 'S'], {'M1', 'M2'}, g);
      final w = directionWeights(['M1', 'M2', 'S'], {'M1', 'M2'}, g, l);
      expect(w['S'], 9 * 20); // matches the 180 in the real data
    });
  });

  group('cycles', () {
    MetricEdge dep(String m, String d) => (metricId: m, dependsOnId: d);
    test('a loop is detected, a DAG is not', () {
      expect(
        GrowthGraph([dep('a', 'b'), dep('b', 'c'), dep('c', 'a')]).hasCycle,
        isTrue,
      );
      expect(
        GrowthGraph([dep('a', 'b'), dep('a', 'c'), dep('b', 'c')]).hasCycle,
        isFalse,
      );
      expect(GrowthGraph(const []).hasCycle, isFalse);
    });
  });

  group('computeStats', () {
    final now = utc(2026, 9, 29, 10);
    final inWindow = utc(2026, 9, 27, 10);
    final tooOld = utc(2026, 9, 10, 10);

    LinkedActionFact fact(
      String metric, {
      bool done = true,
      DateTime? at,
      double hours = 1,
    }) => LinkedActionFact(
      metricId: metric,
      isDone: done,
      windowTime: at ?? inWindow,
      duration: Duration(minutes: (hours * 60).round()),
    );

    Map<String, MetricStat> stats(
      List<GrowthMetric> metrics,
      List<LinkedActionFact> facts, [
      List<MetricEdge> edges = const [],
    ]) => computeStats(
      metrics: metrics,
      graph: GrowthGraph(edges),
      facts: facts,
      nowUtc: now,
    );

    test('count: only finished actions inside the window', () {
      final s = stats(
        [
          const GrowthMetric(
            id: 'c',
            name: 'c',
            kind: MetricKind.count,
            window: MetricWindow.week,
            target: 7,
            weight: 900,
          ),
        ],
        [
          fact('c'),
          fact('c'),
          fact('c'),
          fact('c', at: tooOld),
          fact('c', done: false),
        ],
      );
      expect(s['c']!.fact, 3);
      expect(s['c']!.progress, 42.86);
      expect(s['c']!.urgency, closeTo(900 * (90 - 42.86) / 90, 0.01));
    });

    test('hours: sums durations, can exceed 100%', () {
      final s = stats(
        [
          const GrowthMetric(
            id: 'h',
            name: 'h',
            kind: MetricKind.hours,
            window: MetricWindow.week,
            target: 7,
          ),
        ],
        [fact('h', hours: 4), fact('h', hours: 3.5), fact('h', hours: 5)],
      );
      expect(s['h']!.fact, 12.5);
      expect(s['h']!.progress, 178.57);
    });

    test('boolean with linked actions: the share that is done', () {
      final s = stats(
        [const GrowthMetric(id: 'b', name: 'b', kind: MetricKind.boolean)],
        [fact('b'), fact('b'), fact('b'), fact('b', done: false)],
      );
      expect(s['b']!.progress, 75);
    });

    test(
      'boolean without actions: mean of its children, each capped at 100',
      () {
        final s = stats(
          [
            const GrowthMetric(id: 'p', name: 'p', kind: MetricKind.boolean),
            const GrowthMetric(
              id: 'gym',
              name: 'gym',
              kind: MetricKind.count,
              window: MetricWindow.week,
              target: 3,
            ),
            const GrowthMetric(
              id: 'protein',
              name: 'protein',
              kind: MetricKind.count,
              window: MetricWindow.week,
              target: 10,
            ),
          ],
          [
            // gym 2/3 = 66.67%, protein 11/10 = 110% -> capped at 100.
            fact('gym'), fact('gym'),
            for (var i = 0; i < 11; i++) fact('protein'),
          ],
          [
            (metricId: 'p', dependsOnId: 'gym'),
            (metricId: 'p', dependsOnId: 'protein'),
          ],
        );
        // The parent averages the children's already-rounded 66.67 and 100.
        expect(s['p']!.progress, closeTo(83.34, 0.005));
      },
    );

    test('actions take precedence over sub-directions (Notion order)', () {
      final s = stats(
        [
          const GrowthMetric(id: 'p', name: 'p', kind: MetricKind.boolean),
          const GrowthMetric(id: 'k', name: 'k', kind: MetricKind.boolean),
        ],
        [fact('p'), fact('p', done: false), fact('k')],
        [(metricId: 'p', dependsOnId: 'k')],
      );
      expect(s['p']!.progress, 50);
    });

    test('a boolean with nothing to go on is at 0%', () {
      final s = stats([
        const GrowthMetric(
          id: 'b',
          name: 'b',
          kind: MetricKind.boolean,
          weight: 100,
        ),
      ], const []);
      expect(s['b']!.progress, 0);
      expect(s['b']!.urgency, 100);
    });
  });

  group('Balance Dashboard', () {
    GrowthMetric m(
      MetricKind kind,
      MetricWindow? w,
      double target, {
      String id = 'x',
    }) => GrowthMetric(id: id, name: id, kind: kind, window: w, target: target);

    test('weekly windows split at 7 actions / 3 hours', () {
      expect(
        balanceGroupOf(m(MetricKind.count, MetricWindow.week, 7)),
        BalanceGroup.weekly,
      );
      expect(
        balanceGroupOf(m(MetricKind.count, MetricWindow.week, 8)),
        BalanceGroup.daily,
      );
      expect(
        balanceGroupOf(m(MetricKind.hours, MetricWindow.week, 3)),
        BalanceGroup.weekly,
      );
      expect(
        balanceGroupOf(m(MetricKind.hours, MetricWindow.week, 4)),
        BalanceGroup.daily,
      );
    });
    test(
      '30-day windows are monthly; boolean, year and 5-year are off-board',
      () {
        expect(
          balanceGroupOf(m(MetricKind.count, MetricWindow.month, 2)),
          BalanceGroup.monthly,
        );
        expect(
          balanceGroupOf(m(MetricKind.hours, MetricWindow.month, 60)),
          BalanceGroup.monthly,
        );
        expect(
          balanceGroupOf(m(MetricKind.count, MetricWindow.year, 2)),
          isNull,
        );
        expect(
          balanceGroupOf(m(MetricKind.count, MetricWindow.fiveYears, 2)),
          isNull,
        );
        expect(balanceGroupOf(m(MetricKind.boolean, null, 1)), isNull);
      },
    );

    MetricStat stat(double urgency, [double progress = 50]) =>
        MetricStat(fact: 0, progress: progress, urgency: urgency);

    test('Focus On: urgency > 0, most urgent first', () {
      final metrics = [
        m(MetricKind.count, MetricWindow.week, 3, id: 'a'),
        m(MetricKind.count, MetricWindow.week, 3, id: 'b'),
        m(MetricKind.count, MetricWindow.week, 3, id: 'c'),
        m(MetricKind.count, MetricWindow.week, 9, id: 'daily'),
      ];
      final rows = balanceBoard(
        BalanceGroup.weekly,
        BalanceSide.focusOn,
        metrics,
        {'a': stat(10), 'b': stat(300), 'c': stat(0), 'daily': stat(999)},
      );
      expect(rows.map((r) => r.metric.id), ['b', 'a']);
    });

    test('Decrease It: below the group limit, lowest first', () {
      GrowthMetric w(String id) =>
          m(MetricKind.count, MetricWindow.week, 3, id: id);
      final weeklyRows = balanceBoard(
        BalanceGroup.weekly,
        BalanceSide.decreaseIt,
        [w('a'), w('b'), w('c'), w('d')],
        {'a': stat(-5), 'b': stat(9.9), 'c': stat(10), 'd': stat(-300)},
      );
      expect(weeklyRows.map((r) => r.metric.id), ['d', 'a', 'b']);

      GrowthMetric d(String id) =>
          m(MetricKind.count, MetricWindow.week, 9, id: id);
      final dailyRows = balanceBoard(
        BalanceGroup.daily,
        BalanceSide.decreaseIt,
        [d('a'), d('b')],
        {'a': stat(0.5), 'b': stat(1)},
      );
      expect(dailyRows.map((r) => r.metric.id), ['a']);

      GrowthMetric mo(String id) =>
          m(MetricKind.count, MetricWindow.month, 2, id: id);
      final monthlyRows = balanceBoard(
        BalanceGroup.monthly,
        BalanceSide.decreaseIt,
        [mo('a'), mo('b')],
        {'a': stat(99), 'b': stat(100)},
      );
      expect(monthlyRows.map((r) => r.metric.id), ['a']);
    });

    test('the footer average is the mean progress of the rows', () {
      final metrics = [
        m(MetricKind.count, MetricWindow.week, 3, id: 'a'),
        m(MetricKind.count, MetricWindow.week, 3, id: 'b'),
      ];
      final rows = balanceBoard(
        BalanceGroup.weekly,
        BalanceSide.focusOn,
        metrics,
        {'a': stat(5, 40), 'b': stat(9, 60)},
      );
      expect(averageProgress(rows), 50);
      expect(averageProgress(const []), isNull);
    });
  });
}
