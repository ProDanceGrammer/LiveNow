import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;

import '../core/error_log.dart';
import '../core/stream_utils.dart';
import '../data/database.dart';
import '../domain/plan_rules.dart';
import '../domain/plan_service.dart';
import 'providers.dart';
import 'views/calendar_layout.dart';

final planServiceProvider = Provider<PlanService>(
  (ref) => PlanService(
    ref.watch(databaseProvider),
    ref.watch(actionServiceProvider),
  ),
);

/// The calendar's planning mode (translucent plan blocks + the plan bar). Not
/// persisted: every start is the plain calendar.
final calendarPlanningProvider = StateProvider<bool>((ref) => false);

/// A write that does not change what a plan query returns (a sync pass, an
/// unrelated row) must not recompute every occurrence; a burst of writes is one
/// recompute.
Stream<List<T>> _calm<T>(Stream<List<T>> s) =>
    debounced(distinctList(s), const Duration(milliseconds: 50));

final planItemsProvider = StreamProvider.autoDispose<List<PlanItem>>(
  (ref) => _calm(ref.watch(planServiceProvider).watchItems()),
);

final planCollectionsProvider = StreamProvider.autoDispose<List<PlanCollection>>(
  (ref) => _calm(ref.watch(planServiceProvider).watchCollections()),
);

final planOverridesProvider = StreamProvider.autoDispose<List<PlanOverride>>(
  (ref) => _calm(ref.watch(planServiceProvider).watchOverrides()),
);

/// The local-date window the plan occurrences are generated for: the viewed
/// range plus a margin, snapped to whole weeks, so moving the view a few days
/// (arrows, scrolling) stays inside it and recomputes nothing.
final planWindowProvider = Provider.autoDispose<({DateTime from, DateTime to})>((
  ref,
) {
  final start = ref.watch(calendarRangeStartProvider);
  final days = ref.watch(calendarDayCountProvider);
  DateTime monday(DateTime d) =>
      d.subtract(Duration(days: d.weekday - DateTime.monday));
  // Occurrences that STARTED up to a week before the first visible day may
  // still run into it (a sleep 22:00-07:00); a block just after the range can
  // have a Previous action that falls on the last visible day. The margin of a
  // week or more on each side covers both.
  final from = monday(planDateOf(start)).subtract(const Duration(days: 14));
  final to = monday(
    planDateOf(calendarAddDays(start, days)),
  ).add(const Duration(days: 14));
  return (from: from, to: to);
});

/// The plan occurrences on the viewed range; EMPTY (and nothing watched) while
/// planning mode is off, so the plain calendar pays nothing for plans. Errors
/// are written to the error log and are not retried silently (a retry loop looks
/// like "loading forever" and the blocks just never appear).
final planOccurrencesProvider =
    FutureProvider.autoDispose<List<PlanOccurrence>>(retry: (_, _) => null, (
      ref,
    ) async {
      if (!ref.watch(calendarPlanningProvider)) return const [];
      try {
        final rows = await ref.watch(planItemsProvider.future);
        final collections = await ref.watch(planCollectionsProvider.future);
        ref.watch(planOverridesProvider);
        final window = ref.watch(planWindowProvider);
        final plans = ref.read(planServiceProvider);
        // Only the items of visible collections (and of none) are drawn.
        final visible = visiblePlanItemIds(
          [for (final r in rows) plans.decode(r)],
          {for (final c in collections) c.id: c.visible},
        );
        return await plans.occurrences(
          window.from,
          window.to,
          itemIds: visible,
        );
      } catch (e, s) {
        await ErrorLog.write(e, s, context: 'planning mode: loading blocks');
        rethrow;
      }
    });

/// Mean real length in minutes of the finished runs (last 30 days, by name) of
/// the plan blocks on the viewed range; key = `normalizeForMatch(name)`, a name
/// without history is absent. One read for the whole range.
final planAveragesProvider = FutureProvider.autoDispose<Map<String, int>>((
  ref,
) async {
  final occurrences = await ref.watch(planOccurrencesProvider.future);
  if (occurrences.isEmpty) return const {};
  final templates = {
    for (final t in ref.watch(templatesProvider).value ?? const []) t.id: t.name,
  };
  final names = <String>{};
  for (final o in occurrences) {
    names.add(o.name);
    for (final c in [...o.extras.prev, ...o.extras.next]) {
      final n = c.name ?? templates[c.templateId];
      if (n != null) names.add(n);
    }
  }
  final averages = await ref
      .read(actionServiceProvider)
      .averagesByName(names);
  return {for (final e in averages.entries) e.key: e.value.inMinutes};
});
