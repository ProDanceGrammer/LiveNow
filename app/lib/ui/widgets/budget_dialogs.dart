import 'dart:io' show Platform;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/time_codec.dart';
import '../../data/database.dart';
import '../../domain/budget_rules.dart';
import '../../domain/budget_service.dart';
import '../../domain/name_sort.dart';
import '../account_icon_codec.dart';
import '../budget_category_rows.dart' show categoryLine;
import '../budget_providers.dart';
import '../dialog_stack.dart';
import '../open_entity.dart';
import '../providers.dart';
import '../undo.dart' show offerUndo, undoHistoryProvider;
import 'account_icon.dart';
import 'action_picker_dialog.dart';
import 'app_toast.dart';
import 'budget_format.dart';
import 'category_transactions_panel.dart';
import 'param_icons.dart';
import '../theme/glass_theme.dart';
import '../time_format.dart' show formatUtcDateTime;
import 'glass_pill_selector.dart';
import 'section_block.dart';

const _dialogWidth = 440.0;

Widget _dialogBody(List<Widget> children) => SizedBox(
  width: _dialogWidth,
  child: SingleChildScrollView(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  ),
);

const _gap = SizedBox(height: 16);

/// Opens a category in its editor (used by every place that shows one).
Future<void> openBudgetCategoryById(
  BuildContext context,
  WidgetRef ref,
  String id,
) async {
  final db = ref.read(databaseProvider);
  final row = await (db.select(
    db.budgetCategoriesTable,
  )..where((t) => t.id.equals(id))).getSingleOrNull();
  if (row == null || !context.mounted) return;
  await BudgetCategoryDialog.show(context, existing: row);
}

/// Searchable list of categories; returns the chosen id. [leavesOnly] hides
/// groups (only leaves can hold transactions or be a percent source).
///
/// [excludeIds] are never offered; [allowNone] pins a "- top level -" row on
/// top that returns [kPickedNoCategory] (an empty string, so null still means
/// "cancelled").
const String kPickedNoCategory = '';

Future<String?> pickBudgetCategory(
  BuildContext context, {
  bool leavesOnly = true,
  String? excludeId,
  Set<String> excludeIds = const {},
  bool allowNone = false,
  bool allowCreate = false,
}) => showStackedDialog<String>(
  context: context,
  builder: (_) => _CategoryPickerDialog(
    leavesOnly: leavesOnly,
    excludeIds: {...excludeIds, ?excludeId},
    allowNone: allowNone,
    allowCreate: allowCreate,
  ),
);

class _CategoryPickerDialog extends ConsumerStatefulWidget {
  const _CategoryPickerDialog({
    required this.leavesOnly,
    required this.excludeIds,
    required this.allowNone,
    required this.allowCreate,
  });

  final bool leavesOnly;
  final Set<String> excludeIds;
  final bool allowNone;

  /// A pinned "Create new category" row (opens the category dialog and returns
  /// the new id), like "Create new transaction" in the action editor's picker.
  final bool allowCreate;

  @override
  ConsumerState<_CategoryPickerDialog> createState() =>
      _CategoryPickerDialogState();
}

class _CategoryPickerDialogState extends ConsumerState<_CategoryPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(budgetCategoriesProvider).value ?? const [];
    final parents = {
      for (final c in all)
        if (c.parentId != null) c.parentId!,
    };
    final byId = {for (final c in all) c.id: c};
    final rows = [
      for (final c in all)
        if (!widget.excludeIds.contains(c.id) &&
            (!widget.leavesOnly || !parents.contains(c.id)) &&
            c.name.toLowerCase().contains(_query))
          c,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return AlertDialog(
      title: const Text('Pick a category'),
      content: SizedBox(
        width: _dialogWidth,
        height: 380,
        child: Column(
          children: [
            TextField(
              key: const ValueKey('budget-category-search'),
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
            ),
            Expanded(
              child: rows.isEmpty &&
                      !(widget.allowNone && _query.isEmpty) &&
                      !widget.allowCreate
                  ? const Center(child: Text('No categories'))
                  : ListView(
                      children: [
                        if (widget.allowCreate)
                          ListTile(
                            key: const ValueKey('pick-category-new'),
                            dense: true,
                            leading: const Icon(Icons.add),
                            title: const Text('Create new category'),
                            onTap: () async {
                              final navigator = Navigator.of(context);
                              final id = await BudgetCategoryDialog.show(
                                context,
                              );
                              if (id != null) navigator.pop(id);
                            },
                          ),
                        if (widget.allowNone && _query.isEmpty)
                          ListTile(
                            key: const ValueKey('pick-category-none'),
                            dense: true,
                            leading: const Icon(Icons.vertical_align_top),
                            title: const Text('— top level —'),
                            onTap: () =>
                                Navigator.of(context).pop(kPickedNoCategory),
                          ),
                        for (final c in rows)
                          ListTile(
                            key: ValueKey('pick-category-${c.id}'),
                            dense: true,
                            title: Text(c.name),
                            // Where it sits, and "price × units per unit each
                            // N months" so similar names can be told apart.
                            subtitle: switch ([
                              if (c.parentId != null) byId[c.parentId]?.name,
                              categoryLine(c),
                            ].whereType<String>().where((s) => s.isNotEmpty)) {
                              final parts when parts.isEmpty => null,
                              final parts => Text(parts.join(' · ')),
                            },
                            onTap: () => Navigator.of(context).pop(c.id),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

// ---- accounts ---------------------------------------------------------------

class BudgetAccountDialog extends ConsumerStatefulWidget {
  const BudgetAccountDialog({super.key, this.existing});

  final BudgetAccount? existing;

  static Future<void> show(BuildContext context, {BudgetAccount? existing}) =>
      showStackedDialog<void>(
        context: context,
        builder: (_) => BudgetAccountDialog(existing: existing),
      );

  @override
  ConsumerState<BudgetAccountDialog> createState() =>
      _BudgetAccountDialogState();
}

class _BudgetAccountDialogState extends ConsumerState<BudgetAccountDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _type = TextEditingController(text: widget.existing?.type);
  late final _currency = TextEditingController(
    text: widget.existing?.currency ?? '',
  );
  late final _rate = TextEditingController(
    text: budgetNumber(widget.existing?.rateToBase ?? 1),
  );
  late final _opening = TextEditingController(
    text: budgetNumber(widget.existing?.openingBalance ?? 0),
  );

  /// The account's picture (base64 PNG), whether the user changed it in this
  /// dialog, and the reason a chosen file was refused.
  late String? _icon = widget.existing?.icon;
  bool _iconTouched = false;
  String? _iconError;

  @override
  void dispose() {
    for (final c in [_name, _type, _currency, _rate, _opening]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickIcon() async {
    // On a phone the icon may come from the Photo library or from Files; on
    // the desktop there is only the file dialog.
    var pick = ref.read(accountIconPickerProvider);
    if (Platform.isIOS || Platform.isAndroid) {
      final photos = ref.read(accountIconPhotoPickerProvider);
      final fromPhotos = await showStackedDialog<bool>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Account icon'),
          children: [
            SimpleDialogOption(
              key: const ValueKey('icon-from-photos'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const ListTile(
                leading: Icon(Icons.photo_library_outlined),
                title: Text('Photo library'),
              ),
            ),
            SimpleDialogOption(
              key: const ValueKey('icon-from-files'),
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const ListTile(
                leading: Icon(Icons.folder_outlined),
                title: Text('Files'),
              ),
            ),
          ],
        ),
      );
      if (fromPhotos == null || !mounted) return;
      if (fromPhotos) pick = photos;
    }
    final bytes = await pick();
    if (bytes == null || !mounted) return;
    try {
      final encoded = await encodeAccountIcon(bytes);
      if (!mounted) return;
      setState(() {
        _icon = encoded;
        _iconTouched = true;
        _iconError = null;
      });
    } on AccountIconException catch (e) {
      if (mounted) setState(() => _iconError = e.message);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final navigator = Navigator.of(context);
    await ref
        .read(budgetServiceProvider)
        .saveAccount(
          id: widget.existing?.id,
          name: _name.text,
          type: _type.text,
          currency: _currency.text,
          rateToBase: parseBudgetNumber(_rate.text)!,
          openingBalance: parseBudgetNumber(_opening.text) ?? 0,
          icon: _iconTouched ? Value(_icon) : const Value.absent(),
        );
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final base = ref.watch(budgetSettingsProvider).value?.baseCurrency ?? 'EUR';
    String? number(String? v, {bool positive = false}) {
      final n = parseBudgetNumber(v ?? '');
      if (n == null) return 'Enter a number';
      if (positive && !(n > 0)) return 'Must be above 0';
      return null;
    }

    return AlertDialog(
      title: Text(widget.existing == null ? 'New account' : 'Edit account'),
      content: Form(
        key: _form,
        child: _dialogBody([
          // The picture: shown next to the name wherever the account appears.
          Row(
            children: [
              AccountIcon(
                key: const ValueKey('account-icon-preview'),
                icon: _icon,
                size: 56,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('account-icon-pick'),
                      icon: const Icon(Icons.image_outlined),
                      label: Text(_icon == null ? 'Choose image…' : 'Change'),
                      onPressed: _pickIcon,
                    ),
                    if (_icon != null)
                      TextButton(
                        key: const ValueKey('account-icon-remove'),
                        onPressed: () => setState(() {
                          _icon = null;
                          _iconTouched = true;
                          _iconError = null;
                        }),
                        child: const Text('Remove'),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (_iconError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _iconError!,
                key: const ValueKey('account-icon-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          _gap,
          TextFormField(
            key: const ValueKey('account-name'),
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name'),
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Name is required' : null,
            onFieldSubmitted: (_) => _save(),
          ),
          _gap,
          TextFormField(
            controller: _type,
            decoration: const InputDecoration(
              labelText: 'Type (optional)',
              hintText: 'electronic money / cash / crypto',
            ),
          ),
          _gap,
          // Currency and rate share a line (equal height: the hint is under
          // the row, not under one field).
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  key: const ValueKey('account-currency'),
                  controller: _currency,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Currency'),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Required' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: TextFormField(
                  key: const ValueKey('account-rate'),
                  controller: _rate,
                  decoration: InputDecoration(
                    labelText: 'Rate (per 1 $base)',
                  ),
                  validator: (v) => number(v, positive: true),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              'e.g. 40 = 40 of this currency per 1 $base',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          _gap,
          TextFormField(
            key: const ValueKey('account-opening'),
            controller: _opening,
            decoration: const InputDecoration(
              labelText: 'Opening balance',
              helperText:
                  'Balance = opening balance + transactions up to today',
              helperMaxLines: 2,
            ),
            validator: number,
            onFieldSubmitted: (_) => _save(),
          ),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('account-save'),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ---- categories -------------------------------------------------------------

class BudgetCategoryDialog extends ConsumerStatefulWidget {
  const BudgetCategoryDialog({super.key, this.existing, this.parentId});

  final BudgetCategory? existing;

  /// Preselected parent for "add sub-category".
  final String? parentId;

  /// Resolves to the saved category's id (null = cancelled or deleted).
  static Future<String?> show(
    BuildContext context, {
    BudgetCategory? existing,
    String? parentId,
  }) => showStackedDialog<String>(
    context: context,
    builder: (_) =>
        BudgetCategoryDialog(existing: existing, parentId: parentId),
  );

  @override
  ConsumerState<BudgetCategoryDialog> createState() =>
      _BudgetCategoryDialogState();
}

class _BudgetCategoryDialogState extends ConsumerState<BudgetCategoryDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _price = TextEditingController(text: _opt(widget.existing?.price));
  late final _percent = TextEditingController(
    text: _opt(widget.existing?.percent),
  );
  late final _frequency = TextEditingController(
    text: _opt(widget.existing?.frequencyMonths),
  );
  late final _units = TextEditingController(
    text: _opt(widget.existing?.unitsPerMonth),
  );
  late bool _isIncome = widget.existing?.isIncome ?? false;
  late bool _oneTime = widget.existing?.oneTime ?? false;
  late BudgetUnit _unit = BudgetUnit.fromDb(widget.existing?.unit ?? 'month');
  late DateTime? _end = dateTimeFromDb(widget.existing?.endDate);
  late String? _parentId = widget.existing?.parentId ?? widget.parentId;
  late String? _percentOfId = widget.existing?.countPercentOfId;
  late String? _countAccount = widget.existing?.accountCountId;
  late String? _useAccount = widget.existing?.accountUseId;
  String? _error;

  static String _opt(double? v) => v == null ? '' : budgetNumber(v);

  @override
  void dispose() {
    for (final c in [_name, _price, _percent, _frequency, _units]) {
      c.dispose();
    }
    super.dispose();
  }

  CategoryInput _input(String? parentId) => CategoryInput(
    id: widget.existing?.id,
    name: _name.text,
    isIncome: _isIncome,
    oneTime: _oneTime,
    unit: _unit,
    endDate: _end,
    price: _unit == BudgetUnit.percentPerMonth
        ? null
        : parseBudgetNumber(_price.text),
    percent: _unit == BudgetUnit.percentPerMonth
        ? parseBudgetNumber(_percent.text)
        : null,
    frequencyMonths: parseBudgetNumber(_frequency.text),
    unitsPerMonth: parseBudgetNumber(_units.text),
    parentId: parentId,
    countPercentOfId: _percentOfId,
    accountCountId: _countAccount,
    accountUseId: _useAccount,
  );

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final navigator = Navigator.of(context);
    final service = ref.read(budgetServiceProvider);
    try {
      final saved = await service.saveCategory(_input(_parentId));
      navigator.pop(saved);
    } on BudgetCycleException catch (e) {
      setState(() => _error = e.message);
    } on BudgetGroupException catch (e) {
      await _offerMove(service, e, navigator);
    }
  }

  /// The chosen parent already holds transactions: offer to move them into
  /// this category (it becomes their new home) and then nest it.
  Future<void> _offerMove(
    BudgetService service,
    BudgetGroupException e,
    NavigatorState navigator,
  ) async {
    final parent = ref
        .read(budgetCategoriesProvider)
        .value
        ?.where((c) => c.id == e.categoryId)
        .firstOrNull;
    final ok = await showStackedDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Move transactions?'),
        content: Text(
          '"${parent?.name ?? 'That category'}" has transactions, and only '
          'categories without sub-categories can hold them. Move them into '
          '"${_name.text.trim()}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-move-transactions'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Move'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final id = await service.saveCategory(_input(null));
    await service.moveTransactions(e.categoryId, id);
    await service.saveCategory(
      CategoryInput(
        id: id,
        name: _name.text,
        isIncome: _isIncome,
        oneTime: _oneTime,
        unit: _unit,
        endDate: _end,
        price: _unit == BudgetUnit.percentPerMonth
            ? null
            : parseBudgetNumber(_price.text),
        percent: _unit == BudgetUnit.percentPerMonth
            ? parseBudgetNumber(_percent.text)
            : null,
        frequencyMonths: parseBudgetNumber(_frequency.text),
        unitsPerMonth: parseBudgetNumber(_units.text),
        parentId: _parentId,
        countPercentOfId: _percentOfId,
        accountCountId: _countAccount,
        accountUseId: _useAccount,
      ),
    );
    navigator.pop(id);
  }

  /// Deletes this category (sub-categories become top level, its transactions
  /// stay without a category) and offers Undo.
  Future<void> _delete() async {
    final c = widget.existing!;
    final overlay = rootOverlayOf(context);
    final navigator = Navigator.of(context);
    final service = ref.read(budgetServiceProvider);
    final history = ref.read(undoHistoryProvider.notifier);
    final undo = await service.deleteCategory(c.id);
    if (undo == null) return;
    navigator.pop();
    offerUndo(
      overlay,
      history,
      'Deleted "${c.name}"',
      () => service.undoDeleteCategory(undo),
    );
  }

  /// Adds a sub-category: the picker lists every category that is not above
  /// this one (a pick is moved under it) and can create a new one.
  Future<void> _addSub(List<BudgetCategory> cats) async {
    final id = widget.existing!.id;
    // Never offer this category or anything above it (that would be a loop).
    final above = <String>{id};
    var p = widget.existing!.parentId;
    final byId = {for (final c in cats) c.id: c};
    while (p != null && above.add(p)) {
      p = byId[p]?.parentId;
    }
    final picked = await pickBudgetCategory(
      context,
      leavesOnly: false,
      excludeIds: above,
      allowCreate: true,
    );
    if (picked == null || !mounted) return;
    try {
      await ref.read(budgetServiceProvider).moveCategory(picked, id);
      if (mounted) setState(() => _error = null);
    } on BudgetCycleException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on BudgetGroupException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// Sets, changes or clears the parent through the searchable picker. The
  /// category itself and everything below it are not offered (no loops).
  Future<void> _pickParent(List<BudgetCategory> cats) async {
    final below = <String>{?widget.existing?.id};
    var grew = true;
    while (grew) {
      grew = false;
      for (final c in cats) {
        if (c.parentId != null &&
            below.contains(c.parentId) &&
            below.add(c.id)) {
          grew = true;
        }
      }
    }
    final picked = await pickBudgetCategory(
      context,
      leavesOnly: false,
      excludeIds: below,
      allowNone: true,
      allowCreate: true,
    );
    if (picked == null || !mounted) return;
    setState(() => _parentId = picked == kPickedNoCategory ? null : picked);
  }

  /// A titled block with a `+` (or edit) button on the right whose [rows] are
  /// separate bordered blocks: the shared look of "Parent category" and
  /// "Sub-categories".
  Widget _linkedBlock(
    BuildContext context, {
    required String title,
    required Key addKey,
    required String addTooltip,
    required IconData addIcon,
    required VoidCallback onAdd,
    required List<Widget> rows,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            key: addKey,
            tooltip: addTooltip,
            icon: Icon(addIcon),
            onPressed: onAdd,
          ),
        ],
      ),
      ...rows,
    ],
  );

  Widget _blockRow({
    required Key key,
    required String title,
    required String? subtitle,
    required VoidCallback onTap,
    Widget? trailing,
  }) => SectionBlock(
    key: key,
    padding: EdgeInsets.zero,
    margin: const EdgeInsets.only(bottom: 8),
    child: InkWell(
      borderRadius: BorderRadius.circular(GlassTheme.radiusControl),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    ),
  );

  /// The settings column, and for an existing category its transactions: to the
  /// right of it on a wide window (same height, each scrolling on its own), below
  /// it on a narrow one.
  Widget _layout(BuildContext context, List<Widget> fields) {
    final id = widget.existing?.id;
    if (id == null) return _dialogBody(fields);
    final size = MediaQuery.sizeOf(context);
    if (size.width < 1100) {
      return _dialogBody([
        ...fields,
        _gap,
        CategoryTransactionsPanel(categoryId: id, scrollable: false),
      ]);
    }
    return SizedBox(
      height: (size.height - 220).clamp(420.0, 760.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _dialogBody(fields),
          const SizedBox(width: 16),
          SizedBox(
            width: 420,
            child: CategoryTransactionsPanel(categoryId: id),
          ),
        ],
      ),
    );
  }

  Future<void> _pickEnd() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _end == null ? now : budgetLocalDay(_end!),
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 30),
    );
    if (picked != null) setState(() => _end = budgetNoonUtc(picked));
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(budgetCategoriesProvider).value ?? const [];
    final accounts = ref.watch(budgetAccountsProvider).value ?? const [];
    final id = widget.existing?.id;
    final isGroup = id != null && cats.any((c) => c.parentId == id);
    final byId = {for (final c in cats) c.id: c};
    final percent = _unit == BudgetUnit.percentPerMonth;

    String? optionalNumber(String? v) {
      if ((v ?? '').trim().isEmpty) return null;
      return parseBudgetNumber(v!) == null ? 'Enter a number' : null;
    }

    DropdownMenuItem<String?> noneItem(String text) =>
        DropdownMenuItem<String?>(value: null, child: Text(text));

    final children = [for (final c in cats) if (c.parentId == id) c]
      ..sort((a, b) => compareIgnoringEmoji(a.name, b.name));
    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text(
              widget.existing == null ? 'New category' : 'Edit category',
            ),
          ),
          if (widget.existing != null)
            IconButton(
              key: const ValueKey('category-delete'),
              tooltip: 'Delete',
              color: Theme.of(context).colorScheme.error,
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _delete,
            ),
        ],
      ),
      content: Form(
        key: _form,
        child: _layout(context, [
          TextFormField(
            key: const ValueKey('category-name'),
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Name',
              helperText: 'Tip: put the currency first, e.g. "(TL) Groceries"',
            ),
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Name is required' : null,
            onFieldSubmitted: (_) => _save(),
          ),
          if (isGroup) ...[
            _gap,
            const Text(
              'This is a group: its totals are the sum of its '
              'sub-categories, so price, units and frequency are ignored.',
            ),
          ],
          _gap,
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: GlassPillSelector<bool>(
                  label: 'Type',
                  options: const {false: 'Expense', true: 'Income'},
                  value: _isIncome,
                  onChanged: (v) => setState(() => _isIncome = v),
                ),
              ),
              // A group ignores it, so only a real category shows the switch.
              // Only the switch itself toggles (a whole-row tile was too easy
              // to hit by accident).
              if (!isGroup) ...[
                const SizedBox(width: 12),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'One-time',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Switch(
                      key: const ValueKey('category-one-time'),
                      value: _oneTime,
                      onChanged: (v) => setState(() => _oneTime = v),
                    ),
                  ],
                ),
              ],
            ],
          ),
          // A group only sums its sub-categories: the unit, price, units,
          // frequency, one-time and end-date fields would all be ignored, so
          // they are not shown at all.
          if (!isGroup) ...[
            _gap,
            GlassPillSelector<BudgetUnit>(
              label: 'Unit of measure',
              options: const {
                BudgetUnit.piece: 'Piece',
                BudgetUnit.kilogram: 'Kg / liter',
                BudgetUnit.month: 'Month',
                BudgetUnit.percentPerMonth: '% per month',
              },
              value: _unit,
              onChanged: (v) => setState(() => _unit = v),
            ),
            _gap,
            if (percent)
              // The value and the category it is taken from sit on one row.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 120,
                    child: TextFormField(
                      key: const ValueKey('category-percent'),
                      controller: _percent,
                      decoration: const InputDecoration(labelText: 'Percent'),
                      validator: optionalNumber,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: OutlinedButton.icon(
                        key: const ValueKey('category-percent-of'),
                        icon: const Icon(Icons.percent),
                        label: Text(
                          _percentOfId == null
                              ? 'Take the percent of…'
                              : 'of: ${byId[_percentOfId]?.name ?? '?'}',
                          overflow: TextOverflow.ellipsis,
                        ),
                        onPressed: () async {
                          final picked = await pickBudgetCategory(
                            context,
                            excludeId: id,
                          );
                          if (picked != null) {
                            setState(() => _percentOfId = picked);
                          }
                        },
                      ),
                    ),
                  ),
                ],
              )
            else
              TextFormField(
                key: const ValueKey('category-price'),
                controller: _price,
                decoration: const InputDecoration(
                  labelText: 'Price per unit',
                  helperText: 'The expected price, even if it varies',
                ),
                validator: optionalNumber,
              ),
            _gap,
            // Same height side by side: the hint lives under the row, not under
            // one field (that pushed the other one out of line).
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    key: const ValueKey('category-units'),
                    controller: _units,
                    decoration: const InputDecoration(
                      labelText: 'Units per month',
                    ),
                    validator: optionalNumber,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    key: const ValueKey('category-frequency'),
                    controller: _frequency,
                    decoration: const InputDecoration(
                      labelText: 'Every N months',
                    ),
                    validator: optionalNumber,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                'Frequency: 1 = monthly, 12 = yearly',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            _gap,
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('category-end-date'),
                    icon: const Icon(Icons.event),
                    label: Text(
                      _end == null
                          ? 'No end date'
                          : 'Ends ${budgetDate(_end!)}',
                    ),
                    onPressed: _pickEnd,
                  ),
                ),
                if (_end != null)
                  IconButton(
                    tooltip: 'Clear end date',
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _end = null),
                  ),
              ],
            ),
          ],
          _gap,
          // Parent category: same block style as the sub-categories below. The
          // searchable picker never offers the category itself or anything
          // below it, so a loop cannot be made.
          KeyedSubtree(
            key: const ValueKey('category-parent'),
            child: _linkedBlock(
              context,
              title: 'Parent category',
              addKey: const ValueKey('category-parent-add'),
              addTooltip: _parentId != null && byId.containsKey(_parentId)
                  ? 'Change the parent'
                  : 'Set a parent',
              addIcon: _parentId != null && byId.containsKey(_parentId)
                  ? Icons.edit_outlined
                  : Icons.add,
              onAdd: () => _pickParent(cats),
              rows: [
                if (_parentId != null && byId.containsKey(_parentId))
                  _blockRow(
                    key: const ValueKey('category-parent-open'),
                    title: byId[_parentId]!.name,
                    subtitle: categoryLine(byId[_parentId]!),
                    onTap: () => BudgetCategoryDialog.show(
                      context,
                      existing: byId[_parentId]!,
                    ),
                    trailing: IconButton(
                      key: const ValueKey('category-parent-clear'),
                      tooltip: 'Make top level',
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _parentId = null),
                    ),
                  ),
              ],
            ),
          ),
          if (id != null) ...[
            _gap,
            _linkedBlock(
              context,
              title: 'Sub-categories',
              addKey: const ValueKey('category-add-sub'),
              addTooltip: 'Add a sub-category',
              addIcon: Icons.add,
              onAdd: () => _addSub(cats),
              rows: [
                for (final c in children)
                  _blockRow(
                    key: ValueKey('category-sub-${c.id}'),
                    title: c.name,
                    subtitle: categoryLine(c),
                    onTap: () =>
                        BudgetCategoryDialog.show(context, existing: c),
                  ),
              ],
            ),
          ],
          _gap,
          DropdownButtonFormField<String?>(
            key: const ValueKey('category-account-count'),
            initialValue: accounts.any((a) => a.id == _countAccount)
                ? _countAccount
                : null,
            isExpanded: true,
            dropdownColor: context.glass.fillDialog,
            decoration: const InputDecoration(
              labelText: 'Account to count',
              helperText: 'The currency this category is counted in',
            ),
            items: [
              noneItem('— none —'),
              for (final a in accounts)
                DropdownMenuItem<String?>(
                  value: a.id,
                  child: Row(
                    children: [
                      AccountIcon(icon: a.icon, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${a.name} (${a.currency})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            onChanged: (v) => setState(() => _countAccount = v),
          ),
          _gap,
          DropdownButtonFormField<String?>(
            key: const ValueKey('category-account-use'),
            initialValue: accounts.any((a) => a.id == _useAccount)
                ? _useAccount
                : null,
            isExpanded: true,
            dropdownColor: context.glass.fillDialog,
            decoration: const InputDecoration(
              labelText: 'Account to use',
              helperText: 'The account the money actually moves through',
            ),
            items: [
              noneItem('— none —'),
              for (final a in accounts)
                DropdownMenuItem<String?>(
                  value: a.id,
                  child: Row(
                    children: [
                      AccountIcon(icon: a.icon, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${a.name} (${a.currency})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            onChanged: (v) => setState(() => _useAccount = v),
          ),
          if (_error != null) ...[
            _gap,
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('category-save'),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ---- transactions -----------------------------------------------------------

/// Creates or edits a transaction. In [quick] mode (the "Add transaction"
/// button) the action defaults to the running / last finished one and the
/// quantity to that of the category's previous transaction.
class BudgetTransactionDialog extends ConsumerStatefulWidget {
  const BudgetTransactionDialog({
    super.key,
    this.existing,
    this.initialCategoryId,
    this.initialActionId,
    this.quick = false,
  });

  final BudgetTxItem? existing;
  final String? initialCategoryId;
  final String? initialActionId;
  final bool quick;

  static Future<void> show(
    BuildContext context, {
    BudgetTxItem? existing,
    String? categoryId,
    String? actionId,
    bool quick = false,
  }) => showStackedDialog<void>(
    context: context,
    builder: (_) => BudgetTransactionDialog(
      existing: existing,
      initialCategoryId: categoryId,
      initialActionId: actionId,
      quick: quick,
    ),
  );

  @override
  ConsumerState<BudgetTransactionDialog> createState() =>
      _BudgetTransactionDialogState();
}

class _BudgetTransactionDialogState
    extends ConsumerState<BudgetTransactionDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.row.name);
  late final _quantity = TextEditingController(
    text: budgetNumber(widget.existing?.row.quantity ?? 1),
  );
  late final _price = TextEditingController(
    text: widget.existing == null
        ? ''
        : budgetNumber(widget.existing!.row.unitPrice),
  );
  late final _rateCount = TextEditingController(
    text: _opt(widget.existing?.row.rateCount),
  );
  late final _rateInteract = TextEditingController(
    text: _opt(widget.existing?.row.rateInteract),
  );
  late String? _categoryId =
      widget.existing?.row.categoryId ?? widget.initialCategoryId;
  late String? _actionId =
      widget.existing?.row.actionId ?? widget.initialActionId;
  String? _actionName;
  DateTime? _actionStart;
  bool _actionAllDay = false;
  DateTime? _date;
  String? _error;

  static String _opt(double? v) => v == null ? '' : budgetNumber(v);

  @override
  void initState() {
    super.initState();
    _actionName = widget.existing?.actionName;
    _date = widget.existing?.date;
    if (widget.existing == null) {
      if (_categoryId != null) _onCategoryChosen(_categoryId!);
      if (widget.quick && _actionId == null) _suggestAction();
      if (_actionId != null) _loadActionName(_actionId!);
    } else if (_actionId != null) {
      _loadActionName(_actionId!);
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _quantity, _price, _rateCount, _rateInteract]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _suggestAction() async {
    final id = await ref.read(budgetServiceProvider).suggestedActionId();
    if (id == null || !mounted || _actionId != null) return;
    setState(() => _actionId = id);
    await _loadActionName(id);
  }

  Future<void> _loadActionName(String id) async {
    final db = ref.read(databaseProvider);
    final row = await (db.select(
      db.actionsTable,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (mounted && _actionId == id) {
      setState(() {
        _actionName = row?.name;
        _actionStart = dateTimeFromDb(row?.startAt);
        _actionAllDay = row?.isAllDay ?? false;
      });
    }
  }

  /// Fills price and quantity from the chosen category (new transactions only).
  Future<void> _onCategoryChosen(String id) async {
    final db = ref.read(databaseProvider);
    final service = ref.read(budgetServiceProvider);
    final cat = await (db.select(
      db.budgetCategoriesTable,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    final last = await service.lastQuantity(id);
    if (!mounted || cat == null) return;
    setState(() {
      _categoryId = id;
      _price.text = cat.price == null ? '' : budgetNumber(cat.price!);
      if (last != null) _quantity.text = budgetNumber(last);
    });
  }

  Future<void> _pickCategory() async {
    final id = await pickBudgetCategory(context);
    if (id == null || !mounted) return;
    if (widget.existing == null) {
      await _onCategoryChosen(id);
    } else {
      setState(() => _categoryId = id);
    }
  }

  Future<void> _pickAction() async {
    final picked = await ActionPickerDialog.show(context, includeDone: true);
    if (picked == null || !mounted) return;
    setState(() {
      _actionId = picked.id;
      _actionName = picked.name;
      _actionStart = picked.startAt;
      _actionAllDay = picked.isAllDay;
    });
  }

  /// Deletes this transaction (Undo is offered) and closes the dialog.
  Future<void> _delete() async {
    final overlay = rootOverlayOf(context);
    final navigator = Navigator.of(context);
    final service = ref.read(budgetServiceProvider);
    final history = ref.read(undoHistoryProvider.notifier);
    final row = await service.deleteTransaction(widget.existing!.row.id);
    if (row == null) return;
    navigator.pop();
    offerUndo(
      overlay,
      history,
      'Deleted transaction',
      () => service.undoDeleteTransaction(row),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now().toUtc();
    final picked = await showDatePicker(
      context: context,
      initialDate: budgetLocalDay(_date ?? now),
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setState(() => _date = budgetNoonUtc(picked));
  }

  Future<void> _save() async {
    if (_categoryId == null) {
      setState(() => _error = 'Pick a category');
      return;
    }
    if (!_form.currentState!.validate()) return;
    final navigator = Navigator.of(context);
    final service = ref.read(budgetServiceProvider);
    final existing = widget.existing?.row;
    final quantity = parseBudgetNumber(_quantity.text) ?? 1;
    final price = parseBudgetNumber(_price.text);
    // Only a rate the user changed counts as "typed" (and moves the account).
    double? typed(TextEditingController c, double? before) {
      final v = parseBudgetNumber(c.text);
      return v != null && v > 0 && v != before ? v : null;
    }

    try {
      if (existing == null) {
        await service.createTransaction(
          categoryId: _categoryId!,
          name: _name.text.trim(),
          actionId: _actionId,
          date: _actionId == null ? _date : null,
          quantity: quantity,
          unitPrice: price,
          rateCount: typed(_rateCount, null),
          rateInteract: typed(_rateInteract, null),
        );
      } else {
        await service.updateTransaction(
          existing.id,
          name: _name.text.trim(),
          categoryId: _categoryId,
          actionId: Value(_actionId),
          date: _actionId == null ? (_date ?? widget.existing!.date) : null,
          quantity: quantity,
          unitPrice: price,
          rateCount: typed(_rateCount, existing.rateCount),
          rateInteract: typed(_rateInteract, existing.rateInteract),
        );
      }
      navigator.pop();
    } on BudgetGroupException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(budgetCategoriesProvider).value ?? const [];
    final accounts = ref.watch(budgetAccountsProvider).value ?? const [];
    final cat = cats.where((c) => c.id == _categoryId).firstOrNull;
    final isAmount = cat?.unit == BudgetUnit.percentPerMonth.db;
    final countAccount = accounts
        .where((a) => a.id == cat?.accountCountId)
        .firstOrNull;
    final useAccount = accounts
        .where((a) => a.id == cat?.accountUseId)
        .firstOrNull;
    final qty = parseBudgetNumber(_quantity.text) ?? 0;
    final price = parseBudgetNumber(_price.text) ?? 0;

    String? number(String? v) =>
        parseBudgetNumber(v ?? '') == null ? 'Enter a number' : null;
    String? optionalNumber(String? v) =>
        (v ?? '').trim().isEmpty ? null : number(v);

    // The same transaction in the three currencies it can be read in, with the
    // rates as typed in the form (else the stored snapshot, else the accounts').
    final base = ref.watch(budgetSettingsProvider).value?.baseCurrency ?? 'EUR';
    TxAmounts? amounts;
    if (cat != null) {
      double? rate(TextEditingController c, double? stored, double? current) {
        final typed = parseBudgetNumber(c.text);
        return typed != null && typed > 0 ? typed : (stored ?? current);
      }

      amounts = transactionAmounts(
        BudgetTx(
          id: 'form',
          date: DateTime.now().toUtc(),
          quantity: qty,
          unitPrice: price,
          isIncome: cat.isIncome,
          isAmount: isAmount,
          accountCountId: countAccount?.id,
          accountUseId: useAccount?.id,
          rateCount: rate(
            _rateCount,
            widget.existing?.row.rateCount,
            countAccount?.rateToBase,
          ),
          rateInteract: rate(
            _rateInteract,
            widget.existing?.row.rateInteract,
            useAccount?.rateToBase,
          ),
        ),
        {for (final a in accounts) a.id: budgetAcctFromRow(a)},
      );
    }
    Widget amountLine(Widget? icon, String label, double? v, String cur) =>
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              if (icon != null) ...[icon, const SizedBox(width: 6)],
              Flexible(
                child: Text(
                  '$label: ${v == null ? '—' : budgetMoney(v, sign: true)} $cur'
                      .trim(),
                ),
              ),
            ],
          ),
        );

    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text(
              widget.existing != null
                  ? 'Edit transaction'
                  : widget.quick
                  ? 'Add transaction'
                  : 'New transaction',
            ),
          ),
          if (widget.existing != null)
            IconButton(
              key: const ValueKey('tx-delete'),
              tooltip: 'Delete',
              color: Theme.of(context).colorScheme.error,
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _delete,
            ),
        ],
      ),
      content: Form(
        key: _form,
        child: _dialogBody([
          // Category: open it, change it, or clear it (a transaction needs one,
          // so Save asks for another) - the same three controls as the action.
          Row(
            children: [
              const ParamIcon(Param.categories, size: 18, tooltip: false),
              const SizedBox(width: 8),
              Expanded(
                child: cat == null
                    ? const Text('No category')
                    : TextButton(
                        key: const ValueKey('tx-open-category'),
                        style: TextButton.styleFrom(
                          alignment: Alignment.centerLeft,
                        ),
                        onPressed: () => openBudgetCategoryById(
                          context,
                          ref,
                          cat.id,
                        ),
                        child: Text(
                          cat.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
              ),
              TextButton(
                key: const ValueKey('tx-category'),
                onPressed: _pickCategory,
                child: Text(cat == null ? 'Pick a category' : 'Change'),
              ),
              if (cat != null)
                IconButton(
                  key: const ValueKey('tx-clear-category'),
                  tooltip: 'Clear the category',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _categoryId = null),
                ),
            ],
          ),
          _gap,
          Row(
            children: [
              Expanded(
                child: _actionId == null
                    ? const Text('No action linked')
                    : TextButton.icon(
                        key: const ValueKey('tx-open-action'),
                        icon: const Icon(Icons.bolt_outlined),
                        label: Text(
                          _actionName ?? 'Action',
                          overflow: TextOverflow.ellipsis,
                        ),
                        onPressed: () =>
                            openActionById(context, ref, _actionId!),
                      ),
              ),
              TextButton(
                key: const ValueKey('tx-change-action'),
                onPressed: _pickAction,
                child: Text(_actionId == null ? 'Link action' : 'Change'),
              ),
              if (_actionId != null)
                IconButton(
                  key: const ValueKey('tx-clear-action'),
                  tooltip: 'Remove link',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() {
                    _actionId = null;
                    _actionName = null;
                  }),
                ),
            ],
          ),
          if (_actionId == null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('tx-date'),
                icon: const Icon(Icons.event),
                label: Text(
                  'Date: ${budgetDate(_date ?? DateTime.now().toUtc())}',
                ),
                onPressed: _pickDate,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                _actionStart == null
                    ? 'The date follows the action.'
                    : 'Action: ${formatUtcDateTime(_actionStart!, includeTime: !_actionAllDay)}',
                key: const ValueKey('tx-action-date'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          _gap,
          TextFormField(
            key: const ValueKey('tx-name'),
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name (optional)'),
            onChanged: (_) => setState(() {}),
          ),
          // An empty name can take the category's name in one tap.
          if (_name.text.trim().isEmpty && cat != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('tx-name-from-category'),
                icon: const Icon(Icons.subdirectory_arrow_left, size: 16),
                label: Text('Use "${cat.name}" as the name'),
                onPressed: () => setState(() => _name.text = cat.name),
              ),
            ),
          _gap,
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: const ValueKey('tx-quantity'),
                  controller: _quantity,
                  autofocus: widget.quick,
                  decoration: InputDecoration(
                    labelText: isAmount ? 'Amount' : 'Quantity',
                  ),
                  validator: number,
                  onChanged: (_) => setState(() {}),
                  onFieldSubmitted: (_) => _save(),
                ),
              ),
              if (!isAmount) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    key: const ValueKey('tx-price'),
                    controller: _price,
                    decoration: const InputDecoration(
                      labelText: 'Price per unit',
                    ),
                    validator: optionalNumber,
                    onChanged: (_) => setState(() {}),
                    onFieldSubmitted: (_) => _save(),
                  ),
                ),
              ],
            ],
          ),
          if (cat != null && amounts != null) ...[
            _gap,
            Text(cat.isIncome ? 'Income' : 'Expense'),
            amountLine(
              countAccount == null
                  ? null
                  : AccountIcon(icon: countAccount.icon, size: 20),
              'Counting',
              amounts.count,
              countAccount?.currency ?? '',
            ),
            if (useAccount != null)
              amountLine(
                AccountIcon(icon: useAccount.icon, size: 20),
                'Interactional',
                amounts.interact,
                useAccount.currency,
              ),
            amountLine(null, 'Main', amounts.base, base),
          ],
          if (countAccount != null || useAccount != null) ...[
            _gap,
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: const ValueKey('tx-rate-count'),
                    controller: _rateCount,
                    decoration: InputDecoration(
                      labelText: 'Rate (count)',
                      helperText: countAccount == null
                          ? null
                          : 'now ${budgetNumber(countAccount.rateToBase)}',
                    ),
                    validator: optionalNumber,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    key: const ValueKey('tx-rate-interact'),
                    controller: _rateInteract,
                    decoration: InputDecoration(
                      labelText: 'Rate (use)',
                      helperText: useAccount == null
                          ? null
                          : 'now ${budgetNumber(useAccount.rateToBase)}',
                    ),
                    validator: optionalNumber,
                  ),
                ),
              ],
            ),
          ],
          if (_error != null) ...[
            _gap,
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('tx-save'),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ---- settings ---------------------------------------------------------------

class BudgetSettingsDialog extends ConsumerStatefulWidget {
  const BudgetSettingsDialog({super.key, required this.initial});

  final BudgetSettings initial;

  static Future<void> show(BuildContext context, BudgetSettings initial) =>
      showStackedDialog<void>(
        context: context,
        builder: (_) => BudgetSettingsDialog(initial: initial),
      );

  @override
  ConsumerState<BudgetSettingsDialog> createState() =>
      _BudgetSettingsDialogState();
}

class _BudgetSettingsDialogState extends ConsumerState<BudgetSettingsDialog> {
  final _form = GlobalKey<FormState>();
  late final _base = TextEditingController(text: widget.initial.baseCurrency);
  late final _months = TextEditingController(
    text: '${widget.initial.periodMonths}',
  );
  late final _tolerance = TextEditingController(
    text: budgetNumber(widget.initial.tolerance),
  );
  late bool _showUrgency = widget.initial.showUrgency;

  @override
  void dispose() {
    _base.dispose();
    _months.dispose();
    _tolerance.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final navigator = Navigator.of(context);
    await ref
        .read(budgetServiceProvider)
        .saveSettings(
          BudgetSettings(
            baseCurrency: _base.text,
            periodMonths: int.parse(_months.text.trim()),
            tolerance: parseBudgetNumber(_tolerance.text)!,
            showUrgency: _showUrgency,
          ),
        );
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Budget settings'),
      content: Form(
        key: _form,
        child: _dialogBody([
          TextFormField(
            key: const ValueKey('settings-base'),
            controller: _base,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Main currency',
              helperText:
                  'All totals are shown in it; account rates are per 1 unit',
              helperMaxLines: 2,
            ),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
          ),
          _gap,
          TextFormField(
            key: const ValueKey('settings-months'),
            controller: _months,
            decoration: const InputDecoration(
              labelText: 'Period length (months)',
            ),
            validator: (v) {
              final n = int.tryParse((v ?? '').trim());
              return n == null || n < 1 ? 'A whole number, at least 1' : null;
            },
          ),
          _gap,
          TextFormField(
            key: const ValueKey('settings-tolerance'),
            controller: _tolerance,
            decoration: const InputDecoration(
              labelText: 'Tolerance (main currency)',
              helperText: 'Plan and fact this close count as "on plan"',
            ),
            validator: (v) {
              final n = parseBudgetNumber(v ?? '');
              return n == null || n < 0 ? 'A number, 0 or more' : null;
            },
            onFieldSubmitted: (_) => _save(),
          ),
          _gap,
          SwitchListTile(
            key: const ValueKey('settings-show-urgency'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Show urgency colours and values'),
            subtitle: const Text('On categories and transactions'),
            value: _showUrgency,
            onChanged: (v) => setState(() => _showUrgency = v),
          ),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('settings-save'),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
