import '../shortcut_keys.dart';
import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/text_rules.dart';
import '../../core/number_rules.dart';
import '../../data/database.dart' show ActionRow, Metric;
import '../../domain/growth_rules.dart';
import '../../domain/metric_service.dart';
import '../dialog_back.dart';
import '../dialog_stack.dart';
import '../layout.dart';
import '../providers.dart';
import '../theme/glass_theme.dart';
import '../undo.dart';
import 'glass_pill_selector.dart';
import 'direction_actions_panel.dart';
import 'emoji_picker_button.dart';
import 'metric_picker.dart';
import 'param_icons.dart';
import 'section_block.dart';

export 'direction_actions_panel.dart' show sortLinkedActionsByDistance;

/// The unsaved fields of a growth direction form (kept for Undo after Back).
class GrowthDirectionDraft {
  const GrowthDirectionDraft({
    required this.name,
    required this.target,
    required this.icon,
    required this.kind,
    required this.window,
    required this.isMain,
    required this.dependsOn,
    required this.leadsTo,
  });

  final String name;
  final String target;
  final String icon;
  final MetricKind kind;
  final MetricWindow window;
  final bool isMain;
  final Set<String> dependsOn;
  final Set<String> leadsTo;
}

/// Create or edit one growth direction: its type and target, whether it is a
/// main direction, and the directions it depends on / leads to. Deleting is
/// here too (with Undo, no confirmation).
class GrowthDirectionDialog extends ConsumerStatefulWidget {
  /// Null = create a new direction.
  final GrowthMetric? existing;

  /// Unsaved edits to restore (Undo after a Back-button close).
  final GrowthDirectionDraft? draft;

  const GrowthDirectionDialog({super.key, this.existing, this.draft});

  /// Opens the dialog; completes with the id of the direction that was saved
  /// (null when cancelled or deleted), so a caller can use a direction it just
  /// created (the action editor's "New direction").
  static Future<String?> show(
    BuildContext context, {
    GrowthMetric? existing,
    GrowthDirectionDraft? draft,
  }) {
    return showStackedDialog<String>(
      context: context,
      // Phone: a tap outside (e.g. to hide the keyboard) must not close the
      // item; only Cancel / Save / Delete / back do.
      barrierDismissible: !usePhoneLayout(context),
      builder: (_) => GrowthDirectionDialog(existing: existing, draft: draft),
    );
  }

  @override
  ConsumerState<GrowthDirectionDialog> createState() =>
      _GrowthDirectionDialogState();
}

class _GrowthDirectionDialogState extends ConsumerState<GrowthDirectionDialog>
    implements DraftDialog {
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

  // What the relations were when the form was opened (for "changed").
  Set<String> _baseDependsOn = {};
  Set<String> _baseLeadsTo = {};

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
    final d = widget.draft;
    if (d != null) {
      _name.text = d.name;
      _target.text = d.target;
      _icon.text = d.icon;
      _kind = d.kind;
      _window = d.window;
      _isMain = d.isMain;
      _dependsOn = {...d.dependsOn};
      _leadsTo = {...d.leadsTo};
    }

    if (m == null) {
      _relationsLoaded = true;
    } else {
      // A one-shot query rather than a provider's `.future` (see the note in
      // ActionEditorDialog: an unwatched auto-dispose provider can be
      // disposed mid-load).
      ref.read(metricServiceProvider).relationsOf(m.id).then((r) {
        if (!mounted) return;
        setState(() {
          _baseDependsOn = {...r.dependsOn};
          _baseLeadsTo = {...r.leadsTo};
          if (widget.draft == null) {
            _dependsOn = r.dependsOn;
            _leadsTo = r.leadsTo;
          }
          _relationsLoaded = true;
        });
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    registerDraftDialog(ModalRoute.of(context), this);
  }

  bool _same(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  bool get _isDirty {
    final m = widget.existing;
    if (_name.text != (m?.name ?? '')) return true;
    if (_target.text != _formatTarget(m?.target ?? 1)) return true;
    if (_icon.text != (m?.icon ?? '')) return true;
    if (_kind != (m?.kind ?? MetricKind.count)) return true;
    if (_window != (m?.window ?? MetricWindow.week)) return true;
    if (_isMain != (m?.isMain ?? false)) return true;
    return !_same(_dependsOn, _baseDependsOn) || !_same(_leadsTo, _baseLeadsTo);
  }

  @override
  void closeByBack() {
    final draft = _isDirty
        ? GrowthDirectionDraft(
            name: _name.text,
            target: _target.text,
            icon: _icon.text,
            kind: _kind,
            window: _window,
            isMain: _isMain,
            dependsOn: {..._dependsOn},
            leadsTo: {..._leadsTo},
          )
        : null;
    final existing = widget.existing;
    final shown = _name.text.trim();
    closeDraftDialog(
      context: context,
      ref: ref,
      label: shown.isEmpty ? 'direction' : '"$shown"',
      draft: draft,
      reopen: (root, d) => GrowthDirectionDialog.show(
        root,
        existing: existing,
        draft: d as GrowthDirectionDraft,
      ),
    );
  }

  @override
  void dispose() {
    unregisterDraftDialog(this);
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
    final phone = usePhoneLayout(context);
    final snapshot = ref.watch(growthSnapshotProvider).value;
    final live = _isEditing ? snapshot?.byId[widget.existing!.id] : null;
    final stat = _isEditing ? snapshot?.statOf(widget.existing!.id) : null;
    final hasLinkedActions =
        _isEditing &&
        (ref.watch(metricLinkedActionsProvider).value ??
                const <(String, ActionRow)>[])
            .any((l) => l.$1 == widget.existing!.id);
    final infoStyle = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: context.glass.textSecondary);

    return CallbackShortcuts(
      // Ctrl+Enter = Save, from any field.
      bindings: {
        primaryActivator(LogicalKeyboardKey.enter):
            _saveIfReady,
        primaryActivator(LogicalKeyboardKey.numpadEnter):
            _saveIfReady,
      },
      child: AlertDialog(
        title: Text(
          _isEditing ? 'Edit growth direction' : 'New growth direction',
        ),
        content: _content(
          context,
          Form(
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
                          // Phone: the keyboard opens only when a field is
                          // tapped, not as soon as the item opens.
                          autofocus: !phone,
                          // Enter = the Save button (once the relations have loaded).
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) {
                            if (_relationsLoaded) _save();
                          },
                          validator: nameFieldError,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _icon,
                          decoration: InputDecoration(
                            labelText: 'Icon (an emoji, optional)',
                            suffixIcon: EmojiPickerButton(
                              controller: _icon,
                              replace: true,
                              onChanged: () => setState(() {}),
                            ),
                          ),
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) {
                            if (_relationsLoaded) _save();
                          },
                        ),
                        // Progress first, then level, weight, urgency, fact.
                        if (_isEditing && live != null && stat != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: _GrowthInfoRow(
                              live: live,
                              stat: stat,
                              savedKind: widget.existing!.kind,
                              style: infoStyle,
                              stacked: phone,
                            ),
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
                              return (n == null ||
                                      !n.isFinite ||
                                      n <= 0 ||
                                      n > kMaxNumber)
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
                      ],
                    ),
                  ),
                  _Block(
                    padding: const EdgeInsets.all(12),
                    child: !_relationsLoaded
                        ? const LinearProgressIndicator()
                        : _twoLists(
                            phone,
                            // Linked actions ARE what this direction depends
                            // on, so the list is hidden while there are any
                            // (its saved edges are kept as they are).
                            hasLinkedActions
                                ? null
                                : MetricPicker(
                                    label: 'Depends on',
                                    labelTooltip:
                                        'Sub-directions that build it',
                                    selectedIds: _dependsOn,
                                    excludeId: widget.existing?.id,
                                    onOpen: _openRelated,
                                    allowCreate: true,
                                    onChanged: (ids) =>
                                        setState(() => _dependsOn = ids),
                                  ),
                            MetricPicker(
                              label: 'Leads to',
                              labelTooltip: 'Larger goals it feeds',
                              selectedIds: _leadsTo,
                              excludeId: widget.existing?.id,
                              onOpen: _openRelated,
                              allowCreate: true,
                              onChanged: (ids) =>
                                  setState(() => _leadsTo = ids),
                            ),
                          ),
                  ),
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

  /// The settings form and, for an existing direction, its linked actions: on a
  /// wide window (>= 1100 px) as a list to the RIGHT at the same height (each
  /// scrolls on its own, like a category's transactions), else below the form.
  Widget _content(BuildContext context, Widget form) {
    final id = widget.existing?.id;
    if (id == null) {
      return SizedBox(width: 720, child: SingleChildScrollView(child: form));
    }
    final size = MediaQuery.sizeOf(context);
    if (!usePhoneLayout(context) && size.width >= 1100) {
      return SizedBox(
        width: 560 + 16 + 420,
        height: (size.height - 220).clamp(420.0, 760.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 560, child: SingleChildScrollView(child: form)),
            const SizedBox(width: 16),
            SizedBox(width: 420, child: DirectionActionsPanel(metricId: id)),
          ],
        ),
      );
    }
    return SizedBox(
      width: 720,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            form,
            const SizedBox(height: 12),
            DirectionActionsPanel(metricId: id, scrollable: false),
          ],
        ),
      ),
    );
  }

  void _saveIfReady() {
    if (_relationsLoaded) _save();
  }

  /// Depends on | Leads to side by side; on a phone one list over the other.
  static Widget _twoLists(bool phone, Widget? a, Widget b) => a == null
      ? b
      : phone
      ? Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [a, const SizedBox(height: 16), b],
        )
      : Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: a),
            const SizedBox(width: 16),
            Expanded(child: b),
          ],
        );

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
      final savedId = await ref
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
      if (mounted) Navigator.of(context).pop(savedId);
    } on MetricCycleException catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } on InvalidNumberException catch (e) {
      if (mounted) setState(() => _error = e.text);
    } on InvalidNameException catch (e) {
      if (mounted) setState(() => _error = e.message);
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

/// progress (+ thin bar) - level - weight - urgency - fact (count/hours only,
/// by the SAVED kind). [stacked] (phone): the progress line first, all the
/// other values together on the line below it.
class _GrowthInfoRow extends StatelessWidget {
  final GrowthMetric live;
  final MetricStat stat;
  final MetricKind savedKind;
  final TextStyle? style;
  final bool stacked;

  const _GrowthInfoRow({
    required this.live,
    required this.stat,
    required this.savedKind,
    required this.style,
    this.stacked = false,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final progress = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ParamValue.progress(
          '${stat.progress.toStringAsFixed(1)}%',
          style: style,
        ),
        const SizedBox(width: 6),
        SizedBox(
          key: const ValueKey('dialogProgressBar'),
          width: stacked ? 140 : 80,
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
    );
    final others = <Widget>[
      ParamValue.level('${live.importanceLevel}', style: style),
      ParamValue.weight('${live.weight.round()}', style: style),
      ParamValue.urgency(stat.urgency.toStringAsFixed(1), style: style),
      if (savedKind != MetricKind.boolean)
        ParamValue.fact(
          formatFact(savedKind, stat.fact),
          key: const ValueKey('dialogFact'),
          style: style,
        ),
    ];
    Widget wrap(List<Widget> kids) => Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: kids,
    );
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [progress, const SizedBox(height: 6), wrap(others)],
      );
    }
    return wrap([progress, ...others]);
  }
}
