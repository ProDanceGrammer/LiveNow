import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ids.dart';
import '../../data/database.dart';
import '../../domain/action_urgency.dart';
import '../../domain/growth_rules.dart';
import '../../domain/template_import_service.dart';
import '../../domain/template_search.dart';
import '../../domain/template_sort.dart';
import '../dialog_back.dart';
import '../dialog_stack.dart';
import '../open_entity.dart';
import '../urgency_colors.dart';
import '../widgets/action_tile.dart' show formatUrgency;
import '../widgets/app_toast.dart';
import '../widgets/param_icons.dart';
import '../providers.dart';
import '../widgets/glass.dart';
import '../widgets/glass_icon_tile.dart';
import '../widgets/sort_chips.dart';
import '../widgets/sort_icons.dart';
import '../widgets/metric_picker.dart';
import '../widgets/notes_document.dart';
import '../widgets/notes_editor.dart';
import '../widgets/section_block.dart';

final templateImportServiceProvider = Provider<TemplateImportService>(
  (ref) => TemplateImportService(ref.watch(databaseProvider)),
);

/// Saved quick-entry presets: "Use" instantiates a new action from one in a
/// single tap.
class TemplatesScreen extends ConsumerStatefulWidget {
  /// [embedded] = shown as a tab of the Actions section: no FAB of its own
  /// (the shell's round button creates a template while this tab is open).
  const TemplatesScreen({super.key, this.embedded = false});

  final bool embedded;

  /// The "New template" dialog (the shell's FAB opens it on the Templates tab).
  static Future<void> showNewTemplate(BuildContext context) =>
      showStackedDialog<void>(
        context: context,
        builder: (_) => const _TemplateEditorDialog(),
      );

  @override
  ConsumerState<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends ConsumerState<TemplatesScreen> {
  String _query = '';
  bool _showOptions = false;
  List<TemplateSortKey> _sort = const [
    TemplateSortKey(TemplateSortField.name),
  ];

  @override
  Widget build(BuildContext context) {
    final templatesAsync = ref.watch(templatesProvider);

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('templates-search'),
                    decoration: const InputDecoration(
                      hintText: 'Search by name or direction',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _query = v.toLowerCase()),
                  ),
                ),
                IconButton(
                  key: const ValueKey('templates-options-toggle'),
                  tooltip: 'Sort',
                  isSelected: _showOptions,
                  icon: const Icon(Icons.tune),
                  onPressed: () => setState(() => _showOptions = !_showOptions),
                ),
              ],
            ),
          ),
          if (_showOptions)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _sortRow(),
            ),
          Expanded(
            child: templatesAsync.when(
              data: (all) {
                if (all.isEmpty) {
                  return const Center(child: Text('No templates yet.'));
                }
                // The search also looks at the names of the growth directions a
                // template links to.
                final directionNames = <String, String>{
                  for (final m in ref.watch(metricsProvider).value ?? const [])
                    m.id: m.name.toLowerCase(),
                };
                final averages =
                    ref.watch(templateAveragesProvider).value ??
                    const <String, Duration>{};
                final stats = ref.watch(growthSnapshotProvider).value?.stats;
                final filtered = _query.isEmpty
                    ? all
                    : [
                        for (final t in all)
                          if (templateMatches(
                            name: t.name,
                            payloadJson: t.payload,
                            query: _query,
                            directionNames: directionNames,
                          ))
                            t,
                      ];
                if (filtered.isEmpty) {
                  return const Center(child: Text('No matches'));
                }
                final infos = {
                  for (final t in filtered)
                    t.id: _infoOf(t, directionNames, averages[t.id], stats),
                };
                final templates = sortTemplates(
                  filtered,
                  _sort,
                  (t) => infos[t.id]!,
                );
                final dark = Theme.of(context).brightness == Brightness.dark;
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: templates.length,
                  itemBuilder: (context, i) {
                    final t = templates[i];
                    // Tinted by the urgency band like an action card; a
                    // template without directions stays plain.
                    final u = infos[t.id]!.urgency;
                    final tint = u == null ? null : urgencyColors(u, dark: dark);
                    final fg = tint?.fg;
                    final tile = ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      textColor: fg,
                      title: Text(t.name),
                      subtitle: _subtitle(
                        context,
                        t,
                        averages[t.id],
                        u,
                        fg: fg,
                      ),
                      onTap: () => _showEditor(context, existing: t),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // The same coloured tiles as the Current board's
                          // hover toolbar.
                          GlassIconTile(
                            key: ValueKey('template-start-${t.id}'),
                            icon: Icons.play_arrow_rounded,
                            hue: GlassHue.blue,
                            tooltip: 'Start now',
                            size: 32,
                            iconSize: 20,
                            onTap: () => _run(context, ref, t, false),
                          ),
                          const SizedBox(width: 4),
                          GlassIconTile(
                            key: ValueKey('template-finish-${t.id}'),
                            icon: Icons.stop_rounded,
                            hue: GlassHue.pink,
                            tooltip: 'Finish now',
                            size: 32,
                            iconSize: 20,
                            onTap: () => _run(context, ref, t, true),
                          ),
                          const SizedBox(width: 4),
                          GlassIconTile(
                            key: ValueKey('template-delete-${t.id}'),
                            icon: Icons.delete_outline_rounded,
                            hue: GlassHue.error,
                            tooltip: 'Delete',
                            size: 32,
                            iconSize: 20,
                            onTap: () => _confirmDelete(context, ref, t),
                          ),
                        ],
                      ),
                    );
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      child: GlassSurface(
                        radius: 16,
                        shadow: false,
                        blurWindow: false,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: tint?.bg,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Material(
                            type: MaterialType.transparency,
                            child: tile,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
      floatingActionButton: widget.embedded
          ? null
          : FloatingActionButton(
              heroTag: null,
              onPressed: () => _showEditor(context),
              tooltip: 'New template',
              child: const Icon(Icons.add),
            ),
    );
  }

  static String _minutesLabel(int m) {
    final h = m ~/ 60, r = m % 60;
    return h == 0 ? '$r min' : (r == 0 ? '$h h' : '$h h $r min');
  }

  /// Manual duration, average of past runs (the one the template uses is
  /// bold) and the "Urgency to Keep in Balance" of its directions.
  static Widget? _subtitle(
    BuildContext context,
    ActionTemplate t,
    Duration? average,
    double? urgency, {
    Color? fg,
  }) {
    final payload = jsonDecode(t.payload) as Map<String, dynamic>;
    final m = payload['estimatedMinutes'];
    final manual = (m is int && m > 0) ? m : null;
    final useAverage = payload['useAverage'] != false;
    final avgMin = average == null
        ? null
        : (average.inSeconds / 60).round().clamp(1, 1 << 30);
    if (manual == null && avgMin == null && urgency == null) return null;
    final base = Theme.of(context).textTheme.bodyMedium!.copyWith(color: fg);
    final bold = base.copyWith(fontWeight: FontWeight.w700);
    return Wrap(
      spacing: 14,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (manual != null)
          Text(
            _minutesLabel(manual),
            key: ValueKey('template-manual-${t.id}'),
            style: useAverage && avgMin != null ? base : bold,
          ),
        if (avgMin != null)
          Text(
            'avg ${_minutesLabel(avgMin)}',
            key: ValueKey('template-average-${t.id}'),
            style: useAverage || manual == null ? bold : base,
          ),
        if (urgency != null)
          ParamValue.urgency(
            formatUrgency(urgency),
            size: 18,
            key: ValueKey('template-urgency-${t.id}'),
            style: base,
            color: base.color,
            iconColor: fg,
          ),
      ],
    );
  }

  /// What the list is sorted on for [t] (the urgency is shared with the tint).
  static TemplateSortInfo _infoOf(
    ActionTemplate t,
    Map<String, String> directionNames,
    Duration? average,
    Map<String, MetricStat>? stats,
  ) {
    final payload = jsonDecode(t.payload) as Map<String, dynamic>;
    final ids = templateMetricIds(t.payload);
    final m = payload['estimatedMinutes'];
    return TemplateSortInfo(
      name: t.name,
      direction: firstDirectionName([
        for (final id in ids)
          if (directionNames[id] != null) directionNames[id]!,
      ]),
      urgency: stats == null ? null : actionUrgency(ids.toSet(), stats),
      averageMinutes: average == null
          ? null
          : (average.inSeconds / 60).round().clamp(1, 1 << 30),
      manualMinutes: (m is int && m > 0) ? m : null,
    );
  }

  Widget _sortRow() {
    final used = {for (final k in _sort) k.field};
    void set(List<TemplateSortKey> v) => setState(() => _sort = v);
    return SortChipsRow(
      keyPrefix: 'tpl-sort',
      chips: [
        for (final k in _sort)
          SortChipData(
            k.field.name,
            k.field.label,
            ascending: k.ascending,
            icon: sortFieldIcon(k.field),
          ),
      ],
      addOptions: [
        for (final f in TemplateSortField.values)
          if (!used.contains(f)) (f.name, f.label, sortFieldIcon(f)),
      ],
      onToggle: (i) => set([
        for (var j = 0; j < _sort.length; j++)
          if (j == i) _sort[j].toggled() else _sort[j],
      ]),
      onRemove: (i) => set([..._sort]..removeAt(i)),
      onMove: (from, to) {
        if (from == to) return;
        final list = [..._sort];
        list.insert(to, list.removeAt(from));
        set(list);
      },
      onAdd: (id) => set([
        ..._sort,
        TemplateSortKey(TemplateSortField.values.byName(id)),
      ]),
    );
  }

  /// Start now ([finished] false) or Finish now (true): creates the action
  /// from the template; the toast's Undo deletes it again.
  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    ActionTemplate t,
    bool finished,
  ) async {
    // Looked up before the await (the tile may be gone afterwards).
    final overlay = rootOverlayOf(context);
    final service = ref.read(actionServiceProvider);
    final id = finished
        ? await service.createFromTemplateFinished(t.id)
        : await service.createFromTemplateStarted(t.id);
    showAppToast(
      overlay,
      leading: finished ? 'Finished "' : 'Started "',
      name: t.name,
      trailing: '"',
      onNameTap: () {
        if (context.mounted) openActionById(context, ref, id);
      },
      actionLabel: 'Undo',
      onAction: () => service.deleteAction(id),
    );
  }

  Future<void> _showEditor(
    BuildContext context, {
    ActionTemplate? existing,
    _TemplateDraft? draft,
  }) {
    return showStackedDialog<void>(
      context: context,
      builder: (_) => _TemplateEditorDialog(existing: existing, draft: draft),
    );
  }

  /// Deleting is final (no Undo), so ask first.
  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    ActionTemplate t,
  ) async {
    final ok = await showStackedDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete template?'),
        content: Text('"${t.name}" will be deleted and cannot be restored.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete-template'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) await _delete(ref, t.id);
  }

  Future<void> _delete(WidgetRef ref, String id) {
    final db = ref.read(databaseProvider);
    return (db.delete(
      db.actionTemplatesTable,
    )..where((t) => t.id.equals(id))).go();
  }
}

/// The unsaved fields of a template form (kept for Undo after Back).
class _TemplateDraft {
  const _TemplateDraft({
    required this.name,
    required this.minutes,
    required this.blocks,
    required this.isAllDay,
    required this.useAverage,
    required this.notes,
    required this.metricIds,
  });

  final String name;
  final String minutes;
  final String blocks;
  final bool isAllDay;
  final bool useAverage;
  final String? notes;
  final Set<String> metricIds;
}

class _TemplateEditorDialog extends ConsumerStatefulWidget {
  final ActionTemplate? existing;

  /// Unsaved edits to restore (Undo after a Back-button close).
  final _TemplateDraft? draft;

  const _TemplateEditorDialog({this.existing, this.draft});

  @override
  ConsumerState<_TemplateEditorDialog> createState() =>
      _TemplateEditorDialogState();
}

class _TemplateEditorDialogState extends ConsumerState<_TemplateEditorDialog>
    implements DraftDialog {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _minutesController;
  late final TextEditingController _blocksController;
  bool _isAllDay = false;
  Set<String> _selectedMetricIds = {};
  String? _notes;
  bool _useAverage = true;
  Duration? _average;

  @override
  void initState() {
    super.initState();
    Map<String, dynamic>? payload;
    final existing = widget.existing;
    if (existing != null) {
      payload = jsonDecode(existing.payload) as Map<String, dynamic>;
    }

    _nameController = TextEditingController(
      text: payload?['name'] as String? ?? '',
    );
    _minutesController = TextEditingController(
      text: (payload?['estimatedMinutes'] as int?)?.toString() ?? '',
    );
    _blocksController = TextEditingController(
      text: payload?['diaryBlocks'] as String? ?? '',
    );
    _isAllDay = payload?['isAllDay'] as bool? ?? false;
    _notes = payload?['notes'] as String?;
    _useAverage = payload?['useAverage'] as bool? ?? true;
    if (existing != null) {
      ref.read(actionServiceProvider).templateAverage(existing.name).then((d) {
        if (mounted) setState(() => _average = d);
      });
    }
    _selectedMetricIds =
        ((payload?['metricIds'] as List<dynamic>?)?.cast<String>() ?? const [])
            .toSet();
    final d = widget.draft;
    if (d != null) {
      _nameController.text = d.name;
      _minutesController.text = d.minutes;
      _blocksController.text = d.blocks;
      _isAllDay = d.isAllDay;
      _useAverage = d.useAverage;
      _notes = d.notes;
      _selectedMetricIds = {...d.metricIds};
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    registerDraftDialog(ModalRoute.of(context), this);
  }

  Map<String, dynamic> get _basePayload => widget.existing == null
      ? const {}
      : jsonDecode(widget.existing!.payload) as Map<String, dynamic>;

  bool get _isDirty {
    final b = _basePayload;
    if (_nameController.text != (b['name'] as String? ?? '')) return true;
    if (_minutesController.text !=
        ((b['estimatedMinutes'] as int?)?.toString() ?? '')) {
      return true;
    }
    if (_blocksController.text != (b['diaryBlocks'] as String? ?? '')) {
      return true;
    }
    if (_isAllDay != (b['isAllDay'] as bool? ?? false)) return true;
    if (_useAverage != (b['useAverage'] as bool? ?? true)) return true;
    if (_notes != (b['notes'] as String?)) return true;
    final ids = ((b['metricIds'] as List<dynamic>?)?.cast<String>() ?? const [])
        .toSet();
    return !(ids.length == _selectedMetricIds.length &&
        ids.containsAll(_selectedMetricIds));
  }

  @override
  void closeByBack() {
    final draft = _isDirty
        ? _TemplateDraft(
            name: _nameController.text,
            minutes: _minutesController.text,
            blocks: _blocksController.text,
            isAllDay: _isAllDay,
            useAverage: _useAverage,
            notes: _notes,
            metricIds: {..._selectedMetricIds},
          )
        : null;
    final existing = widget.existing;
    final shown = _nameController.text.trim();
    closeDraftDialog(
      context: context,
      ref: ref,
      label: shown.isEmpty ? 'template' : '"$shown"',
      draft: draft,
      reopen: (root, d) => showStackedDialog<void>(
        context: root,
        builder: (_) => _TemplateEditorDialog(
          existing: existing,
          draft: d as _TemplateDraft,
        ),
      ),
    );
  }

  @override
  void dispose() {
    unregisterDraftDialog(this);
    _nameController.dispose();
    _minutesController.dispose();
    _blocksController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'New template' : 'Edit template'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name (also the default action name)',
                  ),
                  autofocus: true,
                  // Enter = the Save button.
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _save(),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                // Compact (text + switch only) so its hover area stays small
                // and never overlaps the neighbouring fields.
                Row(
                  children: [
                    const Text('All day'),
                    const SizedBox(width: 4),
                    Switch(
                      key: const ValueKey('template-all-day'),
                      value: _isAllDay,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (v) => setState(() => _isAllDay = v),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('template-duration'),
                  controller: _minutesController,
                  decoration: const InputDecoration(
                    labelText: 'Duration (minutes)',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.isEmpty) return null;
                    final n = int.tryParse(t);
                    return (n == null || n <= 0) ? 'Whole minutes > 0' : null;
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: const ValueKey('template-diary-blocks'),
                  controller: _blocksController,
                  decoration: const InputDecoration(
                    labelText: '"What is done?" blocks',
                    helperText:
                        'Codes such as KBT, Target:Jeremy (empty = every '
                        'tagged action); copied to actions made from this '
                        'template',
                    helperMaxLines: 2,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _average == null
                            ? 'Use average time (no runs yet)'
                            : 'Use average time (${_average!.inMinutes} min)',
                      ),
                    ),
                    Switch(
                      key: const ValueKey('template-use-average'),
                      value: _useAverage,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (v) => setState(() => _useAverage = v),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                MetricPicker(
                  label: 'Growth directions',
                  selectedIds: _selectedMetricIds,
                  onChanged: (ids) => setState(() => _selectedMetricIds = ids),
                ),
                // Collapsed unless the template already has notes;
                // `maintainState: false` keeps the editor out of the tree
                // until opened (the latest JSON lives in `_notes`).
                SectionBlock(
                  padding: kSectionTileBlockPadding,
                  child: ExpansionTile(
                    key: const ValueKey('template-notes-section'),
                    title: const Text('Notes'),
                    shape: const Border(),
                    collapsedShape: const Border(),
                    initiallyExpanded:
                        _notes != null &&
                        !notesDocumentIsEmpty(notesDocumentFromJson(_notes)),
                    maintainState: false,
                    tilePadding: kSectionTilePadding,
                    childrenPadding: kSectionChildrenPadding,
                    children: [
                      NotesEditor(
                        initialJson: _notes,
                        onChanged: (json) => _notes = json,
                        onSave: _save,
                        height: 260,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final db = ref.read(databaseProvider);
    final name = _nameController.text.trim();

    final payload = jsonEncode({
      'name': name,
      'estimatedMinutes': ?int.tryParse(_minutesController.text.trim()),
      'isAllDay': _isAllDay,
      // Absent = on (the default); only an explicit "off" is stored.
      'useAverage': ?(_useAverage ? null : false),
      'diaryBlocks': ?(_blocksController.text.trim().isEmpty
          ? null
          : _blocksController.text.trim()),
      'metricIds': _selectedMetricIds.toList(),
      // Notes document JSON (copied into the action by
      // ActionService.createFromTemplate); omitted when empty.
      'notes': ?_notes,
    });

    await db
        .into(db.actionTemplatesTable)
        .insertOnConflictUpdate(
          ActionTemplatesTableCompanion(
            id: Value(widget.existing?.id ?? newId()),
            name: Value(name),
            payload: Value(payload),
          ),
        );

    if (mounted) Navigator.of(context).pop();
  }
}
