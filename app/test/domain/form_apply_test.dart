import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/form_apply_service.dart';
import 'package:livenow/domain/form_effects.dart';
import 'package:livenow/domain/form_service.dart';
import 'package:livenow/domain/forms.dart';
import 'package:livenow/domain/growth_rules.dart';
import 'package:livenow/domain/metric_service.dart';

void main() {
  late AppDatabase db;
  late ActionService actions;
  late FormApplyService apply;
  late MetricService metrics;

  setUp(() {
    // Foreign keys ON like the real app: a link to a deleted direction would throw.
    db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys = ON;'),
      ),
    );
    actions = ActionService(db);
    apply = FormApplyService(db);
    metrics = MetricService(db);
  });

  tearDown(() => db.close());

  Future<String> direction(String name) =>
      metrics.saveMetric(name: name, kind: MetricKind.boolean);

  Future<Set<String>> linked(String actionId) async => {
    for (final r in await (db.select(
      db.actionMetricsTable,
    )..where((t) => t.actionId.equals(actionId))).get())
      r.metricId,
  };

  Future<ActionRow> row(String id) =>
      (db.select(db.actionsTable)..where((t) => t.id.equals(id))).getSingle();

  test('every selected action gets the directions and keeps what it had', () async {
    final a = await direction('A');
    final b = await direction('B');
    final c = await direction('C');
    final x = await actions.createAction(name: 'x', metricIds: [a]);
    final y = await actions.createAction(name: 'y');
    final r = await apply.apply([x, y], FormEffects(metricIds: [b, c]));

    expect(await linked(x), {a, b, c});
    expect(await linked(y), {b, c});
    expect(r.actionsChanged, 2);
    expect(r.directionsAdded, 4);
    expect(r.directionsSkipped, 0);
    expect(r.changedAnything, isTrue);
  });

  test('an action that already has everything is not touched', () async {
    final a = await direction('A');
    final full = await actions.createAction(name: 'full', metricIds: [a]);
    final fresh = await actions.createAction(name: 'fresh');
    final before = (await row(full)).updatedAt;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final r = await apply.apply([full, fresh], FormEffects(metricIds: [a]));

    expect((await row(full)).updatedAt, before); // not rewritten
    expect(await linked(fresh), {a});
    expect(r.actionsChanged, 1);
    expect(r.directionsAdded, 1);
  });

  test('a deleted direction is skipped and counted, the rest still applies', () async {
    final keep = await direction('Keep');
    final gone = await direction('Gone');
    await metrics.deleteMetric(gone);
    final x = await actions.createAction(name: 'x');
    final r = await apply.apply([x], FormEffects(metricIds: [gone, keep]));

    expect(await linked(x), {keep});
    expect(r.directionsSkipped, 1);
    expect(r.directionsAdded, 1);
  });

  test('the Countable Activity is set only where there is none', () async {
    final own = await actions.createCountableActivity('Mine');
    final withOwn = await actions.createAction(name: 'with');
    await actions.setCountableActivity(withOwn, own);
    final without = await actions.createAction(name: 'without');

    final r = await apply.apply(
      [withOwn, without],
      const FormEffects(activityName: 'Study'),
    );

    expect((await row(withOwn)).countableActivityId, own); // kept
    final got = (await row(without)).countableActivityId;
    expect(got, isNotNull);
    final names = {
      for (final a in await db.select(db.countableActivitiesTable).get())
        a.id: a.name,
    };
    expect(names[got], 'Study');
    expect(r.activitiesSet, 1);
    expect(r.actionsChanged, 1);
  });

  test('an activity with the same name (any case) is reused, not duplicated', () async {
    final existing = await actions.createCountableActivity('Study');
    final x = await actions.createAction(name: 'x');
    await apply.apply([x], const FormEffects(activityName: ' study '));
    expect((await row(x)).countableActivityId, existing);
    expect((await db.select(db.countableActivitiesTable).get()), hasLength(1));
  });

  test('no activity is created when every action already has one', () async {
    final own = await actions.createCountableActivity('Mine');
    final x = await actions.createAction(name: 'x');
    await actions.setCountableActivity(x, own);
    await apply.apply([x], const FormEffects(activityName: 'Brand new'));
    final all = await db.select(db.countableActivitiesTable).get();
    expect(all.map((a) => a.name), ['Mine']);
  });

  test('ONE undo puts back the directions and the activity', () async {
    final a = await direction('A');
    final x = await actions.createAction(name: 'x');
    final y = await actions.createAction(name: 'y', metricIds: [a]);
    final b = await direction('B');
    final r = await apply.apply(
      [x, y],
      FormEffects(metricIds: [a, b], activityName: 'Study'),
    );
    expect(await linked(x), {a, b});
    expect((await row(x)).countableActivityId, isNotNull);

    await apply.undo(r.undo);
    expect(await linked(x), isEmpty);
    expect(await linked(y), {a}); // what it had before
    expect((await row(x)).countableActivityId, isNull);
    expect((await row(y)).countableActivityId, isNull);
  });

  test('empty effects change nothing', () async {
    final x = await actions.createAction(name: 'x');
    final r = await apply.apply([x], const FormEffects());
    expect(r.changedAnything, isFalse);
    expect(r.actionsChanged, 0);
    expect(await linked(x), isEmpty);
  });

  test('a form end to end: answers, parser, apply', () async {
    final m1 = await direction('Learn at work');
    final m2 = await direction('Practice');
    final form = FormDef(
      name: 'F',
      questions: [
        FormQuestion(
          id: 'q',
          title: 'Learn',
          options: [
            FormOption(id: 'o1', label: 'matches', metricIds: [m1, m2], activityName: 'Study'),
          ],
        ),
      ],
    );
    final svc = FormService(db);
    final id = await svc.save(form);
    final stored = (await svc.get(id))!.def;
    final effects = computeEffects(stored, {'q': {'o1'}});
    final x = await actions.createAction(name: 'x');
    await apply.apply([x], effects);
    expect(await linked(x), {m1, m2});
    expect((await row(x)).countableActivityId, isNotNull);
  });
}
