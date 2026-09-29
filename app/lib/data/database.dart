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
  int get schemaVersion => 3;

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
            ],
          ),
        );
      }
    },
  );
}

DatabaseConnection _openConnection() {
  return driftDatabase(
    name: 'livenow',
    native: DriftNativeOptions(
      databaseDirectory: getApplicationSupportDirectory,
      setup: (db) {
        db.execute('PRAGMA foreign_keys = ON;');
        db.execute('PRAGMA journal_mode = WAL;');
      },
    ),
  );
}
