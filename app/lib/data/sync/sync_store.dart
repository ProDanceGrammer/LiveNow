import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/time_codec.dart';
import '../../domain/notes_plain_text.dart';
import '../../domain/sync/cycle_repair.dart';
import '../../domain/sync/hlc.dart';
import '../../domain/sync/sync_models.dart';
import '../database.dart';
import 'sync_schema.dart';

/// "Row A of this table may only link B once": on a clash the LOWER row id
/// wins on every device (both devices created the link independently).
const _uniqueLinks = {
  'action_dependencies': ('predecessor_id', 'successor_id'),
  'metric_dependencies': ('metric_id', 'depends_on_id'),
  'action_metrics': ('action_id', 'metric_id'),
};

/// Graphs that must stay acyclic. A cycle is broken by dropping the newest
/// edge: deleting its row, or (where the edge is a column of a category) by
/// clearing [nullColumn].
const _graphs = [
  (
    table: 'action_dependencies',
    from: 'predecessor_id',
    to: 'successor_id',
    nullColumn: null,
  ),
  (
    table: 'metric_dependencies',
    from: 'depends_on_id',
    to: 'metric_id',
    nullColumn: null,
  ),
  (
    table: 'budget_categories',
    from: 'id',
    to: 'parent_id',
    nullColumn: 'parent_id',
  ),
  (
    table: 'budget_categories',
    from: 'id',
    to: 'count_percent_of_id',
    nullColumn: 'count_percent_of_id',
  ),
];

typedef _Version = ({String hlc, String origin, bool deleted, int seq});

/// Reads the change log and applies remote changes (last writer wins per row,
/// by clock stamp), keeping the data valid afterwards. See `sync_schema.dart`
/// for how local changes are logged.
class SyncStore {
  SyncStore(this.db, {this.afterApply});

  final AppDatabase db;

  /// Called after a batch changed data, with the tables that were written:
  /// recomputes derived caches (growth direction weights).
  final Future<void> Function(Set<String> tables)? afterApply;

  final _columnCache = <String, List<String>>{};

  Future<String> deviceId() async {
    final r = await db
        .customSelect("SELECT value FROM sync_state WHERE key = 'device_id'")
        .getSingle();
    return r.read<String>('value');
  }

  Future<int> currentSeq() async {
    final r = await db
        .customSelect('SELECT seq FROM sync_clock WHERE id = 1')
        .getSingle();
    return r.read<int>('seq');
  }

  Future<String?> getState(String key) async {
    final r = await db
        .customSelect(
          'SELECT value FROM sync_state WHERE key = ?',
          variables: [Variable.withString(key)],
        )
        .getSingleOrNull();
    return r?.read<String>('value');
  }

  Future<void> setState(String key, String value) => db.customStatement(
    'INSERT INTO sync_state (key, value) VALUES (?, ?) '
    'ON CONFLICT (key) DO UPDATE SET value = excluded.value',
    [key, value],
  );

  /// The clock stamp of a row, or null if it was never written.
  Future<String?> rowHlc(String table, String rowId) async =>
      (await _version(table, rowId))?.hlc;

  // ---- reading ---------------------------------------------------------------

  /// Changes logged after position [since] up to and including [until], oldest
  /// first. [excludeOrigin] leaves out what that device wrote itself.
  Future<List<SyncChange>> changesSince(
    int since, {
    required int until,
    int limit = 500,
    String? excludeOrigin,
  }) async {
    final rows = await db
        .customSelect(
          'SELECT tbl, row_id, hlc, origin, deleted, seq FROM sync_versions '
          'WHERE seq > ? AND seq <= ? '
          '${excludeOrigin == null ? '' : 'AND origin <> ? '}'
          'ORDER BY seq LIMIT ?',
          variables: [
            Variable.withInt(since),
            Variable.withInt(until),
            if (excludeOrigin != null) Variable.withString(excludeOrigin),
            Variable.withInt(limit),
          ],
        )
        .get();
    final out = <SyncChange>[];
    for (final r in rows) {
      final table = r.read<String>('tbl');
      final id = r.read<String>('row_id');
      final deleted = r.read<int>('deleted') != 0;
      final data = deleted ? null : await _rowData(table, id);
      // Removed since the log was read: its tombstone follows.
      if (!deleted && data == null) continue;
      out.add(
        SyncChange(
          table: table,
          rowId: id,
          hlc: r.read<String>('hlc'),
          origin: r.read<String>('origin'),
          deleted: deleted,
          data: data,
          seq: r.read<int>('seq'),
        ),
      );
    }
    return out;
  }

  /// [page] plus the current version of every row its rows refer to that is
  /// not already in it. The log keeps only a row's LATEST version, so a page cut
  /// at some position can carry a transaction but not its category (edited
  /// later, so further on): the receiver, not knowing the category yet, would
  /// have to drop the reference. Shipping the referenced rows along makes every
  /// page self-contained; rows the receiver already holds are ignored there
  /// (same stamp), and the cursor still follows [page] only.
  Future<List<SyncChange>> withDependencies(List<SyncChange> page) async {
    final out = [...page];
    final have = {for (final c in page) '${c.table}/${c.rowId}'};
    for (var i = 0; i < out.length; i++) {
      final c = out[i];
      if (c.deleted) continue;
      for (final fk in await _foreignKeys(c.table)) {
        final id = c.data![fk.column];
        if (id is! String || !have.add('${fk.parent}/$id')) continue;
        final v = await _version(fk.parent, id);
        if (v == null || v.deleted) continue;
        final data = await _rowData(fk.parent, id);
        if (data == null) continue;
        out.add(
          SyncChange(
            table: fk.parent,
            rowId: id,
            hlc: v.hlc,
            origin: v.origin,
            deleted: false,
            data: data,
            seq: v.seq,
          ),
        );
      }
    }
    return out;
  }

  final _fkCache = <String, List<({String column, String parent})>>{};

  Future<List<({String column, String parent})>> _foreignKeys(
    String table,
  ) async => _fkCache[table] ??= [
    for (final f
        in await db.customSelect('PRAGMA foreign_key_list($table)').get())
      if (syncTables.containsKey(f.read<String>('table')))
        (column: f.read<String>('from'), parent: f.read<String>('table')),
  ];

  Future<Map<String, Object?>?> _rowData(String table, String id) async {
    final cols = await _syncedColumns(table);
    final r = await db
        .customSelect(
          'SELECT ${cols.join(', ')} FROM $table WHERE ${syncTables[table]} = ?',
          variables: [Variable.withString(id)],
        )
        .getSingleOrNull();
    if (r == null) return null;
    return {for (final c in cols) c: r.data[c]};
  }

  Future<List<String>> _syncedColumns(String table) async =>
      _columnCache[table] ??= await syncedColumns(db, table);

  Future<_Version?> _version(String table, String id) async {
    final r = await db
        .customSelect(
          'SELECT hlc, origin, deleted, seq FROM sync_versions '
          'WHERE tbl = ? AND row_id = ?',
          variables: [Variable.withString(table), Variable.withString(id)],
        )
        .getSingleOrNull();
    if (r == null) return null;
    return (
      hlc: r.read<String>('hlc'),
      origin: r.read<String>('origin'),
      deleted: r.read<int>('deleted') != 0,
      seq: r.read<int>('seq'),
    );
  }

  // ---- applying --------------------------------------------------------------

  /// Applies [changes] from another device in ONE transaction. A change wins
  /// when its stamp is newer than the row's; the triggers stay silent so it is
  /// not logged as a local edit. [unsyncedAfterSeq] is this device's log
  /// position the sender is known to have: a row stamped after it by someone
  /// else is a concurrent edit, and the losing side is kept in
  /// `sync_conflicts`. Afterwards dangling references, duplicate links,
  /// cycles and the budget leaf rule are repaired.
  Future<ApplyResult> apply(
    List<SyncChange> changes, {
    required int unsyncedAfterSeq,
  }) {
    if (changes.isEmpty) return Future.value(const ApplyResult());
    return _applyChunks((feed) => feed(changes), unsyncedAfterSeq);
  }

  /// Parks the changes of one page received from [peerId] in the inbox (no
  /// merge yet). A transfer arrives in pages, and a row can come a page before
  /// the row it refers to, so nothing is merged or repaired until the last page
  /// is in: [applyStaged] then merges everything at once. Survives a crash.
  Future<void> stage(String peerId, List<SyncChange> changes) =>
      db.transaction(() async {
        for (final c in changes) {
          await db.customStatement(
            'INSERT INTO sync_inbox (peer, tbl, row_id, hlc, origin, deleted, data) '
            'VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT (peer, tbl, row_id) '
            'DO UPDATE SET hlc = excluded.hlc, origin = excluded.origin, '
            'deleted = excluded.deleted, data = excluded.data '
            'WHERE excluded.hlc > sync_inbox.hlc',
            [
              peerId,
              c.table,
              c.rowId,
              c.hlc,
              c.origin,
              c.deleted ? 1 : 0,
              c.data == null ? null : jsonEncode(c.data),
            ],
          );
        }
      });

  /// Merges everything staged for [peerId] in one transaction (see [apply]).
  Future<ApplyResult> applyStaged(
    String peerId, {
    required int unsyncedAfterSeq,
  }) async {
    final any = await db
        .customSelect(
          'SELECT 1 FROM sync_inbox WHERE peer = ? LIMIT 1',
          variables: [Variable.withString(peerId)],
        )
        .getSingleOrNull();
    if (any == null) return const ApplyResult();
    return _applyChunks((feed) async {
      var lastRowId = 0;
      while (true) {
        final rows = await db
            .customSelect(
              'SELECT rowid AS rid, tbl, row_id, hlc, origin, deleted, data '
              'FROM sync_inbox WHERE peer = ? AND rowid > ? '
              'ORDER BY rowid LIMIT 500',
              variables: [
                Variable.withString(peerId),
                Variable.withInt(lastRowId),
              ],
            )
            .get();
        if (rows.isEmpty) break;
        lastRowId = rows.last.read<int>('rid');
        await feed([
          for (final r in rows)
            SyncChange(
              table: r.read<String>('tbl'),
              rowId: r.read<String>('row_id'),
              hlc: r.read<String>('hlc'),
              origin: r.read<String>('origin'),
              deleted: r.read<int>('deleted') != 0,
              data: r.readNullable<String>('data') == null
                  ? null
                  : (jsonDecode(r.read<String>('data')) as Map)
                        .cast<String, Object?>(),
            ),
        ]);
      }
      await db.customStatement('DELETE FROM sync_inbox WHERE peer = ?', [
        peerId,
      ]);
    }, unsyncedAfterSeq);
  }

  /// The merge itself: [source] hands over the changes in chunks through
  /// `feed`; everything happens in one transaction, repairs run once at the end.
  Future<ApplyResult> _applyChunks(
    Future<void> Function(Future<void> Function(List<SyncChange>) feed) source,
    int unsyncedAfterSeq,
  ) async {
    var applied = 0, conflicts = 0;
    final repairs = <SyncRepair>[];
    final touched = <String>{};
    await db.transaction(() async {
      await _setApplying(true);
      await db.customStatement('PRAGMA defer_foreign_keys = ON');
      await source((changes) async {
        for (final c in changes) {
          final r = await _applyOne(c, unsyncedAfterSeq, repairs);
          if (r.applied) {
            applied++;
            touched.add(c.table);
          }
          if (r.conflict) conflicts++;
        }
      });
      if (applied > 0) {
        await _repairForeignKeys(repairs);
        if (touched.contains('budget_categories') ||
            touched.contains('budget_transactions')) {
          await _repairBudgetLeaves(repairs);
        }
        for (final g in _graphs) {
          if (touched.contains(g.table)) await _repairCycles(g, repairs);
        }
        await _sweepOrphans();
      }
      await _setApplying(false);
    });
    if (applied > 0 || repairs.isNotEmpty) {
      // Raw statements do not tell Drift's streams, so say what may have moved.
      db.notifyUpdates({for (final t in syncTables.keys) TableUpdate(t)});
      await afterApply?.call({...touched, for (final r in repairs) r.table});
    }
    return ApplyResult(
      applied: applied,
      conflicts: conflicts,
      repairs: repairs,
    );
  }

  Future<void> _setApplying(bool on) =>
      db.customStatement('UPDATE sync_applying SET flag = ${on ? 1 : 0}');

  /// Runs [body] with the triggers on, so what it writes counts as a local
  /// edit (stamped and sent on): used for repairs the other devices must see.
  Future<void> _asLocalEdit(Future<void> Function() body) async {
    await _setApplying(false);
    try {
      await body();
    } finally {
      await _setApplying(true);
    }
  }

  Future<({bool applied, bool conflict})> _applyOne(
    SyncChange c,
    int unsyncedAfterSeq,
    List<SyncRepair> repairs,
  ) async {
    const skipped = (applied: false, conflict: false);
    final pk = syncTables[c.table];
    if (pk == null) return skipped; // a table this version does not know
    final local = await _version(c.table, c.rowId);
    final remoteWins = local == null || compareHlc(c.hlc, local.hlc) > 0;
    // Both sides edited the row since they last met (and it is not just two
    // deletions, or a seeded row nobody touched).
    final concurrent =
        local != null &&
        local.hlc != c.hlc &&
        local.origin != c.origin &&
        local.origin != 'seed' &&
        local.seq > unsyncedAfterSeq &&
        !(local.deleted && c.deleted);

    if (!remoteWins) {
      if (!concurrent) return skipped;
      final made = await _recordConflict(
        c.table,
        c.rowId,
        loserHlc: c.hlc,
        loserOrigin: c.origin,
        winnerHlc: local.hlc,
        loserData: c.data,
      );
      return (applied: false, conflict: made);
    }

    await _observeClock(c.hlc);
    var conflict = false;
    if (concurrent) {
      conflict = await _recordConflict(
        c.table,
        c.rowId,
        loserHlc: local.hlc,
        loserOrigin: local.origin,
        winnerHlc: c.hlc,
        loserData: local.deleted ? null : await _rowData(c.table, c.rowId),
      );
    }
    if (c.deleted) {
      // With the triggers ON: what the deletion drags along (children removed,
      // references set to NULL by the foreign-key actions) becomes stamped local
      // edits that reach every device. Done silently, a later concurrent edit
      // that revives this row would leave the devices disagreeing about those
      // references for good. The row's own stamp is overwritten just below.
      await _asLocalEdit(
        () => db.customStatement('DELETE FROM ${c.table} WHERE $pk = ?', [
          c.rowId,
        ]),
      );
    } else {
      if (!await _claimLink(c, repairs)) {
        return (applied: false, conflict: conflict);
      }
      await _upsert(c, pk);
    }
    await _writeVersion(c);
    return (applied: true, conflict: conflict);
  }

  /// Makes room for an incoming link row whose (a, b) pair already exists under
  /// another id: the lower id stays. Returns false when the incoming row lost
  /// (it is tombstoned locally, and that tombstone travels back).
  Future<bool> _claimLink(SyncChange c, List<SyncRepair> repairs) async {
    final pair = _uniqueLinks[c.table];
    if (pair == null) return true;
    final (a, b) = pair;
    final existing = await db
        .customSelect(
          'SELECT id FROM ${c.table} WHERE $a = ? AND $b = ? AND id <> ?',
          variables: [
            Variable.withString(c.data![a]! as String),
            Variable.withString(c.data![b]! as String),
            Variable.withString(c.rowId),
          ],
        )
        .getSingleOrNull();
    if (existing == null) return true;
    final existingId = existing.read<String>('id');
    if (existingId.compareTo(c.rowId) < 0) {
      await stampLocalChange(db, c.table, c.rowId, deleted: true);
      repairs.add(SyncRepair('duplicate-link', c.table, c.rowId));
      return false;
    }
    await _asLocalEdit(
      () => db.customStatement('DELETE FROM ${c.table} WHERE id = ?', [
        existingId,
      ]),
    );
    repairs.add(SyncRepair('duplicate-link', c.table, existingId));
    return true;
  }

  Future<void> _upsert(SyncChange c, String pk) async {
    final data = c.data!;
    final cols = [
      for (final col in await _syncedColumns(c.table))
        if (data.containsKey(col)) col,
    ];
    final values = <Object?>[for (final col in cols) data[col]];
    if (c.table == 'actions') {
      // Derived from the notes, never sent.
      cols.add('notes_text');
      values.add(notesPlainText(data['notes'] as String?));
    }
    final updates = [
      for (final col in cols)
        if (col != pk) '$col = excluded.$col',
    ];
    await db.customStatement(
      'INSERT INTO ${c.table} (${cols.join(', ')}) '
      'VALUES (${List.filled(cols.length, '?').join(', ')}) '
      'ON CONFLICT ($pk) DO ${updates.isEmpty ? 'NOTHING' : 'UPDATE SET ${updates.join(', ')}'}',
      values,
    );
  }

  Future<void> _writeVersion(SyncChange c) async {
    await db.customStatement(
      'UPDATE sync_clock SET seq = seq + 1 WHERE id = 1',
    );
    await db.customStatement(
      'INSERT INTO sync_versions (tbl, row_id, hlc, origin, deleted, seq) '
      'VALUES (?, ?, ?, ?, ?, (SELECT seq FROM sync_clock WHERE id = 1)) '
      'ON CONFLICT (tbl, row_id) DO UPDATE SET hlc = excluded.hlc, '
      'origin = excluded.origin, deleted = excluded.deleted, seq = excluded.seq',
      [c.table, c.rowId, c.hlc, c.origin, c.deleted ? 1 : 0],
    );
  }

  /// Moves the local clock past a stamp received from elsewhere, so an edit
  /// made right after a sync is newer than everything just merged.
  Future<void> _observeClock(String hlc) async {
    final (:wall, :counter) = parseHlc(hlc);
    await db.customStatement(
      'UPDATE sync_clock SET '
      'counter = CASE WHEN ? > last_wall THEN ? '
      'WHEN ? = last_wall THEN max(counter, ?) ELSE counter END, '
      'last_wall = max(last_wall, ?) WHERE id = 1',
      [wall, counter, wall, counter, wall],
    );
  }

  /// Empties every synced table and the whole sync history (versions, inbox,
  /// conflicts, per-peer cursors), keeping this device's id and clock. Used
  /// when a phone pairs for the first time: the PC's data then replaces it, and
  /// the next sync pulls everything from position 0.
  Future<void> wipeForReplace() async {
    await db.transaction(() async {
      await _setApplying(true);
      await db.customStatement('PRAGMA defer_foreign_keys = ON');
      for (final t in syncTables.keys) {
        await db.customStatement('DELETE FROM $t');
      }
      await db.customStatement('DELETE FROM sync_versions');
      await db.customStatement('DELETE FROM sync_inbox');
      await db.customStatement('DELETE FROM sync_conflicts');
      await db.customStatement(
        "DELETE FROM sync_state WHERE key LIKE 'pulled:%' "
        "OR key LIKE 'pushed:%' OR key LIKE 'served:%'",
      );
      await _setApplying(false);
    });
    db.notifyUpdates({for (final t in syncTables.keys) TableUpdate(t)});
    await afterApply?.call(syncTables.keys.toSet());
  }

  // ---- conflicts -------------------------------------------------------------

  Future<bool> _recordConflict(
    String table,
    String rowId, {
    required String loserHlc,
    required String loserOrigin,
    required String winnerHlc,
    required Map<String, Object?>? loserData,
  }) async {
    final exists = await db
        .customSelect(
          'SELECT 1 FROM sync_conflicts WHERE tbl = ? AND row_id = ? '
          'AND loser_hlc = ?',
          variables: [
            Variable.withString(table),
            Variable.withString(rowId),
            Variable.withString(loserHlc),
          ],
        )
        .getSingleOrNull();
    if (exists != null) return false;
    await db.customStatement(
      'INSERT INTO sync_conflicts (tbl, row_id, label, detected_at, loser_hlc, '
      'loser_origin, winner_hlc, loser_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        table,
        rowId,
        loserData?['name'],
        dateTimeToDb(DateTime.now().toUtc()),
        loserHlc,
        loserOrigin,
        winnerHlc,
        loserData == null ? null : jsonEncode(loserData),
      ],
    );
    return true;
  }

  Future<List<SyncConflict>> conflicts({bool unseenOnly = false}) async {
    final rows = await db
        .customSelect(
          'SELECT * FROM sync_conflicts '
          '${unseenOnly ? 'WHERE seen = 0 ' : ''}ORDER BY id DESC',
        )
        .get();
    return [
      for (final r in rows)
        SyncConflict(
          id: r.read<int>('id'),
          table: r.read<String>('tbl'),
          rowId: r.read<String>('row_id'),
          label: r.readNullable<String>('label'),
          detectedAt: r.read<String>('detected_at'),
          loserHlc: r.read<String>('loser_hlc'),
          loserOrigin: r.read<String>('loser_origin'),
          winnerHlc: r.read<String>('winner_hlc'),
          loserData: r.readNullable<String>('loser_json') == null
              ? null
              : (jsonDecode(r.read<String>('loser_json')) as Map)
                    .cast<String, Object?>(),
          seen: r.read<int>('seen') != 0,
        ),
    ];
  }

  Future<void> markConflictsSeen() =>
      db.customStatement('UPDATE sync_conflicts SET seen = 1');

  // ---- repairs ---------------------------------------------------------------

  /// References to rows that do not exist (the parent was deleted on another
  /// device): a nullable reference is cleared, a row that cannot exist without
  /// its parent is deleted. Both are stamped local edits so they travel: a
  /// silent fix would let a later revival of the parent split the devices.
  Future<void> _repairForeignKeys(List<SyncRepair> repairs) async {
    for (var round = 0; round < 8; round++) {
      final bad = await db.customSelect('PRAGMA foreign_key_check').get();
      if (bad.isEmpty) return;
      final fks = <String, Map<int, String>>{};
      final notNull = <String, Set<String>>{};
      for (final r in bad) {
        final table = r.read<String>('table');
        final rowid = r.read<int>('rowid');
        final fkid = r.read<int>('fkid');
        fks[table] ??= {
          for (final f
              in await db.customSelect('PRAGMA foreign_key_list($table)').get())
            f.read<int>('id'): f.read<String>('from'),
        };
        notNull[table] ??= {
          for (final c
              in await db.customSelect('PRAGMA table_info($table)').get())
            if (c.read<int>('notnull') != 0) c.read<String>('name'),
        };
        final column = fks[table]![fkid]!;
        final idRow = await db
            .customSelect(
              'SELECT ${syncTables[table] ?? 'rowid'} AS id FROM $table '
              'WHERE rowid = ?',
              variables: [Variable.withInt(rowid)],
            )
            .getSingleOrNull();
        final id = idRow?.read<String>('id') ?? '$rowid';
        if (notNull[table]!.contains(column)) {
          await _asLocalEdit(
            () => db.customStatement('DELETE FROM $table WHERE rowid = ?', [
              rowid,
            ]),
          );
          repairs.add(SyncRepair('dangling-row', table, id));
        } else {
          await _asLocalEdit(
            () => db.customStatement(
              'UPDATE $table SET $column = NULL WHERE rowid = ?',
              [rowid],
            ),
          );
          repairs.add(SyncRepair('cleared-reference', table, id));
        }
      }
    }
  }

  /// Only a budget category WITHOUT sub-categories may hold transactions. After
  /// a merge one that has both gives up the newest of them: the newest
  /// sub-category loses its parent, or the newest transaction its category.
  Future<void> _repairBudgetLeaves(List<SyncRepair> repairs) async {
    while (true) {
      final groups = await db
          .customSelect(
            'SELECT c.id AS id FROM budget_categories c WHERE '
            'EXISTS (SELECT 1 FROM budget_categories k WHERE k.parent_id = c.id) '
            'AND EXISTS (SELECT 1 FROM budget_transactions t '
            'WHERE t.category_id = c.id)',
          )
          .get();
      if (groups.isEmpty) return;
      for (final g in groups) {
        final id = g.read<String>('id');
        final rows = await db
            .customSelect(
              "SELECT 'budget_categories' AS tbl, 'parent_id' AS col, k.id AS id, v.hlc AS hlc "
              'FROM budget_categories k JOIN sync_versions v '
              "ON v.tbl = 'budget_categories' AND v.row_id = k.id "
              'WHERE k.parent_id = ?1 UNION ALL '
              "SELECT 'budget_transactions', 'category_id', t.id, v.hlc "
              'FROM budget_transactions t JOIN sync_versions v '
              "ON v.tbl = 'budget_transactions' AND v.row_id = t.id "
              'WHERE t.category_id = ?1',
              variables: [Variable.withString(id)],
            )
            .get();
        final newest = rows.reduce((a, b) {
          final c = compareHlc(a.read<String>('hlc'), b.read<String>('hlc'));
          final aNewer = c != 0
              ? c > 0
              : a.read<String>('id').compareTo(b.read<String>('id')) > 0;
          return aNewer ? a : b;
        });
        final table = newest.read<String>('tbl');
        final rowId = newest.read<String>('id');
        await _asLocalEdit(
          () => db.customStatement(
            'UPDATE $table SET ${newest.read<String>('col')} = NULL WHERE id = ?',
            [rowId],
          ),
        );
        repairs.add(SyncRepair('leaf-rule', table, rowId));
      }
    }
  }

  Future<void> _repairCycles(
    ({String table, String from, String to, String? nullColumn}) g,
    List<SyncRepair> repairs,
  ) async {
    final rows = await db
        .customSelect(
          'SELECT t.id AS id, t.${g.from} AS a, t.${g.to} AS b, v.hlc AS hlc '
          'FROM ${g.table} t JOIN sync_versions v '
          'ON v.tbl = ? AND v.row_id = t.id WHERE t.${g.to} IS NOT NULL',
          variables: [Variable.withString(g.table)],
        )
        .get();
    final edges = [
      for (final r in rows)
        CycleEdge(
          r.read<String>('id'),
          r.read<String>('a'),
          r.read<String>('b'),
          r.read<String>('hlc'),
        ),
    ];
    for (final id in edgesToBreak(edges)) {
      await _asLocalEdit(
        () => g.nullColumn == null
            ? db.customStatement('DELETE FROM ${g.table} WHERE id = ?', [id])
            : db.customStatement(
                'UPDATE ${g.table} SET ${g.nullColumn} = NULL WHERE id = ?',
                [id],
              ),
      );
      repairs.add(SyncRepair('cycle', g.table, id));
    }
  }

  /// Rows a merge removed through a foreign-key cascade while the triggers were
  /// silent: their versions still say "alive", so give them a fresh tombstone.
  Future<void> _sweepOrphans() async {
    for (final e in syncTables.entries) {
      final orphans = await db
          .customSelect(
            'SELECT v.row_id AS id FROM sync_versions v WHERE v.tbl = ? '
            'AND v.deleted = 0 AND NOT EXISTS '
            '(SELECT 1 FROM ${e.key} WHERE ${e.value} = v.row_id)',
            variables: [Variable.withString(e.key)],
          )
          .get();
      for (final o in orphans) {
        await stampLocalChange(db, e.key, o.read<String>('id'), deleted: true);
      }
    }
  }
}
