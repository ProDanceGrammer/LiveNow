import 'package:flutter/material.dart';

import '../../domain/date_range_filter.dart';

String _formatDay(DateTime utc) {
  final d = DateRangeFilter.dayOf(utc);
  String p(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${p(d.month)}-${p(d.day)}';
}

/// "From" and "Until" date buttons (either may stay empty) for a
/// [DateRangeFilter]: only from = starting from that day, only until = up to
/// and including that day, both = between. Used by the Actions "All" panel
/// and the Transactions panel.
class DateRangeFields extends StatelessWidget {
  const DateRangeFields({
    super.key,
    required this.value,
    required this.onChanged,
    this.keyPrefix = 'date',
  });

  final DateRangeFilter value;
  final ValueChanged<DateRangeFilter> onChanged;

  /// Keys: `<prefix>-from`, `<prefix>-until` (and `-clear-from/-until`).
  final String keyPrefix;

  Future<void> _pick(
    BuildContext context, {
    required DateTime? current,
    required ValueChanged<DateTime> onPicked,
  }) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current == null ? DateTime.now() : DateRangeFilter.dayOf(current),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) onPicked(DateRangeFilter.dayStart(picked));
  }

  Widget _button(
    BuildContext context, {
    required String id,
    required String label,
    required DateTime? day,
    required ValueChanged<DateTime> onPicked,
    required VoidCallback onClear,
  }) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      OutlinedButton.icon(
        key: ValueKey('$keyPrefix-$id'),
        icon: const Icon(Icons.event, size: 18),
        label: Text(day == null ? label : '$label ${_formatDay(day)}'),
        onPressed: () =>
            _pick(context, current: day, onPicked: onPicked),
      ),
      if (day != null)
        IconButton(
          key: ValueKey('$keyPrefix-clear-$id'),
          visualDensity: VisualDensity.compact,
          tooltip: 'Clear',
          icon: const Icon(Icons.close, size: 18),
          onPressed: onClear,
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _button(
              context,
              id: 'from',
              label: 'From',
              day: value.from,
              onPicked: (d) => onChanged(value.copyWith(from: d)),
              onClear: () => onChanged(value.copyWith(clearFrom: true)),
            ),
            _button(
              context,
              id: 'until',
              label: 'Until',
              day: value.until,
              onPicked: (d) => onChanged(value.copyWith(until: d)),
              onClear: () => onChanged(value.copyWith(clearUntil: true)),
            ),
          ],
        ),
        if (value.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'The start day is after the end day: nothing can match.',
              key: ValueKey('$keyPrefix-empty-hint'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }
}
