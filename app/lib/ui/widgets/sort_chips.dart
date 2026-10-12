import 'package:flutter/material.dart';

import '../theme/glass_theme.dart';

/// One level of a waterfall sort as shown on a chip.
class SortChipData {
  final String id;
  final String label;
  final bool ascending;
  const SortChipData(this.id, this.label, {this.ascending = true});
}

/// "Sort  [Date ↓] [Name ↑]  + Add sort": a tap on a chip flips ascending /
/// descending, the cross removes it, a drag onto another chip reorders (the
/// sort is a waterfall, so the order matters). The same behaviour as the
/// Actions "All" panel, for any list.
class SortChipsRow extends StatelessWidget {
  const SortChipsRow({
    super.key,
    required this.chips,
    required this.addOptions,
    required this.onToggle,
    required this.onRemove,
    required this.onMove,
    required this.onAdd,
    this.keyPrefix = 'sort',
  });

  final List<SortChipData> chips;

  /// Levels that can still be added: (id, label).
  final List<(String, String)> addOptions;
  final ValueChanged<int> onToggle;
  final ValueChanged<int> onRemove;
  final void Function(int from, int to) onMove;
  final ValueChanged<String> onAdd;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Sort', style: Theme.of(context).textTheme.titleSmall),
        for (var i = 0; i < chips.length; i++)
          _Chip(
            key: ValueKey('$keyPrefix-chip-${chips[i].id}'),
            index: i,
            data: chips[i],
            onToggle: () => onToggle(i),
            onRemove: () => onRemove(i),
            onMove: onMove,
          ),
        if (addOptions.isNotEmpty)
          PopupMenuButton<String>(
            key: ValueKey('$keyPrefix-add'),
            tooltip: 'Add a sort level',
            onSelected: onAdd,
            itemBuilder: (_) => [
              for (final o in addOptions)
                PopupMenuItem(value: o.$1, child: Text(o.$2)),
            ],
            child: const Chip(
              avatar: Icon(Icons.add, size: 16),
              label: Text('Add sort'),
            ),
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.index,
    required this.data,
    required this.onToggle,
    required this.onRemove,
    required this.onMove,
  });

  final int index;
  final SortChipData data;
  final VoidCallback onToggle;
  final VoidCallback onRemove;
  final void Function(int from, int to) onMove;

  @override
  Widget build(BuildContext context) {
    final chip = InputChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(data.label),
          const SizedBox(width: 4),
          Icon(
            data.ascending ? Icons.arrow_upward : Icons.arrow_downward,
            size: 14,
          ),
        ],
      ),
      tooltip: data.ascending
          ? 'Ascending (tap: descending, drag: reorder)'
          : 'Descending (tap: ascending, drag: reorder)',
      onPressed: onToggle,
      onDeleted: onRemove,
    );
    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => d.data != index,
      onAcceptWithDetails: (d) => onMove(d.data, index),
      builder: (context, candidates, _) => Draggable<int>(
        data: index,
        feedback: Material(
          type: MaterialType.transparency,
          child: Opacity(opacity: 0.8, child: chip),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: chip),
        child: candidates.isEmpty
            ? chip
            : DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(GlassTheme.radiusChip),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                child: chip,
              ),
      ),
    );
  }
}
