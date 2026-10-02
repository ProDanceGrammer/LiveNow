import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/postpone_rules.dart';
import '../providers.dart';
import '../undo.dart';
import 'glass_icon_tile.dart';

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

  const QuickActionBar({
    super.key,
    required this.actionId,
    this.onDelete,
    this.tileSize = 32,
    this.iconSize = 20,
    this.hitExtra = 4,
    this.spacing = 6,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(actionServiceProvider);

    Future<void> run(String description, Future<void> Function() operation) =>
        runUndoable(context, ref, actionId, description, operation);

    Widget tile(
      IconData icon,
      GlassHue hue,
      String tooltip,
      Future<void> Function() onTap,
    ) => GlassIconTile(
      icon: icon,
      hue: hue,
      tooltip: tooltip,
      onTap: onTap,
      size: tileSize,
      iconSize: iconSize,
      hitExtra: hitExtra,
    );

    final items = <Widget>[
      tile(
        Icons.play_arrow_rounded,
        GlassHue.blue,
        'Start',
        () => run('Started', () => service.start(actionId)),
      ),
      tile(
        Icons.stop_rounded,
        GlassHue.pink,
        'Finish',
        () => run('Finished', () => service.finish(actionId)),
      ),
      tile(
        Icons.autorenew_rounded,
        GlassHue.green,
        'Continue with same action',
        () => runUndoableContinue(context, ref, actionId),
      ),
      // A visible gap here separates "act on it now" (above) from
      // "postpone" (below) — those two groups being right next to each
      // other, in small tightly-packed buttons, was the likely cause of
      // mis-clicking Finish while aiming for a postpone option.
      const SizedBox(width: 10),
      tile(
        Icons.hourglass_bottom_rounded,
        GlassHue.lavender,
        'Prolong 30 min',
        () => run(
          'Prolonged 30 min',
          () => service.postpone(actionId, PostponeRule.prolongThirtyMinutes),
        ),
      ),
      tile(
        Icons.more_time_rounded,
        GlassHue.cyan,
        'Postpone +1 hour',
        () => run(
          'Postponed +1 hour',
          () => service.postpone(actionId, PostponeRule.plusOneHour),
        ),
      ),
      tile(
        Icons.update_rounded,
        GlassHue.cyan,
        'Postpone +5 hours',
        () => run(
          'Postponed +5 hours',
          () => service.postpone(actionId, PostponeRule.plusFiveHours),
        ),
      ),
      tile(
        Icons.nightlight_round,
        GlassHue.lavender,
        'Postpone: after work (18:00)',
        () => run(
          'Postponed to after work',
          () => service.postpone(actionId, PostponeRule.afterWork),
        ),
      ),
      tile(
        Icons.wb_twilight_rounded,
        GlassHue.peach,
        'Postpone: tomorrow morning',
        () => run(
          'Postponed to tomorrow morning',
          () => service.postpone(actionId, PostponeRule.morning),
        ),
      ),
      tile(
        Icons.work_history_outlined,
        GlassHue.cyan,
        'Postpone: next working morning',
        () => run(
          'Postponed to next working morning',
          () => service.postpone(actionId, PostponeRule.workingMorning),
        ),
      ),
      tile(
        Icons.calendar_view_week_rounded,
        GlassHue.blue,
        'Postpone: next week',
        () => run(
          'Postponed to next week',
          () => service.postpone(actionId, PostponeRule.nextWeek),
        ),
      ),
      tile(
        Icons.event_repeat_rounded,
        GlassHue.lavender,
        'Postpone: next Monday morning',
        () => run(
          'Postponed to next Monday morning',
          () => service.postpone(actionId, PostponeRule.nextMondayMorning),
        ),
      ),
      // Set apart from the everyday buttons so it isn't hit by accident;
      // Undo (snackbar / Ctrl+Z) is the safety net, not a confirmation.
      const SizedBox(width: 10),
      tile(
        Icons.delete_outline_rounded,
        GlassHue.error,
        'Delete',
        () async => onDelete != null
            ? onDelete!()
            : await runUndoableDelete(context, ref, actionId),
      ),
    ];

    // Gaps are plain SizedBoxes; every other pair of neighbours gets
    // [spacing] between them.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0 && items[i - 1] is! SizedBox && items[i] is! SizedBox)
            SizedBox(width: spacing),
          items[i],
        ],
      ],
    );
  }
}
