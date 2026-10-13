import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../domain/budget_category_view.dart';
import '../budget_category_rows.dart';
import '../layout.dart';
import '../theme/glass_theme.dart';
import '../urgency_colors.dart';
import 'glass.dart';
import 'param_icons.dart';
import 'sort_chips.dart';
import 'sort_icons.dart';

/// Counts row builds (tests assert that an unchanged snapshot rebuilds none).
class CategoryPerfCounters {
  static int rowBuilds = 0;

  static void reset() => rowBuilds = 0;
}

const double _kWideRow = 56;
const double _kPhoneRow = 66;
const double _kPlanW = 104;
const double _kFactW = 104;
const double _kBarW = 84;
const double _kUrgencyW = 70;

/// The Categories tab: ONE glass board (search, sort levels, a Flat switch, then
/// the rows). Rows are plain, fixed height, a handful of widgets each; the data
/// comes ready-made from [budgetCategoryRowsProvider] and a row skips its
/// rebuild when its own numbers did not change.
class BudgetCategoriesBoard extends ConsumerStatefulWidget {
  const BudgetCategoriesBoard({
    super.key,
    required this.onOpen,
    required this.onAddSub,
    required this.onDelete,
  });

  final void Function(BudgetCategory category) onOpen;
  final void Function(String parentId) onAddSub;
  final void Function(BudgetCategory category) onDelete;

  @override
  ConsumerState<BudgetCategoriesBoard> createState() =>
      _BudgetCategoriesBoardState();
}

class _BudgetCategoriesBoardState extends ConsumerState<BudgetCategoriesBoard> {
  final _search = TextEditingController();
  Timer? _debounce;

  /// The row widgets of the last build, by category id: an unchanged row is
  /// handed back as the identical instance.
  final _rowCache = <String, _CategoryBoardRow>{};

  _CategoryBoardRow _rowFor(CategoryRowView vm, bool phone) {
    final old = _rowCache[vm.id];
    if (old != null && old.phone == phone && old.vm == vm) return old;
    return _rowCache[vm.id] = _CategoryBoardRow(
      key: ValueKey(vm.id),
      vm: vm,
      phone: phone,
      onOpen: widget.onOpen,
      onAddSub: widget.onAddSub,
      onDelete: widget.onDelete,
      onToggle: _toggle,
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
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
                if (!used.contains(f)) (f.name, f.label, sortFieldIcon(f)),
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

  Widget _header(BuildContext context) {
    final s = Theme.of(context).textTheme.labelMedium;
    Widget cell(double w, Widget child) =>
        SizedBox(width: w, child: Center(child: child));
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
      child: Row(
        children: [
          Expanded(child: Padding(padding: const EdgeInsets.only(left: 8), child: Text('Category', style: s))),
          cell(_kPlanW, const ParamIcon(Param.plan, size: 18)),
          cell(_kFactW, const ParamIcon(Param.actual, size: 18)),
          cell(_kBarW, Text('Used', style: s)),
          cell(_kUrgencyW, const ParamIcon(Param.urgency, size: 18)),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(budgetCategoryRowsProvider)?.rows;
    final phone = usePhoneLayout(context);
    final query = ref.watch(budgetCategoryQueryProvider);

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
        itemBuilder: (context, i) => _rowFor(rows[i], phone),
      );
      // Rows that left the list are forgotten.
      if (_rowCache.length > rows.length * 2 + 16) {
        _rowCache.removeWhere((id, _) => !indexById.containsKey(id));
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: GlassSurface(
        radius: GlassTheme.radiusPanel,
        shadow: false,
        blurWindow: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: TextField(
                key: const ValueKey('budget-categories-search'),
                controller: _search,
                onChanged: _onSearch,
                decoration: const InputDecoration(
                  hintText: 'Search categories',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
              child: _sortRow(),
            ),
            if (!phone) _header(context),
            Expanded(child: list),
          ],
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
    required this.onOpen,
    required this.onAddSub,
    required this.onDelete,
    required this.onToggle,
  });

  final CategoryRowView vm;
  final bool phone;
  final void Function(BudgetCategory) onOpen;
  final void Function(String) onAddSub;
  final void Function(BudgetCategory) onDelete;
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
    final barColor = fg ?? (over ? scheme.error : scheme.primary);

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
          if (vm.subline != null)
            Text(
              vm.subline!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: small,
            ),
        ],
      ),
    );

    final menu = PopupMenuButton<String>(
      key: ValueKey('budget-category-menu-${vm.id}'),
      padding: EdgeInsets.zero,
      iconSize: 18,
      iconColor: fg,
      onSelected: (v) => v == 'sub' ? onAddSub(vm.id) : onDelete(c),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'sub', child: Text('Add sub-category')),
        PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );

    Widget figures;
    if (phone) {
      figures = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(vm.planText, style: base),
          Text(
            vm.factText,
            style: base.copyWith(
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
          SizedBox(
            width: _kBarW,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: CustomPaint(
                size: const Size(double.infinity, 6),
                painter: _PlanBarPainter(
                  vm.ratio,
                  barColor,
                  (fg ?? scheme.onSurface).withValues(alpha: 0.16),
                ),
              ),
            ),
          ),
        ],
      );
    }

    final urgency = vm.urgency == null
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
        SizedBox(width: 40, child: Center(child: menu)),
      ],
    );

    final row = InkWell(
      key: ValueKey('budget-category-${vm.id}'),
      borderRadius: BorderRadius.circular(12),
      onTap: () => onOpen(c),
      child: phone
          ? Stack(
              children: [
                Positioned.fill(child: content),
                Positioned(
                  left: 40.0 + vm.depth * 16,
                  right: 12,
                  bottom: 4,
                  height: 3,
                  child: CustomPaint(
                    painter: _PlanBarPainter(
                      vm.ratio,
                      barColor,
                      (fg ?? scheme.onSurface).withValues(alpha: 0.16),
                    ),
                  ),
                ),
              ],
            )
          : content,
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
  _PlanBarPainter(this.ratio, this.fill, this.track);

  final double? ratio;
  final Color fill;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    final full = RRect.fromRectAndRadius(Offset.zero & size, r);
    canvas.drawRRect(full, Paint()..color = track);
    final v = ratio;
    if (v == null || v <= 0) return;
    final w = size.width * v.clamp(0.0, 1.0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, size.height), r),
      Paint()..color = fill,
    );
  }

  @override
  bool shouldRepaint(_PlanBarPainter old) =>
      old.ratio != ratio || old.fill != fill || old.track != track;
}
