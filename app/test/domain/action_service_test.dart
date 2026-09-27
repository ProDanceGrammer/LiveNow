import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/ids.dart';
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

  test('start is idempotent while an occurrence is already running', () async {
    final actionId = await service.createAction(name: 'Write my book');
    await service.start(actionId);
    await service.start(actionId);

    final running = await (db.select(
      db.actionOccurrencesTable,
    )..where((t) => t.actionId.equals(actionId))).get();
    expect(running, hasLength(1));
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
