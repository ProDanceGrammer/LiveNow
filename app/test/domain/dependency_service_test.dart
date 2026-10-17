import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/dependency_service.dart';

void main() {
  late AppDatabase db;
  late ActionService actions;
  late DependencyService deps;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    actions = ActionService(db);
    deps = DependencyService(db);
  });

  tearDown(() => db.close());

  test('rejects a self-link', () async {
    final a = await actions.createAction(name: 'A');
    expect(
      () => deps.addDependency(predecessorId: a, successorId: a),
      throwsArgumentError,
    );
  });

  test('adding a duplicate edge is a no-op', () async {
    final a = await actions.createAction(name: 'A');
    final b = await actions.createAction(name: 'B');
    await deps.addDependency(predecessorId: a, successorId: b);
    await deps.addDependency(predecessorId: a, successorId: b);

    final rows = await db.select(db.actionDependenciesTable).get();
    expect(rows, hasLength(1));
  });

  test('rejects an edge that would close a cycle', () async {
    final a = await actions.createAction(name: 'A');
    final b = await actions.createAction(name: 'B');
    final c = await actions.createAction(name: 'C');
    // Chain: C -> A -> B
    await deps.addDependency(predecessorId: c, successorId: a);
    await deps.addDependency(predecessorId: a, successorId: b);

    // B -> C would close the loop C -> A -> B -> C.
    expect(
      () => deps.addDependency(predecessorId: b, successorId: c),
      throwsA(isA<DependencyCycleException>()),
    );
  });

  group('edge cases', () {
    Future<Set<String>> edgesOf(String id) async => {
      for (final d in await db.select(db.actionDependenciesTable).get())
        if (d.predecessorId == id || d.successorId == id)
          '${d.predecessorId}>${d.successorId}',
    };

    test('a direct two-way link (A -> B, then B -> A) is rejected', () async {
      final a = await actions.createAction(name: 'A');
      final b = await actions.createAction(name: 'B');
      await deps.addDependency(predecessorId: a, successorId: b);

      await expectLater(
        deps.addDependency(predecessorId: b, successorId: a),
        throwsA(isA<DependencyCycleException>()),
      );
      expect(await db.select(db.actionDependenciesTable).get(), hasLength(1));
    });

    test('a diamond is allowed, closing it back to the top is not', () async {
      final a = await actions.createAction(name: 'A');
      final b = await actions.createAction(name: 'B');
      final c = await actions.createAction(name: 'C');
      final d = await actions.createAction(name: 'D');
      // A -> B -> D and A -> C -> D: two paths to D are not a cycle.
      await deps.addDependency(predecessorId: a, successorId: b);
      await deps.addDependency(predecessorId: a, successorId: c);
      await deps.addDependency(predecessorId: b, successorId: d);
      await deps.addDependency(predecessorId: c, successorId: d);
      expect(await db.select(db.actionDependenciesTable).get(), hasLength(4));

      for (final from in [d]) {
        for (final to in [a, b, c]) {
          await expectLater(
            deps.addDependency(predecessorId: from, successorId: to),
            throwsA(isA<DependencyCycleException>()),
            reason: 'D -> $to',
          );
        }
      }
      // A shortcut that skips ahead (A -> D) is fine.
      await deps.addDependency(predecessorId: a, successorId: d);
      expect(await db.select(db.actionDependenciesTable).get(), hasLength(5));
    });

    test('a long chain still detects the loop at its far end', () async {
      final ids = <String>[
        for (var i = 0; i < 40; i++) await actions.createAction(name: 'A$i'),
      ];
      for (var i = 0; i < ids.length - 1; i++) {
        await deps.addDependency(predecessorId: ids[i], successorId: ids[i + 1]);
      }
      await expectLater(
        deps.addDependency(predecessorId: ids.last, successorId: ids.first),
        throwsA(isA<DependencyCycleException>()),
      );
    });

    test('after Continue, a link back to the source is a cycle', () async {
      final source = await actions.createAction(name: 'Read');
      final later = await actions.createAction(name: 'Report');
      await deps.addDependency(predecessorId: source, successorId: later);

      final created = (await actions.continueSameAction(source)).newActionId;
      // Continue moved source -> later to created -> later.
      expect(await edgesOf(later), {'$created>$later'});

      await expectLater(
        deps.addDependency(predecessorId: created, successorId: source),
        throwsA(isA<DependencyCycleException>()),
      );
      await expectLater(
        deps.addDependency(predecessorId: later, successorId: source),
        throwsA(isA<DependencyCycleException>()),
      );
      await expectLater(
        deps.addDependency(predecessorId: later, successorId: created),
        throwsA(isA<DependencyCycleException>()),
      );
    });

    test('(pinned) deleting an action in the middle does not join its neighbours', () async {
      final a = await actions.createAction(name: 'A');
      final b = await actions.createAction(name: 'B');
      final c = await actions.createAction(name: 'C');
      await deps.addDependency(predecessorId: a, successorId: b);
      await deps.addDependency(predecessorId: b, successorId: c);

      await actions.deleteAction(b);

      // Both links of B are gone; A and C are not linked to each other.
      expect(await db.select(db.actionDependenciesTable).get(), isEmpty);
      expect(await edgesOf(a), isEmpty);
      expect(await edgesOf(c), isEmpty);
    });
  });

  test('removeDependency deletes the edge', () async {
    final a = await actions.createAction(name: 'A');
    final b = await actions.createAction(name: 'B');
    await deps.addDependency(predecessorId: a, successorId: b);
    await deps.removeDependency(predecessorId: a, successorId: b);

    final rows = await db.select(db.actionDependenciesTable).get();
    expect(rows, isEmpty);
  });
}
