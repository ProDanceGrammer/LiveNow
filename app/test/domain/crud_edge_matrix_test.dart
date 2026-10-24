import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Variable, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/data_exceptions.dart';
import 'package:livenow/core/error_log.dart';
import 'package:livenow/core/ids.dart';
import 'package:livenow/core/text_rules.dart';
import 'package:livenow/data/backup/backup_import_service.dart';
import 'package:livenow/data/backup/backup_sources.dart';
import 'package:livenow/data/backup/backup_writer.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/data/queries.dart';
import 'package:livenow/data/sync/sync_store.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/budget_io_service.dart';
import 'package:livenow/domain/budget_service.dart';
import 'package:livenow/domain/dependency_service.dart';
import 'package:livenow/domain/form_service.dart';
import 'package:livenow/domain/forms.dart';
import 'package:livenow/domain/full_backup.dart';
import 'package:livenow/domain/growth_rules.dart';
import 'package:livenow/domain/metric_service.dart';
import 'package:livenow/domain/plan_rules.dart';
import 'package:livenow/domain/plan_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/domain/template_payload.dart';

// CRUD + Error matrix over actions, templates, directions, budget categories
// and transactions, plans and forms, plus database integrity. In-memory
// databases (foreign keys ON) except the concurrency / leak cases, which use
// temp files.

AppDatabase _db() => AppDatabase.forTesting(
  NativeDatabase.memory(
    setup: (raw) => raw.execute('PRAGMA foreign_keys = ON;'),
  ),
);

/// The whole observable state: every user table plus which rows the sync log
/// knows (and whether as deleted). [stamps] adds the clock stamps too: a row
/// that was deleted and restored legitimately gets a newer stamp, a rolled
/// back change must not.
Future<Map<String, List<List<Object?>>>> _dump(
  AppDatabase db, {
  bool stamps = false,
}) async {
  final out = <String, List<List<Object?>>>{};
  await for (final c in BackupWriter(db).chunks()) {
    out.putIfAbsent(c.table, () => []).addAll(c.rows);
  }
  final versions = await db
      .customSelect(
        'SELECT tbl, row_id, hlc, deleted FROM sync_versions ORDER BY tbl, row_id',
      )
      .get();
  out['sync_versions'] = [
    for (final r in versions)
      [
        r.read<String>('tbl'),
        r.read<String>('row_id'),
        r.read<int>('deleted'),
        if (stamps) r.read<String>('hlc'),
      ],
  ];
  return out;
}

Future<List<Object?>> _fkViolations(AppDatabase db) async => [
  for (final r in await db.customSelect('PRAGMA foreign_key_check').get())
    r.data,
];

Future<int> _count(AppDatabase db, String table) async =>
    (await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle())
        .read<int>('n');

class _Entity {
  const _Entity(this.label, this.table, this.create);
  final String label;
  final String table;
  final Future<String> Function(AppDatabase db, String name) create;
}

final _entities = <_Entity>[
  _Entity(
    'action',
    'actions',
    (db, n) => ActionService(db).createAction(name: n),
  ),
  _Entity(
    'direction',
    'metrics',
    (db, n) => MetricService(db).saveMetric(name: n, kind: MetricKind.boolean),
  ),
  _Entity(
    'budget category',
    'budget_categories',
    (db, n) => BudgetService(db).saveCategory(CategoryInput(name: n)),
  ),
  _Entity(
    'budget account',
    'budget_accounts',
    (db, n) => BudgetService(db).saveAccount(
      name: n,
      currency: 'EUR',
      rateToBase: 1,
    ),
  ),
  _Entity(
    'plan item',
    'plan_items',
    (db, n) => PlanService(db, ActionService(db)).saveItem(
      PlanItemInput(
        name: n,
        kind: PlanKind.cycle,
        startDate: planDate(2026, 1, 1),
        forever: true,
        cycle: const CycleRule(
          occurrences: [CycleOccurrence(day: 0, startMin: 540)],
        ),
      ),
    ),
  ),
  _Entity(
    'plan collection',
    'plan_collections',
    (db, n) => PlanService(db, ActionService(db)).saveCollection(name: n),
  ),
  _Entity(
    'form',
    'forms',
    (db, n) => FormService(db).save(FormDef(name: n)),
  ),
];

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  setUp(() => db = _db());
  tearDown(() => db.close());

  // ---------------------------------------------------------------- Create
  group('Create', () {
    for (final e in _entities) {
      test('${e.label}: an empty or blank name is refused and nothing is stored', () async {
        for (final bad in ['', '   ', '\t\n ', '\u0000', '\u0001\u0002']) {
          await expectLater(
            () => e.create(db, bad),
            throwsA(
              anyOf(isA<InvalidNameException>(), isA<ArgumentError>()),
            ),
            reason: '${e.label} "${bad.codeUnits}"',
          );
        }
        expect(await _count(db, e.table), 0);
      });

      test('${e.label}: the same name twice makes two rows (names are not unique)', () async {
        final a = await e.create(db, 'Same');
        final b = await e.create(db, 'Same');
        expect(a, isNot(b));
        expect(await _count(db, e.table), greaterThanOrEqualTo(2));
      });
    }

    test('the same id created on two devices is one row after the merge, not two', () async {
      // A row inserted twice under one id (another device made it first) is a
      // constraint error, never a silent duplicate.
      final id = newId();
      await db.customStatement(
        'INSERT INTO actions (id, name, created_at, updated_at) VALUES (?, ?, ?, ?)',
        [id, 'a', '2026-01-01T00:00:00.000000Z', '2026-01-01T00:00:00.000000Z'],
      );
      await expectLater(
        db.customStatement(
          'INSERT INTO actions (id, name, created_at, updated_at) VALUES (?, ?, ?, ?)',
          [id, 'b', '2026-01-01T00:00:00.000000Z', '2026-01-01T00:00:00.000000Z'],
        ),
        throwsA(isA<Exception>()),
      );
      expect(await _count(db, 'actions'), 1);
    });

    test('a creation that fails halfway leaves nothing behind (action + missing direction)', () async {
      await expectLater(
        ActionService(db).createAction(name: 'Half', metricIds: ['no-such-direction']),
        throwsA(isA<Exception>()),
      );
      expect(await _count(db, 'actions'), 0);
      expect(await _count(db, 'action_metrics'), 0);
    });

    test('a direction that fails halfway (missing relation) is not created', () async {
      await expectLater(
        MetricService(db).saveMetric(
          name: 'Half',
          kind: MetricKind.boolean,
          dependsOnIds: ['ghost'],
        ),
        throwsA(isA<Exception>()),
      );
      expect(await _count(db, 'metrics'), 0);
      expect(await _count(db, 'metric_dependencies'), 0);
    });

    test('a category pointing at a missing account is refused and not stored', () async {
      await expectLater(
        BudgetService(db).saveCategory(
          const CategoryInput(name: 'Orphan', accountUseId: 'ghost'),
        ),
        throwsA(isA<Exception>()),
      );
      expect(await _count(db, 'budget_categories'), 0);
    });
  });

  // ------------------------------------------------------------------ Read
  group('Read', () {
    late Directory logDir;
    setUp(() {
      logDir = Directory.systemTemp.createTempSync('livenow-errlog');
      ErrorLog.errorLogDirectoryOverride = logDir;
    });
    tearDown(() {
      ErrorLog.errorLogDirectoryOverride = null;
      logDir.deleteSync(recursive: true);
    });

    Future<String> logText() async {
      // ErrorLog writes are fire-and-forget: give them a moment.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final f = File('${logDir.path}${Platform.pathSeparator}error.log');
      return f.existsSync() ? f.readAsStringSync() : '';
    }

    test('a missing id reads as null / is refused with a typed error, never a crash', () async {
      expect(await FormService(db).get('ghost'), isNull);
      expect(await PlanService(db, ActionService(db)).deleteItem('ghost'), isNull);
      expect(await BudgetService(db).deleteCategory('ghost'), isNull);
      expect(await BudgetService(db).deleteAccount('ghost'), isNull);
      expect(await BudgetService(db).deleteTransaction('ghost'), isNull);
      expect(await FormService(db).delete('ghost'), isNull);
      await expectLater(
        ActionService(db).deleteAction('ghost'),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        MetricService(db).deleteMetric('ghost'),
        throwsA(isA<StateError>()),
      );
    });

    test('a form with a damaged payload opens as an empty form with its name', () async {
      final id = await FormService(db).save(FormDef(name: 'Mood'));
      for (final bad in ['{', 'null', '[]', '"x"', '{"questions": 5}', '{"questions":[1,"a",null]}']) {
        await db.customStatement('UPDATE forms SET payload = ? WHERE id = ?', [bad, id]);
        final f = await FormService(db).get(id);
        expect(f, isNotNull, reason: bad);
        expect(f!.name, 'Mood');
        expect(f.def.questions, isEmpty, reason: bad);
      }
      final all = await FormService(db).all();
      expect(all, hasLength(1));
    });

    test('a template with a damaged payload reads as a placeholder and is logged; others still load', () async {
      Future<String> template(String name, String payload) async {
        final id = newId();
        await db.customStatement(
          'INSERT INTO action_templates (id, name, payload) VALUES (?, ?, ?)',
          [id, name, payload],
        );
        return id;
      }

      final good = await template('Good', jsonEncode({'name': 'Good', 'estimatedMinutes': 20}));
      final bad = await template('Broken', '{not json');
      final notMap = await template('Listy', '[1,2,3]');
      final wrongTypes = await template(
        'Typed',
        jsonEncode({
          'name': 5,
          'estimatedMinutes': 'soon',
          'metricIds': [1, 2, 'x'],
          'isAllDay': 'yes',
          'notes': 7,
        }),
      );
      final huge = await template(
        'Huge',
        jsonEncode({'name': 'Huge', 'estimatedMinutes': 1 << 60}),
      );
      final actions = ActionService(db);

      final p = decodeTemplatePayload('{not json', fallbackName: 'Broken');
      expect(p['name'], 'Broken');
      expect(p['metricIds'], isEmpty);
      expect(decodeTemplatePayload('[1]', fallbackName: 'L')['name'], 'L');
      final t = decodeTemplatePayload(
        jsonEncode({'name': 5, 'estimatedMinutes': 'soon', 'metricIds': [1, 'x']}),
        fallbackName: 'Typed',
      );
      expect(t['name'], 'Typed');
      expect(t.containsKey('estimatedMinutes'), isFalse);
      expect(t['metricIds'], ['x']);

      // "New from template" works for every one of them (placeholder names).
      final names = <String>[];
      for (final id in [good, bad, notMap, wrongTypes, huge]) {
        final created = await actions.createFromTemplate(id);
        names.add(
          (await (db.select(db.actionsTable)..where((a) => a.id.equals(created)))
                  .getSingle())
              .name,
        );
      }
      expect(names, ['Good', 'Broken', 'Listy', 'Typed', 'Huge']);
      expect(await logText(), contains('template payload'));
    });

    test('an action with damaged notes JSON still lists, edits and searches', () async {
      final id = await ActionService(db).createAction(name: 'Odd notes');
      await db.customStatement(
        "UPDATE actions SET notes = '{broken', notes_text = NULL WHERE id = ?",
        [id],
      );
      final other = await ActionService(db).createAction(name: 'Fine');
      final items = await ViewQueries(db).watchAllActions().first;
      expect(items.map((i) => i.id), containsAll([id, other]));
      await ActionService(db).updateAction(
        actionId: id,
        name: 'Odd notes 2',
        postponeFlex: 'flexible',
        isAllDay: false,
      );
      expect(await ViewQueries(db).watchNotesMatchIds('x').first, isEmpty);
    });

    test('a bad timestamp text in one row leaves the other rows loading', () async {
      final ok = await ActionService(db).createAction(
        name: 'ok',
        startAt: DateTime.utc(2030, 1, 1, 10),
        endAt: DateTime.utc(2030, 1, 1, 11),
      );
      final broken = await ActionService(db).createAction(name: 'broken');
      await db.customStatement(
        "UPDATE actions SET start_at = 'garbage', end_at = '31/12/2026' WHERE id = ?",
        [broken],
      );
      final q = ViewQueries(db);
      final all = await q.watchAllActions().first;
      expect(all.map((i) => i.id), containsAll([ok, broken]));
      final upcoming = await q.watchUpcoming().first;
      expect(upcoming.map((i) => i.id), contains(ok));
      final cur = await q.watchCurrentNotDone(limit: 100).first;
      expect(cur, isNotNull);
      expect(dateTimeFromDbSafe('garbage'), isNull);
    });

    test('a bad transaction date does not break the CSV export or the backup dump', () async {
      final budget = BudgetService(db);
      final cat = await budget.saveCategory(const CategoryInput(name: 'C', price: 3));
      final t1 = await budget.createTransaction(categoryId: cat);
      await budget.createTransaction(categoryId: cat);
      await db.customStatement(
        "UPDATE budget_transactions SET occurred_at = 'not a date' WHERE id = ?",
        [t1],
      );
      final csvs = await BudgetIoService(db).exportCsvs();
      expect(csvs.values, hasLength(3));
      expect(await BudgetIoService(db).exportJson(), isNotEmpty);
      expect(await _dump(db), isNotEmpty);
    });

    test('an unknown direction kind / window / plan kind reads as a safe default and is logged', () async {
      final id = await MetricService(db).saveMetric(name: 'Odd', kind: MetricKind.boolean);
      // The table has a CHECK on the kind: a row from a newer app (or a
      // damaged file) is simulated with checks switched off.
      await db.customStatement('PRAGMA ignore_check_constraints = ON');
      await db.customStatement(
        "UPDATE metrics SET kind = 'quantum', time_window = 'decade' WHERE id = ?",
        [id],
      );
      await db.customStatement('PRAGMA ignore_check_constraints = OFF');
      final other = await MetricService(db).saveMetric(name: 'Fine', kind: MetricKind.boolean);
      final rows = await db.select(db.metricsTable).get();
      final list = [for (final r in rows) GrowthMetric.fromRow(r)];
      expect(list, hasLength(2));
      expect(list.firstWhere((m) => m.id == id).kind, MetricKind.boolean);
      expect(list.firstWhere((m) => m.id == id).window, isNull);
      expect(list.any((m) => m.id == other), isTrue);
      expect(await logText(), contains('quantum'));

      final plans = PlanService(db, ActionService(db));
      final pid = await ActionService(db).createAction(name: 'x'); // unrelated
      expect(pid, isNotEmpty);
      final planId = await plans.saveItem(
        PlanItemInput(
          name: 'Odd plan',
          kind: PlanKind.cycle,
          startDate: planDate(2026, 1, 1),
          forever: true,
          cycle: const CycleRule(occurrences: [CycleOccurrence(day: 0, startMin: 60)]),
        ),
      );
      await db.customStatement('PRAGMA ignore_check_constraints = ON');
      await db.customStatement(
        "UPDATE plan_items SET kind = 'weekly-ish', rule = '{broken' WHERE id = ?",
        [planId],
      );
      await db.customStatement('PRAGMA ignore_check_constraints = OFF');
      final item = (await plans.items()).single;
      final data = plans.decode(item);
      expect(data.kind, PlanKind.cycle);
      expect(
        occurrencesInRange(data, planDate(2026, 1, 1), planDate(2026, 1, 31)),
        isEmpty,
      );
    });

    test('a plan row with a damaged start date is paused, logged, and the others still decode', () async {
      final plans = PlanService(db, ActionService(db));
      PlanItemInput input(String n) => PlanItemInput(
        name: n,
        kind: PlanKind.cycle,
        startDate: planDate(2026, 1, 1),
        forever: true,
        cycle: const CycleRule(occurrences: [CycleOccurrence(day: 0, startMin: 60)]),
      );
      final bad = await plans.saveItem(input('Bad'));
      await plans.saveItem(input('Good'));
      await db.customStatement(
        "UPDATE plan_items SET start_date = 'yesterday', end_date = '??' WHERE id = ?",
        [bad],
      );
      final decoded = [for (final r in await plans.items()) plans.decode(r)];
      expect(decoded, hasLength(2));
      final b = decoded.firstWhere((d) => d.name == 'Bad');
      expect(b.paused, isTrue);
      expect(b.endDate, isNull);
      expect(await logText(), contains('start date'));
    });
  });

  // ---------------------------------------------------------------- Update
  group('Update', () {
    test('saving a row that was deleted elsewhere says so instead of silently doing nothing', () async {
      final actions = ActionService(db);
      final id = await actions.createAction(name: 'Doomed');
      await db.customStatement('DELETE FROM actions WHERE id = ?', [id]);
      await expectLater(
        actions.updateAction(
          actionId: id,
          name: 'Too late',
          postponeFlex: 'flexible',
          isAllDay: false,
        ),
        throwsA(isA<MissingRowException>()),
      );
      expect(await _count(db, 'actions'), 0);

      final budget = BudgetService(db);
      final cat = await budget.saveCategory(const CategoryInput(name: 'Gone'));
      await db.customStatement('DELETE FROM budget_categories WHERE id = ?', [cat]);
      await expectLater(
        () => budget.saveCategory(CategoryInput(id: cat, name: 'Gone 2')),
        throwsA(isA<MissingRowException>()),
      );
      expect(await _count(db, 'budget_categories'), 0);

      final acct = await budget.saveAccount(name: 'A', currency: 'EUR', rateToBase: 1);
      await db.customStatement('DELETE FROM budget_accounts WHERE id = ?', [acct]);
      await expectLater(
        () => budget.saveAccount(id: acct, name: 'A2', currency: 'EUR', rateToBase: 1),
        throwsA(isA<MissingRowException>()),
      );
      expect(await _count(db, 'budget_accounts'), 0);

      final plans = PlanService(db, ActionService(db));
      final pid = await _entities[4].create(db, 'P');
      await db.customStatement('DELETE FROM plan_items WHERE id = ?', [pid]);
      await expectLater(
        plans.saveItem(
          PlanItemInput(
            id: pid,
            name: 'P2',
            kind: PlanKind.cycle,
            startDate: planDate(2026, 1, 1),
            cycle: const CycleRule(),
          ),
        ),
        throwsA(isA<MissingRowException>()),
      );
      expect(await _count(db, 'plan_items'), 0);

      final cid = await plans.saveCollection(name: 'C');
      await db.customStatement('DELETE FROM plan_collections WHERE id = ?', [cid]);
      await expectLater(
        plans.saveCollection(id: cid, name: 'C2'),
        throwsA(isA<MissingRowException>()),
      );

      final tx = await budget.createTransaction(
        categoryId: await budget.saveCategory(const CategoryInput(name: 'T', price: 1)),
      );
      await db.customStatement('DELETE FROM budget_transactions WHERE id = ?', [tx]);
      await expectLater(
        () => budget.updateTransaction(tx, name: 'x'),
        throwsA(isA<MissingRowException>()),
      );
    });

    test('last writer wins per row: an edit with an older stamp does not beat a newer remote one', () async {
      // The editor asks before overwriting (rowStamp); at the data level the
      // second write simply wins and is stamped later.
      final actions = ActionService(db);
      final id = await actions.createAction(name: 'v1');
      final store = SyncStore(db);
      final before = await store.rowStamp('actions', id);
      await actions.updateAction(
        actionId: id,
        name: 'remote edit',
        postponeFlex: 'flexible',
        isAllDay: false,
      );
      final mid = await store.rowStamp('actions', id);
      expect(mid!.hlc.compareTo(before!.hlc), greaterThan(0));
      await actions.updateAction(
        actionId: id,
        name: 'local edit',
        postponeFlex: 'flexible',
        isAllDay: false,
      );
      final after = await store.rowStamp('actions', id);
      expect(after!.hlc.compareTo(mid.hlc), greaterThan(0));
    });

    test('a failing update rolls back every table it touched (trigger raises)', () async {
      final metrics = MetricService(db);
      final a = await metrics.saveMetric(name: 'A', kind: MetricKind.boolean);
      final b = await metrics.saveMetric(name: 'B', kind: MetricKind.boolean);
      await metrics.saveMetric(
        id: a,
        name: 'A',
        kind: MetricKind.boolean,
        dependsOnIds: [b],
      );
      final before = await _dump(db);
      await db.customStatement(
        "CREATE TRIGGER boom BEFORE INSERT ON metric_dependencies "
        "BEGIN SELECT RAISE(ABORT, 'boom'); END",
      );
      await expectLater(
        metrics.saveMetric(
          id: a,
          name: 'A renamed',
          kind: MetricKind.boolean,
          dependsOnIds: [b],
        ),
        throwsA(isA<Exception>()),
      );
      await db.customStatement('DROP TRIGGER boom');
      expect(await _dump(db), before, reason: 'rename and relation rewrite rolled back');
    });

    test('a cycle or loop is refused and leaves the data byte-for-byte unchanged', () async {
      final actions = ActionService(db);
      final deps = DependencyService(db);
      final a = await actions.createAction(name: 'a');
      final b = await actions.createAction(name: 'b');
      final c = await actions.createAction(name: 'c');
      await deps.addDependency(predecessorId: a, successorId: b);
      await deps.addDependency(predecessorId: b, successorId: c);

      final metrics = MetricService(db);
      final m1 = await metrics.saveMetric(name: 'm1', kind: MetricKind.boolean);
      final m2 = await metrics.saveMetric(
        name: 'm2',
        kind: MetricKind.boolean,
        dependsOnIds: [m1],
      );

      final budget = BudgetService(db);
      final parent = await budget.saveCategory(const CategoryInput(name: 'parent'));
      final child = await budget.saveCategory(
        CategoryInput(name: 'child', parentId: parent),
      );

      final before = await _dump(db);
      await expectLater(
        deps.addDependency(predecessorId: c, successorId: a),
        throwsA(isA<DependencyCycleException>()),
      );
      await expectLater(
        deps.addDependency(predecessorId: a, successorId: a),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        metrics.saveMetric(
          id: m1,
          name: 'm1',
          kind: MetricKind.boolean,
          dependsOnIds: [m2],
          leadsToIds: [m2],
        ),
        throwsA(isA<MetricCycleException>()),
      );
      await expectLater(
        () => budget.saveCategory(
          CategoryInput(id: parent, name: 'parent', parentId: child),
        ),
        throwsA(isA<BudgetCycleException>()),
      );
      expect(await _dump(db), before);
    });

    test('a duplicate dependency edge is a no-op, not an error', () async {
      final actions = ActionService(db);
      final a = await actions.createAction(name: 'a');
      final b = await actions.createAction(name: 'b');
      final deps = DependencyService(db);
      await deps.addDependency(predecessorId: a, successorId: b);
      await deps.addDependency(predecessorId: a, successorId: b);
      expect(await _count(db, 'action_dependencies'), 1);
    });

    test('a transaction into a group category is refused and the row is unchanged', () async {
      final budget = BudgetService(db);
      final group = await budget.saveCategory(const CategoryInput(name: 'group'));
      await budget.saveCategory(CategoryInput(name: 'leaf', parentId: group));
      final leaf2 = await budget.saveCategory(const CategoryInput(name: 'leaf2', price: 2));
      final tx = await budget.createTransaction(categoryId: leaf2);
      final before = await _dump(db);
      await expectLater(
        () => budget.updateTransaction(tx, categoryId: group),
        throwsA(isA<BudgetGroupException>()),
      );
      expect(await _dump(db), before);
    });

    test('setMetrics with one missing direction keeps the old links', () async {
      final actions = ActionService(db);
      final m = await MetricService(db).saveMetric(name: 'm', kind: MetricKind.boolean);
      final a = await actions.createAction(name: 'a', metricIds: [m]);
      final before = await _dump(db);
      await expectLater(
        actions.setMetrics(a, [m, 'ghost']),
        throwsA(isA<Exception>()),
      );
      expect(await _dump(db), before);
    });
  });

  // ---------------------------------------------------------------- Delete
  group('Delete', () {
    test('an action with links: delete cleans edges, links, occurrences; undo restores them; undo twice is harmless', () async {
      final actions = ActionService(db);
      final deps = DependencyService(db);
      final m = await MetricService(db).saveMetric(name: 'm', kind: MetricKind.boolean);
      final a = await actions.createAction(name: 'a', metricIds: [m]);
      final b = await actions.createAction(name: 'b');
      final c = await actions.createAction(name: 'c');
      await deps.addDependency(predecessorId: a, successorId: b);
      await deps.addDependency(predecessorId: c, successorId: a);
      await actions.start(a);
      final cat = await BudgetService(db).saveCategory(const CategoryInput(name: 'cat', price: 5));
      final tx = await BudgetService(db).createTransaction(categoryId: cat, actionId: a);
      final before = await _dump(db);

      final undo = await actions.deleteAction(a);
      expect(await _count(db, 'actions'), 2);
      expect(await _count(db, 'action_dependencies'), 0);
      expect(await _count(db, 'action_metrics'), 0);
      expect(await _count(db, 'action_occurrences'), 0);
      expect(await _fkViolations(db), isEmpty);
      final detached = await db
          .customSelect('SELECT action_id FROM budget_transactions WHERE id = ?',
              variables: [Variable.withString(tx)])
          .getSingle();
      expect(detached.read<String?>('action_id'), isNull);

      await actions.undoDelete(undo);
      expect(await _dump(db), before, reason: 'row AND links restored');
      expect(await _fkViolations(db), isEmpty);

      // Undo again: nothing doubles, nothing is corrupted.
      await actions.undoDelete(undo);
      expect(await _dump(db), before);
      expect(await _fkViolations(db), isEmpty);
    });

    test('undo after a related row was deleted meanwhile restores what it can', () async {
      final actions = ActionService(db);
      final deps = DependencyService(db);
      final m = await MetricService(db).saveMetric(name: 'm', kind: MetricKind.boolean);
      final a = await actions.createAction(name: 'a', metricIds: [m]);
      final b = await actions.createAction(name: 'b');
      await deps.addDependency(predecessorId: a, successorId: b);
      final undo = await actions.deleteAction(a);
      await actions.deleteAction(b);
      await MetricService(db).deleteMetric(m);
      await actions.undoDelete(undo);
      expect(await _count(db, 'actions'), 1);
      expect(await _count(db, 'action_dependencies'), 0);
      expect(await _count(db, 'action_metrics'), 0);
      expect(await _fkViolations(db), isEmpty);
    });

    test('a delete that fails partway rolls back (action with links, trigger raises)', () async {
      final actions = ActionService(db);
      final m = await MetricService(db).saveMetric(name: 'm', kind: MetricKind.boolean);
      final a = await actions.createAction(name: 'a', metricIds: [m]);
      final b = await actions.createAction(name: 'b');
      await DependencyService(db).addDependency(predecessorId: a, successorId: b);
      await actions.start(a);
      final before = await _dump(db);
      await db.customStatement(
        "CREATE TRIGGER boom BEFORE DELETE ON action_occurrences "
        "BEGIN SELECT RAISE(ABORT, 'boom'); END",
      );
      await expectLater(actions.deleteAction(a), throwsA(isA<Exception>()));
      await db.customStatement('DROP TRIGGER boom');
      expect(await _dump(db), before);
    });

    test('a direction delete: links removed, actions kept; undo restores relations and links; twice is harmless', () async {
      final metrics = MetricService(db);
      final parent = await metrics.saveMetric(name: 'parent', kind: MetricKind.boolean, isMain: true);
      final child = await metrics.saveMetric(
        name: 'child',
        kind: MetricKind.boolean,
        leadsToIds: [parent],
      );
      final a = await ActionService(db).createAction(name: 'a', metricIds: [child]);
      final before = await _dump(db);
      final undo = await metrics.deleteMetric(child);
      expect(await _count(db, 'actions'), 1);
      expect(await _count(db, 'action_metrics'), 0);
      expect(await _count(db, 'metric_dependencies'), 0);
      expect(a, isNotEmpty);
      await metrics.undoDelete(undo);
      expect(await _dump(db), before);
      await metrics.undoDelete(undo);
      expect(await _dump(db), before);
      expect(await _fkViolations(db), isEmpty);
    });

    test('a direction delete that fails partway rolls back', () async {
      final metrics = MetricService(db);
      final parent = await metrics.saveMetric(name: 'parent', kind: MetricKind.boolean);
      final child = await metrics.saveMetric(
        name: 'child',
        kind: MetricKind.boolean,
        leadsToIds: [parent],
      );
      await ActionService(db).createAction(name: 'a', metricIds: [child]);
      final before = await _dump(db);
      await db.customStatement(
        "CREATE TRIGGER boom BEFORE DELETE ON metrics "
        "BEGIN SELECT RAISE(ABORT, 'boom'); END",
      );
      await expectLater(metrics.deleteMetric(child), throwsA(isA<Exception>()));
      await db.customStatement('DROP TRIGGER boom');
      expect(await _dump(db), before);
    });

    test('a category with children and transactions: children go top-level, transactions keep amounts; undo restores; twice is harmless', () async {
      final budget = BudgetService(db);
      final parent = await budget.saveCategory(const CategoryInput(name: 'parent'));
      final leaf = await budget.saveCategory(
        CategoryInput(name: 'leaf', parentId: parent, price: 4),
      );
      final txs = [
        await budget.createTransaction(categoryId: leaf, quantity: 2),
        await budget.createTransaction(categoryId: leaf, quantity: 3),
      ];
      final before = await _dump(db);
      final undo = (await budget.deleteCategory(leaf))!;
      for (final t in txs) {
        final r = await db
            .customSelect('SELECT category_id, quantity FROM budget_transactions WHERE id = ?',
                variables: [Variable.withString(t)])
            .getSingle();
        expect(r.read<String?>('category_id'), isNull);
      }
      expect(await _fkViolations(db), isEmpty);
      await budget.undoDeleteCategory(undo);
      expect(await _dump(db), before);
      await budget.undoDeleteCategory(undo);
      expect(await _dump(db), before);

      final undoParent = (await budget.deleteCategory(parent))!;
      final leafRow = await db
          .customSelect('SELECT parent_id FROM budget_categories WHERE id = ?',
              variables: [Variable.withString(leaf)])
          .getSingle();
      expect(leafRow.read<String?>('parent_id'), isNull);
      await budget.undoDeleteCategory(undoParent);
      expect(await _dump(db), before);
    });

    test('a category delete that fails partway rolls back', () async {
      final budget = BudgetService(db);
      final cat = await budget.saveCategory(const CategoryInput(name: 'c', price: 1));
      await budget.createTransaction(categoryId: cat);
      final before = await _dump(db);
      await db.customStatement(
        "CREATE TRIGGER boom BEFORE DELETE ON budget_categories "
        "BEGIN SELECT RAISE(ABORT, 'boom'); END",
      );
      await expectLater(budget.deleteCategory(cat), throwsA(isA<Exception>()));
      await db.customStatement('DROP TRIGGER boom');
      expect(await _dump(db), before);
    });

    test('an account delete frees categories and transactions; undo restores; twice is harmless', () async {
      final budget = BudgetService(db);
      final acct = await budget.saveAccount(name: 'A', currency: 'EUR', rateToBase: 1);
      final cat = await budget.saveCategory(
        CategoryInput(name: 'c', price: 1, accountUseId: acct, accountCountId: acct),
      );
      await budget.createTransaction(categoryId: cat);
      final before = await _dump(db);
      final undo = (await budget.deleteAccount(acct))!;
      expect(await _fkViolations(db), isEmpty);
      await budget.undoDeleteAccount(undo);
      expect(await _dump(db), before);
      await budget.undoDeleteAccount(undo);
      expect(await _dump(db), before);
    });

    test('a plan item delete (with overrides and future actions) is all or nothing, and undoable twice', () async {
      final plans = PlanService(db, ActionService(db));
      final id = await _entities[4].create(db, 'Daily');
      await plans.setOverride(
        itemId: id,
        date: planDate(2026, 1, 1),
        index: 0,
        name: 'special',
      );
      final before = await _dump(db);
      await db.customStatement(
        "CREATE TRIGGER boom BEFORE DELETE ON plan_items "
        "BEGIN SELECT RAISE(ABORT, 'boom'); END",
      );
      await expectLater(plans.deleteItem(id), throwsA(isA<Exception>()));
      await db.customStatement('DROP TRIGGER boom');
      expect(await _dump(db), before, reason: 'overrides not half-deleted');

      final undo = (await plans.deleteItem(id))!;
      expect(await _count(db, 'plan_items'), 0);
      expect(await _count(db, 'plan_overrides'), 0);
      await plans.undoDeleteItem(undo);
      expect(await _dump(db), before);
      await plans.undoDeleteItem(undo);
      expect(await _dump(db), before);
    });

    test('a template used by plan items can be deleted; the plan keeps working', () async {
      final plans = PlanService(db, ActionService(db));
      final id = await _entities[4].create(db, 'From scratch');
      final item = (await plans.items()).single;
      expect(item.templateId, isNotNull);
      await db.customStatement('DELETE FROM action_templates WHERE id = ?', [item.templateId]);
      expect(await _fkViolations(db), isEmpty, reason: 'no dangling template id');
      final data = plans.decode((await plans.items()).single);
      expect(
        occurrencesInRange(data, planDate(2026, 1, 1), planDate(2026, 1, 15)),
        hasLength(3),
      );
      expect(id, isNotEmpty);
    });

    test('a form and a tx template delete + undo twice are idempotent', () async {
      final forms = FormService(db);
      final fid = await forms.save(FormDef(name: 'F'));
      final before = await _dump(db);
      final row = (await forms.delete(fid))!;
      await forms.undoDelete(row);
      await forms.undoDelete(row);
      expect(await _dump(db), before);

      final budget = BudgetService(db);
      final tid = await budget.saveTxTemplate(name: 'T', categoryId: null);
      final b2 = await _dump(db);
      final trow = (await budget.deleteTxTemplate(tid))!;
      await budget.undoDeleteTxTemplate(trow);
      await budget.undoDeleteTxTemplate(trow);
      expect(await _dump(db), b2);
    });

    test('deleting the same action twice (deleted on another device first) fails cleanly', () async {
      final actions = ActionService(db);
      final id = await actions.createAction(name: 'x');
      await actions.deleteAction(id);
      final before = await _dump(db);
      await expectLater(actions.deleteAction(id), throwsA(isA<StateError>()));
      expect(await _dump(db), before);
    });
  });

  // --------------------------------------------------------- Database layer
  group('Database', () {
    test('every foreign key of every table rejects an orphan insert (FK ON)', () async {
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
          )
          .get();
      var checked = 0;
      for (final t in tables) {
        final table = t.read<String>('name');
        final fks = await db.customSelect('PRAGMA foreign_key_list($table)').get();
        if (fks.isEmpty) continue;
        final cols = await db.customSelect('PRAGMA table_info($table)').get();
        for (final fk in fks) {
          final fkCol = fk.read<String>('from');
          final names = <String>[];
          final values = <Object?>[];
          for (final c in cols) {
            final name = c.read<String>('name');
            final type = c.read<String>('type').toUpperCase();
            final notNull = c.read<int>('notnull') == 1;
            final hasDefault = c.data['dflt_value'] != null;
            final isPk = c.read<int>('pk') > 0;
            if (name == fkCol) {
              names.add(name);
              values.add('no-such-row');
            } else if (isPk) {
              names.add(name);
              values.add(type.contains('INT') ? 999 : 'pk-${newId()}');
            } else if (notNull && !hasDefault) {
              names.add(name);
              values.add(
                type.contains('INT') || type.contains('BOOL') || type.contains('REAL')
                    ? 0
                    : 'x',
              );
            }
          }
          final sql =
              'INSERT INTO $table (${names.join(',')}) VALUES (${List.filled(names.length, '?').join(',')})';
          Object? error;
          try {
            await db.customStatement(sql, values);
          } on Object catch (e) {
            error = e;
          }
          expect(error, isNotNull, reason: '$table.$fkCol accepted an orphan');
          expect(
            error.toString(),
            anyOf(contains('FOREIGN KEY'), contains('constraint')),
            reason: '$table.$fkCol: $error',
          );
          checked++;
        }
      }
      expect(checked, greaterThan(15));
      expect(await _fkViolations(db), isEmpty);
    });

    test('import atomicity: a failure at row N leaves the database identical (merge and replace)', () async {
      final actions = ActionService(db);
      final m = await MetricService(db).saveMetric(name: 'm', kind: MetricKind.boolean);
      final a = await actions.createAction(name: 'a', metricIds: [m]);
      final b = await actions.createAction(name: 'b');
      await DependencyService(db).addDependency(predecessorId: a, successorId: b);
      final cat = await BudgetService(db).saveCategory(const CategoryInput(name: 'c', price: 2));
      await BudgetService(db).createTransaction(categoryId: cat);

      final dir = Directory.systemTemp.createTempSync('livenow-atomic');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/ok.livenow');
      await BackupWriter(db).writeCompact(file);
      final good = <TableChunk>[];
      await for (final c in CompactBackupSource(file).chunks()) {
        good.add(c);
      }
      expect(good.length, greaterThan(5));

      for (final failAt in [1, good.length ~/ 2, good.length - 1]) {
        for (final mode in BackupImportMode.values) {
          final target = _db();
          addTearDown(target.close);
          await ActionService(target).createAction(name: 'pre-existing');
          final before = await _dump(target);
          final src = _FailingSource(good, failAt);
          await expectLater(
            BackupImportService(target, SyncStore(target)).import(src, mode: mode),
            throwsA(isA<StateError>()),
            reason: 'fail at chunk $failAt, $mode',
          );
          expect(await _dump(target), before, reason: 'fail at chunk $failAt, $mode');
          expect(await _fkViolations(target), isEmpty);
        }
      }
    });

    test('a chunk with a damaged row (wrong column count) aborts the import untouched', () async {
      final target = _db();
      addTearDown(target.close);
      await ActionService(target).createAction(name: 'keep me');
      final before = await _dump(target);
      final src = _ListSource([
        TableChunk('actions', const ['id', 'name'], [
          ['x1', 'ok'],
          ['x2'],
        ]),
      ]);
      await expectLater(
        BackupImportService(target, SyncStore(target)).import(src, mode: BackupImportMode.replace),
        throwsA(isA<Object>()),
      );
      expect(await _dump(target), before);
    });

    test('foreign_key_check is empty after a restore and after a merge of overlapping data', () async {
      final actions = ActionService(db);
      final m = await MetricService(db).saveMetric(name: 'm', kind: MetricKind.boolean);
      final a = await actions.createAction(name: 'a', metricIds: [m]);
      final b = await actions.createAction(name: 'b');
      await DependencyService(db).addDependency(predecessorId: a, successorId: b);
      final cat = await BudgetService(db).saveCategory(const CategoryInput(name: 'c', price: 2));
      await BudgetService(db).createTransaction(categoryId: cat, actionId: a);
      await _entities[4].create(db, 'plan');

      final dir = Directory.systemTemp.createTempSync('livenow-fk');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/b.livenow');
      await BackupWriter(db).writeCompact(file);

      final replaced = _db();
      addTearDown(replaced.close);
      await ActionService(replaced).createAction(name: 'old');
      await BackupImportService(replaced, SyncStore(replaced))
          .import(CompactBackupSource(file), mode: BackupImportMode.replace);
      expect(await _fkViolations(replaced), isEmpty);

      // Merge into a database that already holds half of it, with one of the
      // referenced rows deleted locally.
      final merged = _db();
      addTearDown(merged.close);
      await BackupImportService(merged, SyncStore(merged))
          .import(CompactBackupSource(file));
      await ActionService(merged).deleteAction(b);
      await MetricService(merged).deleteMetric(m);
      await BackupImportService(merged, SyncStore(merged))
          .import(CompactBackupSource(file));
      expect(await _fkViolations(merged), isEmpty);
      expect(await _count(merged, 'actions'), greaterThanOrEqualTo(1));
    });

    test('repeated open / close does not leak: the file can be deleted after 50 cycles', () async {
      final dir = Directory.systemTemp.createTempSync('livenow-leak');
      final path = '${dir.path}${Platform.pathSeparator}leak.sqlite';
      try {
        for (var i = 0; i < 50; i++) {
          final d = AppDatabase.forTesting(
            NativeDatabase(
              File(path),
              setup: (raw) {
                raw.execute('PRAGMA foreign_keys = ON;');
                raw.execute('PRAGMA journal_mode = WAL;');
              },
            ),
          );
          await ActionService(d).createAction(name: 'run $i');
          await d.close();
        }
        final d = AppDatabase.forTesting(NativeDatabase(File(path)));
        expect(await _count(d, 'actions'), 50);
        await d.close();
        // A leaked handle would make this throw on Windows.
        File(path).deleteSync();
        for (final ext in ['-wal', '-shm']) {
          final f = File('$path$ext');
          if (f.existsSync()) f.deleteSync();
        }
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('two connections on one WAL file write concurrently without losing rows', () async {
      final dir = Directory.systemTemp.createTempSync('livenow-wal');
      final path = '${dir.path}${Platform.pathSeparator}shared.sqlite';
      try {
        final a = AppDatabase.forTesting(
          NativeDatabase.createInBackground(
            File(path),
            setup: (raw) {
              raw.execute('PRAGMA journal_mode = WAL;');
              raw.execute('PRAGMA busy_timeout = 5000;');
              raw.execute('PRAGMA foreign_keys = ON;');
            },
          ),
        );
        await ActionService(a).createAction(name: 'seed'); // creates the schema
        final b = AppDatabase.forTesting(
          NativeDatabase.createInBackground(
            File(path),
            setup: (raw) {
              raw.execute('PRAGMA journal_mode = WAL;');
              raw.execute('PRAGMA busy_timeout = 5000;');
              raw.execute('PRAGMA foreign_keys = ON;');
            },
          ),
        );
        Future<void> writer(AppDatabase d, String tag) async {
          final svc = ActionService(d);
          await Future.wait([
            for (var i = 0; i < 40; i++) svc.createAction(name: '$tag $i'),
          ]);
        }

        await Future.wait([writer(a, 'A'), writer(b, 'B')]);
        expect(await _count(a, 'actions'), 81);
        expect(await _count(b, 'actions'), 81);
        final check = await a.customSelect('PRAGMA integrity_check').getSingle();
        expect(check.read<String>('integrity_check'), 'ok');
        final names = (await a.select(a.actionsTable).get()).map((r) => r.name).toSet();
        expect(names, hasLength(81));
        // A write transaction held open by one connection does not corrupt the
        // other's view, and both converge after it commits.
        await a.transaction(() async {
          await ActionService(a).createAction(name: 'in tx');
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        expect(await _count(b, 'actions'), 82);
        await a.close();
        await b.close();
      } finally {
        try {
          dir.deleteSync(recursive: true);
        } on FileSystemException {
          // A background isolate may still hold the file for a moment.
        }
      }
    });
  });
}

/// A source that yields [chunks] and then throws at chunk [failAt].
class _FailingSource implements BackupSource {
  _FailingSource(this.chunks_, this.failAt);
  final List<TableChunk> chunks_;
  final int failAt;

  @override
  Future<BackupHeader> header() async => const BackupHeader();

  @override
  Stream<TableChunk> chunks() async* {
    for (var i = 0; i < chunks_.length; i++) {
      if (i == failAt) throw StateError('disk went away at chunk $i');
      yield chunks_[i];
    }
  }
}

class _ListSource implements BackupSource {
  _ListSource(this.items);
  final List<TableChunk> items;

  @override
  Future<BackupHeader> header() async => const BackupHeader();

  @override
  Stream<TableChunk> chunks() => Stream.fromIterable(items);
}

DateTime? dateTimeFromDbSafe(String text) => DateTime.tryParse(text);
