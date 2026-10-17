import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/ids.dart';
import 'package:livenow/core/time_codec.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:timezone/timezone.dart' as tz;

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
      metricIds: [metricId],
    );

    final links = await (db.select(
      db.actionMetricsTable,
    )..where((t) => t.actionId.equals(actionId))).get();
    expect(links, hasLength(1));
    expect(links.single.metricId, metricId);
  });

  test('starting again while already running updates the same occurrence, not a duplicate', () async {
    final actionId = await service.createAction(name: 'Write my book');
    await service.start(actionId);
    await service.start(actionId);

    final running = await (db.select(
      db.actionOccurrencesTable,
    )..where((t) => t.actionId.equals(actionId))).get();
    expect(running, hasLength(1));
    expect(running.single.finishedAt, isNull);
  });

  test(
    'starting again while already running still moves start_at to now',
    () async {
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
      expect(
        startAt.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(startAt.isBefore(after.add(const Duration(seconds: 1))), isTrue);
    },
  );

  test(
    'start defaults to a 60-minute duration for a task with no time set at all',
    () async {
      final actionId = await service.createAction(name: 'Totally unscheduled');
      await service.start(actionId);

      final action = await (db.select(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).getSingle();
      final startAt = dateTimeFromDb(action.startAt)!;
      final endAt = dateTimeFromDb(action.endAt)!;
      expect(endAt.difference(startAt), const Duration(minutes: 60));
    },
  );

  test(
    'start sets start_at to the real start time, not just the occurrence',
    () async {
      final actionId = await service.createAction(name: 'Unscheduled task');
      final before = DateTime.now().toUtc();
      await service.start(actionId);
      final after = DateTime.now().toUtc();

      final action = await (db.select(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).getSingle();
      final startAt = DateTime.parse(action.startAt!);
      expect(
        startAt.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(startAt.isBefore(after.add(const Duration(seconds: 1))), isTrue);
    },
  );

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

  test('finishing a never-started, 0-duration action scheduled for the future sets both times to now', () async {
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
    expect(
      startAt.isAfter(before.subtract(const Duration(seconds: 1))),
      isTrue,
    );
    expect(startAt.isBefore(after.add(const Duration(seconds: 1))), isTrue);
  });

  test('finishing a never-started, 90-minute action scheduled for the future projects the start backward from now', () async {
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
  });

  test('finishing an action whose start is already in the past keeps it, even without ever pressing Start', () async {
    // Mirrors the original "Finished Now" formula exactly: a start that's
    // already at/before now is trusted as real, whether it got there via
    // the Start button or a manual edit (e.g. the board's tap-to-edit
    // time dialog).
    final pastStart = DateTime.now().toUtc().subtract(const Duration(hours: 1));
    final actionId = await service.createAction(
      name: 'Manually backdated',
      startAt: pastStart,
    );

    await service.finish(actionId);

    final action = await (db.select(
      db.actionsTable,
    )..where((t) => t.id.equals(actionId))).getSingle();
    expect(dateTimeFromDb(action.startAt), pastStart);
  });

  test('finishing an action that was actually started leaves its real start_at alone', () async {
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
  });

  test(
    'start keeps the existing start/end gap over a legacy estimate',
    () async {
      final actionId = await service.createAction(
        name: 'Has both a legacy estimate and a gap',
        startAt: DateTime.utc(2024, 1, 1, 9),
        endAt: DateTime.utc(2024, 1, 1, 9, 45), // a 45-minute gap
        estimatedMinutes: 15,
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

  test(
    'updateSchedule sets exactly start_at/end_at and nothing else',
    () async {
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
      expect(action.estimatedMinutes, isNull);
      expect(action.done, false);
    },
  );

  test(
    'updateSchedule keeps the running occurrence started_at in sync',
    () async {
      final actionId = await service.createAction(name: 'Deep work');
      await service.start(actionId);

      final newStart = DateTime.utc(2025, 3, 4, 8);
      await service.updateSchedule(
        actionId,
        startAt: newStart,
        endAt: DateTime.utc(2025, 3, 4, 9),
      );

      final occurrence = await (db.select(
        db.actionOccurrencesTable,
      )..where((t) => t.actionId.equals(actionId))).getSingle();
      expect(dateTimeFromDb(occurrence.startedAt), newStart);
      expect(occurrence.finishedAt, isNull);
    },
  );

  test('postponing a started action shifts from its real start, e.g. 18:43 + 1h = 19:43', () async {
    final actionId = await service.createAction(name: 'Deep work');
    await service.start(actionId);

    // Force start_at to a known value, as if it had actually been
    // started at 18:43 (independent of whatever time the test runs at).
    await (db.update(
      db.actionsTable,
    )..where((t) => t.id.equals(actionId))).write(
      ActionsTableCompanion(
        startAt: Value(
          dateTimeToDb(DateTime.utc(2024, 1, 1, 15, 43))!,
        ), // 18:43 Istanbul
      ),
    );

    await service.postpone(actionId, PostponeRule.plusOneHour);

    final action = await (db.select(
      db.actionsTable,
    )..where((t) => t.id.equals(actionId))).getSingle();
    expect(dateTimeFromDb(action.startAt), DateTime.utc(2024, 1, 1, 16, 43));
  });

  test('postponing a running action closes its open occurrence instead of leaving it running into the future', () async {
    final actionId = await service.createAction(name: 'Deep work');
    await service.start(actionId);

    await (db.update(
      db.actionsTable,
    )..where((t) => t.id.equals(actionId))).write(
      ActionsTableCompanion(
        startAt: Value(
          dateTimeToDb(DateTime.utc(2024, 1, 1, 15, 43))!,
        ), // 18:43 Istanbul
      ),
    );

    await service.postpone(actionId, PostponeRule.plusOneHour);

    final stillRunning =
        await (db.select(db.actionOccurrencesTable)..where(
              (t) => t.actionId.equals(actionId) & t.finishedAt.isNull(),
            ))
            .getSingleOrNull();
    expect(stillRunning, isNull);

    final occurrence = await (db.select(
      db.actionOccurrencesTable,
    )..where((t) => t.actionId.equals(actionId))).getSingle();
    expect(occurrence.finishedAt, isNotNull);
    expect(occurrence.outcome, 'postponed');
  });

  test(
    'postponing a running action freezes the single source\'s current value '
    'into history, not whatever the occurrence still had from Start',
    () async {
      final actionId = await service.createAction(name: 'Deep work');
      await service.start(actionId);

      // Simulate a quick-edit of the schedule while running (e.g. tapping
      // the card's time) — this only ever touches actions.start_at, same as
      // updateSchedule()/updateAction() do for real, leaving the occurrence's
      // own started_at (set back when Start ran) stale.
      final editedStart = DateTime.utc(2024, 1, 1, 12, 0);
      await (db.update(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).write(
        ActionsTableCompanion(startAt: Value(dateTimeToDb(editedStart)!)),
      );

      await service.postpone(actionId, PostponeRule.plusOneHour);

      final occurrence = await (db.select(
        db.actionOccurrencesTable,
      )..where((t) => t.actionId.equals(actionId))).getSingle();
      expect(dateTimeFromDb(occurrence.startedAt), editedStart);
    },
  );

  test('finishing a running occurrence whose start was postponed into the '
      'future re-syncs the occurrence\'s started_at, so it never ends up '
      'finished before it started', () async {
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
      ActionOccurrencesTableCompanion(
        startedAt: Value(dateTimeToDb(newStart)!),
      ),
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
  });

  test(
    'snapshot/restore round-trips an action and its occurrence history',
    () async {
      final actionId = await service.createAction(name: 'Undo me');
      await service.start(actionId);

      final before = await service.snapshot(actionId);

      await service.finish(actionId);
      var action = await (db.select(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).getSingle();
      expect(action.done, true);

      await service.restore(before);

      action = await (db.select(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).getSingle();
      expect(action.done, false);

      final occurrences = await (db.select(
        db.actionOccurrencesTable,
      )..where((t) => t.actionId.equals(actionId))).get();
      expect(occurrences, hasLength(1));
      expect(occurrences.single.finishedAt, isNull); // running again, not done
    },
  );

  test('finish on a task marks it done and closes the occurrence', () async {
    final actionId = await service.createAction(name: 'Pay electricity bill');
    await service.start(actionId);
    await service.finish(actionId);

    final action = await (db.select(
      db.actionsTable,
    )..where((t) => t.id.equals(actionId))).getSingle();
    expect(action.done, true);
    expect(action.completedAt, isNotNull);

    final occurrence = await (db.select(
      db.actionOccurrencesTable,
    )..where((t) => t.actionId.equals(actionId))).getSingle();
    expect(occurrence.outcome, 'done');
    expect(occurrence.finishedAt, isNotNull);
  });

  test('starting a done action reopens it', () async {
    final actionId = await service.createAction(name: 'Redo this');
    await service.start(actionId);
    await service.finish(actionId);

    var action = await (db.select(
      db.actionsTable,
    )..where((t) => t.id.equals(actionId))).getSingle();
    expect(action.done, true);

    await service.start(actionId);

    action = await (db.select(
      db.actionsTable,
    )..where((t) => t.id.equals(actionId))).getSingle();
    expect(action.done, false);
    expect(action.completedAt, isNull);
  });

  test(
    'starting an action stuck as done-while-running self-heals to open',
    () async {
      // Simulates the state a pre-fix build could leave behind: an open
      // occurrence (still running) but `done` wrongly stuck true.
      final actionId = await service.createAction(name: 'Weird state');
      await service.start(actionId);
      await (db.update(db.actionsTable)..where((t) => t.id.equals(actionId)))
          .write(const ActionsTableCompanion(done: Value(true)));

      await service.start(actionId);

      final action = await (db.select(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).getSingle();
      expect(action.done, false);

      final occurrences = await (db.select(
        db.actionOccurrencesTable,
      )..where((t) => t.actionId.equals(actionId))).get();
      expect(occurrences, hasLength(1)); // no duplicate occurrence created
    },
  );

  test(
    'postpone on a task updates the schedule without an occurrence log',
    () async {
      final actionId = await service.createAction(
        name: 'Send out resumes',
        startAt: DateTime.utc(2024, 1, 1, 9),
        endAt: DateTime.utc(2024, 1, 1, 10),
      );
      await service.postpone(actionId, PostponeRule.plusOneHour);

      final action = await (db.select(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).getSingle();
      expect(
        action.startAt,
        isNot(DateTime.utc(2024, 1, 1, 9).toIso8601String()),
      );

      final occurrences = await (db.select(
        db.actionOccurrencesTable,
      )..where((t) => t.actionId.equals(actionId))).get();
      expect(occurrences, isEmpty);
    },
  );

  test(
    'createFromTemplate instantiates a new action from the payload',
    () async {
      final templateId = newId();
      await db
          .into(db.actionTemplatesTable)
          .insert(
            ActionTemplatesTableCompanion.insert(
              id: templateId,
              name: 'Prepare for interview',
              payload: jsonEncode({
                'name': 'Prepare for interview',
                'postponeFlex': 'hard',
              }),
            ),
          );

      final actionId = await service.createFromTemplate(templateId);
      expect(actionId, isNot(templateId));

      final action = await (db.select(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).getSingle();
      expect(action.name, 'Prepare for interview');
      expect(action.postponeFlex, 'hard');
    },
  );

  test(
    'createFromTemplate copies the template notes (notes + notes_text)',
    () async {
      final notes = jsonEncode({
        'document': {
          'type': 'document',
          'children': [
            {
              'type': 'paragraph',
              'data': {
                'delta': [
                  {'insert': 'Remember the milk'},
                ],
              },
            },
          ],
        },
      });
      final templateId = newId();
      await db
          .into(db.actionTemplatesTable)
          .insert(
            ActionTemplatesTableCompanion.insert(
              id: templateId,
              name: 'Shop',
              payload: jsonEncode({'name': 'Shop', 'notes': notes}),
            ),
          );

      final actionId = await service.createFromTemplate(templateId);
      final action = await (db.select(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).getSingle();
      expect(action.notes, notes);
      expect(action.notesText, contains('remember the milk'));
    },
  );

  Future<String> seedTemplate(Map<String, dynamic> payload) async {
    final id = newId();
    await db
        .into(db.actionTemplatesTable)
        .insert(
          ActionTemplatesTableCompanion.insert(
            id: id,
            name: payload['name'] as String,
            payload: jsonEncode(payload),
          ),
        );
    return id;
  }

  Future<ActionRow> actionRow(String id) =>
      (db.select(db.actionsTable)..where((t) => t.id.equals(id))).getSingle();

  Future<List<ActionOccurrence>> occurrencesOf(String id) => (db.select(
    db.actionOccurrencesTable,
  )..where((t) => t.actionId.equals(id))).get();

  test('createFromTemplateStarted: timed, runs from now, open occurrence, '
      'notes and live directions copied', () async {
    final metricId = newId();
    await db
        .into(db.metricsTable)
        .insert(MetricsTableCompanion.insert(id: metricId, name: 'Health'));
    final notes = jsonEncode({
      'document': {
        'type': 'document',
        'children': [
          {
            'type': 'paragraph',
            'data': {
              'delta': [
                {'insert': 'Remember the milk'},
              ],
            },
          },
        ],
      },
    });
    final t = await seedTemplate({
      'name': 'Walk',
      'estimatedMinutes': 45,
      'notes': notes,
      'metricIds': [metricId, 'stale-id'],
    });

    final before = DateTime.now().toUtc();
    final id = await service.createFromTemplateStarted(t);
    final a = await actionRow(id);
    final start = dateTimeFromDb(a.startAt)!;
    final end = dateTimeFromDb(a.endAt)!;
    expect(start.difference(before).inSeconds.abs(), lessThan(5));
    expect(end.difference(start), const Duration(minutes: 45));
    expect(a.isAllDay, isFalse);
    expect(a.done, isFalse);
    expect(a.notes, notes);
    expect(a.notesText, contains('remember the milk'));
    expect(a.countableActivityId, isNull);

    final links = await (db.select(
      db.actionMetricsTable,
    )..where((l) => l.actionId.equals(id))).get();
    expect(links.map((l) => l.metricId), [metricId]);

    final occ = await occurrencesOf(id);
    expect(occ, hasLength(1));
    expect(occ.single.startedAt, a.startAt);
    expect(occ.single.finishedAt, isNull);
  });

  test('createFromTemplateFinished: timed, ended now, done, closed '
      'occurrence', () async {
    final t = await seedTemplate({'name': 'Walk', 'estimatedMinutes': 30});

    final before = DateTime.now().toUtc();
    final id = await service.createFromTemplateFinished(t);
    final a = await actionRow(id);
    final start = dateTimeFromDb(a.startAt)!;
    final end = dateTimeFromDb(a.endAt)!;
    expect(end.difference(before).inSeconds.abs(), lessThan(5));
    expect(end.difference(start), const Duration(minutes: 30));
    expect(a.done, isTrue);
    expect(a.completedAt, a.endAt);
    expect(a.isAllDay, isFalse);

    final occ = await occurrencesOf(id);
    expect(occ, hasLength(1));
    expect(occ.single.startedAt, a.startAt);
    expect(occ.single.finishedAt, a.endAt);
    expect(occ.single.outcome, 'done');
  });

  test('template duration falls back: estimated -> countable average -> 1 h, '
      'linking only an existing same-name activity', () async {
    // No estimate, no activity: 1 hour, nothing created.
    final plain = await seedTemplate({'name': 'Read'});
    var a = await actionRow(await service.createFromTemplateStarted(plain));
    expect(
      dateTimeFromDb(a.endAt)!.difference(dateTimeFromDb(a.startAt)!),
      const Duration(hours: 1),
    );
    expect(a.countableActivityId, isNull);
    expect(await db.select(db.countableActivitiesTable).get(), isEmpty);

    // A same-name activity with a finished 20-minute run: its average.
    final activityId = await service.createCountableActivity('read');
    final run = await service.createAction(
      name: 'Read earlier',
      countableActivityId: activityId,
    );
    final end = DateTime.now().toUtc().subtract(const Duration(days: 1));
    await (db.update(db.actionsTable)..where((r) => r.id.equals(run))).write(
      ActionsTableCompanion(
        done: const Value(true),
        completedAt: Value(dateTimeToDb(end)),
        startAt: Value(dateTimeToDb(end.subtract(const Duration(minutes: 20)))),
        endAt: Value(dateTimeToDb(end)),
      ),
    );
    a = await actionRow(await service.createFromTemplateStarted(plain));
    expect(
      dateTimeFromDb(a.endAt)!.difference(dateTimeFromDb(a.startAt)!),
      const Duration(minutes: 20),
    );
    expect(a.countableActivityId, activityId);
    expect(await db.select(db.countableActivitiesTable).get(), hasLength(1));

    // By default the average wins over the manual estimate ...
    final est = await seedTemplate({'name': 'Read', 'estimatedMinutes': 10});
    a = await actionRow(await service.createFromTemplateFinished(est));
    expect(
      dateTimeFromDb(a.endAt)!.difference(dateTimeFromDb(a.startAt)!),
      const Duration(minutes: 20),
    );
    // ... and the manual estimate wins when the template switches it off.
    final manual = await seedTemplate({
      'name': 'Read',
      'estimatedMinutes': 10,
      'useAverage': false,
    });
    a = await actionRow(await service.createFromTemplateFinished(manual));
    expect(
      dateTimeFromDb(a.endAt)!.difference(dateTimeFromDb(a.startAt)!),
      const Duration(minutes: 10),
    );
  });

  test('a template with 0 or negative minutes is treated as having no estimate', () async {
    for (final minutes in [0, -5]) {
      for (final useAverage in [true, false]) {
        final t = await seedTemplate({
          'name': 'Read $minutes $useAverage',
          'estimatedMinutes': minutes,
          'useAverage': useAverage,
        });
        expect(
          await service.templateDuration(t),
          const Duration(hours: 1),
          reason: 'minutes $minutes, useAverage $useAverage',
        );
        final a = await actionRow(await service.createFromTemplateStarted(t));
        expect(
          dateTimeFromDb(a.endAt)!.difference(dateTimeFromDb(a.startAt)!),
          const Duration(hours: 1),
          reason: 'minutes $minutes, useAverage $useAverage',
        );
      }
    }
  });

  test('all-day template: the day is the ISTANBUL day, also after 21:00 UTC', () async {
    final t = await seedTemplate({'name': 'Rest day', 'isAllDay': true});
    // 22:30 UTC on 16 Oct is 01:30 on 17 Oct in Istanbul.
    final late = await actionRow(
      await service.createFromTemplateAt(t, DateTime.utc(2026, 10, 16, 22, 30)),
    );
    expect(late.isAllDay, isTrue);
    expect(late.endAt, isNull);
    expect(dateTimeFromDb(late.startAt), DateTime.utc(2026, 10, 16, 21)); // 17 Oct 00:00
    // 20:59:59 UTC is 23:59:59 on 16 Oct in Istanbul: still the 16th.
    final early = await actionRow(
      await service.createFromTemplateAt(t, DateTime.utc(2026, 10, 16, 20, 59, 59)),
    );
    expect(dateTimeFromDb(early.startAt), DateTime.utc(2026, 10, 15, 21)); // 16 Oct 00:00
  });

  test('all-day template started or finished now: today in Istanbul, never the UTC date', () async {
    final t = await seedTemplate({'name': 'Rest day', 'isAllDay': true});
    final istanbulNow = tz.TZDateTime.now(tz.getLocation('Europe/Istanbul'));
    final midnight = tz.TZDateTime(
      tz.getLocation('Europe/Istanbul'),
      istanbulNow.year,
      istanbulNow.month,
      istanbulNow.day,
    );
    // A plain UTC DateTime (a TZDateTime never equals one, even for one instant).
    final expected = DateTime.fromMillisecondsSinceEpoch(
      midnight.millisecondsSinceEpoch,
      isUtc: true,
    );

    final started = await actionRow(await service.createFromTemplateStarted(t));
    final finished = await actionRow(await service.createFromTemplateFinished(t));

    expect(dateTimeFromDb(started.startAt), expected);
    expect(started.done, isFalse);
    expect(dateTimeFromDb(finished.startAt), expected);
    expect(finished.done, isTrue);
    expect(started.endAt, isNull);
    expect(finished.endAt, isNull);
  });

  test(
    'deleteAction removes the action and everything hanging off it',
    () async {
      final metricId = newId();
      await db
          .into(db.metricsTable)
          .insert(MetricsTableCompanion.insert(id: metricId, name: 'Health'));
      final p = await service.createAction(name: 'P');
      final s = await service.createAction(name: 'S', metricIds: [metricId]);
      final x = await service.createAction(name: 'X');
      for (final (from, to) in [(p, s), (s, x)]) {
        await db
            .into(db.actionDependenciesTable)
            .insert(
              ActionDependenciesTableCompanion.insert(
                id: newId(),
                predecessorId: from,
                successorId: to,
              ),
            );
      }
      await service.start(s);

      await service.deleteAction(s);

      final remaining = await db.select(db.actionsTable).get();
      expect(remaining.map((a) => a.id).toSet(), {p, x});
      expect(await db.select(db.actionDependenciesTable).get(), isEmpty);
      expect(await db.select(db.actionMetricsTable).get(), isEmpty);
      expect(await db.select(db.actionOccurrencesTable).get(), isEmpty);
      // The metric itself is not the action's to delete.
      expect(await db.select(db.metricsTable).get(), hasLength(1));
    },
  );

  // ---- Start / Finish edge cases (spec: Starting Now / Finished Now) ----------

  Future<ActionRow> rowOf(String id) =>
      (db.select(db.actionsTable)..where((t) => t.id.equals(id))).getSingle();

  /// An action planned for TOMORROW (90 min) linked to an activity whose only
  /// finished run lasted 10 minutes: the activity's average is 10, its own
  /// length is 90.
  Future<String> tomorrowsReadLinkedToTenMinuteActivity() async {
    final activityId = await service.createCountableActivity('Reading');
    final run = await service.createAction(
      name: 'earlier run',
      countableActivityId: activityId,
    );
    final end = DateTime.now().toUtc().subtract(const Duration(hours: 1));
    await (db.update(db.actionsTable)..where((t) => t.id.equals(run))).write(
      ActionsTableCompanion(
        done: const Value(true),
        startAt: Value(dateTimeToDb(end.subtract(const Duration(minutes: 10)))),
        endAt: Value(dateTimeToDb(end)),
        completedAt: Value(dateTimeToDb(end)),
      ),
    );
    final tomorrow = DateTime.now().toUtc().add(const Duration(days: 1));
    return service.createAction(
      name: 'Read',
      countableActivityId: activityId,
      startAt: tomorrow,
      endAt: tomorrow.add(const Duration(minutes: 90)),
    );
  }

  Duration lengthOf(ActionRow r) =>
      dateTimeFromDb(r.endAt)!.difference(dateTimeFromDb(r.startAt)!);

  test('Start keeps the action own length, not the activity average (owner choice)', () async {
    final id = await tomorrowsReadLinkedToTenMinuteActivity();

    await service.start(id);

    expect(lengthOf(await rowOf(id)), const Duration(minutes: 90)); // not 10
  });

  test('Finish back-projects with the own length, not the activity average (owner choice)', () async {
    final id = await tomorrowsReadLinkedToTenMinuteActivity();

    await service.finish(id);

    final r = await rowOf(id);
    final end = dateTimeFromDb(r.endAt)!;
    final start = dateTimeFromDb(r.startAt)!;
    expect(end.difference(start).inSeconds, 90 * 60); // 12:30-14:00, not 13:50
    expect(DateTime.now().toUtc().difference(end).inSeconds.abs(), lessThan(5));
  });

  test('Finish: a start one second ago is kept, a start one minute ahead is back-projected', () async {
    final past = DateTime.now().toUtc().subtract(const Duration(seconds: 1));
    final started = await service.createAction(
      name: 'Just started',
      startAt: past,
      endAt: past.add(const Duration(minutes: 30)),
    );
    await service.finish(started);
    expect(dateTimeFromDb((await rowOf(started)).startAt), past); // kept

    final ahead = DateTime.now().toUtc().add(const Duration(minutes: 1));
    final notYet = await service.createAction(
      name: 'Not yet started',
      startAt: ahead,
      endAt: ahead.add(const Duration(minutes: 30)),
    );
    await service.finish(notYet);
    final r = await rowOf(notYet);
    expect(lengthOf(r).inSeconds, 30 * 60);
    expect(dateTimeFromDb(r.startAt)!.isBefore(DateTime.now().toUtc()), isTrue);
  });

  test('an inverted range (end before start) is treated as 60 minutes by Start and Finish', () async {
    final tomorrow = DateTime.now().toUtc().add(const Duration(days: 1));
    Future<String> inverted() => service.createAction(
      name: 'Inverted',
      startAt: tomorrow,
      endAt: tomorrow.subtract(const Duration(hours: 3)),
    );

    final a = await inverted();
    await service.start(a);
    expect(lengthOf(await rowOf(a)), const Duration(minutes: 60));

    final b = await inverted();
    await service.finish(b);
    expect(lengthOf(await rowOf(b)).inSeconds, 3600);
  });

  test('(pinned) Finish on an all-day action ticks it done and keeps it all-day', () async {
    final midnight = DateTime.utc(2026, 10, 16, 21); // 00:00 Istanbul, in the past
    final id = await service.createAction(
      name: 'Rest day',
      isAllDay: true,
      startAt: midnight,
    );

    await service.finish(id);

    final r = await rowOf(id);
    expect(r.done, isTrue);
    expect(r.isAllDay, isTrue);
    expect(dateTimeFromDb(r.startAt), midnight); // its day start is kept
  });

  test('Next week on a done all-day action moves it and it stays ticked (owner choice)', () async {
    final day = DateTime.utc(2026, 10, 16, 21); // 00:00 Istanbul
    final id = await service.createAction(
      name: 'Drink water',
      isAllDay: true,
      startAt: day,
    );
    await service.toggleDone(id);
    expect((await rowOf(id)).done, isTrue);

    await service.postpone(id, PostponeRule.nextWeek);

    final r = await rowOf(id);
    expect(dateTimeFromDb(r.startAt), day.add(const Duration(days: 7)));
    expect(r.isAllDay, isTrue);
    expect(r.done, isTrue); // postpone only moves the date
  });

  test('undoDelete restores the action, its links and its history', () async {
    final metricId = newId();
    await db
        .into(db.metricsTable)
        .insert(MetricsTableCompanion.insert(id: metricId, name: 'Health'));
    final p = await service.createAction(name: 'P');
    final s = await service.createAction(name: 'S', metricIds: [metricId]);
    final x = await service.createAction(name: 'X');
    for (final (from, to) in [(p, s), (s, x)]) {
      await db
          .into(db.actionDependenciesTable)
          .insert(
            ActionDependenciesTableCompanion.insert(
              id: newId(),
              predecessorId: from,
              successorId: to,
            ),
          );
    }
    await service.start(s);
    final before = await service.snapshot(s);
    final edgesBefore = (await db.select(db.actionDependenciesTable).get())
        .map((e) => (e.id, e.predecessorId, e.successorId))
        .toSet();

    final undo = await service.deleteAction(s);
    await service.undoDelete(undo);

    final after = await service.snapshot(s);
    expect(after.action, before.action);
    expect(after.occurrences, before.occurrences);
    expect(
      (await db.select(db.actionDependenciesTable).get())
          .map((e) => (e.id, e.predecessorId, e.successorId))
          .toSet(),
      edgesBefore,
    );
    final links = await db.select(db.actionMetricsTable).get();
    expect(links.map((l) => l.metricId), [metricId]);
  });

  test('undoDelete skips edges to an action deleted in the meantime', () async {
    final p = await service.createAction(name: 'P');
    final s = await service.createAction(name: 'S');
    await db
        .into(db.actionDependenciesTable)
        .insert(
          ActionDependenciesTableCompanion.insert(
            id: newId(),
            predecessorId: p,
            successorId: s,
          ),
        );

    final undo = await service.deleteAction(s);
    await service.deleteAction(p);
    await service.undoDelete(undo);

    expect((await db.select(db.actionsTable).get()).map((a) => a.id), [s]);
    expect(await db.select(db.actionDependenciesTable).get(), isEmpty);
  });
}
