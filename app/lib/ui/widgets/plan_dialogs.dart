import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../domain/plan_rules.dart';
import '../../domain/plan_service.dart';
import '../dialog_stack.dart';
import '../plan_providers.dart';
import '../providers.dart';
import '../theme/glass_theme.dart';
import '../undo.dart';
import 'app_toast.dart';

// Planning mode's dialogs: the plan item editor, the "this day only / whole
// pattern" question, the confirm dialog (turn the plan into real actions) and the
// list of plan items.

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

DateTime _mondayOf(DateTime d) => d.subtract(Duration(days: d.weekday - 1));

String _dateLabel(DateTime d) => planDateKey(d);

TimeOfDay _tod(int minutes) =>
    TimeOfDay(hour: (minutes ~/ 60) % 24, minute: minutes % 60);

// ---- scope question ---------------------------------------------------------

enum PlanScope { day, all }

/// "This day only" or "Whole pattern" for a changed occurrence.
Future<PlanScope?> askPlanScope(BuildContext context) =>
    showStackedDialog<PlanScope>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change the plan'),
        content: const Text('Apply the new time to this day only, or to every repetition?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            key: const ValueKey('plan-scope-day'),
            onPressed: () => Navigator.of(ctx).pop(PlanScope.day),
            child: const Text('This day only'),
          ),
          FilledButton(
            key: const ValueKey('plan-scope-all'),
            onPressed: () => Navigator.of(ctx).pop(PlanScope.all),
            child: const Text('Whole pattern'),
          ),
        ],
      ),
    );

/// Applies a moved / resized ghost: asks the scope, then writes an override or
/// changes the rule.
Future<void> applyGhostChange(
  BuildContext context,
  WidgetRef ref,
  PlanOccurrence occ,
  int startMin,
  int durationMin,
) async {
  final scope = await askPlanScope(context);
  if (scope == null) return;
  final plans = ref.read(planServiceProvider);
  if (scope == PlanScope.day) {
    await plans.setOverride(
      itemId: occ.planItemId,
      date: occ.date,
      index: occ.index,
      startMin: startMin,
      durationMin: durationMin,
    );
  } else {
    await plans.shiftPattern(
      occ.planItemId,
      occ.index,
      startMin: startMin,
      durationMin: durationMin,
    );
  }
}

// ---- plan item editor ---------------------------------------------------------

class _OccRow {
  _OccRow({
    this.day = 0,
    this.startMin = 9 * 60,
    this.durationMin,
    String? name,
  }) : name = TextEditingController(text: name ?? ''),
       duration = TextEditingController(
         text: durationMin == null ? '' : '$durationMin',
       );

  int day;
  int startMin;
  int? durationMin;
  final TextEditingController name;
  final TextEditingController duration;

  void dispose() {
    name.dispose();
    duration.dispose();
  }
}

/// Creates or edits a plan item. Returns the saved id.
class PlanItemEditorDialog extends ConsumerStatefulWidget {
  const PlanItemEditorDialog({
    super.key,
    this.itemId,
    this.initialStart,
    this.initialMinutes,
    this.initialTemplateId,
  });

  final String? itemId;

  /// A swept range (UTC instant + minutes) a new item starts from.
  final DateTime? initialStart;
  final int? initialMinutes;
  final String? initialTemplateId;

  static Future<String?> show(
    BuildContext context, {
    String? itemId,
    DateTime? initialStart,
    int? initialMinutes,
  }) => showStackedDialog<String>(
    context: context,
    builder: (_) => PlanItemEditorDialog(
      itemId: itemId,
      initialStart: initialStart,
      initialMinutes: initialMinutes,
    ),
  );

  @override
  ConsumerState<PlanItemEditorDialog> createState() =>
      _PlanItemEditorDialogState();
}

class _PlanItemEditorDialogState extends ConsumerState<PlanItemEditorDialog> {
  final _name = TextEditingController();
  final _cycleDays = TextEditingController(text: '7');
  final _everyMonths = TextEditingController(text: '1');
  final _monthDay = TextEditingController(text: '1');
  final _manual = TextEditingController();
  String? _templateId;
  PlanKind _kind = PlanKind.cycle;
  DateTime _start = planDateOf(DateTime.now());
  DateTime? _end;
  bool _forever = false;
  bool _paused = false;
  final _rows = <_OccRow>[];
  MonthlyMode _mode = MonthlyMode.dayOfMonth;
  int _nth = 1;
  int _weekday = DateTime.monday;
  int _monthlyStart = 9 * 60;
  bool _loaded = false;
  PlanItem? _existing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.itemId;
    if (id != null) {
      final plans = ref.read(planServiceProvider);
      final row = (await plans.items()).where((r) => r.id == id).firstOrNull;
      if (row != null) {
        _existing = row;
        final d = plans.decode(row);
        _name.text = d.name;
        _templateId = d.templateId;
        _kind = d.kind;
        _start = d.startDate;
        _end = d.endDate;
        _forever = d.forever;
        _paused = d.paused;
        if (d.cycle != null) {
          _cycleDays.text = '${d.cycle!.cycleDays}';
          for (final o in d.cycle!.occurrences) {
            _rows.add(
              _OccRow(
                day: o.day,
                startMin: o.startMin,
                durationMin: o.durationMin,
                name: o.name,
              ),
            );
          }
        }
        final m = d.monthly;
        if (m != null) {
          _everyMonths.text = '${m.everyMonths}';
          _mode = m.mode;
          _monthDay.text = '${m.day}';
          _nth = m.nth;
          _weekday = m.weekday;
          _monthlyStart = m.startMin;
          if (m.durationMin != null) _manual.text = '${m.durationMin}';
        }
      }
    } else {
      final s = widget.initialStart;
      final mins = widget.initialMinutes;
      if (s != null) {
        final date = planDateOf(s);
        final startMin = s.difference(planInstant(date, 0)).inMinutes;
        _start = date;
        _rows.add(
          _OccRow(day: date.weekday - 1, startMin: startMin, durationMin: mins),
        );
        _monthlyStart = startMin;
        _monthDay.text = '${date.day}';
        _weekday = date.weekday;
        if (mins != null) _manual.text = '$mins';
      } else {
        _rows.add(_OccRow(day: _start.weekday - 1));
      }
    }
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _name.dispose();
    _cycleDays.dispose();
    _everyMonths.dispose();
    _monthDay.dispose();
    _manual.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  int get _days => (int.tryParse(_cycleDays.text) ?? 7).clamp(1, 365);

  Future<void> _pickDate({required bool end}) async {
    final first = DateTime(2020);
    final init = end ? (_end ?? _start) : _start;
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime(init.year, init.month, init.day),
      firstDate: first,
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    setState(() {
      final v = planDate(d.year, d.month, d.day);
      if (end) {
        _end = v;
      } else {
        _start = v;
      }
    });
  }

  Future<void> _pickTime(int minutes, ValueChanged<int> set) async {
    final t = await showTimePicker(context: context, initialTime: _tod(minutes));
    if (t != null) setState(() => set(t.hour * 60 + t.minute));
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showInfoToast(rootOverlayOf(context), 'Give the plan item a name');
      return;
    }
    final plans = ref.read(planServiceProvider);
    final nav = Navigator.of(context);
    var start = _start;
    CycleRule? cycle;
    MonthlyRule? monthly;
    int? manual;
    if (_kind == PlanKind.cycle) {
      final n = _days;
      // A weekly pattern is anchored to a Monday so its rows are plain weekdays.
      if (n == 7) start = _mondayOf(start);
      cycle = CycleRule(
        cycleDays: n,
        occurrences: [
          for (final r in _rows)
            CycleOccurrence(
              day: r.day % n,
              startMin: r.startMin,
              durationMin: int.tryParse(r.duration.text),
              name: r.name.text.trim().isEmpty ? null : r.name.text.trim(),
              templateId: null,
            ),
        ],
      );
      manual = _rows.isEmpty ? null : int.tryParse(_rows.first.duration.text);
    } else {
      manual = int.tryParse(_manual.text);
      monthly = MonthlyRule(
        everyMonths: (int.tryParse(_everyMonths.text) ?? 1).clamp(1, 99999),
        mode: _mode,
        day: (int.tryParse(_monthDay.text) ?? 1).clamp(1, 31),
        nth: _nth,
        weekday: _weekday,
        startMin: _monthlyStart,
        durationMin: manual,
      );
    }
    final id = await plans.saveItem(
      PlanItemInput(
        id: widget.itemId,
        name: name,
        templateId: _templateId,
        kind: _kind,
        startDate: start,
        endDate: _forever ? null : _end,
        forever: _forever,
        paused: _paused,
        cycle: cycle,
        monthly: monthly,
        manualMinutes: manual,
      ),
    );
    if (nav.mounted) nav.pop(id);
  }

  Widget _timeButton(Key key, int minutes, ValueChanged<int> set) =>
      OutlinedButton(
        key: key,
        onPressed: () => _pickTime(minutes, set),
        child: Text(planTime(minutes)),
      );

  Widget _cycleSection() {
    final n = _days;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Repeats every'),
            const SizedBox(width: 8),
            SizedBox(
              width: 64,
              child: TextField(
                key: const ValueKey('plan-cycle-days'),
                controller: _cycleDays,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            Text(n == 7 ? 'days (a week)' : 'days'),
          ],
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < _rows.length; i++) _rowEditor(i, n),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('plan-add-occurrence'),
            onPressed: () => setState(
              () => _rows.add(_OccRow(day: _rows.isEmpty ? 0 : _rows.last.day)),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Add a time'),
          ),
        ),
      ],
    );
  }

  Widget _rowEditor(int i, int n) {
    final r = _rows[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DropdownButton<int>(
            key: ValueKey('plan-row-day-$i'),
            value: r.day % n,
            dropdownColor: context.glassFillDialog,
            items: [
              for (var d = 0; d < n; d++)
                DropdownMenuItem(
                  value: d,
                  child: Text(n == 7 ? _weekdays[d] : 'Day ${d + 1}'),
                ),
            ],
            onChanged: (v) => setState(() => r.day = v ?? 0),
          ),
          _timeButton(
            ValueKey('plan-row-time-$i'),
            r.startMin,
            (v) => r.startMin = v,
          ),
          SizedBox(
            width: 84,
            child: TextField(
              key: ValueKey('plan-row-duration-$i'),
              controller: r.duration,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                hintText: 'minutes',
                isDense: true,
              ),
            ),
          ),
          SizedBox(
            width: 120,
            child: TextField(
              key: ValueKey('plan-row-name-$i'),
              controller: r.name,
              decoration: const InputDecoration(
                hintText: 'own name',
                isDense: true,
              ),
            ),
          ),
          IconButton(
            key: ValueKey('plan-row-remove-$i'),
            tooltip: 'Remove',
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => _rows.removeAt(i).dispose()),
          ),
        ],
      ),
    );
  }

  Widget _monthlySection() {
    String nthLabel(int v) => v == -1 ? 'last' : '${v}th';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Every'),
            const SizedBox(width: 8),
            SizedBox(
              width: 72,
              child: TextField(
                key: const ValueKey('plan-every-months'),
                controller: _everyMonths,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ),
            const SizedBox(width: 8),
            const Text('month(s)'),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DropdownButton<MonthlyMode>(
              key: const ValueKey('plan-monthly-mode'),
              value: _mode,
              dropdownColor: context.glassFillDialog,
              items: const [
                DropdownMenuItem(
                  value: MonthlyMode.dayOfMonth,
                  child: Text('Day of the month'),
                ),
                DropdownMenuItem(
                  value: MonthlyMode.nthWeekday,
                  child: Text('Nth weekday'),
                ),
                DropdownMenuItem(
                  value: MonthlyMode.lastDay,
                  child: Text('Last day'),
                ),
              ],
              onChanged: (v) => setState(() => _mode = v ?? _mode),
            ),
            if (_mode == MonthlyMode.dayOfMonth)
              SizedBox(
                width: 56,
                child: TextField(
                  key: const ValueKey('plan-month-day'),
                  controller: _monthDay,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
            if (_mode == MonthlyMode.nthWeekday) ...[
              DropdownButton<int>(
                key: const ValueKey('plan-monthly-nth'),
                value: _nth,
                dropdownColor: context.glassFillDialog,
                items: [
                  for (final v in const [1, 2, 3, 4, -1])
                    DropdownMenuItem(
                      value: v,
                      child: Text(v == -1 ? 'last' : nthLabel(v)),
                    ),
                ],
                onChanged: (v) => setState(() => _nth = v ?? _nth),
              ),
              DropdownButton<int>(
                key: const ValueKey('plan-monthly-weekday'),
                value: _weekday,
                dropdownColor: context.glassFillDialog,
                items: [
                  for (var d = 1; d <= 7; d++)
                    DropdownMenuItem(value: d, child: Text(_weekdays[d - 1])),
                ],
                onChanged: (v) => setState(() => _weekday = v ?? _weekday),
              ),
            ],
            _timeButton(
              const ValueKey('plan-monthly-time'),
              _monthlyStart,
              (v) => _monthlyStart = v,
            ),
            SizedBox(
              width: 84,
              child: TextField(
                key: const ValueKey('plan-monthly-duration'),
                controller: _manual,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  hintText: 'minutes',
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final templates =
        ref.watch(templatesProvider).value ?? const <ActionTemplate>[];
    final isNew = widget.itemId == null;
    return AlertDialog(
      title: Text(isNew ? 'New plan item' : 'Edit plan item'),
      content: SizedBox(
        width: 520,
        child: !_loaded
            ? const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      key: const ValueKey('plan-name'),
                      controller: _name,
                      autofocus: isNew,
                      decoration: const InputDecoration(hintText: 'Name'),
                    ),
                    const SizedBox(height: 8),
                    DropdownButton<String?>(
                      key: const ValueKey('plan-template'),
                      isExpanded: true,
                      value: templates.any((t) => t.id == _templateId)
                          ? _templateId
                          : null,
                      dropdownColor: context.glassFillDialog,
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(
                            isNew
                                ? 'New template from this name'
                                : 'No template',
                          ),
                        ),
                        for (final t in templates)
                          DropdownMenuItem<String?>(
                            value: t.id,
                            child: Text(t.name, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) => setState(() => _templateId = v),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<PlanKind>(
                      key: const ValueKey('plan-kind'),
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: PlanKind.cycle,
                          label: Text('Days cycle'),
                        ),
                        ButtonSegment(
                          value: PlanKind.monthly,
                          label: Text('Monthly'),
                        ),
                      ],
                      selected: {_kind},
                      onSelectionChanged: (s) => setState(() => _kind = s.first),
                    ),
                    const SizedBox(height: 10),
                    if (_kind == PlanKind.cycle)
                      _cycleSection()
                    else
                      _monthlySection(),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('From'),
                        OutlinedButton(
                          key: const ValueKey('plan-start-date'),
                          onPressed: () => _pickDate(end: false),
                          child: Text(_dateLabel(_start)),
                        ),
                        const Text('until'),
                        OutlinedButton(
                          key: const ValueKey('plan-end-date'),
                          onPressed: _forever ? null : () => _pickDate(end: true),
                          child: Text(
                            _forever || _end == null ? 'no end' : _dateLabel(_end!),
                          ),
                        ),
                        if (_end != null && !_forever)
                          IconButton(
                            key: const ValueKey('plan-end-clear'),
                            tooltip: 'No end',
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () => setState(() => _end = null),
                          ),
                      ],
                    ),
                    SwitchListTile(
                      key: const ValueKey('plan-forever'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Keep creating actions (forever)'),
                      subtitle: const Text(
                        'The next 8 weeks are filled in automatically.',
                      ),
                      value: _forever,
                      onChanged: (v) => setState(() => _forever = v),
                    ),
                    if (!isNew)
                      SwitchListTile(
                        key: const ValueKey('plan-paused'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Paused'),
                        value: _paused,
                        onChanged: (v) => setState(() => _paused = v),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('plan-save'),
          onPressed: _loaded && (isNew || _existing != null) ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

extension on BuildContext {
  Color get glassFillDialog => glass.fillDialog;
}

// ---- confirm ----------------------------------------------------------------

enum _Horizon { week, twoWeeks, month, threeMonths, year, custom, forever }

String _horizonLabel(_Horizon h) => switch (h) {
  _Horizon.week => '1 week',
  _Horizon.twoWeeks => '2 weeks',
  _Horizon.month => 'Month',
  _Horizon.threeMonths => '3 months',
  _Horizon.year => 'Year',
  _Horizon.custom => 'Until date',
  _Horizon.forever => 'Forever',
};

DateTime _addMonths(DateTime d, int months) {
  final idx = d.year * 12 + (d.month - 1) + months;
  final y = idx ~/ 12;
  final m = idx % 12 + 1;
  final last = DateTime.utc(y, m + 1, 0).day;
  return DateTime.utc(y, m, d.day > last ? last : d.day);
}

/// "Confirm plan": turns the plan items into real actions up to a chosen day.
class PlanConfirmDialog extends ConsumerStatefulWidget {
  const PlanConfirmDialog({super.key});

  static Future<void> show(BuildContext context) =>
      showStackedDialog<void>(
        context: context,
        builder: (_) => const PlanConfirmDialog(),
      );

  @override
  ConsumerState<PlanConfirmDialog> createState() => _PlanConfirmDialogState();
}

class _PlanConfirmDialogState extends ConsumerState<PlanConfirmDialog> {
  _Horizon _horizon = _Horizon.twoWeeks;
  DateTime? _custom;
  Set<String>? _selected; // null = all items
  int? _toCreate;
  int _existing = 0;
  int _seq = 0;
  bool _busy = false;

  DateTime get _today => planDateOf(DateTime.now());

  DateTime get _to => switch (_horizon) {
    _Horizon.week => _today.add(const Duration(days: 6)),
    _Horizon.twoWeeks => _today.add(const Duration(days: 13)),
    _Horizon.month => _addMonths(_today, 1),
    _Horizon.threeMonths => _addMonths(_today, 3),
    _Horizon.year => _addMonths(_today, 12),
    _Horizon.custom => _custom ?? _today.add(const Duration(days: 13)),
    // The rolling window a "forever" item keeps filled.
    _Horizon.forever => _today.add(const Duration(days: 8 * 7 - 1)),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final seq = ++_seq;
    final p = await ref
        .read(planServiceProvider)
        .preview(itemIds: _selected, from: _today, to: _to);
    if (!mounted || seq != _seq) return;
    setState(() {
      _toCreate = p.toCreate.length;
      _existing = p.existing;
    });
  }

  Future<void> _confirm() async {
    setState(() => _busy = true);
    final plans = ref.read(planServiceProvider);
    final nav = Navigator.of(context);
    final overlay = rootOverlayOf(context);
    if (_horizon == _Horizon.forever) {
      final ids = _selected ?? {for (final r in await plans.items()) r.id};
      for (final id in ids) {
        await plans.setForever(id, true);
      }
    }
    if (!mounted) return;
    final result = await runUndoableConfirmPlan(
      context,
      ref,
      itemIds: _selected,
      from: _today,
      to: _to,
    );
    if (result.createdIds.isEmpty) {
      showInfoToast(overlay, 'Nothing new to create');
    }
    if (nav.mounted) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(planItemsProvider).value ?? const <PlanItem>[];
    return AlertDialog(
      title: const Text('Confirm plan'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Create real actions from now until:'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final h in _Horizon.values)
                    ChoiceChip(
                      key: ValueKey('plan-horizon-${h.name}'),
                      label: Text(
                        h == _Horizon.custom && _custom != null
                            ? _dateLabel(_custom!)
                            : _horizonLabel(h),
                      ),
                      selected: _horizon == h,
                      onSelected: (_) async {
                        if (h == _Horizon.custom) {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate: DateTime(2100),
                          );
                          if (d == null) return;
                          _custom = planDate(d.year, d.month, d.day);
                        }
                        setState(() => _horizon = h);
                        _refresh();
                      },
                    ),
                ],
              ),
              if (_horizon == _Horizon.forever)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'The chosen items keep the next 8 weeks filled in whenever the app opens.',
                  ),
                ),
              const SizedBox(height: 10),
              const Text('Plan items'),
              for (final r in items)
                CheckboxListTile(
                  key: ValueKey('plan-confirm-item-${r.id}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(r.name),
                  value: _selected == null || _selected!.contains(r.id),
                  onChanged: (v) {
                    final all = {for (final i in items) i.id};
                    final cur = {...(_selected ?? all)};
                    v == true ? cur.add(r.id) : cur.remove(r.id);
                    setState(() => _selected = cur.length == all.length ? null : cur);
                    _refresh();
                  },
                ),
              const SizedBox(height: 8),
              Text(
                _toCreate == null
                    ? '...'
                    : '$_toCreate action(s) to create'
                          '${_existing > 0 ? ', $_existing already exist' : ''}',
                key: const ValueKey('plan-confirm-preview'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('plan-confirm'),
          onPressed: _busy || items.isEmpty ? null : _confirm,
          child: const Text('Create actions'),
        ),
      ],
    );
  }
}

// ---- plan items list ----------------------------------------------------------

class PlanItemsDialog extends ConsumerWidget {
  const PlanItemsDialog({super.key});

  static Future<void> show(BuildContext context) => showStackedDialog<void>(
    context: context,
    builder: (_) => const PlanItemsDialog(),
  );

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    PlanItem item,
  ) async {
    final choice = await showStackedDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${item.name}"?'),
        content: const Text(
          'Also remove its future actions that were never edited?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            key: const ValueKey('plan-delete-keep'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep actions'),
          ),
          FilledButton(
            key: const ValueKey('plan-delete-remove'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove them'),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    await runUndoableDeletePlanItem(context, ref, item.id, removeFuture: choice);
  }

  Future<void> _removeFuture(
    BuildContext context,
    WidgetRef ref,
    PlanItem item,
  ) async {
    final plans = ref.read(planServiceProvider);
    final overlay = rootOverlayOf(context);
    final history = ref.read(undoHistoryProvider.notifier);
    final actions = ref.read(actionServiceProvider);
    final undo = await plans.removeFuture(item.id);
    if (undo == null) {
      showInfoToast(overlay, 'No untouched future actions');
      return;
    }
    offerUndo(
      overlay,
      history,
      'Removed ${undo.count} future actions',
      () => actions.undoDeleteMany(undo),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(planItemsProvider).value ?? const <PlanItem>[];
    final plans = ref.read(planServiceProvider);
    return AlertDialog(
      title: const Text('Plan items'),
      content: SizedBox(
        width: 480,
        child: items.isEmpty
            ? const Text('Nothing planned yet. Sweep a time on the calendar.')
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final r in items)
                      ListTile(
                        key: ValueKey('plan-item-${r.id}'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          r.name,
                          style: TextStyle(
                            decoration: r.paused
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        subtitle: Text(
                          '${describePlan(plans.decode(r))}'
                          '${r.forever ? ' · forever' : ''}'
                          '${r.paused ? ' · paused' : ''}',
                        ),
                        onTap: () =>
                            PlanItemEditorDialog.show(context, itemId: r.id),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              key: ValueKey('plan-pause-${r.id}'),
                              tooltip: r.paused ? 'Resume' : 'Pause',
                              icon: Icon(
                                r.paused ? Icons.play_arrow : Icons.pause,
                                size: 18,
                              ),
                              onPressed: () => plans.setPaused(r.id, !r.paused),
                            ),
                            IconButton(
                              key: ValueKey('plan-remove-future-${r.id}'),
                              tooltip: 'Remove future actions',
                              icon: const Icon(Icons.event_busy, size: 18),
                              onPressed: () => _removeFuture(context, ref, r),
                            ),
                            IconButton(
                              key: ValueKey('plan-delete-${r.id}'),
                              tooltip: 'Delete',
                              icon: const Icon(Icons.delete_outline, size: 18),
                              onPressed: () => _delete(context, ref, r),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
