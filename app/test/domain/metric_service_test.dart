import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/growth_import.dart';
import 'package:livenow/domain/growth_rules.dart';
import 'package:livenow/domain/metric_service.dart';

void main() {
  late AppDatabase db;
  late MetricService service;

  setUp(() {
    // Foreign keys on, like the real connection in data/database.dart.
    db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys = ON;'),
      ),
    );
    service = MetricService(db);
  });

  tearDown(() => db.close());

  Future<Metric> row(String id) =>
      (db.select(db.metricsTable)..where((t) => t.id.equals(id))).getSingle();

  Future<Set<(String, String)>> edges() async =>
      (await db.select(db.metricDependenciesTable).get())
          .map((e) => (e.metricId, e.dependsOnId))
          .toSet();

  group('saveMetric', () {
    test('creates a direction and computes weights down the graph', () async {
      final main = await service.saveMetric(
        name: 'Healthy family',
        kind: MetricKind.boolean,
        isMain: true,
      );
      final sleep = await service.saveMetric(
        name: 'I sleep enough',
        kind: MetricKind.hours,
        window: MetricWindow.week,
        target: 56,
        leadsToIds: [main],
      );
      final bed = await service.saveMetric(
        name: 'I go to bed early',
        kind: MetricKind.count,
        window: MetricWindow.week,
        target: 5,
        leadsToIds: [sleep],
      );

      final m = await row(main);
      expect((m.weight, m.importanceLevel, m.isMain), (1000, 10, true));
      final s = await row(sleep);
      expect((s.weight, s.importanceLevel), (90, 9)); // 9 x 10
      expect(s.kind, 'hours');
      expect(s.timeWindow, 'week');
      expect(s.target, 56);
      final b = await row(bed);
      expect((b.weight, b.importanceLevel), (152, 8)); // 8 x (9 + 10)
      expect(await edges(), {(main, sleep), (sleep, bed)});
    });

    test('editing replaces relations and recomputes weights', () async {
      final main = await service.saveMetric(
        name: 'Main',
        kind: MetricKind.boolean,
        isMain: true,
      );
      final a = await service.saveMetric(
        name: 'A',
        kind: MetricKind.boolean,
        leadsToIds: [main],
      );
      expect((await row(a)).weight, 90);

      // A stops leading to Main and becomes a main direction itself.
      await service.saveMetric(
        id: a,
        name: 'A renamed',
        kind: MetricKind.boolean,
        isMain: true,
      );
      final updated = await row(a);
      expect(updated.name, 'A renamed');
      expect(updated.weight, 1000);
      expect(await edges(), isEmpty);
    });

    test('a boolean direction drops any window and target', () async {
      final id = await service.saveMetric(
        name: 'B',
        kind: MetricKind.boolean,
        window: MetricWindow.week,
        target: 9,
      );
      final r = await row(id);
      expect((r.timeWindow, r.target), (null, 1));
    });

    test('rejects a loop and changes nothing', () async {
      // Chain: A leads to B, B leads to C (C depends on B, B depends on A).
      final a = await service.saveMetric(name: 'A', kind: MetricKind.boolean);
      final b = await service.saveMetric(
        name: 'B',
        kind: MetricKind.boolean,
        dependsOnIds: [a],
      );
      final c = await service.saveMetric(
        name: 'C',
        kind: MetricKind.boolean,
        dependsOnIds: [b],
      );
      // Keeping A -> B but also making C lead to A closes the loop A -> B -> C -> A.
      await expectLater(
        service.saveMetric(
          id: a,
          name: 'A',
          kind: MetricKind.boolean,
          dependsOnIds: [c],
          leadsToIds: [b],
        ),
        throwsA(isA<MetricCycleException>()),
      );
      expect(await edges(), {(b, a), (c, b)});
    });

    test('needs a name, and a window for count/hours', () async {
      expect(
        () => service.saveMetric(name: '  ', kind: MetricKind.boolean),
        throwsArgumentError,
      );
      expect(
        () => service.saveMetric(name: 'X', kind: MetricKind.count),
        throwsArgumentError,
      );
    });
  });

  group('deleteMetric', () {
    test('removes relations and links, undo puts everything back', () async {
      final main = await service.saveMetric(
        name: 'Main',
        kind: MetricKind.boolean,
        isMain: true,
      );
      final mid = await service.saveMetric(
        name: 'Mid',
        kind: MetricKind.boolean,
        leadsToIds: [main],
      );
      final leaf = await service.saveMetric(
        name: 'Leaf',
        kind: MetricKind.boolean,
        leadsToIds: [mid],
      );
      final actions = ActionService(db);
      final actionId = await actions.createAction(
        name: 'Do it',
        metricIds: [mid],
      );

      final undo = await service.deleteMetric(mid);
      expect(await edges(), isEmpty);
      expect(await db.select(db.actionMetricsTable).get(), isEmpty);
      expect((await row(leaf)).weight, 0, reason: 'leaf lost its way to Main');

      await service.undoDelete(undo);
      expect(await edges(), {(main, mid), (mid, leaf)});
      final links = await db.select(db.actionMetricsTable).get();
      expect(links.map((l) => (l.actionId, l.metricId)), [(actionId, mid)]);
      expect((await row(leaf)).weight, 152);
    });

    test(
      'undo skips a relation whose other end was deleted meanwhile',
      () async {
        final a = await service.saveMetric(name: 'A', kind: MetricKind.boolean);
        final b = await service.saveMetric(
          name: 'B',
          kind: MetricKind.boolean,
          leadsToIds: [a],
        );
        final undo = await service.deleteMetric(b);
        await service.deleteMetric(a);
        await service.undoDelete(undo);
        expect((await db.select(db.metricsTable).get()).map((m) => m.id), [b]);
        expect(await edges(), isEmpty);
      },
    );
  });

  group('icons', () {
    test('saveMetric sets, keeps (absent) and clears the icon', () async {
      final id = await service.saveMetric(
        name: 'Sleep',
        kind: MetricKind.boolean,
        icon: const Value('😴'),
      );
      expect((await row(id)).icon, '😴');

      // Editing without mentioning the icon leaves it alone.
      await service.saveMetric(
        id: id,
        name: 'Sleep well',
        kind: MetricKind.boolean,
      );
      expect((await row(id)).icon, '😴');

      await service.saveMetric(
        id: id,
        name: 'Sleep well',
        kind: MetricKind.boolean,
        icon: const Value(null),
      );
      expect((await row(id)).icon, isNull);
    });

    test(
      'applyIcons matches by normalized name and reports the rest',
      () async {
        final id = await service.saveMetric(
          name: 'Мама має здоров’я',
          kind: MetricKind.boolean,
        );
        final other = await service.saveMetric(
          name: 'Other',
          kind: MetricKind.boolean,
        );
        final s = await service.applyIcons({
          "Мама має здоров'я": '💪🏻', // straight apostrophe vs ’ in the DB
          'Nope': '🚫',
        });
        expect(s.matched, 1);
        expect(s.unmatched, ['Nope']);
        expect((await row(id)).icon, '💪🏻');
        expect((await row(other)).icon, isNull);
      },
    );

    test(
      'a CSV re-import keeps the icons of directions still present',
      () async {
        String csv(List<String> rows) => [
          'page_id,objective_name,metric_data_type,numerical_objective,depends_on,improves_count',
          ...rows,
        ].join('\r\n');
        await service.importGrowthDirections(
          csv(['p1,Alpha,Boolean,1,[],0', 'p2,Beta,Boolean,1,[],0']),
        );
        await service.applyIcons({'Alpha': 'A', 'Beta': 'B'});
        await service.importGrowthDirections(
          csv(['p1,Alpha,Boolean,1,[],0', 'p3,Gamma,Boolean,1,[],0']),
        );
        final icons = {
          for (final m in await db.select(db.metricsTable).get())
            m.name: m.icon,
        };
        expect(icons, {'Alpha': 'A', 'Gamma': null});
      },
    );
  });

  group('importGrowthDirections', () {
    // Mirrors the quirks of the real export: BOM, CRLF, quoted cells with
    // commas and doubled quotes, ’ vs ', an empty template row, an unknown
    // type and a relation to a name that isn't in the file.
    String csv() {
      const header =
          'page_id,created_time,objective_name,metric_data_type,'
          'numerical_objective,manual_weight,auto_weight,depends_on,'
          'improves_count';
      final lines = [
        header,
        'p1,2026-05-14 17:00,Мої діти здорові,Boolean,1,,1000,'
            '"[""Я гуляю, дихаю"", ""Мама має здоров\'я"", ""Немає такого""]",1',
        'p2,2026-05-14 17:01,"Я гуляю, дихаю",Weekly Done Hours,7,152,90,[],0',
        'p3,2026-05-14 17:02,Мама має здоров’я,Last 30 Days Done Actions,2,,90,[],0',
        'p4,2026-05-14 17:03,Дивний,Monthly Vibes,3,,,[],0',
        'e1,2026-09-06 10:00,,,,,,,',
      ];
      return '﻿${lines.join('\r\n')}\r\n';
    }

    test('parses kinds, windows, targets, main flags and relations', () async {
      final summary = await service.importGrowthDirections(csv());

      expect(summary.directions, 3);
      expect(summary.relations, 2);
      expect(summary.skippedBlank, 1);
      expect(summary.unsupported, ['Дивний']);
      expect(summary.unresolved, ['Немає такого']);

      final byName = {
        for (final m in await db.select(db.metricsTable).get()) m.name: m,
      };
      final main = byName['Мої діти здорові']!;
      expect((main.kind, main.isMain, main.target), ('boolean', true, 1));
      expect(main.timeWindow, isNull);

      final walk = byName['Я гуляю, дихаю']!;
      expect((walk.kind, walk.timeWindow, walk.target), ('hours', 'week', 7));
      expect(walk.isMain, isFalse);

      final mom = byName['Мама має здоров’я']!;
      expect((mom.kind, mom.timeWindow, mom.target), ('count', 'month', 2));

      // ’ in the name matched ' in the relation; ignored columns didn't leak in.
      expect(await edges(), {(main.id, walk.id), (main.id, mom.id)});
      expect((main.weight, walk.weight, mom.weight), (1000, 90, 90));
    });

    test(
      'replaces every existing direction, relation and action link',
      () async {
        final old = await service.saveMetric(
          name: 'Old',
          kind: MetricKind.boolean,
        );
        await ActionService(db).createAction(name: 'Act', metricIds: [old]);

        await service.importGrowthDirections(csv());

        expect(await db.select(db.actionMetricsTable).get(), isEmpty);
        final names = (await db.select(db.metricsTable).get()).map(
          (m) => m.name,
        );
        expect(names, isNot(contains('Old')));
        expect(names, hasLength(3));
      },
    );

    test('importing the same file twice gives the same result', () async {
      await service.importGrowthDirections(csv());
      final summary = await service.importGrowthDirections(csv());
      expect(summary.directions, 3);
      expect(await db.select(db.metricsTable).get(), hasLength(3));
      expect(await edges(), hasLength(2));
    });

    test('a file without the expected columns changes nothing', () async {
      await service.saveMetric(name: 'Keep me', kind: MetricKind.boolean);
      await expectLater(
        service.importGrowthDirections('a,b\r\n1,2\r\n'),
        throwsFormatException,
      );
      final names = (await db.select(db.metricsTable).get()).map((m) => m.name);
      expect(names, ['Keep me']);
    });
  });

  Future<String> make(String name, {bool main = false}) =>
      service.saveMetric(name: name, kind: MetricKind.boolean, isMain: main);

  group('mindmap positions', () {
    test('savePositions stores positions and leaves others null', () async {
      final a = await make('A');
      final b = await make('B');
      final c = await make('C');
      await service.savePositions({a: (10.5, -20), b: (0, 300.25)});

      expect(((await row(a)).posX, (await row(a)).posY), (10.5, -20));
      expect(((await row(b)).posX, (await row(b)).posY), (0, 300.25));
      expect(((await row(c)).posX, (await row(c)).posY), (null, null));

      // Saving again overwrites; unknown ids are ignored.
      await service.savePositions({a: (1, 2), 'nope': (5, 5)});
      expect(((await row(a)).posX, (await row(a)).posY), (1, 2));
      expect((await row(b)).posX, 0);
    });

    test('clearPositions resets every position', () async {
      final a = await make('A');
      final b = await make('B');
      await service.savePositions({a: (1, 2), b: (3, 4)});
      await service.clearPositions();
      for (final id in [a, b]) {
        final r = await row(id);
        expect((r.posX, r.posY), (null, null));
      }
    });
  });

  test('restorePositions writes exact values, nulls included', () async {
    final a = await make('A');
    final b = await make('B');
    await service.savePositions({a: (1, 2)});
    await service.restorePositions({
      a: (null, null),
      b: (7.5, 8),
      'nope': (1, 1),
    });
    expect(((await row(a)).posX, (await row(a)).posY), (null, null));
    expect(((await row(b)).posX, (await row(b)).posY), (7.5, 8));
  });

  group('relations', () {
    test('addRelation: to depends on from; weights recompute', () async {
      final main = await make('Main', main: true);
      final sub = await make('Sub');
      expect((await row(sub)).weight, 0);

      await service.addRelation(fromId: sub, toId: main);

      // Sub leads to Main, so the edge row is metricId=Main (to) depends on
      // dependsOnId=Sub (from).
      expect(await edges(), {(main, sub)});
      final rel = await service.relationsOf(sub);
      expect(rel.leadsTo, {main});
      expect(rel.dependsOn, isEmpty);
      final relMain = await service.relationsOf(main);
      expect(relMain.dependsOn, {sub});
      expect(relMain.leadsTo, isEmpty);

      // Weight semantics: sub leads to a main -> level 9, weight 9 x 10.
      final s = await row(sub);
      expect((s.weight, s.importanceLevel), (90, 9));
      expect((await row(main)).weight, 1000);
    });

    test('a duplicate addRelation is a no-op', () async {
      final a = await make('A');
      final b = await make('B');
      await service.addRelation(fromId: a, toId: b);
      await service.addRelation(fromId: a, toId: b);
      expect(await edges(), {(b, a)});
      expect(await db.select(db.metricDependenciesTable).get(), hasLength(1));
    });

    test('a direct loop throws and changes nothing', () async {
      final a = await make('A');
      final b = await make('B');
      await service.addRelation(fromId: a, toId: b);
      await expectLater(
        service.addRelation(fromId: b, toId: a),
        throwsA(isA<MetricCycleException>()),
      );
      expect(await edges(), {(b, a)});
    });

    test('a longer loop throws and changes nothing', () async {
      final main = await make('Main', main: true);
      final a = await make('A');
      final b = await make('B');
      final c = await make('C');
      await service.addRelation(fromId: a, toId: b);
      await service.addRelation(fromId: b, toId: c);
      await service.addRelation(fromId: c, toId: main);
      final before = await edges();
      final weightsBefore = {
        for (final m in await db.select(db.metricsTable).get()) m.id: m.weight,
      };

      // C already (transitively) leads from A; C leads to A closes the loop.
      await expectLater(
        service.addRelation(fromId: c, toId: a),
        throwsA(isA<MetricCycleException>()),
      );
      await expectLater(
        service.addRelation(fromId: main, toId: a),
        throwsA(isA<MetricCycleException>()),
      );
      expect(await edges(), before);
      expect({
        for (final m in await db.select(db.metricsTable).get()) m.id: m.weight,
      }, weightsBefore);
    });

    test('a self link throws', () async {
      final a = await make('A');
      expect(
        () => service.addRelation(fromId: a, toId: a),
        throwsArgumentError,
      );
      expect(await edges(), isEmpty);
    });

    test('removeRelation removes it; addRelation restores it', () async {
      final main = await make('Main', main: true);
      final sub = await make('Sub');
      await service.addRelation(fromId: sub, toId: main);
      expect((await row(sub)).weight, 90);

      await service.removeRelation(fromId: sub, toId: main);
      expect(await edges(), isEmpty);
      final s = await row(sub);
      expect((s.weight, s.importanceLevel), (0, 0));

      // Removing a missing relation is harmless.
      await service.removeRelation(fromId: sub, toId: main);

      await service.addRelation(fromId: sub, toId: main);
      expect(await edges(), {(main, sub)});
      expect((await row(sub)).weight, 90);
    });

    test('removing the middle link cuts the path for the far end', () async {
      final main = await make('Main', main: true);
      final mid = await make('Mid');
      final leaf = await make('Leaf');
      await service.addRelation(fromId: mid, toId: main);
      await service.addRelation(fromId: leaf, toId: mid);
      expect((await row(leaf)).weight, greaterThan(0));

      await service.removeRelation(fromId: mid, toId: main);
      expect((await row(mid)).weight, 0);
      expect((await row(leaf)).weight, 0);
    });
  });

  group('parseCsv', () {
    test(
      'quotes, doubled quotes, embedded newlines and a missing final EOL',
      () {
        final rows = parseCsv('a,b\n"x,1","he said ""hi"""\n"two\nlines",z');
        expect(rows, [
          ['a', 'b'],
          ['x,1', 'he said "hi"'],
          ['two\nlines', 'z'],
        ]);
      },
    );
  });

  group('linkAction / unlinkAction', () {
    test('idempotent link, unlink only that pair, cascade-safe', () async {
      final actions = ActionService(db);
      final a = await actions.createAction(name: 'A');
      final b = await actions.createAction(name: 'B');
      final m1 = await service.saveMetric(name: 'M1', kind: MetricKind.boolean);
      final m2 = await service.saveMetric(name: 'M2', kind: MetricKind.boolean);

      await service.linkAction(a, m1);
      await service.linkAction(a, m1);
      await service.linkAction(a, m2);
      await service.linkAction(b, m1);
      Future<Set<(String, String)>> links() async =>
          (await db.select(db.actionMetricsTable).get())
              .map((l) => (l.actionId, l.metricId))
              .toSet();
      expect(await db.select(db.actionMetricsTable).get(), hasLength(3));

      await service.unlinkAction(a, m1);
      expect(await links(), {(a, m2), (b, m1)});
      await service.unlinkAction(a, m1); // no-op
      expect(await links(), {(a, m2), (b, m1)});
      // Rows themselves stay.
      expect(await db.select(db.actionsTable).get(), hasLength(2));
      expect(await db.select(db.metricsTable).get(), hasLength(2));

      await service.deleteMetric(m2);
      expect(await links(), {(b, m1)});
    });
  });
}
