import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/time_codec.dart';
import '../../data/queries.dart' show ActionListItem;
import '../dialog_stack.dart';
import '../providers.dart';
import '../time_format.dart';

/// A searchable "Choose an action" dialog (name search + short schedule
/// subtitles). Pops the chosen [ActionListItem], or null on Cancel.
///
/// By default only open (not done) actions are listed; [includeDone] lists ALL
/// actions, finished and past ones too. [excludeIds] are left out.
class ActionPickerDialog extends ConsumerStatefulWidget {
  final Set<String> excludeIds;
  final bool includeDone;

  const ActionPickerDialog({
    super.key,
    this.excludeIds = const {},
    this.includeDone = false,
  });

  static Future<ActionListItem?> show(
    BuildContext context, {
    Set<String> excludeIds = const {},
    bool includeDone = false,
  }) {
    return showStackedDialog<ActionListItem>(
      context: context,
      builder: (_) =>
          ActionPickerDialog(excludeIds: excludeIds, includeDone: includeDone),
    );
  }

  @override
  ConsumerState<ActionPickerDialog> createState() => _ActionPickerDialogState();
}

class _ActionPickerDialogState extends ConsumerState<ActionPickerDialog> {
  String _query = '';

  AsyncValue<List<ActionListItem>> _items() {
    if (widget.includeDone) return ref.watch(allActionsProvider);
    return ref
        .watch(openActionsProvider)
        .whenData(
          (rows) => [
            for (final a in rows)
              ActionListItem(
                id: a.id,
                name: a.name,
                done: a.done,
                startAt: dateTimeFromDb(a.startAt),
                endAt: dateTimeFromDb(a.endAt),
                isAllDay: a.isAllDay,
                estimatedMinutes: a.estimatedMinutes,
              ),
          ],
        );
  }

  Widget? _scheduleText(ActionListItem a) {
    final text = formatShortSchedule(a.startAt, a.endAt, isAllDay: a.isAllDay);
    return text == null ? null : Text(text);
  }

  @override
  Widget build(BuildContext context) {
    final actionsAsync = _items();

    return AlertDialog(
      title: const Text('Choose an action'),
      content: SizedBox(
        width: math.min(640.0, MediaQuery.sizeOf(context).width - 80),
        height: 400,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(labelText: 'Search'),
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
            ),
            Expanded(
              child: actionsAsync.when(
                data: (items) {
                  final filtered = items
                      .where(
                        (a) =>
                            !widget.excludeIds.contains(a.id) &&
                            a.name.toLowerCase().contains(_query),
                      )
                      .toList();
                  return ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, i) => ListTile(
                      title: Text(filtered[i].name),
                      subtitle: _scheduleText(filtered[i]),
                      onTap: () => Navigator.of(context).pop(filtered[i]),
                    ),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
