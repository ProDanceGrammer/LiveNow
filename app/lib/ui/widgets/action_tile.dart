import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../../domain/duration_rules.dart';
import '../providers.dart';
import '../time_format.dart';
import 'action_menu_button.dart';
import 'action_time_label.dart';
import 'glass.dart';
import 'param_icons.dart';

// Re-exported for the widgets/views that imported these from here.
export '../time_format.dart' show twoDigits, formatClockTime;

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

    final urgency = ref.watch(
      actionUrgencyProvider.select((m) => m[action.id]),
    );

    // Parts are either plain strings or the clickable time label.
    final subtitleParts = <Object>[
      if (action.isDoneBefore) 'Done',
      if (action.startAt != null)
        ActionTimeLabel(
          key: const ValueKey('tileTimeLabel'),
          action: action,
          text: formatScheduledWhen(action),
        ),
      if (!action.isAllDay) formatActionDuration(action),
      if (isRunning && action.startAt != null)
        'Started ${formatClockTime(action.startAt!)}',
      if (urgency != null)
        ParamValue.urgency(
          formatUrgency(urgency),
          key: const ValueKey('tileUrgency'),
          size: 19,
          style: Theme.of(context).textTheme.bodyMedium,
          color: Theme.of(context).colorScheme.onSurface,
        ),
    ];

    final tile = ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      leading: Icon(
        iconForAction(action, isRunning),
        color: isRunning ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(action.name),
      subtitle: subtitleParts.isEmpty
          ? null
          : Text.rich(
              TextSpan(
                children: [
                  for (var i = 0; i < subtitleParts.length; i++) ...[
                    if (i > 0) const TextSpan(text: ' · '),
                    switch (subtitleParts[i]) {
                      final Widget w => WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: w,
                      ),
                      final p => TextSpan(text: p as String),
                    },
                  ],
                ],
              ),
            ),
      onTap: onTap,
      trailing: ActionMenuButton(actionId: action.id),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: GlassSurface(
        radius: 16,
        // Small row: no shadow / blurred window (invisible here, costly in bulk).
        shadow: false,
        blurWindow: false,
        child: Material(type: MaterialType.transparency, child: tile),
      ),
    );
  }
}

String formatScheduledWhen(ActionListItem a) =>
    formatUtcDateTime(a.startAt!, includeTime: !a.isAllDay);

/// The computed, human-readable duration of [a] (see `computeActionDuration`).
String formatActionDuration(ActionListItem a) => formatDuration(
  computeActionDuration(
    startAt: a.startAt,
    endAt: a.endAt,
    legacyEstimatedMinutes: a.estimatedMinutes,
  ),
);

/// Urgency rounded to a whole number, e.g. 910 or -90.
String formatUrgency(double u) => u.round().toString();

IconData iconForAction(ActionListItem a, bool isRunning) {
  if (isRunning) return Icons.play_circle_fill;
  return a.isDoneBefore ? Icons.check_circle : Icons.check_circle_outline;
}
