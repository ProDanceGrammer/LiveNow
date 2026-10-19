import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/capped_read.dart';
import '../../domain/growth_rules.dart';
import '../../domain/growth_time.dart' show filterDirections;
import '../calendar_fullscreen.dart';
import '../growth_filters.dart';
import '../layout.dart';
import '../providers.dart';
import '../saved_views_bar.dart';
import '../../domain/saved_views.dart' show ViewScreens;
import '../theme/glass_theme.dart';
import '../widgets/glass.dart';
import '../widgets/growth_direction_dialog.dart';
import '../widgets/growth_filters_bar.dart';
import '../widgets/metric_picker.dart' show describeDirection;
import '../widgets/mindmap_view.dart';
import '../widgets/param_icons.dart';
import '../widgets/treemap_view.dart';

/// Asks the user for saved Notion pages (.htm) and returns their texts (empty
/// = cancelled). Several files are allowed: a saved page only contains the
/// rows Notion had rendered, so different scroll positions are saved apart.
/// A provider so tests can replace the native file dialog.
final notionPagesPickerProvider = Provider<Future<List<String>> Function()>(
  (ref) => () async {
    final files = await openFiles(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Saved Notion page or name<TAB>emoji list',
          extensions: ['htm', 'html', 'tsv', 'txt'],
          uniformTypeIdentifiers: [
            'public.html',
            'public.text',
            'public.tab-separated-values-text',
          ],
        ),
      ],
    );
    return [for (final f in files) await readTextCapped(f)];
  },
);

/// Asks the user for the Notion export and returns its text (null = cancelled).
/// A provider so tests can replace the native file dialog.
final growthCsvPickerProvider = Provider<Future<String?> Function()>(
  (ref) => () async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'CSV',
          extensions: ['csv'],
          // iOS ignores extensions: it needs type identifiers (without them
          // the picker shows nothing selectable).
          uniformTypeIdentifiers: [
            'public.comma-separated-values-text',
            'public.text',
          ],
          mimeTypes: ['text/csv', 'text/plain'],
        ),
      ],
    );
    return file == null ? null : readTextCapped(file);
  },
);

String _fmt(double v, [int digits = 1]) => v.toStringAsFixed(digits);

/// The growth directions: a Balance Dashboard of what to focus on and what to
/// ease off, the full list, and the mindmap of how they lead to each other.
class GrowthDirectionsScreen extends ConsumerWidget {
  const GrowthDirectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Phone: a full-screen Mindmap hides the tabs and the new-direction button.
    final full = usePhoneLayout(context) && ref.watch(phoneMindmapFullProvider);
    return DefaultTabController(
      length: 4,
      animationDuration: Duration.zero,
      child: Scaffold(
        body: Column(
          children: [
            if (!full)
              Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
                      child: GlassSurface(
                        radius: 20,
                        shadow: false,
                        blurWindow: false,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.all(
                            Radius.circular(20),
                          ),
                          child: TabBar(
                            splashFactory: NoSplash.splashFactory,
                            tabs: [
                              for (final (icon, label) in const [
                                (Icons.balance, 'Balance'),
                                (Icons.grid_view_rounded, 'Treemap'),
                                (Icons.view_list_rounded, 'List'),
                                (Icons.account_tree, 'Mindmap'),
                              ])
                                Tab(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(icon, size: 18),
                                      const SizedBox(width: 6),
                                      // Shrinks (with an ellipsis) instead of
                                      // overflowing a narrow tab.
                                      Flexible(
                                        child: Text(
                                          label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            const Expanded(
              child: TabBarView(
                // No swiping between tabs: horizontal drags belong to the
                // Mindmap (moving boxes, panning).
                physics: NeverScrollableScrollPhysics(),
                children: [
                  _BalanceTab(),
                  TreemapView(),
                  _ListTab(),
                  MindmapView(),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: full
            ? null
            : FloatingActionButton(
                heroTag: null,
                onPressed: () => GrowthDirectionDialog.show(context),
                tooltip: 'New growth direction',
                child: const Icon(Icons.add),
              ),
      ),
    );
  }

}

// ---- Balance ----------------------------------------------------------------

class _BalanceTab extends ConsumerWidget {
  const _BalanceTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(growthSnapshotProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (snapshot) {
            if (snapshot.metrics.isEmpty) {
              return const Center(
                child: Text(
                  'No growth directions yet — add one or import a CSV.',
                ),
              );
            }
            return LayoutBuilder(
              builder: (context, box) {
                final wide = box.maxWidth >= 900;
                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    for (final group in BalanceGroup.values)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _BalanceBoard(
                                      group: group,
                                      side: BalanceSide.focusOn,
                                      snapshot: snapshot,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _BalanceBoard(
                                      group: group,
                                      side: BalanceSide.decreaseIt,
                                      snapshot: snapshot,
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                children: [
                                  _BalanceBoard(
                                    group: group,
                                    side: BalanceSide.focusOn,
                                    snapshot: snapshot,
                                  ),
                                  const SizedBox(height: 12),
                                  _BalanceBoard(
                                    group: group,
                                    side: BalanceSide.decreaseIt,
                                    snapshot: snapshot,
                                  ),
                                ],
                              ),
                      ),
                  ],
                );
              },
            );
          },
        );
  }
}

/// One dashboard board, e.g. "Focus On (Weekly)": the top rows by urgency,
/// "Show more", and the average progress of the whole board.
class _BalanceBoard extends StatefulWidget {
  final BalanceGroup group;
  final BalanceSide side;
  final GrowthSnapshot snapshot;

  _BalanceBoard({
    required this.group,
    required this.side,
    required this.snapshot,
  }) : super(key: ValueKey('board-${side.name}-${group.name}'));

  @override
  State<_BalanceBoard> createState() => _BalanceBoardState();
}

class _BalanceBoardState extends State<_BalanceBoard> {
  int _shown = kBalancePageSize;

  static const _groupLabel = {
    BalanceGroup.daily: 'Daily',
    BalanceGroup.weekly: 'Weekly',
    BalanceGroup.monthly: 'Monthly',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = balanceBoard(
      widget.group,
      widget.side,
      widget.snapshot.metrics,
      widget.snapshot.stats,
    );
    final title =
        '${widget.side == BalanceSide.focusOn ? 'Focus On' : 'Decrease It'}'
        ' (${_groupLabel[widget.group]})';
    final average = averageProgress(rows);
    final headerStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final phone = usePhoneLayout(context);

    // Rows stay plain (no per-row surface): the board is ONE glass panel, and
    // a transparent Material inside it hosts the rows' ink.
    return GlassSurface(
      radius: GlassTheme.radiusPanel,
      shadow: false,
      blurWindow: false,
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(title, style: theme.textTheme.titleMedium),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(
                  children: [
                    // Every column name sits in the middle of its column.
                    Expanded(
                      child: Align(
                        alignment: Alignment.center,
                        child: ParamLabel(Param.direction, style: headerStyle),
                      ),
                    ),
                    SizedBox(
                      width: phone ? 64 : 72,
                      child: Align(
                        alignment: Alignment.center,
                        child: ParamIcon(
                          Param.urgency,
                          size: 22,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: phone ? 82 : 120,
                      child: Padding(
                        padding: EdgeInsets.only(left: phone ? 6 : 12),
                        child: const Align(
                          alignment: Alignment.center,
                          child: ParamIcon(Param.progress),
                        ),
                      ),
                    ),
                    // The weight column is left out on a phone (the room goes
                    // to the name); it is in the direction's dialog.
                    if (!phone)
                      const SizedBox(
                        width: 56,
                        child: Align(
                          alignment: Alignment.center,
                          child: ParamIcon(Param.weight),
                        ),
                      ),
                    // The level ring is desktop-only too (phone: no room).
                    if (!phone)
                      const SizedBox(
                        width: 32,
                        child: Align(
                          alignment: Alignment.center,
                          child: ParamIcon(Param.level),
                        ),
                      ),
                  ],
                ),
              ),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Nothing here.'),
                )
              else
                for (final r in rows.take(_shown)) _BalanceRowTile(row: r),
              if (rows.length > _shown)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setState(() => _shown += kBalancePageSize),
                    child: Text('Show more (${rows.length - _shown})'),
                  ),
                ),
              if (average != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  child: Text(
                    'AVERAGE ${_fmt(average, 2)}',
                    key: ValueKey(
                      'average-${widget.side.name}-${widget.group.name}',
                    ),
                    style: headerStyle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BalanceRowTile extends StatelessWidget {
  final BalanceRow row;

  const _BalanceRowTile({required this.row});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = row.metric;
    final s = row.stat;
    final phone = usePhoneLayout(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => GrowthDirectionDialog.show(context, existing: m),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                m.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: phone ? 64 : 72,
              // One line always: a long number shrinks instead of wrapping,
              // the name (Expanded, ellipsis) gives way instead.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  _fmt(s.urgency),
                  maxLines: 1,
                  softWrap: false,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: s.urgency < 0 ? theme.colorScheme.tertiary : null,
                  ),
                ),
              ),
            ),
            SizedBox(
              width: phone ? 82 : 120,
              child: Padding(
                padding: EdgeInsets.only(left: phone ? 6 : 12),
                child: _ProgressBar(progress: s.progress),
              ),
            ),
            if (!phone)
              SizedBox(
                width: 56,
                child: Text(
                  m.weight.round().toString(),
                  textAlign: TextAlign.right,
                ),
              ),
            if (!phone)
              SizedBox(
                width: 32,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _LevelRing(level: m.importanceLevel),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The percentage as text over a bar that stops at 100%.
class _ProgressBar extends StatelessWidget {
  final double progress;

  const _ProgressBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_fmt(progress), style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 2),
        LinearProgressIndicator(
          value: (progress / 100).clamp(0.0, 1.0),
          minHeight: 4,
          borderRadius: BorderRadius.circular(2),
          backgroundColor: Theme.of(context).colorScheme.primary
              .withValues(alpha: 0.15),
        ),
      ],
    );
  }
}

/// The importance level (0-10) as a small ring with the number inside.
class _LevelRing extends StatelessWidget {
  final int level;

  const _LevelRing({required this.level});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 24,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: (level / kMainImportanceLevel).clamp(0.0, 1.0),
            strokeWidth: 2.5,
          ),
          Text('$level', style: const TextStyle(fontSize: 10)),
        ],
      ),
    );
  }
}

// ---- List -------------------------------------------------------------------

enum _Sort { urgency, progress, weight, name }

class _ListTab extends ConsumerStatefulWidget {
  const _ListTab();

  @override
  ConsumerState<_ListTab> createState() => _ListTabState();
}

class _ListTabState extends ConsumerState<_ListTab> {
  _Sort _sort = _Sort.urgency;

  /// Saved views: the sort is one of four orders, the filter the type.
  SavedViewHooks _viewHooks() => SavedViewHooks(
    screen: ViewScreens.growthList,
    readSort: () => {'sort': _sort.name},
    applySort: (j) => setState(
      () => _sort = _Sort.values.firstWhere(
        (s) => s.name == j['sort'],
        orElse: () => _Sort.urgency,
      ),
    ),
    clearSort: () => setState(() => _sort = _Sort.urgency),
    // The type filter is shared with the Treemap tab.
    readFilter: () => {'kind': ref.read(growthKindProvider)?.name},
    applyFilter: (j) {
      final k = j['kind'];
      ref.read(growthKindProvider.notifier).state = MetricKind.values
          .where((m) => m.name == k)
          .firstOrNull;
    },
    clearFilter: () => ref.read(growthKindProvider.notifier).state = null,
  );

  @override
  Widget build(BuildContext context) {
    return SavedViewsDefaultLoader(
      hooks: _viewHooks(),
      child: _buildList(context),
    );
  }

  Widget _buildList(BuildContext context) {
    return ref
        .watch(growthSnapshotProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (snapshot) {
            final items = filterDirections(
              snapshot.metrics,
              query: ref.watch(growthSearchProvider),
              kind: ref.watch(growthKindProvider),
            );
            double stat(GrowthMetric m, double Function(MetricStat) f) =>
                f(snapshot.stats[m.id]!);
            items.sort((a, b) {
              switch (_sort) {
                case _Sort.urgency:
                  return stat(
                    b,
                    (s) => s.urgency,
                  ).compareTo(stat(a, (s) => s.urgency));
                case _Sort.progress:
                  return stat(
                    b,
                    (s) => s.progress,
                  ).compareTo(stat(a, (s) => s.progress));
                case _Sort.weight:
                  return b.weight.compareTo(a.weight);
                case _Sort.name:
                  return a.name.compareTo(b.name);
              }
            });

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: GrowthFiltersBar(
                    beforeKind: [
                      DropdownButton<_Sort>(
                        isExpanded: usePhoneLayout(context),
                        dropdownColor: context.glass.fillDialog,
                        borderRadius: BorderRadius.circular(14),
                        value: _sort,
                        items: const [
                          DropdownMenuItem(
                            value: _Sort.urgency,
                            child: Text('Most urgent'),
                          ),
                          DropdownMenuItem(
                            value: _Sort.progress,
                            child: Text('Highest progress'),
                          ),
                          DropdownMenuItem(
                            value: _Sort.weight,
                            child: Text('Heaviest'),
                          ),
                          DropdownMenuItem(
                            value: _Sort.name,
                            child: Text('Name'),
                          ),
                        ],
                        onChanged: (v) => setState(() => _sort = v!),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SavedViewsBar(hooks: _viewHooks()),
                  ),
                ),
                Expanded(
                  child: items.isEmpty
                      ? const Center(child: Text('No growth directions match.'))
                      : ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (context, i) {
                            final m = items[i];
                            final s = snapshot.stats[m.id]!;
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(12, 3, 12, 3),
                              child: GlassSurface(
                                radius: GlassTheme.radiusControl,
                                shadow: false,
                                blurWindow: false,
                                child: Material(
                                  type: MaterialType.transparency,
                                  child: ListTile(
                                    key: ValueKey('direction-${m.id}'),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        GlassTheme.radiusControl,
                                      ),
                                    ),
                                    title: Text(m.label),
                                    subtitle: Text.rich(
                                      TextSpan(
                                        children: [
                                          TextSpan(
                                            text:
                                                '${describeDirection(m)}'
                                                '${m.isMain ? ' · main' : ''}'
                                                ' · ',
                                          ),
                                          WidgetSpan(
                                            alignment:
                                                PlaceholderAlignment.middle,
                                            child: ParamValue.weight(
                                              '${m.weight.round()}',
                                              size: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    trailing: SizedBox(
                                      width: usePhoneLayout(context)
                                          ? 130
                                          : 190,
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: usePhoneLayout(context)
                                                ? 70
                                                : 110,
                                            child: _ProgressBar(
                                              progress: s.progress,
                                            ),
                                          ),
                                          Expanded(
                                            child: Align(
                                              alignment: Alignment.centerRight,
                                              child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: ParamValue.urgency(
                                                  _fmt(s.urgency),
                                                  size: 18,
                                                  style: DefaultTextStyle.of(
                                                    context,
                                                  ).style,
                                                  color: DefaultTextStyle.of(
                                                    context,
                                                  ).style.color,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    onTap: () => GrowthDirectionDialog.show(
                                      context,
                                      existing: m,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
  }
}
