import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'date_time_field.dart';

/// Lets you edit an action's start/end time directly
/// by tapping the time shown on a Current Actions board card — the same
/// two fields as "Scheduled start"/"Scheduled end" in
/// the editor's Manual Parameters, just without having to open the full
/// editor first.
class QuickTimeEditDialog extends ConsumerStatefulWidget {
  final String actionId;
  final DateTime? initialStart;
  final DateTime? initialEnd;

  const QuickTimeEditDialog({
    super.key,
    required this.actionId,
    this.initialStart,
    this.initialEnd,
  });

  static Future<void> show(
    BuildContext context, {
    required String actionId,
    DateTime? initialStart,
    DateTime? initialEnd,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => QuickTimeEditDialog(
        actionId: actionId,
        initialStart: initialStart,
        initialEnd: initialEnd,
      ),
    );
  }

  @override
  ConsumerState<QuickTimeEditDialog> createState() =>
      _QuickTimeEditDialogState();
}

class _QuickTimeEditDialogState extends ConsumerState<QuickTimeEditDialog> {
  DateTime? _start;
  DateTime? _end;

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end = widget.initialEnd;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit time'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DateTimeField(
              label: 'Start',
              value: _start,
              includeTime: true,
              onChanged: (v) => setState(() => _start = v),
            ),
            const SizedBox(height: 8),
            DateTimeField(
              label: 'End',
              value: _end,
              includeTime: true,
              onChanged: (v) => setState(() => _end = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  Future<void> _save() async {
    await ref
        .read(actionServiceProvider)
        .updateSchedule(
          widget.actionId,
          startAt: _start,
          endAt: _end,
        );
    if (mounted) Navigator.of(context).pop();
  }
}
