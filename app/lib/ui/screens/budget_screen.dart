import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/time_codec.dart';
import '../../data/database.dart';
import '../../domain/budget_csv.dart';
import '../../domain/budget_io_service.dart';
import '../../domain/budget_rules.dart';
import '../../domain/budget_service.dart';
import '../../domain/name_sort.dart';
import '../budget_files.dart';
import '../budget_providers.dart';
import '../dialog_stack.dart';
import '../open_entity.dart';
import '../widgets/app_toast.dart';
import '../widgets/budget_dialogs.dart';
import '../widgets/budget_format.dart';
import '../widgets/budget_import_summary_dialog.dart';
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

  /// Import: one JSON backup, or any of the three Notion CSVs (recognised by
  /// their header). Replaces the budget data, after asking when there is some.
  Future<void> _import() async {
    final overlay = rootOverlayOf(context);
    final files = await ref.read(budgetFilesProvider).pickImportFiles();
    if (files.isEmpty || !mounted) return;

    String? backup, accounts, categories, transactions;
    final ignored = <String>[];
    for (final f in files) {
      if (BudgetIoService.looksLikeBackup(f.text)) {
        backup = f.text;
        continue;
      }
      switch (detectBudgetCsv(f.text)) {
        case BudgetCsvKind.accounts:
          accounts = f.text;
        case BudgetCsvKind.categories:
          categories = f.text;
        case BudgetCsvKind.transactions:
          transactions = f.text;
        case null:
          ignored.add(f.name);
      }
    }
    final anyCsv =
        accounts != null || categories != null || transactions != null;
    if (backup == null && !anyCsv) {
      showInfoToast(overlay, 'No budget data found in the chosen files');
      return;
    }
    if (backup != null && anyCsv) {
      showInfoToast(overlay, 'Choose either one backup file or the CSV files');
      return;
    }

    final io = ref.read(budgetIoServiceProvider);
    if (await io.hasData()) {
      if (!mounted) return;
      final ok = await showStackedDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Replace the budget data?'),
          content: const Text(
            'The accounts, categories and transactions now in the app will be '
            'replaced by the imported ones. Export a backup first if you may '
            'want them back.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('confirm-budget-import'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    try {
      final summary = backup != null
          ? await io.importJson(backup)
          : await io.importNotionCsvs(
              accountsCsv: accounts,
              categoriesCsv: categories,
              transactionsCsv: transactions,
            );
      if (!mounted) return;
      await BudgetImportSummaryDialog.show(
        context,
        summary,
        ignoredFiles: ignored,
      );
    } on FormatException catch (e) {
      showInfoToast(overlay, 'Import failed: ${e.message}');
    }
  }

  String get _today {
    final n = DateTime.now();
    String p(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${p(n.month)}-${p(n.day)}';
  }

  Future<void> _exportJson() async {
    final overlay = rootOverlayOf(context);
    final json = await ref.read(budgetIoServiceProvider).exportJson();
    final path = await ref
        .read(budgetFilesProvider)
        .saveText('livenow-budget-$_today.json', json);
    if (path != null) showInfoToast(overlay, 'Backup saved: $path');
  }

  Future<void> _exportCsv() async {
    final overlay = rootOverlayOf(context);
    final files = await ref.read(budgetIoServiceProvider).exportCsvs();
    final dir = await ref.read(budgetFilesProvider).saveFolder(files);
    if (dir != null) showInfoToast(overlay, '3 CSV files saved to $dir');
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
                    child: TabBar(
                      key: const ValueKey('budget-switch'),
                      controller: _tabs,
                      splashFactory: NoSplash.splashFactory,
                      tabs: [
                        for (final t in BudgetTab.values) Tab(text: t.label),
                      ],
                    ),
                  ),
                ),
              ),
              PopupMenuButton<String>(
                key: const ValueKey('budget-menu'),
                icon: const Icon(Icons.import_export),
                tooltip: 'Import / export',
                onSelected: (v) => switch (v) {
                  'import' => _import(),
                  'json' => _exportJson(),
                  _ => _exportCsv(),
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    key: ValueKey('budget-import'),
                    value: 'import',
                    child: Text('Import (CSV or backup)…'),
                  ),
                  PopupMenuItem(
                    key: ValueKey('budget-export-json'),
                    value: 'json',
                    child: Text('Export backup (JSON)…'),
                  ),
                  PopupMenuItem(
                    key: ValueKey('budget-export-csv'),
                    value: 'csv',
                    child: Text('Export CSV files…'),
                  ),
                ],
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
  final undo = await service.deleteCategory(c.id);
  if (undo == null) return;
  showUndoToast(
    overlay,
    'Deleted "${c.name}"',
    onUndo: () => service.undoDeleteCategory(undo),
  );
}

Future<void> _deleteAccount(
  BuildContext context,
  WidgetRef ref,
  BudgetAccount a,
) async {
  final overlay = rootOverlayOf(context);
  final service = ref.read(budgetServiceProvider);
  final undo = await service.deleteAccount(a.id);
  if (undo == null) return;
  showUndoToast(
    overlay,
    'Deleted "${a.name}"',
    onUndo: () => service.undoDeleteAccount(undo),
  );
}

Future<void> _deleteTransaction(
  BuildContext context,
  WidgetRef ref,
  BudgetTransaction t,
) async {
  final overlay = rootOverlayOf(context);
  final service = ref.read(budgetServiceProvider);
  final row = await service.deleteTransaction(t.id);
  if (row == null) return;
  showUndoToast(
    overlay,
    'Deleted transaction',
    onUndo: () => service.undoDeleteTransaction(row),
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
      for (final c in view.categories) {
        final isTop = c.parentId == null || !byId.containsKey(c.parentId);
        final include = _leavesOnly ? !hasChild.contains(c.id) : isTop;
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
                  label:
                      'Fact · ${budgetDate(period.factStart)} – ${budgetDate(period.asOf)}',
                  value: snap.factTotal,
                  currency: cur,
                ),
                _Figure(
                  key: const ValueKey('budget-plan-total'),
                  label:
                      'Plan · ${budgetDate(period.asOf)} – ${budgetDate(period.planEnd)}',
                  value: snap.planTotal,
                  currency: cur,
                ),
                _Figure(
                  key: const ValueKey('budget-position'),
                  label: 'Position (fact + plan)',
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _BoardColumn(
                    columnKey: 'over',
                    title: 'Actual above plan',
                    entries: over,
                  ),
                ),
                Expanded(
                  child: _BoardColumn(
                    columnKey: 'under',
                    title: 'Plan above actual',
                    entries: under,
                  ),
                ),
                Expanded(
                  child: _BoardColumn(
                    columnKey: 'within',
                    title: 'Close to plan (±${budgetNumber(s.tolerance)})',
                    entries: within,
                  ),
                ),
              ],
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
    this.strong = false,
  });

  final String label;
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
        Text(label, style: theme.textTheme.bodySmall),
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
    required this.entries,
  });

  final String columnKey;
  final String title;
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
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              if (entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('—', textAlign: TextAlign.center),
                ),
              for (final e in entries)
                InkWell(
                  key: ValueKey('budget-board-${e.category.id}'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: () =>
                      BudgetCategoryDialog.show(context, existing: e.category),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.category.name),
                        Text(
                          'Fact ${budgetMoney(e.figures.factBase)} · '
                          'Plan ${budgetMoney(e.figures.planBase)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- categories -------------------------------------------------------------

class _Col {
  const _Col(this.label, this.width, {this.manual = false, this.hint});
  final String label;
  final double width;

  /// Entered by hand (vs calculated).
  final bool manual;
  final String? hint;
}

const _nameCol = _Col('Name', 230, manual: true);
const _cols = <_Col>[
  _Col('Unit', 68, manual: true),
  _Col('Price', 84, manual: true),
  _Col('Units/mo', 96, manual: true, hint: 'Units per month (plan)'),
  _Col('Every', 78, manual: true, hint: 'Frequency in months'),
  _Col('Ends', 88, manual: true),
  _Col('Monthly', 94, hint: 'Planned cost per month (counting currency)'),
  _Col('Plan', 90, hint: 'Planned cost for the period (counting currency)'),
  _Col('Fact', 90, hint: 'Actual cost, last period (counting currency)'),
  _Col('Plan (base)', 118, hint: 'Plan in the main currency, income +'),
  _Col('Fact (base)', 118, hint: 'Fact in the main currency, income +'),
  _Col('Urgency', 92, hint: 'Urgency of the next planned payment’s action'),
];
const _actionsWidth = 96.0;

class _CategoriesView extends ConsumerStatefulWidget {
  const _CategoriesView();

  @override
  ConsumerState<_CategoriesView> createState() => _CategoriesViewState();
}

class _CategoriesViewState extends ConsumerState<_CategoriesView> {
  String _query = '';

  /// Depth-first list (siblings by name, ignoring emoji), guarded against
  /// corrupt parent loops.
  static List<(BudgetCategory, int)> _flatten(List<BudgetCategory> cats) {
    final ids = {for (final c in cats) c.id};
    final kids = <String?, List<BudgetCategory>>{};
    for (final c in cats) {
      final parent = ids.contains(c.parentId) ? c.parentId : null;
      (kids[parent] ??= []).add(c);
    }
    for (final list in kids.values) {
      list.sort((a, b) => compareIgnoringEmoji(a.name, b.name));
    }
    final out = <(BudgetCategory, int)>[];
    final seen = <String>{};
    void walk(String? parent, int depth) {
      for (final c in kids[parent] ?? const <BudgetCategory>[]) {
        if (!seen.add(c.id)) continue;
        out.add((c, depth));
        walk(c.id, depth + 1);
      }
    }

    walk(null, 0);
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final urgency = ref.watch(budgetCategoryUrgencyProvider);
    return _loading(ref.watch(budgetViewProvider), (view) {
      final rows = [
        for (final r in _flatten(view.categories))
          if (_query.isEmpty || r.$1.name.toLowerCase().contains(_query)) r,
      ];
      final accounts = view.accountById;
      final width =
          _nameCol.width +
          _cols.fold<double>(0, (a, c) => a + c.width) +
          _actionsWidth +
          24;
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('budget-categories-search'),
                    decoration: const InputDecoration(
                      hintText: 'Search categories',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                    onChanged: (v) =>
                        setState(() => _query = v.trim().toLowerCase()),
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(Icons.edit_outlined, size: 14),
                const Text(' entered   '),
                const Icon(Icons.functions, size: 16),
                const Text(' calculated'),
              ],
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? const Center(child: Text('No categories yet.'))
                : Scrollbar(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: width,
                        child: Column(
                          children: [
                            _HeaderRow(),
                            Expanded(
                              child: ListView.builder(
                                padding: const EdgeInsets.only(bottom: 88),
                                itemCount: rows.length,
                                itemBuilder: (context, i) => _CategoryRow(
                                  category: rows[i].$1,
                                  depth: rows[i].$2,
                                  figures:
                                      view.snapshot.byCategory[rows[i].$1.id],
                                  urgency: urgency[rows[i].$1.id],
                                  currency: accounts[rows[i].$1.accountCountId]
                                      ?.currency,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      );
    });
  }
}

class _HeaderRow extends StatelessWidget {
  Widget _cell(BuildContext context, _Col c) {
    final scheme = Theme.of(context).colorScheme;
    final cell = Container(
      width: c.width,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      color: c.manual ? scheme.primary.withValues(alpha: 0.08) : null,
      child: Row(
        children: [
          Icon(c.manual ? Icons.edit_outlined : Icons.functions, size: 12),
          const SizedBox(width: 3),
          Expanded(
            child: Text(
              c.label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ),
        ],
      ),
    );
    return c.hint == null ? cell : Tooltip(message: c.hint!, child: cell);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Row(
      children: [
        _cell(context, _nameCol),
        for (final c in _cols) _cell(context, c),
        const SizedBox(width: _actionsWidth),
      ],
    ),
  );
}

class _CategoryRow extends ConsumerWidget {
  const _CategoryRow({
    required this.category,
    required this.depth,
    required this.figures,
    required this.urgency,
    required this.currency,
  });

  final BudgetCategory category;
  final int depth;
  final CategoryFigures? figures;
  final double? urgency;
  final String? currency;

  static String _unit(String unit) => switch (BudgetUnit.fromDb(unit)) {
    BudgetUnit.piece => 'pc',
    BudgetUnit.kilogram => 'kg',
    BudgetUnit.month => 'mo',
    BudgetUnit.percentPerMonth => '%',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = category;
    final f = figures;
    final group = f?.isGroup ?? false;
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(
      fontStyle: FontStyle.italic,
      color: scheme.onSurface.withValues(alpha: 0.85),
      fontSize: 13,
    );
    final entered = const TextStyle(fontSize: 13);
    final percent = BudgetUnit.fromDb(c.unit) == BudgetUnit.percentPerMonth;

    Widget cell(double w, String text, TextStyle style, {Alignment? align}) =>
        SizedBox(
          width: w,
          child: Align(
            alignment: align ?? Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(text, style: style, overflow: TextOverflow.ellipsis),
            ),
          ),
        );

    String money(double? v) => v == null ? '—' : budgetMoney(v);
    final end = dateTimeFromDb(c.endDate);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: InkWell(
        key: ValueKey('budget-category-${c.id}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => BudgetCategoryDialog.show(context, existing: c),
        child: Row(
          children: [
            SizedBox(
              width: _nameCol.width,
              child: Padding(
                padding: EdgeInsets.only(left: 6.0 + depth * 18, right: 6),
                child: Row(
                  children: [
                    Icon(
                      c.isIncome ? Icons.south_west : Icons.north_east,
                      size: 13,
                      color: c.isIncome ? Colors.green : scheme.error,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        c.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: group ? FontWeight.w700 : null,
                        ),
                      ),
                    ),
                    if (f?.noRate ?? false)
                      const Tooltip(
                        message: 'No rate: set the category’s account rate',
                        child: Icon(Icons.warning_amber_rounded, size: 14),
                      ),
                  ],
                ),
              ),
            ),
            cell(_cols[0].width, group ? '' : _unit(c.unit), entered),
            cell(
              _cols[1].width,
              group
                  ? ''
                  : percent
                  ? (c.percent == null ? '—' : '${budgetNumber(c.percent!)}%')
                  : (c.price == null ? '—' : budgetNumber(c.price!)),
              entered,
            ),
            cell(
              _cols[2].width,
              group || c.unitsPerMonth == null
                  ? ''
                  : budgetNumber(c.unitsPerMonth!),
              entered,
            ),
            cell(
              _cols[3].width,
              group || c.frequencyMonths == null
                  ? ''
                  : budgetNumber(c.frequencyMonths!),
              entered,
            ),
            cell(_cols[4].width, end == null ? '' : budgetDate(end), entered),
            cell(_cols[5].width, group ? '' : money(f?.monthlyPlan), muted),
            cell(_cols[6].width, group ? '' : money(f?.planCost), muted),
            cell(_cols[7].width, group ? '' : money(f?.factCost), muted),
            cell(_cols[8].width, money(f?.planBase), muted),
            cell(_cols[9].width, money(f?.factBase), muted),
            SizedBox(
              width: _cols[10].width,
              child: urgency == null
                  ? null
                  : Align(
                      alignment: Alignment.centerRight,
                      child: ParamValue.urgency(urgency!.toStringAsFixed(0)),
                    ),
            ),
            SizedBox(
              width: _actionsWidth,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    key: ValueKey('budget-add-sub-${c.id}'),
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    tooltip: 'Add sub-category',
                    icon: const Icon(Icons.subdirectory_arrow_right),
                    onPressed: () =>
                        BudgetCategoryDialog.show(context, parentId: c.id),
                  ),
                  IconButton(
                    key: ValueKey('budget-delete-category-${c.id}'),
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteCategory(context, ref, c),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- transactions -----------------------------------------------------------

class _TransactionsView extends ConsumerStatefulWidget {
  const _TransactionsView();

  @override
  ConsumerState<_TransactionsView> createState() => _TransactionsViewState();
}

class _TransactionsViewState extends ConsumerState<_TransactionsView> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return _loading(ref.watch(budgetViewProvider), (view) {
      final cats = view.categoryById;
      final accounts = view.accountById;
      final now = DateTime.now().toUtc();
      final items = [
        for (final t in view.transactions)
          if (_query.isEmpty ||
              [
                t.row.name,
                cats[t.row.categoryId]?.name ?? '',
                t.actionName ?? '',
              ].any((s) => s.toLowerCase().contains(_query)))
            t,
      ];
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: TextField(
              key: const ValueKey('budget-transactions-search'),
              decoration: const InputDecoration(
                hintText: 'Search by name, category or action',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const Center(child: Text('No transactions yet.'))
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final t = items[i];
                      final prev = i == 0 ? null : items[i - 1];
                      final newDay =
                          prev == null ||
                          budgetDate(prev.date) != budgetDate(t.date);
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
  });

  final BudgetTxItem item;
  final BudgetCategory? category;
  final String? currency;

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
    return _card(
      padding: EdgeInsets.zero,
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          key: ValueKey('budget-tx-${t.id}'),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          dense: true,
          title: Text(
            [
              category?.name ?? 'No category',
              if (t.name.isNotEmpty) t.name,
            ].join(' · '),
          ),
          subtitle: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              if (detail != null) Text(detail),
              if (t.actionId != null)
                InkWell(
                  key: ValueKey('budget-tx-action-${t.id}'),
                  onTap: () => openActionById(context, ref, t.actionId!),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.bolt_outlined, size: 14),
                      Text(item.actionName ?? 'Action'),
                    ],
                  ),
                ),
            ],
          ),
          onTap: () => BudgetTransactionDialog.show(context, existing: item),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${budgetMoney(amount, sign: true)} ${currency ?? ''}'.trim(),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: amount < 0 ? scheme.error : Colors.green,
                ),
              ),
              IconButton(
                key: ValueKey('budget-delete-tx-${t.id}'),
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _deleteTransaction(context, ref, t),
              ),
            ],
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
