import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/treemap_layout.dart';

void main() {
  const eps = 1e-6;

  List<TreemapItem> items(List<double> values) => [
    for (var i = 0; i < values.length; i++)
      TreemapItem('i${i.toString().padLeft(3, '0')}', values[i]),
  ];

  /// The rectangles must lie inside the bounds and not overlap.
  void expectTiled(List<TreemapRect> r, double w, double h) {
    for (final a in r) {
      expect(a.x, greaterThanOrEqualTo(-eps));
      expect(a.y, greaterThanOrEqualTo(-eps));
      expect(a.right, lessThanOrEqualTo(w + eps));
      expect(a.bottom, lessThanOrEqualTo(h + eps));
      expect(a.w, greaterThan(0));
      expect(a.h, greaterThan(0));
    }
    for (var i = 0; i < r.length; i++) {
      for (var j = i + 1; j < r.length; j++) {
        final overlapW =
            math.min(r[i].right, r[j].right) - math.max(r[i].x, r[j].x);
        final overlapH =
            math.min(r[i].bottom, r[j].bottom) - math.max(r[i].y, r[j].y);
        expect(
          overlapW > eps && overlapH > eps,
          isFalse,
          reason: '${r[i].id} overlaps ${r[j].id}',
        );
      }
    }
  }

  test('one item fills the whole space', () {
    final r = squarify(items([5]), width: 400, height: 300);
    expect(r, hasLength(1));
    expect(r.single.x, 0);
    expect(r.single.y, 0);
    expect(r.single.w, closeTo(400, eps));
    expect(r.single.h, closeTo(300, eps));
  });

  test('areas are proportional to the values and add up to the space', () {
    final values = <double>[60, 30, 20, 10, 5, 5, 1];
    final r = squarify(items(values), width: 800, height: 500);
    expect(r, hasLength(values.length));
    final total = values.fold<double>(0, (a, b) => a + b);
    var sum = 0.0;
    for (var i = 0; i < values.length; i++) {
      final rect = r.firstWhere((x) => x.id == 'i${i.toString().padLeft(3, '0')}');
      expect(rect.area, closeTo(values[i] / total * 800 * 500, 1e-3));
      sum += rect.area;
    }
    expect(sum, closeTo(800 * 500, 1e-3));
    expectTiled(r, 800, 500);
  });

  test('the rectangles tile the space without overlap (many items)', () {
    final rnd = math.Random(7);
    final values = [for (var i = 0; i < 120; i++) 1 + rnd.nextDouble() * 500];
    final r = squarify(items(values), width: 1000, height: 640);
    expect(r, hasLength(120));
    expectTiled(r, 1000, 640);
    expect(
      r.fold<double>(0, (a, b) => a + b.area),
      closeTo(1000 * 640, 1e-2),
    );
  });

  test('tall and wide spaces work, and blocks stay reasonably square', () {
    for (final (w, h) in [(300.0, 900.0), (900.0, 300.0)]) {
      final r = squarify(items([8, 7, 6, 5, 4, 3, 2, 1]), width: w, height: h);
      expectTiled(r, w, h);
      for (final b in r) {
        final ratio = math.max(b.w / b.h, b.h / b.w);
        expect(ratio, lessThan(8), reason: '${b.id} in ${w}x$h');
      }
    }
  });

  test('zero, negative and non-finite values are dropped', () {
    final r = squarify(
      [
        const TreemapItem('a', 10),
        const TreemapItem('zero', 0),
        const TreemapItem('neg', -3),
        const TreemapItem('nan', double.nan),
        const TreemapItem('inf', double.infinity),
      ],
      width: 100,
      height: 100,
    );
    expect(r.map((x) => x.id), ['a']);
    expect(r.single.area, closeTo(10000, 1e-6));
  });

  test('empty input and an empty space give nothing', () {
    expect(squarify(const [], width: 100, height: 100), isEmpty);
    expect(squarify(items([1, 2]), width: 0, height: 100), isEmpty);
    expect(squarify(items([1, 2]), width: 100, height: 0), isEmpty);
    expect(squarify(items([1, 2]), width: -5, height: 100), isEmpty);
    expect(squarify(items([0, 0]), width: 100, height: 100), isEmpty);
  });

  test('the same data always gives the same picture, whatever the input order', () {
    final a = squarify(
      const [TreemapItem('x', 5), TreemapItem('y', 5), TreemapItem('z', 9)],
      width: 300,
      height: 200,
    );
    final b = squarify(
      const [TreemapItem('z', 9), TreemapItem('y', 5), TreemapItem('x', 5)],
      width: 300,
      height: 200,
    );
    expect(a.map((r) => r.id), b.map((r) => r.id));
    for (var i = 0; i < a.length; i++) {
      expect(a[i].x, b[i].x);
      expect(a[i].y, b[i].y);
      expect(a[i].w, b[i].w);
      expect(a[i].h, b[i].h);
    }
    // Largest first; equal values by id.
    expect(a.map((r) => r.id), ['z', 'x', 'y']);
  });

  test('a tiny value next to a huge one still gets a positive rectangle', () {
    final r = squarify(
      const [TreemapItem('big', 100000), TreemapItem('tiny', 1)],
      width: 600,
      height: 400,
    );
    expect(r, hasLength(2));
    expectTiled(r, 600, 400);
    expect(r.firstWhere((x) => x.id == 'tiny').area, greaterThan(0));
  });
}
