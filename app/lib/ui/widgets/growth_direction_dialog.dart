import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart' show ActionRow, Metric;
import '../../domain/growth_rules.dart';
import '../../domain/metric_service.dart';
import '../dialog_stack.dart';
import '../open_entity.dart';
import '../providers.dart';
import '../time_format.dart';
import '../../core/time_codec.dart';
import '../theme/glass_theme.dart';
import '../undo.dart';
import 'glass_pill_selector.dart';
import 'action_picker_dialog.dart';
import 'metric_picker.dart';
import 'param_icons.dart';
import 'section_block.dart';

/// Linked actions ordered by pure distance from now (|start - now|, past and
/// future interleaved); actions without a start come last, then by name.
List<ActionRow> sortLinkedActionsByDistance(
  List<ActionRow> actions,
  DateTime nowUtc,
) {
  final keyed = [
    for (final a in actions)
      (a, dateTimeFromDb(a.startAt)?.difference(nowUtc).abs()),
  ];
  keyed.sort((x, y) {
    final dx = x.$2, dy = y.$2;
    if (dx != null && dy != null) {
      final c = dx.compareTo(dy);
      if (c != 0) return c;
    } else if (dx != null) {
      return -1;
    } else if (dy != null) {
      return 1;
    }
    return x.$1.name.toLowerCase().compareTo(y.$1.name.toLowerCase());
  });
  return [for (final k in keyed) k.$1];
}

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
    final infoStyle = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: context.glass.textSecondary);

    return CallbackShortcuts(
      // Ctrl+Enter = Save, from any field.
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true):
            _saveIfReady,
        const SingleActivator(LogicalKeyboardKey.numpadEnter, control: true):
            _saveIfReady,
      },
      child: AlertDialog(
        title: Text(
          _isEditing ? 'Edit growth direction' : 'New growth direction',
        ),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Block(
                    margin: EdgeInsets.zero,
                    padding: const EdgeInsets.all(12),
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
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Required'
                              : null,
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
                        GlassPillSelector<MetricKind>(
                          label: 'Type',
                          options: const {
                            MetricKind.count: 'Number of actions',
                            MetricKind.hours: 'Hours spent',
                            MetricKind.boolean: 'Boolean',
                          },
                          value: _kind,
                          onChanged: (v) => setState(() => _kind = v),
                        ),
                        if (numeric) ...[
                          const SizedBox(height: 12),
                          GlassPillSelector<MetricWindow>(
                            label: 'Per',
                            options: const {
                              MetricWindow.week: 'Week',
                              MetricWindow.month: 'Month',
                              MetricWindow.year: 'Year',
                              MetricWindow.fiveYears: '5 years',
                            },
                            value: _window,
                            onChanged: (v) => setState(() => _window = v),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
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
                        ],
                        CheckboxListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              GlassTheme.radiusChip,
                            ),
                          ),
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text(
                            'Main growth direction (weight 1000)',
                          ),
                          value: _isMain,
                          onChanged: (v) =>
                              setState(() => _isMain = v ?? false),
                        ),
                        if (_isEditing && live != null && stat != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _GrowthInfoRow(
                              live: live,
                              stat: stat,
                              savedKind: widget.existing!.kind,
                              style: infoStyle,
                            ),
                          ),
                      ],
                    ),
                  ),
                  _Block(
                    padding: const EdgeInsets.all(12),
                    child: !_relationsLoaded
                        ? const LinearProgressIndicator()
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: MetricPicker(
                                  label: 'Depends on',
                                  labelTooltip: 'Sub-directions that build it',
                                  selectedIds: _dependsOn,
                                  excludeId: widget.existing?.id,
                                  onOpen: _openRelated,
                                  onChanged: (ids) =>
                                      setState(() => _dependsOn = ids),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: MetricPicker(
                                  label: 'Leads to',
                                  labelTooltip: 'Larger goals it feeds',
                                  selectedIds: _leadsTo,
                                  excludeId: widget.existing?.id,
                                  onOpen: _openRelated,
                                  onChanged: (ids) =>
                                      setState(() => _leadsTo = ids),
                                ),
                              ),
                            ],
                          ),
                  ),
                  if (_isEditing) _buildLinkedActions(context),
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
      ),
    );
  }

  void _saveIfReady() {
    if (_relationsLoaded) _save();
  }

  /// The actions linked to this direction; each chip opens that action's
  /// editor on top of this dialog (every related entity is openable).
  Widget _buildLinkedActions(BuildContext context) {
    final id = widget.existing!.id;
    final linked = [
      for (final (metricId, action)
          in ref.watch(metricLinkedActionsProvider).value ??
              const <(String, ActionRow)>[])
        if (metricId == id) action,
    ];
    final nowUtc = DateTime.now().toUtc();
    final sorted = sortLinkedActionsByDistance(linked, nowUtc);
    return _Block(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  'Linked actions (${sorted.length})',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Link an action',
                visualDensity: VisualDensity.compact,
                onPressed: () =>
                    _linkAction(id, {for (final a in sorted) a.id}),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (sorted.isEmpty)
            Text('None', style: TextStyle(color: context.glass.textSecondary))
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final a in sorted)
                    ListTile(
                      key: ValueKey('linked-action-${a.id}'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(a.name, overflow: TextOverflow.ellipsis),
                      trailing: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 160),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                formatShortSchedule(
                                      dateTimeFromDb(a.startAt),
                                      dateTimeFromDb(a.endAt),
                                      isAllDay: a.isAllDay,
                                      nowUtc: nowUtc,
                                    ) ??
                                    '',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.glass.textSecondary,
                                ),
                              ),
                            ),
                            IconButton(
                              key: ValueKey('unlink-action-${a.id}'),
                              icon: const Icon(Icons.close, size: 16),
                              tooltip: 'Unlink',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => ref
                                  .read(metricServiceProvider)
                                  .unlinkAction(a.id, id),
                            ),
                          ],
                        ),
                      ),
                      onTap: () => openActionById(context, ref, a.id),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _linkAction(String metricId, Set<String> linkedIds) async {
    final service = ref.read(metricServiceProvider);
    final picked = await ActionPickerDialog.show(
      context,
      excludeIds: linkedIds,
      includeDone: true,
    );
    if (picked == null) return;
    await service.linkAction(picked.id, metricId);
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

/// A [SectionBlock] with a transparent Material inside, so ListTiles in it
/// can paint their ink over the block's decorated background.
class _Block extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  const _Block({required this.child, required this.padding, this.margin});

  @override
  Widget build(BuildContext context) => margin == null
      ? SectionBlock(
          padding: padding,
          child: Material(type: MaterialType.transparency, child: child),
        )
      : SectionBlock(
          padding: padding,
          margin: margin!,
          child: Material(type: MaterialType.transparency, child: child),
        );
}

/// Formats the fact: a whole number for count directions, hours with one
/// decimal (trimmed) and ' h' for hours directions.
String formatFact(MetricKind kind, double fact) {
  if (kind == MetricKind.hours) {
    final t = fact.toStringAsFixed(1);
    return '${t.endsWith('.0') ? t.substring(0, t.length - 2) : t} h';
  }
  return fact.round().toString();
}

/// level - progress (+ thin bar) - weight - urgency - fact (count/hours only,
/// by the SAVED kind).
class _GrowthInfoRow extends StatelessWidget {
  final GrowthMetric live;
  final MetricStat stat;
  final MetricKind savedKind;
  final TextStyle? style;

  const _GrowthInfoRow({
    required this.live,
    required this.stat,
    required this.savedKind,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ParamValue.level('${live.importanceLevel}', style: style),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ParamValue.progress(
              '${stat.progress.toStringAsFixed(1)}%',
              style: style,
            ),
            const SizedBox(width: 6),
            SizedBox(
              key: const ValueKey('dialogProgressBar'),
              width: 80,
              height: 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: (stat.progress / 100).clamp(0.0, 1.0),
                  minHeight: 4,
                  color: primary,
                  backgroundColor: primary.withValues(alpha: 0.15),
                ),
              ),
            ),
          ],
        ),
        ParamValue.weight('${live.weight.round()}', style: style),
        ParamValue.urgency(stat.urgency.toStringAsFixed(1), style: style),
        if (savedKind != MetricKind.boolean)
          ParamValue.fact(
            formatFact(savedKind, stat.fact),
            key: const ValueKey('dialogFact'),
            style: style,
          ),
      ],
    );
  }
}
