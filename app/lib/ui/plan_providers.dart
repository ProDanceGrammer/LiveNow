import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;

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

final planItemsProvider = StreamProvider.autoDispose<List<PlanItem>>(
  (ref) => ref.watch(planServiceProvider).watchItems(),
);

final planCollectionsProvider = StreamProvider.autoDispose<List<PlanCollection>>(
  (ref) => ref.watch(planServiceProvider).watchCollections(),
);

final planOverridesProvider = StreamProvider.autoDispose<List<PlanOverride>>(
  (ref) => ref.watch(planServiceProvider).watchOverrides(),
);

/// The plan occurrences on the viewed range; EMPTY (and nothing watched) while
/// planning mode is off, so the plain calendar pays nothing for plans.
final planOccurrencesProvider =
    FutureProvider.autoDispose<List<PlanOccurrence>>((ref) async {
      if (!ref.watch(calendarPlanningProvider)) return const [];
      final rows = await ref.watch(planItemsProvider.future);
      final collections = await ref.watch(planCollectionsProvider.future);
      ref.watch(planOverridesProvider);
      final start = ref.watch(calendarRangeStartProvider);
      final days = ref.watch(calendarDayCountProvider);
      // Occurrences that STARTED up to a week before the first visible day may
      // still run into it (a sleep 22:00-07:00): the ghost layer draws only the
      // slices that fall on visible days.
      final from = planDateOf(start).subtract(const Duration(days: 7));
      // One day more at the end: a block just after the range can have a
      // Previous action that falls on the last visible day.
      final to = planDateOf(calendarAddDays(start, days));
      final plans = ref.read(planServiceProvider);
      // Only the items of visible collections (and of none) are drawn.
      final visible = visiblePlanItemIds(
        [for (final r in rows) plans.decode(r)],
        {for (final c in collections) c.id: c.visible},
      );
      return plans.occurrences(from, to, itemIds: visible);
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
