import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../edit_action.dart';
import '../providers.dart';
import 'action_tile.dart' show iconForAction, twoDigits;
import 'quick_action_bar.dart';

/// One card on the Current Actions board: name, its current time range
/// (`start_at` -> `end_at` — kept in sync with the real started/finished
/// time by Start/Finish, so there's a single time to show and to postpone,
/// not a separate "scheduled" one), and the quick-action buttons inline —
/// no menu to open first.
class ActionCard extends ConsumerWidget {
  final ActionListItem action;

  const ActionCard({super.key, required this.action});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isRunning = ref.watch(runningOccurrencesProvider).value?.containsKey(action.id) ?? false;
    final timeLine = _formatTimeRange(action);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () => openActionEditor(context, ref, action.id),
              child: Row(
                children: [
                  Icon(
                    iconForAction(action, isRunning),
                    size: 20,
                    color: isRunning
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      action.name,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
            ),
            if (timeLine != null)
              Padding(
                padding: const EdgeInsets.only(left: 28, top: 2),
                child: Text(
                  timeLine,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
              ),
            const SizedBox(height: 6),
            QuickActionBar(actionId: action.id),
          ],
        ),
      ),
    );
  }

  String? _formatTimeRange(ActionListItem a) {
    if (a.startAt == null) return null;
    final start = a.startAt!.toLocal();
    final now = DateTime.now();
    final startStr = _sameDay(start, now)
        ? _time(start)
        : '${_date(start)} ${_time(start)}';
    if (a.endAt == null) return startStr;

    final end = a.endAt!.toLocal();
    final endStr = _sameDay(end, start)
        ? _time(end)
        : '${_date(end)} ${_time(end)}';
    return '$startStr → $endStr';
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _date(DateTime d) =>
      '${d.year}-${twoDigits(d.month)}-${twoDigits(d.day)}';
  String _time(DateTime d) => '${twoDigits(d.hour)}:${twoDigits(d.minute)}';
}
