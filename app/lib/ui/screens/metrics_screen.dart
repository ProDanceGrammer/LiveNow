import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ids.dart';
import '../../data/database.dart';
import '../providers.dart';

/// Simple CRUD for the life-balance metrics an action can increment.
class MetricsScreen extends ConsumerWidget {
  const MetricsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metricsAsync = ref.watch(metricsProvider);

    return Scaffold(
      body: metricsAsync.when(
        data: (metrics) => metrics.isEmpty
            ? const Center(child: Text('No metrics yet.'))
            : ListView.builder(
                itemCount: metrics.length,
                itemBuilder: (context, i) {
                  final m = metrics[i];
                  final subtitle = StringBuffer('Weight: ${m.weight}');
                  if (m.targetIntervalDays != null) {
                    subtitle.write(' · every ${m.targetIntervalDays}d');
                  }
                  return ListTile(
                    title: Text(m.name),
                    subtitle: Text(subtitle.toString()),
                    onTap: () => _showEditor(context, existing: m),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete',
                      onPressed: () => _delete(ref, m.id),
                    ),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditor(context),
        tooltip: 'New metric',
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _showEditor(BuildContext context, {Metric? existing}) {
    return showDialog<void>(
      context: context,
      builder: (_) => _MetricEditorDialog(existing: existing),
    );
  }

  Future<void> _delete(WidgetRef ref, String id) {
    final db = ref.read(databaseProvider);
    return (db.delete(db.metricsTable)..where((t) => t.id.equals(id))).go();
  }
}

class _MetricEditorDialog extends ConsumerStatefulWidget {
  final Metric? existing;

  const _MetricEditorDialog({this.existing});

  @override
  ConsumerState<_MetricEditorDialog> createState() =>
      _MetricEditorDialogState();
}

class _MetricEditorDialogState extends ConsumerState<_MetricEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _weightController;
  late final TextEditingController _leadingController;
  late final TextEditingController _intervalController;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _weightController = TextEditingController(
      text: existing?.weight.toString() ?? '1',
    );
    _leadingController = TextEditingController(text: existing?.leading ?? '');
    _intervalController = TextEditingController(
      text: existing?.targetIntervalDays?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _weightController.dispose();
    _leadingController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'New metric' : 'Edit metric'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name'),
              autofocus: true,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            TextFormField(
              controller: _weightController,
              decoration: const InputDecoration(labelText: 'Weight'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            TextFormField(
              controller: _leadingController,
              decoration: const InputDecoration(
                labelText: 'Leads to… (optional)',
              ),
            ),
            TextFormField(
              controller: _intervalController,
              decoration: const InputDecoration(
                labelText: 'Target interval (days, optional)',
              ),
              keyboardType: TextInputType.number,
            ),
          ],
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
    final weight = double.tryParse(_weightController.text.trim()) ?? 0;
    final interval = int.tryParse(_intervalController.text.trim());
    final leading = _leadingController.text.trim();

    await db
        .into(db.metricsTable)
        .insertOnConflictUpdate(
          MetricsTableCompanion(
            id: Value(widget.existing?.id ?? newId()),
            name: Value(_nameController.text.trim()),
            weight: Value(weight),
            leading: Value(leading.isEmpty ? null : leading),
            targetIntervalDays: Value(interval),
          ),
        );

    if (mounted) Navigator.of(context).pop();
  }
}
