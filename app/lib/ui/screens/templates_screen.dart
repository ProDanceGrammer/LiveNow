import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ids.dart';
import '../../data/database.dart';
import '../../domain/template_import_service.dart';
import '../dialog_stack.dart';
import '../providers.dart';
import '../widgets/action_import_summary_dialog.dart';
import 'actions_section.dart' show actionsCsvPickerProvider;
import '../widgets/glass.dart';
import '../widgets/metric_picker.dart';

final templateImportServiceProvider = Provider<TemplateImportService>(
  (ref) => TemplateImportService(ref.watch(databaseProvider)),
);

/// Saved quick-entry presets: "Use" instantiates a new action from one in a
/// single tap.
class TemplatesScreen extends ConsumerWidget {
  const TemplatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templatesAsync = ref.watch(templatesProvider);

    return Scaffold(
      body: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: TextButton.icon(
                key: const ValueKey('import-templates-csv'),
                icon: const Icon(Icons.upload_file),
                label: const Text('Import CSV'),
                onPressed: () => _importCsv(context, ref),
              ),
            ),
          ),
          Expanded(
            child: templatesAsync.when(
              data: (templates) => templates.isEmpty
                  ? const Center(child: Text('No templates yet.'))
                  : ListView.builder(
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
                              FilledButton.tonal(
                                onPressed: () => _use(context, ref, t),
                                child: const Text('Use'),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: 'Delete',
                                onPressed: () => _delete(ref, t.id),
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
                    ),
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

  Future<void> _use(
    BuildContext context,
    WidgetRef ref,
    ActionTemplate t,
  ) async {
    await ref.read(actionServiceProvider).createFromTemplate(t.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Created "${t.name}"')));
    }
  }

  Future<void> _showEditor(BuildContext context, {ActionTemplate? existing}) {
    return showStackedDialog<void>(
      context: context,
      builder: (_) => _TemplateEditorDialog(existing: existing),
    );
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
        width: 420,
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
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('All day'),
                  value: _isAllDay,
                  onChanged: (v) => setState(() => _isAllDay = v),
                ),
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
