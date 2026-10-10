import 'package:flutter/material.dart';

import '../time_format.dart';
import 'quick_time_edit_dialog.dart';

/// A "Start: `<date/time>`" row with edit/clear controls. [value] and the
/// value passed to [onChanged] are UTC instants; they are shown and edited as
/// wall-clock time in the app time zone. Tapping the text opens
/// the shared [QuickTimeEditDialog] in single-value mode and hands the result
/// back to the form without touching the database. Used by the action editor's
/// "Manual parameters" section.
class DateTimeField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final bool includeTime;
  final ValueChanged<DateTime?> onChanged;

  const DateTimeField({
    super.key,
    required this.label,
    required this.value,
    required this.includeTime,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final text = value == null
        ? 'Not set'
        : formatUtcDateTime(value!, includeTime: includeTime);

    // Just the text: tapping it opens the picker (no separate Pick button).
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Flexible: in a narrow dialog the text wraps instead of overflowing.
        Flexible(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _pick(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('$label: $text'),
            ),
          ),
        ),
        if (value != null)
          IconButton(
            icon: const Icon(Icons.clear, size: 16),
            tooltip: 'Clear',
            visualDensity: VisualDensity.compact,
            onPressed: () => onChanged(null),
          ),
      ],
    );
  }

  Future<void> _pick(BuildContext context) async {
    final result = await QuickTimeEditDialog.pick(
      context,
      start: value,
      isAllDay: !includeTime,
      showEnd: false,
      title: label,
    );
    if (result == null) return;
    onChanged(result.start);
  }
}
