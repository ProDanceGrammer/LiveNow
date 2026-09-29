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
}
