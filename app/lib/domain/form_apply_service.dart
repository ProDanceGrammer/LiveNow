import 'package:drift/drift.dart';

import '../data/database.dart';
import 'action_service.dart';
import 'bulk_edit_service.dart';
import 'form_effects.dart';

/// What applying a form changed, for Undo as ONE step.
class FormApplyUndo {
  const FormApplyUndo({required this.metrics, required this.activities});

  final BulkMetricsUndo metrics;
  final BulkActivityUndo activities;

  bool get isEmpty => metrics.before.isEmpty && activities.before.isEmpty;
}

/// The outcome shown to the owner.
class FormApplyResult {
  const FormApplyResult({
    required this.undo,
    required this.actionsChanged,
    required this.directionsAdded,
    required this.directionsSkipped,
    required this.activitiesSet,
  });

  final FormApplyUndo undo;

  /// Actions that really changed (directions and / or activity).
  final int actionsChanged;

  /// New direction links written (an action that already had a direction does
  /// not count it again).
  final int directionsAdded;

  /// Directions the form names that no longer exist (not applied).
  final int directionsSkipped;

  /// Actions that got the Countable Activity.
  final int activitiesSet;

  bool get changedAnything => !undo.isEmpty;
}

/// Applies the [FormEffects] of a filled form to several actions: ONLY ADDS
/// (directions are added to what each action has; the Countable Activity is set
/// only where there is none). One transaction, one Undo.
class FormApplyService {
  FormApplyService(this.db)
    : _bulk = BulkEditService(db),
      _actions = ActionService(db);

  final AppDatabase db;
  final BulkEditService _bulk;
  final ActionService _actions;

  Future<FormApplyResult> apply(
    Iterable<String> actionIds,
    FormEffects effects,
  ) => db.transaction(() async {
    final ids = actionIds.toSet();

    // A direction deleted since the form was made (here or on another device)
    // must not break the whole apply (a link to it would violate its foreign key).
    final existing = {
      for (final r in await db.select(db.metricsTable).get()) r.id,
    };
    final keep = [
      for (final id in effects.metricIds)
        if (existing.contains(id)) id,
    ];
    final skipped = effects.metricIds.length - keep.length;

    final metricsUndo = await _bulk.setMetricsMany(ids, keep, BulkMode.add);
    var added = 0;
    for (final before in metricsUndo.before.values) {
      added += keep.toSet().difference(before.toSet()).length;
    }

    var activitiesUndo = const BulkActivityUndo({});
    final name = effects.activityName?.trim();
    if (name != null && name.isNotEmpty) {
      // Create the activity only when some action can really take it.
      final free = await (db.select(db.actionsTable)
            ..where((t) => t.id.isIn(ids) & t.countableActivityId.isNull()))
          .get();
      if (free.isNotEmpty) {
        final activityId = await _actions.countableActivityForTemplate(name);
        activitiesUndo = await _bulk.setActivityIfEmptyMany(ids, activityId);
      }
    }

    final changed = {
      ...metricsUndo.before.keys,
      ...activitiesUndo.before.keys,
    };
    return FormApplyResult(
      undo: FormApplyUndo(metrics: metricsUndo, activities: activitiesUndo),
      actionsChanged: changed.length,
      directionsAdded: added,
      directionsSkipped: skipped,
      activitiesSet: activitiesUndo.before.length,
    );
  });

  /// Puts everything back as ONE step.
  Future<void> undo(FormApplyUndo undo) => db.transaction(() async {
    await _bulk.undoSetMetricsMany(undo.metrics);
    await _bulk.undoSetActivityMany(undo.activities);
  });
}
