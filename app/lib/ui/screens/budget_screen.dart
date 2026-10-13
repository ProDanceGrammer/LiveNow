import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../domain/budget_rules.dart';
import '../../domain/budget_tx_view_rules.dart';
import '../../domain/budget_service.dart';
import '../../domain/name_sort.dart';
import '../budget_providers.dart';
import '../providers.dart'
    show actionUrgencyProvider, actionsWithDirectionsProvider;
import '../urgency_colors.dart';
import '../widgets/action_tile.dart' show formatUrgency;
import '../layout.dart';
import '../undo.dart' show offerUndo, undoHistoryProvider;
import '../open_entity.dart';
import '../widgets/account_icon.dart';
import '../widgets/budget_tx_options_panel.dart';
import '../widgets/app_toast.dart';
import '../widgets/budget_categories_board.dart';
import '../widgets/budget_dialogs.dart';
import '../widgets/budget_format.dart';
import '../widgets/glass.dart';
import '../widgets/param_icons.dart';

enum BudgetTab {
  overview('Overview'),
  categories('Categories'),
  transactions('Transactions'),
  accounts('Accounts');

  const BudgetTab(this.label);
  final String label;
}

/// The Budget section: money accounts, a category tree with plan-vs-fact
/// figures, and transactions that link to Actions.
class BudgetScreen extends ConsumerStatefulWidget {
  const BudgetScreen({super.key});

  @override
  ConsumerState<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends ConsumerState<BudgetScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _visited = <BudgetTab>{BudgetTab.overview};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: BudgetTab.values.length,
      vsync: this,
      animationDuration: Duration.zero,
    )..addListener(() => setState(() => _visited.add(_current)));
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  BudgetTab get _current => BudgetTab.values[_tabs.index];

  static Widget _viewFor(BudgetTab tab) => switch (tab) {
    BudgetTab.overview => const _OverviewView(),
    BudgetTab.categories => const _CategoriesView(),
    BudgetTab.transactions => const _TransactionsView(),
    BudgetTab.accounts => const _AccountsView(),
  };

  void _onFab() {
    switch (_current) {
      case BudgetTab.overview:
      case BudgetTab.transactions:
        BudgetTransactionDialog.show(context, quick: true);
      case BudgetTab.categories:
        BudgetCategoryDialog.show(context);
      case BudgetTab.accounts:
        BudgetAccountDialog.show(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(budgetSettingsProvider).value;
    final tab = _current;
    return Scaffold(
      body: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
                  child: GlassSurface(
                    radius: 20,
                    shadow: false,
                    blurWindow: false,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: TabBar(
                        key: const ValueKey('budget-switch'),
                        controller: _tabs,
                        // Four tabs do not fit a phone: scroll them.
                        isScrollable: usePhoneLayout(context),
                        tabAlignment: usePhoneLayout(context)
                            ? TabAlignment.start
                            : null,
                        splashFactory: NoSplash.splashFactory,
                        tabs: [
                          for (final t in BudgetTab.values)
                            Tab(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  switch (t) {
                                    BudgetTab.overview => const Icon(
                                      Icons.pie_chart_outline,
                                      size: 18,
                                    ),
                                    BudgetTab.categories => const ParamIcon(
                                      Param.categories,
                                      size: 18,
                                      tooltip: false,
                                    ),
                                    BudgetTab.transactions => const ParamIcon(
                                      Param.transactions,
                                      size: 18,
                                      tooltip: false,
                                    ),
                                    BudgetTab.accounts => const ParamIcon(
                                      Param.accounts,
                                      size: 18,
                                      tooltip: false,
                                    ),
                                  },
                                  const SizedBox(width: 6),
                                  Text(t.label),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('budget-settings'),
                icon: const Icon(Icons.tune),
                tooltip: 'Budget settings',
                onPressed: settings == null
                    ? null
                    : () => BudgetSettingsDialog.show(context, settings),
              ),
              const SizedBox(width: 8),
            ],
          ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                for (final t in BudgetTab.values)
                  if (_visited.contains(t) || t == tab)
                    Visibility(
                      key: ValueKey('budget-view-${t.name}'),
                      visible: t == tab,
                      maintainState: true,
                      child: ExcludeFocus(
                        excluding: t != tab,
                        child: _viewFor(t),
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: null,
        key: const ValueKey('budget-fab'),
        onPressed: _onFab,
        tooltip: switch (tab) {
          BudgetTab.overview || BudgetTab.transactions => 'Add transaction',
          BudgetTab.categories => 'New category',
          BudgetTab.accounts => 'New account',
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ---- shared bits ------------------------------------------------------------

/// The tint of a budget row/card from the urgency of its related action: WHITE
/// when that action has no growth direction ("fill me in"), the urgency scale
/// when it has one, null (plain glass) when there is no action at all.
({Color bg, Color fg})? _urgencyTint(
  BuildContext context, {
  double? urgency,
  bool unlinked = false,
}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  if (unlinked) return emptyColors(dark: dark);
  if (urgency != null) return urgencyColors(urgency, dark: dark);
  return null;
}

Widget _card({required Widget child, EdgeInsets? padding}) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
  child: GlassSurface(
    radius: 16,
    shadow: false,
    blurWindow: false,
    child: Padding(padding: padding ?? const EdgeInsets.all(12), child: child),
  ),
);

Widget _loading(AsyncValue<BudgetView> v, Widget Function(BudgetView) data) =>
    v.when(
      data: data,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );

Future<void> _deleteCategory(
  BuildContext context,
  WidgetRef ref,
  BudgetCategory c,
) async {
  final overlay = rootOverlayOf(context);
  final service = ref.read(budgetServiceProvider);
  final history = ref.read(undoHistoryProvider.notifier);
  final undo = await service.deleteCategory(c.id);
  if (undo == null) return;
  offerUndo(
    overlay,
    history,
    'Deleted "${c.name}"',
    () => service.undoDeleteCategory(undo),
  );
}

Future<void> _deleteAccount(
  BuildContext context,
  WidgetRef ref,
  BudgetAccount a,
) async {
  final overlay = rootOverlayOf(context);
  final service = ref.read(budgetServiceProvider);
  final history = ref.read(undoHistoryProvider.notifier);
  final undo = await service.deleteAccount(a.id);
  if (undo == null) return;
  offerUndo(
    overlay,
    history,
    'Deleted "${a.name}"',
    () => service.undoDeleteAccount(undo),
  );
}

Future<void> _deleteTransaction(
  BuildContext context,
  WidgetRef ref,
  BudgetTransaction t,
) async {
  final overlay = rootOverlayOf(context);
  final service = ref.read(budgetServiceProvider);
  final history = ref.read(undoHistoryProvider.notifier);
  final row = await service.deleteTransaction(t.id);
  if (row == null) return;
  offerUndo(
    overlay,
    history,
    'Deleted transaction',
    () => service.undoDeleteTransaction(row),
  );
}

// ---- overview ---------------------------------------------------------------

class _OverviewView extends ConsumerStatefulWidget {
  const _OverviewView();

  @override
  ConsumerState<_OverviewView> createState() => _OverviewViewState();
}

class _OverviewViewState extends ConsumerState<_OverviewView> {
  bool _leavesOnly = false;

  Future<void> _setMonths(BudgetSettings s, int months) {
    if (months < 1) return Future.value();
    return ref
        .read(budgetServiceProvider)
        .saveSettings(
          BudgetSettings(
            baseCurrency: s.baseCurrency,
            periodMonths: months,
            tolerance: s.tolerance,
          ),
        );
  }

  Future<void> _pickAsOf(BudgetView view) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: budgetLocalDay(view.period.asOf),
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) {
      ref.read(budgetAsOfProvider.notifier).state = budgetNoonUtc(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final asOf = ref.watch(budgetAsOfProvider);
    return _loading(ref.watch(budgetViewProvider), (view) {
      final s = view.settings;
      final snap = view.snapshot;
      final cur = s.baseCurrency;
      final period = view.period;
      final byId = view.categoryById;
      final hasChild = {
        for (final c in view.categories)
          if (c.parentId != null && byId.containsKey(c.parentId)) c.parentId!,
      };

      final over = <_BoardEntry>[],
          under = <_BoardEntry>[],
          within = <_BoardEntry>[];
      // Categories that ended before the as-of day stay out of the boards (the
      // totals above still count them); "Leaves only" folds same-name price
      // variants into their parent.
      final cats = [for (final c in view.categories) budgetCatFromRow(c)];
      final ended = endedCategoryIds(cats, period.asOf);
      final collapse = collapseSameNameLeaves(cats);
      for (final c in view.categories) {
        final isTop = c.parentId == null || !byId.containsKey(c.parentId);
        final include = _leavesOnly
            ? collapse.show.contains(c.id) ||
                  (!hasChild.contains(c.id) && !collapse.hide.contains(c.id))
            : isTop;
        if (ended.contains(c.id)) continue;
        final f = snap.byCategory[c.id];
        if (!include || f == null || (f.factBase == 0 && f.planBase == 0)) {
          continue;
        }
        final entry = _BoardEntry(c, f);
        switch (classifyPlanFact(f.factBase, f.planBase, s.tolerance)) {
          case BoardColumn.over:
            over.add(entry);
          case BoardColumn.under:
            under.add(entry);
          case BoardColumn.within:
            within.add(entry);
        }
      }
      int byName(_BoardEntry a, _BoardEntry b) =>
          compareIgnoringEmoji(a.category.name, b.category.name);
      over.sort(byName);
      under.sort(byName);
      within.sort(byName);

      final boards = [
        _BoardColumn(
          columnKey: 'over',
          semanticTitle: 'Actual above plan',
          title: const [Param.plan, ' below ', Param.actual],
          entries: over,
        ),
        _BoardColumn(
          columnKey: 'under',
          semanticTitle: 'Plan above actual',
          title: const [Param.plan, ' above ', Param.actual],
          entries: under,
        ),
        _BoardColumn(
          columnKey: 'within',
          semanticTitle: 'Close to plan (±${budgetNumber(s.tolerance)})',
          title: ['Close to ', Param.plan, ' (±${budgetNumber(s.tolerance)})'],
          entries: within,
        ),
      ];
      return ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          _card(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Period'),
                IconButton(
                  key: const ValueKey('budget-months-minus'),
                  icon: const Icon(Icons.remove),
                  tooltip: 'Shorter period',
                  onPressed: () => _setMonths(s, s.periodMonths - 1),
                ),
                Text('${s.periodMonths} months'),
                IconButton(
                  key: const ValueKey('budget-months-plus'),
                  icon: const Icon(Icons.add),
                  tooltip: 'Longer period',
                  onPressed: () => _setMonths(s, s.periodMonths + 1),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  key: const ValueKey('budget-as-of'),
                  icon: const Icon(Icons.event),
                  label: Text(
                    asOf == null ? 'As of today' : 'As of ${budgetDate(asOf)}',
                  ),
                  onPressed: () => _pickAsOf(view),
                ),
                if (asOf != null)
                  IconButton(
                    key: const ValueKey('budget-as-of-reset'),
                    icon: const Icon(Icons.today),
                    tooltip: 'Back to today',
                    onPressed: () =>
                        ref.read(budgetAsOfProvider.notifier).state = null,
                  ),
              ],
            ),
          ),
          _card(
            child: Wrap(
              spacing: 32,
              runSpacing: 12,
              children: [
                _Figure(
                  key: const ValueKey('budget-fact-total'),
                  icon: Param.actual,
                  label:
                      '${budgetDate(period.factStart)} – ${budgetDate(period.asOf)}',
                  value: snap.factTotal,
                  currency: cur,
                ),
                _Figure(
                  key: const ValueKey('budget-plan-total'),
                  icon: Param.plan,
                  label:
                      '${budgetDate(period.asOf)} – ${budgetDate(period.planEnd)}',
                  value: snap.planTotal,
                  currency: cur,
                ),
                _Figure(
                  key: const ValueKey('budget-position'),
                  label: 'Position',
                  trailingIcons: const [Param.actual, Param.plan],
                  value: snap.position,
                  currency: cur,
                  strong: true,
                ),
                if (snap.noRate)
                  const Tooltip(
                    message:
                        'Some categories have no account or rate, so they are '
                        'left out of these totals.',
                    child: Chip(
                      avatar: Icon(Icons.warning_amber_rounded, size: 18),
                      label: Text('Some amounts have no rate'),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Categories vs plan',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const Text('Leaves only'),
                Switch(
                  key: const ValueKey('budget-leaves-only'),
                  value: _leavesOnly,
                  onChanged: (v) => setState(() => _leavesOnly = v),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: usePhoneLayout(context)
                // A phone stacks the three boards: side by side they are
                // ~110 px wide each.
                ? Column(children: boards)
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [for (final b in boards) Expanded(child: b)],
                  ),
          ),
        ],
      );
    });
  }
}

class _BoardEntry {
  const _BoardEntry(this.category, this.figures);
  final BudgetCategory category;
  final CategoryFigures figures;
}

class _Figure extends StatelessWidget {
  const _Figure({
    super.key,
    required this.label,
    required this.value,
    required this.currency,
    this.icon,
    this.trailingIcons = const [],
    this.strong = false,
  });

  /// The words (a date range, "Position"); a Plan/Fact [icon] replaces the
  /// word that used to lead it, [trailingIcons] sit after it.
  final String label;
  final Param? icon;
  final List<Param> trailingIcons;
  final double value;
  final String currency;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              ParamIcon(icon!, size: 18, tapToShow: true),
              const SizedBox(width: 4),
            ],
            Text(label, style: theme.textTheme.bodySmall),
            for (final p in trailingIcons) ...[
              const SizedBox(width: 4),
              ParamIcon(p, size: 16, tapToShow: true),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '${budgetMoney(value, sign: true)} $currency',
          style: TextStyle(
            fontSize: strong ? 22 : 18,
            fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
            color: value < 0 ? theme.colorScheme.error : null,
          ),
        ),
      ],
    );
  }
}

class _BoardColumn extends ConsumerWidget {
  const _BoardColumn({
    required this.columnKey,
    required this.title,
    required this.semanticTitle,
    required this.entries,
  });

  final String columnKey;

  /// The title as text pieces and [Param] icons, e.g. `[plan, ' above ',
  /// actual]`: the words Plan/Fact are icons everywhere.
  final List<Object> title;

  /// The same title as plain words (accessibility, tests).
  final String semanticTitle;
  final List<_BoardEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: GlassSurface(
        key: ValueKey('budget-board-$columnKey'),
        radius: 16,
        shadow: false,
        blurWindow: false,
        child: DecoratedBox(
          // Green = plan above actual (room left), red = actual above plan.
          decoration: BoxDecoration(
            color: switch (columnKey) {
              'under' => _boardGreen(context),
              'over' => _boardRed(context),
              _ => null,
            },
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  label: semanticTitle,
                  child: ExcludeSemantics(
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final part in title)
                          part is Param
                              ? Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                  ),
                                  child: ParamIcon(
                                    part,
                                    size: 18,
                                    tooltip: false,
                                    color: DefaultTextStyle.of(context)
                                        .style
                                        .color,
                                  ),
                                )
                              : Text(
                                  part as String,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (entries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('—', textAlign: TextAlign.center),
                  ),
                for (final e in entries) _BoardEntryBlock(entry: e),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One category of a board as its own rounded glass block: the name, then the
/// plan and the fact (icons, not words) with their amounts.
class _BoardEntryBlock extends StatelessWidget {
  const _BoardEntryBlock({required this.entry});

  final _BoardEntry entry;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final small = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: GlassSurface(
        radius: 14,
        shadow: false,
        blurWindow: false,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: ValueKey('budget-board-${e.category.id}'),
            borderRadius: BorderRadius.circular(14),
            onTap: () =>
                BudgetCategoryDialog.show(context, existing: e.category),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.category.name),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ParamValue.plan(
                        budgetMoney(e.figures.planBase),
                        style: small,
                        iconAfter: true,
                      ),
                      ParamValue.actual(
                        budgetMoney(e.figures.factBase),
                        style: small,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Soft tints for the plan-vs-actual boards (translucent over the glass, so
/// the normal text colour keeps its contrast in light and dark).
Color _boardGreen(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0x4D2E9E5B)
    : const Color(0x6694E2B1);

Color _boardRed(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0x4DD9534F)
    : const Color(0x66F4A3A0);

// ---- categories -------------------------------------------------------------

/// The Categories tab: one glass board (search, sort levels, Flat switch, fixed
/// height rows) in `widgets/budget_categories_board.dart`.
class _CategoriesView extends ConsumerWidget {
  const _CategoriesView();

  @override
  Widget build(BuildContext context, WidgetRef ref) => BudgetCategoriesBoard(
    onOpen: (c) => BudgetCategoryDialog.show(context, existing: c),
    onAddSub: (id) => BudgetCategoryDialog.show(context, parentId: id),
    onDelete: (c) => _deleteCategory(context, ref, c),
  );
}

// ---- transactions -----------------------------------------------------------

class _TransactionsView extends ConsumerStatefulWidget {
  const _TransactionsView();

  @override
  ConsumerState<_TransactionsView> createState() => _TransactionsViewState();
}

class _TransactionsViewState extends ConsumerState<_TransactionsView> {
  String _query = '';
  bool _showOptions = false;

  static double _amount(BudgetTransaction t) =>
      (t.isIncome ? 1 : -1) *
      (t.isAmount ? t.quantity : t.unitPrice * t.quantity);

  @override
  Widget build(BuildContext context) {
    final sort = ref.watch(budgetTxSortProvider);
    final flags = ref.watch(budgetTxSearchFlagsProvider);
    final filters = ref.watch(budgetTxFiltersProvider);
    final optionsActive =
        filters.active ||
        flags != const TxSearchFlags() ||
        !listEquals(sort, kDefaultTxSort);
    return _loading(ref.watch(budgetViewProvider), (view) {
      final cats = view.categoryById;
      final accounts = view.accountById;
      final now = DateTime.now().toUtc();

      final byId = {for (final t in view.transactions) t.row.id: t};
      final ids = arrangeTransactionIds(
        rows: [
          for (final t in view.transactions)
            TxRowView(
              id: t.row.id,
              name: t.row.name,
              categoryId: t.row.categoryId,
              categoryName: cats[t.row.categoryId]?.name ?? '',
              accountId: t.row.accountCountId,
              actionName: t.actionName ?? '',
              linked: t.row.actionId != null,
              date: t.date,
              amount: _amount(t.row),
            ),
        ],
        sort: sort,
        filters: filters,
        query: _query,
        flags: flags,
        descendants: categoryWithDescendants({
          for (final c in view.categories) c.id: c.parentId,
        }),
      );
      final items = [for (final id in ids) byId[id]!];
      // Day headings only make sense while the list is in date order.
      final byDate = sort.isNotEmpty && sort.first.field == TxSortField.date;
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('budget-transactions-search'),
                    decoration: const InputDecoration(
                      hintText: 'Search by name, category or action',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                    onChanged: (v) =>
                        setState(() => _query = v.trim().toLowerCase()),
                  ),
                ),
                IconButton(
                  key: const ValueKey('budget-tx-options-toggle'),
                  isSelected: _showOptions || optionsActive,
                  tooltip: _showOptions
                      ? 'Hide sort and filters'
                      : 'Sort and filters',
                  icon: const Icon(Icons.tune),
                  onPressed: () => setState(() => _showOptions = !_showOptions),
                ),
              ],
            ),
          ),
          if (_showOptions) const BudgetTxOptionsPanel(),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Text(
                      view.transactions.isEmpty
                          ? 'No transactions yet.'
                          : 'No transaction matches.',
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final t = items[i];
                      final prev = i == 0 ? null : items[i - 1];
                      final newDay =
                          byDate &&
                          (prev == null ||
                              budgetDate(prev.date) != budgetDate(t.date));
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (newDay)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
                              child: Text(
                                budgetDate(t.date) +
                                    (t.date.isAfter(now) ? '  · planned' : ''),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          _TransactionTile(
                            item: t,
                            category: cats[t.row.categoryId],
                            currency: accounts[t.row.accountCountId]?.currency,
                            accountIcon: accounts[t.row.accountCountId]?.icon,
                            hasAccount: accounts[t.row.accountCountId] != null,
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      );
    });
  }
}

class _TransactionTile extends ConsumerWidget {
  const _TransactionTile({
    required this.item,
    required this.category,
    required this.currency,
    this.accountIcon,
    this.hasAccount = false,
  });

  final BudgetTxItem item;
  final BudgetCategory? category;
  final String? currency;

  /// The counting account's picture (null = none) and whether there is an
  /// account at all (no account = no icon shown).
  final String? accountIcon;
  final bool hasAccount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = item.row;
    final amount =
        (t.isIncome ? 1 : -1) *
        (t.isAmount ? t.quantity : t.unitPrice * t.quantity);
    final scheme = Theme.of(context).colorScheme;
    final detail = t.isAmount
        ? null
        : '${budgetNumber(t.quantity)} × ${budgetNumber(t.unitPrice)}';
    // Urgency of the related action: the tile takes its colour from the scale
    // (white when that action has no direction; plain without an action), and
    // the number + icon sit on the action line.
    final actionId = t.actionId;
    final urgency = ref.watch(
      actionUrgencyProvider.select((m) => actionId == null ? null : m[actionId]),
    );
    final unlinked = ref.watch(
      actionsWithDirectionsProvider.select(
        (s) => actionId != null && s != null && !s.contains(actionId),
      ),
    );
    final tint = _urgencyTint(context, urgency: urgency, unlinked: unlinked);
    final fg = tint?.fg;
    return _card(
      padding: EdgeInsets.zero,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tint?.bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          key: ValueKey('budget-tx-${t.id}'),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textColor: fg,
          iconColor: fg,
          dense: true,
          // Line 1: the transaction's own name.
          title: t.name.isEmpty
              ? Text(
                  'No name',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                )
              : Text(t.name),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Line 2: the categories icon and the category name.
              Row(
                key: ValueKey('budget-tx-category-${t.id}'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  ParamIcon(
                    Param.categories,
                    size: 14,
                    tooltip: false,
                    color: fg,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      category?.name ?? 'No category',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              // Line 3: quantity x price.
              if (detail != null) Text(detail),
              // Line 4: the action, as before.
              if (t.actionId != null)
                InkWell(
                  key: ValueKey('budget-tx-action-${t.id}'),
                  onTap: () => openActionById(context, ref, t.actionId!),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bolt_outlined, size: 14, color: fg),
                      Flexible(
                        child: Text(
                          item.actionName ?? 'Action',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Urgency of the action, coloured like its tile.
                      if (urgency != null) ...[
                        const SizedBox(width: 8),
                        ParamValue.urgency(
                          formatUrgency(urgency),
                          key: ValueKey('budget-tx-urgency-${t.id}'),
                          size: 16,
                          color: fg ?? scheme.onSurface,
                          iconColor: fg,
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
          onTap: () => BudgetTransactionDialog.show(context, existing: item),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasAccount) ...[
                AccountIcon(icon: accountIcon, size: 20),
                const SizedBox(width: 6),
              ],
              Text(
                '${budgetMoney(amount, sign: true)} ${currency ?? ''}'.trim(),
                // The amount carries its sign; on a tinted tile it uses the text
                // colour (red/green would clash with the scale).
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: fg ?? (amount < 0 ? scheme.error : Colors.green),
                ),
              ),
              IconButton(
                key: ValueKey('budget-delete-tx-${t.id}'),
                tooltip: 'Delete',
                color: fg,
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _deleteTransaction(context, ref, t),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

// ---- accounts ---------------------------------------------------------------

/// Fiat balances with two decimals; crypto-like currencies (tiny rate per base
/// unit) keep their precision instead of rounding to 0.00.
String _balanceText(double amount, double rateToBase) =>
    rateToBase > 0.5 ? budgetMoney(amount) : budgetNumber(amount);

class _AccountsView extends ConsumerWidget {
  const _AccountsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _loading(ref.watch(budgetViewProvider), (view) {
      final base = view.settings.baseCurrency;
      if (view.accounts.isEmpty) {
        return const Center(child: Text('No accounts yet.'));
      }
      final accounts = [...view.accounts]
        ..sort((a, b) => compareIgnoringEmoji(a.name, b.name));
      return ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 88),
        children: [
          for (final a in accounts)
            _card(
              padding: EdgeInsets.zero,
              child: Material(
                type: MaterialType.transparency,
                child: ListTile(
                  key: ValueKey('budget-account-${a.id}'),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  leading: AccountIcon(
                    key: ValueKey('budget-account-icon-${a.id}'),
                    icon: a.icon,
                    size: 36,
                  ),
                  title: Text(a.name),
                  subtitle: Text(
                    [
                      if (a.type != null) a.type!,
                      '${a.currency} · ${budgetNumber(a.rateToBase)} per 1 $base',
                    ].join(' · '),
                  ),
                  onTap: () => BudgetAccountDialog.show(context, existing: a),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (view.balances[a.id]?.incomplete ?? false)
                        const Tooltip(
                          message: 'Some transactions have no rate and are left out.',
                          child: Icon(Icons.warning_amber_rounded, size: 18),
                        ),
                      Text(
                        '${_balanceText(view.balances[a.id]?.amount ?? a.openingBalance, a.rateToBase)} ${a.currency}',
                        key: ValueKey('budget-balance-${a.id}'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      IconButton(
                        key: ValueKey('budget-delete-account-${a.id}'),
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deleteAccount(context, ref, a),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }
}
