import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/time_codec.dart';
import '../../data/database.dart';
import '../../domain/dependency_service.dart';
import '../../domain/done_rule.dart';
import '../providers.dart';
import 'action_menu_button.dart';
import 'date_time_field.dart';

const _priorities = [
  'A1',
  'A2',
  'A3',
  'B1',
  'B2',
  'B3',
  'C1',
  'C2',
  'C3',
  'D1',
  'D2',
  'D3',
];

/// Create/edit dialog for a single action: core fields, metric links, and
/// (when editing) its previous/next action dependencies.
class ActionEditorDialog extends ConsumerStatefulWidget {
  final ActionRow? existing;

  const ActionEditorDialog({super.key, this.existing});

  static Future<void> show(BuildContext context, {ActionRow? existing}) {
    return showDialog<void>(
      context: context,
      builder: (_) => ActionEditorDialog(existing: existing),
    );
  }

  @override
  ConsumerState<ActionEditorDialog> createState() =>
      _ActionEditorDialogState();
}

class _ActionEditorDialogState extends ConsumerState<ActionEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _estimatedMinutesController;

  String? _priority;
  String _postponeFlex = 'flexible';
  String? _depthLevel;
  DateTime? _startAt;
  DateTime? _endAt;
  bool _isAllDay = false;
  Set<String> _selectedMetricIds = {};

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _estimatedMinutesController = TextEditingController(
      text: existing?.estimatedMinutes?.toString() ?? '',
    );

    if (existing != null) {
      _priority = existing.priority;
      _postponeFlex = existing.postponeFlex;
      _depthLevel = existing.depthLevel;
      _startAt = dateTimeFromDb(existing.startAt);
      _endAt = dateTimeFromDb(existing.endAt);
      _isAllDay = existing.isAllDay;

      ref.read(metricIdsOfProvider(existing.id).future).then((ids) {
        if (mounted) setState(() => _selectedMetricIds = ids.toSet());
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _estimatedMinutesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final metricsAsync = ref.watch(metricsProvider);

    return AlertDialog(
      title: Text(_isEditing ? 'Edit action' : 'New action'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                  autofocus: true,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                if (_isEditing) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        isDoneBefore(
                              startAt: dateTimeFromDb(widget.existing!.startAt),
                              endAt: dateTimeFromDb(widget.existing!.endAt),
                              isAllDay: widget.existing!.isAllDay,
                              done: widget.existing!.done,
                            )
                            ? 'Done'
                            : 'Open',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const Spacer(),
                      ActionMenuButton(actionId: widget.existing!.id),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _TimeTrackingSection(
                    actionId: widget.existing!.id,
                    scheduledStart: _startAt,
                  ),
                ],
                const SizedBox(height: 12),
                ExpansionTile(
                  title: const Text('Manual parameters'),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  children: [
                    DropdownButtonFormField<String?>(
                      initialValue: _priority,
                      decoration: const InputDecoration(
                        labelText: 'Priority',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('None'),
                        ),
                        for (final p in _priorities)
                          DropdownMenuItem(value: p, child: Text(p)),
                      ],
                      onChanged: (v) => setState(() => _priority = v),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _postponeFlex,
                            decoration: const InputDecoration(
                              labelText: 'Postpone flexibility',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'flexible',
                                child: Text('Flexible'),
                              ),
                              DropdownMenuItem(
                                value: 'hard',
                                child: Text('Hard'),
                              ),
                              DropdownMenuItem(
                                value: 'impossible',
                                child: Text('Impossible'),
                              ),
                            ],
                            onChanged: (v) =>
                                setState(() => _postponeFlex = v!),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String?>(
                            initialValue: _depthLevel,
                            decoration: const InputDecoration(
                              labelText: 'Depth (learning)',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: null,
                                child: Text('N/A'),
                              ),
                              DropdownMenuItem(
                                value: 'easy',
                                child: Text('Easy'),
                              ),
                              DropdownMenuItem(
                                value: 'medium',
                                child: Text('Medium'),
                              ),
                              DropdownMenuItem(
                                value: 'deep',
                                child: Text('Deep'),
                              ),
                            ],
                            onChanged: (v) => setState(() => _depthLevel = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('All day'),
                      value: _isAllDay,
                      onChanged: (v) => setState(() => _isAllDay = v),
                    ),
                    DateTimeField(
                      label: 'Scheduled start',
                      value: _startAt,
                      includeTime: !_isAllDay,
                      onChanged: (v) => setState(() => _startAt = v),
                    ),
                    const SizedBox(height: 4),
                    DateTimeField(
                      label: 'Scheduled end',
                      value: _endAt,
                      includeTime: !_isAllDay,
                      onChanged: (v) => setState(() => _endAt = v),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _estimatedMinutesController,
                      decoration: const InputDecoration(
                        labelText: 'Estimated minutes',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Metrics',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    metricsAsync.when(
                      data: (metrics) => metrics.isEmpty
                          ? const Text('No metrics yet.')
                          : Wrap(
                              spacing: 8,
                              children: [
                                for (final m in metrics)
                                  FilterChip(
                                    label: Text(m.name),
                                    selected: _selectedMetricIds.contains(
                                      m.id,
                                    ),
                                    onSelected: (selected) => setState(() {
                                      if (selected) {
                                        _selectedMetricIds.add(m.id);
                                      } else {
                                        _selectedMetricIds.remove(m.id);
                                      }
                                    }),
                                  ),
                              ],
                            ),
                      loading: () => const LinearProgressIndicator(),
                      error: (e, _) => Text('Error: $e'),
                    ),
                  ],
                ),
                if (_isEditing)
                  ExpansionTile(
                    title: const Text('Connected actions'),
                    tilePadding: EdgeInsets.zero,
                    initiallyExpanded: true,
                    children: [
                      _DependencySection(actionId: widget.existing!.id),
                    ],
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
    final service = ref.read(actionServiceProvider);
    final minutes = int.tryParse(_estimatedMinutesController.text.trim());
    final name = _nameController.text.trim();

    if (_isEditing) {
      final id = widget.existing!.id;
      await service.updateAction(
        actionId: id,
        name: name,
        priority: _priority,
        postponeFlex: _postponeFlex,
        depthLevel: _depthLevel,
        startAt: _startAt,
        endAt: _endAt,
        isAllDay: _isAllDay,
        estimatedMinutes: minutes,
      );
      await service.setMetrics(id, _selectedMetricIds.toList());
    } else {
      await service.createAction(
        name: name,
        priority: _priority,
        postponeFlex: _postponeFlex,
        depthLevel: _depthLevel,
        startAt: _startAt,
        endAt: _endAt,
        isAllDay: _isAllDay,
        estimatedMinutes: minutes,
        metricIds: _selectedMetricIds.toList(),
      );
    }

    if (mounted) Navigator.of(context).pop();
  }
}


/// Shows whether an occurrence is currently open (`action_occurrences`), and
/// if so since when — using [scheduledStart] (`actions.start_at`, the single
/// source of truth for the current start time) rather than the occurrence's
/// own `started_at`, so this always agrees with "Scheduled start" above it.
/// A *closed* occurrence's own start/finish is genuine frozen history and is
/// shown as-is.
class _TimeTrackingSection extends ConsumerWidget {
  final String actionId;
  final DateTime? scheduledStart;

  const _TimeTrackingSection({
    required this.actionId,
    required this.scheduledStart,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final occurrencesAsync = ref.watch(occurrencesOfProvider(actionId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Time tracking', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        occurrencesAsync.when(
          data: (occurrences) {
            if (occurrences.isEmpty) {
              return const Text('Not started yet.');
            }
            final latest = occurrences.first;
            if (latest.finishedAt == null) {
              final start = scheduledStart;
              return Text(
                start != null
                    ? 'Currently running — started ${_fmt(start)}'
                    : 'Currently running',
              );
            }
            final started = dateTimeFromDb(latest.startedAt);
            final finished = dateTimeFromDb(latest.finishedAt);
            final text = (started != null && finished != null)
                ? 'Last: ${_fmt(started)} → ${_fmt(finished)}'
                : 'Not started yet.';
            return Text(text);
          },
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('Error: $e'),
        ),
      ],
    );
  }

  String _fmt(DateTime utc) {
    final d = utc.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }
}

/// Shows and manages an existing action's previous/next action links.
class _DependencySection extends ConsumerWidget {
  final String actionId;

  const _DependencySection({required this.actionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final predecessors = ref.watch(predecessorsOfProvider(actionId));
    final successors = ref.watch(successorsOfProvider(actionId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Previous actions (must happen before this)',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        predecessors.when(
          data: (list) =>
              _chipList(context, ref, list, isPredecessor: true),
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('Error: $e'),
        ),
        TextButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Add previous action'),
          onPressed: () => _addDependency(context, ref, asPredecessor: true),
        ),
        const SizedBox(height: 12),
        Text(
          'Next actions (must happen after this)',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        successors.when(
          data: (list) =>
              _chipList(context, ref, list, isPredecessor: false),
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('Error: $e'),
        ),
        TextButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Add next action'),
          onPressed: () => _addDependency(context, ref, asPredecessor: false),
        ),
      ],
    );
  }

  Widget _chipList(
    BuildContext context,
    WidgetRef ref,
    List<ActionRow> items, {
    required bool isPredecessor,
  }) {
    if (items.isEmpty) return const Text('None');
    return Wrap(
      spacing: 8,
      children: [
        for (final item in items)
          InputChip(
            label: Text(item.name),
            onDeleted: () {
              final deps = ref.read(dependencyServiceProvider);
              if (isPredecessor) {
                deps.removeDependency(
                  predecessorId: item.id,
                  successorId: actionId,
                );
              } else {
                deps.removeDependency(
                  predecessorId: actionId,
                  successorId: item.id,
                );
              }
            },
          ),
      ],
    );
  }

  Future<void> _addDependency(
    BuildContext context,
    WidgetRef ref, {
    required bool asPredecessor,
  }) async {
    final chosen = await showDialog<ActionRow>(
      context: context,
      builder: (_) => _ActionPickerDialog(excludeId: actionId),
    );
    if (chosen == null) return;

    final deps = ref.read(dependencyServiceProvider);
    try {
      if (asPredecessor) {
        await deps.addDependency(
          predecessorId: chosen.id,
          successorId: actionId,
        );
      } else {
        await deps.addDependency(
          predecessorId: actionId,
          successorId: chosen.id,
        );
      }
    } on DependencyCycleException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('That would create a dependency cycle.'),
          ),
        );
      }
    }
  }
}

class _ActionPickerDialog extends ConsumerStatefulWidget {
  final String excludeId;

  const _ActionPickerDialog({required this.excludeId});

  @override
  ConsumerState<_ActionPickerDialog> createState() =>
      _ActionPickerDialogState();
}

class _ActionPickerDialogState extends ConsumerState<_ActionPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final actionsAsync = ref.watch(openActionsProvider);

    return AlertDialog(
      title: const Text('Choose an action'),
      content: SizedBox(
        width: 400,
        height: 400,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(labelText: 'Search'),
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
            ),
            Expanded(
              child: actionsAsync.when(
                data: (items) {
                  final filtered = items
                      .where(
                        (a) =>
                            a.id != widget.excludeId &&
                            a.name.toLowerCase().contains(_query),
                      )
                      .toList();
                  return ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, i) => ListTile(
                      title: Text(filtered[i].name),
                      onTap: () => Navigator.of(context).pop(filtered[i]),
                    ),
                  );
                },
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
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
