import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../edit_action.dart';
import '../providers.dart';
import 'action_tile.dart' show iconForAction, twoDigits;
import 'quick_action_bar.dart';
import 'quick_time_edit_dialog.dart';

/// One card on the Current Actions board: name, its current time range
/// (`start_at` -> `end_at` — kept in sync with the real started/finished
/// time by Start/Finish, so there's a single time to show and to postpone,
/// not a separate "scheduled" one), and the quick-action buttons inline —
/// no menu to open first. Tapping anywhere on the card opens the full
/// editor; tapping the time specifically opens a quick date/time picker
/// instead.
class ActionCard extends ConsumerWidget {
  final ActionListItem action;

  const ActionCard({super.key, required this.action});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isRunning = ref
        .watch(runningOccurrencesProvider)
        .value
        ?.contains(action.id) ?? false;
    final timeLine = _formatTimeRange(action);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        onTap: () => openActionEditor(context, ref, action.id),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
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
              if (timeLine != null)
                Padding(
                  padding: const EdgeInsets.only(left: 28, top: 2),
                  child: InkWell(
                    onTap: () => QuickTimeEditDialog.show(
                      context,
                      actionId: action.id,
                      initialStart: action.startAt,
                      initialEnd: action.endAt,
                      initialEstimatedMinutes: action.estimatedMinutes,
                    ),
                    child: Text(
                      timeLine,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.secondary,
                        decoration: TextDecoration.underline,
                        decorationColor: Theme.of(
                          context,
                        ).colorScheme.secondary.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              QuickActionBar(actionId: action.id),
            ],
          ),
        ),
      ),
    );
  }

  /// Independently shows a date on the start and/or the end whenever that
  /// side isn't today — showing it only when start/end differ *from each
  /// other* (the old behaviour) meant a range entirely in the past could
  /// render with no date at all, which is exactly the confusing case.
  /// Appends the estimated duration (the same value `QuickTimeEditDialog`
  /// and the editor's Manual Parameters edit) when it's set.
  String? _formatTimeRange(ActionListItem a) {
    if (a.startAt == null) return null;
    final start = a.startAt!.toLocal();
    final today = DateTime.now();
    final startStr = _sameDay(start, today)
        ? _time(start)
        : '${_date(start)} ${_time(start)}';

    final String range;
    if (a.endAt == null) {
      range = startStr;
    } else {
      final end = a.endAt!.toLocal();
      final endStr = _sameDay(end, today)
          ? _time(end)
          : '${_date(end)} ${_time(end)}';
      range = '$startStr → $endStr';
    }
    return a.estimatedMinutes != null
        ? '$range · ${a.estimatedMinutes}m'
        : range;
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _date(DateTime d) =>
      '${d.year}-${twoDigits(d.month)}-${twoDigits(d.day)}';
  String _time(DateTime d) => '${twoDigits(d.hour)}:${twoDigits(d.minute)}';
}
