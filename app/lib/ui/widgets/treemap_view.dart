import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/duration_rules.dart';
import '../../domain/growth_rules.dart';
import '../../domain/growth_time.dart';
import '../../domain/saved_views.dart' show ViewScreens;
import '../../domain/treemap_layout.dart';
import '../growth_filters.dart';
import '../providers.dart';
import '../saved_views_bar.dart';
import '../urgency_colors.dart';
import 'direction_badge.dart' show emojiLabelStyle;
import 'growth_direction_dialog.dart';
import 'growth_filters_bar.dart';

/// The Treemap tab of Growth directions: every direction is a rectangle whose
/// AREA is the time of its finished linked actions over the chosen period
/// (boolean and count directions too), coloured by urgency like the mindmap.
/// Filters are the List's, shared with it.
class TreemapView extends ConsumerWidget {
  const TreemapView({super.key});

  /// Saved views share the List's screen key: the type filter is common, the
  /// period is stored with it (a view without one leaves the period alone);
  /// there is no sort.
  SavedViewHooks _hooks(WidgetRef ref) => SavedViewHooks(
    screen: ViewScreens.growthList,
    readFilter: () => {
      'kind': ref.read(growthKindProvider)?.name,
      'period': ref.read(treemapPeriodProvider).name,
    },
    applyFilter: (j) {
      ref.read(growthKindProvider.notifier).state = MetricKind.values
          .where((m) => m.name == j['kind'])
          .firstOrNull;
      final p = TreemapPeriod.byName(j['period']);
      if (p != null) ref.read(treemapPeriodProvider.notifier).state = p;
    },
    clearFilter: () => ref.read(growthKindProvider.notifier).state = null,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hooks = _hooks(ref);
    final period = ref.watch(treemapPeriodProvider);
    final data = ref.watch(treemapDataProvider);
    return SavedViewsDefaultLoader(
      hooks: hooks,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: GrowthFiltersBar(),
          ),
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
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final p in TreemapPeriod.values)
                  ChoiceChip(
                    key: ValueKey('treemap-period-${p.name}'),
                    label: Text(p.label),
                    selected: p == period,
                    onSelected: (_) =>
                        ref.read(treemapPeriodProvider.notifier).state = p,
                  ),
              ],
            ),
          ),
          Expanded(
            child: data.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (d) => _TreemapBody(data: d),
            ),
          ),
        ],
      ),
    );
  }
}

class _TreemapBody extends ConsumerWidget {
  const _TreemapBody({required this.data});
  final TreemapData data;

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
              const Tooltip(
                triggerMode: TooltipTriggerMode.tap,
                showDuration: Duration(seconds: 6),
                message:
                    'Time of finished actions in the period. An action linked '
                    'to several directions counts in each of them, so the '
                    'total can be more than your real time.',
                child: Icon(Icons.info_outline, size: 16),
              ),
            ],
          ),
        ),
        Expanded(
          child: hasAny
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: _TreemapChart(data: data),
                )
              : Center(
                  child: Text(
                    data.withoutTime > 0
                        ? 'No finished time in this period.'
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

  /// A block shows text only when it is at least this big.
  static const _minTextW = 64.0;
  static const _minTextH = 36.0;
  static const _gap = 1.5;

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
    return LayoutBuilder(
      builder: (context, box) {
        final rects = squarify(
          [
            for (final b in data.blocks)
              TreemapItem(b.metric.id, b.time.inSeconds.toDouble()),
          ],
          width: box.maxWidth,
          height: box.maxHeight,
        );
        return SizedBox(
          width: box.maxWidth,
          height: box.maxHeight,
          child: Stack(
            children: [
              for (final r in rects)
                Positioned(
                  left: r.x + _gap / 2,
                  top: r.y + _gap / 2,
                  width: (r.w - _gap).clamp(0.0, double.infinity),
                  height: (r.h - _gap).clamp(0.0, double.infinity),
                  child: _Block(
                    block: byId[r.id]!,
                    share: _share(byId[r.id]!.time, data.total),
                    colors: needsData?.contains(r.id) ?? false
                        ? emptyColors(dark: dark)
                        : urgencyColors(byId[r.id]!.urgency, dark: dark),
                    showText: r.w - _gap >= _minTextW && r.h - _gap >= _minTextH,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({
    required this.block,
    required this.share,
    required this.colors,
    required this.showText,
  });

  final TreemapBlock block;
  final String share;
  final ({Color bg, Color fg}) colors;
  final bool showText;

  @override
  Widget build(BuildContext context) {
    final m = block.metric;
    final time = formatDuration(block.time);
    return Tooltip(
      message: '${m.label}\n$time${share.isEmpty ? '' : ' · $share'}',
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
                        share.isEmpty ? time : '$time · $share',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.fg, fontSize: 11),
                      ),
                    ],
                  ),
                )
              : const SizedBox.expand(),
        ),
      ),
    );
  }
}
