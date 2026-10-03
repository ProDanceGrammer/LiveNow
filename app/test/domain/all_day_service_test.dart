import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/ids.dart';
import 'package:livenow/core/time_codec.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/duration_rules.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  late AppDatabase db;
  late ActionService service;

  setUpAll(initPostponeTimeZoneData);

  setUp(() {
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

  /// A finished run of [name] that lasted [minutes], completed [daysAgo] ago.
  Future<void> finishedRun(String name, int minutes, {int daysAgo = 1}) async {
    final id = await service.createAction(name: name);
    final end = DateTime.now().toUtc().subtract(Duration(days: daysAgo));
    await (db.update(db.actionsTable)..where((t) => t.id.equals(id))).write(
      ActionsTableCompanion(
        done: const Value(true),
        completedAt: Value(dateTimeToDb(end)),
        startAt: Value(dateTimeToDb(end.subtract(Duration(minutes: minutes)))),
        endAt: Value(dateTimeToDb(end)),
      ),
    );
  }

  group('predictedDurationFor', () {
    test('falls back to 1 hour for an all-day item with no history', () async {
      final id = await service.createAction(name: 'Day', isAllDay: true);
      expect(await service.predictedDurationFor(id), defaultActionDuration);
    });

    test('uses its own duration when timed and no history', () async {
      final start = DateTime.utc(2030, 1, 1, 9);
      final id = await service.createAction(
        name: 'Solo',
        startAt: start,
        endAt: start.add(const Duration(minutes: 25)),
      );
      expect(
        await service.predictedDurationFor(id),
        const Duration(minutes: 25),
      );
    });

    test('averages recent same-name runs (case/prefix insensitive)', () async {
      await finishedRun('Reading', 30);
      await finishedRun('[#2] reading', 50);
      await finishedRun('Reading', 600, daysAgo: 60); // outside the window
      await finishedRun('Other', 500);
      final id = await service.createAction(name: 'Reading', isAllDay: true);
      expect(
        await service.predictedDurationFor(id),
        const Duration(minutes: 40),
      );
    });

    test('countable activity average beats same-name runs', () async {
      final activityId = await service.createCountableActivity('Reading');
      final run = await service.createAction(name: 'Something else');
      final end = DateTime.now().toUtc().subtract(const Duration(days: 2));
      await (db.update(db.actionsTable)..where((t) => t.id.equals(run))).write(
        ActionsTableCompanion(
          countableActivityId: Value(activityId),
          done: const Value(true),
          completedAt: Value(dateTimeToDb(end)),
          startAt: Value(dateTimeToDb(end.subtract(const Duration(hours: 2)))),
          endAt: Value(dateTimeToDb(end)),
        ),
      );
      await finishedRun('Reading', 30);
      final id = await service.createAction(name: 'Reading', isAllDay: true);
      await service.setCountableActivity(id, activityId);
      expect(await service.predictedDurationFor(id), const Duration(hours: 2));
    });
  });

  test('scheduleAllDayAt makes it timed and Undo restores the flag', () async {
    await finishedRun('Gym', 90);
    final day = DateTime.utc(2030, 5, 1);
    final id = await service.createAction(
      name: 'Gym',
      isAllDay: true,
      startAt: day,
    );
    final start = DateTime.utc(2030, 5, 1, 10, 30);

    final undo = await service.scheduleAllDayAt(id, start);
    final after = await row(id);
    expect(after.isAllDay, isFalse);
    expect(dateTimeFromDb(after.startAt), start);
    expect(dateTimeFromDb(after.endAt), start.add(const Duration(minutes: 90)));

    await service.undoMoveActions(undo);
    final back = await row(id);
    expect(back.isAllDay, isTrue);
    expect(dateTimeFromDb(back.startAt), day);
    expect(back.endAt, isNull);
  });

  test('makeAllDay uses Istanbul midnight, null end; Undo restores', () async {
    final start = DateTime.utc(2030, 5, 1, 10);
    final end = DateTime.utc(2030, 5, 1, 11);
    final id = await service.createAction(
      name: 'Timed',
      startAt: start,
      endAt: end,
    );

    final undo = await service.makeAllDay(id, DateTime(2030, 5, 2, 15, 45));
    final after = await row(id);
    expect(after.isAllDay, isTrue);
    expect(after.endAt, isNull);
    final expected = tz.TZDateTime(
      tz.getLocation('Europe/Istanbul'),
      2030,
      5,
      2,
    ).toUtc();
    expect(
      dateTimeFromDb(after.startAt)!.millisecondsSinceEpoch,
      expected.millisecondsSinceEpoch,
    );
    expect(
      expected.millisecondsSinceEpoch,
      DateTime.utc(2030, 5, 1, 21).millisecondsSinceEpoch, // UTC+3
    );

    await service.undoMoveActions(undo);
    final back = await row(id);
    expect(back.isAllDay, isFalse);
    expect(dateTimeFromDb(back.startAt), start);
    expect(dateTimeFromDb(back.endAt), end);
  });

  test('toggleDone flips done only and Undo restores it', () async {
    final day = DateTime.utc(2030, 5, 1);
    final id = await service.createAction(
      name: 'Chk',
      isAllDay: true,
      startAt: day,
    );
    final before = await row(id);

    final undo = await service.toggleDone(id);
    final ticked = await row(id);
    expect(ticked.done, isTrue);
    expect(ticked.completedAt, isNotNull);
    expect(ticked.startAt, before.startAt);
    expect(ticked.endAt, before.endAt);
    expect(ticked.isAllDay, isTrue);

    await service.undoToggleDone(undo);
    final back = await row(id);
    expect(back.done, isFalse);
    expect(back.completedAt, isNull);

    await service.toggleDone(id);
    await service.toggleDone(id);
    expect((await row(id)).done, isFalse);
  });

  test(
    'start on an all-day action moves it to now for the predicted time',
    () async {
      final metricId = newId();
      await db
          .into(db.metricsTable)
          .insert(MetricsTableCompanion.insert(id: metricId, name: 'M'));
      final id = await service.createAction(
        name: 'Whole day',
        isAllDay: true,
        startAt: DateTime.utc(2030, 5, 1),
        metricIds: [metricId],
      );
      final t0 = DateTime.now().toUtc();
      await service.start(id);
      final after = await row(id);
      expect(after.isAllDay, isFalse);
      final start = dateTimeFromDb(after.startAt)!;
      expect(start.difference(t0).inSeconds.abs() < 5, isTrue);
      expect(
        dateTimeFromDb(after.endAt)!.difference(start),
        defaultActionDuration,
      );
      expect(await db.select(db.actionMetricsTable).get(), hasLength(1));
    },
  );

  test('moveActions without isAllDay leaves the flag alone', () async {
    final id = await service.createAction(name: 'A', isAllDay: true);
    final undo = await service.moveActions([
      ScheduleChange(id, startAt: DateTime.utc(2030), endAt: null),
    ]);
    expect((await row(id)).isAllDay, isTrue);
    await service.undoMoveActions(undo);
    expect((await row(id)).isAllDay, isTrue);
  });

  test('createFromTemplate drops metric ids that no longer exist', () async {
    final keep = newId();
    await db
        .into(db.metricsTable)
        .insert(MetricsTableCompanion.insert(id: keep, name: 'Keep'));
    final templateId = newId();
    await db
        .into(db.actionTemplatesTable)
        .insert(
          ActionTemplatesTableCompanion.insert(
            id: templateId,
            name: 'T',
            payload: jsonEncode({
              'name': 'T',
              'metricIds': [keep, newId()],
            }),
          ),
        );
    final id = await service.createFromTemplate(templateId);
    final links = await (db.select(
      db.actionMetricsTable,
    )..where((t) => t.actionId.equals(id))).get();
    expect(links.map((l) => l.metricId), [keep]);
  });

  group('all-day templates', () {
    Future<String> seed() async {
      final id = newId();
      await db
          .into(db.actionTemplatesTable)
          .insert(
            ActionTemplatesTableCompanion.insert(
              id: id,
              name: 'Water',
              payload: jsonEncode({
                'name': 'Water',
                'isAllDay': true,
                'estimatedMinutes': 30,
              }),
            ),
          );
      return id;
    }

    DateTime istanbulMidnight() {
      final n = tz.TZDateTime.now(tz.getLocation('Europe/Istanbul'));
      return tz.TZDateTime(
        tz.getLocation('Europe/Istanbul'),
        n.year,
        n.month,
        n.day,
      ).toUtc();
    }

    Future<List<ActionOccurrence>> occ(String id) => (db.select(
      db.actionOccurrencesTable,
    )..where((t) => t.actionId.equals(id))).get();

    test('Started: all-day today, not done, no occurrence', () async {
      final id = await service.createFromTemplateStarted(await seed());
      final a = await row(id);
      expect(a.isAllDay, isTrue);
      expect(
        dateTimeFromDb(a.startAt)!.isAtSameMomentAs(istanbulMidnight()),
        isTrue,
      );
      expect(a.endAt, isNull);
      expect(a.done, isFalse);
      expect(a.completedAt, isNull);
      expect(await occ(id), isEmpty);
    });

    test('Finished: all-day today, done, closed occurrence', () async {
      final id = await service.createFromTemplateFinished(await seed());
      final a = await row(id);
      expect(a.isAllDay, isTrue);
      expect(
        dateTimeFromDb(a.startAt)!.isAtSameMomentAs(istanbulMidnight()),
        isTrue,
      );
      expect(a.endAt, isNull);
      expect(a.done, isTrue);
      expect(a.completedAt, isNotNull);
      final o = await occ(id);
      expect(o, hasLength(1));
      expect(o.single.startedAt, isNotNull);
      expect(o.single.finishedAt, o.single.startedAt);
      expect(o.single.outcome, 'done');
    });
  });
}
