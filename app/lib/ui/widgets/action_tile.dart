import '../shortcut_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../../domain/duration_rules.dart';
import '../all_selection.dart';
import '../providers.dart';
import '../time_format.dart';
import '../urgency_colors.dart';
import 'action_time_label.dart';
import 'glass.dart';
import 'param_icons.dart';

// Re-exported for the widgets/views that imported these from here.
export '../time_format.dart' show twoDigits, formatClockTime;

/// One row in the All list: a checkbox (selection for bulk edits), the status
/// icon, name and a short "when/how long" subtitle. No menu: an action is
/// edited by opening it, several at once through the bulk bar.
class ActionTile extends ConsumerWidget {
  final ActionListItem action;
  final VoidCallback? onTap;

  const ActionTile({super.key, required this.action, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The minute tick only re-evaluates the end side; the check itself uses the
    // current moment, so a Start just pressed shows as running at once (the
    // pinned board time can be up to a minute older than the new start).
    ref.watch(currentBoardNowProvider);
    final isRunning = action.isRunningAt(DateTime.now().toUtc());

    final urgency = ref.watch(
      actionUrgencyProvider.select((m) => m[action.id]),
    );
    // Tinted like a Current card: no direction = white ("fill me in"), else
    // the urgency band (muted when done); a running action stays plain.
    final unlinked = ref.watch(
      actionsWithDirectionsProvider.select(
        (s) => s != null && !s.contains(action.id),
      ),
    );
    final dark = Theme.of(context).brightness == Brightness.dark;
    final done = action.isDoneBefore;
    final tint = isRunning
        ? null
        : unlinked
        ? emptyColors(dark: dark, done: done)
        : urgency != null
        ? (done
              ? urgencyColorsMuted(urgency, dark: dark)
              : urgencyColors(urgency, dark: dark))
        : null;
    final fg = tint?.fg;
    final scheme = Theme.of(context).colorScheme;
    final selected = ref.watch(
      allSelectionProvider.select((s) => s.contains(action.id)),
    );

    // Parts are either plain strings or the clickable time label.
    final subtitleParts = <Object>[
      if (action.startAt != null)
        ActionTimeLabel(
          key: const ValueKey('tileTimeLabel'),
          action: action,
          text: formatScheduledWhen(action),
          // The link colour (teal) is unreadable on a tinted tile: use the
          // tile's text colour (black on light fills, white on dark ones).
          style: fg == null ? null : TextStyle(color: fg),
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
          color: fg ?? Theme.of(context).colorScheme.onSurface,
          iconColor: fg,
        ),
    ];

    final tile = ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textColor: fg,
      iconColor: fg,
      key: ValueKey('all-tile-${action.id}'),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            key: ValueKey('all-check-${action.id}'),
            semanticLabel: 'Select ${action.name}',
            value: selected,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            activeColor: fg ?? scheme.primary,
            checkColor: tint?.bg ?? scheme.surface,
            side: BorderSide(color: fg ?? scheme.onSurfaceVariant, width: 1.5),
            onChanged: (_) =>
                ref.read(allSelectionProvider.notifier).toggle(action.id),
          ),
          Icon(
            iconForAction(action, isRunning),
            color: isRunning ? scheme.primary : null,
          ),
        ],
      ),
      title: Text(action.name),
      subtitle: subtitleParts.isEmpty
          ? null
          : Text.rich(
              TextSpan(
                style: fg == null ? null : TextStyle(color: fg),
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
      // With something selected (or Ctrl/Shift held) a tap toggles the row;
      // otherwise it opens the action.
      onTap: () {
        final selection = ref.read(allSelectionProvider.notifier);
        final kb = HardwareKeyboard.instance;
        if (selection.state.isNotEmpty ||
            isPrimaryPressed() ||
            kb.isShiftPressed) {
          selection.toggle(action.id);
        } else {
          onTap?.call();
        }
      },
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: GlassSurface(
        radius: 16,
        // Small row: no shadow / blurred window (invisible here, costly in bulk).
        shadow: false,
        blurWindow: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            // A selected row: the tint with a faint primary wash + a 2 px ring.
            color: selected
                ? Color.alphaBlend(
                    scheme.primary.withValues(alpha: 0.14),
                    tint?.bg ?? const Color(0x00000000),
                  )
                : tint?.bg,
            borderRadius: BorderRadius.circular(16),
            border: selected ? Border.all(color: scheme.primary, width: 2) : null,
          ),
          child: Material(type: MaterialType.transparency, child: tile),
        ),
      ),
    );
  }
}

/// The schedule in the card's style (`20-12-2026 12:00 → 14:00`).
String formatScheduledWhen(ActionListItem a) =>
    formatTimeRange(a.startAt, a.endAt, isAllDay: a.isAllDay)!;

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
