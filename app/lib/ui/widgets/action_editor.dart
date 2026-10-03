import 'dart:async';
import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/time_codec.dart';
import '../../data/database.dart';
import '../../domain/action_urgency.dart';
import '../../domain/dependency_service.dart';
import '../../domain/duration_rules.dart';
import '../dialog_stack.dart';
import '../open_entity.dart';
import '../providers.dart';
import '../theme/glass_theme.dart';
import '../undo.dart';
import 'action_tile.dart' show formatUrgency;
import 'date_time_field.dart';
import 'metric_picker.dart';
import 'notes_document.dart';
import 'notes_editor.dart';
import 'quick_action_bar.dart';

/// Create/edit dialog for a single action: core fields, metric links, and
/// (when editing) its previous/next action dependencies.
class ActionEditorDialog extends ConsumerStatefulWidget {
  final ActionRow? existing;

  /// For a new action: the schedule to start with (UTC), e.g. the time range
  /// dragged out on the calendar.
  final DateTime? initialStart;
  final DateTime? initialEnd;

  const ActionEditorDialog({
    super.key,
    this.existing,
    this.initialStart,
    this.initialEnd,
  });

  static Future<void> show(
    BuildContext context, {
    ActionRow? existing,
    DateTime? initialStart,
    DateTime? initialEnd,
  }) {
    return showStackedDialog<void>(
      context: context,
      builder: (_) => ActionEditorDialog(
        existing: existing,
        initialStart: initialStart,
        initialEnd: initialEnd,
      ),
    );
  }

  @override
  ConsumerState<ActionEditorDialog> createState() => _ActionEditorDialogState();
}

class _ActionEditorDialogState extends ConsumerState<ActionEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;

  String _postponeFlex = 'flexible';
  String? _depthLevel;
  DateTime? _startAt;
  DateTime? _endAt;
  bool _isAllDay = false;
  Set<String> _selectedMetricIds = {};
  String? _countableActivityId;
  int _activityFieldEpoch = 0;
  String? _notes;
  bool _notesOpen = false; // the Notes section (tile) is open
  bool _notesExpanded = false; // the editor's wide "Expand" mode
  final _notesKey = GlobalKey();
  StreamSubscription<ActionRow?>? _rowSub;
  ActionRow? _seen; // the last database row seen (to spot external changes)

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _notes = existing?.notes;
    // Open the Notes section only when there already is text to show.
    _notesOpen =
        _notes != null && !notesDocumentIsEmpty(notesDocumentFromJson(_notes));
    _startAt = widget.initialStart;
    _endAt = widget.initialEnd;

    if (existing != null) {
      _postponeFlex = existing.postponeFlex;
      _depthLevel = existing.depthLevel;
      _startAt = dateTimeFromDb(existing.startAt);
      _endAt = dateTimeFromDb(existing.endAt);
      _isAllDay = existing.isAllDay;
      _countableActivityId = existing.countableActivityId;

      // A one-shot query, not `ref.read(metricIdsOfProvider(..).future)`:
      // nothing listens to that auto-dispose provider, so Riverpod can
      // dispose it mid-load — which throws and leaves the future forever
      // pending, silently dropping the action's metric selection.
      final db = ref.read(databaseProvider);
      _seen = existing;
      _rowSub =
          (db.select(db.actionsTable)..where((t) => t.id.equals(existing.id)))
              .watchSingleOrNull()
              .listen(_onRowChanged);
      (db.select(
        db.actionMetricsTable,
      )..where((t) => t.actionId.equals(existing.id))).get().then((links) {
        if (mounted) {
          setState(
            () => _selectedMetricIds = links.map((l) => l.metricId).toSet(),
          );
        }
      });
    }
  }

  /// The button row (Start / Finish / Postpone / Continue) writes straight to
  /// the database and the dialog stays open: pull the new schedule (and a
  /// renamed `[#n]` name, if the user has not typed over it) into the form.
  /// Typed notes and every other field are left alone.
  void _onRowChanged(ActionRow? row) {
    final prev = _seen;
    if (row == null || prev == null || !mounted) return;
    _seen = row;
    final scheduleChanged =
        row.startAt != prev.startAt ||
        row.endAt != prev.endAt ||
        row.isAllDay != prev.isAllDay;
    final nameChanged = row.name != prev.name;
    if (!scheduleChanged && !nameChanged) return;
    setState(() {
      if (scheduleChanged) {
        _startAt = dateTimeFromDb(row.startAt);
        _endAt = dateTimeFromDb(row.endAt);
        _isAllDay = row.isAllDay;
      }
      if (nameChanged && _nameController.text == prev.name) {
        _nameController.text = row.name;
      }
    });
  }

  @override
  void dispose() {
    _rowSub?.cancel();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final expanded = _notesExpanded;
    final width = expanded
        ? math.min(1100.0, screen.width - 48)
        : math.min(720.0, screen.width - 80);
    final notesHeight = expanded ? math.max(320.0, screen.height - 260) : 320.0;
    // Ctrl+Enter = Save from anywhere in the dialog (the notes editor has its
    // own command, see NotesEditor.onSave, so it does not swallow the key).
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.numpadEnter, control: true):
            _save,
      },
      child: AlertDialog(
        title: Text(_isEditing ? 'Edit action' : 'New action'),
        content: SizedBox(
          width: math.max(280.0, width),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _nameController,
                    // A hint (not a label) so the word disappears once filled.
                    decoration: const InputDecoration(hintText: 'Name'),
                    autofocus: true,
                    // Enter = the Save button.
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _save(),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  Visibility(
                    visible: !expanded,
                    maintainState: true,
                    child: _buildTopSections(context),
                  ),
                  const SizedBox(height: 4),
                  // Collapsed by default (opened only when the action already
                  // has notes). `maintainState: false` keeps the heavy editor
                  // out of the tree until the section is opened; the latest
                  // JSON lives in `_notes`, so collapsing never loses edits.
                  ExpansionTile(
                    title: const Text('Notes'),
                    initiallyExpanded: _notesOpen,
                    maintainState: false,
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 8),
                    onExpansionChanged: (open) => setState(() {
                      _notesOpen = open;
                      if (!open) _notesExpanded = false;
                    }),
                    children: [
                      NotesEditor(
                        key: _notesKey,
                        initialJson: _notes,
                        onChanged: (json) => _notes = json,
                        onSave: _save,
                        height: notesHeight,
                        expanded: expanded,
                        onToggleExpand: () =>
                            setState(() => _notesExpanded = !_notesExpanded),
                      ),
                    ],
                  ),
                  Visibility(
                    visible: !expanded,
                    maintainState: true,
                    child: _buildBottomSections(context),
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
      ),
    );
  }

  /// Everything between the Name field and Notes: the button row, the
  /// schedule, time tracking, urgency and the growth directions.
  Widget _buildTopSections(BuildContext context) {
    final duration = formatDuration(
      computeActionDuration(
        startAt: _startAt,
        endAt: _endAt,
        legacyEstimatedMinutes: widget.existing?.estimatedMinutes,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isEditing)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            // Scaled down (never wrapped or clipped) to fit the dialog.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: QuickActionBar(
                actionId: widget.existing!.id,
                onDelete: _deleteAndClose,
              ),
            ),
          ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 16,
          runSpacing: 0,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DateTimeField(
              label: 'Start',
              value: _startAt,
              includeTime: !_isAllDay,
              onChanged: (v) => setState(() => _startAt = v),
            ),
            DateTimeField(
              label: 'End',
              value: _endAt,
              includeTime: !_isAllDay,
              onChanged: (v) => setState(() => _endAt = v),
            ),
            Text(
              'Duration: $duration',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('All day'),
                const SizedBox(width: 4),
                Switch(
                  value: _isAllDay,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (v) => setState(() => _isAllDay = v),
                ),
              ],
            ),
          ],
        ),
        _buildUrgencyLine(),
        if (_isEditing)
          _TimeTrackingSection(
            actionId: widget.existing!.id,
            scheduledStart: _startAt,
          ),
        ExpansionTile(
          title: const Text('Growth directions'),
          tilePadding: EdgeInsets.zero,
          initiallyExpanded: true,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MetricPicker(
              label: '',
              selectedIds: _selectedMetricIds,
              onOpen: (m) => openDirectionById(context, ref, m.id),
              onChanged: (ids) => setState(() => _selectedMetricIds = ids),
            ),
          ],
        ),
      ],
    );
  }

  /// Connected actions (Previous left, Next right) and Manual parameters.
  Widget _buildBottomSections(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isEditing)
          ExpansionTile(
            title: const Text('Connected actions'),
            tilePadding: EdgeInsets.zero,
            initiallyExpanded: true,
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [_DependencySection(actionId: widget.existing!.id)],
          ),
        ExpansionTile(
          title: const Text('Manual parameters'),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _postponeFlex,
                    isDense: true,
                    dropdownColor: context.glass.fillDialog,
                    decoration: const InputDecoration(
                      labelText: 'Postpone flexibility',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'flexible',
                        child: Text('Flexible'),
                      ),
                      DropdownMenuItem(value: 'hard', child: Text('Hard')),
                      DropdownMenuItem(
                        value: 'impossible',
                        child: Text('Impossible'),
                      ),
                    ],
                    onChanged: (v) => setState(() => _postponeFlex = v!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: _depthLevel,
                    isDense: true,
                    dropdownColor: context.glass.fillDialog,
                    decoration: const InputDecoration(
                      labelText: 'Depth (learning)',
                    ),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('N/A')),
                      DropdownMenuItem(value: 'easy', child: Text('Easy')),
                      DropdownMenuItem(value: 'medium', child: Text('Medium')),
                      DropdownMenuItem(value: 'deep', child: Text('Deep')),
                    ],
                    onChanged: (v) => setState(() => _depthLevel = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildCountableActivityField(),
          ],
        ),
      ],
    );
  }

  /// The button row's Delete: run it (Undo snackbar) and close this editor,
  /// which would otherwise show a row that no longer exists.
  void _deleteAndClose() {
    // The helper reads what it needs from `ref`/`context` before its first
    // await, i.e. before this dialog is gone.
    unawaited(runUndoableDelete(context, ref, widget.existing!.id));
    Navigator.of(context).pop();
  }

  /// Read-only "Urgency to Keep in Balance": computed live from the directions
  /// currently selected (saved or not), so it follows the picker. Hidden when
  /// none is selected.
  Widget _buildUrgencyLine() {
    final stats = ref.watch(growthSnapshotProvider).value?.stats;
    if (stats == null) return const SizedBox.shrink();
    final urgency = actionUrgency(_selectedMetricIds, stats);
    if (urgency == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        'Urgency to Keep in Balance: ${formatUrgency(urgency)}',
        key: const ValueKey('actionUrgencyLine'),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }

  static const _newActivityValue = '__new_activity__';

  /// Picker for the Countable Activity; its recent average predicts the
  /// duration of "Continue with same action". "New activity…" creates one
  /// inline.
  Widget _buildCountableActivityField() {
    final activities =
        ref.watch(countableActivitiesProvider).value ??
        const <CountableActivity>[];
    // A stale id (activity deleted elsewhere) must not crash the dropdown.
    final selected = activities.any((a) => a.id == _countableActivityId)
        ? _countableActivityId
        : null;

    return DropdownButtonFormField<String?>(
      key: ValueKey((selected, _activityFieldEpoch)),
      initialValue: selected,
      isDense: true,
      dropdownColor: context.glass.fillDialog,
      decoration: const InputDecoration(labelText: 'Countable activity'),
      items: [
        const DropdownMenuItem(value: null, child: Text('None')),
        for (final a in activities)
          DropdownMenuItem(value: a.id, child: Text(a.name)),
        const DropdownMenuItem(
          value: _newActivityValue,
          child: Text('New activity…'),
        ),
      ],
      onChanged: (v) async {
        if (v != _newActivityValue) {
          setState(() => _countableActivityId = v);
          return;
        }
        final name = await _askActivityName();
        if (!mounted) return;
        if (name == null) {
          // Cancelled: rebuild the field so it stops showing "New activity…".
          setState(() => _activityFieldEpoch++);
          return;
        }
        final id = await ref
            .read(actionServiceProvider)
            .createCountableActivity(name);
        if (mounted) setState(() => _countableActivityId = id);
      },
    );
  }

  Future<String?> _askActivityName() {
    final controller = TextEditingController();
    return showStackedDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New countable activity'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (v) => Navigator.of(dialogContext).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    ).then((name) => (name == null || name.isEmpty) ? null : name);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final service = ref.read(actionServiceProvider);
    final name = _nameController.text.trim();

    if (_isEditing) {
      final id = widget.existing!.id;
      await service.updateAction(
        actionId: id,
        name: name,
        postponeFlex: _postponeFlex,
        depthLevel: _depthLevel,
        startAt: _startAt,
        endAt: _endAt,
        isAllDay: _isAllDay,
        notes: Value(_notes),
      );
      await service.setMetrics(id, _selectedMetricIds.toList());
      await service.setCountableActivity(id, _countableActivityId);
    } else {
      await service.createAction(
        name: name,
        postponeFlex: _postponeFlex,
        depthLevel: _depthLevel,
        startAt: _startAt,
        endAt: _endAt,
        isAllDay: _isAllDay,
        countableActivityId: _countableActivityId,
        metricIds: _selectedMetricIds.toList(),
        notes: _notes,
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
    // Shown only once the action has been started at least once.
    final occurrences =
        ref.watch(occurrencesOfProvider(actionId)).value ??
        const <ActionOccurrence>[];
    if (occurrences.isEmpty) return const SizedBox.shrink();

    final latest = occurrences.first;
    final String text;
    if (latest.finishedAt == null) {
      final start = scheduledStart;
      text = start != null
          ? 'Currently running — started ${_fmt(start)}'
          : 'Currently running';
    } else {
      final started = dateTimeFromDb(latest.startedAt);
      final finished = dateTimeFromDb(latest.finishedAt);
      text = (started != null && finished != null)
          ? 'Last: ${_fmt(started)} → ${_fmt(finished)}'
          : '';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Time tracking', style: Theme.of(context).textTheme.titleSmall),
          if (text.isNotEmpty) Text(text),
        ],
      ),
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
    final predecessors =
        ref.watch(predecessorsOfProvider(actionId)).value ??
        const <ActionRow>[];
    final successors =
        ref.watch(successorsOfProvider(actionId)).value ?? const <ActionRow>[];

    // Previous on the left, Next on the right; an empty side is only a +.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _column(
            context,
            ref,
            title: 'Previous',
            items: predecessors,
            isPredecessor: true,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _column(
            context,
            ref,
            title: 'Next',
            items: successors,
            isPredecessor: false,
          ),
        ),
      ],
    );
  }

  Widget _column(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required List<ActionRow> items,
    required bool isPredecessor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final item in items)
              InputChip(
                label: Text(item.name),
                tooltip: 'Open this action',
                // Stacked on top (not replacing) so unsaved edits in the
                // current editor aren't lost; closing it returns here.
                onPressed: () => openActionById(context, ref, item.id),
                onDeleted: () {
                  final deps = ref.read(dependencyServiceProvider);
                  deps.removeDependency(
                    predecessorId: isPredecessor ? item.id : actionId,
                    successorId: isPredecessor ? actionId : item.id,
                  );
                },
              ),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: isPredecessor
                  ? 'Add previous action'
                  : 'Add next action',
              visualDensity: VisualDensity.compact,
              onPressed: () =>
                  _addDependency(context, ref, asPredecessor: isPredecessor),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _addDependency(
    BuildContext context,
    WidgetRef ref, {
    required bool asPredecessor,
  }) async {
    final chosen = await showStackedDialog<ActionRow>(
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
                loading: () => const Center(child: CircularProgressIndicator()),
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
