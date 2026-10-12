import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/ids.dart';
import '../core/settings.dart';
import '../core/time_codec.dart';
import '../data/database.dart';
import 'duration_rules.dart';
import 'notes_plain_text.dart';
import 'postpone_rules.dart';
import 'work_hours.dart';
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

  /// Budget transactions that were linked to the action: they are detached on
  /// delete (their date frozen) and re-linked by undo.
  final List<BudgetTxDetach> budgetTxs;

  const DeleteUndo({
    required this.action,
    required this.occurrences,
    required this.metricLinks,
    required this.edges,
    this.budgetTxs = const [],
  });
}

/// A budget transaction's link state before its action was deleted.
class BudgetTxDetach {
  final String id;
  final String occurredAtBefore;

  const BudgetTxDetach({required this.id, required this.occurredAtBefore});
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

  /// The new all-day flag; null leaves the flag as it is. In the `before` list
  /// of a [MoveManyUndo] it always holds the flag's previous value, so Undo
  /// restores it.
  final bool? isAllDay;

  const ScheduleChange(
    this.id, {
    required this.startAt,
    required this.endAt,
    this.isAllDay,
  });
}

/// The `done`/`completed_at` values [ActionService.toggleDone] overwrote.
class ToggleDoneUndo {
  final String id;
  final bool done;
  final String? completedAt;
  final String updatedAt;

  const ToggleDoneUndo({
    required this.id,
    required this.done,
    required this.completedAt,
    required this.updatedAt,
  });
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

/// How far back finished same-name runs (anywhere, not just in the chain) count
/// toward [ActionService.predictedDurationFor].
const Duration _sameNameWindow = Duration(days: 30);

/// Create/edit/start/finish/postpone an action, continue it, and instantiate
/// one from a saved template.
class ActionService {
  final AppDatabase db;

  /// The current working hours (postpone "after work" / "morning"); defaults
  /// when not given.
  final WorkHours Function() _workHours;

  ActionService(this.db, {WorkHours Function()? workHours})
    : _workHours = workHours ?? (() => WorkHours.defaults);

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
              notesText: Value(notesPlainText(notes)),
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
        // Derived search text kept in step with the notes (absent = untouched).
        notesText: notes.present
            ? Value(notesPlainText(notes.value))
            : const Value.absent(),
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

      // Budget transactions keep existing without the action: unlink them and
      // freeze the date they currently show (the action's start, if any).
      final budgetTxs = <BudgetTxDetach>[];
      final linkedTxs = await (db.select(
        db.budgetTransactionsTable,
      )..where((t) => t.actionId.equals(actionId))).get();
      for (final tx in linkedTxs) {
        budgetTxs.add(
          BudgetTxDetach(id: tx.id, occurredAtBefore: tx.occurredAt),
        );
        await (db.update(
          db.budgetTransactionsTable,
        )..where((t) => t.id.equals(tx.id))).write(
          BudgetTransactionsTableCompanion(
            actionId: const Value(null),
            occurredAt: Value(action.startAt ?? tx.occurredAt),
          ),
        );
      }

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
        budgetTxs: budgetTxs,
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

      // Re-link budget transactions that still exist and are still detached.
      for (final d in undo.budgetTxs) {
        await (db.update(
          db.budgetTransactionsTable,
        )..where((t) => t.id.equals(d.id) & t.actionId.isNull())).write(
          BudgetTransactionsTableCompanion(
            actionId: Value(undo.action.id),
            occurredAt: Value(d.occurredAtBefore),
          ),
        );
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
            isAllDay: row.isAllDay,
          ),
        );
        await updateSchedule(c.id, startAt: c.startAt, endAt: c.endAt);
        if (c.isAllDay != null) await _setAllDayFlag(c.id, c.isAllDay!);
      }
      return MoveManyUndo(before);
    });
  }

  Future<void> undoMoveActions(MoveManyUndo undo) {
    return db.transaction(() async {
      for (final c in undo.before) {
        await updateSchedule(c.id, startAt: c.startAt, endAt: c.endAt);
        if (c.isAllDay != null) await _setAllDayFlag(c.id, c.isAllDay!);
      }
    });
  }

  Future<void> _setAllDayFlag(String id, bool isAllDay) {
    return (db.update(db.actionsTable)..where((t) => t.id.equals(id))).write(
      ActionsTableCompanion(isAllDay: Value(isAllDay)),
    );
  }

  /// How long a new run of [actionId] should take: its Countable Activity's
  /// 30-day average, else the average of finished same-name runs (matched with
  /// [normalizeForMatch]) over the last 30 days, else its own duration - which
  /// for an all-day item (no real length) is [defaultActionDuration] (1 hour).
  /// Reads a lean column list (no notes).
  Future<Duration> predictedDurationFor(String actionId) async {
    final nowUtc = DateTime.now().toUtc();
    final row = await db
        .customSelect(
          'SELECT name, start_at, end_at, is_all_day, estimated_minutes, '
          'countable_activity_id FROM actions WHERE id = ?',
          variables: [Variable<String>(actionId)],
          readsFrom: {db.actionsTable},
        )
        .getSingle();
    final name = row.read<String>('name');
    final isAllDay = row.read<bool>('is_all_day');
    final own = isAllDay
        ? defaultActionDuration
        : computeActionDuration(
            startAt: dateTimeFromDb(row.readNullable<String>('start_at')),
            endAt: dateTimeFromDb(row.readNullable<String>('end_at')),
            legacyEstimatedMinutes: row.readNullable<int>('estimated_minutes'),
          );

    final cutoff = dateTimeToDb(nowUtc.subtract(_sameNameWindow))!;
    final runs = await db
        .customSelect(
          'SELECT name, start_at, end_at FROM actions '
          'WHERE done = 1 AND completed_at >= ? AND id <> ? '
          'AND is_all_day = 0 AND start_at IS NOT NULL '
          'AND end_at IS NOT NULL',
          variables: [Variable<String>(cutoff), Variable<String>(actionId)],
          readsFrom: {db.actionsTable},
        )
        .get();
    final key = normalizeForMatch(name);
    final samples = <Duration>[];
    for (final r in runs) {
      if (normalizeForMatch(r.read<String>('name')) != key) continue;
      final start = dateTimeFromDb(r.read<String>('start_at'));
      final end = dateTimeFromDb(r.read<String>('end_at'));
      if (start == null || end == null || end.isBefore(start)) continue;
      samples.add(end.difference(start));
    }

    return predictedDuration(
      ownDuration: own,
      countableAverage: await _countableAverage(
        row.readNullable<String>('countable_activity_id'),
        nowUtc,
      ),
      chainSamples: samples,
    );
  }

  /// Turns an all-day action into a timed one starting at [start] for its
  /// predicted duration ([predictedDurationFor]), in one transaction. Undo
  /// with [undoMoveActions].
  Future<MoveManyUndo> scheduleAllDayAt(String id, DateTime start) {
    return db.transaction(() async {
      final predicted = await predictedDurationFor(id);
      final startUtc = start.toUtc();
      return moveActions([
        ScheduleChange(
          id,
          startAt: startUtc,
          endAt: startUtc.add(predicted),
          isAllDay: false,
        ),
      ]);
    });
  }

  /// Turns an action into an all-day one on [day] (its year/month/day read as
  /// Istanbul wall-clock): `start_at` is that day's local midnight, `end_at`
  /// null. Undo with [undoMoveActions].
  Future<MoveManyUndo> makeAllDay(String id, DateTime day) {
    final midnight = tz.TZDateTime(_location(), day.year, day.month, day.day);
    return moveActions([
      ScheduleChange(
        id,
        startAt: midnight.toUtc(),
        endAt: null,
        isAllDay: true,
      ),
    ]);
  }

  tz.Location _location() {
    try {
      return tz.getLocation(AppSettings.timeZoneName);
    } on tz.LocationNotFoundException {
      initPostponeTimeZoneData();
      return tz.getLocation(AppSettings.timeZoneName);
    }
  }

  /// Flips the manual `done` flag (and `completed_at`) only; the schedule and
  /// occurrence history stay as they are. Undo with [undoToggleDone].
  Future<ToggleDoneUndo> toggleDone(String id) {
    final nowText = dateTimeToDb(DateTime.now())!;
    return db.transaction(() async {
      final row = await (db.select(
        db.actionsTable,
      )..where((t) => t.id.equals(id))).getSingle();
      final done = !row.done;
      await (db.update(db.actionsTable)..where((t) => t.id.equals(id))).write(
        ActionsTableCompanion(
          done: Value(done),
          completedAt: Value(done ? nowText : null),
          updatedAt: Value(nowText),
        ),
      );
      return ToggleDoneUndo(
        id: id,
        done: row.done,
        completedAt: row.completedAt,
        updatedAt: row.updatedAt,
      );
    });
  }

  Future<void> undoToggleDone(ToggleDoneUndo undo) {
    return (db.update(
      db.actionsTable,
    )..where((t) => t.id.equals(undo.id))).write(
      ActionsTableCompanion(
        done: Value(undo.done),
        completedAt: Value(undo.completedAt),
        updatedAt: Value(undo.updatedAt),
      ),
    );
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

  /// The id of the Countable Activity named [name] (case-insensitive),
  /// creating it when none exists. Lets a template act as an activity.
  Future<String> countableActivityForTemplate(String name) async {
    final wanted = name.trim().toLowerCase();
    final all = await db.select(db.countableActivitiesTable).get();
    for (final a in all) {
      if (a.name.trim().toLowerCase() == wanted) return a.id;
    }
    return createCountableActivity(name.trim());
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
      // An all-day action has no real length: use the predicted one and move
      // it onto the timeline (it stops being all-day).
      final duration = action.isAllDay
          ? await predictedDurationFor(actionId)
          : computeActionDuration(
              startAt: dateTimeFromDb(action.startAt),
              endAt: dateTimeFromDb(action.endAt),
              legacyEstimatedMinutes: action.estimatedMinutes,
            );
      final newEnd = nowUtc.add(duration);

      await (db.update(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).write(
        ActionsTableCompanion(
          isAllDay: const Value(false),
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
      // The name is the truth: a removed `[#n]` restarts the count at 1, an
      // edited one is honoured (the stored counter is only rewritten below).
      final sequence = prefixNumber ?? 1;

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
              notesText: Value(source.notesText),
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

  /// Mean real duration of the finished runs of a template over the last
  /// [_countableAverageWindow]: actions of the Countable Activity named like it
  /// (that covers "Continue" copies and actions added to the activity) plus any
  /// finished action with the same normalized name (what the template created).
  /// Null when there is none.
  Future<Duration?> templateAverage(String name, {DateTime? nowUtc}) async {
    final now = nowUtc ?? DateTime.now().toUtc();
    final wanted = name.trim().toLowerCase();
    String? activityId;
    for (final c in await db.select(db.countableActivitiesTable).get()) {
      if (c.name.trim().toLowerCase() == wanted) {
        activityId = c.id;
        break;
      }
    }
    final key = normalizeForMatch(name);
    final cutoff = dateTimeToDb(now.subtract(_countableAverageWindow))!;
    final rows =
        await (db.select(db.actionsTable)..where(
              (t) =>
                  t.done.equals(true) &
                  t.completedAt.isBiggerOrEqualValue(cutoff) &
                  t.startAt.isNotNull() &
                  t.endAt.isNotNull(),
            ))
            .get();
    final durations = _actualDurations(
      rows.where(
        (r) =>
            (activityId != null && r.countableActivityId == activityId) ||
            normalizeForMatch(r.name) == key,
      ),
    );
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
      hours: _workHours(),
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
    final payload = await _templatePayload(templateId);
    final a = await _templateArgs(payload);
    final id = await createAction(
      name: a.name,
      postponeFlex: a.postponeFlex,
      depthLevel: a.depthLevel,
      isAllDay: a.isAllDay,
      estimatedMinutes: a.estimatedMinutes,
      notes: a.notes,
      metricIds: a.metricIds,
    );
    await _applyTemplateBlocks(id, payload);
    return id;
  }

  /// Copies the template's "What is done?" Blocks codes (payload
  /// `diaryBlocks`) onto the new action (`result_note` holds them).
  Future<void> _applyTemplateBlocks(
    String actionId,
    Map<String, dynamic> payload,
  ) async {
    final blocks = (payload['diaryBlocks'] as String?)?.trim();
    if (blocks == null || blocks.isEmpty) return;
    await (db.update(db.actionsTable)..where((t) => t.id.equals(actionId)))
        .write(ActionsTableCompanion(resultNote: Value(blocks)));
  }

  /// Quick "Start now" from a template. Timed: runs from now for the
  /// template's duration, with an open occurrence (like [start]). All-day:
  /// an all-day action for today, not done. Returns the new action's id.
  Future<String> createFromTemplateStarted(String templateId) =>
      _createFromTemplateNow(templateId, finished: false);

  /// Quick "Finish now" from a template. Timed: ran for the duration up to
  /// now, done, with a closed occurrence (like [finish]). All-day: an all-day
  /// action for today, done (like [toggleDone]). Returns the new action's id.
  Future<String> createFromTemplateFinished(String templateId) =>
      _createFromTemplateNow(templateId, finished: true);

  Future<String> _createFromTemplateNow(
    String templateId, {
    required bool finished,
  }) async {
    final nowUtc = DateTime.now().toUtc();
    final nowText = dateTimeToDb(nowUtc)!;
    final payload = await _templatePayload(templateId);
    final a = await _templateArgs(payload);

    // Read-only: a template must not create a countable activity by itself.
    final wanted = a.name.trim().toLowerCase();
    String? activityId;
    for (final c in await db.select(db.countableActivitiesTable).get()) {
      if (c.name.trim().toLowerCase() == wanted) {
        activityId = c.id;
        break;
      }
    }

    return db.transaction(() async {
      final DateTime? startAt;
      final DateTime? endAt;
      var occStart = nowUtc;
      if (a.isAllDay) {
        final today = tz.TZDateTime.now(_location());
        startAt = tz.TZDateTime(
          _location(),
          today.year,
          today.month,
          today.day,
        ).toUtc();
        endAt = null;
      } else {
        final minutes = a.estimatedMinutes;
        final manual = (minutes != null && minutes > 0)
            ? Duration(minutes: minutes)
            : null;
        final average = await templateAverage(a.name, nowUtc: nowUtc);
        // The template's switch picks which one wins; the other is the
        // fallback.
        final useAverage = payload['useAverage'] == true;
        final duration = useAverage
            ? (average ?? manual ?? defaultActionDuration)
            : (manual ?? average ?? defaultActionDuration);
        if (finished) {
          occStart = nowUtc.subtract(duration);
          startAt = occStart;
          endAt = nowUtc;
        } else {
          startAt = nowUtc;
          endAt = nowUtc.add(duration);
        }
      }

      final id = await createAction(
        name: a.name,
        postponeFlex: a.postponeFlex,
        depthLevel: a.depthLevel,
        startAt: startAt,
        endAt: endAt,
        isAllDay: a.isAllDay,
        estimatedMinutes: a.estimatedMinutes,
        countableActivityId: activityId,
        notes: a.notes,
        metricIds: a.metricIds,
      );
      await _applyTemplateBlocks(id, payload);

      if (finished) {
        await (db.update(db.actionsTable)..where((t) => t.id.equals(id))).write(
          ActionsTableCompanion(
            done: const Value(true),
            completedAt: Value(nowText),
          ),
        );
      }
      if (finished || !a.isAllDay) {
        await db
            .into(db.actionOccurrencesTable)
            .insert(
              ActionOccurrencesTableCompanion.insert(
                id: newId(),
                actionId: id,
                startedAt: Value(dateTimeToDb(occStart)),
                finishedAt: finished ? Value(nowText) : const Value.absent(),
                outcome: finished ? const Value('done') : const Value.absent(),
              ),
            );
      }
      return id;
    });
  }

  Future<Map<String, dynamic>> _templatePayload(String templateId) async {
    final template = await (db.select(
      db.actionTemplatesTable,
    )..where((t) => t.id.equals(templateId))).getSingle();
    return jsonDecode(template.payload) as Map<String, dynamic>;
  }

  /// The createAction arguments a template payload describes. Directions
  /// deleted since the template was saved are filtered out (FK safety).
  Future<
    ({
      String name,
      String postponeFlex,
      String? depthLevel,
      bool isAllDay,
      int? estimatedMinutes,
      String? notes,
      List<String> metricIds,
    })
  >
  _templateArgs(Map<String, dynamic> payload) async {
    final existingMetricIds = (await db.select(db.metricsTable).get())
        .map((m) => m.id)
        .toSet();
    final metricIds =
        ((payload['metricIds'] as List<dynamic>?)?.cast<String>() ??
                const <String>[])
            .where(existingMetricIds.contains)
            .toList();
    return (
      name: payload['name'] as String,
      postponeFlex: payload['postponeFlex'] as String? ?? 'flexible',
      depthLevel: payload['depthLevel'] as String?,
      isAllDay: payload['isAllDay'] as bool? ?? false,
      estimatedMinutes: payload['estimatedMinutes'] as int?,
      notes: payload['notes'] as String?,
      metricIds: metricIds,
    );
  }
}
