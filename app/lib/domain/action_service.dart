import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/ids.dart';
import '../core/time_codec.dart';
import '../data/database.dart';
import 'postpone_rules.dart';

/// Create/edit/start/finish/postpone/cancel an action, and instantiate one
/// from a saved template.
class ActionService {
  final AppDatabase db;

  ActionService(this.db);

  Future<String> createAction({
    required String name,
    String kind = 'task',
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
              kind: Value(kind),
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
    required String kind,
    String? priority,
    required String postponeFlex,
    String? depthLevel,
    DateTime? startAt,
    DateTime? endAt,
    required bool isAllDay,
    int? estimatedMinutes,
  }) {
    final nowText = dateTimeToDb(DateTime.now())!;
    return (db.update(
      db.actionsTable,
    )..where((t) => t.id.equals(actionId))).write(
      ActionsTableCompanion(
        name: Value(name),
        kind: Value(kind),
        priority: Value(priority),
        postponeFlex: Value(postponeFlex),
        depthLevel: Value(depthLevel),
        startAt: Value(dateTimeToDb(startAt)),
        endAt: Value(dateTimeToDb(endAt)),
        isAllDay: Value(isAllDay),
        estimatedMinutes: Value(estimatedMinutes),
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
  /// duration (see [_predictedDuration]) is preserved onto the new start.
  /// Always reopens a done/cancelled action first — starting it means it's
  /// in progress, not finished — including when an occurrence is already
  /// running (an action can end up "done" while still running if it was
  /// finished and then started again from an old build; this self-heals
  /// that instead of getting stuck).
  Future<void> start(String actionId) async {
    final nowUtc = DateTime.now().toUtc();
    final nowText = dateTimeToDb(nowUtc)!;

    await db.transaction(() async {
      final action = await (db.select(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).getSingle();
      final duration = _predictedDuration(
        estimatedMinutes: action.estimatedMinutes,
        currentStart: dateTimeFromDb(action.startAt),
        currentEnd: dateTimeFromDb(action.endAt),
        kind: action.kind,
      );
      final newEnd = nowUtc.add(duration);

      await (db.update(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).write(
        ActionsTableCompanion(
          status: const Value('open'),
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

  /// Finishes the action, sets `end_at` to now, and marks tasks (but not
  /// habits/bad habits) done.
  ///
  /// `start_at` is kept as-is if it's already set and at/before now — the
  /// scheduled start already happened, so the elapsed time is genuine.
  /// Otherwise (empty, or still in the future — i.e. it was never actually
  /// started) finishing "now" means the whole thing just happened right
  /// now: `start_at` is set to `now - duration` (see [_predictedDuration]),
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
              _predictedDuration(
                estimatedMinutes: action.estimatedMinutes,
                currentStart: oldStart,
                currentEnd: dateTimeFromDb(action.endAt),
                kind: action.kind,
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
          status: action.kind == 'task' ? const Value('done') : const Value.absent(),
          completedAt: action.kind == 'task' ? Value(nowText) : const Value.absent(),
          startAt: Value(dateTimeToDb(newStart)),
          endAt: Value(nowText),
          updatedAt: Value(nowText),
        ),
      );
    });
  }

  /// Approximates the original "Predicted Time Consumption"/"Minutes
  /// Consuming" formulas, which our schema has no direct equivalent for (no
  /// Countable Activities or same-name-previous-action matching): prefer an
  /// explicit estimate, else the action's own existing start/end gap (even
  /// if that gap is zero — a deliberately point-in-time action stays that
  /// way rather than being padded out), else a default of 60 minutes (10
  /// for habits), matching the original formula's fallback exactly.
  Duration _predictedDuration({
    required int? estimatedMinutes,
    required DateTime? currentStart,
    required DateTime? currentEnd,
    required String kind,
  }) {
    if (estimatedMinutes != null && estimatedMinutes > 0) {
      return Duration(minutes: estimatedMinutes);
    }
    if (currentStart != null && currentEnd != null) {
      return currentEnd.difference(currentStart);
    }
    return kind == 'habit'
        ? const Duration(minutes: 10)
        : const Duration(minutes: 60);
  }

  /// Directly sets `start_at`/`end_at` without touching anything else — used
  /// by the quick "tap the time" editor on a Current Actions board card.
  Future<void> updateSchedule(
    String actionId, {
    required DateTime? startAt,
    required DateTime? endAt,
  }) {
    final nowText = dateTimeToDb(DateTime.now())!;
    return (db.update(
      db.actionsTable,
    )..where((t) => t.id.equals(actionId))).write(
      ActionsTableCompanion(
        startAt: Value(dateTimeToDb(startAt)),
        endAt: Value(dateTimeToDb(endAt)),
        updatedAt: Value(nowText),
      ),
    );
  }

  Future<void> cancel(String actionId) {
    final nowText = dateTimeToDb(DateTime.now())!;
    return (db.update(
      db.actionsTable,
    )..where((t) => t.id.equals(actionId))).write(
      ActionsTableCompanion(
        status: const Value('cancelled'),
        updatedAt: Value(nowText),
      ),
    );
  }

  /// Applies a postpone rule: recomputes start/end, and — for habits and bad
  /// habits — logs a `postponed` occurrence so the balance history isn't
  /// lost (postponing just moves the same row's time, it doesn't create a
  /// new one).
  ///
  /// If the action is currently running (an occurrence is open), that
  /// occurrence's `started_at` is moved to match the new start too. Without
  /// this, postponing a running action left `actions.start_at` (what the
  /// card shows) and the open occurrence's `started_at` (what the editor's
  /// "Currently running" line shows) pointing at two different times.
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
            startedAt: Value(dateTimeToDb(next.startAt)),
          ),
        );
      }

      if (action.kind == 'habit' || action.kind == 'bad_habit') {
        await db
            .into(db.actionOccurrencesTable)
            .insert(
              ActionOccurrencesTableCompanion.insert(
                id: newId(),
                actionId: actionId,
                outcome: const Value('postponed'),
              ),
            );
      }
    });
  }

  /// Instantiates a new action from a saved template's JSON payload, in one
  /// transaction. Payload shape: `{name, kind?, priority?, postponeFlex?,
  /// depthLevel?, estimatedMinutes?, isAllDay?, metricIds?}`.
  Future<String> createFromTemplate(String templateId) async {
    final template = await (db.select(
      db.actionTemplatesTable,
    )..where((t) => t.id.equals(templateId))).getSingle();
    final payload = jsonDecode(template.payload) as Map<String, dynamic>;

    return createAction(
      name: payload['name'] as String,
      kind: payload['kind'] as String? ?? 'task',
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
