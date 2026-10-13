import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/bulk_edit_service.dart';
import 'package:livenow/domain/dependency_service.dart';
import 'package:livenow/domain/growth_rules.dart';
import 'package:livenow/domain/metric_service.dart';

void main() {
  late AppDatabase db;
  late BulkEditService bulk;
  late ActionService actions;
  late DependencyService deps;
  late String m1, m2, m3;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    bulk = BulkEditService(db);
    actions = ActionService(db);
    deps = DependencyService(db);
    final metrics = MetricService(db);
    Future<String> metric(String n) =>
        metrics.saveMetric(name: n, kind: MetricKind.boolean);
    m1 = await metric('one');
    m2 = await metric('two');
    m3 = await metric('three');
  });
  tearDown(() => db.close());

  Future<Set<String>> metricsOf(String id) async => {
    for (final r in await (db.select(
      db.actionMetricsTable,
    )..where((t) => t.actionId.equals(id))).get())
      r.metricId,
  };

  Future<Set<(String, String)>> edges() async => {
    for (final e in await db.select(db.actionDependenciesTable).get())
      (e.predecessorId, e.successorId),
  };

  group('growth directions', () {
    test('Add keeps what each action has and dedupes', () async {
      final a = await actions.createAction(name: 'a', metricIds: [m1]);
      final b = await actions.createAction(name: 'b');
      await bulk.setMetricsMany([a, b], [m1, m2], BulkMode.add);
      expect(await metricsOf(a), {m1, m2});
      expect(await metricsOf(b), {m1, m2});
      final rows = await db.select(db.actionMetricsTable).get();
      expect(rows.where((r) => r.actionId == a), hasLength(2)); // no duplicate
    });

    test('Remove only takes the chosen ones away', () async {
      final a = await actions.createAction(name: 'a', metricIds: [m1, m2, m3]);
      final b = await actions.createAction(name: 'b', metricIds: [m3]);
      await bulk.setMetricsMany([a, b], [m1, m3], BulkMode.remove);
      expect(await metricsOf(a), {m2});
      expect(await metricsOf(b), isEmpty);
    });

    test('Replace gives every action exactly the chosen set', () async {
      final a = await actions.createAction(name: 'a', metricIds: [m1, m2]);
      final b = await actions.createAction(name: 'b');
      await bulk.setMetricsMany([a, b], [m3], BulkMode.replace);
      expect(await metricsOf(a), {m3});
      expect(await metricsOf(b), {m3});
      await bulk.setMetricsMany([a, b], const [], BulkMode.replace);
      expect(await metricsOf(a), isEmpty);
    });

    test('Undo restores each action and only changed ones are recorded', () async {
      final a = await actions.createAction(name: 'a', metricIds: [m1]);
      final b = await actions.createAction(name: 'b', metricIds: [m1, m2]);
      final undo = await bulk.setMetricsMany([a, b], [m1], BulkMode.add);
      expect(undo.before.keys, isEmpty); // nothing changed
      final real = await bulk.setMetricsMany([a, b], [m3], BulkMode.replace);
      expect(real.before.keys, {a, b});
      await bulk.undoSetMetricsMany(real);
      expect(await metricsOf(a), {m1});
      expect(await metricsOf(b), {m1, m2});
    });

    test('a changed action moves its updated_at', () async {
      final a = await actions.createAction(name: 'a');
      await (db.update(db.actionsTable)..where((t) => t.id.equals(a))).write(
        const ActionsTableCompanion(
          updatedAt: Value('2000-01-01T00:00:00.000Z'),
        ),
      );
      final before = (await (db.select(db.actionsTable)
            ..where((t) => t.id.equals(a))).getSingle()).updatedAt;
      await bulk.setMetricsMany([a], [m1], BulkMode.add);
      final after = (await (db.select(db.actionsTable)
            ..where((t) => t.id.equals(a))).getSingle()).updatedAt;
      expect(after.compareTo(before), greaterThan(0));
    });
  });

  group('previous / next links', () {
    test('Add: the target becomes the previous of each; loops are skipped', () async {
      final t = await actions.createAction(name: 'target');
      final a = await actions.createAction(name: 'a');
      final b = await actions.createAction(name: 'b');
      // b already leads to the target, so target -> b would close a loop.
      await deps.addDependency(predecessorId: b, successorId: t);
      final r = await bulk.linkMany(
        [a, b],
        targetId: t,
        side: LinkSide.previous,
        mode: BulkMode.add,
      );
      expect(r.linked, 1);
      expect(r.skippedLoop, 1);
      expect(await edges(), {(t, a), (b, t)});
    });

    test('Add on the Next side links each selected action to the target', () async {
      final t = await actions.createAction(name: 'target');
      final a = await actions.createAction(name: 'a');
      final b = await actions.createAction(name: 'b');
      await bulk.linkMany(
        [a, b],
        targetId: t,
        side: LinkSide.next,
        mode: BulkMode.add,
      );
      expect(await edges(), {(a, t), (b, t)});
    });

    test('Remove only drops the edges to the target', () async {
      final t = await actions.createAction(name: 'target');
      final a = await actions.createAction(name: 'a');
      final other = await actions.createAction(name: 'other');
      await deps.addDependency(predecessorId: t, successorId: a);
      await deps.addDependency(predecessorId: other, successorId: a);
      final r = await bulk.linkMany(
        [a],
        targetId: t,
        side: LinkSide.previous,
        mode: BulkMode.remove,
      );
      expect(r.removed, 1);
      expect(await edges(), {(other, a)});
    });

    test('Replace: only the target stays; no target clears the side', () async {
      final t = await actions.createAction(name: 'target');
      final a = await actions.createAction(name: 'a');
      final o1 = await actions.createAction(name: 'o1');
      final next = await actions.createAction(name: 'next');
      await deps.addDependency(predecessorId: o1, successorId: a);
      await deps.addDependency(predecessorId: a, successorId: next);
      await bulk.linkMany(
        [a],
        targetId: t,
        side: LinkSide.previous,
        mode: BulkMode.replace,
      );
      // The other PREVIOUS is gone, the NEXT side is untouched.
      expect(await edges(), {(t, a), (a, next)});
      await bulk.linkMany(
        [a],
        targetId: null,
        side: LinkSide.previous,
        mode: BulkMode.replace,
      );
      expect(await edges(), {(a, next)});
    });

    test('Undo removes what was added and restores what was removed', () async {
      final t = await actions.createAction(name: 'target');
      final a = await actions.createAction(name: 'a');
      final o1 = await actions.createAction(name: 'o1');
      await deps.addDependency(predecessorId: o1, successorId: a);
      final r = await bulk.linkMany(
        [a],
        targetId: t,
        side: LinkSide.previous,
        mode: BulkMode.replace,
      );
      expect(await edges(), {(t, a)});
      await bulk.undoLinkMany(r.undo);
      expect(await edges(), {(o1, a)});
    });

    test('an edge that already exists is not counted and not undone', () async {
      final t = await actions.createAction(name: 'target');
      final a = await actions.createAction(name: 'a');
      await deps.addDependency(predecessorId: t, successorId: a);
      final r = await bulk.linkMany(
        [a],
        targetId: t,
        side: LinkSide.previous,
        mode: BulkMode.add,
      );
      expect(r.linked, 0);
      await bulk.undoLinkMany(r.undo);
      expect(await edges(), {(t, a)});
    });

    test('the target itself in the selection is left out', () async {
      final t = await actions.createAction(name: 'target');
      final r = await bulk.linkMany(
        [t],
        targetId: t,
        side: LinkSide.next,
        mode: BulkMode.add,
      );
      expect(r.linked, 0);
      expect(await edges(), isEmpty);
    });
  });
}
