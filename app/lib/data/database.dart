import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/notes_plain_text.dart';
import 'sync/sync_schema.dart';
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
    BudgetAccountsTable,
    BudgetCategoriesTable,
    BudgetTransactionsTable,
    BudgetSettingsTable,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Lets tests inject an in-memory executor instead of the real file.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 12;

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
        // notes_text is new to the rebuilt table when coming from < 9 (it is
        // listed so the copy does not look for it in the old table).
        await m.alterTable(
          TableMigration(
            actionsTable,
            newColumns: from < 9 ? [actionsTable.notesText] : const [],
          ),
        );
      }
      if (from >= 8 && from < 9) {
        await m.addColumn(actionsTable, actionsTable.notesText);
      }
      if (from < 9) {
        await _backfillNotesText();
      }
      if (from < 10) {
        // Budget: accounts, categories, transactions (linked to actions) and
        // a small settings store. Purely additive.
        await m.createTable(budgetAccountsTable);
        await m.createTable(budgetCategoriesTable);
        await m.createTable(budgetTransactionsTable);
        await m.createTable(budgetSettingsTable);
        await m.createIndex(idxBudgetCategoriesParent);
        await m.createIndex(idxBudgetTxCategory);
        await m.createIndex(idxBudgetTxAction);
      }
      if (from < 11) {
        // Sync bookkeeping: every existing row gets a version (seeded from its
        // updated_at); the triggers are (re)created by beforeOpen below.
        await createSyncTables(this);
        await backfillSyncVersions(this);
      }
      if (from >= 10 && from < 12) {
        // Account pictures. (From < 10 the budget table was just created with
        // the column already.)
        // Only when it is really missing, so a half-migrated or hand-built
        // file cannot fail with "duplicate column".
        final columns = await customSelect(
          'PRAGMA table_info(budget_accounts)',
        ).get();
        if (!columns.any((r) => r.read<String>('name') == 'icon')) {
          await m.addColumn(budgetAccountsTable, budgetAccountsTable.icon);
        }
      }
    },
    // Runs after onCreate/onUpgrade on EVERY open: a TableMigration rebuild
    // drops a table's triggers, so they are recreated each time, and rows
    // written without them get a version.
    beforeOpen: (details) async {
      await ensureSyncTriggers(this);
      await reconcileSyncVersions(this);
    },
  );

  /// One-off (schema v9): derives `notes_text` from every existing `notes`
  /// value, in id-ordered batches so memory stays flat with thousands of rows.
  Future<void> _backfillNotesText() async {
    const batchSize = 200;
    var lastId = '';
    while (true) {
      final rows = await customSelect(
        'SELECT id, notes FROM actions '
        'WHERE notes IS NOT NULL AND id > ? ORDER BY id LIMIT $batchSize',
        variables: [Variable.withString(lastId)],
      ).get();
      if (rows.isEmpty) return;
      for (final r in rows) {
        final id = r.read<String>('id');
        lastId = id;
        final text = notesPlainText(r.read<String>('notes'));
        if (text == null) continue;
        await customStatement(
          'UPDATE actions SET notes_text = ? WHERE id = ?',
          [text, id],
        );
      }
    }
  }
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
