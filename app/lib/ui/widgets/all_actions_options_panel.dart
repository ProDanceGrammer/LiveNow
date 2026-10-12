import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../../domain/all_actions_view_rules.dart';
import '../dialog_stack.dart';
import '../providers.dart';
import '../theme/glass_theme.dart';
import 'date_range_fields.dart';
import 'glass.dart';
import 'metric_picker.dart';
import 'param_icons.dart';

/// The collapsible panel under the All list's search field: waterfall sort
/// chips and the filters. It only edits the providers; the rules live in
/// `domain/all_actions_view_rules.dart`.
class AllActionsOptionsPanel extends ConsumerWidget {
  const AllActionsOptionsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: GlassSurface(
        radius: 16,
        shadow: false,
        blurWindow: false,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: const SingleChildScrollView(
            padding: EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [_SortRow(), SizedBox(height: 12), _FilterSection()],
            ),
          ),
        ),
      ),
    );
  }
}

class _SortRow extends ConsumerWidget {
  const _SortRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(allActionsSortProvider);
    void set(List<SortKey> v) =>
        ref.read(allActionsSortProvider.notifier).state = v;

    void move(int from, int to) {
      if (from == to) return;
      final list = [...sort];
      final k = list.removeAt(from);
      list.insert(to, k);
      set(list);
    }

    final remaining = [
      for (final f in SortField.values)
        if (!sort.any((k) => k.field == f)) f,
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Sort', style: Theme.of(context).textTheme.titleSmall),
        for (var i = 0; i < sort.length; i++)
          _SortChip(
            key: ValueKey('sortChip-${sort[i].field.name}'),
            index: i,
            sortKey: sort[i],
            onToggle: () => set([
              for (var j = 0; j < sort.length; j++)
                if (j == i) sort[j].toggled() else sort[j],
            ]),
            onRemove: () => set([...sort]..removeAt(i)),
            onMove: move,
          ),
        if (remaining.isNotEmpty)
          PopupMenuButton<SortField>(
            key: const ValueKey('sortAdd'),
            tooltip: 'Add a sort level',
            onSelected: (f) => set([...sort, SortKey(f)]),
            itemBuilder: (_) => [
              for (final f in remaining)
                PopupMenuItem(value: f, child: Text(f.label)),
            ],
            child: const Chip(
              avatar: Icon(Icons.add, size: 16),
              label: Text('Add sort'),
            ),
          ),
      ],
    );
  }
}

/// A removable chip "Field ↑/↓": tap toggles asc/desc, drag onto another chip
/// moves it (the sort is a waterfall, so order matters).
class _SortChip extends StatelessWidget {
  final int index;
  final SortKey sortKey;
  final VoidCallback onToggle;
  final VoidCallback onRemove;
  final void Function(int from, int to) onMove;

  const _SortChip({
    super.key,
    required this.index,
    required this.sortKey,
    required this.onToggle,
    required this.onRemove,
    required this.onMove,
  });

  @override
  Widget build(BuildContext context) {
    final chip = InputChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(sortKey.field.label),
          const SizedBox(width: 4),
          Icon(
            sortKey.ascending ? Icons.arrow_upward : Icons.arrow_downward,
            size: 14,
          ),
        ],
      ),
      tooltip: sortKey.ascending
          ? 'Ascending (tap: descending, drag: reorder)'
          : 'Descending (tap: ascending, drag: reorder)',
      onPressed: onToggle,
      onDeleted: onRemove,
    );
    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => d.data != index,
      onAcceptWithDetails: (d) => onMove(d.data, index),
      builder: (context, candidates, _) => Draggable<int>(
        data: index,
        feedback: Material(
          type: MaterialType.transparency,
          child: Opacity(opacity: 0.8, child: chip),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: chip),
        child: candidates.isEmpty
            ? chip
            : DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(GlassTheme.radiusChip),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                child: chip,
              ),
      ),
    );
  }
}

class _FilterSection extends ConsumerStatefulWidget {
  const _FilterSection();

  @override
  ConsumerState<_FilterSection> createState() => _FilterSectionState();
}

class _FilterSectionState extends ConsumerState<_FilterSection> {
  final _name = TextEditingController();
  final _minDur = TextEditingController();
  final _maxDur = TextEditingController();
  final _minUrg = TextEditingController();
  final _maxUrg = TextEditingController();

  @override
  void initState() {
    super.initState();
    // The panel can be re-opened: show what is already applied.
    final f = ref.read(allActionsFiltersProvider);
    _name.text = f.nameText;
    _minDur.text = f.minMinutes?.toString() ?? '';
    _maxDur.text = f.maxMinutes?.toString() ?? '';
    _minUrg.text = f.minUrgency == null ? '' : _num(f.minUrgency!);
    _maxUrg.text = f.maxUrgency == null ? '' : _num(f.maxUrgency!);
  }

  @override
  void dispose() {
    _name.dispose();
    _minDur.dispose();
    _maxDur.dispose();
    _minUrg.dispose();
    _maxUrg.dispose();
    super.dispose();
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : '$v';

  AllActionsFilters get _f => ref.read(allActionsFiltersProvider);
  void _set(AllActionsFilters f) =>
      ref.read(allActionsFiltersProvider.notifier).state = f;

  static double? _parseNum(String s) =>
      double.tryParse(s.trim().replaceAll(',', '.'));

  Widget _numField(
    Key key,
    TextEditingController c,
    String label,
    ValueChanged<String> onChanged, {
    Widget? prefix,
  }) => SizedBox(
    width: 136,
    child: TextField(
      key: key,
      controller: c,
      onChanged: onChanged,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        prefixIcon: prefix == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(right: 6),
                child: prefix,
              ),
        prefixIconConstraints: prefix == null
            ? null
            : const BoxConstraints(minWidth: 22, minHeight: 16),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final filters = ref.watch(allActionsFiltersProvider);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Filters', style: theme.textTheme.titleSmall),
            const Spacer(),
            if (filters.active)
              TextButton(
                key: const ValueKey('filtersReset'),
                onPressed: () {
                  _name.clear();
                  _minDur.clear();
                  _maxDur.clear();
                  _minUrg.clear();
                  _maxUrg.clear();
                  _set(const AllActionsFilters());
                },
                child: const Text('Reset filters'),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            SizedBox(
              width: 220,
              child: TextField(
                key: const ValueKey('filterName'),
                controller: _name,
                onChanged: (v) => _set(_f.copyWith(nameText: v)),
                decoration: const InputDecoration(
                  labelText: 'Name contains',
                  isDense: true,
                ),
              ),
            ),
            _numField(
              const ValueKey('filterMinDuration'),
              _minDur,
              'Min minutes',
              (v) {
                final n = int.tryParse(v.trim());
                _set(
                  n == null
                      ? _f.copyWith(clearMinMinutes: true)
                      : _f.copyWith(minMinutes: n),
                );
              },
            ),
            _numField(
              const ValueKey('filterMaxDuration'),
              _maxDur,
              'Max minutes',
              (v) {
                final n = int.tryParse(v.trim());
                _set(
                  n == null
                      ? _f.copyWith(clearMaxMinutes: true)
                      : _f.copyWith(maxMinutes: n),
                );
              },
            ),
            _numField(
              const ValueKey('filterMinUrgency'),
              _minUrg,
              'Min urgency',
              (v) {
                final n = _parseNum(v);
                _set(
                  n == null
                      ? _f.copyWith(clearMinUrgency: true)
                      : _f.copyWith(minUrgency: n),
                );
              },
              prefix: const ParamIcon.urgency(size: 16),
            ),
            _numField(
              const ValueKey('filterMaxUrgency'),
              _maxUrg,
              'Max urgency',
              (v) {
                final n = _parseNum(v);
                _set(
                  n == null
                      ? _f.copyWith(clearMaxUrgency: true)
                      : _f.copyWith(maxUrgency: n),
                );
              },
              prefix: const ParamIcon.urgency(size: 16),
            ),
            // Actions whose START falls on these days (unscheduled ones are
            // left out while a date is set).
            DateRangeFields(
              keyPrefix: 'filterDate',
              value: filters.dateRange,
              onChanged: (r) => _set(_f.copyWith(dateRange: r)),
            ),
            _LinkFilterField(
              label: 'Previous',
              keyPrefix: 'filterPrevious',
              value: filters.previous,
              onChanged: (v) => _set(_f.copyWith(previous: v)),
            ),
            _LinkFilterField(
              label: 'Next',
              keyPrefix: 'filterNext',
              value: filters.next,
              onChanged: (v) => _set(_f.copyWith(next: v)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: MetricPicker(
                label: 'Growth directions',
                selectedIds: filters.metricIds,
                onChanged: (ids) => _set(_f.copyWith(metricIds: ids)),
              ),
            ),
            if (filters.metricIds.isNotEmpty)
              SegmentedButton<bool>(
                key: const ValueKey('filterMetricMode'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('Any')),
                  ButtonSegment(value: true, label: Text('All')),
                ],
                selected: {filters.allMetrics},
                onSelectionChanged: (s) =>
                    _set(_f.copyWith(allMetrics: s.first)),
              ),
          ],
        ),
      ],
    );
  }
}

/// "Previous" / "Next" filter: a mode dropdown and, for "Linked to", the
/// chosen action.
class _LinkFilterField extends ConsumerWidget {
  final String label;
  final String keyPrefix;
  final LinkFilter value;
  final ValueChanged<LinkFilter> onChanged;

  const _LinkFilterField({
    required this.label,
    required this.keyPrefix,
    required this.value,
    required this.onChanged,
  });

  static String _modeLabel(LinkMode m) => switch (m) {
    LinkMode.any => 'Any',
    LinkMode.has => 'Has some',
    LinkMode.none => 'Has none',
    LinkMode.linkedTo => 'Linked to…',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String? chosenName;
    if (value.mode == LinkMode.linkedTo && value.actionId != null) {
      final all = ref.watch(allActionsProvider).value ?? const [];
      for (final a in all) {
        if (a.id == value.actionId) chosenName = a.name;
      }
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          key: ValueKey(value.mode), // rebuild the field when Reset changes it
          width: 150,
          child: DropdownButtonFormField<LinkMode>(
            key: ValueKey('$keyPrefix-mode'),
            initialValue: value.mode,
            isDense: true,
            isExpanded: true,
            borderRadius: BorderRadius.circular(14),
            decoration: InputDecoration(labelText: label, isDense: true),
            items: [
              for (final m in LinkMode.values)
                DropdownMenuItem(value: m, child: Text(_modeLabel(m))),
            ],
            onChanged: (m) async {
              if (m == null) return;
              if (m != LinkMode.linkedTo) {
                onChanged(LinkFilter(mode: m));
                return;
              }
              final id = await _pickAction(context);
              if (id != null) {
                onChanged(LinkFilter(mode: m, actionId: id));
              }
            },
          ),
        ),
        if (value.mode == LinkMode.linkedTo) ...[
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: ActionChip(
              key: ValueKey('$keyPrefix-action'),
              label: Text(
                chosenName ?? 'Choose action',
                overflow: TextOverflow.ellipsis,
              ),
              onPressed: () async {
                final id = await _pickAction(context);
                if (id != null) {
                  onChanged(LinkFilter(mode: LinkMode.linkedTo, actionId: id));
                }
              },
            ),
          ),
        ],
      ],
    );
  }
}

Future<String?> _pickAction(BuildContext context) => showStackedDialog<String>(
  context: context,
  builder: (_) => const _ActionFilterPickerDialog(),
);

/// A small searchable list of every action (open or done), returning the id.
class _ActionFilterPickerDialog extends ConsumerStatefulWidget {
  const _ActionFilterPickerDialog();

  @override
  ConsumerState<_ActionFilterPickerDialog> createState() =>
      _ActionFilterPickerDialogState();
}

class _ActionFilterPickerDialogState
    extends ConsumerState<_ActionFilterPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(allActionsProvider).value ?? const <ActionListItem>[];
    final q = _query.trim().toLowerCase();
    final shown = [
      for (final a in all)
        if (q.isEmpty || a.name.toLowerCase().contains(q)) a,
    ];
    final sorted = [...shown]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final capped = sorted.take(200).toList();
    return AlertDialog(
      title: const Text('Choose an action'),
      content: SizedBox(
        width: 460,
        height: 460,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Search',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            Expanded(
              child: capped.isEmpty
                  ? const Center(child: Text('No matching actions.'))
                  : ListView.builder(
                      itemCount: capped.length,
                      itemBuilder: (context, i) => ListTile(
                        dense: true,
                        title: Text(capped[i].name),
                        onTap: () => Navigator.of(context).pop(capped[i].id),
                      ),
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
