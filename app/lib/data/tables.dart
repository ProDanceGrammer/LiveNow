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
@TableIndex(name: 'idx_actions_start', columns: {#startAt})
class ActionsTable extends Table {
  @override
  String get tableName => 'actions';

  TextColumn get id => text()();
  TextColumn get name => text()();
  BoolColumn get done => boolean().withDefault(const Constant(false))();
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

  /// The action's rich-text description (checklists, bullets, headings…):
  /// the editor's Document JSON, or null when empty. Written by the notes
  /// editor in the action dialog; `result_note` stays a separate, unused
  /// plain "outcome" field.
  TextColumn get notes => text().nullable()();

  /// Lower-cased plain text of [notes], derived (see `notesPlainText`) and
  /// written next to it; only used by the All list's notes search.
  TextColumn get notesText => text().nullable()();
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
/// - `icon`: an emoji shown before the name (null = none).
/// - `pos_x`/`pos_y`: the node's position on the Mindmap (null = auto layout).
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
  TextColumn get icon => text().nullable()();

  /// Where the node sits on the Mindmap canvas (null = not placed yet).
  RealColumn get posX => real().nullable()();
  RealColumn get posY => real().nullable()();

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

/// A named sort / filter preset of one screen (schema v13). `kind` says what it
/// stores (`sort`, `filter` or `both`), `payload` is JSON `{"sort": {...},
/// "filter": {...}}` written by `domain/saved_views.dart`; at most one view per
/// screen is the default (`is_default`). Synced like every other table, so the
/// ids a filter mentions exist on every device.
@DataClassName('SavedView')
class SavedViewsTable extends Table {
  @override
  String get tableName => 'saved_views';

  TextColumn get id => text()();
  TextColumn get screen => text()();
  TextColumn get name => text()();
  TextColumn get kind => text().withDefault(const Constant('both'))();
  TextColumn get payload => text().withDefault(const Constant('{}'))();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

// ---- Budget (schema v10) -----------------------------------------------------
// Money is stored as plain REAL and rounded by `domain/budget_rules.dart`
// (like `metrics.target`). A transaction snapshots its own price, rates, income
// flag and accounts so editing a category never rewrites history or balances.

/// A place money lives: its own currency and its current rate to the base
/// currency (units of this currency per 1 base unit — the spec's "Euro Rate").
@DataClassName('BudgetAccount')
class BudgetAccountsTable extends Table {
  @override
  String get tableName => 'budget_accounts';

  TextColumn get id => text()();
  TextColumn get name => text()();

  /// Free label: electronic money / cash / crypto. Optional, for readability.
  TextColumn get type => text().nullable()();
  TextColumn get currency => text()();
  RealColumn get rateToBase => real().withDefault(const Constant(1))();
  RealColumn get openingBalance => real().withDefault(const Constant(0))();

  /// The account's picture: a square PNG (96 px) as base64 text, or null (the
  /// purse icon is shown instead). Text rather than a BLOB so the sync log and
  /// the JSON backup carry it like any other column.
  TextColumn get icon => text().nullable()();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['CHECK (rate_to_base > 0)'];
}

/// A budget category. A "group" is simply a category that has children; only
/// leaves carry prices/units/transactions. NULL replaces the Notion `-1`
/// sentinels everywhere.
@DataClassName('BudgetCategory')
@TableIndex(name: 'idx_budget_categories_parent', columns: {#parentId})
class BudgetCategoriesTable extends Table {
  @override
  String get tableName => 'budget_categories';

  TextColumn get id => text()();
  TextColumn get name => text()();
  BoolColumn get isIncome => boolean().withDefault(const Constant(false))();
  BoolColumn get oneTime => boolean().withDefault(const Constant(false))();

  /// piece | kilogram | month | percent_per_month
  TextColumn get unit => text().withDefault(const Constant('month'))();

  /// UTC ISO-8601 text; the category stops counting after it.
  TextColumn get endDate => text().nullable()();
  RealColumn get price => real().nullable()();
  RealColumn get percent => real().nullable()();
  RealColumn get frequencyMonths => real().nullable()();
  RealColumn get unitsPerMonth => real().nullable()();

  @ReferenceName('childCategories')
  TextColumn get parentId => text().nullable().references(
    BudgetCategoriesTable,
    #id,
    onDelete: KeyAction.setNull,
  )();

  /// For `percent_per_month`: the (leaf) category the percentage is taken of.
  @ReferenceName('percentDistributors')
  TextColumn get countPercentOfId => text().nullable().references(
    BudgetCategoriesTable,
    #id,
    onDelete: KeyAction.setNull,
  )();

  /// Account whose currency the category is COUNTED in / that money actually
  /// moves through ("Account to count" / "Account to use" in the spec).
  @ReferenceName('countedCategories')
  TextColumn get accountCountId => text().nullable().references(
    BudgetAccountsTable,
    #id,
    onDelete: KeyAction.setNull,
  )();
  @ReferenceName('usedCategories')
  TextColumn get accountUseId => text().nullable().references(
    BudgetAccountsTable,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (unit IN ('piece','kilogram','month','percent_per_month'))",
    'CHECK (parent_id IS NULL OR parent_id <> id)',
  ];
}

/// One income/expense record. The date follows the linked action's start live
/// (`COALESCE(actions.start_at, occurred_at)`); `occurred_at` is the fallback
/// and the frozen date once the action is gone.
@DataClassName('BudgetTransaction')
@TableIndex(name: 'idx_budget_tx_category', columns: {#categoryId})
@TableIndex(name: 'idx_budget_tx_action', columns: {#actionId})
class BudgetTransactionsTable extends Table {
  @override
  String get tableName => 'budget_transactions';

  TextColumn get id => text()();
  TextColumn get name => text().withDefault(const Constant(''))();
  TextColumn get categoryId => text().nullable().references(
    BudgetCategoriesTable,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get actionId => text().nullable().references(
    ActionsTable,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get occurredAt => text()();
  RealColumn get quantity => real().withDefault(const Constant(1))();

  /// Price per unit actually used (snapshot of the category price).
  RealColumn get unitPrice => real().withDefault(const Constant(0))();
  BoolColumn get isIncome => boolean().withDefault(const Constant(false))();

  /// True for percent categories: `quantity` already IS the amount.
  BoolColumn get isAmount => boolean().withDefault(const Constant(false))();
  @ReferenceName('countedTransactions')
  TextColumn get accountCountId => text().nullable().references(
    BudgetAccountsTable,
    #id,
    onDelete: KeyAction.setNull,
  )();
  @ReferenceName('usedTransactions')
  TextColumn get accountUseId => text().nullable().references(
    BudgetAccountsTable,
    #id,
    onDelete: KeyAction.setNull,
  )();
  RealColumn get rateCount => real().nullable()();
  RealColumn get rateInteract => real().nullable()();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Small key/value store: base_currency, period_months, tolerance.
@DataClassName('BudgetSetting')
class BudgetSettingsTable extends Table {
  @override
  String get tableName => 'budget_settings';

  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
