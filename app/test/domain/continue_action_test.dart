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
