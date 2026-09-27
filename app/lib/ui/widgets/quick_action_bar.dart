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
      spacing: 2,
      runSpacing: 2,
      children: [
        _EmojiButton('▶️', 'Start', () => service.start(actionId)),
        _EmojiButton('🏁', 'Finish', () => service.finish(actionId)),
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
        _EmojiButton('❌', 'Cancel', () => service.cancel(actionId)),
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
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Text(emoji, style: const TextStyle(fontSize: 15)),
        ),
      ),
    );
  }
}
