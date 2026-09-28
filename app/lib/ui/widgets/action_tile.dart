import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../../domain/duration_rules.dart';
import '../providers.dart';
import 'action_menu_button.dart';

/// One row in a view list: name, a short "when/how long" subtitle, and the
/// Start/Finish/Postpone menu.
class ActionTile extends ConsumerWidget {
  final ActionListItem action;
  final VoidCallback? onTap;

  const ActionTile({super.key, required this.action, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isRunning =
        ref.watch(runningOccurrencesProvider).value?.contains(action.id) ??
        false;

    final subtitleParts = <String>[
      if (action.isDoneBefore) 'Done',
      if (action.priority != null) action.priority!,
      if (action.startAt != null) formatScheduledWhen(action),
      if (!action.isAllDay) formatActionDuration(action),
      if (isRunning && action.startAt != null)
        'Started ${formatClockTime(action.startAt!)}',
    ];

    return ListTile(
      leading: Icon(
        iconForAction(action, isRunning),
        color: isRunning ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(action.name),
      subtitle: subtitleParts.isEmpty ? null : Text(subtitleParts.join(' · ')),
      onTap: onTap,
      trailing: ActionMenuButton(actionId: action.id),
    );
  }
}

String formatScheduledWhen(ActionListItem a) {
  final start = a.startAt!.toLocal();
  final date = '${start.year}-${twoDigits(start.month)}-${twoDigits(start.day)}';
  if (a.isAllDay) return date;
  return '$date ${twoDigits(start.hour)}:${twoDigits(start.minute)}';
}

String formatClockTime(DateTime utc) {
  final local = utc.toLocal();
  return '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}

/// The computed, human-readable duration of [a] (see `computeActionDuration`).
String formatActionDuration(ActionListItem a) => formatDuration(
  computeActionDuration(
    startAt: a.startAt,
    endAt: a.endAt,
    legacyEstimatedMinutes: a.estimatedMinutes,
  ),
);

String twoDigits(int n) => n.toString().padLeft(2, '0');

IconData iconForAction(ActionListItem a, bool isRunning) {
  if (isRunning) return Icons.play_circle_fill;
  return a.isDoneBefore ? Icons.check_circle : Icons.check_circle_outline;
}
