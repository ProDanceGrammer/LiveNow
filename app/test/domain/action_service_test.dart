import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/ids.dart';
import 'package:livenow/core/time_codec.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/postpone_rules.dart';

void main() {
  late AppDatabase db;
  late ActionService service;

  setUpAll(initPostponeTimeZoneData);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = ActionService(db);
  });

  tearDown(() => db.close());

  test('createAction links the requested metrics', () async {
    final metricId = newId();
    await db
        .into(db.metricsTable)
        .insert(MetricsTableCompanion.insert(id: metricId, name: 'Health'));

    final actionId = await service.createAction(
      name: 'Go for a run',
      kind: 'habit',
      metricIds: [metricId],
    );

    final links = await (db.select(
      db.actionMetricsTable,
    )..where((t) => t.actionId.equals(actionId))).get();
    expect(links, hasLength(1));
    expect(links.single.metricId, metricId);
  });

  test(
    'starting again while already running updates the same occurrence, not a duplicate',
    () async {
      final actionId = await service.createAction(name: 'Write my book');
      await service.start(actionId);
      await service.start(actionId);

      final running = await (db.select(
        db.actionOccurrencesTable,
      )..where((t) => t.actionId.equals(actionId))).get();
      expect(running, hasLength(1));
      expect(running.single.finishedAt, isNull);
    },
  );

  test('starting again while already running still moves start_at to now', () async {
    final actionId = await service.createAction(name: 'Write my book');
    await service.start(actionId);

    // Force start_at into the past, as if Start had been pressed a while
    // ago and never touched since.
    await (db.update(
      db.actionsTable,
    )..where((t) => t.id.equals(actionId))).write(
      ActionsTableCompanion(
        startAt: Value(dateTimeToDb(DateTime.utc(2020, 1, 1))!),
      ),
    );

    final before = DateTime.now().toUtc();
    await service.start(actionId);
    final after = DateTime.now().toUtc();

    final action = await (db.select(
      db.actionsTable,
    )..where((t) => t.id.equals(actionId))).getSingle();
    final startAt = dateTimeFromDb(action.startAt)!;
    expect(startAt.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
    expect(startAt.isBefore(after.add(const Duration(seconds: 1))), isTrue);
  });

  test('start defaults to a 60-minute duration for a task with no time set at all', () async {
    final actionId = await service.createAction(name: 'Totally unscheduled');
    await service.start(actionId);

    final action = await (db.select(
      db.actionsTable,
    )..where((t) => t.id.equals(actionId))).getSingle();
    final startAt = dateTimeFromDb(action.startAt)!;
    final endAt = dateTimeFromDb(action.endAt)!;
    expect(endAt.difference(startAt), const Duration(minutes: 60));
  });

  test('start defaults to a 10-minute duration for a habit with no time set at all', () async {
    final actionId = await service.createAction(
      name: 'Totally unscheduled habit',
      kind: 'habit',
    );
    await service.start(actionId);

    final action = await (db.select(
      db.actionsTable,
    )..where((t) => t.id.equals(actionId))).getSingle();
    final startAt = dateTimeFromDb(action.startAt)!;
    final endAt = dateTimeFromDb(action.endAt)!;
    expect(endAt.difference(startAt), const Duration(minutes: 10));
  });

  test('start sets start_at to the real start time, not just the occurrence', () async {
    final actionId = await service.createAction(name: 'Unscheduled task');
    final before = DateTime.now().toUtc();
    await service.start(actionId);
    final after = DateTime.now().toUtc();

    final action = await (db.select(
      db.actionsTable,
    )..where((t) => t.id.equals(actionId))).getSingle();
    final startAt = DateTime.parse(action.startAt!);
    expect(startAt.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
    expect(startAt.isBefore(after.add(const Duration(seconds: 1))), isTrue);
  });

  test('start carries an existing duration onto the new start', () async {
    final actionId = await service.createAction(
      name: 'Scheduled meeting',
      startAt: DateTime.utc(2024, 1, 1, 9),
      endAt: DateTime.utc(2024, 1, 1, 10, 30),
    );
    await service.start(actionId);

    final action = await (db.select(
      db.actionsTable,
    )..where((t) => t.id.equals(actionId))).getSingle();
    final startAt = DateTime.parse(action.startAt!);
    final endAt = DateTime.parse(action.endAt!);
    expect(endAt.difference(startAt), const Duration(hours: 1, minutes: 30));
  });

  test('finish sets end_at to the real finish time', () async {
    final actionId = await service.createAction(name: 'Quick task');
    await service.start(actionId);
    final before = DateTime.now().toUtc();
    await service.finish(actionId);
    final after = DateTime.now().toUtc();

    final action = await (db.select(
      db.actionsTable,
    )..where((t) => t.id.equals(actionId))).getSingle();
    final endAt = DateTime.parse(action.endAt!);
    expect(endAt.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
    expect(endAt.isBefore(after.add(const Duration(seconds: 1))), isTrue);
  });

  test(
    'finishing a never-started, 0-duration action scheduled for the future sets both times to now',
    () async {
      // A point action (start == end already), scheduled ahead of "now";
      // finishing it without ever pressing Start means "this just
      // happened, right now" — 0 minutes, not the stale scheduled time.
      final futureStart = DateTime.now().toUtc().add(const Duration(hours: 2));
      final actionId = await service.createAction(
        name: 'Instant thing',
        startAt: futureStart,
        endAt: futureStart,
      );

      final before = DateTime.now().toUtc();
      await service.finish(actionId);
      final after = DateTime.now().toUtc();

      final action = await (db.select(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).getSingle();
      final startAt = dateTimeFromDb(action.startAt)!;
      final endAt = dateTimeFromDb(action.endAt)!;
      expect(startAt, endAt);
      expect(startAt.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
      expect(startAt.isBefore(after.add(const Duration(seconds: 1))), isTrue);
    },
  );

  test(
    'finishing a never-started, 90-minute action scheduled for the future projects the start backward from now',
    () async {
      // Scheduled +3h -> +4h30m (90 min) from now, never actually started;
      // finishing it "now" should read as "90 minutes ago -> now", not
      // "some still-future time -> now".
      final futureStart = DateTime.now().toUtc().add(const Duration(hours: 3));
      final actionId = await service.createAction(
        name: 'Ninety minute task',
        startAt: futureStart,
        endAt: futureStart.add(const Duration(minutes: 90)),
      );

      final beforeFinish = DateTime.now().toUtc();
      await service.finish(actionId);

      final action = await (db.select(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).getSingle();
      final startAt = dateTimeFromDb(action.startAt)!;
      final endAt = dateTimeFromDb(action.endAt)!;
      expect(endAt.difference(startAt), const Duration(hours: 1, minutes: 30));
      // end_at is "now", so it must be at/after whatever "now" was just
      // before we called finish.
      expect(
        endAt.isAfter(beforeFinish.subtract(const Duration(seconds: 1))),
        isTrue,
      );
    },
  );

  test(
    'finishing an action whose start is already in the past keeps it, even without ever pressing Start',
    () async {
      // Mirrors the original "Finished Now" formula exactly: a start that's
      // already at/before now is trusted as real, whether it got there via
      // the Start button or a manual edit (e.g. the board's tap-to-edit
      // time dialog).
      final pastStart = DateTime.now().toUtc().subtract(
        const Duration(hours: 1),
      );
      final actionId = await service.createAction(
        name: 'Manually backdated',
        startAt: pastStart,
      );

      await service.finish(actionId);

      final action = await (db.select(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).getSingle();
      expect(dateTimeFromDb(action.startAt), pastStart);
    },
  );

  test(
    'finishing an action that was actually started leaves its real start_at alone',
    () async {
      final futureStart = DateTime.now().toUtc().add(const Duration(hours: 1));
      final actionId = await service.createAction(
        name: 'Actually worked on',
        startAt: futureStart,
        endAt: futureStart.add(const Duration(minutes: 90)),
      );
      await service.start(actionId); // real start_at is now "now"

      final action = await (db.select(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).getSingle();
      final realStart = action.startAt;

      await service.finish(actionId);

      final finished = await (db.select(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).getSingle();
      expect(finished.startAt, realStart); // untouched by finish
    },
  );

  test(
    'start prefers Estimated minutes over the existing start/end gap',
    () async {
      final actionId = await service.createAction(
        name: 'Has both an estimate and a stale gap',
        startAt: DateTime.utc(2024, 1, 1, 9),
        endAt: DateTime.utc(2024, 1, 1, 9, 15), // a stale 15-minute gap
        estimatedMinutes: 45,
      );

      await service.start(actionId);

      final action = await (db.select(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).getSingle();
      final startAt = dateTimeFromDb(action.startAt)!;
      final endAt = dateTimeFromDb(action.endAt)!;
      expect(endAt.difference(startAt), const Duration(minutes: 45));
    },
  );

  test('updateSchedule sets exactly start_at/end_at and nothing else', () async {
    final actionId = await service.createAction(name: 'Reschedule me');
    await service.updateSchedule(
      actionId,
      startAt: DateTime.utc(2025, 3, 4, 8),
      endAt: DateTime.utc(2025, 3, 4, 9),
    );

    final action = await (db.select(
      db.actionsTable,
    )..where((t) => t.id.equals(actionId))).getSingle();
    expect(dateTimeFromDb(action.startAt), DateTime.utc(2025, 3, 4, 8));
    expect(dateTimeFromDb(action.endAt), DateTime.utc(2025, 3, 4, 9));
    expect(action.status, 'open');
  });

  test(
    'postponing a started action shifts from its real start, e.g. 18:43 + 1h = 19:43',
    () async {
      final actionId = await service.createAction(name: 'Deep work');
      await service.start(actionId);

      // Force start_at to a known value, as if it had actually been
      // started at 18:43 (independent of whatever time the test runs at).
      await (db.update(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).write(
        ActionsTableCompanion(
          startAt: Value(dateTimeToDb(DateTime.utc(2024, 1, 1, 15, 43))!), // 18:43 Istanbul
        ),
      );

      await service.postpone(actionId, PostponeRule.plusOneHour);

      final action = await (db.select(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).getSingle();
      expect(
        dateTimeFromDb(action.startAt),
        DateTime.utc(2024, 1, 1, 16, 43),
      );
    },
  );

  test(
    'postponing a running action also moves its open occurrence, so the editor stays in sync with the card',
    () async {
      final actionId = await service.createAction(name: 'Deep work');
      await service.start(actionId);

      await (db.update(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).write(
        ActionsTableCompanion(
          startAt: Value(dateTimeToDb(DateTime.utc(2024, 1, 1, 15, 43))!), // 18:43 Istanbul
        ),
      );

      await service.postpone(actionId, PostponeRule.plusOneHour);

      final occurrence = await (db.select(
        db.actionOccurrencesTable,
      )..where((t) => t.actionId.equals(actionId) & t.finishedAt.isNull())).getSingle();
      expect(
        dateTimeFromDb(occurrence.startedAt),
        DateTime.utc(2024, 1, 1, 16, 43),
      );
    },
  );

  test(
    'finishing a running occurrence whose start was postponed into the '
    'future re-syncs the occurrence\'s started_at, so it never ends up '
    'finished before it started',
    () async {
      final actionId = await service.createAction(name: 'Fresh 60min test');
      await service.start(actionId);

      // Simulate a postpone that pushed start_at (and end_at, by the same
      // delta, preserving duration) ahead of "now" while the occurrence was
      // still running — postpone() already keeps the occurrence's
      // started_at in sync with this, per the test above — then Finish is
      // pressed before "now" catches up to that pushed time, so finish()
      // must back-project a fresh start rather than trusting the
      // still-future one.
      final before = await (db.select(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).getSingle();
      final originalStart = dateTimeFromDb(before.startAt)!;
      final originalEnd = dateTimeFromDb(before.endAt)!;
      const delta = Duration(hours: 5);
      final newStart = originalStart.add(delta);
      final newEnd = originalEnd.add(delta);

      await (db.update(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).write(
        ActionsTableCompanion(
          startAt: Value(dateTimeToDb(newStart)!),
          endAt: Value(dateTimeToDb(newEnd)!),
        ),
      );
      await (db.update(
        db.actionOccurrencesTable,
      )..where((t) => t.actionId.equals(actionId))).write(
        ActionOccurrencesTableCompanion(startedAt: Value(dateTimeToDb(newStart)!)),
      );

      await service.finish(actionId);

      final action = await (db.select(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).getSingle();
      final occurrence = await (db.select(
        db.actionOccurrencesTable,
      )..where((t) => t.actionId.equals(actionId))).getSingle();

      // The card's actions.start_at and the editor's occurrence.started_at
      // must always agree, and neither may show a start after the finish.
      expect(occurrence.startedAt, action.startAt);
      final startAt = dateTimeFromDb(action.startAt)!;
      final endAt = dateTimeFromDb(action.endAt)!;
      expect(startAt.isAfter(endAt), isFalse);
    },
  );

  test('snapshot/restore round-trips an action and its occurrence history', () async {
    final actionId = await service.createAction(name: 'Undo me');
    await service.start(actionId);

    final before = await service.snapshot(actionId);

    await service.finish(actionId);
    var action = await (db.select(
      db.actionsTable,
    )..where((t) => t.id.equals(actionId))).getSingle();
    expect(action.status, 'done');

    await service.restore(before);

    action = await (db.select(
      db.actionsTable,
    )..where((t) => t.id.equals(actionId))).getSingle();
    expect(action.status, 'open');

    final occurrences = await (db.select(
      db.actionOccurrencesTable,
    )..where((t) => t.actionId.equals(actionId))).get();
    expect(occurrences, hasLength(1));
    expect(occurrences.single.finishedAt, isNull); // running again, not done
  });

  test('finish on a task marks it done and closes the occurrence', () async {
    final actionId = await service.createAction(name: 'Pay electricity bill');
    await service.start(actionId);
    await service.finish(actionId);

    final action = await (db.select(
      db.actionsTable,
    )..where((t) => t.id.equals(actionId))).getSingle();
    expect(action.status, 'done');
    expect(action.completedAt, isNotNull);

    final occurrence = await (db.select(
      db.actionOccurrencesTable,
    )..where((t) => t.actionId.equals(actionId))).getSingle();
    expect(occurrence.outcome, 'done');
    expect(occurrence.finishedAt, isNotNull);
  });

  test('finish on a habit closes the occurrence but keeps it open', () async {
    final actionId = await service.createAction(name: 'Pray', kind: 'habit');
    await service.start(actionId);
    await service.finish(actionId);

    final action = await (db.select(
      db.actionsTable,
    )..where((t) => t.id.equals(actionId))).getSingle();
    expect(action.status, 'open');
    expect(action.completedAt, isNull);
  });

  test('starting a done action reopens it', () async {
    final actionId = await service.createAction(name: 'Redo this');
    await service.start(actionId);
    await service.finish(actionId);

    var action = await (db.select(
      db.actionsTable,
    )..where((t) => t.id.equals(actionId))).getSingle();
    expect(action.status, 'done');

    await service.start(actionId);

    action = await (db.select(
      db.actionsTable,
    )..where((t) => t.id.equals(actionId))).getSingle();
    expect(action.status, 'open');
    expect(action.completedAt, isNull);
  });

  test(
    'starting an action stuck as done-while-running self-heals to open',
    () async {
      // Simulates the state a pre-fix build could leave behind: an open
      // occurrence (still running) but status wrongly stuck at 'done'.
      final actionId = await service.createAction(name: 'Weird state');
      await service.start(actionId);
      await (db.update(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).write(
        const ActionsTableCompanion(status: Value('done')),
      );

      await service.start(actionId);

      final action = await (db.select(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).getSingle();
      expect(action.status, 'open');

      final occurrences = await (db.select(
        db.actionOccurrencesTable,
      )..where((t) => t.actionId.equals(actionId))).get();
      expect(occurrences, hasLength(1)); // no duplicate occurrence created
    },
  );

  test('starting a cancelled action reopens it', () async {
    final actionId = await service.createAction(name: 'Reconsidering');
    await service.cancel(actionId);

    await service.start(actionId);

    final action = await (db.select(
      db.actionsTable,
    )..where((t) => t.id.equals(actionId))).getSingle();
    expect(action.status, 'open');
  });

  test('cancel marks the action cancelled', () async {
    final actionId = await service.createAction(name: 'Old idea');
    await service.cancel(actionId);

    final action = await (db.select(
      db.actionsTable,
    )..where((t) => t.id.equals(actionId))).getSingle();
    expect(action.status, 'cancelled');
  });

  test('postpone on a task updates the schedule without an occurrence log', () async {
    final actionId = await service.createAction(
      name: 'Send out resumes',
      startAt: DateTime.utc(2024, 1, 1, 9),
      endAt: DateTime.utc(2024, 1, 1, 10),
    );
    await service.postpone(actionId, PostponeRule.plusOneHour);

    final action = await (db.select(
      db.actionsTable,
    )..where((t) => t.id.equals(actionId))).getSingle();
    expect(action.startAt, isNot(DateTime.utc(2024, 1, 1, 9).toIso8601String()));

    final occurrences = await (db.select(
      db.actionOccurrencesTable,
    )..where((t) => t.actionId.equals(actionId))).get();
    expect(occurrences, isEmpty);
  });

  test('postpone on a habit also logs a postponed occurrence', () async {
    final actionId = await service.createAction(
      name: 'Stretching',
      kind: 'habit',
      startAt: DateTime.utc(2024, 1, 1, 9),
    );
    await service.postpone(actionId, PostponeRule.nextWeek);

    final occurrences = await (db.select(
      db.actionOccurrencesTable,
    )..where((t) => t.actionId.equals(actionId))).get();
    expect(occurrences, hasLength(1));
    expect(occurrences.single.outcome, 'postponed');
  });

  test('createFromTemplate instantiates a new action from the payload', () async {
    final templateId = newId();
    await db
        .into(db.actionTemplatesTable)
        .insert(
          ActionTemplatesTableCompanion.insert(
            id: templateId,
            name: 'Prepare for interview',
            payload: jsonEncode({
              'name': 'Prepare for interview',
              'kind': 'task',
              'priority': 'B1',
            }),
          ),
        );

    final actionId = await service.createFromTemplate(templateId);
    expect(actionId, isNot(templateId));

    final action = await (db.select(
      db.actionsTable,
    )..where((t) => t.id.equals(actionId))).getSingle();
    expect(action.name, 'Prepare for interview');
    expect(action.priority, 'B1');
  });
}
