import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../../domain/action_service.dart' show ScheduleChange;
import '../../domain/bulk_edit_service.dart';
import '../../domain/bulk_schedule.dart';
import '../dialog_stack.dart';
import '../providers.dart';
import '../../domain/name_sort.dart' show compareIgnoringEmoji;
import '../undo.dart';
import 'activity_picker_dialog.dart';
import 'action_picker_dialog.dart';
import 'app_toast.dart';
import 'metric_picker.dart';
import 'quick_time_edit_dialog.dart';

// The dialogs behind the bulk bar of the All list and the Calendar: the same
// growth directions, the same previous / next action, a date for the selected
// actions. Each one runs through an `runUndoable...Many` helper, so it is one
// transaction and ONE Undo.

String _modeHelp(BulkMode m) => switch (m) {
  BulkMode.add => 'Add to what each action already has',
  BulkMode.remove => 'Remove from each action',
  BulkMode.replace => 'Replace what each action has',
};

Widget _modeSelector(BulkMode mode, ValueChanged<BulkMode> onChanged) =>
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<BulkMode>(
          key: const ValueKey('bulk-mode'),
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: BulkMode.add, label: Text('Add')),
            ButtonSegment(value: BulkMode.remove, label: Text('Remove')),
            ButtonSegment(value: BulkMode.replace, label: Text('Replace')),
          ],
          selected: {mode},
          onSelectionChanged: (s) => onChanged(s.first),
        ),
        const SizedBox(height: 6),
        Text(_modeHelp(mode)),
      ],
    );

// ---- growth directions ------------------------------------------------------

/// Growth directions for [ids]: pick directions and Add / Remove / Replace.
Future<void> runBulkDirections(
  BuildContext context,
  WidgetRef ref,
  List<String> ids,
) async {
  final picked = await showStackedDialog<(BulkMode, Set<String>)>(
    context: context,
    builder: (_) => _BulkDirectionsDialog(count: ids.length),
  );
  if (picked == null || !context.mounted) return;
  await runUndoableSetMetricsMany(
    context,
    ref,
    ids,
    picked.$2.toList(),
    picked.$1,
  );
}

class _BulkDirectionsDialog extends StatefulWidget {
  const _BulkDirectionsDialog({required this.count});

  final int count;

  @override
  State<_BulkDirectionsDialog> createState() => _BulkDirectionsDialogState();
}

class _BulkDirectionsDialogState extends State<_BulkDirectionsDialog> {
  BulkMode _mode = BulkMode.add;
  Set<String> _ids = {};

  @override
  Widget build(BuildContext context) {
    // Replace with nothing chosen clears every direction; Add / Remove need
    // at least one.
    final canApply = _mode == BulkMode.replace || _ids.isNotEmpty;
    return AlertDialog(
      title: Text('Growth directions for ${widget.count} actions'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _modeSelector(_mode, (m) => setState(() => _mode = m)),
              const SizedBox(height: 12),
              MetricPicker(
                label: _mode == BulkMode.replace && _ids.isEmpty
                    ? 'Directions (none = clear them all)'
                    : 'Directions',
                selectedIds: _ids,
                onChanged: (ids) => setState(() => _ids = ids),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('bulk-directions-apply'),
          onPressed: canApply
              ? () => Navigator.of(context).pop((_mode, _ids))
              : null,
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

// ---- countable activity -----------------------------------------------------

/// The countable activity of [ids]: the same searchable picker as the action
/// editor (None clears it, 'New activity...' asks a name).
Future<void> runBulkActivity(
  BuildContext context,
  WidgetRef ref,
  List<String> ids,
) async {
  final service = ref.read(actionServiceProvider);
  // Nothing listens to the (auto-dispose) stream providers here, so read once.
  final db = ref.read(databaseProvider);
  final activities = await (db.select(
    db.countableActivitiesTable,
  )..orderBy([(t) => OrderingTerm.asc(t.name)])).get();
  final templates = [...await db.select(db.actionTemplatesTable).get()]
    ..sort((a, b) => compareIgnoringEmoji(a.name, b.name));
  if (!context.mounted) return;
  final pick = await ActivityPickerDialog.show(
    context,
    activities: activities,
    templates: templates,
  );
  if (pick == null || !context.mounted) return;
  final String? activityId;
  switch (pick) {
    case ActivityPickNone():
      activityId = null;
    case ActivityPickExisting(:final id):
      activityId = id;
    case ActivityPickTemplate(:final name):
      activityId = await service.countableActivityForTemplate(name);
    case ActivityPickNew():
      final name = await _askActivityName(context);
      if (name == null || name.isEmpty || !context.mounted) return;
      activityId = await service.createCountableActivity(name);
  }
  if (!context.mounted) return;
  await runUndoableSetActivityMany(context, ref, ids, activityId);
}

Future<String?> _askActivityName(BuildContext context) {
  final controller = TextEditingController();
  return showStackedDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('New countable activity'),
      content: TextField(
        key: const ValueKey('bulk-activity-name'),
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (v) => Navigator.of(dialogContext).pop(v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(controller.text.trim()),
          child: const Text('Create'),
        ),
      ],
    ),
  );
}

// ---- previous / next --------------------------------------------------------

/// The Previous (or Next) action of [ids]: choose ONE action and Add / Remove /
/// Replace it.
Future<void> runBulkLinks(
  BuildContext context,
  WidgetRef ref,
  List<String> ids,
  LinkSide side,
) async {
  final picked = await showStackedDialog<(BulkMode, String?)>(
    context: context,
    builder: (_) => _BulkLinksDialog(ids: ids, side: side),
  );
  if (picked == null || !context.mounted) return;
  await runUndoableLinkMany(
    context,
    ref,
    ids,
    targetId: picked.$2,
    side: side,
    mode: picked.$1,
  );
}

class _BulkLinksDialog extends StatefulWidget {
  const _BulkLinksDialog({required this.ids, required this.side});

  final List<String> ids;
  final LinkSide side;

  @override
  State<_BulkLinksDialog> createState() => _BulkLinksDialogState();
}

class _BulkLinksDialogState extends State<_BulkLinksDialog> {
  BulkMode _mode = BulkMode.add;
  ActionListItem? _target;

  Future<void> _choose() async {
    final a = await ActionPickerDialog.show(
      context,
      excludeIds: widget.ids.toSet(),
      
    );
    if (a != null && mounted) setState(() => _target = a);
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.side == LinkSide.previous ? 'Previous' : 'Next';
    final canApply = _mode == BulkMode.replace || _target != null;
    return AlertDialog(
      title: Text('$label action for ${widget.ids.length} actions'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _modeSelector(_mode, (m) => setState(() => _mode = m)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('bulk-links-choose'),
                    icon: const Icon(Icons.link),
                    label: Text(
                      _target?.name ??
                          (_mode == BulkMode.replace
                              ? 'Choose an action (none = clear)'
                              : 'Choose an action'),
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: _choose,
                  ),
                ),
                if (_target != null)
                  IconButton(
                    tooltip: 'No action',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _target = null),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('bulk-links-apply'),
          onPressed: canApply
              ? () => Navigator.of(context).pop((_mode, _target?.id))
              : null,
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

// ---- date -------------------------------------------------------------------

/// A date for [items]: asks "Set date" or "Shift by", then runs it. One Undo.
Future<void> runBulkDate(
  BuildContext context,
  WidgetRef ref,
  List<ActionListItem> items,
) async {
  if (items.isEmpty) return;
  final how = await showStackedDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Date for ${items.length} actions'),
      content: const Text(
        'Set date: the earliest selected action starts at the date you pick '
        'and the others keep their distance to it.\n\n'
        'Shift by: every action moves by the same amount.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        OutlinedButton(
          key: const ValueKey('bulk-date-shift'),
          onPressed: () => Navigator.of(ctx).pop('shift'),
          child: const Text('Shift by…'),
        ),
        FilledButton(
          key: const ValueKey('bulk-date-set'),
          onPressed: () => Navigator.of(ctx).pop('set'),
          child: const Text('Set date…'),
        ),
      ],
    ),
  );
  if (how == null || !context.mounted) return;
  if (how == 'set') {
    await runBulkSetDate(context, ref, items);
  } else {
    await runBulkShift(context, ref, items);
  }
}

/// "Set date": [items]' EARLIEST action starts at the picked date and time, the
/// others move by the same amount (they keep their distance to it).
Future<void> runBulkSetDate(
  BuildContext context,
  WidgetRef ref,
  List<ActionListItem> items,
) async {
  if (items.isEmpty) return;
  final overlay = rootOverlayOf(context);
  ActionListItem? first;
  for (final a in items) {
    if (a.startAt == null) continue;
    if (first == null || a.startAt!.isBefore(first.startAt!)) first = a;
  }
  if (first == null) {
    showInfoToast(overlay, 'None of the selected actions has a date');
    return;
  }
  final r = await QuickTimeEditDialog.pick(
    context,
    start: first.startAt,
    isAllDay: first.isAllDay,
    showEnd: false,
    title: 'Start of the earliest selected action',
  );
  final chosen = r?.start;
  if (chosen == null || !context.mounted) return;
  await _applySchedule(context, ref, bulkSetDate(items, chosen));
}

/// "Shift by": every action in [items] moves by the same amount of time.
Future<void> runBulkShift(
  BuildContext context,
  WidgetRef ref,
  List<ActionListItem> items,
) async {
  if (items.isEmpty) return;
  final shift = await showStackedDialog<ShiftAmount>(
    context: context,
    builder: (_) => const _ShiftDialog(),
  );
  if (shift == null || !context.mounted) return;
  await _applySchedule(context, ref, bulkShift(items, shift));
}

Future<void> _applySchedule(
  BuildContext context,
  WidgetRef ref,
  BulkSchedule schedule,
) async {
  final overlay = rootOverlayOf(context);
  if (schedule.changes.isEmpty) {
    showInfoToast(
      overlay,
      schedule.skipped > 0
          ? 'Nothing changed (${schedule.skipped} without a date)'
          : 'Nothing changed',
    );
    return;
  }
  await runUndoableMoveMany(
    context,
    ref,
    <ScheduleChange>[...schedule.changes],
    description: schedule.changes.length == 1
        ? 'Date changed'
        : 'Date changed for ${schedule.changes.length} actions',
  );
}

class _ShiftDialog extends StatefulWidget {
  const _ShiftDialog();

  @override
  State<_ShiftDialog> createState() => _ShiftDialogState();
}

class _ShiftDialogState extends State<_ShiftDialog> {
  final _months = TextEditingController(text: '0');
  final _weeks = TextEditingController(text: '0');
  final _days = TextEditingController(text: '1');
  final _hours = TextEditingController(text: '0');
  bool _later = true;

  @override
  void dispose() {
    _months.dispose();
    _weeks.dispose();
    _days.dispose();
    _hours.dispose();
    super.dispose();
  }

  ShiftAmount get _value {
    int n(TextEditingController c) => int.tryParse(c.text) ?? 0;
    final d = ShiftAmount(
      months: n(_months),
      days: n(_weeks) * 7 + n(_days),
      hours: n(_hours),
    );
    return _later ? d : d.negated;
  }

  Widget _field(String key, String label, TextEditingController c) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TextField(
        key: ValueKey(key),
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label, isDense: true),
        onChanged: (_) => setState(() {}),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Shift by'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<bool>(
              key: const ValueKey('shift-direction'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('Earlier')),
                ButtonSegment(value: true, label: Text('Later')),
              ],
              selected: {_later},
              onSelectionChanged: (s) => setState(() => _later = s.first),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _field('shift-months', 'Months', _months),
                _field('shift-weeks', 'Weeks', _weeks),
                _field('shift-days', 'Days', _days),
                _field('shift-hours', 'Hours', _hours),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('shift-apply'),
          onPressed: _value.isZero
              ? null
              : () => Navigator.of(context).pop(_value),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
