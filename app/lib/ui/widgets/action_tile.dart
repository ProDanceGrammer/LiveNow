import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../../domain/postpone_rules.dart';
import '../providers.dart';

enum _TileAction {
  start,
  finish,
  cancel,
  plusOneHour,
  plusFiveHours,
  prolong,
  afterWork,
  morning,
  workingMorning,
  nextWeek,
  nextMondayMorning,
}

/// One row in a view list: name, a short "when/how long" subtitle, and the
/// Start/Finish/Postpone/Cancel menu.
class ActionTile extends ConsumerWidget {
  final ActionListItem action;
  final VoidCallback? onTap;

  const ActionTile({super.key, required this.action, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subtitleParts = <String>[
      if (action.priority != null) action.priority!,
      if (action.startAt != null) _formatWhen(action),
      if (action.estimatedMinutes != null) '${action.estimatedMinutes}m',
    ];

    return ListTile(
      leading: Icon(_iconFor(action.kind)),
      title: Text(action.name),
      subtitle: subtitleParts.isEmpty ? null : Text(subtitleParts.join(' · ')),
      onTap: onTap,
      trailing: PopupMenuButton<_TileAction>(
        tooltip: 'Actions',
        onSelected: (value) => _handle(ref, value),
        itemBuilder: (context) => const [
          PopupMenuItem(value: _TileAction.start, child: Text('Start')),
          PopupMenuItem(value: _TileAction.finish, child: Text('Finish')),
          PopupMenuDivider(),
          PopupMenuItem(
            value: _TileAction.plusOneHour,
            child: Text('Postpone +1 hour'),
          ),
          PopupMenuItem(
            value: _TileAction.plusFiveHours,
            child: Text('Postpone +5 hours'),
          ),
          PopupMenuItem(
            value: _TileAction.prolong,
            child: Text('Prolong 30 min'),
          ),
          PopupMenuItem(
            value: _TileAction.afterWork,
            child: Text('Postpone: after work (18:00)'),
          ),
          PopupMenuItem(
            value: _TileAction.morning,
            child: Text('Postpone: tomorrow morning'),
          ),
          PopupMenuItem(
            value: _TileAction.workingMorning,
            child: Text('Postpone: next working morning'),
          ),
          PopupMenuItem(
            value: _TileAction.nextWeek,
            child: Text('Postpone: next week'),
          ),
          PopupMenuItem(
            value: _TileAction.nextMondayMorning,
            child: Text('Postpone: next Monday morning'),
          ),
          PopupMenuDivider(),
          PopupMenuItem(value: _TileAction.cancel, child: Text('Cancel')),
        ],
      ),
    );
  }

  String _formatWhen(ActionListItem a) {
    final start = a.startAt!.toLocal();
    final date = '${start.year}-${_two(start.month)}-${_two(start.day)}';
    if (a.isAllDay) return date;
    return '$date ${_two(start.hour)}:${_two(start.minute)}';
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  IconData _iconFor(String kind) => switch (kind) {
    'habit' => Icons.repeat,
    'bad_habit' => Icons.warning_amber,
    _ => Icons.check_circle_outline,
  };

  Future<void> _handle(WidgetRef ref, _TileAction value) {
    final service = ref.read(actionServiceProvider);
    return switch (value) {
      _TileAction.start => service.start(action.id),
      _TileAction.finish => service.finish(action.id),
      _TileAction.cancel => service.cancel(action.id),
      _TileAction.plusOneHour => service.postpone(
        action.id,
        PostponeRule.plusOneHour,
      ),
      _TileAction.plusFiveHours => service.postpone(
        action.id,
        PostponeRule.plusFiveHours,
      ),
      _TileAction.prolong => service.postpone(
        action.id,
        PostponeRule.prolongThirtyMinutes,
      ),
      _TileAction.afterWork => service.postpone(
        action.id,
        PostponeRule.afterWork,
      ),
      _TileAction.morning => service.postpone(
        action.id,
        PostponeRule.morning,
      ),
      _TileAction.workingMorning => service.postpone(
        action.id,
        PostponeRule.workingMorning,
      ),
      _TileAction.nextWeek => service.postpone(
        action.id,
        PostponeRule.nextWeek,
      ),
      _TileAction.nextMondayMorning => service.postpone(
        action.id,
        PostponeRule.nextMondayMorning,
      ),
    };
  }
}
