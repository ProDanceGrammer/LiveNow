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

  test('removeDependency deletes the edge', () async {
    final a = await actions.createAction(name: 'A');
    final b = await actions.createAction(name: 'B');
    await deps.addDependency(predecessorId: a, successorId: b);
    await deps.removeDependency(predecessorId: a, successorId: b);

    final rows = await db.select(db.actionDependenciesTable).get();
    expect(rows, isEmpty);
  });
}
