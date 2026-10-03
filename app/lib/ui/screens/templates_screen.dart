import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ids.dart';
import '../../data/database.dart';
import '../../domain/template_import_service.dart';
import '../dialog_stack.dart';
import '../open_entity.dart';
import '../widgets/app_toast.dart';
import '../providers.dart';
import '../widgets/action_import_summary_dialog.dart';
import 'actions_section.dart' show actionsCsvPickerProvider;
import '../widgets/glass.dart';
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
  const TemplatesScreen({super.key});

  @override
  ConsumerState<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends ConsumerState<TemplatesScreen> {
  String _query = '';

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
                      hintText: 'Search templates',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _query = v.toLowerCase()),
                  ),
                ),
                const SizedBox(width: 12),
                TextButton.icon(
                  key: const ValueKey('import-templates-csv'),
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Import CSV'),
                  onPressed: () => _importCsv(context, ref),
                ),
              ],
            ),
          ),
          Expanded(
            child: templatesAsync.when(
              data: (all) {
                if (all.isEmpty) {
                  return const Center(child: Text('No templates yet.'));
                }
                final templates = _query.isEmpty
                    ? all
                    : [
                        for (final t in all)
                          if (t.name.toLowerCase().contains(_query)) t,
                      ];
                if (templates.isEmpty) {
                  return const Center(child: Text('No matches'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: templates.length,
                  itemBuilder: (context, i) {
                    final t = templates[i];
                    final tile = ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      title: Text(t.name),
                      subtitle: _durationLabel(t) == null
                          ? null
                          : Text(_durationLabel(t)!),
                      onTap: () => _showEditor(context, existing: t),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            key: ValueKey('template-start-${t.id}'),
                            icon: const Icon(Icons.play_arrow),
                            tooltip: 'Start now',
                            onPressed: () => _run(context, ref, t, false),
                          ),
                          IconButton(
                            key: ValueKey('template-finish-${t.id}'),
                            icon: const Icon(Icons.stop),
                            tooltip: 'Finish now',
                            onPressed: () => _run(context, ref, t, true),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Delete',
                            onPressed: () => _confirmDelete(context, ref, t),
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
                        child: Material(
                          type: MaterialType.transparency,
                          child: tile,
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditor(context),
        tooltip: 'New template',
        child: const Icon(Icons.add),
      ),
    );
  }

  static String? _durationLabel(ActionTemplate t) {
    final m =
        (jsonDecode(t.payload) as Map<String, dynamic>)['estimatedMinutes'];
    if (m is! int || m <= 0) return null;
    final h = m ~/ 60, r = m % 60;
    return h == 0 ? '$r min' : (r == 0 ? '$h h' : '$h h $r min');
  }

  Future<void> _importCsv(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final text = await ref.read(actionsCsvPickerProvider)();
    if (text == null || !context.mounted) return;
    try {
      final result = await ref
          .read(templateImportServiceProvider)
          .importCsv(text);
      if (!context.mounted) return;
      await TemplateImportSummaryDialog.show(context, result);
    } on FormatException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Import failed: ${e.message}')),
      );
    }
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

  Future<void> _showEditor(BuildContext context, {ActionTemplate? existing}) {
    return showStackedDialog<void>(
      context: context,
      builder: (_) => _TemplateEditorDialog(existing: existing),
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

class _TemplateEditorDialog extends ConsumerStatefulWidget {
  final ActionTemplate? existing;

  const _TemplateEditorDialog({this.existing});

  @override
  ConsumerState<_TemplateEditorDialog> createState() =>
      _TemplateEditorDialogState();
}

class _TemplateEditorDialogState extends ConsumerState<_TemplateEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _minutesController;
  bool _isAllDay = false;
  Set<String> _selectedMetricIds = {};
  String? _notes;

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
    _isAllDay = payload?['isAllDay'] as bool? ?? false;
    _notes = payload?['notes'] as String?;
    _selectedMetricIds =
        ((payload?['metricIds'] as List<dynamic>?)?.cast<String>() ?? const [])
            .toSet();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _minutesController.dispose();
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
                const SizedBox(height: 16),
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
