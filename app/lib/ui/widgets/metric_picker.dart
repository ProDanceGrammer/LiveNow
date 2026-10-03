import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../domain/growth_rules.dart';
import '../dialog_stack.dart';
import '../providers.dart';
import '../theme/glass_theme.dart';

/// Chips for the chosen growth directions plus an "Add" button that opens a
/// searchable multi-select. There are hundreds of directions, so a chip per
/// direction (the old picker) doesn't work.
class MetricPicker extends ConsumerWidget {
  /// Heading above the chips; empty = none (the caller supplies its own).
  final String label;
  final Set<String> selectedIds;
  final ValueChanged<Set<String>> onChanged;

  /// A direction that must not be offered (the one being edited).
  final String? excludeId;

  /// When set, tapping a chip's label opens that direction (the chip's x
  /// still removes it).
  final ValueChanged<Metric>? onOpen;

  /// Longer explanation shown as a tooltip on the heading.
  final String? labelTooltip;

  const MetricPicker({
    super.key,
    required this.label,
    this.labelTooltip,
    required this.selectedIds,
    required this.onChanged,
    this.excludeId,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ref.watch(metricsProvider).value ?? const <Metric>[];
    final byId = {for (final m in metrics) m.id: m};
    // Ids of deleted directions can linger in a form; just don't show them.
    final chosen = [
      for (final id in selectedIds)
        if (byId[id] != null) byId[id]!,
    ]..sort((a, b) => a.name.compareTo(b.name));

    Future<void> openSearch() async {
      final result = await showStackedDialog<Set<String>>(
        context: context,
        builder: (_) => _MetricSearchDialog(
          metrics: [
            for (final m in metrics)
              if (m.id != excludeId) m,
          ],
          initial: selectedIds,
        ),
      );
      if (result != null) onChanged(result);
    }

    final hasHeader = label.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasHeader) ...[
          Row(
            children: [
              Expanded(
                child: labelTooltip == null
                    ? Text(label, style: Theme.of(context).textTheme.titleSmall)
                    : Tooltip(
                        message: labelTooltip!,
                        child: Text(
                          label,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Add…',
                visualDensity: VisualDensity.compact,
                onPressed: openSearch,
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],
        if (chosen.isEmpty)
          Text('None', style: TextStyle(color: context.glass.textSecondary))
        else
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final m in chosen)
                InputChip(
                  label: Text(metricLabel(m.name, m.icon)),
                  tooltip: onOpen == null ? null : 'Open this direction',
                  onPressed: onOpen == null ? null : () => onOpen!(m),
                  onDeleted: () => onChanged({...selectedIds}..remove(m.id)),
                ),
            ],
          ),
        if (!hasHeader)
          TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add…'),
            onPressed: openSearch,
          ),
      ],
    );
  }
}

class _MetricSearchDialog extends StatefulWidget {
  final List<Metric> metrics;
  final Set<String> initial;

  const _MetricSearchDialog({required this.metrics, required this.initial});

  @override
  State<_MetricSearchDialog> createState() => _MetricSearchDialogState();
}

class _MetricSearchDialogState extends State<_MetricSearchDialog> {
  late final Set<String> _selected = {...widget.initial};
  String _query = '';

  String _subtitle(Metric m) {
    if (m.kind == 'boolean') return 'Boolean';
    return '${m.kind} · ${m.timeWindow} · target ${_num(m.target)}';
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final shown = [
      for (final m in widget.metrics)
        if (query.isEmpty || m.name.toLowerCase().contains(query)) m,
    ]..sort((a, b) => a.name.compareTo(b.name));

    return AlertDialog(
      title: const Text('Choose growth directions'),
      content: SizedBox(
        width: 460,
        height: 460,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Search',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            Expanded(
              child: shown.isEmpty
                  ? const Center(child: Text('No matching directions.'))
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (context, i) {
                        final m = shown[i];
                        return CheckboxListTile(
                          dense: true,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              GlassTheme.radiusChip,
                            ),
                          ),
                          tileColor: _selected.contains(m.id)
                              ? Theme.of(context).colorScheme.primary
                                    .withValues(alpha: 0.10)
                              : null,
                          value: _selected.contains(m.id),
                          title: Text(metricLabel(m.name, m.icon)),
                          subtitle: Text(_subtitle(m)),
                          onChanged: (on) => setState(() {
                            if (on == true) {
                              _selected.add(m.id);
                            } else {
                              _selected.remove(m.id);
                            }
                          }),
                        );
                      },
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
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selected),
          child: Text('Done (${_selected.length})'),
        ),
      ],
    );
  }
}

/// 7 -> "7", 2.5 -> "2.5".
String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : '$v';

/// Short description of a direction's type and target, e.g. "hours · week · 56".
String describeDirection(GrowthMetric m) {
  if (m.kind == MetricKind.boolean) return 'Boolean';
  final unit = m.kind == MetricKind.hours ? 'hours' : 'actions';
  final window = switch (m.window) {
    MetricWindow.week => 'per week',
    MetricWindow.month => 'per 30 days',
    MetricWindow.year => 'per year',
    MetricWindow.fiveYears => 'per 5 years',
    null => '',
  };
  return '${_num(m.target)} $unit $window'.trim();
}
