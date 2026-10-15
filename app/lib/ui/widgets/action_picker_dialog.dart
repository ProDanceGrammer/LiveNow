import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart' show ActionTemplate;
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
/// What [ActionPickerDialog.showWithCreate] returns.
sealed class ActionPickResult {
  const ActionPickResult();
}

/// An existing action was chosen.
class ActionPickExisting extends ActionPickResult {
  const ActionPickExisting(this.item);
  final ActionListItem item;
}

/// 'New action...': a blank new action.
class ActionPickNew extends ActionPickResult {
  const ActionPickNew();
}

/// 'New from template...': the caller then asks which template.
class ActionPickFromTemplate extends ActionPickResult {
  const ActionPickFromTemplate();
}

class ActionPickerDialog extends ConsumerStatefulWidget {
  final Set<String> excludeIds;

  /// Pins 'New action...' and 'New from template...' above the list and pops an
  /// [ActionPickResult] instead of the bare action.
  final bool allowCreate;

  const ActionPickerDialog({
    super.key,
    this.excludeIds = const {},
    this.allowCreate = false,
  });

  /// [show] plus the two pinned 'create' rows.
  static Future<ActionPickResult?> showWithCreate(
    BuildContext context, {
    Set<String> excludeIds = const {},
  }) {
    return showStackedDialog<ActionPickResult>(
      context: context,
      builder: (_) =>
          ActionPickerDialog(excludeIds: excludeIds, allowCreate: true),
    );
  }

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
            if (widget.allowCreate) ...[
              ListTile(
                key: const ValueKey('pick-new-action'),
                dense: true,
                leading: const Icon(Icons.add),
                title: const Text('New action...'),
                onTap: () =>
                    Navigator.of(context).pop(const ActionPickNew()),
              ),
              ListTile(
                key: const ValueKey('pick-new-from-template'),
                dense: true,
                leading: const Icon(Icons.copy_all_outlined),
                title: const Text('New from template...'),
                onTap: () =>
                    Navigator.of(context).pop(const ActionPickFromTemplate()),
              ),
            ],
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
                      onTap: () => Navigator.of(context).pop(
                        widget.allowCreate
                            ? ActionPickExisting(filtered[i])
                            : filtered[i],
                      ),
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

/// A searchable "Choose a template" dialog; pops the template id.
class TemplatePickerDialog extends ConsumerStatefulWidget {
  const TemplatePickerDialog({super.key});

  static Future<String?> show(BuildContext context) =>
      showStackedDialog<String>(
        context: context,
        builder: (_) => const TemplatePickerDialog(),
      );

  @override
  ConsumerState<TemplatePickerDialog> createState() =>
      _TemplatePickerDialogState();
}

class _TemplatePickerDialogState extends ConsumerState<TemplatePickerDialog> {
  String _query = '';

  String? _subtitle(ActionTemplate t) {
    try {
      final p = jsonDecode(t.payload) as Map<String, dynamic>;
      if (p['isAllDay'] == true) return 'All day';
      final m = p['estimatedMinutes'];
      return m is int && m > 0 ? '$m min' : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final templates =
        ref.watch(templatesProvider).value ?? const <ActionTemplate>[];
    final shown = [
      for (final t in templates)
        if (t.name.toLowerCase().contains(_query)) t,
    ];
    return AlertDialog(
      title: const Text('Choose a template'),
      content: SizedBox(
        width: math.min(520.0, MediaQuery.sizeOf(context).width - 80),
        height: 400,
        child: Column(
          children: [
            TextField(
              key: const ValueKey('template-pick-search'),
              decoration: const InputDecoration(labelText: 'Search'),
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
            ),
            Expanded(
              child: shown.isEmpty
                  ? const Center(child: Text('No template.'))
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (context, i) => ListTile(
                        key: ValueKey('template-pick-${shown[i].id}'),
                        title: Text(shown[i].name),
                        subtitle: _subtitle(shown[i]) == null
                            ? null
                            : Text(_subtitle(shown[i])!),
                        onTap: () => Navigator.of(context).pop(shown[i].id),
                      ),
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
