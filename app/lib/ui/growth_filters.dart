import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;

import '../domain/growth_rules.dart';
import '../domain/growth_time.dart';
import 'providers.dart';

// The Growth directions List and Treemap tabs share their search text and type
// filter (and the saved views): change one on a tab and the other follows, and
// it survives a tab switch.

final growthSearchProvider = StateProvider<String>((ref) => '');

final growthKindProvider = StateProvider<MetricKind?>((ref) => null);

/// The Treemap's period (session only; saved with a saved view).
final treemapPeriodProvider = StateProvider<TreemapPeriod>(
  (ref) => TreemapPeriod.month,
);

/// One rectangle of the treemap: a direction and its finished time.
class TreemapBlock {
  const TreemapBlock(this.metric, this.time, this.urgency);
  final GrowthMetric metric;
  final Duration time;
  final double urgency;

  @override
  bool operator ==(Object other) =>
      other is TreemapBlock &&
      other.metric.id == metric.id &&
      other.time == time &&
      other.urgency == urgency;

  @override
  int get hashCode => Object.hash(metric.id, time, urgency);
}

/// What the Treemap draws: the directions that passed the filters and have
/// finished time in the period (biggest first), how many passed the filters
/// but have none, and the sum of the blocks.
class TreemapData {
  const TreemapData({
    required this.blocks,
    required this.withoutTime,
    required this.total,
  });
  final List<TreemapBlock> blocks;
  final int withoutTime;
  final Duration total;

  @override
  bool operator ==(Object other) =>
      other is TreemapData &&
      other.withoutTime == withoutTime &&
      other.total == total &&
      other.blocks.length == blocks.length &&
      [
        for (var i = 0; i < blocks.length; i++) blocks[i] == other.blocks[i],
      ].every((same) => same);

  @override
  int get hashCode => Object.hash(withoutTime, total, blocks.length);
}

/// Finished time per direction for the shared filters and the chosen period,
/// recomputed every minute (the snapshot ticks) and whenever links, directions
/// or the filters change.
final treemapDataProvider = Provider.autoDispose<AsyncValue<TreemapData>>((
  ref,
) {
  final snapshot = ref.watch(growthSnapshotProvider);
  final linked = ref.watch(metricLinkedActionsProvider);
  final period = ref.watch(treemapPeriodProvider);
  final query = ref.watch(growthSearchProvider);
  final kind = ref.watch(growthKindProvider);

  if (snapshot.hasError) {
    return AsyncValue.error(snapshot.error!, snapshot.stackTrace!);
  }
  if (linked.hasError) {
    return AsyncValue.error(linked.error!, linked.stackTrace!);
  }
  if (!snapshot.hasValue || !linked.hasValue) {
    return const AsyncValue.loading();
  }

  final s = snapshot.requireValue;
  final times = timeSpentPerDirection(
    [
      for (final (metricId, action) in linked.requireValue)
        LinkedActionFact.fromAction(metricId, action),
    ],
    nowUtc: DateTime.now().toUtc(),
    period: period,
  );
  final shown = filterDirections(s.metrics, query: query, kind: kind);
  final blocks = <TreemapBlock>[
    for (final m in shown)
      if ((times[m.id] ?? Duration.zero) > Duration.zero)
        TreemapBlock(m, times[m.id]!, s.stats[m.id]?.urgency ?? 0),
  ]..sort((a, b) {
      final byTime = b.time.compareTo(a.time);
      return byTime != 0 ? byTime : a.metric.id.compareTo(b.metric.id);
    });
  return AsyncValue.data(
    TreemapData(
      blocks: blocks,
      withoutTime: shown.length - blocks.length,
      total: blocks.fold(Duration.zero, (sum, b) => sum + b.time),
    ),
  );
});
