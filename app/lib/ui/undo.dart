import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;

import '../domain/action_service.dart';
import 'providers.dart';

class _UndoEntry {
  final ActionSnapshot snapshot;
  const _UndoEntry(this.snapshot);
}

/// The most recent undoable quick-action, while its ~5-second window (the
/// same window as the snackbar offering it) is still open. Both the
/// snackbar's "Undo" button and the global Ctrl+Z shortcut just restore
/// this snapshot; either one clears it afterward.
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
  // Looked up before the operation runs: some operations (e.g. Finish,
  // which can drop a task off a view that only shows open items) remove
  // this action's card from the list it's currently shown in, which can
  // unmount this context by the time the write finishes. The
  // ScaffoldMessengerState itself belongs to the stable Scaffold ancestor,
  // so it stays valid to call even after that.
  final messenger = ScaffoldMessenger.of(context);
  final snapshot = await service.snapshot(actionId);
  await operation();

  final entry = _UndoEntry(snapshot);
  ref.read(lastUndoProvider.notifier).state = entry;

  // Replace rather than queue: only this entry is actually undoable, so a
  // still-queued snackbar from an earlier quick action would offer an
  // "Undo" that no longer restores what it claims to.
  messenger.hideCurrentSnackBar();
  final controller = messenger.showSnackBar(
    SnackBar(
      content: Text(description),
      duration: const Duration(seconds: 5),
      action: SnackBarAction(label: 'Undo', onPressed: () => performUndo(ref)),
    ),
  );
  controller.closed.then((_) {
    if (identical(ref.read(lastUndoProvider), entry)) {
      ref.read(lastUndoProvider.notifier).state = null;
    }
  });
}

/// Restores the snapshot from the most recent undoable quick-action, if its
/// window hasn't closed yet. Used by both the snackbar's "Undo" button and
/// the global Ctrl+Z shortcut.
Future<void> performUndo(WidgetRef ref) async {
  final entry = ref.read(lastUndoProvider);
  if (entry is! _UndoEntry) return;
  ref.read(lastUndoProvider.notifier).state = null;
  await ref.read(actionServiceProvider).restore(entry.snapshot);
}
