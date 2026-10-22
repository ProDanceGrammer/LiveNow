import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/date_range_filter.dart';
import '../../domain/growth_plan.dart';
import '../../domain/growth_rules.dart';
import '../../domain/treemap_layout.dart';
import '../device_prefs.dart';
import '../growth_filters.dart';
import '../providers.dart';
import '../urgency_colors.dart';
import 'date_range_fields.dart';
import 'metric_picker.dart';
import '../layout.dart' show kFabClearance;
import 'treemap_canvas.dart';
import 'treemap_view.dart' show TreemapTile, kTreemapMinTextH, kTreemapMinTextW;

/// The controls of the planned-hours mode: the span (Day / Week / Month / Year),
/// custom dates (they override the span), the hours available per day, and the
/// choice of which hours directions are in the plan.
class PlannedControls extends ConsumerWidget {
  const PlannedControls({super.key});

  static String _hoursText(double h) =>
      h == h.roundToDouble() ? '${h.round()}' : '$h';

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final rows = ref.read(metricsProvider).value ?? const [];
    final candidates = [
      for (final m in rows)
        if (isPlannable(GrowthMetric.fromRow(m))) m,
    ];
    final included = ref.read(plannedIncludedProvider);
    final result = await MetricPicker.pickMany(
      context,
      candidates: candidates,
      initial: included ?? {for (final m in candidates) m.id},
      title: 'Directions in the plan',
    );
    if (result == null) return;
    ref.read(devicePrefsProvider.notifier).set(kPlanIncludedKey, result.toList()..sort());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final span = ref.watch(plannedSpanProvider);
    final range = ref.watch(treemapRangeProvider);
    final hoursPerDay = ref.watch(plannedHoursPerDayProvider);
    final included = ref.watch(plannedIncludedProvider);
    final rows = ref.watch(metricsProvider).value ?? const [];
    final plannableIds = {
      for (final m in rows)
        if (isPlannable(GrowthMetric.fromRow(m))) m.id,
    };
    final chosen = included == null
        ? plannableIds.length
        : included.where(plannableIds.contains).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final s in PlanSpan.values)
            ChoiceChip(
              key: ValueKey('treemap-span-${s.name}'),
              label: Text(s.label),
              selected: !range.active && s == span,
              onSelected: (_) {
                ref.read(plannedSpanProvider.notifier).state = s;
                // A chip is a whole span: it replaces custom dates.
                ref.read(treemapRangeProvider.notifier).state =
                    const DateRangeFilter();
              },
            ),
          DateRangeFields(
            keyPrefix: 'treemap-date',
            value: range,
            onChanged: (r) => ref.read(treemapRangeProvider.notifier).state = r,
          ),
          SizedBox(
            width: 210,
            child: TextFormField(
              key: const ValueKey('treemap-plan-hours'),
              initialValue: _hoursText(hoursPerDay),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Available hours / day',
                isDense: true,
              ),
              onChanged: (text) {
                final v = double.tryParse(text.trim().replaceAll(',', '.'));
                if (v != null && v > 0 && v <= 24) {
                  ref.read(devicePrefsProvider.notifier).set(kPlanHoursKey, v);
                }
              },
            ),
          ),
          OutlinedButton.icon(
            key: const ValueKey('treemap-plan-pick'),
            icon: const Icon(Icons.checklist_rounded, size: 18),
            label: Text('Directions ($chosen of ${plannableIds.length})'),
            onPressed: () => _pick(context, ref),
          ),
        ],
      ),
    );
  }
}

/// The planned-hours chart with its insight: planned against available hours,
/// where it is overplanned and by how much to cut, and (in each tooltip) what
/// was really spent in the same dates.
class PlannedBody extends ConsumerWidget {
  const PlannedBody({super.key, required this.data});
  final PlannedData data;

  static String _percent(double fraction) {
    final p = fraction * 100;
    return '${p.toStringAsFixed(p < 10 ? 1 : 0)} %';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = data.report;
    Widget message(String key, String text) =>
        Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, key: ValueKey(key), textAlign: TextAlign.center),
        ));

    if (data.range == null) {
      return message(
        'treemap-plan-badrange',
        'To plan over a range, pick both dates (From and Until).',
      );
    }
    if (data.plannable == 0) {
      return message(
        'treemap-plan-none',
        'No hours directions yet. Make a growth direction of type "Hours" '
            'with a target, and it can be planned here.',
      );
    }
    if (report.blocks.isEmpty) {
      return message(
        'treemap-plan-nonechosen',
        'No directions in the plan. Press "Directions" to choose them.',
      );
    }

    final theme = Theme.of(context);
    final days = report.days;
    final over = report.overplanned;
    final summary =
        'Planned ${formatHours(report.total)} of '
        '${formatHours(report.available)} available in '
        '${days == 1 ? 'a day' : '$days days'} · '
        '${report.blocks.length} direction${report.blocks.length == 1 ? '' : 's'}';
    // How far over or under the available hours it is, in the same line.
    final balance = over
        ? ' · ${formatHours(report.over)} over'
        : report.free > 0
        ? ' · ${formatHours(report.free)} free'
        : ' · fits exactly';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Row(
            children: [
              Flexible(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: summary),
                      TextSpan(
                        text: balance,
                        style: over
                            ? TextStyle(
                                color: theme.colorScheme.error,
                                fontWeight: FontWeight.w600,
                              )
                            : null,
                      ),
                    ],
                  ),
                  key: const ValueKey('treemap-planned-summary'),
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              const Tooltip(
                triggerMode: TooltipTriggerMode.tap,
                showDuration: Duration(seconds: 8),
                message:
                    'Planned hours = the target of each hours direction spread '
                    'evenly over its window (56 h per week is 8 h a day). '
                    '"Spent" in a tooltip is finished time in the same dates. '
                    'Directions that contain each other can overlap: choose '
                    'which ones are in the plan.',
                child: Icon(Icons.info_outline, size: 16),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, kFabClearance),
            child: _PlannedChart(data: data),
          ),
        ),
      ],
    );
  }
}

class _PlannedChart extends ConsumerWidget {
  const _PlannedChart({required this.data});
  final PlannedData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final needsData = ref.watch(emptyDirectionIdsProvider);
    final report = data.report;
    final byId = {for (final b in report.blocks) b.metric.id: b};
    return TreemapCanvas(
      items: [for (final b in report.blocks) TreemapItem(b.metric.id, b.hours)],
      tileBuilder: (id, rect) => _tile(byId[id]!, rect, dark, needsData),
    );
  }

  Widget _tile(PlanBlock b, Rect r, bool dark, IdSet? needsData) {
    final m = b.metric;
    final share = PlannedBody._percent(data.report.share(b));
    final spent = data.spentHours[m.id] ?? 0;
    final spentText = spent <= 0
        ? 'spent nothing in these dates'
        : 'spent ${formatHours(spent)} '
              '(${PlannedBody._percent(b.hours <= 0 ? 0 : spent / b.hours)} of the plan)';
    return TreemapTile(
      metric: m,
      valueText: '${formatHours(b.hours)} · $share',
      tooltip: '${m.label}\nplanned ${formatHours(b.hours)} · $share of the available\n$spentText',
      colors: needsData?.contains(m.id) ?? false
          ? emptyColors(dark: dark)
          : urgencyColors(data.urgency[m.id] ?? 0, dark: dark),
      showText: r.width >= kTreemapMinTextW && r.height >= kTreemapMinTextH,
    );
  }
}
