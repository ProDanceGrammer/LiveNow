import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart'
    show StateController, StateProvider;

import '../domain/action_service.dart' show ScheduleChange;
import '../domain/growth_rules.dart' show metricLabel;
import 'providers.dart';
import 'widgets/app_toast.dart';

class _UndoEntry {
  /// Puts back whatever the quick-action changed.
  final Future<void> Function() revert;
  const _UndoEntry(this.revert);
}

/// The most recent undoable quick-action, while its ~5-second window (the
/// same window as the toast offering it) is still open. Both the
/// toast's "Undo" button and the global Ctrl+Z shortcut just run this
/// entry's revert; either one clears it afterward.
final lastUndoProvider = StateProvider<Object?>((ref) => null);

/// Wraps a quick-action call (Start/Finish/Postpone/...) so it can be
/// undone: snapshots the action's full row + occurrence history first, runs
/// the operation, then offers a Notion-style "Undo" toast for 5 seconds
/// (and arms Ctrl+Z for the same window).
Future<void> runUndoable(
  BuildContext context,
  WidgetRef ref,
  String actionId,
  String description,
  Future<void> Function() operation,
) async {
  final service = ref.read(actionServiceProvider);
  // Everything that needs `ref`/`context` is looked up before the operation
  // runs: some operations (e.g. Finish, which can drop a task off a view that
  // only shows open items, or Delete) remove this action's card from the
  // list it's currently shown in, which can unmount this widget by the time
  // the write finishes — and using `ref` after that throws. The
  // root OverlayState belongs to the root navigator and the notifier lives in
  // the ProviderScope, so both stay valid.
  final overlay = rootOverlayOf(context);
  final lastUndo = ref.read(lastUndoProvider.notifier);
  final snapshot = await service.snapshot(actionId);
  await operation();
  _offerUndo(overlay, lastUndo, description, () => service.restore(snapshot));
}

/// "Continue with Same Action", undoable like the other quick actions. It
/// can't go through [runUndoable]: that snapshots a single action, while a
/// continue also creates an action and rewires other actions' edges.
Future<void> runUndoableContinue(
  BuildContext context,
  WidgetRef ref,
  String sourceId,
) async {
  final service = ref.read(actionServiceProvider);
  final overlay = rootOverlayOf(context);
  final lastUndo = ref.read(lastUndoProvider.notifier);
  final result = await service.continueSameAction(sourceId);
  _offerUndo(
    overlay,
    lastUndo,
    'Continued as a new action',
    () => service.undoContinue(result.undo),
  );
}

/// Deletes an action right away and offers Undo (no confirmation dialog —
/// the Undo toast is the safety net). Like [runUndoableContinue], it
/// can't use [runUndoable]: the snapshot must also cover the action's links.
Future<void> runUndoableDelete(
  BuildContext context,
  WidgetRef ref,
  String actionId,
) async {
  final service = ref.read(actionServiceProvider);
  // Looked up before deleting: the card/block this context belongs to
  // disappears with the action, after which `ref` can't be used.
  final overlay = rootOverlayOf(context);
  final lastUndo = ref.read(lastUndoProvider.notifier);
  final selected = ref.read(calendarSelectedActionProvider.notifier);

  final undo = await service.deleteAction(actionId);
  if (selected.state == actionId) selected.state = null;
  _offerUndo(
    overlay,
    lastUndo,
    'Deleted "${undo.action.name}"',
    () => service.undoDelete(undo),
  );
}

/// Deletes SEVERAL actions at once (one transaction) and offers ONE Undo that
/// brings all of them back, links included. Like [runUndoableDelete] nothing
/// needing `ref`/`context` is touched after the first await. Clears the
/// calendar's single selection if it was among them; a caller that keeps its
/// own selection set must clear it itself (before or after this call).
Future<void> runUndoableDeleteMany(
  BuildContext context,
  WidgetRef ref,
  Iterable<String> actionIds,
) async {
  final ids = actionIds.toList();
  if (ids.isEmpty) return;
  final service = ref.read(actionServiceProvider);
  final overlay = rootOverlayOf(context);
  final lastUndo = ref.read(lastUndoProvider.notifier);
  final selected = ref.read(calendarSelectedActionProvider.notifier);

  final undo = await service.deleteActions(ids);
  if (undo.count == 0) return;
  if (ids.contains(selected.state)) selected.state = null;
  _offerUndo(
    overlay,
    lastUndo,
    undo.count == 1
        ? 'Deleted "${undo.parts.first.action.name}"'
        : 'Deleted ${undo.count} actions',
    () => service.undoDeleteMany(undo),
  );
}

/// Moves SEVERAL actions at once (one transaction) and offers ONE Undo that
/// puts all their schedules back. [description] defaults to "Moved N events".
Future<void> runUndoableMoveMany(
  BuildContext context,
  WidgetRef ref,
  Iterable<ScheduleChange> changes, {
  String? description,
}) async {
  final list = changes.toList();
  if (list.isEmpty) return;
  final service = ref.read(actionServiceProvider);
  final overlay = rootOverlayOf(context);
  final lastUndo = ref.read(lastUndoProvider.notifier);

  final undo = await service.moveActions(list);
  if (undo.before.isEmpty) return;
  _offerUndo(
    overlay,
    lastUndo,
    description ??
        (undo.before.length == 1
            ? 'Moved'
            : 'Moved ${undo.before.length} events'),
    () => service.undoMoveActions(undo),
  );
}

/// Ticks/unticks an action (`done` only, schedule untouched) and offers Undo.
/// Nothing needing `ref`/`context` is touched after the first await.
Future<void> runUndoableToggleDone(
  BuildContext context,
  WidgetRef ref,
  String actionId,
) async {
  final service = ref.read(actionServiceProvider);
  final overlay = rootOverlayOf(context);
  final lastUndo = ref.read(lastUndoProvider.notifier);

  final undo = await service.toggleDone(actionId);
  _offerUndo(
    overlay,
    lastUndo,
    undo.done ? 'Marked not done' : 'Marked done',
    () => service.undoToggleDone(undo),
  );
}

/// Drops an all-day action into the time grid at [start] (predicted duration)
/// and offers Undo, which also restores the all-day flag.
Future<void> runUndoableScheduleAllDayAt(
  BuildContext context,
  WidgetRef ref,
  String actionId,
  DateTime start,
) async {
  final service = ref.read(actionServiceProvider);
  final overlay = rootOverlayOf(context);
  final lastUndo = ref.read(lastUndoProvider.notifier);

  final undo = await service.scheduleAllDayAt(actionId, start);
  _offerUndo(
    overlay,
    lastUndo,
    'Scheduled',
    () => service.undoMoveActions(undo),
  );
}

/// Turns an action into an all-day one on [day] and offers Undo, which puts
/// the old times and the all-day flag back.
Future<void> runUndoableMakeAllDay(
  BuildContext context,
  WidgetRef ref,
  String actionId,
  DateTime day,
) async {
  final service = ref.read(actionServiceProvider);
  final overlay = rootOverlayOf(context);
  final lastUndo = ref.read(lastUndoProvider.notifier);

  final undo = await service.makeAllDay(actionId, day);
  _offerUndo(
    overlay,
    lastUndo,
    'Made all-day',
    () => service.undoMoveActions(undo),
  );
}

/// Deletes a growth direction right away and offers Undo (same approach as
/// [runUndoableDelete]: nothing needing `ref`/`context` is touched after the
/// first await, since the screen showing the direction may be gone by then).
Future<void> runUndoableDeleteMetric(
  BuildContext context,
  WidgetRef ref,
  String metricId,
) async {
  final service = ref.read(metricServiceProvider);
  final overlay = rootOverlayOf(context);
  final lastUndo = ref.read(lastUndoProvider.notifier);

  final undo = await service.deleteMetric(metricId);
  _offerUndo(
    overlay,
    lastUndo,
    'Deleted "${metricLabel(undo.metric.name, undo.metric.icon)}"',
    () => service.undoDelete(undo),
  );
}

/// Removes the relation "[fromId] leads to [toId]" (a Mindmap edge) and offers
/// Undo, which adds it back. Reads `ref`/`context` before the first await.
Future<void> runUndoableRemoveRelation(
  BuildContext context,
  WidgetRef ref, {
  required String fromId,
  required String toId,
  required String description,
}) async {
  final service = ref.read(metricServiceProvider);
  final overlay = rootOverlayOf(context);
  final lastUndo = ref.read(lastUndoProvider.notifier);

  await service.removeRelation(fromId: fromId, toId: toId);
  _offerUndo(
    overlay,
    lastUndo,
    description,
    () => service.addRelation(fromId: fromId, toId: toId),
  );
}

/// Runs a Mindmap layout ([apply]) and offers Undo, which writes [previous]
/// (the positions as stored before, nulls included) back. [afterUndo] lets the
/// view refit itself; it may run after the view is gone, so it must check.
Future<void> runUndoableLayout(
  BuildContext context,
  WidgetRef ref, {
  required String description,
  required Future<void> Function() apply,
  required Map<String, (double?, double?)> previous,
  VoidCallback? afterUndo,
}) async {
  final service = ref.read(metricServiceProvider);
  final overlay = rootOverlayOf(context);
  final lastUndo = ref.read(lastUndoProvider.notifier);

  await apply();
  _offerUndo(overlay, lastUndo, description, () async {
    await service.restorePositions(previous);
    afterUndo?.call();
  });
}

void _offerUndo(
  OverlayState overlay,
  StateController<Object?> lastUndo,
  String description,
  Future<void> Function() revert,
) {
  final entry = _UndoEntry(revert);
  lastUndo.state = entry;

  // Shown in the root overlay (above dialogs, still clickable). A new toast
  // replaces the previous one: only this entry is actually undoable.
  showUndoToast(
    overlay,
    description,
    onUndo: () => _undoLast(lastUndo),
    onClosed: () {
      try {
        if (identical(lastUndo.state, entry)) lastUndo.state = null;
      } catch (_) {
        // The provider container is already gone.
      }
    },
  );
}

/// Reverts the most recent undoable quick-action, if its window hasn't
/// closed yet. Used by the global Ctrl+Z shortcut; the toast's "Undo"
/// button does the same through [_undoLast].
Future<void> performUndo(WidgetRef ref) =>
    _undoLast(ref.read(lastUndoProvider.notifier));

Future<void> _undoLast(StateController<Object?> lastUndo) async {
  final entry = lastUndo.state;
  if (entry is! _UndoEntry) return;
  lastUndo.state = null;
  await entry.revert();
}
