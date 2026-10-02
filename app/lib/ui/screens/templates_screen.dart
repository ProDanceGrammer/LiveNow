import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ids.dart';
import '../../data/database.dart';
import '../dialog_stack.dart';
import '../providers.dart';
import '../widgets/glass.dart';
import '../widgets/metric_picker.dart';

/// Saved quick-entry presets: "Use" instantiates a new action from one in a
/// single tap.
class TemplatesScreen extends ConsumerWidget {
  const TemplatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templatesAsync = ref.watch(templatesProvider);

    return Scaffold(
      body: templatesAsync.when(
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditor(context),
        tooltip: 'New template',
        child: const Icon(Icons.add),
      ),
    );
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
  // Legacy payload field: no longer editable, but preserved on re-save.
  int? _legacyEstimatedMinutes;
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
    _legacyEstimatedMinutes = payload?['estimatedMinutes'] as int?;
    _isAllDay = payload?['isAllDay'] as bool? ?? false;
    _selectedMetricIds =
        ((payload?['metricIds'] as List<dynamic>?)?.cast<String>() ?? const [])
            .toSet();
  }

  @override
  void dispose() {
    _nameController.dispose();
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
      if (_legacyEstimatedMinutes != null)
        'estimatedMinutes': _legacyEstimatedMinutes,
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
