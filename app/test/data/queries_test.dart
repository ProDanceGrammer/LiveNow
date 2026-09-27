import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/ids.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/data/queries.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/dependency_service.dart';
import 'package:livenow/domain/postpone_rules.dart';

void main() {
  late AppDatabase db;
  late ActionService actions;
  late DependencyService deps;
  late ViewQueries queries;

  setUpAll(initPostponeTimeZoneData);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    actions = ActionService(db);
    deps = DependencyService(db);
    queries = ViewQueries(db);
  });

  tearDown(() => db.close());

  test('watchOperational only returns today\'s timed, open actions', () async {
    final now = DateTime.utc(2024, 1, 1, 9); // 12:00 Istanbul
    final today = await actions.createAction(
      name: 'Today',
      startAt: DateTime.utc(2024, 1, 1, 10),
    );
    await actions.createAction(
      name: 'Tomorrow',
      startAt: DateTime.utc(2024, 1, 2, 10),
    );
    await actions.createAction(
      name: 'All day today',
      startAt: DateTime.utc(2024, 1, 1, 10),
      isAllDay: true,
    );

    final result = await queries.watchOperational(referenceUtc: now).first;
    expect(result.map((a) => a.id), [today]);
  });

  test('watchTodo excludes tasks whose predecessor is unscheduled', () async {
    final blocked = await actions.createAction(name: 'Blocked');
    final blocker = await actions.createAction(name: 'Blocker');
    await deps.addDependency(predecessorId: blocker, successorId: blocked);

    var todo = await queries.watchTodo().first;
    expect(todo.map((a) => a.id), isNot(contains(blocked)));

    await actions.createAction(
      name: 'schedule the blocker',
    ); // no-op, just noise
    await (db.update(
      db.actionsTable,
    )..where((t) => t.id.equals(blocker))).write(
      const ActionsTableCompanion(startAt: Value('2024-01-01T00:00:00.000000Z')),
    );

    todo = await queries.watchTodo().first;
    expect(todo.map((a) => a.id), contains(blocked));
  });

  test(
    'watchMostImportant excludes actions with an undone predecessor and ranks by weight',
    () async {
      final metricId = newId();
      await db
          .into(db.metricsTable)
          .insert(
            MetricsTableCompanion.insert(id: metricId, name: 'Health', weight: const Value(5)),
          );

      final done = await actions.createAction(name: 'Done predecessor');
      await actions.finish(done);
      final undone = await actions.createAction(name: 'Undone predecessor');

      final readyLowWeight = await actions.createAction(name: 'Ready, no metric');
      await deps.addDependency(predecessorId: done, successorId: readyLowWeight);

      final readyHighWeight = await actions.createAction(
        name: 'Ready, weighted',
        metricIds: [metricId],
      );

      final blocked = await actions.createAction(name: 'Blocked');
      await deps.addDependency(predecessorId: undone, successorId: blocked);

      final result = await queries.watchMostImportant().first;
      final ids = result.map((a) => a.id).toList();

      expect(ids, isNot(contains(blocked)));
      expect(ids.indexOf(readyHighWeight), lessThan(ids.indexOf(readyLowWeight)));
    },
  );

  test('watchCalendarWeek filters by range and excludes habits', () async {
    final inWeek = await actions.createAction(
      name: 'In week',
      startAt: DateTime.utc(2024, 1, 2),
    );
    await actions.createAction(
      name: 'Out of week',
      startAt: DateTime.utc(2024, 1, 10),
    );
    await actions.createAction(
      name: 'Habit in week',
      kind: 'habit',
      startAt: DateTime.utc(2024, 1, 2),
    );

    final result = await queries
        .watchCalendarWeek(
          weekStartUtc: DateTime.utc(2024, 1, 1),
          weekEndUtc: DateTime.utc(2024, 1, 8),
        )
        .first;
    expect(result.map((a) => a.id), [inWeek]);
  });

  test('watchHabits returns only open habits', () async {
    final habit = await actions.createAction(name: 'Pray', kind: 'habit');
    final task = await actions.createAction(name: 'Task');
    final doneHabit = await actions.createAction(name: 'Sleep', kind: 'habit');
    await actions.finish(doneHabit); // habits stay 'open' though; cancel instead
    await actions.cancel(doneHabit);

    final result = await queries.watchHabits().first;
    final ids = result.map((a) => a.id).toList();
    expect(ids, contains(habit));
    expect(ids, isNot(contains(task)));
    expect(ids, isNot(contains(doneHabit)));
  });
}
