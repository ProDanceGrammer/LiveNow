import 'dart:async';

import 'package:drift/drift.dart' show Variable;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/global_search_index.dart';
import '../../domain/global_search.dart';
import '../../domain/growth_rules.dart' show metricLabel;
import '../budget_providers.dart' show BudgetTxItem;
import '../dialog_stack.dart';
import '../open_entity.dart';
import '../providers.dart';
import '../root_navigator.dart';
import '../form_providers.dart' show formServiceProvider;
import '../screens/templates_screen.dart' show TemplatesScreen;
import '../time_format.dart';
import 'app_toast.dart' show showMissingToast;
import 'budget_dialogs.dart' show BudgetCategoryDialog, BudgetTransactionDialog;
import 'direction_badge.dart' show emojiLabelStyle;
import 'form_builder.dart' show FormBuilderDialog;
import 'param_icons.dart';
import 'plan_dialogs.dart' show PlanItemEditorDialog;
import '../../core/time_codec.dart';

/// The Ctrl+K window: one search over actions, templates, directions, budget
/// categories and transactions (plus forms and plan items). A compact panel at the
/// top: the text field, one row of section chips, an "updated" menu and the
/// results (whole-word matches first, then the rest; see `searchHits`). Enter or
/// a tap opens the thing in its own editor; Esc closes.
class GlobalSearchDialog extends ConsumerStatefulWidget {
  const GlobalSearchDialog({
    super.key,
    this.sections = const {},
    this.initialQuery = '',
  });

  /// Sections that are chosen when it opens (empty = all).
  final Set<SearchSection> sections;
  final String initialQuery;

  static VoidCallback? _close;

  /// True while the window is on screen.
  static bool get isOpen => _close != null;

  /// Opens it, or closes it when it is already open (Ctrl+K twice).
  static Future<void> toggle(
    BuildContext context, {
    Set<SearchSection> sections = const {},
    String initialQuery = '',
  }) {
    final close = _close;
    if (close != null) {
      close();
      return Future.value();
    }
    return showStackedDialog<void>(
      context: context,
      builder: (_) => GlobalSearchDialog(
        sections: sections,
        initialQuery: initialQuery,
      ),
    );
  }

  @override
  ConsumerState<GlobalSearchDialog> createState() => _GlobalSearchDialogState();
}

class _GlobalSearchDialogState extends ConsumerState<GlobalSearchDialog> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _listScroll = ScrollController();
  List<SearchHit>? _all;
  late Set<SearchSection> _sections = {...widget.sections};
  UpdatedWithin _updated = UpdatedWithin.any;
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    GlobalSearchDialog._close = _close;
    _text.text = widget.initialQuery;
    final db = ref.read(databaseProvider);
    loadSearchHits(db).then((hits) {
      if (mounted) setState(() => _all = hits);
    });
  }

  @override
  void dispose() {
    if (GlobalSearchDialog._close == _close) GlobalSearchDialog._close = null;
    _text.dispose();
    _focus.dispose();
    _listScroll.dispose();
    super.dispose();
  }

  void _close() {
    if (mounted) Navigator.of(context).pop();
  }

  List<SearchHit> _results() => searchHits(
    _all ?? const [],
    query: _text.text,
    sections: _sections,
    updated: _updated,
    nowUtc: DateTime.now().toUtc(),
  );

  /// Opens [hit] in its own editor on top of everything and closes the window.
  /// Everything that needs `ref` is read BEFORE the window goes away.
  void _open(SearchHit hit) {
    final overlay = rootNavigatorKey.currentState?.overlay;
    if (overlay == null || !overlay.mounted) return;
    final root = overlay.context;
    final opener = openSearchHit(root, ref, hit);
    Navigator.of(context).pop();
    unawaited(opener);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final results = _results();
    if (results.isEmpty) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _selected = (_selected + 1).clamp(0, results.length - 1));
      _scrollToSelected();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() => _selected = (_selected - 1).clamp(0, results.length - 1));
      _scrollToSelected();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _scrollToSelected() {
    if (!_listScroll.hasClients) return;
    const rowHeight = 56.0;
    final top = _selected * rowHeight;
    final p = _listScroll.position;
    if (top < p.pixels) {
      _listScroll.jumpTo(top);
    } else if (top + rowHeight > p.pixels + p.viewportDimension) {
      _listScroll.jumpTo(top + rowHeight - p.viewportDimension);
    }
  }

  Widget _sectionIcon(SearchSection s, Color color) => switch (s) {
    SearchSection.actions => Icon(Icons.checklist_rounded, size: 20, color: color),
    SearchSection.templates => Icon(Icons.copy_all_outlined, size: 20, color: color),
    SearchSection.directions => Icon(Icons.insights, size: 20, color: color),
    SearchSection.categories => ParamIcon(Param.categories, size: 20, color: color),
    SearchSection.transactions => ParamIcon(Param.transactions, size: 20, color: color),
    SearchSection.forms => Icon(Icons.fact_check_outlined, size: 20, color: color),
    SearchSection.plans => Icon(Icons.event_repeat, size: 20, color: color),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = _results();
    if (_selected >= results.length) _selected = 0;
    final muted = theme.colorScheme.onSurfaceVariant;

    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.fromLTRB(16, 56, 16, 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 560),
        child: Focus(
          onKeyEvent: _onKey,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const ValueKey('global-search-field'),
                  controller: _text,
                  focusNode: _focus,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search everything',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    suffixIcon: _text.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setState(_text.clear),
                          ),
                  ),
                  onChanged: (_) => setState(() => _selected = 0),
                  onSubmitted: (_) {
                    if (results.isNotEmpty) _open(results[_selected]);
                  },
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ChoiceChip(
                      key: const ValueKey('global-search-section-all'),
                      label: const Text('All'),
                      visualDensity: VisualDensity.compact,
                      selected: _sections.isEmpty,
                      onSelected: (_) => setState(() {
                        _sections = {};
                        _selected = 0;
                      }),
                    ),
                    for (final s in SearchSection.values)
                      ChoiceChip(
                        key: ValueKey('global-search-section-${s.name}'),
                        label: Text(s.label),
                        visualDensity: VisualDensity.compact,
                        selected: _sections.contains(s),
                        onSelected: (_) => setState(() {
                          // One section at a time; tapping it again = all.
                          _sections = _sections.contains(s) ? {} : {s};
                          _selected = 0;
                        }),
                      ),
                    PopupMenuButton<UpdatedWithin>(
                      key: const ValueKey('global-search-updated'),
                      tooltip: 'Last updated',
                      onSelected: (v) => setState(() {
                        _updated = v;
                        _selected = 0;
                      }),
                      itemBuilder: (_) => [
                        for (final u in UpdatedWithin.values)
                          PopupMenuItem(
                            key: ValueKey('global-search-updated-${u.name}'),
                            value: u,
                            child: Text(u.label),
                          ),
                      ],
                      child: Chip(
                        visualDensity: VisualDensity.compact,
                        avatar: const Icon(Icons.schedule, size: 16),
                        label: Text(
                          _updated == UpdatedWithin.any
                              ? 'Updated'
                              : 'Updated: ${_updated.label}',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Flexible(
                  child: _all == null
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : results.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: Text(
                              key: const ValueKey('global-search-empty'),
                              'Nothing found',
                              style: TextStyle(color: muted),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _listScroll,
                          shrinkWrap: true,
                          itemExtent: 56,
                          itemCount: results.length,
                          itemBuilder: (context, i) =>
                              _row(context, results[i], i == _selected, muted),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, SearchHit h, bool selected, Color muted) {
    final scheme = Theme.of(context).colorScheme;
    final changed = h.changedAt;
    final sub = [
      h.section.label,
      if (h.subtitle.isNotEmpty) h.subtitle,
      if (changed != null)
        'updated ${formatUtcDateTime(changed, includeTime: false)}',
    ].join(' · ');
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.12)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        key: ValueKey('global-search-hit-${h.section.name}-${h.id}'),
        borderRadius: BorderRadius.circular(10),
        onTap: () => _open(h),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              _sectionIcon(h.section, muted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      h.section == SearchSection.directions
                          ? metricLabel(h.title, h.icon)
                          : (h.title.isEmpty ? '(no name)' : h.title),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: emojiLabelStyle.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the editor of [hit]. [context] must stay mounted (the root navigator's
/// own overlay context), [ref] is used only before the first await.
Future<void> openSearchHit(
  BuildContext context,
  WidgetRef ref,
  SearchHit hit,
) async {
  final db = ref.read(databaseProvider);
  final forms = ref.read(formServiceProvider);
  switch (hit.section) {
    case SearchSection.actions:
      return openActionById(context, ref, hit.id);
    case SearchSection.directions:
      return openDirectionById(context, ref, hit.id);
    case SearchSection.templates:
      final row = await (db.select(
        db.actionTemplatesTable,
      )..where((t) => t.id.equals(hit.id))).getSingleOrNull();
      if (!context.mounted) return;
      if (row == null) return showMissingToast(context, 'template');
      await TemplatesScreen.showEditTemplate(context, row);
    case SearchSection.categories:
      final row = await (db.select(
        db.budgetCategoriesTable,
      )..where((t) => t.id.equals(hit.id))).getSingleOrNull();
      if (!context.mounted) return;
      if (row == null) return showMissingToast(context, 'category');
      await BudgetCategoryDialog.show(context, existing: row);
    case SearchSection.transactions:
      final item = await _transactionItem(db, hit.id);
      if (!context.mounted) return;
      if (item == null) return showMissingToast(context, 'transaction');
      await BudgetTransactionDialog.show(context, existing: item);
    case SearchSection.forms:
      final item = await forms.get(hit.id);
      if (!context.mounted) return;
      if (item == null) return showMissingToast(context, 'form');
      await FormBuilderDialog.show(context, existing: item);
    case SearchSection.plans:
      await PlanItemEditorDialog.show(context, itemId: hit.id);
  }
}

/// One transaction as the Transactions list holds it (live effective date and
/// the linked action's name).
Future<BudgetTxItem?> _transactionItem(AppDatabase db, String id) async {
  final rows = await db
      .customSelect(
        'SELECT t.*, a.start_at AS action_start, a.name AS action_name '
        'FROM budget_transactions t '
        'LEFT JOIN actions a ON a.id = t.action_id WHERE t.id = ?',
        variables: [Variable<String>(id)],
        readsFrom: {db.budgetTransactionsTable, db.actionsTable},
      )
      .get();
  if (rows.isEmpty) return null;
  final r = rows.first;
  return BudgetTxItem(
    row: db.budgetTransactionsTable.map(r.data),
    date:
        dateTimeFromDb(r.read<String?>('action_start')) ??
        dateTimeFromDb(r.read<String>('occurred_at'))!,
    actionName: r.read<String?>('action_name'),
  );
}
