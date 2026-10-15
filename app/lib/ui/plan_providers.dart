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
      final from = planDateOf(start);
      final to = planDateOf(calendarAddDays(start, days - 1));
      final plans = ref.read(planServiceProvider);
      // Only the items of visible collections (and of none) are drawn.
      final visible = visiblePlanItemIds(
        [for (final r in rows) plans.decode(r)],
        {for (final c in collections) c.id: c.visible},
      );
      return plans.occurrences(from, to, itemIds: visible);
    });
