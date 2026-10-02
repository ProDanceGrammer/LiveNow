import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/data/queries.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/postpone_rules.dart';

void main() {
  late AppDatabase db;
  late ActionService actions;
  late ViewQueries queries;

  setUpAll(initPostponeTimeZoneData);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    actions = ActionService(db);
    queries = ViewQueries(db);
  });

  tearDown(() => db.close());

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
    test(
      'watchCurrentNotDone lists open actions, nearest deadline first',
      () async {
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

        final result = await queries.watchCurrentNotDone(limit: 100).first;
        final ids = result.map((a) => a.id).toList();

        expect(ids, isNot(contains(done)));
        expect(ids, [sooner, later, noDeadline]);
      },
    );

    test('watchCurrentDone lists done actions with their real start/finish time, most recent finish first', () async {
      final open = await actions.createAction(name: 'Still open');

      final firstDone = await actions.createAction(name: 'First done');
      await actions.start(firstDone);
      await actions.finish(firstDone);

      final secondDone = await actions.createAction(name: 'Second done');
      await actions.start(secondDone);
      await actions.finish(secondDone);

      final result = await queries.watchCurrentDone(limit: 100).first;
      final ids = result.map((a) => a.id).toList();

      expect(ids, isNot(contains(open)));
      // Whichever finished last (secondDone) sorts first.
      expect(ids.first, secondDone);

      final item = result.firstWhere((a) => a.id == firstDone);
      expect(item.startAt, isNotNull);
      expect(item.endAt, isNotNull);
    });

    test('watchCurrentNotDone shows a running action as started', () async {
      final running = await actions.createAction(name: 'In progress');
      await actions.start(running);

      final result = await queries.watchCurrentNotDone(limit: 100).first;
      final item = result.firstWhere((a) => a.id == running);

      // start() always resolves some duration (falling back to zero), so
      // end_at is never left null — just possibly equal to start_at.
      expect(item.startAt, isNotNull);
      expect(item.endAt, isNotNull);
    });
  });
}
