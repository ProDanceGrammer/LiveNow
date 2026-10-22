import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/date_range_filter.dart';
import '../../domain/duration_rules.dart';
import '../../domain/growth_plan.dart';
import '../../domain/growth_rules.dart';
import '../../domain/growth_time.dart';
import '../../domain/saved_views.dart'
    show ViewScreens, dateRangeFromJson, dateRangeToJson;
import '../../domain/treemap_layout.dart';
import '../device_prefs.dart';
import '../layout.dart' show kFabClearance;
import '../growth_filters.dart';
import '../providers.dart';
import '../saved_views_bar.dart';
import '../urgency_colors.dart';
import 'date_range_fields.dart';
import 'direction_badge.dart' show emojiLabelStyle;
import 'growth_direction_dialog.dart';
import 'glass.dart';
import 'growth_filters_bar.dart';
import 'treemap_canvas.dart';
import 'treemap_planned_view.dart';

export 'treemap_canvas.dart' show kTreemapGap;

/// A block shows text only when it is at least this big (below it, the
/// direction's emoji, when it has one and fits).
const double kTreemapMinTextW = 64;
const double kTreemapMinTextH = 36;

/// The Treemap tab of Growth directions. Two modes: TIME SPENT (every direction
/// is a rectangle whose AREA is the time of its finished linked actions over the
/// chosen period or custom dates; boolean and count directions too) and PLANNED
/// HOURS (the hours directions' targets turned into hours for a day / week /
/// month / year or custom dates, against the hours available). Blocks are
/// coloured by urgency like the mindmap. Search and type filters are the List's,
/// shared with it.
class TreemapView extends ConsumerStatefulWidget {
  const TreemapView({super.key});

  @override
  ConsumerState<TreemapView> createState() => _TreemapViewState();
}

class _TreemapViewState extends ConsumerState<TreemapView> {
  /// The filter panel is hidden until asked for (session only).
  bool _showFilters = false;

  /// Saved views share the List's screen key: the type filter is common; the
  /// mode, the period, the dates and the plan settings are stored with it. A
  /// view without a key leaves that setting alone, except the dates and the mode
  /// (a view defines both: a view saved before they existed means "time spent,
  /// no custom dates").
  SavedViewHooks _hooks(WidgetRef ref) => SavedViewHooks(
    screen: ViewScreens.growthList,
    readFilter: () {
      final ids = ref.read(plannedIncludedProvider);
      return {
        'kind': ref.read(growthKindProvider)?.name,
        'period': ref.read(treemapPeriodProvider).name,
        'mode': ref.read(treemapModeProvider).name,
        'span': ref.read(plannedSpanProvider).name,
        'range': dateRangeToJson(ref.read(treemapRangeProvider)),
        'planHours': ref.read(plannedHoursPerDayProvider),
        'planIds': ids == null ? null : (ids.toList()..sort()),
      };
    },
    applyFilter: (j) {
      ref.read(growthKindProvider.notifier).state = MetricKind.values
          .where((m) => m.name == j['kind'])
          .firstOrNull;
      final p = TreemapPeriod.byName(j['period']);
      if (p != null) ref.read(treemapPeriodProvider.notifier).state = p;
      ref.read(treemapModeProvider.notifier).state =
          TreemapMode.byName(j['mode']) ?? TreemapMode.time;
      final s = PlanSpan.byName(j['span']);
      if (s != null) ref.read(plannedSpanProvider.notifier).state = s;
      ref.read(treemapRangeProvider.notifier).state = dateRangeFromJson(
        j['range'],
      );
      final prefs = ref.read(devicePrefsProvider.notifier);
      final hours = j['planHours'];
      if (hours is num && hours > 0 && hours <= 24) {
        prefs.set(kPlanHoursKey, hours.toDouble());
      }
      if (j.containsKey('planIds')) {
        final ids = j['planIds'];
        prefs.set(
          kPlanIncludedKey,
          ids is List ? [for (final x in ids) if (x is String) x] : null,
        );
      }
    },
    clearFilter: () {
      ref.read(growthKindProvider.notifier).state = null;
      ref.read(treemapRangeProvider.notifier).state = const DateRangeFilter();
      ref.read(treemapModeProvider.notifier).state = TreemapMode.time;
    },
  );

  /// True when something other than the defaults is set, so the closed Filters
  /// button still tells that the chart is filtered.
  bool _filtering() =>
      ref.watch(treemapModeProvider) != TreemapMode.time ||
      ref.watch(treemapRangeProvider).active ||
      ref.watch(treemapPeriodProvider) != TreemapPeriod.month ||
      ref.watch(plannedSpanProvider) != PlanSpan.day ||
      ref.watch(growthKindProvider) != null;

  @override
  Widget build(BuildContext context) {
    final hooks = _hooks(ref);
    final mode = ref.watch(treemapModeProvider);
    final period = ref.watch(treemapPeriodProvider);
    final range = ref.watch(treemapRangeProvider);
    final filtering = _filtering();
    final height = MediaQuery.sizeOf(context).height;
    return SavedViewsDefaultLoader(
      hooks: hooks,
      child: Column(
        // Stretched, so the chip rows start at the left edge (a shrink-wrapped
        // Wrap in a centred Column floated in the middle).
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: GrowthFiltersBar(
              trailing: IconButton(
                key: const ValueKey('treemap-options-toggle'),
                icon: const Icon(Icons.tune),
                isSelected: _showFilters || filtering,
                tooltip: _showFilters ? 'Hide filters' : 'Filters',
                onPressed: () => setState(() => _showFilters = !_showFilters),
              ),
            ),
          ),
          if (_showFilters)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: GlassSurface(
                radius: 16,
                shadow: false,
                blurWindow: false,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: height * 0.4),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SavedViewsBar(hooks: hooks),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              for (final m in TreemapMode.values)
                                ChoiceChip(
                                  key: ValueKey('treemap-mode-${m.name}'),
                                  avatar: Icon(
                                    m == TreemapMode.time
                                        ? Icons.timer_outlined
                                        : Icons.event_note_outlined,
                                    size: 18,
                                  ),
                                  label: Text(m.label),
                                  selected: m == mode,
                                  onSelected: (_) {
                                    ref
                                            .read(treemapModeProvider.notifier)
                                            .state =
                                        m;
                                  },
                                ),
                            ],
                          ),
                        ),
                        if (mode == TreemapMode.time)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                for (final p in TreemapPeriod.values)
                                  ChoiceChip(
                                    key: ValueKey('treemap-period-${p.name}'),
                                    label: Text(p.label),
                                    // Custom dates win over the period chips.
                                    selected: !range.active && p == period,
                                    onSelected: (_) {
                                      ref
                                              .read(
                                                treemapPeriodProvider.notifier,
                                              )
                                              .state =
                                          p;
                                      // A chip is a whole period: it replaces
                                      // custom dates.
                                      ref
                                              .read(
                                                treemapRangeProvider.notifier,
                                              )
                                              .state =
                                          const DateRangeFilter();
                                    },
                                  ),
                                DateRangeFields(
                                  keyPrefix: 'treemap-date',
                                  value: range,
                                  onChanged: (r) {
                                    ref
                                            .read(treemapRangeProvider.notifier)
                                            .state =
                                        r;
                                  },
                                ),
                              ],
                            ),
                          )
                        else
                          const PlannedControls(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Expanded(
            // A new key per mode: switching mode resets the zoom.
            child: KeyedSubtree(
              key: ValueKey(mode),
              child: mode == TreemapMode.time
                  ? ref
                        .watch(treemapDataProvider)
                        .when(
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (e, _) => Center(child: Text('Error: $e')),
                          data: (d) => _TreemapBody(
                            data: d,
                            rangeActive: range.active,
                          ),
                        )
                  : ref
                        .watch(plannedDataProvider)
                        .when(
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (e, _) => Center(child: Text('Error: $e')),
                          data: (d) => PlannedBody(data: d),
                        ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TreemapBody extends ConsumerWidget {
  const _TreemapBody({required this.data, required this.rangeActive});
  final TreemapData data;
  final bool rangeActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasAny = data.blocks.isNotEmpty;
    final summary = StringBuffer(
      hasAny ? 'Total ${formatDuration(data.total)}' : 'No time',
    );
    if (hasAny) {
      summary.write(' · ${data.blocks.length} direction');
      if (data.blocks.length != 1) summary.write('s');
    }
    if (data.withoutTime > 0) summary.write(' · ${data.withoutTime} without time');
    final where = rangeActive ? 'range' : 'period';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  summary.toString(),
                  key: const ValueKey('treemap-summary'),
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Tooltip(
                triggerMode: TooltipTriggerMode.tap,
                showDuration: const Duration(seconds: 6),
                message:
                    'Time of finished actions in the $where. An action linked '
                    'to several directions counts in each of them, so the '
                    'total can be more than your real time.',
                child: const Icon(Icons.info_outline, size: 16),
              ),
            ],
          ),
        ),
        Expanded(
          child: hasAny
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, kFabClearance),
                  child: _TreemapChart(data: data),
                )
              : Center(
                  child: Text(
                    data.withoutTime > 0
                        ? 'No finished time in this $where.'
                        : 'No growth directions match.',
                    key: const ValueKey('treemap-empty'),
                  ),
                ),
        ),
      ],
    );
  }
}

class _TreemapChart extends ConsumerWidget {
  const _TreemapChart({required this.data});
  final TreemapData data;

  static String _share(Duration t, Duration total) {
    if (total.inSeconds == 0) return '';
    final p = t.inSeconds * 100 / total.inSeconds;
    return '${p.toStringAsFixed(p < 10 ? 1 : 0)}%';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final needsData = ref.watch(emptyDirectionIdsProvider);
    final byId = {for (final b in data.blocks) b.metric.id: b};
    return TreemapCanvas(
      items: [
        for (final b in data.blocks)
          TreemapItem(b.metric.id, b.time.inSeconds.toDouble()),
      ],
      tileBuilder: (id, rect) => _tile(byId[id]!, rect, dark, needsData),
    );
  }

  Widget _tile(TreemapBlock b, Rect r, bool dark, IdSet? needsData) {
    final share = _share(b.time, data.total);
    final time = formatDuration(b.time);
    final value = share.isEmpty ? time : '$time · $share';
    return TreemapTile(
      metric: b.metric,
      valueText: value,
      tooltip: '${b.metric.label}\n$time${share.isEmpty ? '' : ' · $share'}',
      colors: needsData?.contains(b.metric.id) ?? false
          ? emptyColors(dark: dark)
          : urgencyColors(b.urgency, dark: dark),
      showText: r.width >= kTreemapMinTextW && r.height >= kTreemapMinTextH,
    );
  }
}

/// One block of a treemap, for either mode: the direction's name and a value
/// line when it has room, otherwise just its emoji; the tooltip says it all and
/// a tap opens the direction.
class TreemapTile extends StatelessWidget {
  const TreemapTile({
    super.key,
    required this.metric,
    required this.valueText,
    required this.tooltip,
    required this.colors,
    required this.showText,
  });

  final GrowthMetric metric;
  final String valueText;
  final String tooltip;
  final ({Color bg, Color fg}) colors;
  final bool showText;

  @override
  Widget build(BuildContext context) {
    final m = metric;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: Material(
        color: colors.bg,
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('treemap-block-${m.id}'),
          onTap: () => GrowthDirectionDialog.show(context, existing: m),
          child: showText
              ? Padding(
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        child: Text(
                          m.label,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: emojiLabelStyle.copyWith(
                            color: colors.fg,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        valueText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.fg, fontSize: 11),
                      ),
                    ],
                  ),
                )
              : _iconOnly(m.icon),
        ),
      ),
    );
  }

  /// Below this side (px) an emoji is no longer legible: the block stays plain.
  static const _minIconSide = 14.0;

  /// A block too small for text shows the direction's emoji instead, as large as
  /// fits (about 60 % of its shorter side, 9-26 px), centred. A direction
  /// without an emoji, or a block smaller than [_minIconSide], stays empty (the
  /// tooltip still names it).
  static Widget _iconOnly(String? icon) {
    final emoji = icon?.trim() ?? '';
    if (emoji.isEmpty) return const SizedBox.expand();
    return LayoutBuilder(
      builder: (context, box) {
        final side = math.min(box.maxWidth, box.maxHeight);
        if (side < _minIconSide) return const SizedBox.expand();
        return Center(
          child: Text(
            emoji,
            key: const ValueKey('treemap-block-icon'),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
            // Dynamic Type must not push it out of a small block.
            textScaler: TextScaler.noScaling,
            style: emojiLabelStyle.copyWith(
              fontSize: (side * 0.6).clamp(9.0, 26.0),
            ),
          ),
        );
      },
    );
  }
}
