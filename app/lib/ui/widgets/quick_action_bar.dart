import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/form_schedule.dart';
import '../../domain/postpone_rules.dart';
import '../../domain/work_hours.dart';
import '../providers.dart';
import '../undo.dart';
import '../work_hours.dart';
import 'continue_icon.dart';
import 'glass_icon_tile.dart';

/// One quick action (Start, Finish, a postpone rule, Delete). [group] only
/// controls where visual gaps go: 0 = act now, 1 = postpone, 2 = delete.
class QuickActionSpec {
  final IconData icon;
  final GlassHue hue;
  final String label;
  final int group;
  final Future<void> Function() onTap;
  final bool enabled;

  const QuickActionSpec(
    this.icon,
    this.hue,
    this.label,
    this.group,
    this.onTap, {
    this.enabled = true,
  });
}

/// The postpone / prolong buttons, in display order, with their icon, colour,
/// tooltip and the Undo text. One table for the real bar ([quickActionSpecs])
/// and the form's bar ([formQuickActionSpecs]), so both stay identical.
typedef _PostponeButton = ({
  PostponeRule rule,
  IconData icon,
  GlassHue hue,
  String label,
  String done,
});

List<_PostponeButton> _postponeButtons(WorkHours hours) => [
  (
    rule: PostponeRule.prolongThirtyMinutes,
    icon: Icons.hourglass_bottom_rounded,
    hue: GlassHue.lavender,
    label: 'Prolong 30 min',
    done: 'Prolonged 30 min',
  ),
  (
    rule: PostponeRule.plusOneHour,
    icon: Icons.more_time_rounded,
    hue: GlassHue.cyan,
    label: 'Postpone +1 hour',
    done: 'Postponed +1 hour',
  ),
  (
    rule: PostponeRule.plusFiveHours,
    icon: Icons.update_rounded,
    hue: GlassHue.cyan,
    label: 'Postpone +5 hours',
    done: 'Postponed +5 hours',
  ),
  (
    rule: PostponeRule.afterWork,
    icon: Icons.nightlight_round,
    hue: GlassHue.lavender,
    label: 'Postpone: after work (${WorkHours.format(hours.workEnd)})',
    done: 'Postponed to after work',
  ),
  (
    rule: PostponeRule.morning,
    icon: Icons.wb_twilight_rounded,
    hue: GlassHue.peach,
    label: 'Postpone: tomorrow morning',
    done: 'Postponed to tomorrow morning',
  ),
  (
    rule: PostponeRule.workingMorning,
    icon: Icons.work_history_outlined,
    hue: GlassHue.cyan,
    label: 'Postpone: next working morning',
    done: 'Postponed to next working morning',
  ),
  (
    rule: PostponeRule.nextWeek,
    icon: Icons.calendar_view_week_rounded,
    hue: GlassHue.blue,
    label: 'Postpone: next week',
    done: 'Postponed to next week',
  ),
  (
    rule: PostponeRule.nextMondayMorning,
    icon: Icons.event_repeat_rounded,
    hue: GlassHue.lavender,
    label: 'Postpone: next Monday morning',
    done: 'Postponed to next Monday morning',
  ),
];

/// The buttons of a NEW action's form: Start, Finish and the postpone / prolong
/// buttons (Continue and Delete make no sense before the action exists). They
/// change the form's times only ([apply]); nothing is saved until Save.
/// [current] reads the form's schedule.
List<QuickActionSpec> formQuickActionSpecs(
  WidgetRef ref, {
  required ActionSchedule Function() current,
  required void Function(ActionSchedule next) apply,
}) {
  final hours = ref.read(workHoursProvider);
  DateTime now() => DateTime.now().toUtc();

  return [
    QuickActionSpec(Icons.play_arrow_rounded, GlassHue.blue, 'Start', 0, () async {
      final c = current();
      final r = formStartNow(start: c.startAt, end: c.endAt, nowUtc: now());
      apply(ActionSchedule(startAt: r.start, endAt: r.end));
    }),
    QuickActionSpec(Icons.stop_rounded, GlassHue.pink, 'Finish', 0, () async {
      final c = current();
      final r = formFinishNow(start: c.startAt, end: c.endAt, nowUtc: now());
      apply(ActionSchedule(startAt: r.start, endAt: r.end));
    }),
    for (final b in _postponeButtons(hours))
      QuickActionSpec(
        b.icon,
        b.hue,
        b.label,
        1,
        () async => apply(
          applyPostponeRule(b.rule, current(), nowUtc: now(), hours: hours),
        ),
      ),
  ];
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
  final hours = ref.read(workHoursProvider);

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
      continueIconData,
      GlassHue.green,
      'Continue with same action',
      0,
      () => runUndoableContinue(context, ref, actionId),
    ),
    for (final b in _postponeButtons(hours))
      QuickActionSpec(
        b.icon,
        b.hue,
        b.label,
        1,
        () => postpone(b.done, b.rule),
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

  /// Only these groups (0 = Start/Stop/Continue, 1 = postpone + prolong,
  /// 2 = Delete); null = all of them.
  final Set<int>? groups;

  /// One row split into its groups across the full width: Start/Stop/Continue
  /// at the left, the postpones in the middle, Delete at the right (Windows
  /// editor). Scaled down, never wrapped, when the room is too small.
  final bool spread;

  /// Extra tiles (group 3) shown between the postpone group and Delete; the
  /// action editor adds "Set after previous / before next" here.
  final List<QuickActionSpec> extra;

  /// Ready-made tiles instead of the ones for [actionId]: the NEW-action form
  /// builds its own with [formQuickActionSpecs] (see [QuickActionBar.form]).
  final List<QuickActionSpec>? formSpecs;

  const QuickActionBar({
    super.key,
    required this.actionId,
    this.onDelete,
    this.tileSize = 32,
    this.iconSize = 20,
    this.hitExtra = 4,
    this.spacing = 6,
    this.wrap = false,
    this.groups,
    this.spread = false,
    this.extra = const [],
  }) : formSpecs = null;

  /// The same bar for [specs] that belong to no saved action (a new action's
  /// form): same tiles, spacing, wrapping and spreading.
  const QuickActionBar.form({
    super.key,
    required List<QuickActionSpec> specs,
    this.tileSize = 32,
    this.iconSize = 20,
    this.hitExtra = 4,
    this.spacing = 6,
    this.wrap = false,
    this.groups,
    this.spread = false,
  }) : formSpecs = specs,
       actionId = '',
       onDelete = null,
       extra = const [];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final base =
        formSpecs ?? quickActionSpecs(context, ref, actionId, onDelete: onDelete);
    final all = [
      for (final s in base)
        if (s.group != 2) s,
      ...extra,
      for (final s in base)
        if (s.group == 2) s,
    ];
    final specs = groups == null
        ? all
        : [
            for (final s in all)
              if (groups!.contains(s.group)) s,
          ];

    Widget tile(QuickActionSpec s) => GlassIconTile(
      icon: s.icon,
      hue: s.hue,
      tooltip: s.label,
      onTap: s.onTap,
      enabled: s.enabled,
      size: tileSize,
      iconSize: iconSize,
      hitExtra: hitExtra,
    );

    if (spread) {
      final byGroup = <int, List<QuickActionSpec>>{};
      for (final s in specs) {
        (byGroup[s.group] ??= []).add(s);
      }
      Widget group(List<QuickActionSpec> g) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < g.length; i++) ...[
            if (i > 0) SizedBox(width: spacing),
            tile(g[i]),
          ],
        ],
      );
      final tileW = tileSize + hitExtra;
      var natural = 16.0 * (byGroup.length - 1);
      for (final g in byGroup.values) {
        natural += g.length * tileW + (g.length - 1) * spacing;
      }
      return LayoutBuilder(
        builder: (context, c) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: c.hasBoundedWidth ? math.max(natural, c.maxWidth) : natural,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [for (final g in byGroup.values) group(g)],
            ),
          ),
        ),
      );
    }

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
