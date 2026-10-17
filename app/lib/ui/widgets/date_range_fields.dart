import 'package:flutter/material.dart';

import '../../domain/date_range_filter.dart';

String _formatDay(DateTime utc) {
  final d = DateRangeFilter.dayOf(utc);
  String p(int n) => n.toString().padLeft(2, '0');
  return '${p(d.day)}-${p(d.month)}-${d.year}';
}

/// "From" and "Until" date buttons (either may stay empty) for a
/// [DateRangeFilter]: only from = starting from that day, only until = up to
/// and including that day, both = between. A "Quick dates" menu offers whole
/// periods relative to today (Yesterday, Last week, Rest of this month ...);
/// a chosen one shows as a chip and the buttons show the days it means now.
/// Touching From / Until turns the choice into a custom range. Used by the
/// Actions "All" panel and the Transactions panel.
class DateRangeFields extends StatelessWidget {
  const DateRangeFields({
    super.key,
    required this.value,
    required this.onChanged,
    this.keyPrefix = 'date',
  });

  final DateRangeFilter value;
  final ValueChanged<DateRangeFilter> onChanged;

  /// Keys: `<prefix>-from`, `<prefix>-until` (and `-clear-from/-until`),
  /// `<prefix>-quick` (+ `-quick-<preset name>`), `<prefix>-preset` chip and
  /// `<prefix>-clear-preset`.
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

  Widget _quickMenu() => PopupMenuButton<DatePreset>(
    key: ValueKey('$keyPrefix-quick'),
    tooltip: 'Quick dates',
    onSelected: (p) => onChanged(DateRangeFilter(preset: p)),
    itemBuilder: (_) {
      final items = <PopupMenuEntry<DatePreset>>[];
      String? group;
      for (final p in DatePreset.values) {
        if (p.group != group) {
          if (group != null) items.add(const PopupMenuDivider());
          group = p.group;
        }
        items.add(
          PopupMenuItem(
            key: ValueKey('$keyPrefix-quick-${p.name}'),
            value: p,
            height: 36,
            child: Text(p.label),
          ),
        );
      }
      return items;
    },
    child: IgnorePointer(
      child: OutlinedButton.icon(
        icon: const Icon(Icons.bolt, size: 18),
        label: const Text('Quick dates'),
        onPressed: () {},
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final preset = value.preset;
    final shown = value.resolved();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _quickMenu(),
            if (preset != null)
              InputChip(
                key: ValueKey('$keyPrefix-preset'),
                label: Text(preset.label),
                onDeleted: () => onChanged(value.copyWith(clearPreset: true)),
                deleteButtonTooltipMessage: 'Remove the quick choice',
              ),
            _button(
              context,
              id: 'from',
              label: 'From',
              day: shown.from,
              onPicked: (d) => onChanged(value.copyWith(from: d)),
              onClear: () => onChanged(value.copyWith(clearFrom: true)),
            ),
            _button(
              context,
              id: 'until',
              label: 'Until',
              day: shown.until,
              onPicked: (d) => onChanged(value.copyWith(until: d)),
              onClear: () => onChanged(value.copyWith(clearUntil: true)),
            ),
          ],
        ),
        if (value.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              preset != null
                  ? 'Nothing is left in this period.'
                  : 'The start day is after the end day: nothing can match.',
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
