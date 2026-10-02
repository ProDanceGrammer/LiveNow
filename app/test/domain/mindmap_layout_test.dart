import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/growth_rules.dart';
import 'package:livenow/domain/mindmap_layout.dart';

GrowthMetric m(String id, {bool main = false, String? name}) => GrowthMetric(
  id: id,
  name: name ?? id,
  kind: MetricKind.boolean,
  isMain: main,
);

GrowthGraph g(List<(String, String)> deps) =>
    GrowthGraph([for (final (a, b) in deps) (metricId: a, dependsOnId: b)]);

void expectNoOverlap(MindmapPositions pos) {
  final e = pos.entries.toList();
  for (var i = 0; i < e.length; i++) {
    for (var j = i + 1; j < e.length; j++) {
      final a = e[i].value, b = e[j].value;
      final overlapX = (a.$1 - b.$1).abs() < mindmapNodeWidth;
      final overlapY = (a.$2 - b.$2).abs() < mindmapNodeHeight;
      expect(
        overlapX && overlapY,
        isFalse,
        reason: '${e[i].key} overlaps ${e[j].key}',
      );
    }
  }
}

double colX(int c) => c * (mindmapNodeWidth + mindmapGapX);

({List<GrowthMetric> metrics, GrowthGraph graph}) randomDag(int n) {
  final rnd = Random(42);
  final metrics = [
    for (var i = 0; i < n; i++)
      m('n$i', main: i < 5, name: 'Node ${rnd.nextInt(1000)}'),
  ];
  final deps = <(String, String)>[];
  for (var i = 5; i < n; i++) {
    for (var k = 0; k < 1 + rnd.nextInt(2); k++) {
      deps.add(('n${rnd.nextInt(i)}', 'n$i'));
    }
  }
  return (metrics: metrics, graph: g(deps));
}

void main() {
  group('layeredLayout', () {
    test('empty and single node', () {
      expect(layeredLayout(g([]), []), isEmpty);
      final p = layeredLayout(g([]), [m('a')]);
      expect(p['a'], (0.0, 0.0));
    });

    test('chain puts sub-directions further right', () {
      // a leads to nothing; b feeds a; c feeds b.
      final p = layeredLayout(g([('a', 'b'), ('b', 'c')]), [
        m('a'),
        m('b'),
        m('c'),
      ]);
      expect(p['a']!.$1, colX(0));
      expect(p['b']!.$1, colX(1));
      expect(p['c']!.$1, colX(2));
    });

    test('deepest column wins for a node with two parents', () {
      // top <- mid <- leaf, and top <- leaf directly.
      final p = layeredLayout(
        g([('top', 'mid'), ('mid', 'leaf'), ('top', 'leaf')]),
        [m('top'), m('mid'), m('leaf')],
      );
      expect(p['leaf']!.$1, colX(2));
    });

    test('diamond', () {
      final p = layeredLayout(
        g([('a', 'b'), ('a', 'c'), ('b', 'd'), ('c', 'd')]),
        [m('a'), m('b'), m('c'), m('d')],
      );
      expect(p['b']!.$1, colX(1));
      expect(p['c']!.$1, colX(1));
      expect(p['d']!.$1, colX(2));
      expect(p['c']!.$2, mindmapNodeHeight + mindmapGapY);
    });

    test('main directions are in column 0', () {
      final p = layeredLayout(g([('x', 'a')]), [
        m('a', main: true),
        m('x', main: true),
      ]);
      expect(p['a']!.$1, 0);
      expect(p['x']!.$1, 0);
    });

    test('no overlaps on a 210-node DAG, fast, deterministic', () {
      final d = randomDag(210);
      final sw = Stopwatch()..start();
      final p = layeredLayout(d.graph, d.metrics);
      expect(sw.elapsedMilliseconds, lessThan(100));
      expect(p.length, 210);
      expectNoOverlap(p);
      expect(layeredLayout(d.graph, d.metrics), p);
    });

    test('a cycle does not hang', () {
      final p = layeredLayout(g([('a', 'b'), ('b', 'c'), ('c', 'a')]), [
        m('a'),
        m('b'),
        m('c'),
      ]);
      expect(p.length, 3);
      expectNoOverlap(p);
    });
  });

  group('radialLayout', () {
    test('empty graph and single node', () {
      expect(radialLayout(g([]), [], 'x'), isEmpty);
      final p = radialLayout(g([]), [m('a')], 'a');
      expect(p['a'], (-mindmapNodeWidth / 2, -mindmapNodeHeight / 2));
    });

    (double, double) centreOf((double, double) p) =>
        (p.$1 + mindmapNodeWidth / 2, p.$2 + mindmapNodeHeight / 2);
    double dist((double, double) p) {
      final c = centreOf(p);
      return sqrt(c.$1 * c.$1 + c.$2 * c.$2);
    }

    test('rings are ordered by hop distance, either direction', () {
      // c -> b -> a -> x (a depends on x) ; centre is a.
      final p = radialLayout(g([('b', 'a'), ('c', 'b'), ('a', 'x')]), [
        m('a'),
        m('b'),
        m('c'),
        m('x'),
      ], 'a');
      expect(dist(p['a']!), closeTo(0, 1e-9));
      expect(dist(p['b']!), lessThan(dist(p['c']!)));
      expect(dist(p['x']!), closeTo(dist(p['b']!), 1e-9));
      // The centre's two neighbours split the circle: opposite sides.
      expect(centreOf(p['b']!).$1 * centreOf(p['x']!).$1, lessThan(0));
      expectNoOverlap(p);
    });

    test('children stay in their parent sector (siblings are adjacent)', () {
      // hub with two branches of three leaves each: the two branches must not interleave.
      final metrics = [
        m('hub'),
        m('p1'),
        m('p2'),
        for (final i in [1, 2, 3]) m('a$i'),
        for (final i in [1, 2, 3]) m('b$i'),
      ];
      final edges = [
        ('p1', 'hub'),
        ('p2', 'hub'),
        for (final i in [1, 2, 3]) ('a$i', 'p1'),
        for (final i in [1, 2, 3]) ('b$i', 'p2'),
      ];
      final p = radialLayout(g(edges), metrics, 'hub');
      double angle(String id) {
        final c = centreOf(p[id]!);
        return atan2(c.$2, c.$1);
      }

      // Every a-leaf is closer (in angle) to p1 than to p2, and vice versa.
      double gap(String x, String y) {
        final d = (angle(x) - angle(y)).abs();
        return min(d, 2 * pi - d);
      }

      for (final i in [1, 2, 3]) {
        expect(gap('a$i', 'p1'), lessThan(gap('a$i', 'p2')));
        expect(gap('b$i', 'p2'), lessThan(gap('b$i', 'p1')));
      }
      expectNoOverlap(p);
    });

    test('disconnected nodes sit outside the outermost ring', () {
      final metrics = [
        for (final id in ['a', 'b', 'c', 'd', 'e']) m(id),
      ];
      final p = radialLayout(g([('a', 'b'), ('a', 'c')]), metrics, 'a');
      final outer = max(dist(p['b']!), dist(p['c']!));
      for (final id in ['d', 'e']) {
        expect(p[id]!.$2, greaterThan(outer));
      }
      expectNoOverlap(p);
    });

    test('210 nodes: no overlaps, fast, deterministic', () {
      final d = randomDag(210);
      final sw = Stopwatch()..start();
      final p = radialLayout(d.graph, d.metrics, 'n0');
      expect(sw.elapsedMilliseconds, lessThan(500));
      expect(p.length, 210);
      expectNoOverlap(p);
      expect(radialLayout(d.graph, d.metrics, 'n0'), p);
    });

    test('a cycle does not hang', () {
      final p = radialLayout(g([('a', 'b'), ('b', 'c'), ('c', 'a')]), [
        m('a'),
        m('b'),
        m('c'),
      ], 'a');
      expect(p.length, 3);
      expectNoOverlap(p);
    });
  });

  test(
    'shiftIntoView moves the top-left node to the margin, keeping shape',
    () {
      final p = shiftIntoView({'a': (-300.0, -50.0), 'b': (100.0, 200.0)});
      expect(p['a'], (100.0, 100.0));
      expect(p['b'], (500.0, 350.0));
      expect(shiftIntoView({}), isEmpty);
      // A real radial layout has no negative coordinate afterwards.
      final r = shiftIntoView(
        radialLayout(g([('b', 'a')]), [m('a'), m('b')], 'a'),
      );
      expect(r.values.every((v) => v.$1 >= 0 && v.$2 >= 0), isTrue);
    },
  );

  group('treeLayout', () {
    // g(parent, child): parent depends on child, i.e. child leads to parent.
    test('empty, and goals stand to the right of what builds them', () {
      expect(treeLayout(g([]), []), isEmpty);
      final p = treeLayout(g([('goal', 'a'), ('a', 'b')]), [
        m('goal', main: true),
        m('a'),
        m('b'),
      ]);
      expect(p['goal']!.$1, greaterThan(p['a']!.$1));
      expect(p['a']!.$1, greaterThan(p['b']!.$1));
      expect(p['goal']!.$2, p['a']!.$2); // a chain sits on one row
      expectNoOverlap(p);
    });

    test('a parent is centred on its children, branches stay grouped', () {
      final p = treeLayout(
        g([('P', 'k1'), ('P', 'k2'), ('P', 'k3'), ('Q', 'q1')]),
        [
          m('P', main: true),
          m('Q', main: true),
          m('k1'),
          m('k2'),
          m('k3'),
          m('q1'),
        ],
      );
      expect(p['P']!.$2, closeTo(p['k2']!.$2, 1e-9)); // middle of k1..k3
      // Q's whole branch is below P's (no interleaving).
      expect(p['q1']!.$2, greaterThan(p['k3']!.$2));
      expect(p['Q']!.$2, greaterThan(p['P']!.$2));
      expectNoOverlap(p);
    });

    test('a shared direction stands under the parent nearest to a main', () {
      // M (main) <- P1 ; M <- X <- P2 ; N feeds both P1 and P2.
      final p = treeLayout(
        g([('M', 'P1'), ('M', 'X'), ('X', 'P2'), ('P1', 'N'), ('P2', 'N')]),
        [m('M', main: true), m('P1'), m('X'), m('P2'), m('N')],
      );
      // N is P1's only child -> P1 sits on N's row; P2 is a childless leaf.
      expect(p['P1']!.$2, closeTo(p['N']!.$2, 1e-9));
      expect(p['P2']!.$2, isNot(closeTo(p['N']!.$2, 1e-9)));
      // Every arrow still points right (children left of all their parents).
      expect(p['N']!.$1, lessThan(p['P1']!.$1));
      expect(p['N']!.$1, lessThan(p['P2']!.$1));
      expectNoOverlap(p);
    });

    test('siblings and roots follow the order hint, else the name', () {
      final metrics = [m('R', main: true), m('a'), m('b'), m('c')];
      final graph = g([('R', 'a'), ('R', 'b'), ('R', 'c')]);
      final byName = treeLayout(graph, metrics);
      expect(byName['a']!.$2, lessThan(byName['b']!.$2));
      expect(byName['b']!.$2, lessThan(byName['c']!.$2));
      final hinted = treeLayout(
        graph,
        metrics,
        orderHint: {'c': 0, 'a': 10, 'b': 20},
      );
      expect(hinted['c']!.$2, lessThan(hinted['a']!.$2));
      expect(hinted['a']!.$2, lessThan(hinted['b']!.$2));
    });

    test('rootId lays out only the root and what builds it', () {
      final metrics = [m('G', main: true), m('a'), m('b'), m('other'), m('x')];
      final p = treeLayout(
        g([('G', 'a'), ('a', 'b'), ('other', 'x')]),
        metrics,
        rootId: 'a',
      );
      expect(p.keys.toSet(), {'a', 'b'});
      expect(p['a']!.$1, greaterThan(p['b']!.$1));
      expect(treeLayout(g([]), metrics, rootId: 'missing'), isEmpty);
    });

    test('unconnected directions form a block below the trees', () {
      final p = treeLayout(g([('R', 'a')]), [
        m('R', main: true),
        m('a'),
        m('solo1'),
        m('solo2'),
      ]);
      final treeBottom = max(p['R']!.$2, p['a']!.$2);
      expect(p['solo1']!.$2, greaterThan(treeBottom));
      expect(p['solo2']!.$2, greaterThan(treeBottom));
      expectNoOverlap(p);
    });

    test(
      '210 nodes: no overlaps, arrows all point right, fast, deterministic',
      () {
        final d = randomDag(210);
        final sw = Stopwatch()..start();
        final p = treeLayout(d.graph, d.metrics);
        expect(sw.elapsedMilliseconds, lessThan(200));
        expect(p.length, 210);
        expectNoOverlap(p);
        for (final mm in d.metrics) {
          for (final parent in d.graph.leadsToOf(mm.id)) {
            expect(
              p[mm.id]!.$1,
              lessThan(p[parent]!.$1),
              reason: '${mm.id} -> $parent',
            );
          }
        }
        expect(treeLayout(d.graph, d.metrics), p);
      },
    );

    test('a cycle does not hang and still places everything', () {
      final p = treeLayout(g([('a', 'b'), ('b', 'c'), ('c', 'a')]), [
        m('a'),
        m('b'),
        m('c'),
      ]);
      expect(p.keys.toSet(), {'a', 'b', 'c'});
      expectNoOverlap(p);
    });
  });
}
