import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/postpone_rules.dart';
import '../providers.dart';

enum _MenuAction {
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

/// The Start/Finish/Postpone/Cancel menu for one action. Shared by
/// [ActionTile] (a trailing 3-dot menu) and the Current Actions board's
/// cards, so the button list only lives in one place.
class ActionMenuButton extends ConsumerWidget {
  final String actionId;

  const ActionMenuButton({super.key, required this.actionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<_MenuAction>(
      tooltip: 'Actions',
      onSelected: (value) => _handle(ref, value),
      itemBuilder: (context) => const [
        PopupMenuItem(value: _MenuAction.start, child: Text('Start')),
        PopupMenuItem(value: _MenuAction.finish, child: Text('Finish')),
        PopupMenuDivider(),
        PopupMenuItem(
          value: _MenuAction.plusOneHour,
          child: Text('Postpone +1 hour'),
        ),
        PopupMenuItem(
          value: _MenuAction.plusFiveHours,
          child: Text('Postpone +5 hours'),
        ),
        PopupMenuItem(
          value: _MenuAction.prolong,
          child: Text('Prolong 30 min'),
        ),
        PopupMenuItem(
          value: _MenuAction.afterWork,
          child: Text('Postpone: after work (18:00)'),
        ),
        PopupMenuItem(
          value: _MenuAction.morning,
          child: Text('Postpone: tomorrow morning'),
        ),
        PopupMenuItem(
          value: _MenuAction.workingMorning,
          child: Text('Postpone: next working morning'),
        ),
        PopupMenuItem(
          value: _MenuAction.nextWeek,
          child: Text('Postpone: next week'),
        ),
        PopupMenuItem(
          value: _MenuAction.nextMondayMorning,
          child: Text('Postpone: next Monday morning'),
        ),
        PopupMenuDivider(),
        PopupMenuItem(value: _MenuAction.cancel, child: Text('Cancel')),
      ],
    );
  }

  Future<void> _handle(WidgetRef ref, _MenuAction value) {
    final service = ref.read(actionServiceProvider);
    return switch (value) {
      _MenuAction.start => service.start(actionId),
      _MenuAction.finish => service.finish(actionId),
      _MenuAction.cancel => service.cancel(actionId),
      _MenuAction.plusOneHour => service.postpone(
        actionId,
        PostponeRule.plusOneHour,
      ),
      _MenuAction.plusFiveHours => service.postpone(
        actionId,
        PostponeRule.plusFiveHours,
      ),
      _MenuAction.prolong => service.postpone(
        actionId,
        PostponeRule.prolongThirtyMinutes,
      ),
      _MenuAction.afterWork => service.postpone(
        actionId,
        PostponeRule.afterWork,
      ),
      _MenuAction.morning => service.postpone(actionId, PostponeRule.morning),
      _MenuAction.workingMorning => service.postpone(
        actionId,
        PostponeRule.workingMorning,
      ),
      _MenuAction.nextWeek => service.postpone(
        actionId,
        PostponeRule.nextWeek,
      ),
      _MenuAction.nextMondayMorning => service.postpone(
        actionId,
        PostponeRule.nextMondayMorning,
      ),
    };
  }
}
