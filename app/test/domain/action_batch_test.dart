import 'package:drift/drift.dart' show TableInfo;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/ids.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/dependency_service.dart';
import 'package:livenow/domain/postpone_rules.dart';

void main() {
  late AppDatabase db;
  late ActionService service;
  late DependencyService deps;

  setUpAll(initPostponeTimeZoneData);

  setUp(() {
    // Foreign keys on, like the real connection.
    db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys = ON;'),
      ),
    );
    service = ActionService(db);
    deps = DependencyService(db);
  });

  tearDown(() => db.close());

  Future<int> count(TableInfo t) async => (await db.select(t).get()).length;

  group('deleteActions / undoDeleteMany', () {
    test(
      'deletes all, undo restores all with links, notes and history',
      () async {
        final metric = newId();
        await db
            .into(db.metricsTable)
            .insert(MetricsTableCompanion.insert(id: metric, name: 'M'));
        final a = await service.createAction(
          name: 'A',
          notes: '{"n":1}',
          metricIds: [metric],
        );
        final b = await service.createAction(name: 'B');
        final c = await service.createAction(name: 'C');
        final outside = await service.createAction(name: 'Outside');
        await deps.addDependency(predecessorId: a, successorId: b);
        await deps.addDependency(predecessorId: b, successorId: c);
        await deps.addDependency(predecessorId: outside, successorId: a);
        await service.start(a);

        final undo = await service.deleteActions([a, b, c]);
        expect(undo.count, 3);
        expect(await count(db.actionsTable), 1); // only "Outside"
        expect(await count(db.actionDependenciesTable), 0);
        expect(await count(db.actionMetricsTable), 0);
        expect(await count(db.actionOccurrencesTable), 0);

        await service.undoDeleteMany(undo);
        expect(await count(db.actionsTable), 4);
        // a->b and b->c (both ends deleted) AND outside->a (one end kept).
        final edges = (await db.select(db.actionDependenciesTable).get())
            .map((e) => '${e.predecessorId}>${e.successorId}')
            .toSet();
        expect(edges, {'$a>$b', '$b>$c', '$outside>$a'});
        expect(await count(db.actionMetricsTable), 1);
        expect(await count(db.actionOccurrencesTable), 1);
        final restored = await (db.select(
          db.actionsTable,
        )..where((t) => t.id.equals(a))).getSingle();
        expect(restored.notes, '{"n":1}');
      },
    );

    test('skips unknown and duplicate ids', () async {
      final a = await service.createAction(name: 'A');
      final undo = await service.deleteActions([a, 'nope', a]);
      expect(undo.count, 1);
      await service.undoDeleteMany(undo);
      expect(await count(db.actionsTable), 1);
    });

    test('an empty list is a no-op', () async {
      final undo = await service.deleteActions([]);
      expect(undo.count, 0);
      await service.undoDeleteMany(undo);
    });
  });

  group('moveActions / undoMoveActions', () {
    test(
      'moves several, undo puts every schedule back (nulls included)',
      () async {
        final s1 = DateTime.utc(2026, 10, 5, 9);
        final e1 = DateTime.utc(2026, 10, 5, 10);
        final a = await service.createAction(name: 'A', startAt: s1, endAt: e1);
        final b = await service.createAction(name: 'B'); // unscheduled
        final link = await service.createAction(name: 'Linked');
        await deps.addDependency(predecessorId: a, successorId: link);

        final undo = await service.moveActions([
          ScheduleChange(
            a,
            startAt: s1.add(const Duration(days: 1)),
            endAt: e1.add(const Duration(days: 1)),
          ),
          ScheduleChange(
            b,
            startAt: DateTime.utc(2026, 10, 6, 12),
            endAt: DateTime.utc(2026, 10, 6, 13),
          ),
          ScheduleChange('missing', startAt: s1, endAt: e1),
        ]);
        expect(undo.before, hasLength(2));

        Future<ActionRow> row(String id) => (db.select(
          db.actionsTable,
        )..where((t) => t.id.equals(id))).getSingle();
        expect((await row(a)).startAt, contains('2026-10-06T09'));
        expect((await row(b)).startAt, contains('2026-10-06T12'));

        await service.undoMoveActions(undo);
        expect((await row(a)).startAt, contains('2026-10-05T09'));
        expect((await row(a)).endAt, contains('2026-10-05T10'));
        expect((await row(b)).startAt, isNull);
        expect((await row(b)).endAt, isNull);
        // Moving never touches links.
        expect(await count(db.actionDependenciesTable), 1);
      },
    );

    test(
      'a running action keeps its open occurrence in step, also on undo',
      () async {
        final a = await service.createAction(
          name: 'Run',
          startAt: DateTime.utc(2026, 10, 5, 9),
          endAt: DateTime.utc(2026, 10, 5, 10),
        );
        await service.start(a);
        final started =
            (await db.select(db.actionOccurrencesTable).get()).single;
        final undo = await service.moveActions([
          ScheduleChange(
            a,
            startAt: DateTime.utc(2026, 10, 7, 9),
            endAt: DateTime.utc(2026, 10, 7, 10),
          ),
        ]);
        final moved = (await db.select(db.actionOccurrencesTable).get()).single;
        expect(moved.startedAt, contains('2026-10-07T09'));
        await service.undoMoveActions(undo);
        final back = (await db.select(db.actionOccurrencesTable).get()).single;
        expect(back.startedAt, started.startedAt);
      },
    );
  });
}
