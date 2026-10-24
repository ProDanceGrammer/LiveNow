import '../../domain/search_match.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../domain/growth_rules.dart';
import '../dialog_stack.dart';
import '../providers.dart';
import '../theme/glass_theme.dart';
import 'action_tile.dart' show formatUrgency;
import 'direction_badge.dart' show emojiLabelStyle;
import 'growth_direction_dialog.dart';
import 'param_icons.dart';

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

  /// Offers "New…": creates a growth direction in its own dialog and adds it
  /// to the selection.
  final bool allowCreate;

  const MetricPicker({
    super.key,
    required this.label,
    this.labelTooltip,
    required this.selectedIds,
    required this.onChanged,
    this.excludeId,
    this.onOpen,
    this.allowCreate = false,
    this.showUrgency = false,
    this.showNone = true,
    this.textStyle,
  });

  /// Overrides the text of the chips and of the "Add…" button (the form builder
  /// sets its own size; null = the app's).
  final TextStyle? textStyle;

  /// Whether an empty selection reads "None" (the form builder leaves the space
  /// empty instead: next to "Adds:" it only looked like a value).
  final bool showNone;

  /// Shows each direction's "Urgency to Keep in Balance" before its chip.
  final bool showUrgency;

  /// The same searchable multi-select the picker's "Add…" opens, for a screen
  /// that keeps its own selection (the Treemap's planned-hours directions).
  /// Returns the chosen ids, or null when cancelled.
  static Future<Set<String>?> pickMany(
    BuildContext context, {
    required List<Metric> candidates,
    required Set<String> initial,
    String title = 'Choose growth directions',
  }) => showStackedDialog<Set<String>>(
    context: context,
    builder: (_) => _MetricSearchDialog(
      metrics: candidates,
      initial: initial,
      title: title,
    ),
  );

  Widget _withUrgency(BuildContext context, MetricStat? stat, Widget chip) {
    if (stat == null) return chip;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ParamValue.urgency(
          formatUrgency(stat.urgency),
          size: 18,
          style: Theme.of(context).textTheme.bodyMedium,
          color: Theme.of(context).textTheme.bodyMedium?.color,
        ),
        const SizedBox(width: 6),
        Flexible(child: chip),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ref.watch(metricsProvider).value ?? const <Metric>[];
    final byId = {for (final m in metrics) m.id: m};
    final stats = showUrgency
        ? ref.watch(growthSnapshotProvider).value?.stats
        : null;
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

    Future<void> createNew() async {
      final id = await GrowthDirectionDialog.show(context);
      if (id != null) onChanged({...selectedIds, id});
    }

    final canCreate = allowCreate && openStackedDialogCount < 3;
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
              if (canCreate)
                IconButton(
                  key: const ValueKey('metric-picker-new'),
                  icon: const Icon(Icons.library_add_outlined),
                  tooltip: 'New growth direction…',
                  visualDensity: VisualDensity.compact,
                  onPressed: createNew,
                ),
            ],
          ),
          const SizedBox(height: 4),
        ],
        if (chosen.isEmpty && showNone)
          Text('None', style: TextStyle(color: context.glass.textSecondary))
        else if (chosen.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final m in chosen)
                _withUrgency(
                  context,
                  stats?[m.id],
                  InputChip(
                    label: Text(
                      metricLabel(m.name, m.icon),
                      style: textStyle == null
                          ? emojiLabelStyle
                          : emojiLabelStyle.merge(textStyle),
                    ),
                    tooltip: onOpen == null ? null : 'Open this direction',
                    onPressed: onOpen == null ? null : () => onOpen!(m),
                    onDeleted: () => onChanged({...selectedIds}..remove(m.id)),
                  ),
                ),
            ],
          ),
        if (!hasHeader)
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: Text('Add…', style: textStyle),
                onPressed: openSearch,
              ),
              if (canCreate)
                TextButton.icon(
                  key: const ValueKey('metric-picker-new'),
                  icon: const Icon(Icons.library_add_outlined),
                  label: const Text('New…'),
                  onPressed: createNew,
                ),
            ],
          ),
      ],
    );
  }
}

class _MetricSearchDialog extends StatefulWidget {
  final List<Metric> metrics;
  final Set<String> initial;
  final String title;

  const _MetricSearchDialog({
    required this.metrics,
    required this.initial,
    this.title = 'Choose growth directions',
  });

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
    // By name; whole-word matches of the typed text first, then the rest.
    final shown = rankMatches(
      [...widget.metrics]..sort((a, b) => a.name.compareTo(b.name)),
      _query,
      (m) => [m.name],
    );

    return AlertDialog(
      title: Text(widget.title),
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
                          title: Text(
                            metricLabel(m.name, m.icon),
                            style: emojiLabelStyle,
                          ),
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
