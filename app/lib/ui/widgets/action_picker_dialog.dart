import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart' show ActionListItem;
import '../../domain/name_sort.dart' show compareIgnoringEmoji;
import '../dialog_stack.dart';
import '../providers.dart';
import '../time_format.dart';

/// A searchable "Choose an action" dialog (name search + short schedule
/// subtitles). Pops the chosen [ActionListItem], or null on Cancel.
///
/// It lists EVERY action - open, finished, past, all-day, created from a template
/// or by hand: a previous / next / linked action is very often one that already
/// happened. [excludeIds] are left out. Without a search the nearest in time come
/// first (recent and coming ones on top); a search lists matches by name.
class ActionPickerDialog extends ConsumerStatefulWidget {
  final Set<String> excludeIds;

  const ActionPickerDialog({super.key, this.excludeIds = const {}});

  static Future<ActionListItem?> show(
    BuildContext context, {
    Set<String> excludeIds = const {},
  }) {
    return showStackedDialog<ActionListItem>(
      context: context,
      builder: (_) => ActionPickerDialog(excludeIds: excludeIds),
    );
  }

  @override
  ConsumerState<ActionPickerDialog> createState() => _ActionPickerDialogState();
}

class _ActionPickerDialogState extends ConsumerState<ActionPickerDialog> {
  String _query = '';

  Widget? _scheduleText(ActionListItem a) {
    final text = formatShortSchedule(a.startAt, a.endAt, isAllDay: a.isAllDay);
    return text == null ? null : Text(text);
  }

  @override
  Widget build(BuildContext context) {
    final actionsAsync = ref.watch(allActionsProvider);

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
                  final filtered = pickerOrder(
                    [
                      for (final a in items)
                        if (!widget.excludeIds.contains(a.id) &&
                            a.name.toLowerCase().contains(_query))
                          a,
                    ],
                    searching: _query.trim().isNotEmpty,
                    nowUtc: DateTime.now().toUtc(),
                  );
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

/// The picker's order: with a search the matches by name; without one the actions
/// nearest in time to [nowUtc] first (an action with no date goes last).
List<ActionListItem> pickerOrder(
  List<ActionListItem> items, {
  required bool searching,
  required DateTime nowUtc,
}) {
  final out = [...items];
  if (searching) {
    out.sort((a, b) => compareIgnoringEmoji(a.name, b.name));
  } else {
    int distance(ActionListItem a) => a.startAt == null
        ? 1 << 62
        : a.startAt!.difference(nowUtc).inSeconds.abs();
    out.sort((a, b) {
      final c = distance(a).compareTo(distance(b));
      return c != 0 ? c : compareIgnoringEmoji(a.name, b.name);
    });
  }
  return out;
}
