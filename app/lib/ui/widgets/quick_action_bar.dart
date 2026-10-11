import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/postpone_rules.dart';
import '../providers.dart';
import '../undo.dart';
import 'glass_icon_tile.dart';

/// One quick action (Start, Finish, a postpone rule, Delete). [group] only
/// controls where visual gaps go: 0 = act now, 1 = postpone, 2 = delete.
class QuickActionSpec {
  final IconData icon;
  final GlassHue hue;
  final String label;
  final int group;
  final Future<void> Function() onTap;

  const QuickActionSpec(
    this.icon,
    this.hue,
    this.label,
    this.group,
    this.onTap,
  );
}

/// The quick actions for [actionId], shared by the icon bar (hover toolbar,
/// editor) and the phone's long-press list, so both stay identical.
/// [onDelete] replaces the Delete button's default (delete just [actionId]).
List<QuickActionSpec> quickActionSpecs(
  BuildContext context,
  WidgetRef ref,
  String actionId, {
  VoidCallback? onDelete,
}) {
  final service = ref.read(actionServiceProvider);

  Future<void> run(String description, Future<void> Function() operation) =>
      runUndoable(context, ref, actionId, description, operation);

  Future<void> postpone(String done, PostponeRule rule) =>
      run(done, () => service.postpone(actionId, rule));

  return [
    QuickActionSpec(
      Icons.play_arrow_rounded,
      GlassHue.blue,
      'Start',
      0,
      () => run('Started', () => service.start(actionId)),
    ),
    QuickActionSpec(
      Icons.stop_rounded,
      GlassHue.pink,
      'Finish',
      0,
      () => run('Finished', () => service.finish(actionId)),
    ),
    QuickActionSpec(
      Icons.autorenew_rounded,
      GlassHue.green,
      'Continue with same action',
      0,
      () => runUndoableContinue(context, ref, actionId),
    ),
    QuickActionSpec(
      Icons.hourglass_bottom_rounded,
      GlassHue.lavender,
      'Prolong 30 min',
      1,
      () => postpone('Prolonged 30 min', PostponeRule.prolongThirtyMinutes),
    ),
    QuickActionSpec(
      Icons.more_time_rounded,
      GlassHue.cyan,
      'Postpone +1 hour',
      1,
      () => postpone('Postponed +1 hour', PostponeRule.plusOneHour),
    ),
    QuickActionSpec(
      Icons.update_rounded,
      GlassHue.cyan,
      'Postpone +5 hours',
      1,
      () => postpone('Postponed +5 hours', PostponeRule.plusFiveHours),
    ),
    QuickActionSpec(
      Icons.nightlight_round,
      GlassHue.lavender,
      'Postpone: after work (18:00)',
      1,
      () => postpone('Postponed to after work', PostponeRule.afterWork),
    ),
    QuickActionSpec(
      Icons.wb_twilight_rounded,
      GlassHue.peach,
      'Postpone: tomorrow morning',
      1,
      () => postpone('Postponed to tomorrow morning', PostponeRule.morning),
    ),
    QuickActionSpec(
      Icons.work_history_outlined,
      GlassHue.cyan,
      'Postpone: next working morning',
      1,
      () => postpone(
        'Postponed to next working morning',
        PostponeRule.workingMorning,
      ),
    ),
    QuickActionSpec(
      Icons.calendar_view_week_rounded,
      GlassHue.blue,
      'Postpone: next week',
      1,
      () => postpone('Postponed to next week', PostponeRule.nextWeek),
    ),
    QuickActionSpec(
      Icons.event_repeat_rounded,
      GlassHue.lavender,
      'Postpone: next Monday morning',
      1,
      () => postpone(
        'Postponed to next Monday morning',
        PostponeRule.nextMondayMorning,
      ),
    ),
    // Set apart from the everyday buttons so it isn't hit by accident;
    // Undo (snackbar / Ctrl+Z) is the safety net, not a confirmation.
    QuickActionSpec(
      Icons.delete_outline_rounded,
      GlassHue.error,
      'Delete',
      2,
      () async => onDelete != null
          ? onDelete()
          : await runUndoableDelete(context, ref, actionId),
    ),
  ];
}

/// The Start/Finish/Postpone actions as a row of small tinted glass icon
/// tiles. Shown inside the hover toolbar of a Current Actions card (see
/// `hover_toolbar.dart`); the card itself builds none of these buttons.
class QuickActionBar extends ConsumerWidget {
  final String actionId;

  /// Replaces the Delete button's default (delete just [actionId]), e.g. to
  /// delete a whole multi-selection.
  final VoidCallback? onDelete;

  /// Tile geometry (see `GlassIconTile`) and the gap between tiles.
  final double tileSize;
  final double iconSize;
  final double hitExtra;
  final double spacing;

  /// Wrap onto several rows instead of one long row (phone editor, where a
  /// single row forces tiny icons).
  final bool wrap;

  const QuickActionBar({
    super.key,
    required this.actionId,
    this.onDelete,
    this.tileSize = 32,
    this.iconSize = 20,
    this.hitExtra = 4,
    this.spacing = 6,
    this.wrap = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final specs = quickActionSpecs(context, ref, actionId, onDelete: onDelete);

    Widget tile(QuickActionSpec s) => GlassIconTile(
      icon: s.icon,
      hue: s.hue,
      tooltip: s.label,
      onTap: s.onTap,
      size: tileSize,
      iconSize: iconSize,
      hitExtra: hitExtra,
    );

    if (wrap) {
      return Wrap(
        spacing: spacing + 4,
        runSpacing: spacing + 4,
        children: [for (final s in specs) tile(s)],
      );
    }

    // A visible gap separates "act on it now" from "postpone" from "delete":
    // tightly-packed small buttons once caused mis-clicking Finish while
    // aiming for a postpone option. Neighbours in a group get [spacing].
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < specs.length; i++) ...[
          if (i > 0)
            SizedBox(
              width: specs[i].group != specs[i - 1].group ? 10 : spacing,
            ),
          tile(specs[i]),
        ],
      ],
    );
  }
}
