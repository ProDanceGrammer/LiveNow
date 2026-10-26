import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/ids.dart';
import 'package:livenow/core/time_codec.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/plan_rules.dart';
import 'package:livenow/domain/plan_service.dart';
import 'package:livenow/domain/postpone_rules.dart';

/// PlanService: saving plans, generating occurrences, confirming them into real
/// actions (idempotent, one Undo), "this day only" overrides, removing future
/// actions, the rolling "forever" window.
void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late ActionService actions;
  late PlanService plans;

  setUp(() {
    db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys = ON;'),
      ),
    );
    actions = ActionService(db);
    plans = PlanService(db, actions);
  });
  tearDown(() => db.close());

  // "Now" is fixed so the tests do not depend on the clock: Mon 19 Oct 2026
  // 08:00 local (05:00Z). Occurrences before it are never confirmed.
  final now = DateTime.utc(2026, 10, 19, 5);
  DateTime day(int d) => planDate(2026, 10, d);

  Future<String> template({
    String name = 'Breakfast',
    int? minutes = 30,
    bool useAverage = false,
    String? notes,
  }) async {
    final id = newId();
    await db
        .into(db.actionTemplatesTable)
        .insert(
          ActionTemplatesTableCompanion.insert(
            id: id,
            name: name,
            payload: jsonEncode({
              'name': name,
              'estimatedMinutes': ?minutes,
              'useAverage': useAverage,
              'notes': ?notes,
            }),
          ),
        );
    return id;
  }

  Future<String> daily(String templateId, {int startMin = 9 * 60}) =>
      plans.saveItem(
        PlanItemInput(
          name: 'Breakfast plan',
          templateId: templateId,
          kind: PlanKind.cycle,
          startDate: day(19),
          cycle: CycleRule(
            cycleDays: 1,
            occurrences: [CycleOccurrence(day: 0, startMin: startMin)],
          ),
        ),
      );

  Future<List<ActionRow>> allActions() => db.select(db.actionsTable).get();

  group('saving', () {
    test('a plan item round trips through the database', () async {
      final id = await plans.saveItem(
        PlanItemInput(
          name: ' Run ',
          kind: PlanKind.monthly,
          startDate: day(19),
          endDate: planDate(2027, 1, 1),
          forever: false,
          monthly: const MonthlyRule(everyMonths: 2, mode: MonthlyMode.lastDay),
        ),
      );
      final row = (await plans.items()).single;
      expect((row.id, row.name, row.kind), (id, 'Run', 'monthly'));
      final data = plans.decode(row);
      expect(data.monthly!.everyMonths, 2);
      expect(data.endDate, planDate(2027, 1, 1));
      // Editing keeps the id.
      await plans.saveItem(
        PlanItemInput(
          id: id,
          name: 'Run more',
          kind: PlanKind.monthly,
          startDate: day(19),
          monthly: const MonthlyRule(),
        ),
      );
      expect((await plans.items()).single.name, 'Run more');
    });

    test('a new plan item keeps the notes and directions it was made from', () async {
      final metric = newId();
      await db.into(db.metricsTable).insert(
        MetricsTableCompanion(
          id: Value(metric),
          name: const Value('Health'),
          kind: const Value('boolean'),
        ),
      );
      final id = await plans.saveItem(
        PlanItemInput(
          name: 'Gym',
          kind: PlanKind.cycle,
          startDate: day(19),
          cycle: CycleRule(
            cycleDays: 1,
            occurrences: [CycleOccurrence(day: 0, startMin: 9 * 60)],
          ),
          templateNotes: '{"document":{"type":"page","children":[]}}',
          templateMetricIds: [metric],
        ),
      );
      expect(id, isNotEmpty);
      final r = await plans.confirm(from: day(20), to: day(20), nowUtc: now);
      final a = (await allActions()).single;
      expect(r.createdIds, [a.id]);
      expect(a.notes, isNotNull);
      final links = await db.select(db.actionMetricsTable).get();
      expect(links.map((l) => (l.actionId, l.metricId)), [(a.id, metric)]);
    });

    test('a same-name template only gets what it is missing', () async {
      final own = await template(notes: '{"own":true}');
      await plans.saveItem(
        PlanItemInput(
          name: 'Breakfast plan',
          templateId: own,
          kind: PlanKind.cycle,
          startDate: day(19),
          cycle: CycleRule(
            cycleDays: 1,
            occurrences: [CycleOccurrence(day: 0, startMin: 9 * 60)],
          ),
          templateNotes: '{"other":true}',
          templateMetricIds: const ['m1'],
        ),
      );
      final payload =
          jsonDecode(
                (await (db.select(db.actionTemplatesTable)
                          ..where((t) => t.id.equals(own)))
                        .getSingle())
                    .payload,
              )
              as Map;
      expect(payload['notes'], '{"own":true}'); // never overwritten
      expect(payload['metricIds'], ['m1']); // was empty: filled
    });

    test('a nameless plan item is refused', () async {
      expect(
        () => plans.saveItem(
          PlanItemInput(name: '  ', kind: PlanKind.cycle, startDate: day(19)),
        ),
        throwsArgumentError,
      );
    });
  });

  group('confirm', () {
    test('creates real actions from the template, once per occurrence', () async {
      final t = await template(notes: '{"document":{"type":"page","children":[]}}');
      final id = await daily(t);
      final r = await plans.confirm(from: day(19), to: day(21), nowUtc: now);
      // Mon 09:00 is after 08:00: three days, three actions.
      expect(r.createdIds, hasLength(3));
      expect(r.existing, 0);
      final rows = await allActions();
      expect(rows, hasLength(3));
      for (final a in rows) {
        expect(a.planItemId, id);
        expect(a.planKey, isNotNull);
        expect(a.name, 'Breakfast');
        // 09:00 local = 06:00Z, 30 minutes from the template.
        final s = dateTimeFromDb(a.startAt)!;
        expect(s.hour, 6);
        expect(dateTimeFromDb(a.endAt)!.difference(s), const Duration(minutes: 30));
        expect(a.notes, isNotNull);
      }
      expect(rows.map((a) => a.planKey).toSet(), {
        '2026-10-19#0',
        '2026-10-20#0',
        '2026-10-21#0',
      });
    });

    test('is idempotent: confirming again creates nothing', () async {
      await daily(await template());
      await plans.confirm(from: day(19), to: day(21), nowUtc: now);
      final again = await plans.confirm(from: day(19), to: day(23), nowUtc: now);
      expect(again.existing, 3);
      expect(again.createdIds, hasLength(2)); // only 22 and 23 are new
      expect(await allActions(), hasLength(5));
    });

    test('occurrences in the past are never created', () async {
      await daily(await template(), startMin: 7 * 60); // 07:00 < 08:00 now
      final r = await plans.confirm(from: day(19), to: day(19), nowUtc: now);
      expect(r.createdIds, isEmpty);
    });

    test('a paused plan item confirms nothing; selecting items narrows it', () async {
      final t = await template();
      final a = await daily(t);
      final b = await plans.saveItem(
        PlanItemInput(
          name: 'Other',
          templateId: t,
          kind: PlanKind.cycle,
          startDate: day(19),
          cycle: const CycleRule(
            cycleDays: 1,
            occurrences: [CycleOccurrence(day: 0, startMin: 15 * 60)],
          ),
        ),
      );
      await plans.setPaused(a, true);
      final r = await plans.confirm(
        itemIds: {a, b},
        from: day(20),
        to: day(20),
        nowUtc: now,
      );
      expect(r.createdIds, hasLength(1));
      expect((await allActions()).single.planItemId, b);
    });

    test('without a template the action takes the occurrence name and times', () async {
      await plans.saveItem(
        PlanItemInput(
          name: 'Plain',
          kind: PlanKind.cycle,
          startDate: day(20),
          cycle: const CycleRule(
            cycleDays: 1,
            occurrences: [CycleOccurrence(day: 0, startMin: 600, durationMin: 45)],
          ),
        ),
      );
      await plans.confirm(from: day(20), to: day(20), nowUtc: now);
      final a = (await allActions()).single;
      expect(a.name, 'Plain');
      expect(
        dateTimeFromDb(a.endAt)!.difference(dateTimeFromDb(a.startAt)!),
        const Duration(minutes: 45),
      );
    });

    test('a deleted template does not break a confirmation', () async {
      final t = await template();
      await daily(t);
      await (db.delete(db.actionTemplatesTable)..where((x) => x.id.equals(t))).go();
      final r = await plans.confirm(from: day(20), to: day(20), nowUtc: now);
      expect(r.createdIds, hasLength(1));
    });

    test('one Undo takes the whole confirmation back', () async {
      await daily(await template());
      final r = await plans.confirm(from: day(20), to: day(22), nowUtc: now);
      expect(await allActions(), hasLength(3));
      await plans.undoConfirm(r.createdIds);
      expect(await allActions(), isEmpty);
    });

    test('the average of finished runs wins when the template says so', () async {
      final t = await template(name: 'Run', minutes: 30, useAverage: true);
      await plans.saveItem(
        PlanItemInput(
          name: 'Runs',
          templateId: t,
          kind: PlanKind.cycle,
          startDate: day(20),
          cycle: const CycleRule(
            cycleDays: 1,
            occurrences: [CycleOccurrence(day: 0, startMin: 600)],
          ),
        ),
      );
      // Three finished 'Run' actions of 50 minutes each, a few days ago.
      for (var i = 0; i < 3; i++) {
        final id = await actions.createAction(
          name: 'Run',
          startAt: DateTime.now().toUtc().subtract(Duration(days: 2 + i)),
          endAt: DateTime.now()
              .toUtc()
              .subtract(Duration(days: 2 + i))
              .add(const Duration(minutes: 50)),
        );
        await actions.toggleDone(id);
      }
      expect(await plans.defaultMinutes(plans.decode((await plans.items()).single)), 50);
    });
  });

  group('overrides', () {
    test('a moved / renamed occurrence is what gets confirmed; a skipped one is not', () async {
      final t = await template();
      final id = await daily(t);
      await plans.setOverride(
        itemId: id,
        date: day(20),
        index: 0,
        startMin: 11 * 60,
        durationMin: 20,
        name: 'Late breakfast',
      );
      await plans.setOverride(itemId: id, date: day(21), index: 0, skipped: true);
      final r = await plans.confirm(from: day(20), to: day(22), nowUtc: now);
      expect(r.createdIds, hasLength(2));
      final byKey = {for (final a in await allActions()) a.planKey!: a};
      final moved = byKey['2026-10-20#0']!;
      expect(moved.name, 'Late breakfast');
      expect(dateTimeFromDb(moved.startAt)!.hour, 8); // 11:00 local
      expect(
        dateTimeFromDb(moved.endAt)!.difference(dateTimeFromDb(moved.startAt)!),
        const Duration(minutes: 20),
      );
      expect(byKey.containsKey('2026-10-21#0'), isFalse);
      // Clearing the override brings the plain occurrence back.
      await plans.clearOverride(id, day(21), 0);
      final again = await plans.confirm(from: day(21), to: day(21), nowUtc: now);
      expect(again.createdIds, hasLength(1));
    });

    test('the same occurrence overridden twice is one row', () async {
      final id = await daily(await template());
      await plans.setOverride(itemId: id, date: day(20), index: 0, startMin: 600);
      await plans.setOverride(itemId: id, date: day(20), index: 0, startMin: 660);
      final rows = await db.select(db.planOverridesTable).get();
      expect(rows, hasLength(1));
      expect(rows.single.startMin, 660);
    });
  });

  group('remove future', () {
    test('only future, undone, untouched actions of THAT plan go', () async {
      final t = await template();
      final a = await daily(t);
      final other = await plans.saveItem(
        PlanItemInput(
          name: 'Other',
          templateId: t,
          kind: PlanKind.cycle,
          startDate: day(20),
          cycle: const CycleRule(
            cycleDays: 1,
            occurrences: [CycleOccurrence(day: 0, startMin: 15 * 60)],
          ),
        ),
      );
      await plans.confirm(from: day(20), to: day(24), nowUtc: now);
      final mine = [
        for (final r in await allActions())
          if (r.planItemId == a) r,
      ]..sort((x, y) => x.planKey!.compareTo(y.planKey!));
      expect(mine, hasLength(5));
      // One was edited, one is done: both stay.
      await actions.updateSchedule(
        mine[0].id,
        startAt: dateTimeFromDb(mine[0].startAt)!.add(const Duration(minutes: 5)),
        endAt: dateTimeFromDb(mine[0].endAt)!.add(const Duration(minutes: 5)),
      );
      await actions.toggleDone(mine[1].id);
      // The actions are dated 20-24 Oct 2026; "now" for the rule is before them.
      final undo = await plans.removeFuture(a, nowUtc: now);
      expect(undo, isNotNull);
      final left = await allActions();
      expect(left.where((r) => r.planItemId == a), hasLength(2));
      expect(left.where((r) => r.planItemId == other), hasLength(5));
      // Undo brings them back.
      await actions.undoDeleteMany(undo!);
      expect((await allActions()).where((r) => r.planItemId == a), hasLength(5));
    });

    test('nothing to remove returns null', () async {
      final a = await daily(await template());
      expect(await plans.removeFuture(a, nowUtc: now), isNull);
    });
  });

  group('delete', () {
    test('deleting a plan item removes its overrides; its actions stay (or go with removeFuture); Undo restores', () async {
      final id = await daily(await template());
      await plans.setOverride(itemId: id, date: day(21), index: 0, skipped: true);
      await plans.confirm(from: day(20), to: day(22), nowUtc: now);
      expect(await allActions(), hasLength(2)); // 21st skipped

      final keep = await plans.deleteItem(id);
      expect(await plans.items(), isEmpty);
      expect(await db.select(db.planOverridesTable).get(), isEmpty);
      expect(await allActions(), hasLength(2), reason: 'the actions stay');
      await plans.undoDeleteItem(keep!);
      expect(await plans.items(), hasLength(1));
      expect(await db.select(db.planOverridesTable).get(), hasLength(1));

      final gone = await plans.deleteItem(id, removeFuture: true);
      expect(await allActions(), isEmpty);
      await plans.undoDeleteItem(gone!);
      expect(await allActions(), hasLength(2));
    });
  });

  group('forever', () {
    test('refill creates the next 8 weeks once and tops up later', () async {
      final t = await template();
      await plans.saveItem(
        PlanItemInput(
          name: 'Forever',
          templateId: t,
          kind: PlanKind.cycle,
          startDate: day(19),
          forever: true,
          cycle: const CycleRule(
            cycleDays: 1,
            occurrences: [CycleOccurrence(day: 0, startMin: 15 * 60)],
          ),
        ),
      );
      final first = await plans.refillForever(nowUtc: now);
      expect(first.createdIds, hasLength(8 * 7 + 1)); // today 15:00 + 56 days
      final second = await plans.refillForever(nowUtc: now);
      expect(second.createdIds, isEmpty);
      // A week later two more weeks of days are needed.
      final later = await plans.refillForever(
        nowUtc: now.add(const Duration(days: 7)),
      );
      expect(later.createdIds, hasLength(7));
    });

    test('a non-forever or paused item is never refilled', () async {
      final t = await template();
      final id = await daily(t); // not forever
      expect((await plans.refillForever(nowUtc: now)).createdIds, isEmpty);
      await plans.saveItem(
        PlanItemInput(
          id: id,
          name: 'Breakfast plan',
          templateId: t,
          kind: PlanKind.cycle,
          startDate: day(19),
          forever: true,
          paused: true,
          cycle: const CycleRule(
            cycleDays: 1,
            occurrences: [CycleOccurrence(day: 0, startMin: 600)],
          ),
        ),
      );
      expect((await plans.refillForever(nowUtc: now)).createdIds, isEmpty);
    });
  });

  group('occurrences', () {
    test('lists the occurrences of every unpaused item in a range, overrides applied', () async {
      final id = await daily(await template());
      await plans.setOverride(itemId: id, date: day(20), index: 0, startMin: 600);
      final occ = await plans.occurrences(day(19), day(21));
      expect(occ, hasLength(3));
      expect(occ[1].startMin, 600);
      expect(occ.first.durationMin, 30);
    });
  });

  group('from scratch, preview and the pattern', () {
    test('a plan item made without a template also creates one (name + minutes)', () async {
      final id = await plans.saveItem(
        PlanItemInput(
          name: 'Stretching',
          kind: PlanKind.cycle,
          startDate: day(19),
          manualMinutes: 25,
          cycle: const CycleRule(
            cycleDays: 7,
            occurrences: [CycleOccurrence(day: 0, startMin: 480)],
          ),
        ),
      );
      final row = (await plans.items()).single;
      expect(row.id, id);
      expect(row.templateId, isNotNull);
      final t = await (db.select(
        db.actionTemplatesTable,
      )..where((x) => x.id.equals(row.templateId!))).getSingle();
      expect(t.name, 'Stretching');
      expect(jsonDecode(t.payload)['estimatedMinutes'], 25);
      // Editing it later does NOT make another template.
      await plans.saveItem(
        PlanItemInput(
          id: id,
          name: 'Stretching',
          templateId: row.templateId,
          kind: PlanKind.cycle,
          startDate: day(19),
          cycle: const CycleRule(
            cycleDays: 7,
            occurrences: [CycleOccurrence(day: 0, startMin: 480)],
          ),
        ),
      );
      expect(await db.select(db.actionTemplatesTable).get(), hasLength(1));
      // 25 minutes come through to the real action.
      await plans.confirm(from: day(26), to: day(26), nowUtc: now);
      final a = (await allActions()).single;
      expect(
        dateTimeFromDb(a.endAt)!.difference(dateTimeFromDb(a.startAt)!),
        const Duration(minutes: 25),
      );
    });

    test('preview counts what a confirmation would create and what exists', () async {
      await daily(await template());
      final before = await plans.preview(from: day(20), to: day(24), nowUtc: now);
      expect((before.toCreate.length, before.existing), (5, 0));
      await plans.confirm(from: day(20), to: day(22), nowUtc: now);
      final after = await plans.preview(from: day(20), to: day(24), nowUtc: now);
      expect((after.toCreate.length, after.existing), (2, 3));
      expect(await allActions(), hasLength(3), reason: 'a preview creates nothing');
    });

    test('shiftPattern changes the rule (every repetition) and drops the overrides of that occurrence', () async {
      final id = await daily(await template());
      await plans.setOverride(itemId: id, date: day(21), index: 0, startMin: 700);
      await plans.shiftPattern(id, 0, startMin: 600, durationMin: 40);
      final occ = await plans.occurrences(day(20), day(22));
      expect(occ.map((o) => (o.startMin, o.durationMin)).toSet(), {(600, 40)});
      expect(await db.select(db.planOverridesTable).get(), isEmpty);
      // A monthly rule is shifted too.
      final m = await plans.saveItem(
        PlanItemInput(
          name: 'Rent',
          kind: PlanKind.monthly,
          startDate: day(19),
          monthly: const MonthlyRule(day: 20),
        ),
      );
      await plans.shiftPattern(m, 0, startMin: 900, durationMin: 15);
      final mo = (await plans.occurrences(day(20), day(20)))
          .where((o) => o.planItemId == m)
          .single;
      expect((mo.startMin, mo.durationMin), (900, 15));
    });
  });
}
