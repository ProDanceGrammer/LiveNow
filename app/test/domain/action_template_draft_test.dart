import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/ids.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/chain_schedule.dart';
import 'package:livenow/domain/postpone_rules.dart';

/// `templateDraft` (what a template gives a new action), `setDiaryBlocks` and the
/// pure `adjacentSchedule` the Connected actions block uses.
void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late ActionService actions;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    actions = ActionService(db);
  });
  tearDown(() => db.close());

  Future<String> template(Map<String, Object?> payload) async {
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

  final start = DateTime.utc(2026, 10, 20, 7); // 10:00 Istanbul

  group('templateDraft', () {
    test('a timed template: name, notes, directions, duration, times', () async {
      final metric = await db
          .into(db.metricsTable)
          .insert(
            MetricsTableCompanion.insert(
              id: 'm1',
              name: 'Health',
              kind: const Value('boolean'),
              timeWindow: const Value('week'),
            ),
          )
          .then((_) => 'm1');
      final t = await template({
        'name': 'Shower',
        'estimatedMinutes': 20,
        'useAverage': false,
        'notes': '{"document":{"type":"page","children":[]}}',
        'metricIds': [metric, 'deleted-direction'],
        'diaryBlocks': ' a, b ',
      });
      final d = await actions.templateDraft(t, startUtc: start);
      expect(d.name, 'Shower');
      expect(d.startAt, start);
      expect(d.endAt, start.add(const Duration(minutes: 20)));
      expect(d.metricIds, [metric]); // the deleted direction is dropped
      expect(d.notes, isNotNull);
      expect(d.diaryBlocks, 'a, b');
      expect(d.isAllDay, isFalse);
    });

    test('an explicit duration wins; no start = no times', () async {
      final t = await template({'name': 'Walk', 'estimatedMinutes': 20});
      final d = await actions.templateDraft(
        t,
        startUtc: start,
        duration: const Duration(minutes: 45),
      );
      expect(d.endAt, start.add(const Duration(minutes: 45)));
      final bare = await actions.templateDraft(t);
      expect(bare.startAt, isNull);
      expect(bare.endAt, isNull);
    });

    test('an all-day template gets that day, no end', () async {
      final t = await template({'name': 'Rest day', 'isAllDay': true});
      final d = await actions.templateDraft(t, startUtc: start);
      expect(d.isAllDay, isTrue);
      expect(d.endAt, isNull);
      // Istanbul midnight of 20 Oct = 21:00Z the day before.
      expect(d.startAt, DateTime.utc(2026, 10, 19, 21));
    });

    test('the Countable Activity of the same name comes along', () async {
      final act = await actions.createCountableActivity('Reading');
      final t = await template({'name': 'reading'});
      final d = await actions.templateDraft(t, startUtc: start);
      expect(d.countableActivityId, act);
    });

    test('a deleted template is a StateError', () async {
      expect(
        () => actions.templateDraft('nope'),
        throwsA(isA<StateError>()),
      );
    });

    test('createFromTemplateAt is unchanged: same data, blocks written', () async {
      final t = await template({
        'name': 'Cook',
        'estimatedMinutes': 30,
        'useAverage': false,
        'diaryBlocks': 'x',
      });
      final id = await actions.createFromTemplateAt(t, start);
      final row = await (db.select(
        db.actionsTable,
      )..where((r) => r.id.equals(id))).getSingle();
      expect(row.name, 'Cook');
      expect(row.resultNote, 'x');
      expect(
        DateTime.parse(row.endAt!).difference(DateTime.parse(row.startAt!)),
        const Duration(minutes: 30),
      );
    });
  });

  test('setDiaryBlocks ignores empty text', () async {
    final id = await actions.createAction(name: 'A');
    await actions.setDiaryBlocks(id, '  ');
    await actions.setDiaryBlocks(id, null);
    var row = await (db.select(db.actionsTable)..where((r) => r.id.equals(id))).getSingle();
    expect(row.resultNote, isNull);
    await actions.setDiaryBlocks(id, ' q ');
    row = await (db.select(db.actionsTable)..where((r) => r.id.equals(id))).getSingle();
    expect(row.resultNote, 'q');
  });

  group('adjacentSchedule', () {
    const len = Duration(minutes: 30);
    final s = DateTime.utc(2026, 10, 20, 7);
    final e = DateTime.utc(2026, 10, 20, 8);

    test('before ends when the current starts', () {
      final r = adjacentSchedule(
        before: true,
        startAt: s,
        endAt: e,
        isAllDay: false,
        length: len,
      )!;
      expect(r.end, s);
      expect(r.start, s.subtract(len));
    });

    test('after starts when the current ends (start + 1 h without an end)', () {
      var r = adjacentSchedule(
        before: false,
        startAt: s,
        endAt: e,
        isAllDay: false,
        length: len,
      )!;
      expect(r.start, e);
      expect(r.end, e.add(len));
      r = adjacentSchedule(
        before: false,
        startAt: s,
        endAt: null,
        isAllDay: false,
        length: len,
      )!;
      expect(r.start, s.add(const Duration(hours: 1)));
    });

    test('all-day or unscheduled: no schedule', () {
      expect(
        adjacentSchedule(
          before: true,
          startAt: s,
          endAt: null,
          isAllDay: true,
          length: len,
        ),
        isNull,
      );
      expect(
        adjacentSchedule(
          before: false,
          startAt: null,
          endAt: null,
          isAllDay: false,
          length: len,
        ),
        isNull,
      );
    });
  });
}
