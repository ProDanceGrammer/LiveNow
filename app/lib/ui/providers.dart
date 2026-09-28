import 'package:drift/drift.dart' show OrderingTerm, innerJoin;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:timezone/timezone.dart' as tz;

import '../core/settings.dart';
import '../core/time_codec.dart';
import '../data/database.dart';
import '../data/queries.dart';
import '../domain/action_service.dart';
import '../domain/dependency_service.dart';
import '../domain/done_rule.dart' as done_rule;

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final actionServiceProvider = Provider<ActionService>(
  (ref) => ActionService(ref.watch(databaseProvider)),
);

final dependencyServiceProvider = Provider<DependencyService>(
  (ref) => DependencyService(ref.watch(databaseProvider)),
);

final viewQueriesProvider = Provider<ViewQueries>(
  (ref) => ViewQueries(ref.watch(databaseProvider)),
);

final operationalProvider = StreamProvider.autoDispose<List<ActionListItem>>(
  (ref) => ref.watch(viewQueriesProvider).watchOperational(),
);

final todoProvider = StreamProvider.autoDispose<List<ActionListItem>>(
  (ref) => ref.watch(viewQueriesProvider).watchTodo(),
);

final mostImportantProvider = StreamProvider.autoDispose<List<ActionListItem>>(
  (ref) => ref.watch(viewQueriesProvider).watchMostImportant(),
);

final currentNotDoneProvider = StreamProvider.autoDispose<List<ActionListItem>>(
  (ref) => ref.watch(viewQueriesProvider).watchCurrentNotDone(),
);

final currentDoneProvider = StreamProvider.autoDispose<List<ActionListItem>>(
  (ref) => ref.watch(viewQueriesProvider).watchCurrentDone(),
);

/// The Monday (UTC instant of Istanbul midnight) that starts the currently
/// viewed calendar week.
final calendarWeekStartProvider = StateProvider<DateTime>((ref) {
  final location = tz.getLocation(AppSettings.timeZoneName);
  final now = tz.TZDateTime.now(location);
  final monday = now.subtract(Duration(days: now.weekday - 1));
  return tz.TZDateTime(location, monday.year, monday.month, monday.day).toUtc();
});

final calendarWeekProvider = StreamProvider.autoDispose<List<ActionListItem>>((
  ref,
) {
  final start = ref.watch(calendarWeekStartProvider);
  final end = start.add(const Duration(days: 7));
  return ref
      .watch(viewQueriesProvider)
      .watchCalendarWeek(weekStartUtc: start, weekEndUtc: end);
});

/// All metrics, for the action editor's metric picker.
final metricsProvider = StreamProvider.autoDispose<List<Metric>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.metricsTable).watch();
});

/// All saved "new from template" presets.
final templatesProvider = StreamProvider.autoDispose<List<ActionTemplate>>((
  ref,
) {
  final db = ref.watch(databaseProvider);
  return db.select(db.actionTemplatesTable).watch();
});

/// All not-done actions, for the action editor's predecessor/successor
/// picker.
final openActionsProvider = StreamProvider.autoDispose<List<ActionRow>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.actionsTable).watch().map(
    (rows) => rows
        .where(
          (a) => !done_rule.isDoneBefore(
            startAt: dateTimeFromDb(a.startAt),
            endAt: dateTimeFromDb(a.endAt),
            isAllDay: a.isAllDay,
            done: a.done,
          ),
        )
        .toList(),
  );
});

/// The actions that must happen before [actionId] (its current predecessors).
final predecessorsOfProvider = StreamProvider.autoDispose
    .family<List<ActionRow>, String>((ref, actionId) {
      final db = ref.watch(databaseProvider);
      final query =
          db.select(db.actionsTable).join([
              innerJoin(
                db.actionDependenciesTable,
                db.actionDependenciesTable.predecessorId.equalsExp(
                  db.actionsTable.id,
                ),
              ),
            ])
            ..where(db.actionDependenciesTable.successorId.equals(actionId));
      return query.watch().map(
        (rows) => rows.map((r) => r.readTable(db.actionsTable)).toList(),
      );
    });

/// The actions that must happen after [actionId] (its current successors).
final successorsOfProvider = StreamProvider.autoDispose
    .family<List<ActionRow>, String>((ref, actionId) {
      final db = ref.watch(databaseProvider);
      final query =
          db.select(db.actionsTable).join([
              innerJoin(
                db.actionDependenciesTable,
                db.actionDependenciesTable.successorId.equalsExp(
                  db.actionsTable.id,
                ),
              ),
            ])
            ..where(db.actionDependenciesTable.predecessorId.equals(actionId));
      return query.watch().map(
        (rows) => rows.map((r) => r.readTable(db.actionsTable)).toList(),
      );
    });

/// Ids of every action that's currently running (started but not yet
/// finished) — lets a tile/card mark itself as running without opening the
/// action. `actions.start_at` (not this table) is the single source for
/// *when* it started; this only answers "is it running at all."
final runningOccurrencesProvider = StreamProvider.autoDispose<Set<String>>((
  ref,
) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.actionOccurrencesTable)
    ..where((t) => t.finishedAt.isNull());
  return query.watch().map((rows) => rows.map((r) => r.actionId).toSet());
});

/// [actionId]'s start/finish/postpone history, most recent first — lets
/// the editor show when an action was actually started/finished, as
/// opposed to `actions.start_at`/`end_at`, which is only the *scheduled*
/// time.
final occurrencesOfProvider = StreamProvider.autoDispose
    .family<List<ActionOccurrence>, String>((ref, actionId) {
      final db = ref.watch(databaseProvider);
      final query = db.select(db.actionOccurrencesTable)
        ..where((t) => t.actionId.equals(actionId))
        ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]);
      return query.watch();
    });

/// All actions regardless of status, most recently updated first — the
/// "see everything, including finished" view.
final allActionsProvider = StreamProvider.autoDispose<List<ActionListItem>>((
  ref,
) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.actionsTable)
    ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]);
  return query.watch().map(
    (rows) => rows.map(ActionListItem.fromRow).toList(),
  );
});

/// The metric ids currently linked to [actionId].
final metricIdsOfProvider = StreamProvider.autoDispose
    .family<List<String>, String>((ref, actionId) {
      final db = ref.watch(databaseProvider);
      final query = db.select(db.actionMetricsTable)
        ..where((t) => t.actionId.equals(actionId));
      return query.watch().map(
        (rows) => rows.map((r) => r.metricId).toList(),
      );
    });
