import 'hlc.dart';

/// A directed edge of a graph that must stay acyclic (action chain, growth
/// relations, budget parent / percent links). [hlc] is the clock stamp of the
/// row that holds the edge: the newest edit is the one given up.
class CycleEdge {
  const CycleEdge(this.id, this.from, this.to, this.hlc);
  final String id;
  final String from;
  final String to;
  final String hlc;
}

/// Ids of the edges to remove so that the graph becomes acyclic: while a cycle
/// exists, the newest edge of the first cycle found (nodes and edges visited in
/// id order, so the choice does not depend on input order) is removed.
/// Two devices that merged the same data therefore repair it the same way, and
/// if they repair at different moments the result still converges, because the
/// removals are ordinary synced deletions.
List<String> edgesToBreak(List<CycleEdge> edges) {
  var remaining = edges;
  final removed = <String>[];
  while (true) {
    final core = _cyclicCore(remaining);
    if (core.isEmpty) return removed;
    final cycle = _findCycle(core);
    final victim = cycle.reduce((a, b) => _newer(a, b) ? a : b);
    removed.add(victim.id);
    remaining = [
      for (final e in remaining)
        if (e.id != victim.id) e,
    ];
  }
}

bool _newer(CycleEdge a, CycleEdge b) {
  final c = compareHlc(a.hlc, b.hlc);
  return c != 0 ? c > 0 : a.id.compareTo(b.id) > 0;
}

/// Edges left after peeling off every node with no incoming edge repeatedly:
/// the cycles plus whatever hangs below them. Empty when acyclic.
List<CycleEdge> _cyclicCore(List<CycleEdge> edges) {
  final indegree = <String, int>{};
  final out = <String, List<CycleEdge>>{};
  for (final e in edges) {
    indegree[e.from] ??= 0;
    indegree[e.to] = (indegree[e.to] ?? 0) + 1;
    (out[e.from] ??= []).add(e);
  }
  final ready = [
    for (final n in indegree.entries)
      if (n.value == 0) n.key,
  ];
  while (ready.isNotEmpty) {
    final n = ready.removeLast();
    for (final e in out[n] ?? const <CycleEdge>[]) {
      final d = indegree[e.to]! - 1;
      indegree[e.to] = d;
      if (d == 0) ready.add(e.to);
    }
  }
  return [
    for (final e in edges)
      if (indegree[e.from]! > 0 && indegree[e.to]! > 0) e,
  ];
}

/// The edges of one cycle of [edges], which must contain at least one.
List<CycleEdge> _findCycle(List<CycleEdge> edges) {
  final sorted = [...edges]..sort((a, b) => a.id.compareTo(b.id));
  final adj = <String, List<CycleEdge>>{};
  for (final e in sorted) {
    (adj[e.from] ??= []).add(e);
  }
  final nodes = adj.keys.toList()..sort();
  const white = 0, gray = 1, black = 2;
  final state = <String, int>{};
  for (final start in nodes) {
    if ((state[start] ?? white) != white) continue;
    final stack = <String>[start];
    final next = <int>[0];
    final path = <CycleEdge>[]; // path[i] leads from stack[i] to stack[i + 1]
    state[start] = gray;
    while (stack.isNotEmpty) {
      final node = stack.last;
      final out = adj[node] ?? const <CycleEdge>[];
      if (next.last < out.length) {
        final e = out[next.last++];
        final s = state[e.to] ?? white;
        if (s == white) {
          state[e.to] = gray;
          path.add(e);
          stack.add(e.to);
          next.add(0);
        } else if (s == gray) {
          return [...path.sublist(stack.indexOf(e.to)), e];
        }
      } else {
        state[node] = black;
        stack.removeLast();
        next.removeLast();
        if (path.isNotEmpty) path.removeLast();
      }
    }
  }
  throw StateError('no cycle in a cyclic core');
}
