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

  /// Starts (or resumes) timing an action: opens a new occurrence unless one
  /// is already running, and sets `start_at` to now — that field is the one
  /// place the UI shows/lets you postpone "the current time of this task",
  /// so it needs to track reality once you've actually started, not just
  /// whatever was scheduled beforehand. Any existing start/end duration is
  /// preserved onto the new start. Always reopens a done/cancelled action
  /// first — starting it means it's in progress, not finished — including
  /// when it's a no-op because an occurrence is already running (an action
  /// can end up "done" while still running if it was finished and then
  /// started again from an old build; this self-heals that instead of
  /// getting stuck).
  Future<void> start(String actionId) async {
    final nowText = dateTimeToDb(DateTime.now())!;

    await db.transaction(() async {
      await (db.update(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).write(
        ActionsTableCompanion(
          status: const Value('open'),
          completedAt: const Value(null),
          updatedAt: Value(nowText),
        ),
      );

      final alreadyRunning =
          await (db.select(db.actionOccurrencesTable)..where(
                (t) => t.actionId.equals(actionId) & t.finishedAt.isNull(),
              ))
              .getSingleOrNull();
      if (alreadyRunning != null) return;

      final action = await (db.select(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).getSingle();
      final oldStart = dateTimeFromDb(action.startAt);
      final oldEnd = dateTimeFromDb(action.endAt);
      final duration = (oldStart != null && oldEnd != null)
          ? oldEnd.difference(oldStart)
          : null;
      final newStart = DateTime.now().toUtc();
      final newEnd = duration == null ? null : newStart.add(duration);

      await (db.update(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).write(
        ActionsTableCompanion(
          startAt: Value(dateTimeToDb(newStart)),
          endAt: Value(dateTimeToDb(newEnd)),
        ),
      );

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

  /// Finishes the action's running occurrence, if any, sets `end_at` to now
  /// (same reasoning as `start_at` in [start]), and marks tasks (but not
  /// habits/bad habits) done.
  Future<void> finish(String actionId) async {
    final nowText = dateTimeToDb(DateTime.now())!;

    await db.transaction(() async {
      await (db.update(db.actionOccurrencesTable)..where(
            (t) => t.actionId.equals(actionId) & t.finishedAt.isNull(),
          ))
          .write(
            ActionOccurrencesTableCompanion(
              finishedAt: Value(nowText),
              outcome: const Value('done'),
            ),
          );

      final action = await (db.select(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).getSingle();

      await (db.update(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).write(
        ActionsTableCompanion(
          status: action.kind == 'task' ? const Value('done') : const Value.absent(),
          completedAt: action.kind == 'task' ? Value(nowText) : const Value.absent(),
          endAt: Value(nowText),
          updatedAt: Value(nowText),
        ),
      );
    });
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
