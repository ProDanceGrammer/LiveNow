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

void main() {
  for (final version in [1, 2]) {
    test(
      'v$version database upgrades to v3 keeping actions, metrics and links',
      () async {
        final db = _oldDatabase(version: version);
        addTearDown(db.close);

        // Actions survive, with the v2 columns empty.
        final actions = await db.select(db.actionsTable).get();
        expect(actions.single.name, 'Old action');
        expect(actions.single.sequenceNumber, isNull);
        expect(actions.single.countableActivityId, isNull);

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
      },
    );
  }

  test('v1 database still gets the v2 columns and activities table', () async {
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
