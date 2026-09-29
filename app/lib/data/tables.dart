import 'package:drift/drift.dart';

/// One action.
///
/// The Dart class is named `ActionsTable` (not `Actions`) because
/// `package:flutter/widgets.dart` already exports a widget called `Actions`;
/// reusing that name would collide wherever both packages are imported.
///
/// `done` is a plain manual flag (Start clears it, Finish sets it) — it is
/// NOT the same as "is this done for filtering/board purposes". That's a
/// derived value, `domain/done_rule.dart`'s `isDoneBefore()`: for a
/// scheduled, non-all-day action it's computed live from `endAt` vs. now
/// (so Postpone moving the schedule is what flips it, not this flag); for an
/// unscheduled or all-day action it just mirrors this flag.
@DataClassName('ActionRow')
@TableIndex(name: 'idx_actions_done_start', columns: {#done, #startAt})
@TableIndex(name: 'idx_actions_allday_start', columns: {#isAllDay, #startAt})
class ActionsTable extends Table {
  @override
  String get tableName => 'actions';

  TextColumn get id => text()();
  TextColumn get name => text()();
  BoolColumn get done => boolean().withDefault(const Constant(false))();
  TextColumn get priority => text().nullable()();
  TextColumn get postponeFlex =>
      text().withDefault(const Constant('flexible'))();
  TextColumn get depthLevel => text().nullable()();

  /// UTC ISO-8601 text, chosen over Drift's native DateTime column so the
  /// on-disk representation matches what a future Postgres sync target
  /// expects, rather than sqlite's integer default.
  TextColumn get startAt => text().nullable()();
  TextColumn get endAt => text().nullable()();
  BoolColumn get isAllDay => boolean().withDefault(const Constant(false))();
  IntColumn get estimatedMinutes => integer().nullable()();
  TextColumn get resultNote => text().nullable()();
  TextColumn get completedAt => text().nullable()();

  /// Position in a "Continue with Same Action" chain (`[#2] Read a Bible`).
  /// The name prefix is display only; this column is the source of truth.
  IntColumn get sequenceNumber => integer().nullable()();

  /// The repeatable activity type this action is an instance of; its past
  /// durations feed the predicted duration of a continuation.
  TextColumn get countableActivityId => text().nullable().references(
    CountableActivitiesTable,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (priority IS NULL OR priority IN "
        "('A1','A2','A3','B1','B2','B3','C1','C2','C3','D1','D2','D3'))",
    "CHECK (postpone_flex IN ('flexible','hard','impossible'))",
    "CHECK (depth_level IS NULL OR depth_level IN ('easy','medium','deep'))",
  ];
}

/// A trackable, repeatable activity type (e.g. "Read the Bible"). Actions
/// link to one so the average of its recent finished runs can predict how
/// long the next one takes.
@DataClassName('CountableActivity')
class CountableActivitiesTable extends Table {
  @override
  String get tableName => 'countable_activities';

  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A "this must follow that" edge between two actions. This is the core
/// GTD dependency chain (previous/next actions); there is no parent/child
/// hierarchy in this schema.
@DataClassName('ActionDependency')
@TableIndex(name: 'idx_dep_successor', columns: {#successorId})
class ActionDependenciesTable extends Table {
  @override
  String get tableName => 'action_dependencies';

  TextColumn get id => text()();
  @ReferenceName('predecessorDependencies')
  TextColumn get predecessorId =>
      text().references(ActionsTable, #id, onDelete: KeyAction.cascade)();
  @ReferenceName('successorDependencies')
  TextColumn get successorId =>
      text().references(ActionsTable, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'UNIQUE (predecessor_id, successor_id)',
    'CHECK (predecessor_id <> successor_id)',
  ];
}

/// Append-only log of started/finished/postponed occurrences for an action.
/// Used both for time tracking (Start/Finish/Continue buttons) and to derive
/// recurring-action history for the metric balance calculation, since
/// postpone just moves `start_at`/`end_at` on the same action row.
@DataClassName('ActionOccurrence')
@TableIndex(name: 'idx_occurrence_action', columns: {#actionId})
class ActionOccurrencesTable extends Table {
  @override
  String get tableName => 'action_occurrences';

  TextColumn get id => text()();
  TextColumn get actionId =>
      text().references(ActionsTable, #id, onDelete: KeyAction.cascade)();
  TextColumn get startedAt => text().nullable()();
  TextColumn get finishedAt => text().nullable()();
  TextColumn get outcome => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (outcome IS NULL OR outcome IN ('done','skipped','postponed'))",
  ];
}

/// A growth direction ("metric"): a personal consistent goal such as "I sleep
/// enough". Actions increment it (see `action_metrics`); its progress, weight
/// and urgency are computed by `domain/growth_rules.dart`.
///
/// - `kind`: `boolean` (progress is derived from linked actions or from the
///   directions it depends on), `count` (each finished action counts 1) or
///   `hours` (finished actions count their duration).
/// - `time_window`: how far back finished actions count (`week`, `month`,
///   `year`, `five_years`); null for boolean directions. Named `time_window`
///   because `window` is a reserved SQL word.
/// - `target`: the amount that means 100% progress for count/hours.
/// - `is_main`: a main growth direction, always weighing 1000.
/// - `weight` and `importance_level` are derived caches, rewritten by
///   `MetricService.recomputeWeights()` whenever the graph or a main flag
///   changes (so SQL can read them without re-walking the graph).
@DataClassName('Metric')
class MetricsTable extends Table {
  @override
  String get tableName => 'metrics';

  TextColumn get id => text()();
  TextColumn get name => text()();
  RealColumn get weight => real().withDefault(const Constant(0))();
  TextColumn get kind => text().withDefault(const Constant('boolean'))();
  TextColumn get timeWindow => text().nullable()();
  RealColumn get target => real().withDefault(const Constant(1))();
  BoolColumn get isMain => boolean().withDefault(const Constant(false))();
  IntColumn get importanceLevel => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (kind IN ('boolean','count','hours'))",
    "CHECK (time_window IS NULL OR time_window IN "
        "('week','month','year','five_years'))",
    "CHECK (kind = 'boolean' OR time_window IS NOT NULL)",
  ];
}

/// "[metric_id] depends on [depends_on_id]" — equivalently, depends_on_id
/// *leads to* metric_id (it is a sub-direction of it). A graph, not a tree:
/// a direction can lead to several others. Kept acyclic by `MetricService`.
@DataClassName('MetricDependency')
@TableIndex(name: 'idx_metric_dep_depends_on', columns: {#dependsOnId})
class MetricDependenciesTable extends Table {
  @override
  String get tableName => 'metric_dependencies';

  TextColumn get id => text()();
  @ReferenceName('dependentMetricLinks')
  TextColumn get metricId =>
      text().references(MetricsTable, #id, onDelete: KeyAction.cascade)();
  @ReferenceName('contributingMetricLinks')
  TextColumn get dependsOnId =>
      text().references(MetricsTable, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'UNIQUE (metric_id, depends_on_id)',
    'CHECK (metric_id <> depends_on_id)',
  ];
}

/// Join table: which metrics an action increments.
@DataClassName('ActionMetric')
@TableIndex(name: 'idx_action_metrics_metric', columns: {#metricId})
class ActionMetricsTable extends Table {
  @override
  String get tableName => 'action_metrics';

  TextColumn get id => text()();
  TextColumn get actionId =>
      text().references(ActionsTable, #id, onDelete: KeyAction.cascade)();
  TextColumn get metricId =>
      text().references(MetricsTable, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['UNIQUE (action_id, metric_id)'];
}

/// A saved "new from template" preset. `payload` is a JSON blob holding the
/// default action fields plus linked metric ids.
@DataClassName('ActionTemplate')
class ActionTemplatesTable extends Table {
  @override
  String get tableName => 'action_templates';

  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get payload => text()();

  @override
  Set<Column> get primaryKey => {id};
}
