import 'package:drift/drift.dart';

import '../core/stream_utils.dart';
import '../core/time_codec.dart';
import '../domain/done_rule.dart' as done_rule;
import 'database.dart';

/// A row as shown in an action list — the Current Actions board, All Actions
/// and the calendar render these. Deliberately has no notes: list queries
/// never read the (large) `notes` / `result_note` columns.
class ActionListItem {
  final String id;
  final String name;
  final bool done;
  final DateTime? startAt;
  final DateTime? endAt;
  final bool isAllDay;
  final int? estimatedMinutes;

  /// Last edit / creation time (the All list sorts on them); null where the
  /// query did not select them.
  final DateTime? updatedAt;
  final DateTime? createdAt;

  const ActionListItem({
    required this.id,
    required this.name,
    required this.done,
    this.startAt,
    this.endAt,
    required this.isAllDay,
    this.estimatedMinutes,
    this.updatedAt,
    this.createdAt,
  });

  /// Value equality, so an unchanged query result can be recognised and
  /// dropped (see `distinctList`).
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActionListItem &&
          id == other.id &&
          name == other.name &&
          done == other.done &&
          startAt == other.startAt &&
          endAt == other.endAt &&
          isAllDay == other.isAllDay &&
          estimatedMinutes == other.estimatedMinutes &&
          updatedAt == other.updatedAt &&
          createdAt == other.createdAt;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    done,
    startAt,
    endAt,
    isAllDay,
    estimatedMinutes,
    updatedAt,
    createdAt,
  );

  /// Whether this action counts as done for filtering/board-column purposes
  /// — see `domain/done_rule.dart`.
  bool get isDoneBefore => done_rule.isDoneBefore(
    startAt: startAt,
    endAt: endAt,
    isAllDay: isAllDay,
    done: done,
  );

  /// [isDoneBefore] evaluated at the pinned instant [nowUtc].
  bool isDoneAt(DateTime nowUtc) => done_rule.isDoneBefore(
    startAt: startAt,
    endAt: endAt,
    isAllDay: isAllDay,
    done: done,
    nowUtc: nowUtc,
  );

  factory ActionListItem.fromRow(ActionRow row) => ActionListItem(
    id: row.id,
    name: row.name,
    done: row.done,
    startAt: dateTimeFromDb(row.startAt),
    endAt: dateTimeFromDb(row.endAt),
    isAllDay: row.isAllDay,
    estimatedMinutes: row.estimatedMinutes,
    updatedAt: DateTime.tryParse(row.updatedAt)?.toUtc(),
    createdAt: DateTime.tryParse(row.createdAt)?.toUtc(),
  );

  factory ActionListItem.fromQueryRow(QueryRow row) => ActionListItem(
    id: row.read<String>('id'),
    name: row.read<String>('name'),
    done: row.read<bool>('done'),
    startAt: dateTimeFromDb(row.readNullable<String>('start_at')),
    endAt: dateTimeFromDb(row.readNullable<String>('end_at')),
    isAllDay: row.read<bool>('is_all_day'),
    estimatedMinutes: row.readNullable<int>('estimated_minutes'),
    updatedAt: _lenientTime(row, 'updated_at'),
    createdAt: _lenientTime(row, 'created_at'),
  );

  /// The audit timestamps are optional extras: absent column or unparseable
  /// text (hand-made test rows) just means "unknown".
  static DateTime? _lenientTime(QueryRow row, String column) {
    if (!row.data.containsKey(column)) return null;
    return DateTime.tryParse(row.readNullable<String>(column) ?? '')?.toUtc();
  }
}

/// Quiet period after which a burst of writes is collapsed into one list
/// rebuild (see `core/stream_utils.dart`).
const kListDebounce = Duration(milliseconds: 40);

/// "Now" as SQL text in the `dateTimeToDb` format (6 fractional digits).
const kSqlNowUtc = "(strftime('%Y-%m-%dT%H:%M:%f', 'now') || '000Z')";

/// SQL port of `domain/done_rule.dart` `isDoneBefore()` over `actions`
/// columns (timestamps are fixed-width UTC ISO text, so text `<` is
/// chronological):
///
///   unscheduled (start_at NULL) or all-day  ->  the manual `done` flag
///   scheduled, timed                        ->  end_at IS NOT NULL AND end_at < now
///
/// [nowExpr] is a SQL expression for "now". The default is evaluated by
/// SQLite on every re-run of a live query, which matches the Dart rule being
/// evaluated on every emit; tests bind a fixed instant instead.
/// `test/data/list_queries_test.dart` checks that the Dart and SQL rules agree.
String doneBeforeSql([String nowExpr = kSqlNowUtc]) =>
    'CASE WHEN start_at IS NULL OR is_all_day = 1 THEN done = 1 '
    'ELSE (end_at IS NOT NULL AND end_at < $nowExpr) END';

/// Live (auto-refreshing) queries backing the views. Assumes
/// [initPostponeTimeZoneData] (see `domain/postpone_rules.dart`) has already
/// run at app startup.
///
/// List queries read only the columns a list needs — never `notes` or
/// `result_note` (a checklist note is ~3 KB; thousands of them are what made
/// the lists slow) — and every stream is debounced and de-duplicated, so a
/// burst of writes causes one rebuild and an unchanged result none.
class ViewQueries {
  final AppDatabase db;

  ViewQueries(this.db);

  /// Columns of `actions` a list item needs.
  static const _itemColumns =
      'id, name, done, start_at, end_at, is_all_day, estimated_minutes';

  /// Every `actions` column except the big text ones, for the few callers
  /// that need a full [ActionRow] (built with `notes`/`resultNote` null).
  late final List<String> _rowColumns = [
    for (final c in db.actionsTable.$columns)
      if (c.$name != 'notes' &&
          c.$name != 'notes_text' &&
          c.$name != 'result_note')
        c.$name,
  ];

  Stream<List<ActionListItem>> _items(
    String sql, {
    List<Variable> variables = const [],
  }) => distinctList(
    debounced(
      db
          .customSelect(sql, variables: variables, readsFrom: {db.actionsTable})
          .watch()
          .map((rows) => rows.map(ActionListItem.fromQueryRow).toList()),
      kListDebounce,
    ),
  );

  Stream<int> _count(String where, {List<Variable> variables = const []}) =>
      debounced(
        db
            .customSelect(
              'SELECT COUNT(*) AS c FROM actions WHERE $where',
              variables: variables,
              readsFrom: {db.actionsTable},
            )
            .watchSingle()
            .map((r) => r.read<int>('c')),
        kListDebounce,
      ).distinct();

  /// Every action linked to a growth direction, as (metric id, action row).
  /// An action linked to several directions appears once per link. The
  /// progress rules (`domain/growth_rules.dart`) decide what counts; this
  /// only supplies the rows, so it refreshes when a link or an action changes.
  /// The rows have `notes` / `resultNote` == null.
  Stream<List<(String, ActionRow)>> watchMetricLinkedActions() {
    final cols = _rowColumns.map((c) => 'a.$c AS $c').join(', ');
    return distinctList(
      debounced(
        db
            .customSelect(
              'SELECT am.metric_id AS metric_id, $cols FROM action_metrics am '
              'JOIN actions a ON a.id = am.action_id',
              readsFrom: {db.actionMetricsTable, db.actionsTable},
            )
            .watch()
            .map(
              (rows) => [
                for (final r in rows)
                  (r.read<String>('metric_id'), db.actionsTable.map(r.data)),
              ],
            ),
        kListDebounce,
      ),
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
    return _items(
      'SELECT $_itemColumns FROM actions '
      'WHERE start_at < ? AND (start_at >= ? OR end_at > ?) '
      'ORDER BY start_at ASC',
      variables: [
        Variable.withString(endText),
        Variable.withString(startText),
        Variable.withString(startText),
      ],
    );
  }

  /// All actions regardless of status, most recently updated first.
  Stream<List<ActionListItem>> watchAllActions() => _items(
    'SELECT $_itemColumns, updated_at, created_at FROM actions '
    'ORDER BY updated_at DESC',
  );

  /// Lean link maps for the All list's filters (only subscribed while a
  /// filter needs them): action id -> ids of its growth directions.
  Stream<Map<String, Set<String>>> watchActionMetricIds() => _idMap(
    'SELECT action_id AS k, metric_id AS v FROM action_metrics',
    {db.actionMetricsTable},
  );

  /// action id -> ids of its predecessors.
  Stream<Map<String, Set<String>>> watchPredecessorIds() => _idMap(
    'SELECT successor_id AS k, predecessor_id AS v FROM action_dependencies',
    {db.actionDependenciesTable},
  );

  /// action id -> ids of its successors.
  Stream<Map<String, Set<String>>> watchSuccessorIds() => _idMap(
    'SELECT predecessor_id AS k, successor_id AS v FROM action_dependencies',
    {db.actionDependenciesTable},
  );

  Stream<Map<String, Set<String>>> _idMap(
    String sql,
    Set<TableInfo> readsFrom,
  ) => debounced(
    db.customSelect(sql, readsFrom: readsFrom).watch().map((rows) {
      final map = <String, Set<String>>{};
      for (final r in rows) {
        (map[r.read<String>('k')] ??= {}).add(r.read<String>('v'));
      }
      return map;
    }),
    kListDebounce,
  );

  /// Ids of actions whose plain-text notes contain [lowerQuery] (already
  /// lower-cased by the caller; `%`, `_` and `\` are escaped here). The
  /// notes text itself is never selected.
  Stream<Set<String>> watchNotesMatchIds(String lowerQuery) {
    final escaped = lowerQuery
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    return debounced(
      db
          .customSelect(
            r"SELECT id FROM actions WHERE notes_text LIKE ? ESCAPE '\'",
            variables: [Variable.withString('%$escaped%')],
            readsFrom: {db.actionsTable},
          )
          .watch()
          .map((rows) => {for (final r in rows) r.read<String>('id')}),
      kListDebounce,
    );
  }

  /// Not-done actions as [ActionRow]s without the heavy text columns (the
  /// predecessor/successor picker).
  Stream<List<ActionRow>> watchOpenActions() => distinctList(
    debounced(
      db
          .customSelect(
            'SELECT ${_rowColumns.join(', ')} FROM actions '
            'WHERE NOT (${doneBeforeSql()})',
            readsFrom: {db.actionsTable},
          )
          .watch()
          .map((rows) => rows.map((r) => db.actionsTable.map(r.data)).toList()),
      kListDebounce,
    ),
  );

  /// All-day actions live on the Calendar's strip, not on the Current board.
  static const _timedOnly = 'is_all_day = 0';

  static const _notDoneOrder = 'ORDER BY start_at IS NULL ASC, start_at ASC';
  static const _doneOrder = 'ORDER BY end_at IS NULL ASC, end_at DESC';

  /// Current Actions board, right column: not done yet, nearest deadline
  /// first (unscheduled last), at most [limit] rows. All-day actions are never
  /// listed on the board. Once an action has been
  /// started, `start_at` is its actual start time (see
  /// [ActionService.start]), so this is also "started, still running" first.
  /// [nowUtc] pins "now" (tests); by default SQLite's clock is used.
  Stream<List<ActionListItem>> watchCurrentNotDone({
    required int limit,
    DateTime? nowUtc,
    Set<String>? onlyIds,
  }) {
    final (now, vars) = _now(nowUtc);
    return _items(
      'SELECT $_itemColumns FROM actions '
      'WHERE $_timedOnly AND NOT (${doneBeforeSql(now)})${_idFilter(onlyIds)} '
      '$_notDoneOrder LIMIT ?',
      variables: [...vars, Variable.withInt(limit)],
    );
  }

  /// ` AND id IN (...)` for the board's search ([ids] null = no search). The
  /// ids are our own UUIDs, quoted defensively anyway.
  static String _idFilter(Set<String>? ids) {
    if (ids == null) return '';
    if (ids.isEmpty) return ' AND 0';
    return ' AND id IN (${ids.map((i) => "'${i.replaceAll("'", "''")}'").join(',')})';
  }

  /// Ids of the timed actions whose name contains [lowerQuery] (already
  /// lower-cased). Matched in Dart: SQLite's LIKE/lower() are not
  /// case-insensitive for Cyrillic.
  Stream<Set<String>> watchNameMatchIds(String lowerQuery) => debounced(
    db
        .customSelect(
          'SELECT id, name FROM actions WHERE $_timedOnly',
          readsFrom: {db.actionsTable},
        )
        .watch()
        .map(
          (rows) => {
            for (final r in rows)
              if (r.read<String>('name').toLowerCase().contains(lowerQuery))
                r.read<String>('id'),
          },
        ),
    kListDebounce,
  );

  /// Current Actions board, left column: done actions, most recently
  /// finished first (`end_at` is the actual finish time — see
  /// [ActionService.finish]), at most [limit] rows.
  Stream<List<ActionListItem>> watchCurrentDone({
    required int limit,
    DateTime? nowUtc,
    Set<String>? onlyIds,
  }) {
    final (now, vars) = _now(nowUtc);
    return _items(
      'SELECT $_itemColumns FROM actions '
      'WHERE $_timedOnly AND (${doneBeforeSql(now)})${_idFilter(onlyIds)} '
      '$_doneOrder LIMIT ?',
      variables: [...vars, Variable.withInt(limit)],
    );
  }

  /// Total number of not-done actions (the column header; not the page size).
  Stream<int> watchCurrentNotDoneCount({
    DateTime? nowUtc,
    Set<String>? onlyIds,
  }) {
    final (now, vars) = _now(nowUtc);
    return _count(
      '$_timedOnly AND NOT (${doneBeforeSql(now)})${_idFilter(onlyIds)}',
      variables: vars,
    );
  }

  /// Total number of done actions.
  Stream<int> watchCurrentDoneCount({DateTime? nowUtc, Set<String>? onlyIds}) {
    final (now, vars) = _now(nowUtc);
    return _count(
      '$_timedOnly AND (${doneBeforeSql(now)})${_idFilter(onlyIds)}',
      variables: vars,
    );
  }

  /// The next timed actions that still have a start or an end ahead of them
  /// (soonest first, at most [limit]): what the reminders are planned from.
  /// Live: any change to an action's times (edit, postpone, sync) re-emits.
  Stream<List<ActionListItem>> watchUpcoming({int limit = 40}) => _items(
    'SELECT $_itemColumns FROM actions '
    'WHERE $_timedOnly AND (end_at > $kSqlNowUtc '
    'OR (end_at IS NULL AND start_at > $kSqlNowUtc)) '
    'ORDER BY start_at IS NULL ASC, start_at ASC LIMIT ?',
    variables: [Variable.withInt(limit)],
  );

  (String, List<Variable>) _now(DateTime? nowUtc) => nowUtc == null
      ? (kSqlNowUtc, const [])
      : ('?', [Variable.withString(dateTimeToDb(nowUtc)!)]);
}
