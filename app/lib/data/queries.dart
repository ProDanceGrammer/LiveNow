import 'package:drift/drift.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/settings.dart';
import '../core/time_codec.dart';
import 'database.dart';

/// A row as shown in a view list — every list-style view (Operational, TODO,
/// Most Important, Habits) and the calendar renders these. Views that sort
/// by a computed score (Most Important) do the sorting in SQL; the score
/// itself isn't exposed here since the UI never needs to display it.
class ActionListItem {
  final String id;
  final String name;
  final String kind;
  final String status;
  final String? priority;
  final DateTime? startAt;
  final DateTime? endAt;
  final bool isAllDay;
  final int? estimatedMinutes;

  const ActionListItem({
    required this.id,
    required this.name,
    required this.kind,
    required this.status,
    this.priority,
    this.startAt,
    this.endAt,
    required this.isAllDay,
    this.estimatedMinutes,
  });

  factory ActionListItem.fromRow(ActionRow row) => ActionListItem(
    id: row.id,
    name: row.name,
    kind: row.kind,
    status: row.status,
    priority: row.priority,
    startAt: dateTimeFromDb(row.startAt),
    endAt: dateTimeFromDb(row.endAt),
    isAllDay: row.isAllDay,
    estimatedMinutes: row.estimatedMinutes,
  );

  factory ActionListItem.fromQueryRow(QueryRow row) => ActionListItem(
    id: row.read<String>('id'),
    name: row.read<String>('name'),
    kind: row.read<String>('kind'),
    status: row.read<String>('status'),
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

  /// Operational: open, not all-day, starting today, soonest first.
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
            t.status.equals('open') &
            t.isAllDay.equals(false) &
            t.startAt.isBiggerOrEqualValue(todayStartText) &
            t.startAt.isSmallerThanValue(tomorrowStartText),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.startAt)]);

    return query.watch().map(
      (rows) => rows.map(ActionListItem.fromRow).toList(),
    );
  }

  /// TODO: open tasks with no deadline yet, whose predecessors (if any) are
  /// all already scheduled, grouped/sorted by priority (unset last).
  Stream<List<ActionListItem>> watchTodo() {
    return db
        .customSelect(
          '''
          SELECT a.* FROM actions a
          WHERE a.kind = 'task' AND a.status = 'open' AND a.start_at IS NULL
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

  /// Most Important to Schedule: open, unscheduled actions whose
  /// predecessors are all done, ranked by linked-metric weight, then by how
  /// much finishing them unlocks downstream, then by shortest duration.
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
          WHERE a.status = 'open' AND a.start_at IS NULL
            AND NOT EXISTS (
              SELECT 1 FROM action_dependencies d
              JOIN actions p ON p.id = d.predecessor_id
              WHERE d.successor_id = a.id AND p.status <> 'done'
            )
          ORDER BY metrics_weight DESC, downstream_count DESC,
            (a.estimated_minutes IS NULL) ASC, a.estimated_minutes ASC
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

  /// Weekly calendar: one-off (non-habit) actions with a schedule inside
  /// `[weekStartUtc, weekEndUtc)`.
  Stream<List<ActionListItem>> watchCalendarWeek({
    required DateTime weekStartUtc,
    required DateTime weekEndUtc,
  }) {
    final startText = dateTimeToDb(weekStartUtc)!;
    final endText = dateTimeToDb(weekEndUtc)!;

    final query = db.select(db.actionsTable)
      ..where(
        (t) =>
            t.kind.equals('task') &
            t.startAt.isBiggerOrEqualValue(startText) &
            t.startAt.isSmallerThanValue(endText),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.startAt)]);

    return query.watch().map(
      (rows) => rows.map(ActionListItem.fromRow).toList(),
    );
  }

  /// Habits: open habit actions (bad habits aren't part of the MVP view).
  /// The UI splits the result into all-day vs timed sections locally using
  /// [ActionListItem.isAllDay].
  Stream<List<ActionListItem>> watchHabits() {
    final query = db.select(db.actionsTable)
      ..where((t) => t.kind.equals('habit') & t.status.equals('open'))
      ..orderBy([(t) => OrderingTerm.asc(t.startAt)]);

    return query.watch().map(
      (rows) => rows.map(ActionListItem.fromRow).toList(),
    );
  }
}
