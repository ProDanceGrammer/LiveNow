import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/ids.dart';
import 'package:livenow/core/time_codec.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';

void main() {
  late AppDatabase db;
  late ActionService service;

  setUp(() {
    // Foreign keys on, like the real connection in data/database.dart.
    db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys = ON;'),
      ),
    );
    service = ActionService(db);
  });

  tearDown(() => db.close());

  Future<ActionRow> row(String id) =>
      (db.select(db.actionsTable)..where((t) => t.id.equals(id))).getSingle();

  Future<void> edge(String from, String to) => db
      .into(db.actionDependenciesTable)
      .insert(
        ActionDependenciesTableCompanion.insert(
          id: newId(),
          predecessorId: from,
          successorId: to,
        ),
      );

  Future<Set<String>> nextOf(String id) async =>
      (await (db.select(
            db.actionDependenciesTable,
          )..where((t) => t.predecessorId.equals(id))).get())
          .map((d) => d.successorId)
          .toSet();

  Future<Set<String>> previousOf(String id) async =>
      (await (db.select(
            db.actionDependenciesTable,
          )..where((t) => t.successorId.equals(id))).get())
          .map((d) => d.predecessorId)
          .toSet();

  /// Marks [id] as a finished run of [minutes], completed [completedAgo] ago.
  Future<void> markFinished(
    String id, {
    required int minutes,
    Duration completedAgo = const Duration(hours: 1),
  }) {
    final end = DateTime.now().toUtc().subtract(completedAgo);
    return (db.update(db.actionsTable)..where((t) => t.id.equals(id))).write(
      ActionsTableCompanion(
        done: const Value(true),
        startAt: Value(dateTimeToDb(end.subtract(Duration(minutes: minutes)))),
        endAt: Value(dateTimeToDb(end)),
        completedAt: Value(dateTimeToDb(end)),
      ),
    );
  }

  Future<String> finishedRun(
    String name,
    int minutes, {
    Duration completedAgo = const Duration(hours: 1),
    String? activityId,
  }) async {
    final id = await service.createAction(
      name: name,
      countableActivityId: activityId,
    );
    await markFinished(id, minutes: minutes, completedAgo: completedAgo);
    return id;
  }

  test(
    'first continue numbers both actions and starts the new one now',
    () async {
      final sourceId = await service.createAction(name: 'Read a Bible');
      await markFinished(sourceId, minutes: 25);

      final before = DateTime.now().toUtc();
      final result = await service.continueSameAction(sourceId);
      final after = DateTime.now().toUtc();

      final source = await row(sourceId);
      final created = await row(result.newActionId);
      expect(source.name, '[#1] Read a Bible');
      expect(source.sequenceNumber, 1);
      expect(created.name, '[#2] Read a Bible');
      expect(created.sequenceNumber, 2);
      expect(created.done, isFalse);
      expect(created.isAllDay, isFalse);

      final start = dateTimeFromDb(created.startAt)!;
      expect(start.isBefore(before), isFalse);
      expect(start.isAfter(after), isFalse);
      expect(
        dateTimeFromDb(created.endAt)!.difference(start),
        const Duration(minutes: 25),
      );

      final occurrences = await (db.select(
        db.actionOccurrencesTable,
      )..where((t) => t.actionId.equals(result.newActionId))).get();
      expect(occurrences, hasLength(1));
      expect(occurrences.single.finishedAt, isNull);
      // The source's finished state is untouched.
      expect(source.done, isTrue);
    },
  );

  test('continuing the continuation gets the next number', () async {
    final sourceId = await service.createAction(name: 'Read a Bible');
    final second = (await service.continueSameAction(sourceId)).newActionId;
    final third = (await service.continueSameAction(second)).newActionId;

    expect((await row(second)).name, '[#2] Read a Bible');
    expect((await row(third)).name, '[#3] Read a Bible');
    expect((await row(third)).sequenceNumber, 3);
    expect(await nextOf(sourceId), {second});
    expect(await nextOf(second), {third});
  });

  test('a hand-typed [#n] prefix continues from that number', () async {
    final sourceId = await service.createAction(name: '[#4] Pray');
    final created = (await service.continueSameAction(sourceId)).newActionId;

    expect((await row(sourceId)).name, '[#4] Pray');
    expect((await row(created)).name, '[#5] Pray');
  });

  test('a huge [#n] in the name does not crash Continue', () async {
    final sourceId = await service.createAction(
      name: '[#99999999999999999999] Pray',
    );
    final created = (await service.continueSameAction(sourceId)).newActionId;

    // It is not a counter, so it stays part of the name.
    expect((await row(sourceId)).name, '[#1] [#99999999999999999999] Pray');
    expect((await row(created)).name, '[#2] [#99999999999999999999] Pray');
  });

  test('a name that is only [#3] continues as [#3] / [#4] without a trailing space', () async {
    final sourceId = await service.createAction(name: '[#3]');
    final created = (await service.continueSameAction(sourceId)).newActionId;

    expect((await row(sourceId)).name, '[#3]');
    expect((await row(created)).name, '[#4]');
  });

  test('[#007] is rewritten as [#7] and the next one is [#8]', () async {
    final sourceId = await service.createAction(name: '[#007] Pray');
    final created = (await service.continueSameAction(sourceId)).newActionId;

    expect((await row(sourceId)).name, '[#7] Pray');
    expect((await row(created)).name, '[#8] Pray');
  });

  test('removing the number from the name restarts at [#1] / [#2]', () async {
    final sourceId = await service.createAction(name: 'Read a Bible');
    var current = sourceId;
    for (var i = 0; i < 3; i++) {
      current = (await service.continueSameAction(current)).newActionId;
    }
    expect((await row(current)).name, '[#4] Read a Bible');
    expect((await row(current)).sequenceNumber, 4);

    // The user deletes the "[#4]" from the name (the stored counter stays 4).
    await (db.update(db.actionsTable)..where((t) => t.id.equals(current)))
        .write(const ActionsTableCompanion(name: Value('Read a Bible')));
    final result = await service.continueSameAction(current);

    expect((await row(current)).name, '[#1] Read a Bible');
    expect((await row(current)).sequenceNumber, 1);
    expect((await row(result.newActionId)).name, '[#2] Read a Bible');
    expect((await row(result.newActionId)).sequenceNumber, 2);

    // Undo still puts the source back the way it was.
    await service.undoContinue(result.undo);
    expect((await row(current)).name, 'Read a Bible');
  });

  test('an edited number wins over the stored counter', () async {
    final sourceId = await service.createAction(name: 'Pray');
    final second = (await service.continueSameAction(sourceId)).newActionId;
    expect((await row(second)).sequenceNumber, 2);
    await (db.update(db.actionsTable)..where((t) => t.id.equals(second)))
        .write(const ActionsTableCompanion(name: Value('[#7] Pray')));
    final third = (await service.continueSameAction(second)).newActionId;
    expect((await row(second)).name, '[#7] Pray');
    expect((await row(third)).name, '[#8] Pray');
  });

  test('next actions move to the new action; predecessors stay put', () async {
    final p = await service.createAction(name: 'P');
    final s = await service.createAction(name: 'S');
    final x = await service.createAction(name: 'X');
    final y = await service.createAction(name: 'Y');
    await edge(p, s);
    await edge(s, x);
    await edge(s, y);

    final n = (await service.continueSameAction(s)).newActionId;

    expect(await previousOf(s), {p});
    expect(await nextOf(s), {n});
    expect(await previousOf(n), {s});
    expect(await nextOf(n), {x, y});
  });

  test('metrics, countable activity and settings are copied', () async {
    final metricId = newId();
    await db
        .into(db.metricsTable)
        .insert(MetricsTableCompanion.insert(id: metricId, name: 'Faith'));
    final activityId = await service.createCountableActivity('Reading');
    final s = await service.createAction(
      name: 'Read',
      postponeFlex: 'hard',
      depthLevel: 'deep',
      countableActivityId: activityId,
      metricIds: [metricId],
    );

    final n = (await service.continueSameAction(s)).newActionId;

    final created = await row(n);
    expect(created.postponeFlex, 'hard');
    expect(created.depthLevel, 'deep');
    expect(created.countableActivityId, activityId);
    final links = await (db.select(
      db.actionMetricsTable,
    )..where((t) => t.actionId.equals(n))).get();
    expect(links.map((l) => l.metricId), [metricId]);
  });

  test('duration: countable activity average over the last month', () async {
    final activityId = await service.createCountableActivity('Reading');
    final s = await service.createAction(
      name: 'Read',
      countableActivityId: activityId,
      startAt: DateTime.now().toUtc(),
      endAt: DateTime.now().toUtc().add(const Duration(minutes: 99)),
    );
    await finishedRun('a', 10, activityId: activityId);
    await finishedRun(
      'b',
      20,
      activityId: activityId,
      completedAgo: const Duration(days: 20),
    );
    await finishedRun(
      'old',
      200,
      activityId: activityId,
      completedAgo: const Duration(days: 40),
    ); // outside the window
    await finishedRun('other activity', 300);

    final n = (await service.continueSameAction(s)).newActionId;

    final created = await row(n);
    expect(
      dateTimeFromDb(created.endAt)!
          .difference(dateTimeFromDb(created.startAt)!),
      const Duration(minutes: 15),
    );
  });

  test('duration: same-name runs in the chain over the last week', () async {
    final p = await finishedRun(
      'Read a Bible 3',
      40,
      completedAgo: const Duration(days: 3),
    );
    final tooOld = await finishedRun(
      'Read a Bible',
      500,
      completedAgo: const Duration(days: 10),
    );
    final otherName = await finishedRun(
      'Pray',
      500,
      completedAgo: const Duration(days: 1),
    );
    final s = await service.createAction(name: 'Read a Bible');
    await edge(tooOld, p);
    await edge(otherName, p);
    await edge(p, s);

    final n = (await service.continueSameAction(s)).newActionId;

    final created = await row(n);
    expect(
      dateTimeFromDb(created.endAt)!
          .difference(dateTimeFromDb(created.startAt)!),
      const Duration(minutes: 40),
    );
  });

  test('duration: falls back to the source own duration', () async {
    final s = await service.createAction(
      name: 'Read',
      startAt: DateTime.utc(2026, 1, 1, 18),
      endAt: DateTime.utc(2026, 1, 1, 18, 25),
    );

    final n = (await service.continueSameAction(s)).newActionId;

    final created = await row(n);
    expect(
      dateTimeFromDb(created.endAt)!
          .difference(dateTimeFromDb(created.startAt)!),
      const Duration(minutes: 25),
    );
  });

  // ---- edge cases of the predicted time (spec: Predicted Time Consumption) ----

  /// Presses Continue on [sourceId] and returns the new action's length.
  Future<Duration> continuedLength(String sourceId) async {
    final n = (await service.continueSameAction(sourceId)).newActionId;
    final created = await row(n);
    return dateTimeFromDb(created.endAt)!
        .difference(dateTimeFromDb(created.startAt)!);
  }

  test('an activity with no finished run this month falls back to the chain', () async {
    final activityId = await service.createCountableActivity('Reading');
    // Its only finished run is 40 days old: no countable average.
    await finishedRun(
      'old run',
      200,
      activityId: activityId,
      completedAgo: const Duration(days: 40),
    );
    final p = await finishedRun(
      'Read a Bible',
      30,
      completedAgo: const Duration(days: 2),
    );
    final s = await service.createAction(
      name: 'Read a Bible',
      countableActivityId: activityId,
    );
    await edge(p, s);

    expect(await continuedLength(s), const Duration(minutes: 30));
  });

  test('an unfinished same-name predecessor is not counted', () async {
    final p = await service.createAction(
      name: 'Read a Bible',
      startAt: DateTime.now().toUtc().subtract(const Duration(hours: 3)),
      endAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
    ); // 2 hours long, but never marked done
    final s = await service.createAction(
      name: 'Read a Bible',
      startAt: DateTime.utc(2026, 1, 1, 18),
      endAt: DateTime.utc(2026, 1, 1, 18, 25),
    );
    await edge(p, s);

    expect(await continuedLength(s), const Duration(minutes: 25)); // own length
  });

  test('the chain window is one week: 6 d 23 h counts, 7 d 1 h does not', () async {
    final inside = await finishedRun(
      'Read a Bible',
      40,
      completedAgo: const Duration(days: 6, hours: 23),
    );
    final outside = await finishedRun(
      'Read a Bible',
      500,
      completedAgo: const Duration(days: 7, hours: 1),
    );
    final s = await service.createAction(name: 'Read a Bible');
    await edge(inside, s);
    await edge(outside, s);

    expect(await continuedLength(s), const Duration(minutes: 40));
  });

  test('the countable window is a month: 29 d 23 h counts, 30 d 1 h does not', () async {
    final activityId = await service.createCountableActivity('Reading');
    await finishedRun(
      'in',
      10,
      activityId: activityId,
      completedAgo: const Duration(days: 29, hours: 23),
    );
    await finishedRun(
      'out',
      1000,
      activityId: activityId,
      completedAgo: const Duration(days: 30, hours: 1),
    );
    final s = await service.createAction(
      name: 'Read',
      countableActivityId: activityId,
    );

    expect(await continuedLength(s), const Duration(minutes: 10));
  });

  test('the window looks at when a run was completed, not at its end time', () async {
    final p = await finishedRun(
      'Read a Bible',
      500,
      completedAgo: const Duration(days: 10),
    );
    // Its schedule says it ended yesterday, but it was completed 10 days ago.
    final yesterday = DateTime.now().toUtc().subtract(const Duration(days: 1));
    await (db.update(db.actionsTable)..where((t) => t.id.equals(p))).write(
      ActionsTableCompanion(
        startAt: Value(
          dateTimeToDb(yesterday.subtract(const Duration(minutes: 500))),
        ),
        endAt: Value(dateTimeToDb(yesterday)),
      ),
    );
    final s = await service.createAction(
      name: 'Read a Bible',
      startAt: DateTime.utc(2026, 1, 1, 18),
      endAt: DateTime.utc(2026, 1, 1, 18, 20),
    );
    await edge(p, s);

    expect(await continuedLength(s), const Duration(minutes: 20)); // not 500
  });

  test('every earlier same-name run in the chain counts, not only the direct one', () async {
    // Monday 20 min -> Tuesday 40 min -> Wednesday (Continue is pressed here).
    final monday = await finishedRun(
      'Read a Bible',
      20,
      completedAgo: const Duration(days: 2),
    );
    final tuesday = await finishedRun(
      'Read a Bible',
      40,
      completedAgo: const Duration(days: 1),
    );
    final wednesday = await service.createAction(name: 'Read a Bible');
    await edge(monday, tuesday);
    await edge(tuesday, wednesday);

    // The average of Monday and Tuesday, not Tuesday alone (the owner chose this).
    expect(await continuedLength(wednesday), const Duration(minutes: 30));
  });

  // The spec is silent on the next two; they pin what the app does today.
  test('(pinned) the finished source counts in its own chain average', () async {
    final p = await finishedRun(
      'Read a Bible',
      60,
      completedAgo: const Duration(days: 2),
    );
    final s = await service.createAction(name: 'Read a Bible');
    await markFinished(s, minutes: 30);
    await edge(p, s);

    // (60 + 30) / 2: the source itself is one of the samples.
    expect(await continuedLength(s), const Duration(minutes: 45));
  });

  test('(pinned) names are compared ignoring case', () async {
    final p = await finishedRun(
      'read a bible',
      40,
      completedAgo: const Duration(days: 2),
    );
    final s = await service.createAction(name: 'Read a Bible');
    await edge(p, s);

    expect(await continuedLength(s), const Duration(minutes: 40));
  });

  test('an unscheduled source continues as a 60 minute action starting now', () async {
    final s = await service.createAction(name: 'Read');

    expect(await continuedLength(s), const Duration(minutes: 60));
    final source = await row(s);
    expect(source.startAt, isNull); // the source itself is left unscheduled
    expect(source.endAt, isNull);
  });

  test('an all-day source continues as a TIMED action, now, for an hour', () async {
    final midnight = DateTime.utc(2026, 10, 16, 21); // 00:00 Istanbul
    final s = await service.createAction(
      name: 'Rest day',
      isAllDay: true,
      startAt: midnight,
    );

    final before = DateTime.now().toUtc();
    final n = (await service.continueSameAction(s)).newActionId;

    final created = await row(n);
    expect(created.isAllDay, isFalse);
    final start = dateTimeFromDb(created.startAt)!;
    expect(start.isBefore(before.subtract(const Duration(seconds: 1))), isFalse);
    expect(
      dateTimeFromDb(created.endAt)!.difference(start),
      const Duration(minutes: 60),
    );
    // The source stays an all-day action.
    expect((await row(s)).isAllDay, isTrue);
  });

  test('Undo after Continue restores the source as it was, later edits to it are lost', () async {
    final s = await service.createAction(name: 'Read');
    final result = await service.continueSameAction(s);
    expect((await row(s)).name, '[#1] Read');

    // The user edits the source after the Continue...
    await (db.update(db.actionsTable)..where((t) => t.id.equals(s))).write(
      const ActionsTableCompanion(name: Value('[#1] Read daily')),
    );
    await service.undoContinue(result.undo);

    // ...and Undo puts the whole row back as before Continue (owner's choice).
    expect((await row(s)).name, 'Read');
    expect(
      await (db.select(db.actionsTable)
            ..where((t) => t.id.equals(result.newActionId)))
          .getSingleOrNull(),
      isNull,
    );
  });

  test('tags in the name are copied, the Blocks box is not (owner choice)', () async {
    final s = await service.createAction(name: '[CS:123] Work');
    await service.setDiaryBlocks(s, 'CS, DEV');

    final n = (await service.continueSameAction(s)).newActionId;

    // The tag is part of the name, so it comes along (after the [#n] prefix).
    expect((await row(s)).name, '[#1] [CS:123] Work');
    expect((await row(n)).name, '[#2] [CS:123] Work');
    // The Blocks box (used by "What is done?") starts empty on the new action,
    // and the source keeps its own.
    expect((await row(n)).resultNote, isNull);
    expect((await row(s)).resultNote, 'CS, DEV');
  });

  test('Continue pressed twice on the same source gives two [#2] in a chain', () async {
    final s = await service.createAction(name: 'Read');
    final first = (await service.continueSameAction(s)).newActionId;
    final second = (await service.continueSameAction(s)).newActionId;

    // Allowed (the owner's choice): both are [#2], nothing is blocked or renumbered.
    expect((await row(s)).name, '[#1] Read');
    expect((await row(first)).name, '[#2] Read');
    expect((await row(second)).name, '[#2] Read');
    // The second Continue moved the source's next action (the first one) onto
    // the new one: source -> second -> first.
    expect(await nextOf(s), {second});
    expect(await nextOf(second), {first});
    expect(await nextOf(first), isEmpty);
  });

  test('continuing a RUNNING action leaves it as it is: the two overlap', () async {
    final now = DateTime.now().toUtc();
    final start = now.subtract(const Duration(minutes: 30));
    final end = now.add(const Duration(minutes: 30));
    final s = await service.createAction(
      name: 'Read',
      startAt: start,
      endAt: end,
    );

    final n = (await service.continueSameAction(s)).newActionId;

    // The source keeps its own times (the owner's choice: it is not cut off).
    final source = await row(s);
    expect(dateTimeFromDb(source.startAt), start);
    expect(dateTimeFromDb(source.endAt), end);
    // The new one starts now, so it overlaps the source until it ends.
    final created = await row(n);
    final newStart = dateTimeFromDb(created.startAt)!;
    expect(newStart.isBefore(end), isTrue);
    expect(newStart.isAfter(start), isTrue);
  });

  test('undoContinue puts everything back', () async {
    final p = await service.createAction(name: 'P');
    final s = await service.createAction(name: 'Read');
    final x = await service.createAction(name: 'X');
    await edge(p, s);
    await edge(s, x);
    final sourceBefore = await row(s);

    final result = await service.continueSameAction(s);
    await service.undoContinue(result.undo);

    expect(await row(s), sourceBefore);
    expect(await nextOf(s), {x});
    expect(await previousOf(s), {p});
    expect(
      await (db.select(
        db.actionsTable,
      )..where((t) => t.id.equals(result.newActionId))).get(),
      isEmpty,
    );
    expect(await db.select(db.actionDependenciesTable).get(), hasLength(2));
    expect(await db.select(db.actionOccurrencesTable).get(), isEmpty);
  });
}
