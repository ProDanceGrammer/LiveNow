import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    ActionsTable,
    ActionDependenciesTable,
    ActionOccurrencesTable,
    MetricsTable,
    ActionMetricsTable,
    ActionTemplatesTable,
    CountableActivitiesTable,
    MetricDependenciesTable,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Lets tests inject an in-memory executor instead of the real file.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // Continue-with-same-action: sequence numbers + countable activities.
        await m.createTable(countableActivitiesTable);
        await m.addColumn(actionsTable, actionsTable.sequenceNumber);
        await m.addColumn(actionsTable, actionsTable.countableActivityId);
      }
      if (from < 3) {
        // Metrics become growth directions: new columns (all defaulted, so
        // old rows become non-main boolean directions), the old `leading` /
        // `target_interval_days` columns are dropped, and directions get a
        // dependency graph. alterTable rebuilds the table with foreign keys
        // switched off by drift, so action_metrics links survive.
        await m.createTable(metricDependenciesTable);
        await m.alterTable(
          TableMigration(
            metricsTable,
            newColumns: [
              metricsTable.kind,
              metricsTable.timeWindow,
              metricsTable.target,
              metricsTable.isMain,
              metricsTable.importanceLevel,
              metricsTable.icon,
              metricsTable.posX,
              metricsTable.posY,
            ],
          ),
        );
      }
      if (from < 4) {
        // Rich-text notes (editor Document JSON) on every action.
        await m.addColumn(actionsTable, actionsTable.notes);
      }
      if (from >= 3 && from < 5) {
        // An emoji icon on growth directions (older databases already got it
        // with the v3 table rebuild above).
        await m.addColumn(metricsTable, metricsTable.icon);
      }
      if (from >= 3 && from < 6) {
        // Mindmap node positions (same: the v3 rebuild covers older ones).
        await m.addColumn(metricsTable, metricsTable.posX);
        await m.addColumn(metricsTable, metricsTable.posY);
      }
      if (from < 7) {
        // Calendar range filter and the Current board's ORDER BY start_at.
        await m.createIndex(idxActionsStart);
      }
      if (from < 8) {
        // Drops actions.priority. A plain DROP COLUMN fails because of its
        // CHECK constraint, so the table is rebuilt (indexes are recreated by
        // drift; foreign keys are off during the rebuild so links survive).
        await m.alterTable(TableMigration(actionsTable));
      }
    },
  );
}

/// Where the database file lives: the app-support folder, or — for automated
/// UI runs that must never touch the real data — the folder named by the
/// `LIVENOW_DATA_DIR` environment variable.
Future<Directory> _databaseDirectory() async {
  final override = Platform.environment['LIVENOW_DATA_DIR'];
  if (override != null && override.isNotEmpty) {
    return Directory(override).create(recursive: true);
  }
  return getApplicationSupportDirectory();
}

DatabaseConnection _openConnection() {
  return driftDatabase(
    name: 'livenow',
    native: DriftNativeOptions(
      databaseDirectory: _databaseDirectory,
      setup: (db) {
        db.execute('PRAGMA foreign_keys = ON;');
        db.execute('PRAGMA journal_mode = WAL;');
      },
    ),
  );
}
