import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/growth_rules.dart';
import '../providers.dart';
import '../widgets/growth_direction_dialog.dart';
import '../widgets/metric_picker.dart' show describeDirection;

/// Asks the user for the Notion export and returns its text (null = cancelled).
/// A provider so tests can replace the native file dialog.
final growthCsvPickerProvider = Provider<Future<String?> Function()>(
  (ref) => () async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'CSV', extensions: ['csv']),
      ],
    );
    return file?.readAsString();
  },
);

String _fmt(double v, [int digits = 1]) => v.toStringAsFixed(digits);

/// The growth directions: a Balance Dashboard of what to focus on and what to
/// ease off, the full list, and the hierarchy under the main directions.
class GrowthDirectionsScreen extends ConsumerWidget {
  const GrowthDirectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        body: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: TabBar(
                    tabs: [
                      Tab(text: 'Balance'),
                      Tab(text: 'List'),
                      Tab(text: 'Tree'),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.upload_file),
                  tooltip: 'Import growth directions from CSV…',
                  onPressed: () => _import(context, ref),
                ),
              ],
            ),
            const Expanded(
              child: TabBarView(
                children: [_BalanceTab(), _ListTab(), _TreeTab()],
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => GrowthDirectionDialog.show(context),
          tooltip: 'New growth direction',
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  /// Replaces every direction with the ones in a Notion export.
  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final pick = ref.read(growthCsvPickerProvider);
    final service = ref.read(metricServiceProvider);

    final text = await pick();
    if (text == null) return;
    try {
      final s = await service.importGrowthDirections(text);
      final notes = [
        if (s.skippedBlank > 0) '${s.skippedBlank} empty rows skipped',
        if (s.unsupported.isNotEmpty)
          '${s.unsupported.length} with an unknown type skipped',
        if (s.unresolved.isNotEmpty)
          '${s.unresolved.length} unknown relations ignored',
      ];
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Imported ${s.directions} growth directions '
            'and ${s.relations} relations'
            '${notes.isEmpty ? '' : ' (${notes.join(', ')})'}.',
          ),
        ),
      );
    } on FormatException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Import failed: ${e.message}')),
      );
    }
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

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
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
                  Expanded(child: Text('Direction', style: headerStyle)),
                  SizedBox(
                    width: 72,
                    child: Text(
                      'Urgency',
                      style: headerStyle,
                      textAlign: TextAlign.right,
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Text('Progress', style: headerStyle),
                    ),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text(
                      'Weight',
                      style: headerStyle,
                      textAlign: TextAlign.right,
                    ),
                  ),
                  SizedBox(
                    width: 32,
                    child: Text(
                      'Lvl',
                      style: headerStyle,
                      textAlign: TextAlign.right,
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
    return InkWell(
      onTap: () => GrowthDirectionDialog.show(context, existing: m),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(m.name, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            SizedBox(
              width: 72,
              child: Text(
                _fmt(s.urgency),
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: s.urgency < 0 ? theme.colorScheme.tertiary : null,
                ),
              ),
            ),
            SizedBox(
              width: 120,
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: _ProgressBar(progress: s.progress),
              ),
            ),
            SizedBox(
              width: 56,
              child: Text(
                m.weight.round().toString(),
                textAlign: TextAlign.right,
              ),
            ),
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
  String _query = '';
  _Sort _sort = _Sort.urgency;
  MetricKind? _kind;

  @override
  Widget build(BuildContext context) {
    return ref
        .watch(growthSnapshotProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (snapshot) {
            final q = _query.trim().toLowerCase();
            final items = [
              for (final m in snapshot.metrics)
                if ((_kind == null || m.kind == _kind) &&
                    (q.isEmpty || m.name.toLowerCase().contains(q)))
                  m,
            ];
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
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: const InputDecoration(
                            labelText: 'Search',
                            prefixIcon: Icon(Icons.search),
                            isDense: true,
                          ),
                          onChanged: (v) => setState(() => _query = v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      DropdownButton<_Sort>(
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
                      const SizedBox(width: 12),
                      DropdownButton<MetricKind?>(
                        value: _kind,
                        items: const [
                          DropdownMenuItem(
                            value: null,
                            child: Text('All types'),
                          ),
                          DropdownMenuItem(
                            value: MetricKind.count,
                            child: Text('Actions'),
                          ),
                          DropdownMenuItem(
                            value: MetricKind.hours,
                            child: Text('Hours'),
                          ),
                          DropdownMenuItem(
                            value: MetricKind.boolean,
                            child: Text('Boolean'),
                          ),
                        ],
                        onChanged: (v) => setState(() => _kind = v),
                      ),
                    ],
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
                            return ListTile(
                              key: ValueKey('direction-${m.id}'),
                              title: Text(m.name),
                              subtitle: Text(
                                '${describeDirection(m)}'
                                '${m.isMain ? ' · main' : ''}'
                                ' · weight ${m.weight.round()}',
                              ),
                              trailing: SizedBox(
                                width: 190,
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 110,
                                      child: _ProgressBar(progress: s.progress),
                                    ),
                                    Expanded(
                                      child: Text(
                                        'U ${_fmt(s.urgency)}',
                                        textAlign: TextAlign.right,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              onTap: () => GrowthDirectionDialog.show(
                                context,
                                existing: m,
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

// ---- Tree -------------------------------------------------------------------

class _TreeTab extends ConsumerWidget {
  const _TreeTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(growthSnapshotProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (snapshot) {
            // Roots: the main directions, plus anything that leads nowhere.
            final roots =
                [
                  for (final m in snapshot.metrics)
                    if (m.isMain || snapshot.graph.leadsToOf(m.id).isEmpty) m,
                ]..sort((a, b) {
                  if (a.isMain != b.isMain) return a.isMain ? -1 : 1;
                  return a.name.compareTo(b.name);
                });
            if (roots.isEmpty) {
              return const Center(child: Text('No growth directions yet.'));
            }
            return ListView(
              children: [
                for (final m in roots)
                  _TreeNode(snapshot: snapshot, metric: m, path: {m.id}),
              ],
            );
          },
        );
  }
}

/// One direction in the hierarchy; its children are the directions it depends
/// on. A direction that feeds several goals shows under each of them.
class _TreeNode extends StatelessWidget {
  final GrowthSnapshot snapshot;
  final GrowthMetric metric;

  /// Ids from the root down to this node (guards against loops).
  final Set<String> path;

  const _TreeNode({
    required this.snapshot,
    required this.metric,
    required this.path,
  });

  @override
  Widget build(BuildContext context) {
    final stat = snapshot.stats[metric.id]!;
    final title = Row(
      children: [
        Expanded(child: Text(metric.name)),
        const SizedBox(width: 8),
        SizedBox(width: 90, child: _ProgressBar(progress: stat.progress)),
        SizedBox(
          width: 96,
          child: Text('U ${_fmt(stat.urgency)}', textAlign: TextAlign.right),
        ),
      ],
    );
    final children = [
      for (final id in snapshot.graph.dependsOnOf(metric.id))
        if (!path.contains(id) && snapshot.byId[id] != null) snapshot.byId[id]!,
    ]..sort((a, b) => a.name.compareTo(b.name));

    if (children.isEmpty) {
      return ListTile(
        dense: true,
        title: title,
        onTap: () => GrowthDirectionDialog.show(context, existing: metric),
      );
    }
    return ExpansionTile(
      key: PageStorageKey<String>(path.join('/')),
      title: title,
      childrenPadding: const EdgeInsets.only(left: 20),
      children: [
        for (final c in children)
          _TreeNode(snapshot: snapshot, metric: c, path: {...path, c.id}),
      ],
    );
  }
}
