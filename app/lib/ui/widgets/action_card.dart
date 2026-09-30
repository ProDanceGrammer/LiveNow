import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../edit_action.dart';
import '../providers.dart';
import '../undo.dart';
import 'action_tile.dart'
    show formatActionDuration, formatUrgency, iconForAction, twoDigits;
import 'quick_action_bar.dart';
import 'quick_time_edit_dialog.dart';

/// One card on the Current Actions board: name, its current time range
/// (`start_at` -> `end_at` — kept in sync with the real started/finished
/// time by Start/Finish, so there's a single time to show and to postpone,
/// not a separate "scheduled" one), and the quick-action buttons inline —
/// no menu to open first. Tapping anywhere on the card opens the full
/// editor; tapping the time specifically opens a quick date/time picker
/// instead.
class ActionCard extends ConsumerWidget {
  final ActionListItem action;

  const ActionCard({super.key, required this.action});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isRunning =
        ref.watch(runningOccurrencesProvider).value?.contains(action.id) ??
        false;
    final urgency = ref.watch(
      actionUrgencyProvider.select((m) => m[action.id]),
    );
    final timeLine = _formatTimeLine(action);

    return GestureDetector(
      onSecondaryTapDown: (d) =>
          _showContextMenu(context, ref, d.globalPosition),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: InkWell(
          onTap: () => openActionEditor(context, ref, action.id),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      iconForAction(action, isRunning),
                      size: 20,
                      color: isRunning
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        action.name,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    if (urgency != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          'U ${formatUrgency(urgency)}',
                          key: const ValueKey('actionUrgencyChip'),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                  ],
                ),
                if (timeLine != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 28, top: 2),
                    child: InkWell(
                      onTap: () => QuickTimeEditDialog.show(
                        context,
                        actionId: action.id,
                        initialStart: action.startAt,
                        initialEnd: action.endAt,
                      ),
                      child: Text(
                        timeLine,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.secondary,
                          decoration: TextDecoration.underline,
                          decorationColor: Theme.of(context)
                              .colorScheme
                              .secondary
                              .withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                QuickActionBar(actionId: action.id),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Right-click menu: currently just a red "Delete" (undoable afterwards).
  Future<void> _showContextMenu(
    BuildContext context,
    WidgetRef ref,
    Offset position,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'delete',
          child: Text(
            'Delete',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
    );
    if (choice == 'delete' && context.mounted) {
      await runUndoableDelete(context, ref, action.id);
    }
  }

  /// Independently shows a date on the start and/or the end whenever that
  /// side isn't today — showing it only when start/end differ *from each
  /// other* (the old behaviour) meant a range entirely in the past could
  /// render with no date at all, which is exactly the confusing case.
  /// Appends the computed duration (see `computeActionDuration`) — and, if
  /// there's no schedule at all yet, shows just the duration on its own
  /// rather than hiding it entirely, so it's still visible/tappable-to-edit.
  String? _formatTimeLine(ActionListItem a) {
    if (a.startAt == null) {
      return a.isAllDay ? null : formatActionDuration(a);
    }
    final start = a.startAt!.toLocal();
    final today = DateTime.now();
    final startStr = _sameDay(start, today)
        ? _time(start)
        : '${_date(start)} ${_time(start)}';

    final String range;
    if (a.endAt == null) {
      range = startStr;
    } else {
      final end = a.endAt!.toLocal();
      final endStr = _sameDay(end, today)
          ? _time(end)
          : '${_date(end)} ${_time(end)}';
      range = '$startStr → $endStr';
    }
    return a.isAllDay ? range : '$range · ${formatActionDuration(a)}';
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _date(DateTime d) =>
      '${d.year}-${twoDigits(d.month)}-${twoDigits(d.day)}';
  String _time(DateTime d) => '${twoDigits(d.hour)}:${twoDigits(d.minute)}';
}
