import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/ids.dart';
import '../core/time_codec.dart';
import '../data/database.dart';
import 'duration_rules.dart';
import 'postpone_rules.dart';
import 'sequence_naming.dart';

/// A full copy of one action's row and its entire occurrence history, taken
/// just before a quick-action button changes it — lets [ActionService.restore]
/// put everything back exactly as it was (the Undo feature).
class ActionSnapshot {
  final ActionRow action;
  final List<ActionOccurrence> occurrences;

  const ActionSnapshot({required this.action, required this.occurrences});
}

/// What [ActionService.continueSameAction] created, plus everything
/// [ActionService.undoContinue] needs to take it back.
class ContinueResult {
  final String newActionId;
  final ContinueUndo undo;

  const ContinueResult({required this.newActionId, required this.undo});
}

/// The pre-continue state that a continue changes: the source action's row
/// (it gets renamed/numbered) and which actions it used to point at (those
/// edges are moved onto the new action).
class ContinueUndo {
  final String newActionId;
  final ActionRow sourceBefore;
  final List<String> formerSuccessorIds;

  const ContinueUndo({
    required this.newActionId,
    required this.sourceBefore,
    required this.formerSuccessorIds,
  });
}

/// Every row [ActionService.deleteAction] removed, kept so
/// [ActionService.undoDelete] can restore the action exactly.
class DeleteUndo {
  final ActionRow action;
  final List<ActionOccurrence> occurrences;
  final List<ActionMetric> metricLinks;
  final List<ActionDependency> edges;

  const DeleteUndo({
    required this.action,
    required this.occurrences,
    required this.metricLinks,
    required this.edges,
  });
}

/// Everything [ActionService.deleteActions] removed, in deletion order.
class DeleteManyUndo {
  final List<DeleteUndo> parts;

  const DeleteManyUndo(this.parts);

  int get count => parts.length;
}

/// One action's new schedule for [ActionService.moveActions].
class ScheduleChange {
  final String id;
  final DateTime? startAt;
  final DateTime? endAt;

  const ScheduleChange(this.id, {required this.startAt, required this.endAt});
}

/// The schedules [ActionService.moveActions] overwrote.
class MoveManyUndo {
  final List<ScheduleChange> before;

  const MoveManyUndo(this.before);
}

/// How far back finished runs count toward a Countable Activity's average
/// ("over the last month" in the Notion prototype).
const Duration _countableAverageWindow = Duration(days: 30);

/// How far back same-name runs in an action's chain count when it has no
/// Countable Activity.
const Duration _chainAverageWindow = Duration(days: 7);

/// Create/edit/start/finish/postpone an action, continue it, and instantiate
/// one from a saved template.
class ActionService {
  final AppDatabase db;

  ActionService(this.db);

  Future<String> createAction({
    required String name,
    String postponeFlex = 'flexible',
    String? depthLevel,
    DateTime? startAt,
    DateTime? endAt,
    bool isAllDay = false,
    int? estimatedMinutes,
    String? countableActivityId,
    String? notes,
    List<String> metricIds = const [],
  }) async {
    final id = newId();
    final nowText = dateTimeToDb(DateTime.now())!;

    await db.transaction(() async {
      await db
          .into(db.actionsTable)
          .insert(
            ActionsTableCompanion.insert(
              id: id,
              name: name,
              postponeFlex: Value(postponeFlex),
              depthLevel: Value(depthLevel),
              startAt: Value(dateTimeToDb(startAt)),
              endAt: Value(dateTimeToDb(endAt)),
              isAllDay: Value(isAllDay),
              estimatedMinutes: Value(estimatedMinutes),
              countableActivityId: Value(countableActivityId),
              notes: Value(notes),
              createdAt: nowText,
              updatedAt: nowText,
            ),
          );

      for (final metricId in metricIds) {
        await db
            .into(db.actionMetricsTable)
            .insert(
              ActionMetricsTableCompanion.insert(
                id: newId(),
                actionId: id,
                metricId: metricId,
              ),
            );
      }
    });

    return id;
  }

  /// Updates an existing action's editable fields (used by the editor form).
  Future<void> updateAction({
    required String actionId,
    required String name,
    required String postponeFlex,
    String? depthLevel,
    DateTime? startAt,
    DateTime? endAt,
    required bool isAllDay,
    // Absent = leave the notes as they are (a caller that doesn't know about
    // notes must not wipe them); `Value(null)` clears them.
    Value<String?> notes = const Value.absent(),
  }) {
    final nowText = dateTimeToDb(DateTime.now())!;
    return (db.update(
      db.actionsTable,
    )..where((t) => t.id.equals(actionId))).write(
      ActionsTableCompanion(
        name: Value(name),
        postponeFlex: Value(postponeFlex),
        depthLevel: Value(depthLevel),
        startAt: Value(dateTimeToDb(startAt)),
        endAt: Value(dateTimeToDb(endAt)),
        isAllDay: Value(isAllDay),
        notes: notes,
        updatedAt: Value(nowText),
      ),
    );
  }

  /// Deletes an action together with its dependency edges, metric links and
  /// occurrence history, and returns everything it removed so [undoDelete]
  /// can put it back. Its neighbours in a chain are left as they are (no
  /// bridging), so a deleted middle link splits the chain.
  /// Rows are removed explicitly rather than relying on ON DELETE CASCADE,
  /// which is only active when foreign keys are enabled on the connection.
  Future<DeleteUndo> deleteAction(String actionId) {
    return db.transaction(() async {
      final action = await (db.select(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).getSingle();
      final occurrences = await (db.select(
        db.actionOccurrencesTable,
      )..where((t) => t.actionId.equals(actionId))).get();
      final metricLinks = await (db.select(
        db.actionMetricsTable,
      )..where((t) => t.actionId.equals(actionId))).get();
      final edges =
          await (db.select(db.actionDependenciesTable)..where(
                (t) =>
                    t.predecessorId.equals(actionId) |
                    t.successorId.equals(actionId),
              ))
              .get();

      await (db.delete(db.actionDependenciesTable)..where(
            (t) =>
                t.predecessorId.equals(actionId) |
                t.successorId.equals(actionId),
          ))
          .go();
      await (db.delete(
        db.actionMetricsTable,
      )..where((t) => t.actionId.equals(actionId))).go();
      await (db.delete(
        db.actionOccurrencesTable,
      )..where((t) => t.actionId.equals(actionId))).go();
      await (db.delete(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).go();

      return DeleteUndo(
        action: action,
        occurrences: occurrences,
        metricLinks: metricLinks,
        edges: edges,
      );
    });
  }

  /// Puts back what [deleteAction] removed, under the same ids. Edges whose
  /// other end has been deleted in the meantime, and metric links to a
  /// deleted metric, are skipped rather than failing the whole undo.
  Future<void> undoDelete(DeleteUndo undo) {
    return db.transaction(() async {
      await db.into(db.actionsTable).insert(undo.action);
      for (final occurrence in undo.occurrences) {
        await db.into(db.actionOccurrencesTable).insert(occurrence);
      }

      final metricIds = (await db.select(db.metricsTable).get())
          .map((m) => m.id)
          .toSet();
      for (final link in undo.metricLinks) {
        if (metricIds.contains(link.metricId)) {
          await db.into(db.actionMetricsTable).insert(link);
        }
      }

      final actionIds = (await db.select(db.actionsTable).get())
          .map((a) => a.id)
          .toSet();
      for (final edge in undo.edges) {
        if (actionIds.contains(edge.predecessorId) &&
            actionIds.contains(edge.successorId)) {
          await db.into(db.actionDependenciesTable).insert(edge);
        }
      }
    });
  }

  /// Deletes several actions in ONE transaction (each as [deleteAction]
  /// does). Ids that no longer exist are skipped. Undo with [undoDeleteMany].
  Future<DeleteManyUndo> deleteActions(Iterable<String> ids) {
    final unique = ids.toSet();
    return db.transaction(() async {
      final existing = (await (db.select(
        db.actionsTable,
      )..where((t) => t.id.isIn(unique))).get()).map((a) => a.id).toSet();
      final parts = <DeleteUndo>[];
      // Keep the caller's order so undo (which runs in reverse) is exact.
      for (final id in ids) {
        if (existing.remove(id)) parts.add(await deleteAction(id));
      }
      return DeleteManyUndo(parts);
    });
  }

  /// Puts back what [deleteActions] removed. Restored in REVERSE order so a
  /// dependency edge between two deleted actions (recorded with whichever was
  /// deleted first) finds both ends present again.
  Future<void> undoDeleteMany(DeleteManyUndo undo) {
    return db.transaction(() async {
      for (final part in undo.parts.reversed) {
        await undoDelete(part);
      }
    });
  }

  /// Sets the schedule of several actions in ONE transaction (each as
  /// [updateSchedule]) and returns the previous schedules for
  /// [undoMoveActions]. Unknown ids are skipped. Unlike snapshot/restore this
  /// only rewrites start/end, so links and history are never touched.
  Future<MoveManyUndo> moveActions(Iterable<ScheduleChange> changes) {
    return db.transaction(() async {
      final before = <ScheduleChange>[];
      for (final c in changes) {
        final row = await (db.select(
          db.actionsTable,
        )..where((t) => t.id.equals(c.id))).getSingleOrNull();
        if (row == null) continue;
        before.add(
          ScheduleChange(
            c.id,
            startAt: dateTimeFromDb(row.startAt),
            endAt: dateTimeFromDb(row.endAt),
          ),
        );
        await updateSchedule(c.id, startAt: c.startAt, endAt: c.endAt);
      }
      return MoveManyUndo(before);
    });
  }

  Future<void> undoMoveActions(MoveManyUndo undo) {
    return db.transaction(() async {
      for (final c in undo.before) {
        await updateSchedule(c.id, startAt: c.startAt, endAt: c.endAt);
      }
    });
  }

  /// Creates a Countable Activity and returns its id.
  Future<String> createCountableActivity(String name) async {
    final id = newId();
    final nowText = dateTimeToDb(DateTime.now())!;
    await db
        .into(db.countableActivitiesTable)
        .insert(
          CountableActivitiesTableCompanion.insert(
            id: id,
            name: name,
            createdAt: nowText,
            updatedAt: nowText,
          ),
        );
    return id;
  }

  /// Links [actionId] to a Countable Activity (null clears the link).
  Future<void> setCountableActivity(String actionId, String? activityId) {
    return (db.update(
      db.actionsTable,
    )..where((t) => t.id.equals(actionId))).write(
      ActionsTableCompanion(
        countableActivityId: Value(activityId),
        updatedAt: Value(dateTimeToDb(DateTime.now())!),
      ),
    );
  }

  /// Replaces an action's linked metrics with exactly [metricIds].
  Future<void> setMetrics(String actionId, List<String> metricIds) {
    return db.transaction(() async {
      await (db.delete(
        db.actionMetricsTable,
      )..where((t) => t.actionId.equals(actionId))).go();
      for (final metricId in metricIds) {
        await db
            .into(db.actionMetricsTable)
            .insert(
              ActionMetricsTableCompanion.insert(
                id: newId(),
                actionId: actionId,
                metricId: metricId,
              ),
            );
      }
    });
  }

  /// Starts (or restarts) timing an action, and sets `start_at` to now every
  /// time — that field is the one place the UI shows/lets you postpone "the
  /// current time of this task", so every press of Start must move it,
  /// whether or not an occurrence was already running. Any existing
  /// duration (see [computeActionDuration]) is preserved onto the new start.
  /// Always reopens a done action first (clears the manual `done` flag) —
  /// starting it means it's in progress, not finished — including when an
  /// occurrence is already running (an action can end up marked done while
  /// still running if it was finished and then started again from an old
  /// build; this self-heals that instead of getting stuck).
  Future<void> start(String actionId) async {
    final nowUtc = DateTime.now().toUtc();
    final nowText = dateTimeToDb(nowUtc)!;

    await db.transaction(() async {
      final action = await (db.select(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).getSingle();
      final duration = computeActionDuration(
        startAt: dateTimeFromDb(action.startAt),
        endAt: dateTimeFromDb(action.endAt),
        legacyEstimatedMinutes: action.estimatedMinutes,
      );
      final newEnd = nowUtc.add(duration);

      await (db.update(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).write(
        ActionsTableCompanion(
          done: const Value(false),
          completedAt: const Value(null),
          startAt: Value(nowText),
          endAt: Value(dateTimeToDb(newEnd)),
          updatedAt: Value(nowText),
        ),
      );

      final runningOccurrence =
          await (db.select(db.actionOccurrencesTable)..where(
                (t) => t.actionId.equals(actionId) & t.finishedAt.isNull(),
              ))
              .getSingleOrNull();

      if (runningOccurrence != null) {
        // Re-pressing Start while already running resets when it "started"
        // too, rather than leaving the button looking like it did nothing.
        await (db.update(db.actionOccurrencesTable)
              ..where((t) => t.id.equals(runningOccurrence.id)))
            .write(ActionOccurrencesTableCompanion(startedAt: Value(nowText)));
        return;
      }

      await db
          .into(db.actionOccurrencesTable)
          .insert(
            ActionOccurrencesTableCompanion.insert(
              id: newId(),
              actionId: actionId,
              startedAt: Value(nowText),
            ),
          );
    });
  }

  /// Finishes the action: sets `end_at` to now and the manual `done` flag
  /// true.
  ///
  /// `start_at` is kept as-is if it's already set and at/before now — the
  /// scheduled start already happened, so the elapsed time is genuine.
  /// Otherwise (empty, or still in the future — i.e. it was never actually
  /// started) finishing "now" means the whole thing just happened right
  /// now: `start_at` is set to `now - duration` (see [computeActionDuration]),
  /// so e.g. a 90-minute action finished cold ends up as
  /// "90 minutes ago -> now", not "some stale future time -> now". This
  /// mirrors the original Notion "Finished Now" button formula exactly.
  Future<void> finish(String actionId) async {
    final nowUtc = DateTime.now().toUtc();
    final nowText = dateTimeToDb(nowUtc)!;

    await db.transaction(() async {
      final action = await (db.select(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).getSingle();

      final oldStart = dateTimeFromDb(action.startAt);
      final keepExistingStart = oldStart != null && !oldStart.isAfter(nowUtc);
      final DateTime newStart = keepExistingStart
          ? oldStart
          : nowUtc.subtract(
              computeActionDuration(
                startAt: oldStart,
                endAt: dateTimeFromDb(action.endAt),
                legacyEstimatedMinutes: action.estimatedMinutes,
              ),
            );

      final runningOccurrence =
          await (db.select(db.actionOccurrencesTable)..where(
                (t) => t.actionId.equals(actionId) & t.finishedAt.isNull(),
              ))
              .getSingleOrNull();

      if (runningOccurrence != null) {
        // Also re-sync startedAt to newStart: if it was back-projected above
        // (oldStart was empty or still in the future — e.g. a postpone had
        // pushed it ahead of "now"), the occurrence's own startedAt would
        // otherwise be left stale, pointing at a time after finishedAt.
        await (db.update(
          db.actionOccurrencesTable,
        )..where((t) => t.id.equals(runningOccurrence.id))).write(
          ActionOccurrencesTableCompanion(
            startedAt: Value(dateTimeToDb(newStart)),
            finishedAt: Value(nowText),
            outcome: const Value('done'),
          ),
        );
      } else {
        await db
            .into(db.actionOccurrencesTable)
            .insert(
              ActionOccurrencesTableCompanion.insert(
                id: newId(),
                actionId: actionId,
                startedAt: Value(dateTimeToDb(newStart)),
                finishedAt: Value(nowText),
                outcome: const Value('done'),
              ),
            );
      }

      await (db.update(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).write(
        ActionsTableCompanion(
          done: const Value(true),
          completedAt: Value(nowText),
          startAt: Value(dateTimeToDb(newStart)),
          endAt: Value(nowText),
          updatedAt: Value(nowText),
        ),
      );
    });
  }

  /// "Continue with Same Action": creates the next numbered run of
  /// [sourceId], starting now for its predicted duration (see
  /// [predictedDuration]).
  ///
  /// The source becomes `[#n] Name` and the new action `[#n+1] Name`. The
  /// source's next-action edges move onto the new action and a
  /// source -> new edge is added, so the source ends up with exactly one next
  /// action (the new one) and the new one with exactly one previous action
  /// (the source). The source's own predecessors are not copied. The moved
  /// edges need no cycle check: the new action is a fresh node, and each
  /// `new -> X` only mirrors a `source -> X` that already existed.
  Future<ContinueResult> continueSameAction(String sourceId) {
    final nowUtc = DateTime.now().toUtc();
    final nowText = dateTimeToDb(nowUtc)!;

    return db.transaction(() async {
      final source = await (db.select(
        db.actionsTable,
      )..where((t) => t.id.equals(sourceId))).getSingle();
      final metricIds =
          (await (db.select(
                db.actionMetricsTable,
              )..where((t) => t.actionId.equals(sourceId))).get())
              .map((m) => m.metricId)
              .toList();
      final formerSuccessorIds =
          (await (db.select(
                db.actionDependenciesTable,
              )..where((t) => t.predecessorId.equals(sourceId))).get())
              .map((d) => d.successorId)
              .toList();

      final (prefixNumber, baseName) = parseSequencePrefix(source.name);
      final sequence = source.sequenceNumber ?? prefixNumber ?? 1;

      final predicted = predictedDuration(
        ownDuration: computeActionDuration(
          startAt: dateTimeFromDb(source.startAt),
          endAt: dateTimeFromDb(source.endAt),
          legacyEstimatedMinutes: source.estimatedMinutes,
        ),
        countableAverage: await _countableAverage(
          source.countableActivityId,
          nowUtc,
        ),
        chainSamples: await _chainSamples(source, nowUtc),
      );

      await (db.update(
        db.actionsTable,
      )..where((t) => t.id.equals(sourceId))).write(
        ActionsTableCompanion(
          name: Value(formatSequenceName(sequence, baseName)),
          sequenceNumber: Value(sequence),
          updatedAt: Value(nowText),
        ),
      );

      final newActionId = newId();
      await db
          .into(db.actionsTable)
          .insert(
            ActionsTableCompanion.insert(
              id: newActionId,
              name: formatSequenceName(sequence + 1, baseName),
              postponeFlex: Value(source.postponeFlex),
              depthLevel: Value(source.depthLevel),
              // Timed even when the source is all-day: it starts right now.
              startAt: Value(nowText),
              endAt: Value(dateTimeToDb(nowUtc.add(predicted))),
              estimatedMinutes: Value(source.estimatedMinutes),
              sequenceNumber: Value(sequence + 1),
              countableActivityId: Value(source.countableActivityId),
              // The whole description carries over as it is (ticks kept).
              notes: Value(source.notes),
              createdAt: nowText,
              updatedAt: nowText,
            ),
          );
      for (final metricId in metricIds) {
        await db
            .into(db.actionMetricsTable)
            .insert(
              ActionMetricsTableCompanion.insert(
                id: newId(),
                actionId: newActionId,
                metricId: metricId,
              ),
            );
      }
      await db
          .into(db.actionOccurrencesTable)
          .insert(
            ActionOccurrencesTableCompanion.insert(
              id: newId(),
              actionId: newActionId,
              startedAt: Value(nowText),
            ),
          );

      await (db.delete(
        db.actionDependenciesTable,
      )..where((t) => t.predecessorId.equals(sourceId))).go();
      await _insertEdge(sourceId, newActionId);
      for (final successorId in formerSuccessorIds) {
        await _insertEdge(newActionId, successorId);
      }

      return ContinueResult(
        newActionId: newActionId,
        undo: ContinueUndo(
          newActionId: newActionId,
          sourceBefore: source,
          formerSuccessorIds: formerSuccessorIds,
        ),
      );
    });
  }

  /// Takes back a [continueSameAction]: deletes the new action (and, in the
  /// same breath, every row hanging off it), puts the source's row back, and
  /// re-attaches the source to the next actions that were moved away.
  ///
  /// The source row is rewritten with an UPDATE rather than [restore]'s
  /// insert-or-replace: a REPLACE deletes the row first, which would cascade
  /// away the source's own dependency and metric rows.
  Future<void> undoContinue(ContinueUndo undo) {
    final sourceId = undo.sourceBefore.id;
    return db.transaction(() async {
      await (db.delete(db.actionDependenciesTable)..where(
            (t) =>
                t.predecessorId.equals(undo.newActionId) |
                t.successorId.equals(undo.newActionId),
          ))
          .go();
      await (db.delete(
        db.actionMetricsTable,
      )..where((t) => t.actionId.equals(undo.newActionId))).go();
      await (db.delete(
        db.actionOccurrencesTable,
      )..where((t) => t.actionId.equals(undo.newActionId))).go();
      await (db.delete(
        db.actionsTable,
      )..where((t) => t.id.equals(undo.newActionId))).go();

      await db.update(db.actionsTable).replace(undo.sourceBefore);
      for (final successorId in undo.formerSuccessorIds) {
        await _insertEdge(sourceId, successorId);
      }
    });
  }

  Future<void> _insertEdge(String predecessorId, String successorId) {
    return db
        .into(db.actionDependenciesTable)
        .insert(
          ActionDependenciesTableCompanion.insert(
            id: newId(),
            predecessorId: predecessorId,
            successorId: successorId,
          ),
        );
  }

  /// Mean actual duration of the activity's finished runs over the last
  /// [_countableAverageWindow], or null when it has none (or no activity).
  Future<Duration?> _countableAverage(
    String? activityId,
    DateTime nowUtc,
  ) async {
    if (activityId == null) return null;
    final cutoff = dateTimeToDb(nowUtc.subtract(_countableAverageWindow))!;
    final rows =
        await (db.select(db.actionsTable)..where(
              (t) =>
                  t.countableActivityId.equals(activityId) &
                  t.done.equals(true) &
                  t.completedAt.isBiggerOrEqualValue(cutoff) &
                  t.startAt.isNotNull() &
                  t.endAt.isNotNull(),
            ))
            .get();
    final durations = _actualDurations(rows);
    if (durations.isEmpty) return null;
    final totalMicros = durations.fold<int>(0, (s, d) => s + d.inMicroseconds);
    return Duration(microseconds: totalMicros ~/ durations.length);
  }

  /// Actual durations of the finished runs, over the last
  /// [_chainAverageWindow], of [source]'s chain (itself plus everything
  /// upstream of it) that carry the same normalized name.
  Future<List<Duration>> _chainSamples(
    ActionRow source,
    DateTime nowUtc,
  ) async {
    final cutoff = dateTimeToDb(nowUtc.subtract(_chainAverageWindow))!;
    final rows = await db
        .customSelect(
          '''
          WITH RECURSIVE chain(id) AS (
            SELECT ?
            UNION
            SELECT d.predecessor_id
            FROM action_dependencies d JOIN chain c ON d.successor_id = c.id
          )
          SELECT a.* FROM actions a JOIN chain c ON c.id = a.id
          WHERE a.done = 1 AND a.completed_at >= ?
            AND a.start_at IS NOT NULL AND a.end_at IS NOT NULL
          ''',
          variables: [Variable<String>(source.id), Variable<String>(cutoff)],
          readsFrom: {db.actionsTable, db.actionDependenciesTable},
        )
        .map((row) => db.actionsTable.map(row.data))
        .get();
    final key = normalizeForMatch(source.name);
    return _actualDurations(
      rows.where((r) => normalizeForMatch(r.name) == key),
    );
  }

  List<Duration> _actualDurations(Iterable<ActionRow> rows) {
    final durations = <Duration>[];
    for (final row in rows) {
      final start = dateTimeFromDb(row.startAt);
      final end = dateTimeFromDb(row.endAt);
      if (start == null || end == null || end.isBefore(start)) continue;
      durations.add(end.difference(start));
    }
    return durations;
  }

  /// Directly sets `start_at`/`end_at` — used by the quick "tap the time"
  /// editor and the calendar's drag/resize. If the action is running, its
  /// open occurrence's `started_at` follows the new `start_at` (same as
  /// Start/Finish keep them in sync), so history never drifts from the
  /// single source. A null [startAt] leaves the occurrence untouched.
  Future<void> updateSchedule(
    String actionId, {
    required DateTime? startAt,
    required DateTime? endAt,
  }) {
    final nowText = dateTimeToDb(DateTime.now())!;
    return db.transaction(() async {
      await (db.update(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).write(
        ActionsTableCompanion(
          startAt: Value(dateTimeToDb(startAt)),
          endAt: Value(dateTimeToDb(endAt)),
          updatedAt: Value(nowText),
        ),
      );
      if (startAt == null) return;
      await (db.update(db.actionOccurrencesTable)
            ..where((t) => t.actionId.equals(actionId) & t.finishedAt.isNull()))
          .write(
            ActionOccurrencesTableCompanion(
              startedAt: Value(dateTimeToDb(startAt)),
            ),
          );
    });
  }

  /// Applies a postpone rule: recomputes start/end, and logs a `postponed`
  /// occurrence so the history isn't lost (postponing just moves the same
  /// row's time, it doesn't create a new action row).
  ///
  /// If the action is currently running (an occurrence is open), postponing
  /// it ends that run — closing the occurrence with outcome `postponed` —
  /// rather than leaving it open with its `started_at` pushed into the
  /// future. Without this, the card/tile kept showing the action as
  /// "running" (highlighted icon, "Started HH:mm") even though postponing it
  /// means it isn't actually in progress at the new, later time.
  Future<void> postpone(String actionId, PostponeRule rule) async {
    final action = await (db.select(
      db.actionsTable,
    )..where((t) => t.id.equals(actionId))).getSingle();

    final current = ActionSchedule(
      startAt: dateTimeFromDb(action.startAt),
      endAt: dateTimeFromDb(action.endAt),
    );
    final next = applyPostponeRule(
      rule,
      current,
      nowUtc: DateTime.now().toUtc(),
    );
    final nowText = dateTimeToDb(DateTime.now())!;

    await db.transaction(() async {
      await (db.update(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).write(
        ActionsTableCompanion(
          startAt: Value(dateTimeToDb(next.startAt)),
          endAt: Value(dateTimeToDb(next.endAt)),
          updatedAt: Value(nowText),
        ),
      );

      final runningOccurrence =
          await (db.select(db.actionOccurrencesTable)..where(
                (t) => t.actionId.equals(actionId) & t.finishedAt.isNull(),
              ))
              .getSingleOrNull();
      if (runningOccurrence != null) {
        await (db.update(
          db.actionOccurrencesTable,
        )..where((t) => t.id.equals(runningOccurrence.id))).write(
          ActionOccurrencesTableCompanion(
            // Freezes whatever the single source (actions.start_at) said
            // right before this postpone, not whatever the occurrence's own
            // startedAt happened to still hold — those two can have drifted
            // apart if the schedule was quick-edited since Start was pressed.
            startedAt: Value(dateTimeToDb(current.startAt)),
            finishedAt: Value(nowText),
            outcome: const Value('postponed'),
          ),
        );
      }
    });
  }

  /// Instantiates a new action from a saved template's JSON payload, in one
  /// transaction. Payload shape: `{name, postponeFlex?,
  /// depthLevel?, estimatedMinutes?, isAllDay?, metricIds?}`.
  /// Snapshots [actionId]'s full row and occurrence history — see
  /// [ActionSnapshot] and [restore].
  Future<ActionSnapshot> snapshot(String actionId) async {
    final action = await (db.select(
      db.actionsTable,
    )..where((t) => t.id.equals(actionId))).getSingle();
    final occurrences = await (db.select(
      db.actionOccurrencesTable,
    )..where((t) => t.actionId.equals(actionId))).get();
    return ActionSnapshot(action: action, occurrences: occurrences);
  }

  /// Restores an action to exactly the state captured by [snapshot]: its
  /// occurrence history is replaced wholesale (Start/Finish/Postpone can
  /// each touch or add an occurrence, so a partial restore could leave a
  /// stray or half-reverted row) and its own row is overwritten
  /// field-for-field, including its original `updated_at`.
  Future<void> restore(ActionSnapshot snapshot) {
    return db.transaction(() async {
      await (db.delete(
        db.actionOccurrencesTable,
      )..where((t) => t.actionId.equals(snapshot.action.id))).go();
      for (final occurrence in snapshot.occurrences) {
        await db
            .into(db.actionOccurrencesTable)
            .insert(
              occurrence.toCompanion(false),
              mode: InsertMode.insertOrReplace,
            );
      }
      await db
          .into(db.actionsTable)
          .insert(
            snapshot.action.toCompanion(false),
            mode: InsertMode.insertOrReplace,
          );
    });
  }

  Future<String> createFromTemplate(String templateId) async {
    final template = await (db.select(
      db.actionTemplatesTable,
    )..where((t) => t.id.equals(templateId))).getSingle();
    final payload = jsonDecode(template.payload) as Map<String, dynamic>;

    return createAction(
      name: payload['name'] as String,
      postponeFlex: payload['postponeFlex'] as String? ?? 'flexible',
      depthLevel: payload['depthLevel'] as String?,
      isAllDay: payload['isAllDay'] as bool? ?? false,
      estimatedMinutes: payload['estimatedMinutes'] as int?,
      metricIds:
          (payload['metricIds'] as List<dynamic>?)?.cast<String>() ?? const [],
    );
  }
}
