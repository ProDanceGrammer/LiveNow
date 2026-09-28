import 'package:drift/drift.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/settings.dart';
import '../core/time_codec.dart';
import '../domain/done_rule.dart' as done_rule;
import 'database.dart';

/// A row as shown in a view list — every list-style view (Operational, TODO,
/// Most Important) and the calendar renders these. Views that sort by a
/// computed score (Most Important) do the sorting in SQL; the score itself
/// isn't exposed here since the UI never needs to display it.
class ActionListItem {
  final String id;
  final String name;
  final bool done;
  final String? priority;
  final DateTime? startAt;
  final DateTime? endAt;
  final bool isAllDay;
  final int? estimatedMinutes;

  const ActionListItem({
    required this.id,
    required this.name,
    required this.done,
    this.priority,
    this.startAt,
    this.endAt,
    required this.isAllDay,
    this.estimatedMinutes,
  });

  /// Whether this action counts as done for filtering/board-column purposes
  /// — see `domain/done_rule.dart`.
  bool get isDoneBefore => done_rule.isDoneBefore(
    startAt: startAt,
    endAt: endAt,
    isAllDay: isAllDay,
    done: done,
  );

  factory ActionListItem.fromRow(ActionRow row) => ActionListItem(
    id: row.id,
    name: row.name,
    done: row.done,
    priority: row.priority,
    startAt: dateTimeFromDb(row.startAt),
    endAt: dateTimeFromDb(row.endAt),
    isAllDay: row.isAllDay,
    estimatedMinutes: row.estimatedMinutes,
  );

  factory ActionListItem.fromQueryRow(QueryRow row) => ActionListItem(
    id: row.read<String>('id'),
    name: row.read<String>('name'),
    done: row.read<bool>('done'),
    priority: row.readNullable<String>('priority'),
    startAt: dateTimeFromDb(row.readNullable<String>('start_at')),
    endAt: dateTimeFromDb(row.readNullable<String>('end_at')),
    isAllDay: row.read<bool>('is_all_day'),
    estimatedMinutes: row.readNullable<int>('estimated_minutes'),
  );
}

/// Live (auto-refreshing) queries backing the five MVP views. Assumes
/// [initPostponeTimeZoneData] (see `domain/postpone_rules.dart`) has already
/// run at app startup.
class ViewQueries {
  final AppDatabase db;

  ViewQueries(this.db);

  /// Operational: not done, not all-day, starting today, soonest first.
  Stream<List<ActionListItem>> watchOperational({DateTime? referenceUtc}) {
    final location = tz.getLocation(AppSettings.timeZoneName);
    final now = tz.TZDateTime.from(referenceUtc ?? DateTime.now().toUtc(), location);
    final todayStart = tz.TZDateTime(location, now.year, now.month, now.day);
    final tomorrowStart = todayStart.add(const Duration(days: 1));
    final todayStartText = dateTimeToDb(todayStart)!;
    final tomorrowStartText = dateTimeToDb(tomorrowStart)!;

    final query = db.select(db.actionsTable)
      ..where(
        (t) =>
            t.isAllDay.equals(false) &
            t.startAt.isBiggerOrEqualValue(todayStartText) &
            t.startAt.isSmallerThanValue(tomorrowStartText),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.startAt)]);

    return query.watch().map(
      (rows) => rows
          .map(ActionListItem.fromRow)
          .where((a) => !a.isDoneBefore)
          .toList(),
    );
  }

  /// TODO: not-done actions with no deadline yet, whose predecessors (if
  /// any) are all already scheduled, grouped/sorted by priority (unset
  /// last). Always unscheduled by definition, so "not done" here is always
  /// just the manual `done` flag (see `domain/done_rule.dart`).
  Stream<List<ActionListItem>> watchTodo() {
    return db
        .customSelect(
          '''
          SELECT a.* FROM actions a
          WHERE a.done = 0 AND a.start_at IS NULL
            AND NOT EXISTS (
              SELECT 1 FROM action_dependencies d
              JOIN actions p ON p.id = d.predecessor_id
              WHERE d.successor_id = a.id AND p.start_at IS NULL
            )
          ORDER BY (a.priority IS NULL) ASC, a.priority ASC
          ''',
          readsFrom: {db.actionsTable, db.actionDependenciesTable},
        )
        .watch()
        .map((rows) => rows.map(ActionListItem.fromQueryRow).toList());
  }

  /// Most Important to Schedule: unscheduled, not-done actions whose
  /// predecessors are all done, ranked by linked-metric weight, then by how
  /// much finishing them unlocks downstream, then by shortest duration.
  ///
  /// A predecessor can be scheduled, so its "done" check must use the full
  /// `isDoneBefore` formula (`domain/done_rule.dart`), not just the manual
  /// flag: unscheduled → the flag; scheduled + timed → `end_at < now()`;
  /// scheduled + all-day → the flag. `strftime('%Y-%m-%dT%H:%M:%f','now')`
  /// gives millisecond precision or gets padded with `'000Z'` to the same
  /// fixed 27-character `yyyy-MM-ddTHH:mm:ss.ffffffZ` shape
  /// `core/time_codec.dart` always writes, so plain text comparison against
  /// the stored microsecond-precision timestamps stays correct.
  Stream<List<ActionListItem>> watchMostImportant() {
    return db
        .customSelect(
          '''
          WITH RECURSIVE downstream(root, id) AS (
            SELECT predecessor_id, successor_id FROM action_dependencies
            UNION
            SELECT ds.root, d.successor_id
            FROM action_dependencies d
            JOIN downstream ds ON d.predecessor_id = ds.id
          ),
          downstream_counts AS (
            SELECT root, COUNT(DISTINCT id) AS cnt FROM downstream GROUP BY root
          )
          SELECT a.*,
            COALESCE((
              SELECT SUM(m.weight) FROM action_metrics am
              JOIN metrics m ON m.id = am.metric_id
              WHERE am.action_id = a.id
            ), 0) AS metrics_weight,
            COALESCE(dc.cnt, 0) AS downstream_count
          FROM actions a
          LEFT JOIN downstream_counts dc ON dc.root = a.id
          WHERE a.done = 0 AND a.start_at IS NULL
            AND NOT EXISTS (
              SELECT 1 FROM action_dependencies d
              JOIN actions p ON p.id = d.predecessor_id
              WHERE d.successor_id = a.id AND NOT (
                (p.start_at IS NULL AND p.done = 1)
                OR (p.start_at IS NOT NULL AND (
                  (p.is_all_day = 0 AND p.end_at IS NOT NULL
                    AND p.end_at < (strftime('%Y-%m-%dT%H:%M:%f','now') || '000Z'))
                  OR (p.is_all_day = 1 AND p.done = 1)
                ))
              )
            )
          ORDER BY metrics_weight DESC, downstream_count DESC,
            COALESCE(a.estimated_minutes, 60) ASC
          ''',
          readsFrom: {
            db.actionsTable,
            db.actionDependenciesTable,
            db.metricsTable,
            db.actionMetricsTable,
          },
        )
        .watch()
        .map((rows) => rows.map(ActionListItem.fromQueryRow).toList());
  }

  /// Weekly calendar: actions with a schedule inside `[weekStartUtc,
  /// weekEndUtc)`.
  Stream<List<ActionListItem>> watchCalendarWeek({
    required DateTime weekStartUtc,
    required DateTime weekEndUtc,
  }) {
    final startText = dateTimeToDb(weekStartUtc)!;
    final endText = dateTimeToDb(weekEndUtc)!;

    final query = db.select(db.actionsTable)
      ..where(
        (t) =>
            t.startAt.isBiggerOrEqualValue(startText) &
            t.startAt.isSmallerThanValue(endText),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.startAt)]);

    return query.watch().map(
      (rows) => rows.map(ActionListItem.fromRow).toList(),
    );
  }

  /// Current Actions board, right column: everything not done yet, nearest
  /// deadline first (unscheduled last). Once an action has been started,
  /// `start_at` is its actual start time (see [ActionService.start]), so
  /// this is also "started, still running" first.
  Stream<List<ActionListItem>> watchCurrentNotDone() {
    final query = db.select(db.actionsTable)
      ..orderBy([
        (t) => OrderingTerm.asc(
          const CustomExpression<bool>('start_at IS NULL'),
        ),
        (t) => OrderingTerm.asc(t.startAt),
      ]);

    return query.watch().map(
      (rows) => rows
          .map(ActionListItem.fromRow)
          .where((a) => !a.isDoneBefore)
          .toList(),
    );
  }

  /// Current Actions board, left column: done actions, most recently
  /// finished first (`end_at` is the actual finish time — see
  /// [ActionService.finish]).
  Stream<List<ActionListItem>> watchCurrentDone() {
    final query = db.select(db.actionsTable)
      ..orderBy([
        (t) =>
            OrderingTerm.asc(const CustomExpression<bool>('end_at IS NULL')),
        (t) => OrderingTerm.desc(t.endAt),
      ]);

    return query.watch().map(
      (rows) => rows
          .map(ActionListItem.fromRow)
          .where((a) => a.isDoneBefore)
          .toList(),
    );
  }
}
