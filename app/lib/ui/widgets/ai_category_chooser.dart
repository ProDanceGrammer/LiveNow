import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_search_field.dart';
import '../../data/database.dart';
import '../../domain/ai/ai_draft.dart';
import '../../domain/ai/category_resolver.dart';
import '../../domain/budget_rules.dart';
import '../../domain/search_match.dart';
import '../dialog_stack.dart';
import '../providers.dart';
import 'ai_line_details_sheet.dart' show choiceHint;

/// What the chooser returns: an existing category ([newName] null), or a NEW
/// category [newName] to create under the group [id].
typedef AiCategoryChoice = ({String id, String name, String? newName});

/// The category of one draft line, changed by hand: the categories the assistant
/// offered (with price and accounts), a live search over every category of the
/// budget, and, when what was typed exists nowhere, "Create «text»" in a group.
Future<AiCategoryChoice?> showAiCategoryChooser(
  BuildContext context, {
  required DraftLine line,
}) => showStackedDialog<AiCategoryChoice>(
  context: context,
  builder: (_) => _Chooser(line: line),
);

class _Chooser extends ConsumerStatefulWidget {
  const _Chooser({required this.line});
  final DraftLine line;

  @override
  ConsumerState<_Chooser> createState() => _ChooserState();
}

class _ChooserState extends ConsumerState<_Chooser> {
  final _query = TextEditingController();
  List<BudgetCategory> _all = const [];
  final _accounts = <String, String>{};
  final _byId = <String, BudgetCategory>{};
  final _parents = <String>{};
  String? _groupId;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final cats = await db.select(db.budgetCategoriesTable).get();
    final accs = await db.select(db.budgetAccountsTable).get();
    if (!mounted) return;
    setState(() {
      _all = cats;
      for (final a in accs) {
        _accounts[a.id] = a.name;
      }
      for (final c in cats) {
        _byId[c.id] = c;
        final p = c.parentId;
        if (p != null) _parents.add(p);
      }
      _loaded = true;
    });
  }

  bool _isWrapper(BudgetCategory c) {
    final key = CategoryResolver.nameKey(c.name);
    return _all.any((k) => k.parentId == c.id && CategoryResolver.nameKey(k.name) == key);
  }

  /// Leaves and same-name wrappers: what a line can be booked to (a leaf of a
  /// wrapper is a price variant, represented by the wrapper).
  List<BudgetCategory> get _selectable => [
    for (final c in _all)
      if (!_parents.contains(c.id) || _isWrapper(c))
        if (!_wrapperParent(c)) c,
  ];

  bool _wrapperParent(BudgetCategory c) {
    final p = _byId[c.parentId];
    return p != null &&
        !_parents.contains(c.id) &&
        CategoryResolver.nameKey(p.name) == CategoryResolver.nameKey(c.name);
  }

  List<BudgetCategory> get _groups => [
    for (final c in _all)
      if (_parents.contains(c.id) && !_isWrapper(c)) c,
  ];

  String _path(BudgetCategory c) {
    final p = _byId[c.parentId]?.name;
    return p == null ? c.name : '$p › ${c.name}';
  }

  DraftChoice _choice(BudgetCategory c) => DraftChoice(
    c.id,
    c.name,
    parentName: _byId[c.parentId]?.name,
    price: _parents.contains(c.id) ? null : c.price,
    unit: BudgetUnit.fromDb(c.unit).name,
    countAccount: _accounts[c.accountCountId],
    useAccount: _accounts[c.accountUseId],
  );

  void _pick(String id, String name, [String? newName]) =>
      Navigator.of(context).pop((id: id, name: name, newName: newName));

  @override
  Widget build(BuildContext context) {
    final q = _query.text.trim();
    final results = q.isEmpty
        ? const <BudgetCategory>[]
        : rankMatches(_selectable, q, (c) => [c.name, _path(c)]).take(20).toList();
    final exact = q.isNotEmpty &&
        _all.any((c) => CategoryResolver.nameKey(c.name) == CategoryResolver.nameKey(q));
    final groups = _groups;
    // The default group: where the best match lives, else the first group.
    final defaultGroup = results.isNotEmpty ? results.first.parentId : null;
    final group = groups.any((g) => g.id == _groupId)
        ? _groupId
        : (groups.any((g) => g.id == defaultGroup)
              ? defaultGroup
              : (groups.isEmpty ? null : groups.first.id));
    return AlertDialog(
      key: const ValueKey('ai-category-chooser'),
      title: Text(widget.line.displayName),
      content: SizedBox(
        width: 380,
        height: 420,
        child: Column(
          children: [
            AppSearchField(
              key: const ValueKey('ai-chooser-search'),
              controller: _query,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Type a category name',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: !_loaded
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      children: [
                        if (q.isEmpty && widget.line.candidates.isNotEmpty) ...[
                          Text('Offered', style: Theme.of(context).textTheme.labelLarge),
                          for (var i = 0; i < widget.line.candidates.length; i++)
                            _row(
                              ValueKey('ai-chooser-offer-$i'),
                              widget.line.candidates[i],
                              () => _pick(
                                widget.line.candidates[i].id,
                                widget.line.candidates[i].name,
                              ),
                            ),
                        ],
                        if (q.isNotEmpty)
                          for (var i = 0; i < results.length; i++)
                            _row(
                              ValueKey('ai-chooser-result-$i'),
                              _choice(results[i]),
                              () => _pick(results[i].id, results[i].name),
                            ),
                        if (q.isNotEmpty && results.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text('No category like that.'),
                          ),
                        if (q.isNotEmpty && !exact && group != null) ...[
                          const Divider(),
                          ListTile(
                            key: const ValueKey('ai-chooser-create'),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.add_circle_outline),
                            title: Text('Create «$q»'),
                            subtitle: const Text('as a new category in the group below'),
                            onTap: () => _pick(group, q, q),
                          ),
                          DropdownButton<String>(
                            key: const ValueKey('ai-chooser-group'),
                            isExpanded: true,
                            value: group,
                            items: [
                              for (final g in groups)
                                DropdownMenuItem(value: g.id, child: Text(_path(g))),
                            ],
                            onChanged: (v) => setState(() => _groupId = v),
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('ai-chooser-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _row(Key key, DraftChoice c, VoidCallback onTap) => ListTile(
    key: key,
    dense: true,
    contentPadding: EdgeInsets.zero,
    title: Text(c.label),
    subtitle: choiceHint(c).isEmpty ? null : Text(choiceHint(c)),
    onTap: onTap,
  );
}
