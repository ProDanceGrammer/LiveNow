import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';

// Raw DDL of the older schemas, so a real upgrade runs against them.

const _actionsV1 = '''
  CREATE TABLE actions (
    id TEXT NOT NULL PRIMARY KEY,
    name TEXT NOT NULL,
    done INTEGER NOT NULL DEFAULT 0,
    priority TEXT NULL,
    postpone_flex TEXT NOT NULL DEFAULT 'flexible',
    depth_level TEXT NULL,
    start_at TEXT NULL,
    end_at TEXT NULL,
    is_all_day INTEGER NOT NULL DEFAULT 0,
    estimated_minutes INTEGER NULL,
    result_note TEXT NULL,
    completed_at TEXT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  )''';

/// v2 = v1 plus the continue-with-same-action columns and their table.
const _countableActivitiesV2 = '''
  CREATE TABLE countable_activities (
    id TEXT NOT NULL PRIMARY KEY,
    name TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  )''';
const _actionsV2 = '''
  CREATE TABLE actions (
    id TEXT NOT NULL PRIMARY KEY,
    name TEXT NOT NULL,
    done INTEGER NOT NULL DEFAULT 0,
    priority TEXT NULL,
    postpone_flex TEXT NOT NULL DEFAULT 'flexible',
    depth_level TEXT NULL,
    start_at TEXT NULL,
    end_at TEXT NULL,
    is_all_day INTEGER NOT NULL DEFAULT 0,
    estimated_minutes INTEGER NULL,
    result_note TEXT NULL,
    completed_at TEXT NULL,
    sequence_number INTEGER NULL,
    countable_activity_id TEXT NULL REFERENCES countable_activities(id)
      ON DELETE SET NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  )''';

const _metricsOld = '''
  CREATE TABLE metrics (
    id TEXT NOT NULL PRIMARY KEY,
    name TEXT NOT NULL,
    weight REAL NOT NULL DEFAULT 0,
    leading TEXT NULL,
    target_interval_days INTEGER NULL
  )''';
const _actionMetricsOld = '''
  CREATE TABLE action_metrics (
    id TEXT NOT NULL PRIMARY KEY,
    action_id TEXT NOT NULL REFERENCES actions(id) ON DELETE CASCADE,
    metric_id TEXT NOT NULL REFERENCES metrics(id) ON DELETE CASCADE,
    UNIQUE (action_id, metric_id)
  )''';

AppDatabase _oldDatabase({required int version}) {
  return AppDatabase.forTesting(
    NativeDatabase.memory(
      setup: (raw) {
        if (version >= 2) raw.execute(_countableActivitiesV2);
        raw.execute(version >= 2 ? _actionsV2 : _actionsV1);
        raw.execute(_metricsOld);
        raw.execute(_actionMetricsOld);
        raw.execute(
          "INSERT INTO actions (id, name, created_at, updated_at) "
          "VALUES ('a1', 'Old action', 't', 't')",
        );
        raw.execute(
          "INSERT INTO metrics (id, name, weight, leading, target_interval_days) "
          "VALUES ('m1', 'Old metric', 5, 'health', 3)",
        );
        raw.execute(
          "INSERT INTO action_metrics (id, action_id, metric_id) "
          "VALUES ('l1', 'a1', 'm1')",
        );
        raw.execute('PRAGMA user_version = $version');
        // Like the real connection: cascades are live during the upgrade.
        raw.execute('PRAGMA foreign_keys = ON');
      },
    ),
  );
}

// Schema v3 = v2 plus growth directions (the reshaped `metrics` table and
// `metric_dependencies`); `actions` has no `notes` column yet.
const _metricsV3 = '''
  CREATE TABLE metrics (
    id TEXT NOT NULL PRIMARY KEY,
    name TEXT NOT NULL,
    weight REAL NOT NULL DEFAULT 0,
    kind TEXT NOT NULL DEFAULT 'boolean',
    time_window TEXT NULL,
    target REAL NOT NULL DEFAULT 1,
    is_main INTEGER NOT NULL DEFAULT 0,
    importance_level INTEGER NOT NULL DEFAULT 0
  )''';
// v5 = v3 metrics plus the emoji `icon` column (no Mindmap positions yet).
const _metricsV5 = '''
  CREATE TABLE metrics (
    id TEXT NOT NULL PRIMARY KEY,
    name TEXT NOT NULL,
    weight REAL NOT NULL DEFAULT 0,
    kind TEXT NOT NULL DEFAULT 'boolean',
    time_window TEXT NULL,
    target REAL NOT NULL DEFAULT 1,
    is_main INTEGER NOT NULL DEFAULT 0,
    importance_level INTEGER NOT NULL DEFAULT 0,
    icon TEXT NULL
  )''';
const _metricDependenciesV3 = '''
  CREATE TABLE metric_dependencies (
    id TEXT NOT NULL PRIMARY KEY,
    metric_id TEXT NOT NULL REFERENCES metrics(id) ON DELETE CASCADE,
    depends_on_id TEXT NOT NULL REFERENCES metrics(id) ON DELETE CASCADE,
    UNIQUE (metric_id, depends_on_id),
    CHECK (metric_id <> depends_on_id)
  )''';

/// A database at [version] 3, 4 or 5: v3 = growth directions, v4 adds
/// `actions.notes`, v5 adds `metrics.icon`.
AppDatabase _v3Database({int version = 3}) {
  return AppDatabase.forTesting(
    NativeDatabase.memory(
      setup: (raw) {
        raw.execute(_countableActivitiesV2);
        raw.execute(_actionsV2);
        if (version >= 4) {
          raw.execute('ALTER TABLE actions ADD COLUMN notes TEXT NULL');
        }
        raw.execute(version >= 5 ? _metricsV5 : _metricsV3);
        raw.execute(_metricDependenciesV3);
        raw.execute(_actionMetricsOld);
        raw.execute(
          "INSERT INTO actions (id, name, created_at, updated_at) "
          "VALUES ('a1', 'Existing action', 't', 't')",
        );
        raw.execute(
          "INSERT INTO metrics (id, name, weight, kind, time_window, target, is_main) "
          "VALUES ('m1', 'Main direction', 1000, 'boolean', NULL, 1, 1)",
        );
        raw.execute(
          "INSERT INTO action_metrics (id, action_id, metric_id) "
          "VALUES ('l1', 'a1', 'm1')",
        );
        raw.execute('PRAGMA user_version = $version');
        raw.execute('PRAGMA foreign_keys = ON');
      },
    ),
  );
}

/// After any upgrade: the icon and Mindmap position columns are empty, and can
/// be written and read back.
Future<void> _expectIconAndPositionsUsable(
  AppDatabase db,
  String metricId,
) async {
  Future<Metric> load() => (db.select(
    db.metricsTable,
  )..where((t) => t.id.equals(metricId))).getSingle();

  final m = await load();
  expect((m.icon, m.posX, m.posY), (null, null, null));
  await (db.update(db.metricsTable)..where((t) => t.id.equals(metricId))).write(
    const MetricsTableCompanion(
      icon: Value('\u{1F331}'),
      posX: Value(12.5),
      posY: Value(-7),
    ),
  );
  final w = await load();
  expect((w.icon, w.posX, w.posY), ('\u{1F331}', 12.5, -7));
}

void main() {
  for (final version in [3, 4, 5]) {
    test('v$version database upgrades to v6: rows intact, new columns empty', () async {
      final db = _v3Database(version: version);
      addTearDown(db.close);

      final action = (await db.select(db.actionsTable).get()).single;
      expect(action.name, 'Existing action');
      expect(action.notes, isNull);

      // Growth directions and their action links are intact.
      final metric = (await db.select(db.metricsTable).get()).single;
      expect(
        (metric.name, metric.weight, metric.isMain),
        ('Main direction', 1000, true),
      );
      expect(await db.select(db.actionMetricsTable).get(), hasLength(1));
      await _expectIconAndPositionsUsable(db, 'm1');

      // The notes column stores and returns the editor's JSON, Cyrillic
      // included.
      const notes =
          '{"document":{"type":"page","children":[{"type":"todo_list",'
          '"data":{"checked":false,"delta":[{"insert":"Перевірити пошту"}]}}]}}';
      await (db.update(db.actionsTable)..where((t) => t.id.equals('a1'))).write(
        const ActionsTableCompanion(notes: Value(notes)),
      );
      expect((await db.select(db.actionsTable).get()).single.notes, notes);
    });
  }

  for (final version in [1, 2]) {
    test(
      'v$version database upgrades to v6 keeping actions, metrics and links',
      () async {
        final db = _oldDatabase(version: version);
        addTearDown(db.close);

        // Actions survive, with the v2 columns empty.
        final actions = await db.select(db.actionsTable).get();
        expect(actions.single.name, 'Old action');
        expect(actions.single.sequenceNumber, isNull);
        expect(actions.single.countableActivityId, isNull);
        expect(actions.single.notes, isNull);

        // The old metric becomes a non-main boolean direction; its weight stays
        // until the next recompute, and the dropped columns are gone.
        final metrics = await db.select(db.metricsTable).get();
        final m = metrics.single;
        expect(m.name, 'Old metric');
        expect(m.weight, 5);
        expect(
          (m.kind, m.timeWindow, m.target, m.isMain, m.importanceLevel),
          ('boolean', null, 1, false, 0),
        );

        // Rebuilding the metrics table must not cascade away the action links.
        final links = await db.select(db.actionMetricsTable).get();
        expect(links.map((l) => (l.actionId, l.metricId)), [('a1', 'm1')]);

        // The new table and the new columns work.
        await expectLater(
          db
              .into(db.metricDependenciesTable)
              .insert(
                MetricDependenciesTableCompanion.insert(
                  id: 'd1',
                  metricId: 'm1',
                  dependsOnId: 'm1',
                ),
              ),
          throwsA(anything),
          reason: 'a direction cannot depend on itself (CHECK constraint)',
        );
        await db.customStatement(
          "INSERT INTO metrics (id, name, kind, time_window, target, is_main) "
          "VALUES ('m2', 'Hours', 'hours', 'week', 56, 1)",
        );
        await db
            .into(db.metricDependenciesTable)
            .insert(
              MetricDependenciesTableCompanion.insert(
                id: 'd2',
                metricId: 'm2',
                dependsOnId: 'm1',
              ),
            );
        expect(await db.select(db.metricDependenciesTable).get(), hasLength(1));
        await _expectIconAndPositionsUsable(db, 'm1');
        await _expectIconAndPositionsUsable(db, 'm2');
      },
    );
  }

  test('v1 database (upgraded to v6) still gets the v2 columns and activities table', () async {
    final db = _oldDatabase(version: 1);
    addTearDown(db.close);
    await db
        .into(db.countableActivitiesTable)
        .insert(
          CountableActivitiesTableCompanion.insert(
            id: 'c1',
            name: 'Reading',
            createdAt: 't',
            updatedAt: 't',
          ),
        );
    await db.customStatement(
      "UPDATE actions SET countable_activity_id = 'c1' WHERE id = 'a1'",
    );
    expect(
      (await db.select(db.actionsTable).get()).single.countableActivityId,
      'c1',
    );
  });
}
