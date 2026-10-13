import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart'
    show StateController, StateProvider;

import '../domain/action_service.dart' show ScheduleChange;
import '../domain/bulk_edit_service.dart';
import '../domain/growth_rules.dart' show metricLabel;
import 'providers.dart';
import 'widgets/app_toast.dart';

/// One undoable operation: what it was called, how to take it back, and the
/// overlay to confirm in.
class UndoEntry {
  final String description;

  /// Puts back whatever the operation changed.
  final Future<void> Function() revert;
  final OverlayState? _overlay;

  const UndoEntry(this.description, this.revert, [this._overlay]);
}

/// How many undoable operations are remembered.
const kUndoHistoryLimit = 10;

/// The undo history, oldest first (at most [kUndoHistoryLimit], kept in memory
/// only: it starts empty at every launch). Ctrl+Z takes back the newest entry,
/// again and again; the toast's "Undo" button takes back the entry the toast
/// was shown for (the newest at that moment) and goes away with it.
final undoHistoryProvider = StateProvider<List<UndoEntry>>((ref) => const []);

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
  final lastUndo = ref.read(undoHistoryProvider.notifier);
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
  final lastUndo = ref.read(undoHistoryProvider.notifier);
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
  final lastUndo = ref.read(undoHistoryProvider.notifier);
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
  final lastUndo = ref.read(undoHistoryProvider.notifier);
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
  final lastUndo = ref.read(undoHistoryProvider.notifier);

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

/// The same growth directions for SEVERAL actions ([mode]: add / remove /
/// replace), one transaction and ONE Undo that restores every action's own
/// directions. Nothing needing `ref`/`context` is touched after the first
/// await (the list re-sorts and tiles unmount).
Future<void> runUndoableSetMetricsMany(
  BuildContext context,
  WidgetRef ref,
  Iterable<String> actionIds,
  List<String> metricIds,
  BulkMode mode,
) async {
  final ids = actionIds.toList();
  if (ids.isEmpty) return;
  final service = ref.read(bulkEditServiceProvider);
  final overlay = rootOverlayOf(context);
  final lastUndo = ref.read(undoHistoryProvider.notifier);

  final undo = await service.setMetricsMany(ids, metricIds, mode);
  if (undo.before.isEmpty) {
    showInfoToast(overlay, 'Nothing to change');
    return;
  }
  _offerUndo(
    overlay,
    lastUndo,
    undo.before.length == 1
        ? 'Directions changed'
        : 'Directions changed for ${undo.before.length} actions',
    () => service.undoSetMetricsMany(undo),
  );
}

/// The same previous / next action for SEVERAL actions ([mode]: add / remove /
/// replace), one transaction and ONE Undo. Pairs that would close a loop are
/// skipped and mentioned in the toast.
Future<void> runUndoableLinkMany(
  BuildContext context,
  WidgetRef ref,
  Iterable<String> actionIds, {
  required String? targetId,
  required LinkSide side,
  required BulkMode mode,
}) async {
  final ids = actionIds.toList();
  if (ids.isEmpty) return;
  final service = ref.read(bulkEditServiceProvider);
  final overlay = rootOverlayOf(context);
  final lastUndo = ref.read(undoHistoryProvider.notifier);

  final r = await service.linkMany(
    ids,
    targetId: targetId,
    side: side,
    mode: mode,
  );
  final loops = r.skippedLoop == 0
      ? ''
      : ' (${r.skippedLoop} skipped: would loop)';
  if (r.linked == 0 && r.removed == 0) {
    showInfoToast(
      overlay,
      r.skippedLoop == 0 ? 'Nothing to change' : 'Nothing linked$loops',
    );
    return;
  }
  final what = [
    if (r.linked > 0) 'linked ${r.linked}',
    if (r.removed > 0) 'unlinked ${r.removed}',
  ].join(', ');
  _offerUndo(
    overlay,
    lastUndo,
    '${side == LinkSide.previous ? 'Previous' : 'Next'}: $what$loops',
    () => service.undoLinkMany(r.undo),
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
  final lastUndo = ref.read(undoHistoryProvider.notifier);

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
  final lastUndo = ref.read(undoHistoryProvider.notifier);

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
  final lastUndo = ref.read(undoHistoryProvider.notifier);

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
  final lastUndo = ref.read(undoHistoryProvider.notifier);

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
  final lastUndo = ref.read(undoHistoryProvider.notifier);

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
  final lastUndo = ref.read(undoHistoryProvider.notifier);

  await apply();
  _offerUndo(overlay, lastUndo, description, () async {
    await service.restorePositions(previous);
    afterUndo?.call();
  });
}

/// Records an undoable operation and shows the "Undo" toast for it. Public so
/// other sections (budget deletes ...) join the same history; read [history]
/// (`ref.read(undoHistoryProvider.notifier)`) and [overlay] BEFORE the first
/// await, like every helper here.
void offerUndo(
  OverlayState overlay,
  StateController<List<UndoEntry>> history,
  String description,
  Future<void> Function() revert,
) {
  final entry = UndoEntry(description, revert, overlay);
  final next = [...history.state, entry];
  history.state = next.length > kUndoHistoryLimit
      ? next.sublist(next.length - kUndoHistoryLimit)
      : next;

  // Shown in the root overlay (above dialogs, still clickable). A new toast
  // replaces the previous one: it always offers the newest operation.
  showUndoToast(overlay, description, onUndo: () => _undoEntry(history, entry));
}

void _offerUndo(
  OverlayState overlay,
  StateController<List<UndoEntry>> history,
  String description,
  Future<void> Function() revert,
) => offerUndo(overlay, history, description, revert);

/// Takes back the newest operation (the global Ctrl+Z); false when there is
/// nothing to undo. Repeated presses walk further back, up to
/// [kUndoHistoryLimit] steps.
Future<bool> performUndo(WidgetRef ref) =>
    undoNewest(ref.read(undoHistoryProvider.notifier));

/// [performUndo] on a history controller directly (tests use it).
Future<bool> undoNewest(StateController<List<UndoEntry>> history) async {
  final list = history.state;
  if (list.isEmpty) return false;
  final entry = list.last;
  return _undoEntry(history, entry);
}

Future<bool> _undoEntry(
  StateController<List<UndoEntry>> history,
  UndoEntry entry,
) async {
  final list = history.state;
  if (!list.contains(entry)) return false;
  history.state = [
    for (final e in list)
      if (!identical(e, entry)) e,
  ];
  // The toast offering this operation is done with.
  dismissActiveToast();
  try {
    await entry.revert();
  } catch (_) {
    // The rows it would restore are gone (deleted elsewhere, a sync merge):
    // the entry is dropped, nothing else to do.
    return false;
  }
  final overlay = entry._overlay;
  if (overlay != null && overlay.mounted) {
    showInfoToast(overlay, 'Undone: ${entry.description}');
  }
  return true;
}
