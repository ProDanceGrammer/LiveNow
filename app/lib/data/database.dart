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
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Lets tests inject an in-memory executor instead of the real file.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration =>
      MigrationStrategy(onCreate: (m) => m.createAll());
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
