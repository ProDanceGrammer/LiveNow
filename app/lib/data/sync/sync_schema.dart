import 'package:drift/drift.dart';

// Change tracking for device-to-device sync. Everything here is raw SQL run
// through customStatement, NOT Drift tables, so TableMigration rebuilds never
// touch it.
//
//  * `sync_versions` holds one row per (table, row id) that was ever written:
//    its hybrid-logical-clock stamp, the device that wrote it, a tombstone flag
//    and `seq`, an ever-increasing position in the log ("what changed since").
//    `seq` comes from a counter in `sync_clock`, and rows are upserted with an
//    explicit ON CONFLICT ... DO UPDATE: an `INSERT OR REPLACE` inside a trigger
//    is overridden by the conflict policy of the statement that fired it
//    (upserts, foreign-key actions), which broke real writes.
//  * AFTER INSERT/UPDATE/DELETE triggers on every synced table keep it current,
//    whatever code path wrote the row (services, imports, undo, raw SQL).
//  * The clock is plain SQL (`sync_clock`), so the triggers need no custom
//    function and work in every SQLite connection, including test databases.
//  * `sync_applying` is a one-row switch: while 1 (set by the apply engine) the
//    triggers stay silent, so remote changes are not echoed back as local ones.

/// Synced table -> its primary key column. `budget_settings` is keyed by `key`.
const Map<String, String> syncTables = {
  'actions': 'id',
  'action_dependencies': 'id',
  'action_occurrences': 'id',
  'metrics': 'id',
  'action_metrics': 'id',
  'action_templates': 'id',
  'countable_activities': 'id',
  'metric_dependencies': 'id',
  'budget_accounts': 'id',
  'budget_categories': 'id',
  'budget_transactions': 'id',
  'budget_settings': 'key',
  'saved_views': 'id',
  'plan_items': 'id',
  'plan_overrides': 'id',
  'budget_tx_templates': 'id',
};

/// Derived caches: recomputed on every device, so they are neither tracked
/// (an update touching only them logs nothing) nor sent.
const Map<String, Set<String>> syncExcludedColumns = {
  'metrics': {'weight', 'importance_level'},
  'actions': {'notes_text'},
};

/// The oldest possible clock stamp (rows that predate sync, no `updated_at`).
const String syncEpochHlc = '1970-01-01T00:00:00.000Z-0000-seed';

const _wallNow = "strftime('%Y-%m-%dT%H:%M:%fZ','now')";
const _deviceId = "(SELECT value FROM sync_state WHERE key = 'device_id')";

/// Creates the sync bookkeeping tables and this device's id. Idempotent.
Future<void> createSyncTables(DatabaseConnectionUser db) async {
  await db.customStatement(
    'CREATE TABLE IF NOT EXISTS sync_state '
    '(key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL)',
  );
  await db.customStatement(
    'CREATE TABLE IF NOT EXISTS sync_applying (flag INTEGER NOT NULL)',
  );
  await db.customStatement(
    'INSERT INTO sync_applying (flag) '
    'SELECT 0 WHERE NOT EXISTS (SELECT 1 FROM sync_applying)',
  );
  await db.customStatement(
    'CREATE TABLE IF NOT EXISTS sync_clock '
    '(id INTEGER PRIMARY KEY CHECK (id = 1), '
    'last_wall TEXT NOT NULL, counter INTEGER NOT NULL, '
    'seq INTEGER NOT NULL DEFAULT 0)',
  );
  await db.customStatement(
    "INSERT OR IGNORE INTO sync_clock (id, last_wall, counter, seq) "
    "VALUES (1, '1970-01-01T00:00:00.000Z', 0, 0)",
  );
  await db.customStatement(
    'CREATE TABLE IF NOT EXISTS sync_versions ('
    'tbl TEXT NOT NULL, row_id TEXT NOT NULL, hlc TEXT NOT NULL, '
    'origin TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0, '
    'seq INTEGER NOT NULL, PRIMARY KEY (tbl, row_id))',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_sync_versions_seq ON sync_versions (seq)',
  );
  await db.customStatement(
    "INSERT OR IGNORE INTO sync_state (key, value) "
    "VALUES ('device_id', lower(hex(randomblob(8))))",
  );
  // Devices this one is paired with: the key they share, the last request
  // counter (seen from them / used towards them) and where to reach them.
  await db.customStatement(
    'CREATE TABLE IF NOT EXISTS sync_peers ('
    'device_id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, '
    'key TEXT NOT NULL, last_counter INTEGER NOT NULL DEFAULT 0, '
    "addresses TEXT NOT NULL DEFAULT '[]', port INTEGER, "
    'created_at TEXT NOT NULL)',
  );
  // Changes received page by page, merged all at once when the transfer ends.
  await db.customStatement(
    'CREATE TABLE IF NOT EXISTS sync_inbox ('
    'peer TEXT NOT NULL, tbl TEXT NOT NULL, row_id TEXT NOT NULL, '
    'hlc TEXT NOT NULL, origin TEXT NOT NULL, deleted INTEGER NOT NULL, '
    'data TEXT, PRIMARY KEY (peer, tbl, row_id))',
  );
  // Edits that lost a last-writer-wins merge while the other side had an
  // unsynced edit of the same row; the losing version is kept here.
  await db.customStatement(
    'CREATE TABLE IF NOT EXISTS sync_conflicts ('
    'id INTEGER PRIMARY KEY AUTOINCREMENT, tbl TEXT NOT NULL, '
    'row_id TEXT NOT NULL, label TEXT, detected_at TEXT NOT NULL, '
    'loser_hlc TEXT NOT NULL, loser_origin TEXT NOT NULL, '
    'winner_hlc TEXT NOT NULL, loser_json TEXT, '
    'seen INTEGER NOT NULL DEFAULT 0, UNIQUE (tbl, row_id, loser_hlc))',
  );
}

/// SQL that advances the clock and stamps `(tbl, rowExpr)` in `sync_versions`.
/// The clock stays monotonic when the wall clock stalls or goes backwards: the
/// counter then increments under the same `last_wall`. Every stamp also takes
/// the next `seq`, so a re-written row moves to the end of the log.
String _stamp(String tbl, String rowExpr, int deleted) =>
    '''
UPDATE sync_clock SET
  counter = CASE WHEN $_wallNow > last_wall THEN 0 ELSE counter + 1 END,
  last_wall = max(last_wall, $_wallNow),
  seq = seq + 1
WHERE id = 1;
INSERT INTO sync_versions (tbl, row_id, hlc, origin, deleted, seq)
SELECT '$tbl', $rowExpr,
  c.last_wall || '-' || printf('%04x', c.counter) || '-' || $_deviceId,
  $_deviceId, $deleted, c.seq
FROM sync_clock c WHERE c.id = 1
ON CONFLICT (tbl, row_id) DO UPDATE SET
  hlc = excluded.hlc, origin = excluded.origin,
  deleted = excluded.deleted, seq = excluded.seq;
''';

/// Stamps `(tbl, rowId)` as a fresh LOCAL change (what the triggers do), for a
/// row that was changed or removed while the triggers were silent (a cascade
/// during a merge) and still has to reach the other devices.
Future<void> stampLocalChange(
  DatabaseConnectionUser db,
  String tbl,
  String rowId, {
  required bool deleted,
}) async {
  await db.customStatement(
    'UPDATE sync_clock SET '
    'counter = CASE WHEN $_wallNow > last_wall THEN 0 ELSE counter + 1 END, '
    'last_wall = max(last_wall, $_wallNow), seq = seq + 1 WHERE id = 1',
  );
  await db.customStatement(
    'INSERT INTO sync_versions (tbl, row_id, hlc, origin, deleted, seq) '
    "SELECT ?, ?, c.last_wall || '-' || printf('%04x', c.counter) || '-' || "
    '$_deviceId, $_deviceId, ?, c.seq FROM sync_clock c WHERE c.id = 1 '
    'ON CONFLICT (tbl, row_id) DO UPDATE SET hlc = excluded.hlc, '
    'origin = excluded.origin, deleted = excluded.deleted, seq = excluded.seq',
    [tbl, rowId, deleted ? 1 : 0],
  );
}

Future<List<String>> _columns(DatabaseConnectionUser db, String table) async {
  final rows = await db.customSelect('PRAGMA table_info($table)').get();
  return [for (final r in rows) r.read<String>('name')];
}

/// The columns of [table] whose changes are tracked and synced.
Future<List<String>> syncedColumns(
  DatabaseConnectionUser db,
  String table,
) async {
  final excluded = syncExcludedColumns[table] ?? const <String>{};
  return [
    for (final c in await _columns(db, table))
      if (!excluded.contains(c)) c,
  ];
}

/// (Re)creates the sync tables and the three triggers of every synced table.
/// Runs on every open: a `TableMigration` rebuild drops a table's triggers, and
/// a column added later is picked up here without touching this file.
Future<void> ensureSyncTriggers(DatabaseConnectionUser db) async {
  await createSyncTables(db);
  const quiet = '(SELECT flag FROM sync_applying) = 0';
  for (final entry in syncTables.entries) {
    final t = entry.key, pk = entry.value;
    final cols = await syncedColumns(db, t);
    if (cols.isEmpty) continue; // the table does not exist (yet)
    final changed = cols.map((c) => 'OLD.$c IS NOT NEW.$c').join(' OR ');
    for (final suffix in ['ins', 'upd', 'del']) {
      await db.customStatement('DROP TRIGGER IF EXISTS sync_${t}_$suffix');
    }
    await db.customStatement(
      'CREATE TRIGGER sync_${t}_ins AFTER INSERT ON $t WHEN $quiet BEGIN '
      '${_stamp(t, 'NEW.$pk', 0)} END',
    );
    await db.customStatement(
      'CREATE TRIGGER sync_${t}_upd AFTER UPDATE OF ${cols.join(', ')} ON $t '
      'WHEN $quiet AND ($changed) BEGIN ${_stamp(t, 'NEW.$pk', 0)} END',
    );
    await db.customStatement(
      'CREATE TRIGGER sync_${t}_del AFTER DELETE ON $t WHEN $quiet BEGIN '
      '${_stamp(t, 'OLD.$pk', 1)} END',
    );
  }
}

/// Inserts a version for every row of [table] that has none, stamped [hlc]
/// (an SQL expression) by [origin], numbering them after the current `seq`.
Future<void> _insertMissingVersions(
  DatabaseConnectionUser db,
  String table,
  String pk, {
  required String hlcExpr,
  required String originExpr,
}) async {
  await db.customStatement(
    "INSERT INTO sync_versions (tbl, row_id, hlc, origin, deleted, seq) "
    "SELECT '$table', $table.$pk, $hlcExpr, $originExpr, 0, "
    "(SELECT seq FROM sync_clock WHERE id = 1) + "
    "row_number() OVER (ORDER BY $table.rowid) "
    "FROM $table WHERE NOT EXISTS (SELECT 1 FROM sync_versions v "
    "WHERE v.tbl = '$table' AND v.row_id = $table.$pk)",
  );
  await db.customStatement(
    'UPDATE sync_clock SET seq = '
    '(SELECT COALESCE(MAX(seq), 0) FROM sync_versions) WHERE id = 1',
  );
}

/// One-off (schema v11): gives every row that predates sync a version, stamped
/// with its `updated_at` when it has one (else the epoch), origin `seed`. Seeded
/// rows never beat a real edit.
Future<void> backfillSyncVersions(DatabaseConnectionUser db) async {
  for (final entry in syncTables.entries) {
    final t = entry.key, pk = entry.value;
    final cols = await _columns(db, t);
    if (cols.isEmpty) continue;
    await _insertMissingVersions(
      db,
      t,
      pk,
      hlcExpr: cols.contains('updated_at')
          ? "substr($t.updated_at, 1, 23) || 'Z-0000-seed'"
          : "'$syncEpochHlc'",
      originExpr: "'seed'",
    );
  }
}

/// Self-healing: a row without a version (written while its triggers were
/// missing, e.g. copied by a table rebuild) gets one as a fresh local edit, so
/// it is never invisible to sync. Cheap: a NOT EXISTS probe per table.
Future<void> reconcileSyncVersions(DatabaseConnectionUser db) async {
  for (final entry in syncTables.entries) {
    final t = entry.key, pk = entry.value;
    if ((await _columns(db, t)).isEmpty) continue;
    final missing = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM $t WHERE NOT EXISTS ('
          "SELECT 1 FROM sync_versions v WHERE v.tbl = '$t' AND v.row_id = $t.$pk)",
        )
        .getSingle();
    if (missing.read<int>('n') == 0) continue;
    // One clock tick for the whole batch.
    await db.customStatement(
      'UPDATE sync_clock SET '
      'counter = CASE WHEN $_wallNow > last_wall THEN 0 ELSE counter + 1 END, '
      'last_wall = max(last_wall, $_wallNow) WHERE id = 1',
    );
    await _insertMissingVersions(
      db,
      t,
      pk,
      hlcExpr:
          "(SELECT last_wall || '-' || printf('%04x', counter) || '-' || $_deviceId "
          'FROM sync_clock WHERE id = 1)',
      originExpr: _deviceId,
    );
  }
}
