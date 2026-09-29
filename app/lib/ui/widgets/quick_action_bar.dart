import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/postpone_rules.dart';
import '../providers.dart';
import '../undo.dart';

/// The Start/Finish/Postpone actions as a row of small emoji buttons, shown
/// directly on a Current Actions board card — no menu to open first.
class QuickActionBar extends ConsumerWidget {
  final String actionId;

  const QuickActionBar({super.key, required this.actionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(actionServiceProvider);

    Future<void> run(String description, Future<void> Function() operation) =>
        runUndoable(context, ref, actionId, description, operation);

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _EmojiButton(
          '▶️',
          'Start',
          () => run('Started', () => service.start(actionId)),
        ),
        _EmojiButton(
          '🏁',
          'Finish',
          () => run('Finished', () => service.finish(actionId)),
        ),
        _EmojiButton(
          '⏭️',
          'Continue with same action',
          () => runUndoableContinue(context, ref, actionId),
        ),
        // A visible gap here separates "act on it now" (above) from
        // "postpone" (below) — those two groups being right next to each
        // other, in small tightly-packed buttons, was the likely cause of
        // mis-clicking Finish while aiming for a postpone option.
        const SizedBox(width: 10),
        _EmojiButton(
          '⏳',
          'Prolong 30 min',
          () => run(
            'Prolonged 30 min',
            () => service.postpone(actionId, PostponeRule.prolongThirtyMinutes),
          ),
        ),
        _EmojiButton(
          '🕐➕',
          'Postpone +1 hour',
          () => run(
            'Postponed +1 hour',
            () => service.postpone(actionId, PostponeRule.plusOneHour),
          ),
        ),
        _EmojiButton(
          '🕔➕',
          'Postpone +5 hours',
          () => run(
            'Postponed +5 hours',
            () => service.postpone(actionId, PostponeRule.plusFiveHours),
          ),
        ),
        _EmojiButton(
          '💼🌇',
          'Postpone: after work (18:00)',
          () => run(
            'Postponed to after work',
            () => service.postpone(actionId, PostponeRule.afterWork),
          ),
        ),
        _EmojiButton(
          '🌅',
          'Postpone: tomorrow morning',
          () => run(
            'Postponed to tomorrow morning',
            () => service.postpone(actionId, PostponeRule.morning),
          ),
        ),
        _EmojiButton(
          '💼🌅',
          'Postpone: next working morning',
          () => run(
            'Postponed to next working morning',
            () => service.postpone(actionId, PostponeRule.workingMorning),
          ),
        ),
        _EmojiButton(
          '7⃣📅',
          'Postpone: next week',
          () => run(
            'Postponed to next week',
            () => service.postpone(actionId, PostponeRule.nextWeek),
          ),
        ),
        _EmojiButton(
          '🗓️🌅',
          'Postpone: next Monday morning',
          () => run(
            'Postponed to next Monday morning',
            () => service.postpone(actionId, PostponeRule.nextMondayMorning),
          ),
        ),
        // Set apart from the everyday buttons so it isn't hit by accident;
        // Undo (snackbar / Ctrl+Z) is the safety net, not a confirmation.
        const SizedBox(width: 10),
        _EmojiButton.icon(
          Icon(
            Icons.delete_outline,
            size: 20,
            color: Theme.of(context).colorScheme.error,
          ),
          'Delete',
          () => runUndoableDelete(context, ref, actionId),
        ),
      ],
    );
  }
}

class _EmojiButton extends StatelessWidget {
  final String? emoji;
  final Widget? icon;
  final String tooltip;
  final Future<void> Function() onTap;

  const _EmojiButton(String this.emoji, this.tooltip, this.onTap) : icon = null;

  const _EmojiButton.icon(Widget this.icon, this.tooltip, this.onTap)
    : emoji = null;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        // A fixed, generous size (not just padding around the glyph) so
        // every button — whether a single emoji or a wider composite one —
        // gets the same large, predictable hit target. The previous
        // padding-only sizing gave narrower glyphs a noticeably smaller tap
        // area, making the wrong neighbor easy to hit.
        child: SizedBox(
          width: 36,
          height: 36,
          child: Center(
            child: icon ?? Text(emoji!, style: const TextStyle(fontSize: 16)),
          ),
        ),
      ),
    );
  }
}
