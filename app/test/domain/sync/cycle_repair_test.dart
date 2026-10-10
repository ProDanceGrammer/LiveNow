import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/sync/cycle_repair.dart';
import 'package:livenow/domain/sync/hlc.dart';

CycleEdge e(String id, String from, String to, [String hlc = 'h0']) =>
    CycleEdge(id, from, to, hlc);

void main() {
  group('hlc', () {
    test('string order is clock order', () {
      const a = '2026-10-10T12:00:00.123Z-0000-aa';
      const b = '2026-10-10T12:00:00.123Z-0001-aa';
      const c = '2026-10-10T12:00:00.124Z-0000-aa';
      expect(compareHlc(a, b), lessThan(0));
      expect(compareHlc(b, c), lessThan(0));
      expect(compareHlc(a, a), 0);
    });

    test('parse gives wall time and counter', () {
      final p = parseHlc('2026-10-10T12:00:00.123Z-00ff-3a4b5c');
      expect(p.wall, '2026-10-10T12:00:00.123Z');
      expect(p.counter, 255);
    });

    test('a seeded stamp parses too', () {
      final p = parseHlc('1970-01-01T00:00:00.000Z-0000-seed');
      expect(p.counter, 0);
    });

    test('garbage is rejected', () {
      expect(() => parseHlc('nope'), throwsFormatException);
    });
  });

  group('edgesToBreak', () {
    test('an acyclic graph loses nothing', () {
      expect(
        edgesToBreak([e('1', 'a', 'b'), e('2', 'b', 'c'), e('3', 'a', 'c')]),
        isEmpty,
      );
    });

    test('a two-node loop drops the newest edge', () {
      expect(edgesToBreak([e('1', 'a', 'b', 'h1'), e('2', 'b', 'a', 'h2')]), [
        '2',
      ]);
    });

    test('equal stamps: the higher id goes', () {
      expect(edgesToBreak([e('1', 'a', 'b'), e('2', 'b', 'a')]), ['2']);
    });

    test('a self loop is a cycle', () {
      expect(edgesToBreak([e('1', 'a', 'a')]), ['1']);
    });

    test('a long loop with a tail only loses one edge of the loop', () {
      final edges = [
        e('t', 'x', 'a', 'h9'), // a tail into the loop, newest of all
        e('1', 'a', 'b', 'h1'),
        e('2', 'b', 'c', 'h5'),
        e('3', 'c', 'a', 'h2'),
        e('4', 'c', 'z', 'h8'), // a branch out of the loop
      ];
      expect(edgesToBreak(edges), ['2']);
    });

    test('two separate loops each lose one edge', () {
      final removed = edgesToBreak([
        e('1', 'a', 'b', 'h1'),
        e('2', 'b', 'a', 'h2'),
        e('3', 'c', 'd', 'h3'),
        e('4', 'd', 'c', 'h4'),
      ]);
      expect(removed.toSet(), {'2', '4'});
    });

    test(
      'two loops sharing an edge: result is acyclic and order independent',
      () {
        final edges = [
          e('1', 'a', 'b', 'h1'),
          e('2', 'b', 'a', 'h5'),
          e('3', 'b', 'c', 'h2'),
          e('4', 'c', 'a', 'h3'),
        ];
        final first = edgesToBreak(edges);
        final second = edgesToBreak(edges.reversed.toList());
        expect(first.toSet(), second.toSet());
        final left = edges.where((x) => !first.contains(x.id)).toList();
        expect(edgesToBreak(left), isEmpty);
      },
    );
  });
}
