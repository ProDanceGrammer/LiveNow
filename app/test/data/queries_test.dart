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

  test(
    'watchMostImportant excludes a successor whose predecessor is a '
    'not-done all-day action (manual done flag, not a time comparison)',
    () async {
      final notDoneAllDay = await actions.createAction(
        name: 'All-day, not done',
        startAt: DateTime.utc(2024, 1, 1),
        isAllDay: true,
      );
      final blocked = await actions.createAction(name: 'Blocked');
      await deps.addDependency(
        predecessorId: notDoneAllDay,
        successorId: blocked,
      );

      final doneAllDay = await actions.createAction(
        name: 'All-day, done',
        startAt: DateTime.utc(2024, 1, 1),
        isAllDay: true,
      );
      await actions.finish(doneAllDay);
      final ready = await actions.createAction(name: 'Ready');
      await deps.addDependency(predecessorId: doneAllDay, successorId: ready);

      final result = await queries.watchMostImportant().first;
      final ids = result.map((a) => a.id).toList();

      expect(ids, isNot(contains(blocked)));
      expect(ids, contains(ready));
    },
  );

  test(
    'watchMostImportant excludes a successor whose timed predecessor is '
    'still scheduled ahead of now',
    () async {
      final future = DateTime.now().toUtc().add(const Duration(days: 30));
      final stillAhead = await actions.createAction(
        name: 'Scheduled far ahead',
        startAt: future,
        endAt: future.add(const Duration(hours: 1)),
      );
      final blocked = await actions.createAction(name: 'Blocked');
      await deps.addDependency(predecessorId: stillAhead, successorId: blocked);

      final result = await queries.watchMostImportant().first;
      expect(result.map((a) => a.id), isNot(contains(blocked)));
    },
  );

  test('watchCalendarWeek filters by range', () async {
    final inWeek = await actions.createAction(
      name: 'In week',
      startAt: DateTime.utc(2024, 1, 2),
    );
    await actions.createAction(
      name: 'Out of week',
      startAt: DateTime.utc(2024, 1, 10),
    );

    final result = await queries
        .watchCalendarWeek(
          weekStartUtc: DateTime.utc(2024, 1, 1),
          weekEndUtc: DateTime.utc(2024, 1, 8),
        )
        .first;
    expect(result.map((a) => a.id), [inWeek]);
  });

  test(
    'watchCalendarWeek keeps all-day, done and range-overlapping rows',
    () async {
      final allDay = await actions.createAction(
        name: 'All day',
        startAt: DateTime.utc(2024, 1, 2),
        isAllDay: true,
      );
      final done = await actions.createAction(
        name: 'Done',
        startAt: DateTime.utc(2024, 1, 3, 10),
        endAt: DateTime.utc(2024, 1, 3, 11),
      );
      await actions.finish(done); // marks done (end_at becomes "now")
      await actions.updateSchedule(
        done,
        startAt: DateTime.utc(2024, 1, 3, 10),
        endAt: DateTime.utc(2024, 1, 3, 11),
      );
      final spanning = await actions.createAction(
        name: 'Starts before the range, ends inside',
        startAt: DateTime.utc(2023, 12, 31, 22),
        endAt: DateTime.utc(2024, 1, 1, 2),
      );
      await actions.createAction(
        name: 'Ends exactly at range start',
        startAt: DateTime.utc(2023, 12, 31, 22),
        endAt: DateTime.utc(2024, 1, 1),
      );
      await actions.createAction(
        name: 'Starts exactly at range end',
        startAt: DateTime.utc(2024, 1, 8),
      );

      final result = await queries
          .watchCalendarWeek(
            weekStartUtc: DateTime.utc(2024, 1, 1),
            weekEndUtc: DateTime.utc(2024, 1, 8),
          )
          .first;
      expect(result.map((a) => a.id).toSet(), {allDay, done, spanning});
    },
  );

  group('Current Actions board', () {
    test('watchCurrentNotDone lists open actions, nearest deadline first', () async {
      final noDeadline = await actions.createAction(name: 'Someday');
      final later = await actions.createAction(
        name: 'Later',
        startAt: DateTime.utc(2024, 1, 10),
      );
      final sooner = await actions.createAction(
        name: 'Sooner',
        startAt: DateTime.utc(2024, 1, 2),
      );
      final done = await actions.createAction(name: 'Already done');
      await actions.finish(done);

      final result = await queries.watchCurrentNotDone().first;
      final ids = result.map((a) => a.id).toList();

      expect(ids, isNot(contains(done)));
      expect(ids, [sooner, later, noDeadline]);
    });

    test(
      'watchCurrentDone lists done actions with their real start/finish time, most recent finish first',
      () async {
        final open = await actions.createAction(name: 'Still open');

        final firstDone = await actions.createAction(name: 'First done');
        await actions.start(firstDone);
        await actions.finish(firstDone);

        final secondDone = await actions.createAction(name: 'Second done');
        await actions.start(secondDone);
        await actions.finish(secondDone);

        final result = await queries.watchCurrentDone().first;
        final ids = result.map((a) => a.id).toList();

        expect(ids, isNot(contains(open)));
        // Whichever finished last (secondDone) sorts first.
        expect(ids.first, secondDone);

        final item = result.firstWhere((a) => a.id == firstDone);
        expect(item.startAt, isNotNull);
        expect(item.endAt, isNotNull);
      },
    );

    test('watchCurrentNotDone shows a running action as started', () async {
      final running = await actions.createAction(name: 'In progress');
      await actions.start(running);

      final result = await queries.watchCurrentNotDone().first;
      final item = result.firstWhere((a) => a.id == running);

      // start() always resolves some duration (falling back to zero), so
      // end_at is never left null — just possibly equal to start_at.
      expect(item.startAt, isNotNull);
      expect(item.endAt, isNotNull);
    });
  });
}
