import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../edit_action.dart';
import 'action_menu_button.dart';
import 'action_tile.dart' show formatScheduledWhen, iconForAction, twoDigits;

/// One card on the Current Actions board. A done card shows the actual
/// started → finished time (from `action_occurrences`); a not-done card
/// shows "Started HH:mm" while running, otherwise the scheduled time, if
/// any is set.
class ActionCard extends ConsumerWidget {
  final CurrentActionCard card;

  const ActionCard({super.key, required this.card});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = card.action;
    final isRunning =
        card.occurrenceStartedAt != null && card.occurrenceFinishedAt == null;
    final timeLine = _timeLine();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: Icon(
          iconForAction(action, isRunning),
          color: isRunning ? Theme.of(context).colorScheme.primary : null,
        ),
        title: Text(action.name),
        subtitle: timeLine == null ? null : Text(timeLine),
        onTap: () => openActionEditor(context, ref, action.id),
        trailing: ActionMenuButton(actionId: action.id),
      ),
    );
  }

  String? _timeLine() {
    final started = card.occurrenceStartedAt;
    if (started != null) {
      return _formatRange(started, card.occurrenceFinishedAt);
    }
    if (card.action.startAt != null) {
      return formatScheduledWhen(card.action);
    }
    return null;
  }

  String _formatRange(DateTime startUtc, DateTime? finishedUtc) {
    final start = startUtc.toLocal();
    final now = DateTime.now();
    final startStr = _sameDay(start, now)
        ? _time(start)
        : '${_date(start)} ${_time(start)}';
    if (finishedUtc == null) return '$startStr → running';

    final finished = finishedUtc.toLocal();
    final finishedStr = _sameDay(finished, start)
        ? _time(finished)
        : '${_date(finished)} ${_time(finished)}';
    return '$startStr → $finishedStr';
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _date(DateTime d) => '${d.year}-${twoDigits(d.month)}-${twoDigits(d.day)}';
  String _time(DateTime d) => '${twoDigits(d.hour)}:${twoDigits(d.minute)}';
}
