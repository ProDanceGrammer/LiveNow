import 'dart:math' as math;

import 'growth_rules.dart';

// Automatic placement of the growth-direction graph on the Mindmap canvas.
// Pure Dart (positions are (x, y) records = a node's TOP-LEFT corner) so it
// is unit-testable without Flutter. Edges point from a sub-direction to the
// direction it leads to; `graph.dependsOnOf(id)` are a node's sub-directions
// and `graph.leadsToOf(id)` the directions it feeds.

/// Size every node is laid out with (the widget draws nodes at this size).
const mindmapNodeWidth = 190.0;
const mindmapNodeHeight = 56.0;

/// Gap kept between nodes by both layouts.
const mindmapGapX = 60.0;
const mindmapGapY = 24.0;

typedef MindmapPositions = Map<String, (double, double)>;

/// Left-to-right layers: main directions (and any direction that leads to
/// nothing) in column 0; each direction sits one column right of the deepest
/// direction it leads to, so every arrow points left. Within a column nodes
/// are ordered by name; columns are stacked top to bottom without overlap.
MindmapPositions layeredLayout(GrowthGraph graph, List<GrowthMetric> metrics) {
  final byId = {for (final m in metrics) m.id: m};
  final column = <String, int>{};
  final onStack = <String>{};

  // Longest path to a node it leads to; a back edge (cycle) is ignored.
  int columnOf(String id) {
    final known = column[id];
    if (known != null) return known;
    if (byId[id]!.isMain) return column[id] = 0;
    onStack.add(id);
    var col = 0;
    for (final up in graph.leadsToOf(id)) {
      if (!byId.containsKey(up) || onStack.contains(up)) continue;
      col = math.max(col, columnOf(up) + 1);
    }
    onStack.remove(id);
    return column[id] = col;
  }

  final columns = <int, List<GrowthMetric>>{};
  for (final m in byId.values) {
    columns.putIfAbsent(columnOf(m.id), () => []).add(m);
  }
  final result = <String, (double, double)>{};
  columns.forEach((col, nodes) {
    nodes.sort(_byName);
    final x = col * (mindmapNodeWidth + mindmapGapX);
    for (var i = 0; i < nodes.length; i++) {
      result[nodes[i].id] = (x, i * (mindmapNodeHeight + mindmapGapY));
    }
  });
  return result;
}

int _byName(GrowthMetric a, GrowthMetric b) {
  final c = a.name.compareTo(b.name);
  return c != 0 ? c : a.id.compareTo(b.id);
}

/// Rings around [centerId]: the centre node in the middle, every node at
/// graph distance d (following relations in either direction) on ring d.
/// Each node sits in the angular sector of the node it was reached from, so
/// related nodes stay together and lines stay short; a crowded ring is spread
/// over several radial lanes and the ring radius grows until nothing touches.
/// Nodes not connected to the centre go in a grid below the outermost ring,
/// ordered by name. No two nodes overlap.
MindmapPositions radialLayout(
  GrowthGraph graph,
  List<GrowthMetric> metrics,
  String centerId,
) {
  const w = mindmapNodeWidth, h = mindmapNodeHeight;
  const pad = 10.0; // minimum clear space between two nodes
  const ringGap = 30.0; // clear space between consecutive rings
  final byId = {for (final m in metrics) m.id: m};
  final result = <String, (double, double)>{};

  // BFS over relations in either direction, remembering who reached whom.
  final rings = <List<GrowthMetric>>[];
  final parent = <String, String>{};
  final children = <String, List<GrowthMetric>>{};
  final seen = <String>{};
  if (byId.containsKey(centerId)) {
    seen.add(centerId);
    var frontier = [byId[centerId]!];
    while (frontier.isNotEmpty) {
      frontier.sort(_byName);
      rings.add(frontier);
      final next = <GrowthMetric>[];
      for (final m in frontier) {
        final neighbours = <GrowthMetric>[
          for (final id in {
            ...graph.dependsOnOf(m.id),
            ...graph.leadsToOf(m.id),
          })
            if (byId.containsKey(id)) byId[id]!,
        ]..sort(_byName);
        for (final n in neighbours) {
          if (seen.add(n.id)) {
            parent[n.id] = m.id;
            (children[m.id] ??= []).add(n);
            next.add(n);
          }
        }
      }
      frontier = next;
    }
  }

  // Sector weight = number of leaves below (a leaf counts 1).
  final weight = <String, double>{};
  for (var d = rings.length - 1; d >= 0; d--) {
    for (final m in rings[d]) {
      final kids = children[m.id] ?? const <GrowthMetric>[];
      weight[m.id] = kids.isEmpty
          ? 1
          : kids.fold<double>(0, (sum, k) => sum + weight[k.id]!);
    }
  }
  // Angular sector [from, to] per node; children split their parent's.
  final from = <String, double>{};
  final to = <String, double>{};
  if (rings.isNotEmpty) {
    from[centerId] = -math.pi / 2;
    to[centerId] = 3 * math.pi / 2;
    for (final ring in rings) {
      for (final m in ring) {
        final kids = children[m.id] ?? const <GrowthMetric>[];
        var a = from[m.id]!;
        final span = to[m.id]! - a;
        for (final k in kids) {
          final part = span * weight[k.id]! / weight[m.id]!;
          from[k.id] = a;
          to[k.id] = a + part;
          a += part;
        }
      }
    }
  }

  final placed = <_Box>[];
  var outer = 0.0;
  var radius = 0.0;
  for (var d = 0; d < rings.length; d++) {
    final nodes = rings[d];
    if (d == 0) {
      result[nodes.first.id] = (-w / 2, -h / 2);
      placed.add(_Box(-w / 2, -h / 2, w, h));
      outer = math.sqrt(w * w + h * h) / 2;
      continue;
    }
    final n = nodes.length;
    final laneStep = h + pad;
    final start = math.max(radius, outer + ringGap + w / 2);
    // Try 1..16 radial lanes and keep the tightest fit: more lanes let a
    // crowded ring sit on a smaller circle, but cost lane thickness.
    // Evenly spaced angles (the tightest packing), rotated so each node lands
    // as near its parent's sector as an even spread allows.
    var sinSum = 0.0, cosSum = 0.0;
    for (var i = 0; i < n; i++) {
      final want = (from[nodes[i].id]! + to[nodes[i].id]!) / 2;
      final delta = want - 2 * math.pi * i / n;
      sinSum += math.sin(delta);
      cosSum += math.cos(delta);
    }
    final offset = math.atan2(sinSum, cosSum);
    List<_Box>? bestRects;
    var bestR = 0.0, bestLanes = 1, bestOuter = double.infinity;
    for (final lanes in const [1, 2, 3, 4, 6, 8, 12, 16]) {
      if (lanes > 1 && lanes > n) break;
      var r = start;
      List<_Box> rects;
      while (true) {
        final angles = [
          for (var i = 0; i < n; i++) offset + 2 * math.pi * i / n,
        ];
        rects = _relaxRing(angles, r, lanes, laneStep, pad);
        final clash =
            _anyOverlap(rects, pad) ||
            rects.any((a) => placed.any((b) => _touch(a, b, pad)));
        if (!clash) break;
        r *= 1.02;
      }
      final extent = r + (lanes - 1) * laneStep;
      if (extent < bestOuter - 1) {
        bestOuter = extent;
        bestRects = rects;
        bestR = r;
        bestLanes = lanes;
      }
    }
    final ringRects = bestRects!;
    final r = bestR;
    final lanes = bestLanes;
    for (var i = 0; i < n; i++) {
      result[nodes[i].id] = (ringRects[i].left, ringRects[i].top);
    }
    placed.addAll(ringRects);
    radius = r;
    outer = r + (lanes - 1) * laneStep + w / 2;
  }

  // Everything not connected to the centre: a tidy grid below the rings.
  final rest = byId.values.where((m) => !seen.contains(m.id)).toList()
    ..sort(_byName);
  if (rest.isNotEmpty) {
    final cellW = w + mindmapGapX;
    final cols = math.max(5, ((2 * outer + w) / cellW).floor());
    final startX = -(math.min(cols, rest.length) * cellW - mindmapGapX) / 2;
    final startY = outer + h + 2 * mindmapGapY;
    for (var i = 0; i < rest.length; i++) {
      result[rest[i].id] = (
        startX + (i % cols) * cellW,
        startY + (i ~/ cols) * (h + mindmapGapY),
      );
    }
  }
  return result;
}

/// Translates [positions] so the top-left-most node lands at ([margin],
/// [margin]): the canvas has no negative coordinates, and [radialLayout] is
/// centred on the origin.
MindmapPositions shiftIntoView(
  MindmapPositions positions, {
  double margin = 100,
}) {
  if (positions.isEmpty) return positions;
  final minX = positions.values.map((p) => p.$1).reduce(math.min);
  final minY = positions.values.map((p) => p.$2).reduce(math.min);
  return {
    for (final e in positions.entries)
      e.key: (e.value.$1 - minX + margin, e.value.$2 - minY + margin),
  };
}

/// Boxes for one ring at [radius]: starts from the wanted [angles] (already
/// in order around the circle) and lets touching neighbours slide apart, so
/// crowded stretches borrow room from empty ones instead of forcing a bigger
/// circle. Lane `i % lanes` sets the radial offset of node i.
List<_Box> _relaxRing(
  List<double> angles,
  double radius,
  int lanes,
  double laneStep,
  double pad,
) {
  final n = angles.length;
  final a = [...angles];
  List<_Box> build() => [
    for (var i = 0; i < n; i++) _rectAt(a[i], radius + (i % lanes) * laneStep),
  ];
  var rects = build();
  if (n < 2) return rects;
  final step = 0.25 * (mindmapNodeHeight + pad) / radius;
  for (var iter = 0; iter < 400; iter++) {
    var moved = false;
    for (var i = 0; i < n; i++) {
      final j = (i + 1) % n;
      if (_touch(rects[i], rects[j], pad)) {
        a[i] -= step;
        a[j] += step;
        moved = true;
      }
    }
    if (!moved) break;
    rects = build();
  }
  return rects;
}

/// The node box whose centre is at [radius] from the origin at [angle].
_Box _rectAt(double angle, double radius) {
  const w = mindmapNodeWidth, h = mindmapNodeHeight;
  return _Box(
    radius * math.cos(angle) - w / 2,
    radius * math.sin(angle) - h / 2,
    w,
    h,
  );
}

bool _touch(_Box a, _Box b, double pad) =>
    a.left < b.right + pad &&
    b.left < a.right + pad &&
    a.top < b.bottom + pad &&
    b.top < a.bottom + pad;

bool _anyOverlap(List<_Box> rects, double pad) {
  for (var i = 0; i < rects.length; i++) {
    for (var j = i + 1; j < rects.length; j++) {
      if (_touch(rects[i], rects[j], pad)) return true;
    }
  }
  return false;
}

/// Minimal axis-aligned box (this file stays free of Flutter imports).
class _Box {
  final double left, top, width, height;
  const _Box(this.left, this.top, this.width, this.height);
  double get right => left + width;
  double get bottom => top + height;
}

bool _sameOrder(List<String> a, List<String> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Left-to-right tree, goals on the RIGHT: a direction's sub-directions
/// stand in the column(s) to its left, each branch grouped so arrows stay
/// short, parents vertically centred on their branch. [rootId] null lays out
/// the whole graph (every direction that leads to nothing is a root, stacked
/// top to bottom); otherwise only [rootId] and everything that (transitively)
/// leads into it. A direction feeding several goals stands under the parent
/// nearest to a main direction (fewest hops up; ties by name) and its other
/// arrows stay long. Column = longest path to a root, so every arrow points
/// right. Roots and siblings are stacked in the order of [orderHint] (a node's
/// current y; unknown ids go last, by name). Unconnected directions (no
/// relations) form a row below. Positions start at (0, 0); no two overlap.
MindmapPositions treeLayout(
  GrowthGraph graph,
  List<GrowthMetric> metrics, {
  String? rootId,
  Map<String, double> orderHint = const {},
}) {
  const w = mindmapNodeWidth, h = mindmapNodeHeight;
  const rowH = h + 12.0;
  const colW = w + 50.0;
  final byId = {for (final m in metrics) m.id: m};
  if (rootId != null && !byId.containsKey(rootId)) return {};

  // Nodes in scope: everything, or the root and all it (transitively) builds.
  final scope = <String>{};
  if (rootId == null) {
    scope.addAll(byId.keys);
  } else {
    final queue = [rootId];
    while (queue.isNotEmpty) {
      final id = queue.removeLast();
      if (!scope.add(id)) continue;
      queue.addAll(graph.dependsOnOf(id).where(byId.containsKey));
    }
  }
  List<String> parentsOf(String id) => [
    for (final p in graph.leadsToOf(id))
      if (scope.contains(p) && byId.containsKey(p)) p,
  ];
  List<String> childrenOf(String id) => [
    for (final c in graph.dependsOnOf(id))
      if (scope.contains(c) && byId.containsKey(c)) c,
  ];

  int byOrder(String a, String b) {
    final ha = orderHint[a], hb = orderHint[b];
    if (ha != null && hb != null && ha != hb) return ha.compareTo(hb);
    if ((ha == null) != (hb == null)) return ha == null ? 1 : -1;
    return _byName(byId[a]!, byId[b]!);
  }

  // Hops down from the nearest main (or from the root), for choosing the
  // parent a shared direction stands under.
  final dist = <String, int>{};
  final sources = rootId != null
      ? [rootId]
      : [
          for (final id in scope)
            if (byId[id]!.isMain) id,
        ];
  var front = [...sources];
  for (final id in front) {
    dist[id] = 0;
  }
  while (front.isNotEmpty) {
    final next = <String>[];
    for (final id in front) {
      for (final c in childrenOf(id)) {
        if (!dist.containsKey(c)) {
          dist[c] = dist[id]! + 1;
          next.add(c);
        }
      }
    }
    front = next;
  }
  const far = 1 << 30;

  // Column = longest path down from a root (cycles are ignored).
  final col = <String, int>{};
  final onStack = <String>{};
  int columnOf(String id) {
    final known = col[id];
    if (known != null) return known;
    onStack.add(id);
    var c = 0;
    for (final p in parentsOf(id)) {
      if (!onStack.contains(p)) c = math.max(c, columnOf(p) + 1);
    }
    onStack.remove(id);
    return col[id] = c;
  }

  // Each node stands under ONE parent: the nearest to a main direction.
  final kids = <String, List<String>>{};
  final roots = <String>[];
  final isolated = <String>[];
  for (final id in scope) {
    if (!byId.containsKey(id)) continue;
    final parents = parentsOf(id);
    if (parents.isEmpty) {
      if (rootId == id || childrenOf(id).isNotEmpty) {
        roots.add(id);
      } else {
        isolated.add(id);
      }
      continue;
    }
    parents.sort((a, b) {
      final c = (dist[a] ?? far).compareTo(dist[b] ?? far);
      return c != 0 ? c : _byName(byId[a]!, byId[b]!);
    });
    (kids[parents.first] ??= []).add(id);
  }
  roots.sort(byOrder);
  for (final list in kids.values) {
    list.sort(byOrder);
  }

  // Rows: leaves take consecutive rows, a parent is centred on its children.
  final row = <String, double>{};
  var nextRow = 0.0;
  final visited = <String>{};
  double place(String id) {
    visited.add(id);
    final children = [
      for (final c in kids[id] ?? const <String>[])
        if (!visited.contains(c)) c,
    ];
    double y;
    if (children.isEmpty) {
      y = nextRow;
      nextRow += 1;
    } else {
      final ys = [for (final c in children) place(c)];
      y = (ys.first + ys.last) / 2;
    }
    return row[id] = y;
  }

  void layoutRows() {
    row.clear();
    visited.clear();
    nextRow = 0.0;
    for (final r in roots) {
      if (visited.contains(r)) continue;
      place(r);
      nextRow += 0.5; // a little air between separate trees
    }
  }

  // Shorten the arrows that leave a branch (a direction feeding several
  // goals only stands under one): re-order siblings, and roots, by the mean
  // height of everything their subtree is connected to outside itself
  // (barycenter sweeps). Branches with no outside links keep their order.
  final treeParent = <String, String>{
    for (final e in kids.entries)
      for (final c in e.value) c: e.key,
  };
  Set<String> subtreeOf(String id, Set<String> into) {
    if (!into.add(id)) return into;
    for (final c in kids[id] ?? const <String>[]) {
      subtreeOf(c, into);
    }
    return into;
  }

  double keyOf(String id) {
    final members = subtreeOf(id, <String>{});
    final ys = <double>[];
    for (final m in members) {
      for (final o in [...parentsOf(m), ...childrenOf(m)]) {
        if (members.contains(o) || !row.containsKey(o)) continue;
        if (m == id && o == treeParent[id]) continue; // shared by siblings
        ys.add(row[o]!);
      }
    }
    return ys.isEmpty
        ? row[id]!
        : ys.fold<double>(0, (a, b) => a + b) / ys.length;
  }

  layoutRows();
  for (var pass = 0; pass < 8; pass++) {
    var changed = false;
    void reorder(List<String> group) {
      if (group.length < 2) return;
      final keys = {for (final id in group) id: keyOf(id)};
      final before = [...group];
      // Stable: equal keys keep their current order.
      final indexed = [for (var i = 0; i < group.length; i++) (i, group[i])]
        ..sort((x, y) {
          final c = keys[x.$2]!.compareTo(keys[y.$2]!);
          return c != 0 ? c : x.$1.compareTo(y.$1);
        });
      group
        ..clear()
        ..addAll(indexed.map((e) => e.$2));
      if (!_sameOrder(before, group)) changed = true;
    }

    reorder(roots);
    for (final list in kids.values) {
      reorder(list);
    }
    if (!changed) break;
    layoutRows();
  }
  // Members of a loop that no root reaches: treated like unconnected ones.
  for (final id in scope) {
    if (byId.containsKey(id) &&
        !visited.contains(id) &&
        !isolated.contains(id)) {
      isolated.add(id);
    }
  }

  final maxCol = row.keys.fold<int>(0, (m, id) => math.max(m, columnOf(id)));
  final result = <String, (double, double)>{
    for (final e in row.entries)
      e.key: ((maxCol - columnOf(e.key)) * colW, e.value * rowH),
  };

  isolated.sort(byOrder);
  final startRow = row.isEmpty ? 0.0 : nextRow + 0.5;
  for (var i = 0; i < isolated.length; i++) {
    result[isolated[i]] = ((i % 5) * colW, (startRow + i ~/ 5) * rowH);
  }
  return result;
}
