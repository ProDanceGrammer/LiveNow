import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart' show Metric;
import '../../domain/growth_rules.dart';
import '../../domain/metric_service.dart';
import '../dialog_stack.dart';
import '../providers.dart';
import '../undo.dart';
import 'metric_picker.dart';

/// Create or edit one growth direction: its type and target, whether it is a
/// main direction, and the directions it depends on / leads to. Deleting is
/// here too (with Undo, no confirmation).
class GrowthDirectionDialog extends ConsumerStatefulWidget {
  /// Null = create a new direction.
  final GrowthMetric? existing;

  const GrowthDirectionDialog({super.key, this.existing});

  static Future<void> show(BuildContext context, {GrowthMetric? existing}) {
    return showStackedDialog<void>(
      context: context,
      builder: (_) => GrowthDirectionDialog(existing: existing),
    );
  }

  @override
  ConsumerState<GrowthDirectionDialog> createState() =>
      _GrowthDirectionDialogState();
}

class _GrowthDirectionDialogState extends ConsumerState<GrowthDirectionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _target;
  late final TextEditingController _icon;

  late MetricKind _kind;
  late MetricWindow _window;
  late bool _isMain;
  Set<String> _dependsOn = {};
  Set<String> _leadsTo = {};
  bool _relationsLoaded = false;
  String? _error;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final m = widget.existing;
    _name = TextEditingController(text: m?.name ?? '');
    _kind = m?.kind ?? MetricKind.count;
    _window = m?.window ?? MetricWindow.week;
    _target = TextEditingController(text: _formatTarget(m?.target ?? 1));
    _icon = TextEditingController(text: m?.icon ?? '');
    _isMain = m?.isMain ?? false;

    if (m == null) {
      _relationsLoaded = true;
    } else {
      // A one-shot query rather than a provider's `.future` (see the note in
      // ActionEditorDialog: an unwatched auto-dispose provider can be
      // disposed mid-load).
      ref.read(metricServiceProvider).relationsOf(m.id).then((r) {
        if (!mounted) return;
        setState(() {
          _dependsOn = r.dependsOn;
          _leadsTo = r.leadsTo;
          _relationsLoaded = true;
        });
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _icon.dispose();
    super.dispose();
  }

  static String _formatTarget(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : '$v';

  @override
  Widget build(BuildContext context) {
    final numeric = _kind != MetricKind.boolean;
    final snapshot = ref.watch(growthSnapshotProvider).value;
    final live = _isEditing ? snapshot?.byId[widget.existing!.id] : null;
    final stat = _isEditing ? snapshot?.statOf(widget.existing!.id) : null;

    return AlertDialog(
      title: Text(
        _isEditing ? 'Edit growth direction' : 'New growth direction',
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Name'),
                  autofocus: true,
                  // Enter = the Save button (once the relations have loaded).
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) {
                    if (_relationsLoaded) _save();
                  },
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _icon,
                  decoration: const InputDecoration(
                    labelText: 'Icon (an emoji, optional)',
                  ),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) {
                    if (_relationsLoaded) _save();
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<MetricKind>(
                  isExpanded: true,
                  initialValue: _kind,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem(
                      value: MetricKind.count,
                      child: Text('Number of actions'),
                    ),
                    DropdownMenuItem(
                      value: MetricKind.hours,
                      child: Text('Hours spent'),
                    ),
                    DropdownMenuItem(
                      value: MetricKind.boolean,
                      child: Text('Boolean (done or not)'),
                    ),
                  ],
                  onChanged: (v) => setState(() => _kind = v!),
                ),
                if (numeric) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<MetricWindow>(
                          isExpanded: true,
                          initialValue: _window,
                          decoration: const InputDecoration(labelText: 'Per'),
                          items: const [
                            DropdownMenuItem(
                              value: MetricWindow.week,
                              child: Text('Week (last 7 days)'),
                            ),
                            DropdownMenuItem(
                              value: MetricWindow.month,
                              child: Text('Month (last 30 days)'),
                            ),
                            DropdownMenuItem(
                              value: MetricWindow.year,
                              child: Text('Year'),
                            ),
                            DropdownMenuItem(
                              value: MetricWindow.fiveYears,
                              child: Text('5 years'),
                            ),
                          ],
                          onChanged: (v) => setState(() => _window = v!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _target,
                          decoration: InputDecoration(
                            labelText: _kind == MetricKind.hours
                                ? 'Target (hours)'
                                : 'Target (actions)',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) {
                            if (_relationsLoaded) _save();
                          },
                          validator: (v) {
                            final n = double.tryParse(
                              (v ?? '').trim().replaceAll(',', '.'),
                            );
                            return (n == null || n <= 0)
                                ? 'A number above 0'
                                : null;
                          },
                        ),
                      ),
                    ],
                  ),
                ],
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Main growth direction (weight 1000)'),
                  value: _isMain,
                  onChanged: (v) => setState(() => _isMain = v ?? false),
                ),
                if (_isEditing && live != null && stat != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Weight ${live.weight.round()} · level ${live.importanceLevel}'
                      ' · progress ${stat.progress.toStringAsFixed(1)}%'
                      ' · urgency ${stat.urgency.toStringAsFixed(1)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (!_relationsLoaded)
                  const LinearProgressIndicator()
                else ...[
                  MetricPicker(
                    label: 'Depends on (sub-directions that build it)',
                    selectedIds: _dependsOn,
                    excludeId: widget.existing?.id,
                    onOpen: _openRelated,
                    onChanged: (ids) => setState(() => _dependsOn = ids),
                  ),
                  const SizedBox(height: 8),
                  MetricPicker(
                    label: 'Leads to (larger goals it feeds)',
                    selectedIds: _leadsTo,
                    excludeId: widget.existing?.id,
                    onOpen: _openRelated,
                    onChanged: (ids) => setState(() => _leadsTo = ids),
                  ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (_isEditing)
          TextButton(
            onPressed: _delete,
            child: Text(
              'Delete',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _relationsLoaded ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }

  /// Stacked on top (not replacing) so unsaved edits here aren't lost;
  /// closing it returns here (same as the action editor's connected chips).
  void _openRelated(Metric row) {
    GrowthDirectionDialog.show(context, existing: GrowthMetric.fromRow(row));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final numeric = _kind != MetricKind.boolean;
    final target = numeric
        ? double.parse(_target.text.trim().replaceAll(',', '.'))
        : 1.0;
    try {
      await ref
          .read(metricServiceProvider)
          .saveMetric(
            id: widget.existing?.id,
            name: _name.text,
            kind: _kind,
            window: numeric ? _window : null,
            target: target,
            isMain: _isMain,
            icon: Value(_icon.text.trim().isEmpty ? null : _icon.text.trim()),
            dependsOnIds: _dependsOn.toList(),
            leadsToIds: _leadsTo.toList(),
          );
      if (mounted) Navigator.of(context).pop();
    } on MetricCycleException catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _delete() {
    // The synchronous part of the helper reads what it needs from `ref` and
    // `context` before this dialog closes.
    unawaited(runUndoableDeleteMetric(context, ref, widget.existing!.id));
    Navigator.of(context).pop();
  }
}
