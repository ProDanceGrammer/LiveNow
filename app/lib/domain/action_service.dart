import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/ids.dart';
import '../core/time_codec.dart';
import '../data/database.dart';
import 'duration_rules.dart';
import 'postpone_rules.dart';

/// A full copy of one action's row and its entire occurrence history, taken
/// just before a quick-action button changes it — lets [ActionService.restore]
/// put everything back exactly as it was (the Undo feature).
class ActionSnapshot {
  final ActionRow action;
  final List<ActionOccurrence> occurrences;

  const ActionSnapshot({required this.action, required this.occurrences});
}

/// Create/edit/start/finish/postpone an action, and instantiate one from a
/// saved template.
class ActionService {
  final AppDatabase db;

  ActionService(this.db);

  Future<String> createAction({
    required String name,
    String? priority,
    String postponeFlex = 'flexible',
    String? depthLevel,
    DateTime? startAt,
    DateTime? endAt,
    bool isAllDay = false,
    int? estimatedMinutes,
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
              priority: Value(priority),
              postponeFlex: Value(postponeFlex),
              depthLevel: Value(depthLevel),
              startAt: Value(dateTimeToDb(startAt)),
              endAt: Value(dateTimeToDb(endAt)),
              isAllDay: Value(isAllDay),
              estimatedMinutes: Value(estimatedMinutes),
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
    String? priority,
    required String postponeFlex,
    String? depthLevel,
    DateTime? startAt,
    DateTime? endAt,
    required bool isAllDay,
  }) {
    final nowText = dateTimeToDb(DateTime.now())!;
    return (db.update(
      db.actionsTable,
    )..where((t) => t.id.equals(actionId))).write(
      ActionsTableCompanion(
        name: Value(name),
        priority: Value(priority),
        postponeFlex: Value(postponeFlex),
        depthLevel: Value(depthLevel),
        startAt: Value(dateTimeToDb(startAt)),
        endAt: Value(dateTimeToDb(endAt)),
        isAllDay: Value(isAllDay),
        updatedAt: Value(nowText),
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
        await (db.update(
          db.actionOccurrencesTable,
        )..where((t) => t.id.equals(runningOccurrence.id))).write(
          ActionOccurrencesTableCompanion(startedAt: Value(nowText)),
        );
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
      await (db.update(db.actionOccurrencesTable)..where(
            (t) => t.actionId.equals(actionId) & t.finishedAt.isNull(),
          ))
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
  /// transaction. Payload shape: `{name, priority?, postponeFlex?,
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
      priority: payload['priority'] as String?,
      postponeFlex: payload['postponeFlex'] as String? ?? 'flexible',
      depthLevel: payload['depthLevel'] as String?,
      isAllDay: payload['isAllDay'] as bool? ?? false,
      estimatedMinutes: payload['estimatedMinutes'] as int?,
      metricIds:
          (payload['metricIds'] as List<dynamic>?)?.cast<String>() ??
          const [],
    );
  }
}
