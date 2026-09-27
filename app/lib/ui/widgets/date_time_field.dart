import 'package:flutter/material.dart';

/// A "Start: `<date/time>`" row with pick/clear controls. [value] and the
/// value passed to [onChanged] are UTC; the picker itself works in the
/// device's local time, same as any other date/time picker. Shared by the
/// action editor's "Manual parameters" section and the board card's quick
/// time-edit dialog.
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
    final local = value?.toLocal();
    final text = local == null
        ? 'Not set'
        : includeTime
        ? '${_fmtDate(local)} ${_fmtTime(local)}'
        : _fmtDate(local);

    return Row(
      children: [
        Expanded(child: Text('$label: $text')),
        TextButton(
          onPressed: () => _pick(context, local),
          child: const Text('Pick'),
        ),
        if (value != null)
          IconButton(
            icon: const Icon(Icons.clear),
            tooltip: 'Clear',
            onPressed: () => onChanged(null),
          ),
      ],
    );
  }

  Future<void> _pick(BuildContext context, DateTime? currentLocal) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: currentLocal ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null) return;

    if (!includeTime) {
      onChanged(DateTime(date.year, date.month, date.day).toUtc());
      return;
    }

    if (!context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: currentLocal != null
          ? TimeOfDay(hour: currentLocal.hour, minute: currentLocal.minute)
          : TimeOfDay.now(),
    );
    if (time == null) return;

    onChanged(
      DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ).toUtc(),
    );
  }

  String _fmtDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
  String _fmtTime(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';
  String _two(int n) => n.toString().padLeft(2, '0');
}
