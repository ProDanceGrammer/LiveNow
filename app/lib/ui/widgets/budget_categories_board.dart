import '../search_targets.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../domain/budget_category_view.dart';
import '../budget_category_rows.dart';
import '../budget_providers.dart';
import '../device_prefs.dart';
import '../layout.dart';
import '../saved_view_hooks.dart';
import '../saved_views_bar.dart';
import '../theme/glass_theme.dart';
import '../urgency_colors.dart';
import 'account_icon.dart';
import 'glass.dart';
import 'param_icons.dart';
import 'sort_chips.dart';
import 'sort_icons.dart';

/// Counts row builds (tests assert that an unchanged snapshot rebuilds none).
class CategoryPerfCounters {
  static int rowBuilds = 0;

  static void reset() => rowBuilds = 0;
}

const double _kWideRow = 62;
const double _kPhoneRow = 82; // two description rows + the bar

/// Device-local: the phone's Sort / search / Flat toolbar is hidden.
const kCategoriesToolbarHiddenPref = 'categories_toolbar_hidden';
const double _kPlanW = 104;
const double _kFactW = 104;
const double _kUrgencyW = 70;

/// The Categories tab: ONE glass board (search, sort levels, a Flat switch, then
/// the rows). Rows are plain, fixed height, a handful of widgets each; the data
/// comes ready-made from [budgetCategoryRowsProvider] and a row skips its
/// rebuild when its own numbers did not change.
class BudgetCategoriesBoard extends ConsumerStatefulWidget {
  const BudgetCategoriesBoard({super.key, required this.onOpen});

  final void Function(BudgetCategory category) onOpen;

  @override
  ConsumerState<BudgetCategoriesBoard> createState() =>
      _BudgetCategoriesBoardState();
}

class _BudgetCategoriesBoardState extends ConsumerState<BudgetCategoriesBoard>
    with SearchTargetState<BudgetCategoriesBoard> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    registerSearchTarget();
  }

  // Ctrl+F: focus the search field and select its text.
  @override
  void openSearch() => focusSearchField(_searchFocus, _search);
  Timer? _debounce;

  /// The row widgets of the last build, by category id: an unchanged row is
  /// handed back as the identical instance.
  final _rowCache = <String, _CategoryBoardRow>{};

  _CategoryBoardRow _rowFor(
    CategoryRowView vm,
    bool phone,
    bool showUrgency,
    String currency,
  ) {
    final old = _rowCache[vm.id];
    if (old != null &&
        old.phone == phone &&
        old.showUrgency == showUrgency &&
        old.currency == currency &&
        old.vm == vm) {
      return old;
    }
    return _rowCache[vm.id] = _CategoryBoardRow(
      key: ValueKey(vm.id),
      vm: vm,
      phone: phone,
      showUrgency: showUrgency,
      currency: currency,
      onOpen: widget.onOpen,
      onToggle: _toggle,
    );
  }

  @override
  void dispose() {
    unregisterSearchTarget();
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearch(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      if (mounted) {
        ref.read(budgetCategoryQueryProvider.notifier).state = text.trim();
      }
    });
  }

  void _toggle(String id) {
    final n = ref.read(budgetCategoryCollapsedProvider.notifier);
    final next = {...n.state};
    if (!next.remove(id)) next.add(id);
    n.state = next;
  }

  Widget _sortRow() {
    final sort = ref.watch(budgetCategorySortProvider);
    final flat = ref.watch(budgetCategoryFlatProvider);
    final used = {for (final k in sort) k.field};
    void set(List<CategorySortKey> v) =>
        ref.read(budgetCategorySortProvider.notifier).state = v;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SortChipsRow(
            keyPrefix: 'cat-sort',
            chips: [
              for (final k in sort)
                SortChipData(
                  k.field.name,
                  k.field.label,
                  ascending: k.ascending,
                  icon: sortFieldIcon(k.field),
                ),
            ],
            addOptions: [
              for (final f in CategorySortField.values)
                if (!used.contains(f) &&
                    (f != CategorySortField.urgency ||
                        ref.watch(budgetShowUrgencyProvider)))
                  (f.name, f.label, sortFieldIcon(f)),
            ],
            onToggle: (i) => set([
              for (var j = 0; j < sort.length; j++)
                if (j == i) sort[j].toggled() else sort[j],
            ]),
            onRemove: (i) => set([...sort]..removeAt(i)),
            onMove: (from, to) {
              if (from == to) return;
              final list = [...sort];
              list.insert(to, list.removeAt(from));
              set(list);
            },
            // Name starts A-Z; Plan, Fact and Urgency start biggest first.
            onAdd: (id) {
              final f = CategorySortField.values.byName(id);
              set([
                ...sort,
                CategorySortKey(f, ascending: f == CategorySortField.name),
              ]);
            },
          ),
        ),
        const SizedBox(width: 8),
        _levelButtons(flat),
        const SizedBox(width: 4),
        FilterChip(
          key: const ValueKey('cat-flat'),
          visualDensity: VisualDensity.compact,
          label: const Text('Flat'),
          tooltip: 'Only categories that hold transactions, without groups',
          selected: flat,
          onSelected: (v) =>
              ref.read(budgetCategoryFlatProvider.notifier).state = v,
        ),
      ],
    );
  }

  /// Opens or folds the whole hierarchy: everything, only the parents (level
  /// 1) or 2-4 levels. Off in Flat mode and while searching (a search ignores
  /// folding anyway).
  Widget _levelButtons(bool flat) {
    final searching = ref.watch(budgetCategoryQueryProvider).isNotEmpty;
    final enabled = !flat && !searching;
    void apply(int? level) {
      final cats = ref.read(budgetViewProvider).value?.categories ?? const [];
      ref.read(budgetCategoryCollapsedProvider.notifier).state =
          collapsedForLevel([
            for (final c in cats) CategoryInfo(c.id, c.name, c.parentId),
          ], level);
    }

    final entries = <(String, String, IconData?, int?)>[
      ('all', 'Open every level', Icons.unfold_more, null),
      ('1', 'Parents only', Icons.unfold_less, 1),
      ('2', 'Show 2 levels', null, 2),
      ('3', 'Show 3 levels', null, 3),
      ('4', 'Show 4 levels', null, 4),
    ];
    if (usePhoneLayout(context)) {
      return PopupMenuButton<int>(
        key: const ValueKey('cat-levels-menu'),
        tooltip: 'Open or fold levels',
        enabled: enabled,
        icon: const Icon(Icons.account_tree_outlined, size: 20),
        onSelected: (v) => apply(v == 0 ? null : v),
        itemBuilder: (_) => [
          for (final e in entries)
            PopupMenuItem(value: e.$4 ?? 0, child: Text(e.$2)),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final e in entries)
          Tooltip(
            message: e.$2,
            child: InkWell(
              key: ValueKey('cat-level-${e.$1}'),
              borderRadius: BorderRadius.circular(8),
              onTap: enabled ? () => apply(e.$4) : null,
              child: SizedBox(
                width: 32,
                height: 32,
                child: Center(
                  child: e.$3 != null
                      ? Icon(e.$3, size: 20)
                      : Text(
                          e.$1,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: enabled
                                ? null
                                : Theme.of(context).disabledColor,
                          ),
                        ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _header(BuildContext context, bool showUrgency) {
    final s = Theme.of(context).textTheme.labelMedium;
    final base = ref.watch(
      budgetSettingsProvider.select((v) => v.value?.baseCurrency ?? 'EUR'),
    );
    Widget cell(double w, Widget child) =>
        SizedBox(width: w, child: Center(child: child));
    // Hover (Windows) or tap (touch) explains the currency of the sums.
    Widget money(Param p, String name) => Tooltip(
      message: '$name: all sums are counted in $base (the main currency from '
          'Budget settings), whatever currency an account is in',
      triggerMode: TooltipTriggerMode.tap,
      child: ParamIcon(p, size: 18, tooltip: false),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text('Category', style: s),
            ),
          ),
          cell(_kPlanW, money(Param.plan, 'Plan')),
          cell(_kFactW, money(Param.actual, 'Fact')),
          if (showUrgency)
            cell(_kUrgencyW, const ParamIcon(Param.urgency, size: 18)),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(budgetCategoryRowsProvider)?.rows;
    final currency = ref.watch(
      budgetSettingsProvider.select((v) => v.value?.baseCurrency ?? 'EUR'),
    );
    final phone = usePhoneLayout(context);
    final query = ref.watch(budgetCategoryQueryProvider);
    final showUrgency = ref.watch(budgetShowUrgencyProvider);
    final toolbarHidden =
        phone &&
        ref.watch(
          devicePrefBoolProvider((kCategoriesToolbarHiddenPref, false)),
        );

    final Widget list;
    if (rows == null) {
      list = const Center(child: CircularProgressIndicator());
    } else if (rows.isEmpty) {
      list = Center(
        child: Text(query.isEmpty ? 'No categories yet.' : 'No matching categories.'),
      );
    } else {
      final indexById = {for (var i = 0; i < rows.length; i++) rows[i].id: i};
      list = ListView.builder(
        padding: const EdgeInsets.fromLTRB(4, 2, 4, 88),
        // A fixed height: layout cost is O(visible rows).
        itemExtent: phone ? _kPhoneRow : _kWideRow,
        itemCount: rows.length,
        findChildIndexCallback: (key) =>
            key is ValueKey<String> ? indexById[key.value] : null,
        itemBuilder: (context, i) =>
            _rowFor(rows[i], phone, showUrgency, currency),
      );
      // Rows that left the list are forgotten.
      if (_rowCache.length > rows.length * 2 + 16) {
        _rowCache.removeWhere((id, _) => !indexById.containsKey(id));
      }
    }

    return SavedViewsDefaultLoader(
      hooks: categoryViewHooks(ref),
      child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: GlassSurface(
        radius: GlassTheme.radiusPanel,
        shadow: false,
        blurWindow: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Row(
                children: [
                  // A phone can hide the whole toolbar (search, sort, Flat,
                  // levels) to give the list the room.
                  if (!toolbarHidden)
                    Expanded(
                      child: TextField(
                        key: const ValueKey('budget-categories-search'),
                        controller: _search,
                        focusNode: _searchFocus,
                        onChanged: _onSearch,
                        decoration: const InputDecoration(
                          hintText: 'Search categories',
                          prefixIcon: Icon(Icons.search),
                          isDense: true,
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  if (phone)
                    IconButton(
                      key: const ValueKey('cat-toolbar-toggle'),
                      tooltip: toolbarHidden
                          ? 'Show search, sort and filters'
                          : 'Hide search, sort and filters',
                      icon: Badge(
                        isLabelVisible:
                            toolbarHidden &&
                            (query.isNotEmpty ||
                                ref.watch(budgetCategoryFlatProvider)),
                        smallSize: 8,
                        child: Icon(
                          toolbarHidden ? Icons.tune : Icons.expand_less,
                        ),
                      ),
                      onPressed: () => setDevicePrefBool(
                        ref,
                        kCategoriesToolbarHiddenPref,
                        !toolbarHidden,
                      ),
                    ),
                ],
              ),
            ),
            if (!toolbarHidden)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                child: _sortRow(),
              ),
            if (!toolbarHidden)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: SavedViewsBar(hooks: categoryViewHooks(ref)),
              ),
            if (!phone)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _header(context, showUrgency),
              ),
            // A row's tint is an `Ink`, which paints on the nearest Material:
            // a local one, clipped to the list, keeps tinted rows from bleeding
            // over the header above or the screen edge below.
            Expanded(
              child: ClipRect(
                child: Material(type: MaterialType.transparency, child: list),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}

/// One category line: ~10 widgets, no tooltips, no per-row provider. The board
/// reuses the SAME widget instance while the row's view-model is unchanged, so
/// Flutter skips its rebuild (a widget's `==` cannot be overridden).
class _CategoryBoardRow extends StatelessWidget {
  const _CategoryBoardRow({
    super.key,
    required this.vm,
    required this.phone,
    required this.showUrgency,
    required this.currency,
    required this.onOpen,
    required this.onToggle,
  });

  final CategoryRowView vm;
  final bool phone;
  final bool showUrgency;

  /// The main currency code shown right of the phone's plan / fact figures.
  final String currency;
  final void Function(BudgetCategory) onOpen;
  final void Function(String) onToggle;

  @override
  Widget build(BuildContext context) {
    CategoryPerfCounters.rowBuilds++;
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final c = vm.category;
    // The urgency tint of the nearest upcoming action: the scale, white when
    // that action has no direction, none without an action.
    final tint = vm.unlinked
        ? emptyColors(dark: dark)
        : vm.urgency != null
        ? urgencyColors(vm.urgency!, dark: dark)
        : null;
    final fg = tint?.fg;
    final base = TextStyle(fontSize: 13.5, color: fg);
    final small = TextStyle(
      fontSize: 11.5,
      color: (fg ?? scheme.onSurface).withValues(alpha: 0.65),
    );
    final over = vm.overPlan;
    // The bar: a standard progress bar with a 100 % marker; green within the
    // plan, red beyond the marker (income above plan is good: green). A tinted
    // row keeps to its own text colour (the part beyond the marker fainter).
    final geo = barGeometry(plan: vm.plan, fact: vm.fact, isIncome: c.isIncome);
    final inPlanColor = fg ?? Colors.green.shade600;
    final overColor = fg == null
        ? (geo.over ? scheme.error : Colors.green.shade600)
        : fg.withValues(alpha: 0.5);

    final leading = vm.hasChildren
        ? InkResponse(
            key: ValueKey('budget-cat-toggle-${vm.id}'),
            radius: 16,
            onTap: () => onToggle(vm.id),
            child: Icon(
              vm.collapsed ? Icons.chevron_right : Icons.expand_more,
              size: 20,
              color: fg,
            ),
          )
        : Icon(
            c.isIncome ? Icons.south_west : Icons.north_east,
            size: 14,
            color: fg ?? (c.isIncome ? Colors.green : scheme.error),
          );

    final name = Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: base.copyWith(
                    fontWeight: vm.hasChildren ? FontWeight.w700 : null,
                  ),
                ),
              ),
              if (vm.noRate)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(Icons.warning_amber_rounded, size: 14, color: fg),
                ),
            ],
          ),
          if (phone) ...[
            // Two short rows: `amount per unit`, then `each N months · until
            // ... in <account>`.
            if (vm.amountLine != null)
              Text(
                vm.amountLine!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: small,
              ),
            if (vm.schedule != null || vm.accountName != null)
              Text.rich(
                TextSpan(
                  children: [
                    if (vm.schedule != null) TextSpan(text: vm.schedule),
                    if (vm.accountName != null) ...[
                      TextSpan(text: vm.schedule == null ? 'in ' : ' in '),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: AccountIcon(icon: vm.accountIcon, size: 12),
                      ),
                      TextSpan(text: ' ${vm.accountName}'),
                    ],
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: small,
              ),
          ] else if (vm.subline != null || vm.accountName != null)
            Text.rich(
              TextSpan(
                children: [
                  if (vm.subline != null) TextSpan(text: vm.subline),
                  if (vm.accountName != null) ...[
                    TextSpan(text: vm.subline == null ? 'in ' : ' in '),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: AccountIcon(icon: vm.accountIcon, size: 12),
                    ),
                    TextSpan(text: ' ${vm.accountName}'),
                  ],
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: small,
            ),
        ],
      ),
    );

    Widget figures;
    if (phone) {
      // Each figure: its icon on the left, the number, then the currency code
      // (small) on the right.
      Widget line(Param param, String text, TextStyle style) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ParamIcon(param, size: 13, tooltip: false, color: fg),
          const SizedBox(width: 4),
          Text(text, style: style),
          const SizedBox(width: 3),
          Text(currency, style: small),
        ],
      );
      figures = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          line(Param.plan, vm.planText, base),
          line(
            Param.actual,
            vm.factText,
            base.copyWith(
              fontWeight: FontWeight.w600,
              color: fg ?? (over ? scheme.error : null),
            ),
          ),
        ],
      );
    } else {
      figures = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: _kPlanW,
            child: Text(vm.planText, textAlign: TextAlign.right, style: base),
          ),
          SizedBox(
            width: _kFactW,
            child: Text(
              vm.factText,
              textAlign: TextAlign.right,
              style: base.copyWith(
                fontWeight: FontWeight.w600,
                color: fg ?? (over ? scheme.error : null),
              ),
            ),
          ),
        ],
      );
    }

    final urgency = !showUrgency
        ? const SizedBox.shrink()
        : vm.urgency == null
        ? SizedBox(width: phone ? 0 : _kUrgencyW)
        : SizedBox(
            width: phone ? 52 : _kUrgencyW,
            child: Text(
              vm.urgency!.toStringAsFixed(0),
              textAlign: TextAlign.center,
              style: base.copyWith(fontWeight: FontWeight.w700),
            ),
          );

    final content = Row(
      children: [
        SizedBox(width: 4.0 + vm.depth * 16),
        SizedBox(width: 24, child: Center(child: leading)),
        const SizedBox(width: 4),
        name,
        figures,
        urgency,
        const SizedBox(width: 12),
      ],
    );

    final row = InkWell(
      key: ValueKey('budget-category-${vm.id}'),
      borderRadius: BorderRadius.circular(12),
      onTap: () => onOpen(c),
      child: Stack(
        children: [
          // The text keeps clear of the bar below it.
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: content,
            ),
          ),
          // "Used" (fact against plan): a bolder bar under the text, the full
          // row wide; the longest ratio of the list fills it and the others are
          // proportional (a tick marks 100 % once somebody is over plan).
          Positioned(
            left: 8,
            right: 8,
            bottom: 3,
            height: 5,
            child: CustomPaint(
              painter: _PlanBarPainter(
                geo.fill,
                geo.marker,
                geo.showMarker,
                inPlanColor,
                overColor,
                (fg ?? scheme.onSurface).withValues(alpha: 0.16),
                (fg ?? scheme.onSurface).withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: tint == null
          ? row
          : Ink(
              decoration: BoxDecoration(
                color: tint.bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: row,
            ),
    );
  }
}

/// How much of the plan is used: a rounded track with a fill (capped at the
/// full width; spending above the plan is shown by the row's colour).
class _PlanBarPainter extends CustomPainter {
  _PlanBarPainter(
    this.fill,
    this.marker,
    this.showMarker,
    this.inPlan,
    this.over,
    this.track,
    this.tick,
  );

  /// Fractions of the track ([barGeometry]): the filled part, where 100 % is.
  final double fill;
  final double marker;
  final bool showMarker;
  final Color inPlan;
  final Color over;
  final Color track;
  final Color tick;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    RRect segment(double from, double to) => RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * from.clamp(0.0, 1.0),
        0,
        size.width * (to.clamp(0.0, 1.0) - from.clamp(0.0, 1.0)),
        size.height,
      ),
      r,
    );
    canvas.drawRRect(segment(0, 1), Paint()..color = track);
    if (fill <= 0) return;
    if (showMarker) {
      // Up to 100 %: the plan colour; beyond the marker: over.
      canvas.drawRRect(segment(0, marker), Paint()..color = inPlan);
      if (fill > marker) {
        canvas.drawRect(
          Rect.fromLTWH(
            size.width * marker,
            0,
            size.width * (fill - marker),
            size.height,
          ),
          Paint()..color = over,
        );
      }
      // The 100 % marker.
      canvas.drawRect(
        Rect.fromLTWH(size.width * marker - 0.75, -2, 1.5, size.height + 4),
        Paint()..color = tick,
      );
    } else {
      canvas.drawRRect(segment(0, fill), Paint()..color = over);
    }
  }

  @override
  bool shouldRepaint(_PlanBarPainter old) =>
      old.fill != fill ||
      old.marker != marker ||
      old.showMarker != showMarker ||
      old.inPlan != inPlan ||
      old.over != over ||
      old.track != track ||
      old.tick != tick;
}
