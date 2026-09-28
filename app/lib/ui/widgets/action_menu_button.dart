import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/postpone_rules.dart';
import '../providers.dart';
import '../undo.dart';

enum _MenuAction {
  start,
  finish,
  plusOneHour,
  plusFiveHours,
  prolong,
  afterWork,
  morning,
  workingMorning,
  nextWeek,
  nextMondayMorning,
}

/// The Start/Finish/Postpone menu for one action. Shared by
/// [ActionTile] (a trailing 3-dot menu) and the Current Actions board's
/// cards, so the button list only lives in one place.
class ActionMenuButton extends ConsumerWidget {
  final String actionId;

  const ActionMenuButton({super.key, required this.actionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<_MenuAction>(
      tooltip: 'Actions',
      onSelected: (value) => _handle(context, ref, value),
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
      ],
    );
  }

  Future<void> _handle(BuildContext context, WidgetRef ref, _MenuAction value) {
    final service = ref.read(actionServiceProvider);
    Future<void> run(String description, Future<void> Function() operation) =>
        runUndoable(context, ref, actionId, description, operation);

    return switch (value) {
      _MenuAction.start => run('Started', () => service.start(actionId)),
      _MenuAction.finish => run('Finished', () => service.finish(actionId)),
      _MenuAction.plusOneHour => run(
        'Postponed +1 hour',
        () => service.postpone(actionId, PostponeRule.plusOneHour),
      ),
      _MenuAction.plusFiveHours => run(
        'Postponed +5 hours',
        () => service.postpone(actionId, PostponeRule.plusFiveHours),
      ),
      _MenuAction.prolong => run(
        'Prolonged 30 min',
        () => service.postpone(actionId, PostponeRule.prolongThirtyMinutes),
      ),
      _MenuAction.afterWork => run(
        'Postponed to after work',
        () => service.postpone(actionId, PostponeRule.afterWork),
      ),
      _MenuAction.morning => run(
        'Postponed to tomorrow morning',
        () => service.postpone(actionId, PostponeRule.morning),
      ),
      _MenuAction.workingMorning => run(
        'Postponed to next working morning',
        () => service.postpone(actionId, PostponeRule.workingMorning),
      ),
      _MenuAction.nextWeek => run(
        'Postponed to next week',
        () => service.postpone(actionId, PostponeRule.nextWeek),
      ),
      _MenuAction.nextMondayMorning => run(
        'Postponed to next Monday morning',
        () => service.postpone(actionId, PostponeRule.nextMondayMorning),
      ),
    };
  }
}
