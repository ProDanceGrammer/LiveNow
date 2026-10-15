import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show setEquals;

import '../core/ids.dart';
import '../core/time_codec.dart';
import '../data/database.dart';
import 'dependency_service.dart';

/// How a bulk edit combines the chosen items with what each action has.
enum BulkMode { add, remove, replace }

/// Which side of each selected action the chosen target is on.
enum LinkSide { previous, next }

/// The directions each changed action had before a bulk edit (for Undo).
class BulkMetricsUndo {
  const BulkMetricsUndo(this.before);

  final Map<String, List<String>> before;
}

/// The countable activity each changed action had before a bulk edit (for Undo;
/// null = it had none).
class BulkActivityUndo {
  const BulkActivityUndo(this.before);

  final Map<String, String?> before;
}

/// The edges a bulk link edit added and removed, as (predecessor, successor).
class BulkLinksUndo {
  const BulkLinksUndo(this.added, this.removed);

  final List<(String, String)> added;
  final List<(String, String)> removed;
}

class BulkLinksResult {
  const BulkLinksResult({required this.undo, required this.skippedLoop});

  final BulkLinksUndo undo;

  /// Pairs left out because they would have closed a loop.
  final int skippedLoop;

  int get linked => undo.added.length;
  int get removed => undo.removed.length;
}

/// Edits several actions at once: the same growth directions, or the same
/// previous / next action. Each call is ONE transaction and returns what it
/// needs to be undone as ONE step.
class BulkEditService {
  BulkEditService(this.db) : _deps = DependencyService(db);

  final AppDatabase db;
  final DependencyService _deps;

  // ---- growth directions --------------------------------------------------

  /// [mode]: add [metricIds] to every action, remove them, or replace each
  /// action's directions with exactly them (an empty list clears). Only the
  /// actions that really change are written (their `updated_at` moves) and
  /// remembered for Undo.
  Future<BulkMetricsUndo> setMetricsMany(
    Iterable<String> actionIds,
    List<String> metricIds,
    BulkMode mode,
  ) => db.transaction(() async {
    final before = <String, List<String>>{};
    final chosen = metricIds.toSet();
    final now = dateTimeToDb(DateTime.now())!;
    for (final id in actionIds) {
      final current = await _metricIdsOf(id);
      final cur = current.toSet();
      final next = switch (mode) {
        BulkMode.add => {...cur, ...chosen},
        BulkMode.remove => cur.difference(chosen),
        BulkMode.replace => chosen,
      };
      if (setEquals(cur, next)) continue;
      before[id] = current;
      await _writeMetrics(id, cur, next, now);
    }
    return BulkMetricsUndo(before);
  });

  /// Sets the countable activity of every action in [actionIds] ([activityId] null
  /// clears it) in ONE transaction; actions that already have it are skipped.
  Future<BulkActivityUndo> setActivityMany(
    Iterable<String> actionIds,
    String? activityId,
  ) => db.transaction(() async {
    final before = <String, String?>{};
    final now = dateTimeToDb(DateTime.now())!;
    for (final id in actionIds) {
      final row = await (db.select(
        db.actionsTable,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null || row.countableActivityId == activityId) continue;
      before[id] = row.countableActivityId;
      await (db.update(db.actionsTable)..where((t) => t.id.equals(id))).write(
        ActionsTableCompanion(
          countableActivityId: Value(activityId),
          updatedAt: Value(now),
        ),
      );
    }
    return BulkActivityUndo(before);
  });

  Future<void> undoSetActivityMany(BulkActivityUndo undo) =>
      db.transaction(() async {
        final now = dateTimeToDb(DateTime.now())!;
        for (final e in undo.before.entries) {
          await (db.update(db.actionsTable)..where((t) => t.id.equals(e.key)))
              .write(
                ActionsTableCompanion(
                  countableActivityId: Value(e.value),
                  updatedAt: Value(now),
                ),
              );
        }
      });

  Future<void> undoSetMetricsMany(BulkMetricsUndo undo) =>
      db.transaction(() async {
        final now = dateTimeToDb(DateTime.now())!;
        for (final e in undo.before.entries) {
          final cur = (await _metricIdsOf(e.key)).toSet();
          await _writeMetrics(e.key, cur, e.value.toSet(), now);
        }
      });

  Future<List<String>> _metricIdsOf(String actionId) async => [
    for (final r in await (db.select(
      db.actionMetricsTable,
    )..where((t) => t.actionId.equals(actionId))).get())
      r.metricId,
  ];

  Future<void> _writeMetrics(
    String actionId,
    Set<String> from,
    Set<String> to,
    String now,
  ) async {
    for (final gone in from.difference(to)) {
      await (db.delete(db.actionMetricsTable)..where(
            (t) => t.actionId.equals(actionId) & t.metricId.equals(gone),
          ))
          .go();
    }
    for (final added in to.difference(from)) {
      await db
          .into(db.actionMetricsTable)
          .insert(
            ActionMetricsTableCompanion.insert(
              id: newId(),
              actionId: actionId,
              metricId: added,
            ),
          );
    }
    await (db.update(db.actionsTable)..where((t) => t.id.equals(actionId)))
        .write(ActionsTableCompanion(updatedAt: Value(now)));
  }

  // ---- previous / next links ----------------------------------------------

  /// [targetId] becomes the previous (or next) action of every selected action
  /// ([mode] add), stops being it ([mode] remove), or becomes the ONLY one
  /// ([mode] replace: each action's existing links on that side go first, so a
  /// null target just clears them). Pairs that would close a loop are skipped
  /// and counted; edges that already exist are left alone.
  Future<BulkLinksResult> linkMany(
    Iterable<String> actionIds, {
    required String? targetId,
    required LinkSide side,
    required BulkMode mode,
  }) => db.transaction(() async {
    final added = <(String, String)>[];
    final removed = <(String, String)>[];
    var skipped = 0;

    (String, String) edge(String action, String target) =>
        side == LinkSide.previous ? (target, action) : (action, target);

    Future<bool> exists(String p, String s) async =>
        await (db.select(db.actionDependenciesTable)..where(
              (t) => t.predecessorId.equals(p) & t.successorId.equals(s),
            ))
            .getSingleOrNull() !=
        null;

    Future<void> drop(String p, String s) async {
      if (!await exists(p, s)) return;
      await _deps.removeDependency(predecessorId: p, successorId: s);
      removed.add((p, s));
    }

    Future<void> tryAdd(String p, String s) async {
      if (p == s || await exists(p, s)) return;
      if (await _deps.wouldCycle(predecessorId: p, successorId: s)) {
        skipped++;
        return;
      }
      await _deps.addDependency(predecessorId: p, successorId: s);
      added.add((p, s));
    }

    for (final a in actionIds) {
      if (a == targetId) continue;
      switch (mode) {
        case BulkMode.add:
          if (targetId != null) {
            final (p, s) = edge(a, targetId);
            await tryAdd(p, s);
          }
        case BulkMode.remove:
          if (targetId != null) {
            final (p, s) = edge(a, targetId);
            await drop(p, s);
          }
        case BulkMode.replace:
          final q = db.select(db.actionDependenciesTable);
          final rows = await (side == LinkSide.previous
                  ? (q..where((t) => t.successorId.equals(a)))
                  : (q..where((t) => t.predecessorId.equals(a))))
              .get();
          for (final r in rows) {
            await drop(r.predecessorId, r.successorId);
          }
          if (targetId != null) {
            final (p, s) = edge(a, targetId);
            await tryAdd(p, s);
          }
      }
    }
    // An edge that was removed and added back is no change at all.
    final both = added.toSet().intersection(removed.toSet());
    added.removeWhere(both.contains);
    removed.removeWhere(both.contains);
    return BulkLinksResult(
      undo: BulkLinksUndo(added, removed),
      skippedLoop: skipped,
    );
  });

  Future<void> undoLinkMany(BulkLinksUndo undo) => db.transaction(() async {
    for (final (p, s) in undo.added) {
      await _deps.removeDependency(predecessorId: p, successorId: s);
    }
    for (final (p, s) in undo.removed) {
      // A restored edge could close a loop only if the chain changed since;
      // addDependency then refuses and the edge stays gone.
      try {
        await _deps.addDependency(predecessorId: p, successorId: s);
      } on DependencyCycleException {
        // Left out: the graph moved on.
      }
    }
  });
}
