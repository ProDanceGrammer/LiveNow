import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/ids.dart';
import 'package:livenow/core/time_codec.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/postpone_rules.dart';

/// Bug of 23.10.2026: the quick buttons of ONE action did nothing. Cause: the
/// action had two OPEN occurrence rows (no unique index stops that; two devices
/// pressing Start both add one, and sync keeps both) and Start / Finish /
/// Postpone read them with `getSingleOrNull()`, which throws on two rows; the
/// transaction rolled back and the error vanished. These tests build such an
/// action (same kind of data as the reported one: a Ukrainian name, two growth
/// directions, a long checklist in the notes, a 41-minute timed schedule).
void main() {
  late AppDatabase db;
  late ActionService service;
  late String actionId;

  setUpAll(initPostponeTimeZoneData);

  Future<void> addOpenOccurrence(String startedAt) => db
      .into(db.actionOccurrencesTable)
      .insert(
        ActionOccurrencesTableCompanion.insert(
          id: newId(),
          actionId: actionId,
          startedAt: Value(startedAt),
        ),
      );

  String checklist() => jsonEncode({
    'document': {
      'type': 'page',
      'children': [
        for (final t in [
          'Подивитися Balance Dashboard',
          'Перевірити, чи запланований наступний тиждень',
          'Перевірка People, чи не треба побачитись із кимось',
        ])
          {
            'type': 'todo_list',
            'data': {
              'checked': true,
              'delta': [
                {'insert': t},
              ],
            },
          },
      ],
    },
  });

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = ActionService(db);
    final m1 = newId(), m2 = newId();
    for (final id in [m1, m2]) {
      await db
          .into(db.metricsTable)
          .insert(MetricsTableCompanion.insert(id: id, name: 'Напрям $id'));
    }
    final start = DateTime.now().toUtc().subtract(const Duration(minutes: 20));
    actionId = await service.createAction(
      name: 'Планування на наступний тиждень',
      startAt: start,
      endAt: start.add(const Duration(minutes: 41)),
      metricIds: [m1, m2],
      notes: checklist(),
    );
    // Two devices both pressed Start: two open rows for one action.
    await addOpenOccurrence(dateTimeToDb(start)!);
    await addOpenOccurrence(dateTimeToDb(start.add(const Duration(minutes: 1)))!);
  });

  tearDown(() => db.close());

  Future<List<ActionOccurrence>> open() => (db.select(
    db.actionOccurrencesTable,
  )..where((t) => t.actionId.equals(actionId) & t.finishedAt.isNull())).get();

  Future<ActionRow> row() => (db.select(
    db.actionsTable,
  )..where((t) => t.id.equals(actionId))).getSingle();

  test('Start works with two open occurrences and leaves exactly one', () async {
    final before = await row();
    await service.start(actionId);
    final after = await row();
    expect(after.startAt, isNot(before.startAt));
    expect(after.done, isFalse);
    expect(await open(), hasLength(1));
  });

  test('Finish works with two open occurrences and closes both', () async {
    await service.finish(actionId);
    final after = await row();
    expect(after.done, isTrue);
    expect(after.completedAt, isNotNull);
    expect(await open(), isEmpty);
  });

  test('Postpone works with two open occurrences and closes both', () async {
    final before = await row();
    await service.postpone(actionId, PostponeRule.plusOneHour);
    final after = await row();
    expect(after.startAt, isNot(before.startAt));
    expect(await open(), isEmpty);
  });

  test('the action keeps its directions and notes through the buttons', () async {
    await service.start(actionId);
    await service.finish(actionId);
    await service.postpone(actionId, PostponeRule.plusOneHour);
    final links = await (db.select(
      db.actionMetricsTable,
    )..where((t) => t.actionId.equals(actionId))).get();
    expect(links, hasLength(2));
    expect((await row()).notes, contains('Balance Dashboard'));
  });
}
