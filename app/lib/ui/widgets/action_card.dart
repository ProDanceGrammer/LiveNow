import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../current_selection.dart';
import '../edit_action.dart';
import '../providers.dart';
import '../undo.dart';
import 'glass.dart';
import '../time_format.dart';
import 'action_tile.dart'
    show formatActionDuration, formatUrgency, iconForAction;
import 'action_time_label.dart';
import 'hover_toolbar.dart';
import 'quick_action_bar.dart';

/// One card on the Current Actions board: name, its current time range
/// (`start_at` -> `end_at` — kept in sync with the real started/finished
/// time by Start/Finish, so there's a single time to show and to postpone,
/// not a separate "scheduled" one). The quick-action buttons live in a hover
/// toolbar ([HoverToolbarHost]) that exists only while the mouse rests on the
/// card — a board of cards must not carry a button row each. Tapping anywhere
/// on the card opens the full editor; tapping the time specifically opens a
/// quick date/time picker instead.
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
    final selected = ref.watch(
      currentSelectionProvider.select((s) => s.contains(action.id)),
    );
    final primary = Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onSecondaryTapDown: (d) =>
          _showContextMenu(context, ref, d.globalPosition),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: HoverToolbarHost(
          toolbarBuilder: (_) => HoverToolbarPill(
            child: QuickActionBar(
              actionId: action.id,
              onDelete: () => _deleteFromToolbar(context, ref),
              tileSize: 28,
              iconSize: 18,
              spacing: 2,
            ),
          ),
          child: GlassSurface(
            radius: 20,
            // Cards sit directly on the page background: a slightly stronger
            // fill and the cheap soft shadow rings give them clear edges against
            // the clouds. No blurred window (invisible at this size, costs ms).
            strength: 1.25,
            shadow: true,
            blurWindow: false,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _onTap(context, ref),
                // A Container without a decoration is just the padding; a
                // selected card adds a 2 px primary border and a faint fill.
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: selected
                      ? BoxDecoration(
                          color: primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: primary, width: 2),
                        )
                      : null,
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
                          child: ActionTimeLabel(
                            action: action,
                            text: timeLine,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The toolbar's Delete: the whole selection when this card is part of a
  /// multi-selection, else just this card.
  void _deleteFromToolbar(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(currentSelectionProvider.notifier);
    final selection = notifier.state;
    if (selection.length > 1 && selection.contains(action.id)) {
      final ids = selection.toList();
      notifier.state = const {};
      runUndoableDeleteMany(context, ref, ids);
    } else {
      runUndoableDelete(context, ref, action.id);
    }
  }

  /// Ctrl/Shift+click toggles this card in the selection (no editor); a
  /// plain click resets the selection and opens the editor.
  void _onTap(BuildContext context, WidgetRef ref) {
    final keys = HardwareKeyboard.instance;
    final notifier = ref.read(currentSelectionProvider.notifier);
    if (keys.isControlPressed || keys.isShiftPressed) {
      final next = <String>{...notifier.state};
      if (!next.remove(action.id)) next.add(action.id);
      notifier.state = next;
      return;
    }
    if (notifier.state.isNotEmpty) notifier.state = const {};
    openActionEditor(context, ref, action.id);
  }

  /// Right-click menu: a red "Delete" (undoable afterwards) that deletes the
  /// whole selection when this card is part of one.
  Future<void> _showContextMenu(
    BuildContext context,
    WidgetRef ref,
    Offset position,
  ) async {
    final selectionNotifier = ref.read(currentSelectionProvider.notifier);
    if (!selectionNotifier.state.contains(action.id)) {
      selectionNotifier.state = {action.id};
    }
    final ids = selectionNotifier.state.toList();
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
            ids.length > 1 ? 'Delete ${ids.length} actions' : 'Delete',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
    );
    if (choice == 'delete' && context.mounted) {
      selectionNotifier.state = const {};
      if (ids.length > 1) {
        await runUndoableDeleteMany(context, ref, ids);
      } else {
        await runUndoableDelete(context, ref, action.id);
      }
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
    final range = formatTimeRange(a.startAt, a.endAt, isAllDay: a.isAllDay)!;
    return a.isAllDay ? range : '$range · ${formatActionDuration(a)}';
  }
}
