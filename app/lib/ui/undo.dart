import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart'
    show StateController, StateProvider;

import 'providers.dart';

class _UndoEntry {
  /// Puts back whatever the quick-action changed.
  final Future<void> Function() revert;
  const _UndoEntry(this.revert);
}

/// The most recent undoable quick-action, while its ~5-second window (the
/// same window as the snackbar offering it) is still open. Both the
/// snackbar's "Undo" button and the global Ctrl+Z shortcut just run this
/// entry's revert; either one clears it afterward.
final lastUndoProvider = StateProvider<Object?>((ref) => null);

/// Wraps a quick-action call (Start/Finish/Postpone/...) so it can be
/// undone: snapshots the action's full row + occurrence history first, runs
/// the operation, then offers a Notion-style "Undo" snackbar for 5 seconds
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
  // ScaffoldMessengerState itself belongs to the stable Scaffold ancestor,
  // and the notifier lives in the ProviderScope, so both stay valid.
  final messenger = ScaffoldMessenger.of(context);
  final lastUndo = ref.read(lastUndoProvider.notifier);
  final snapshot = await service.snapshot(actionId);
  await operation();
  _offerUndo(messenger, lastUndo, description, () => service.restore(snapshot));
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
  final messenger = ScaffoldMessenger.of(context);
  final lastUndo = ref.read(lastUndoProvider.notifier);
  final result = await service.continueSameAction(sourceId);
  _offerUndo(
    messenger,
    lastUndo,
    'Continued as a new action',
    () => service.undoContinue(result.undo),
  );
}

/// Deletes an action right away and offers Undo (no confirmation dialog —
/// the Undo snackbar is the safety net). Like [runUndoableContinue], it
/// can't use [runUndoable]: the snapshot must also cover the action's links.
Future<void> runUndoableDelete(
  BuildContext context,
  WidgetRef ref,
  String actionId,
) async {
  final service = ref.read(actionServiceProvider);
  // Looked up before deleting: the card/block this context belongs to
  // disappears with the action, after which `ref` can't be used.
  final messenger = ScaffoldMessenger.of(context);
  final lastUndo = ref.read(lastUndoProvider.notifier);
  final selected = ref.read(calendarSelectedActionProvider.notifier);

  final undo = await service.deleteAction(actionId);
  if (selected.state == actionId) selected.state = null;
  _offerUndo(
    messenger,
    lastUndo,
    'Deleted "${undo.action.name}"',
    () => service.undoDelete(undo),
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
  final messenger = ScaffoldMessenger.of(context);
  final lastUndo = ref.read(lastUndoProvider.notifier);

  final undo = await service.deleteMetric(metricId);
  _offerUndo(
    messenger,
    lastUndo,
    'Deleted "${undo.metric.name}"',
    () => service.undoDelete(undo),
  );
}

void _offerUndo(
  ScaffoldMessengerState messenger,
  StateController<Object?> lastUndo,
  String description,
  Future<void> Function() revert,
) {
  final entry = _UndoEntry(revert);
  lastUndo.state = entry;

  // Replace rather than queue: only this entry is actually undoable, so a
  // still-queued snackbar from an earlier quick action would offer an
  // "Undo" that no longer restores what it claims to.
  messenger.hideCurrentSnackBar();
  final controller = messenger.showSnackBar(
    SnackBar(
      content: Text(description),
      // SnackBars with an action persist by default (duration ignored).
      persist: false,
      duration: const Duration(seconds: 5),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => _undoLast(lastUndo),
      ),
    ),
  );
  controller.closed.then((_) {
    if (identical(lastUndo.state, entry)) lastUndo.state = null;
  });
}

/// Reverts the most recent undoable quick-action, if its window hasn't
/// closed yet. Used by the global Ctrl+Z shortcut; the snackbar's "Undo"
/// button does the same through [_undoLast].
Future<void> performUndo(WidgetRef ref) =>
    _undoLast(ref.read(lastUndoProvider.notifier));

Future<void> _undoLast(StateController<Object?> lastUndo) async {
  final entry = lastUndo.state;
  if (entry is! _UndoEntry) return;
  lastUndo.state = null;
  await entry.revert();
}
