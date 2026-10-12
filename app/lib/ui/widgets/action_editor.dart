import 'dart:async';
import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/time_codec.dart';
import '../../data/database.dart';
import '../../domain/action_urgency.dart';
import '../../domain/chain_schedule.dart';
import '../../domain/dependency_service.dart';
import '../../domain/duration_rules.dart';
import '../dialog_back.dart';
import '../dialog_stack.dart';
import '../layout.dart';
import '../open_entity.dart';
import '../providers.dart';
import '../sync_providers.dart';
import '../undo.dart';
import 'action_budget_section.dart';
import 'action_picker_dialog.dart';
import 'activity_picker_dialog.dart';
import 'action_tile.dart' show formatUrgency;
import 'app_toast.dart';
import 'glass_icon_tile.dart' show GlassHue;
import 'date_time_field.dart';
import 'metric_picker.dart';
import 'notes_document.dart';
import 'notes_editor.dart';
import 'what_is_done_button.dart';
import 'param_icons.dart';
import 'quick_action_bar.dart';
import 'section_block.dart';

/// The unsaved edits of an action form, kept when the Back button closes the
/// dialog so Undo can open it again exactly as it was.
class ActionEditorDraft {
  const ActionEditorDraft({
    required this.name,
    required this.startAt,
    required this.endAt,
    required this.isAllDay,
    required this.done,
    required this.metricIds,
    required this.countableActivityId,
    required this.notes,
    required this.postponeFlex,
    required this.depthLevel,
  });

  final String name;
  final DateTime? startAt;
  final DateTime? endAt;
  final bool isAllDay;
  final bool done;
  final Set<String> metricIds;
  final String? countableActivityId;
  final String? notes;
  final String postponeFlex;
  final String? depthLevel;
}

/// Create/edit dialog for a single action: core fields, metric links, and
/// (when editing) its previous/next action dependencies.
class ActionEditorDialog extends ConsumerStatefulWidget {
  final ActionRow? existing;

  /// For a new action: the schedule to start with (UTC), e.g. the time range
  /// dragged out on the calendar.
  final DateTime? initialStart;
  final DateTime? initialEnd;

  /// For a new action: growth directions to link from the start (the direction
  /// dialog's "New action" passes its own id).
  final Set<String> initialMetricIds;

  /// Unsaved edits to restore (Undo after a Back-button close).
  final ActionEditorDraft? draft;

  const ActionEditorDialog({
    super.key,
    this.existing,
    this.initialStart,
    this.initialEnd,
    this.initialMetricIds = const {},
    this.draft,
  });

  static Future<void> show(
    BuildContext context, {
    ActionRow? existing,
    DateTime? initialStart,
    DateTime? initialEnd,
    Set<String> initialMetricIds = const {},
    ActionEditorDraft? draft,
  }) {
    return showStackedDialog<void>(
      context: context,
      builder: (_) => ActionEditorDialog(
        existing: existing,
        initialStart: initialStart,
        initialEnd: initialEnd,
        initialMetricIds: initialMetricIds,
        draft: draft,
      ),
    );
  }

  @override
  ConsumerState<ActionEditorDialog> createState() => _ActionEditorDialogState();
}

class _ActionEditorDialogState extends ConsumerState<ActionEditorDialog>
    implements DraftDialog {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;

  String _postponeFlex = 'flexible';
  String? _depthLevel;
  DateTime? _startAt;
  DateTime? _endAt;
  bool _isAllDay = false;
  bool _done = false;
  Set<String> _selectedMetricIds = {};
  String? _countableActivityId;
  String? _notes;
  bool _notesOpen = false; // the Notes section (tile) is open
  bool _notesExpanded = false; // the editor's wide "Expand" mode
  final _notesKey = GlobalKey<NotesEditorState>();
  StreamSubscription<ActionRow?>? _rowSub;
  ActionRow? _seen; // the last database row seen (to spot external changes)
  String? _openStamp; // sync clock stamp of the row when the form was opened

  bool get _isEditing => widget.existing != null;

  /// Id of the action created by a Ctrl+S on a NEW form: later saves update it
  /// instead of creating a duplicate.
  String? _createdId;

  /// The directions the form was opened with (once loaded): what "changed"
  /// is measured against.
  Set<String> _baselineMetricIds = {};
  Timer? _notesTimer;

  /// Five quiet seconds after the last Notes change the notes alone are written
  /// (silently, the dialog stays as it is). A form that is not saved yet has
  /// nothing to write to, so a new action keeps them in the form.
  void _scheduleNotesAutosave() {
    _notesTimer?.cancel();
    final id = widget.existing?.id ?? _createdId;
    if (id == null) return;
    _notesTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      ref.read(actionServiceProvider).updateNotes(id, _notes);
    });
  }

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
    _selectedMetricIds = {...widget.initialMetricIds};

    if (existing != null) {
      _postponeFlex = existing.postponeFlex;
      _depthLevel = existing.depthLevel;
      _startAt = dateTimeFromDb(existing.startAt);
      _endAt = dateTimeFromDb(existing.endAt);
      _isAllDay = existing.isAllDay;
      _done = existing.done;
      _countableActivityId = existing.countableActivityId;

      // A one-shot query, not `ref.read(metricIdsOfProvider(..).future)`:
      // nothing listens to that auto-dispose provider, so Riverpod can
      // dispose it mid-load — which throws and leaves the future forever
      // pending, silently dropping the action's metric selection.
      final db = ref.read(databaseProvider);
      ref
          .read(syncStoreProvider)
          .rowStamp('actions', existing.id)
          .then((v) => _openStamp = v?.hlc);
      _seen = existing;
      _rowSub =
          (db.select(db.actionsTable)..where((t) => t.id.equals(existing.id)))
              .watchSingleOrNull()
              .listen(_onRowChanged);
      (db.select(
        db.actionMetricsTable,
      )..where((t) => t.actionId.equals(existing.id))).get().then((links) {
        if (mounted) {
          _baselineMetricIds = links.map((l) => l.metricId).toSet();
          if (widget.draft == null) {
            setState(() => _selectedMetricIds = {..._baselineMetricIds});
          }
        }
      });
    }

    final d = widget.draft;
    if (d != null) {
      _nameController.text = d.name;
      _startAt = d.startAt;
      _endAt = d.endAt;
      _isAllDay = d.isAllDay;
      _done = d.done;
      _selectedMetricIds = {...d.metricIds};
      _countableActivityId = d.countableActivityId;
      _notes = d.notes;
      _notesOpen =
          _notes != null &&
          !notesDocumentIsEmpty(notesDocumentFromJson(_notes));
      _postponeFlex = d.postponeFlex;
      _depthLevel = d.depthLevel;
    }
    if (existing == null) _baselineMetricIds = {...widget.initialMetricIds};
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    registerDraftDialog(ModalRoute.of(context), this);
  }

  /// True when the form differs from what was opened (or from the row as the
  /// database holds it now: Start/Finish/Postpone and autosave write there).
  bool get _isDirty {
    final base = _seen ?? widget.existing;
    if (_nameController.text != (base?.name ?? '')) return true;
    final start = base == null
        ? widget.initialStart
        : dateTimeFromDb(base.startAt);
    final end = base == null ? widget.initialEnd : dateTimeFromDb(base.endAt);
    if (_startAt != start || _endAt != end) return true;
    if (_isAllDay != (base?.isAllDay ?? false)) return true;
    if (_notes != base?.notes) return true;
    if (_countableActivityId != base?.countableActivityId) return true;
    return !(_selectedMetricIds.length == _baselineMetricIds.length &&
        _selectedMetricIds.containsAll(_baselineMetricIds));
  }

  @override
  void closeByBack() {
    final draft = _isDirty
        ? ActionEditorDraft(
            name: _nameController.text,
            startAt: _startAt,
            endAt: _endAt,
            isAllDay: _isAllDay,
            done: _done,
            metricIds: {..._selectedMetricIds},
            countableActivityId: _countableActivityId,
            notes: _notes,
            postponeFlex: _postponeFlex,
            depthLevel: _depthLevel,
          )
        : null;
    final existing = _seen ?? widget.existing;
    final shown = _nameController.text.trim();
    closeDraftDialog(
      context: context,
      ref: ref,
      label: shown.isEmpty ? 'action' : '"$shown"',
      draft: draft,
      reopen: (root, d) => ActionEditorDialog.show(
        root,
        existing: existing,
        initialStart: widget.initialStart,
        initialEnd: widget.initialEnd,
        initialMetricIds: widget.initialMetricIds,
        draft: d as ActionEditorDraft,
      ),
    );
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
    final doneChanged = row.done != prev.done;
    if (!scheduleChanged && !nameChanged && !doneChanged) return;
    setState(() {
      _done = row.done;
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
    unregisterDraftDialog(this);
    _notesTimer?.cancel();
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
    final compactLandscape =
        usePhoneLayout(context) &&
        MediaQuery.orientationOf(context) == Orientation.landscape;
    // Ctrl+Enter = Save from anywhere in the dialog (the notes editor has its
    // own command, see NotesEditor.onSave, so it does not swallow the key).
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _saveStay,
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.numpadEnter, control: true):
            _save,
      },
      child: AlertDialog(
        // Landscape phone: the title scrolls with the content (see below) so
        // the keyboard leaves room for the Name field; Save/Cancel stay pinned.
        insetPadding: compactLandscape
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 6)
            : null,
        contentPadding: compactLandscape
            ? const EdgeInsets.fromLTRB(20, 8, 20, 0)
            : null,
        actionsPadding: compactLandscape
            ? const EdgeInsets.fromLTRB(16, 0, 16, 4)
            : null,
        title: compactLandscape
            ? null
            : _isEditing && usePhoneLayout(context)
            // Phone: Delete sits in the dialog's top-right corner.
            ? Row(
                children: [
                  const Expanded(child: Text('Edit action')),
                  IconButton(
                    key: const ValueKey('editor-delete'),
                    tooltip: 'Delete',
                    color: Theme.of(context).colorScheme.error,
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: _deleteAndClose,
                  ),
                ],
              )
            : Text(_isEditing ? 'Edit action' : 'New action'),
        content: SizedBox(
          width: math.max(280.0, width),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (compactLandscape)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _isEditing ? 'Edit action' : 'New action',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (_isEditing)
                          IconButton(
                            key: const ValueKey('editor-delete'),
                            tooltip: 'Delete',
                            visualDensity: VisualDensity.compact,
                            color: Theme.of(context).colorScheme.error,
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: _deleteAndClose,
                          ),
                      ],
                    ),
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
                  SectionBlock(
                    padding: kSectionTileBlockPadding,
                    child: ExpansionTile(
                      title: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const ParamIcon(Param.notes, size: 20),
                          const SizedBox(width: 8),
                          const Flexible(
                            child: Text(
                              'Notes',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      shape: const Border(),
                      collapsedShape: const Border(),
                      initiallyExpanded: _notesOpen,
                      maintainState: false,
                      tilePadding: kSectionTilePadding,
                      childrenPadding: kSectionChildrenPadding,
                      onExpansionChanged: (open) => setState(() {
                        _notesOpen = open;
                        if (!open) _notesExpanded = false;
                      }),
                      children: [
                        NotesEditor(
                          key: _notesKey,
                          initialJson: _notes,
                          onChanged: (json) {
                            _notes = json;
                            _scheduleNotesAutosave();
                          },
                          onSave: _save,
                          toolbarExtra: widget.existing == null
                              ? null
                              : WhatIsDoneControl(
                                  actionId: widget.existing!.id,
                                  notesKey: _notesKey,
                                  initialBlocks: widget.existing!.resultNote,
                                ),
                          height: notesHeight,
                          expanded: expanded,
                          onToggleExpand: () =>
                              setState(() => _notesExpanded = !_notesExpanded),
                        ),
                      ],
                    ),
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
    final chain = _chainSpecs();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildUrgencyLine(),
        if (_isEditing)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: usePhoneLayout(context)
                // Phone: two groups of touch-sized tiles, each wrapping onto
                // rows: Start / Stop / Continue, then every postpone and
                // prolong. (Delete is in the title.)
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      QuickActionBar(
                        actionId: widget.existing!.id,
                        groups: const {0},
                        tileSize: 36,
                        iconSize: 22,
                        hitExtra: 4,
                        wrap: true,
                      ),
                      const SizedBox(height: 8),
                      QuickActionBar(
                        actionId: widget.existing!.id,
                        groups: const {1},
                        tileSize: 36,
                        iconSize: 22,
                        hitExtra: 4,
                        wrap: true,
                      ),
                      if (chain.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        QuickActionBar(
                          actionId: widget.existing!.id,
                          groups: const {3},
                          extra: chain,
                          tileSize: 36,
                          iconSize: 22,
                          hitExtra: 4,
                          wrap: true,
                        ),
                      ],
                    ],
                  )
                // Windows: one row in three parts - Start/Stop/Continue at the
                // left, the postpones in the middle, Delete at the right.
                : QuickActionBar(
                    actionId: widget.existing!.id,
                    onDelete: _deleteAndClose,
                    spread: true,
                    extra: chain,
                  ),
          ),
        const SizedBox(height: 4),
        SectionBlock(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: Start, End, Duration (fixed).
              Wrap(
                spacing: 16,
                runSpacing: 0,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DateTimeField(
                    label: 'Start',
                    value: _startAt,
                    includeTime: !_isAllDay,
                    onChanged: (v) => setState(() {
                      // The length stays: the end follows the start (form
                      // state only, saved with the action).
                      final old = _startAt;
                      final end = _endAt;
                      if (!_isAllDay && v != null && old != null && end != null) {
                        _endAt = end.add(v.difference(old));
                      }
                      _startAt = v;
                    }),
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
                ],
              ),
              // Row 2: All day, then [Done] to its right. Done appears only
              // for an all-day action being edited; All day never moves.
              Row(
                children: [
                  const Text('All day'),
                  const SizedBox(width: 4),
                  Switch(
                    key: const ValueKey('editorAllDaySwitch'),
                    value: _isAllDay,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (v) => setState(() => _isAllDay = v),
                  ),
                  if (_isEditing && _isAllDay) ...[
                    const SizedBox(width: 16),
                    const Text('Done'),
                    const SizedBox(width: 4),
                    Switch(
                      key: const ValueKey('editorDoneSwitch'),
                      value: _done,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (_) {
                        // Reads ref/context before its first await.
                        unawaited(
                          runUndoableToggleDone(
                            context,
                            ref,
                            widget.existing!.id,
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        if (_isEditing)
          _TimeTrackingSection(
            actionId: widget.existing!.id,
            scheduledStart: _startAt,
          ),
        SectionBlock(
          padding: kSectionTileBlockPadding,
          child: ExpansionTile(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ParamIcon(Param.direction, size: 20),
                const SizedBox(width: 8),
                const Flexible(
                  child: Text(
                    'Growth directions',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            shape: const Border(),
            collapsedShape: const Border(),
            tilePadding: kSectionTilePadding,
            initiallyExpanded: true,
            childrenPadding: kSectionChildrenPadding,
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MetricPicker(
                label: '',
                allowCreate: true,
                showUrgency: true,
                selectedIds: _selectedMetricIds,
                onOpen: (m) => openDirectionById(context, ref, m.id),
                onChanged: (ids) => setState(() => _selectedMetricIds = ids),
              ),
            ],
          ),
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
          SectionBlock(
            padding: kSectionTileBlockPadding,
            child: ExpansionTile(
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ParamIcon(Param.connected, size: 20),
                  const SizedBox(width: 8),
                  const Flexible(
                    child: Text(
                      'Connected actions',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              shape: const Border(),
              collapsedShape: const Border(),
              tilePadding: kSectionTilePadding,
              childrenPadding: kSectionChildrenPadding,
              initiallyExpanded: true,
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [_DependencySection(actionId: widget.existing!.id)],
            ),
          ),
        if (_isEditing) ActionBudgetSection(actionId: widget.existing!.id),
        SectionBlock(
          padding: kSectionTileBlockPadding,
          child: ExpansionTile(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ParamIcon(Param.manual, size: 20),
                const SizedBox(width: 8),
                const Flexible(
                  child: Text(
                    'Manual parameters',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            shape: const Border(),
            collapsedShape: const Border(),
            tilePadding: kSectionTilePadding,
            childrenPadding: kSectionChildrenPadding,
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 'Postpone flexibility' and 'Depth (learning)' are hidden in
              // the UI; their values are still loaded and saved unchanged.
              _buildCountableActivityField(),
            ],
          ),
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ParamValue.urgency(
        formatUrgency(urgency),
        size: 20,
        key: const ValueKey('actionUrgencyLine'),
        style: Theme.of(context).textTheme.bodyMedium,
        color: Theme.of(context).textTheme.bodyMedium?.color,
      ),
    );
  }

  /// Picker for the Countable Activity; its recent average predicts the
  /// duration of "Continue with same action". A read-only field that opens a
  /// searchable dialog; "New activity…" creates one inline.
  Widget _buildCountableActivityField() {
    final activities =
        ref.watch(countableActivitiesProvider).value ??
        const <CountableActivity>[];
    final templates =
        ref.watch(templatesProvider).value ?? const <ActionTemplate>[];
    // A stale id (activity deleted elsewhere) shows as None.
    String? name;
    for (final a in activities) {
      if (a.id == _countableActivityId) name = a.name;
    }
    return InkWell(
      key: const ValueKey('countableActivityField'),
      borderRadius: BorderRadius.circular(14),
      onTap: () => _pickActivity(activities, templates),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Countable activity',
          suffixIcon: Icon(Icons.arrow_drop_down),
        ),
        child: Text(name ?? 'None', softWrap: true),
      ),
    );
  }

  Future<void> _pickActivity(
    List<CountableActivity> activities,
    List<ActionTemplate> templates,
  ) async {
    final service = ref.read(actionServiceProvider);
    final result = await ActivityPickerDialog.show(
      context,
      activities: activities,
      templates: templates,
    );
    if (result == null || !mounted) return;
    switch (result) {
      case ActivityPickNone():
        setState(() => _countableActivityId = null);
      case ActivityPickExisting(:final id):
        setState(() => _countableActivityId = id);
      case ActivityPickTemplate(:final name):
        final id = await service.countableActivityForTemplate(name);
        if (mounted) setState(() => _countableActivityId = id);
      case ActivityPickNew():
        final name = await _askActivityName();
        if (!mounted || name == null) return;
        final id = await service.createCountableActivity(name);
        if (mounted) setState(() => _countableActivityId = id);
    }
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

  /// True when saving may go ahead. If ANOTHER device changed this action
  /// (through sync) while the form was open, saving would silently overwrite
  /// that change, so the user is asked first. Changes made here (Start,
  /// Finish... keep the dialog open) are not asked about.
  Future<bool> _confirmOverwriteRemote(String id) async {
    final store = ref.read(syncStoreProvider);
    final opened = _openStamp;
    final now = await store.rowStamp('actions', id);
    if (opened == null || now == null || now.hlc == opened) return true;
    if (now.origin == await store.deviceId()) return true;
    if (!mounted) return false;
    return await showStackedDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Changed on another device'),
            content: const Text(
              'This action was changed on your other device while you were '
              'editing it. Saving now replaces that change with yours.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const ValueKey('overwrite-remote'),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Overwrite'),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// Writes the form. False = nothing was saved (validation failed or the
  /// user declined to overwrite a change from another device).
  Future<bool> _persist() async {
    if (!_formKey.currentState!.validate()) return false;
    _notesTimer?.cancel();
    final service = ref.read(actionServiceProvider);
    final name = _nameController.text.trim();
    final id = widget.existing?.id ?? _createdId;

    if (id != null) {
      if (!await _confirmOverwriteRemote(id)) return false;
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
      _createdId = await service.createAction(
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
    return true;
  }

  Future<void> _save() async {
    if (!await _persist()) return;
    if (mounted) Navigator.of(context).pop();
  }

  /// Ctrl+S: the same write, but the dialog stays open and a toast confirms.
  Future<void> _saveStay() async {
    final overlay = rootOverlayOf(context);
    if (!await _persist()) return;
    showInfoToast(overlay, 'Saved');
  }

  /// "Set after previous actions" / "Set before next action": new times in the
  /// FORM only (saved with Save / Ctrl+S), keeping the length. Greyed out when
  /// no neighbour has a time; hidden for all-day actions.
  List<QuickActionSpec> _chainSpecs() {
    if (!_isEditing || _isAllDay) return const [];
    final id = widget.existing!.id;
    final prev = ref.watch(predecessorsOfProvider(id)).value ?? const [];
    final next = ref.watch(successorsOfProvider(id)).value ?? const [];
    ChainNeighbor nb(ActionRow r) => ChainNeighbor(
      startAt: dateTimeFromDb(r.startAt),
      endAt: dateTimeFromDb(r.endAt),
      isAllDay: r.isAllDay,
    );
    final after = scheduleAfterPrevious(
      prev.map(nb),
      currentStart: _startAt,
      currentEnd: _endAt,
    );
    final before = scheduleBeforeNext(
      next.map(nb),
      currentStart: _startAt,
      currentEnd: _endAt,
    );
    Future<void> apply(({DateTime start, DateTime end}) r) async {
      setState(() {
        _startAt = r.start;
        _endAt = r.end;
      });
    }

    return [
      QuickActionSpec(
        Icons.keyboard_tab_rounded,
        GlassHue.cyan,
        after == null
            ? 'Set after previous actions (no previous action has a time)'
            : 'Set after previous actions',
        3,
        () async => apply(after!),
        enabled: after != null,
      ),
      QuickActionSpec(
        Icons.start_rounded,
        GlassHue.cyan,
        before == null
            ? 'Set before next action (no next action has a time)'
            : 'Set before next action',
        3,
        () async => apply(before!),
        enabled: before != null,
      ),
    ];
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

    final previous = _column(
      context,
      ref,
      title: 'Previous actions',
      items: predecessors,
      isPredecessor: true,
    );
    final next = _column(
      context,
      ref,
      title: 'Next actions',
      items: successors,
      isPredecessor: false,
    );
    // Previous on the left, Next on the right (stacked on a phone); an empty
    // side is only its header.
    if (usePhoneLayout(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [previous, const SizedBox(height: 8), next],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: previous),
        const SizedBox(width: 16),
        Expanded(child: next),
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
        Row(
          children: [
            // Shrinks (rather than overflows) when the room is tight.
            Flexible(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
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
    final chosen = await ActionPickerDialog.show(
      context,
      excludeIds: {actionId},
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
