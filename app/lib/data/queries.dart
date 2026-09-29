import 'package:drift/drift.dart';

import '../core/time_codec.dart';
import '../domain/done_rule.dart' as done_rule;
import 'database.dart';

/// A row as shown in an action list — the Current Actions board, All Actions
/// and the calendar render these.
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

/// Live (auto-refreshing) queries backing the views. Assumes
/// [initPostponeTimeZoneData] (see `domain/postpone_rules.dart`) has already
/// run at app startup.
class ViewQueries {
  final AppDatabase db;

  ViewQueries(this.db);

  /// Every action linked to a growth direction, as (metric id, action row).
  /// An action linked to several directions appears once per link. The
  /// progress rules (`domain/growth_rules.dart`) decide what counts; this
  /// only supplies the rows, so it refreshes when a link or an action changes.
  Stream<List<(String, ActionRow)>> watchMetricLinkedActions() {
    final query = db.select(db.actionMetricsTable).join([
      innerJoin(
        db.actionsTable,
        db.actionsTable.id.equalsExp(db.actionMetricsTable.actionId),
      ),
    ]);
    return query.watch().map(
      (rows) => [
        for (final r in rows)
          (
            r.readTable(db.actionMetricsTable).metricId,
            r.readTable(db.actionsTable),
          ),
      ],
    );
  }

  /// Calendar range: every action (all-day or timed, done or not) whose
  /// schedule overlaps `[weekStartUtc, weekEndUtc)` — i.e. it starts before
  /// the range ends and either starts inside the range or ends after the
  /// range start (so an event running past midnight into the range is kept).
  Stream<List<ActionListItem>> watchCalendarWeek({
    required DateTime weekStartUtc,
    required DateTime weekEndUtc,
  }) {
    final startText = dateTimeToDb(weekStartUtc)!;
    final endText = dateTimeToDb(weekEndUtc)!;

    final query = db.select(db.actionsTable)
      ..where(
        (t) =>
            t.startAt.isSmallerThanValue(endText) &
            (t.startAt.isBiggerOrEqualValue(startText) |
                t.endAt.isBiggerThanValue(startText)),
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
