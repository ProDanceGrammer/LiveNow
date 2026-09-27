import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/postpone_rules.dart';
import '../providers.dart';

/// The Start/Finish/Postpone/Cancel actions as a row of small emoji buttons,
/// shown directly on a Current Actions board card — no menu to open first.
class QuickActionBar extends ConsumerWidget {
  final String actionId;

  const QuickActionBar({super.key, required this.actionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(actionServiceProvider);

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _EmojiButton('▶️', 'Start', () => service.start(actionId)),
        _EmojiButton('🏁', 'Finish', () => service.finish(actionId)),
        _EmojiButton('❌', 'Cancel', () => service.cancel(actionId)),
        // A visible gap here separates "act on it now" (above) from
        // "postpone" (below) — those two groups being right next to each
        // other, in small tightly-packed buttons, was the likely cause of
        // mis-clicking Finish/Cancel while aiming for a postpone option.
        const SizedBox(width: 10),
        _EmojiButton(
          '⏳',
          'Prolong 30 min',
          () => service.postpone(actionId, PostponeRule.prolongThirtyMinutes),
        ),
        _EmojiButton(
          '🕐➕',
          'Postpone +1 hour',
          () => service.postpone(actionId, PostponeRule.plusOneHour),
        ),
        _EmojiButton(
          '🕔➕',
          'Postpone +5 hours',
          () => service.postpone(actionId, PostponeRule.plusFiveHours),
        ),
        _EmojiButton(
          '💼🌇',
          'Postpone: after work (18:00)',
          () => service.postpone(actionId, PostponeRule.afterWork),
        ),
        _EmojiButton(
          '🌅',
          'Postpone: tomorrow morning',
          () => service.postpone(actionId, PostponeRule.morning),
        ),
        _EmojiButton(
          '💼🌅',
          'Postpone: next working morning',
          () => service.postpone(actionId, PostponeRule.workingMorning),
        ),
        _EmojiButton(
          '7⃣📅',
          'Postpone: next week',
          () => service.postpone(actionId, PostponeRule.nextWeek),
        ),
        _EmojiButton(
          '🗓️🌅',
          'Postpone: next Monday morning',
          () => service.postpone(actionId, PostponeRule.nextMondayMorning),
        ),
      ],
    );
  }
}

class _EmojiButton extends StatelessWidget {
  final String emoji;
  final String tooltip;
  final Future<void> Function() onTap;

  const _EmojiButton(this.emoji, this.tooltip, this.onTap);

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
            child: Text(emoji, style: const TextStyle(fontSize: 16)),
          ),
        ),
      ),
    );
  }
}
