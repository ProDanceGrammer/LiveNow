import '../search_targets.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../domain/plan_item_search.dart';
import '../../domain/plan_rules.dart';
import '../../domain/plan_service.dart';
import '../dialog_stack.dart';
import '../layout.dart';
import '../plan_providers.dart';
import '../providers.dart';
import '../screens/templates_screen.dart' show TemplatesScreen;
import '../theme/glass_theme.dart';
import '../undo.dart';
import 'app_toast.dart';
import 'section_block.dart';
import 'tx_templates.dart';

// Planning mode's dialogs: the plan item editor, the "this day only / whole
// pattern" question, the confirm dialog (turn the plan into real actions) and the
// list of plan items.

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _dateLabel(DateTime d) => planDateKey(d);

TimeOfDay _tod(int minutes) =>
    TimeOfDay(hour: (minutes ~/ 60) % 24, minute: minutes % 60);

// ---- scope question ---------------------------------------------------------

enum PlanScope { day, weekday, all }

/// "This day only", "This weekday only" ([weekday]: the item is a cycle that can
/// be split by weekday) or "Whole pattern" for a changed occurrence.
Future<PlanScope?> askPlanScope(BuildContext context, {bool weekday = false}) =>
    showStackedDialog<PlanScope>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change the plan'),
        content: Text(
          weekday
              ? 'Apply the new time to this day only, to this weekday every '
                    'week, or to every repetition?'
              : 'Apply the new time to this day only, or to every repetition?',
        ),
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
          if (weekday)
            OutlinedButton(
              key: const ValueKey('plan-scope-weekday'),
              onPressed: () => Navigator.of(ctx).pop(PlanScope.weekday),
              child: const Text('This weekday only'),
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
  final plans = ref.read(planServiceProvider);
  // Splitting by weekday makes sense for a cycle that is not already whole weeks.
  final item = (await plans.items()).where((r) => r.id == occ.planItemId).firstOrNull;
  var canSplit = false;
  if (item != null) {
    final data = plans.decode(item);
    final n = data.cycle?.cycleDays ?? 7;
    canSplit = data.kind == PlanKind.cycle && n % 7 != 0;
  }
  if (!context.mounted) return;
  final scope = await askPlanScope(context, weekday: canSplit);
  if (scope == null) return;
  if (scope == PlanScope.day) {
    await plans.setOverride(
      itemId: occ.planItemId,
      date: occ.date,
      index: occ.index,
      startMin: startMin,
      durationMin: durationMin,
    );
  } else if (scope == PlanScope.weekday) {
    await plans.shiftWeekday(
      occ.planItemId,
      occ.date,
      occ.index,
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

/// Asks whether the plan item's future, never-edited actions go with it, then
/// deletes it with one Undo. Used by the Plan items list and the right-click menu.
Future<void> askAndDeletePlanItem(
  BuildContext context,
  WidgetRef ref,
  String id,
  String name,
) async {
  final choice = await showStackedDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Delete "$name"?'),
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
  await runUndoableDeletePlanItem(context, ref, id, removeFuture: choice);
}

// ---- plan item editor ---------------------------------------------------------

/// A Previous / Next companion being edited.
class _Comp {
  _Comp({
    String? name,
    this.templateId,
    int minutes = 30,
    int gap = 0,
    List<String>? tx,
  }) : name = TextEditingController(text: name ?? ''),
       minutes = TextEditingController(text: '$minutes'),
       gap = TextEditingController(text: '$gap'),
       tx = [...?tx];

  final TextEditingController name;
  String? templateId;
  final TextEditingController minutes;
  final TextEditingController gap;
  final List<String> tx;

  _Comp copy() => _Comp(
    name: name.text,
    templateId: templateId,
    minutes: int.tryParse(minutes.text) ?? 30,
    gap: int.tryParse(gap.text) ?? 0,
    tx: tx,
  );

  PlanCompanion toCompanion() => PlanCompanion(
    name: name.text.trim().isEmpty ? null : name.text.trim(),
    templateId: templateId,
    minutes: (int.tryParse(minutes.text) ?? 30).clamp(1, 24 * 60),
    gapMinutes: (int.tryParse(gap.text) ?? 0).clamp(0, 7 * 24 * 60),
    txTemplateIds: [...tx],
  );

  void dispose() {
    name.dispose();
    minutes.dispose();
    gap.dispose();
  }
}

/// What one time row (or the monthly rule) brings besides the main action.
class _Extras {
  _Extras();

  factory _Extras.from(PlanExtras e) {
    final x = _Extras();
    for (final c in e.prev) {
      x.prev.add(
        _Comp(
          name: c.name,
          templateId: c.templateId,
          minutes: c.minutes,
          gap: c.gapMinutes,
          tx: c.txTemplateIds,
        ),
      );
    }
    for (final c in e.next) {
      x.next.add(
        _Comp(
          name: c.name,
          templateId: c.templateId,
          minutes: c.minutes,
          gap: c.gapMinutes,
          tx: c.txTemplateIds,
        ),
      );
    }
    x.tx.addAll(e.txTemplateIds);
    x.open = !e.isEmpty;
    return x;
  }

  final List<_Comp> prev = [];
  final List<_Comp> next = [];
  final List<String> tx = [];
  bool open = false;

  int get count => prev.length + next.length + tx.length;

  PlanExtras toExtras() => PlanExtras(
    prev: [for (final c in prev) c.toCompanion()],
    next: [for (final c in next) c.toCompanion()],
    txTemplateIds: [...tx],
  );

  void copyFrom(_Extras o) {
    for (final c in o.prev) {
      prev.add(c.copy());
    }
    for (final c in o.next) {
      next.add(c.copy());
    }
    tx.addAll(o.tx);
    open = o.open;
  }

  void dispose() {
    for (final c in [...prev, ...next]) {
      c.dispose();
    }
  }
}

class _OccRow extends _Extras {
  _OccRow({
    this.day = 0,
    this.startMin = 9 * 60,
    int? durationMin,
    String? name,
    this.templateId,
    this.allDay = false,
  }) : name = TextEditingController(text: name ?? ''),
       duration = TextEditingController(
         text: durationMin == null ? '' : '$durationMin',
       );

  int day;
  int startMin;
  final String? templateId;

  /// An all-day row: no time, minutes or Previous / Next actions.
  bool allDay;
  final TextEditingController name;
  final TextEditingController duration;

  _OccRow duplicate() {
    final r = _OccRow(
      day: day,
      startMin: startMin,
      durationMin: int.tryParse(duration.text),
      name: name.text,
      templateId: templateId,
      allDay: allDay,
    );
    r.copyFrom(this);
    return r;
  }

  @override
  void dispose() {
    name.dispose();
    duration.dispose();
    super.dispose();
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
    this.initialName,
  });

  /// A name a new item starts with (e.g. the action it is made from).
  final String? initialName;

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
    String? initialName,
    String? initialTemplateId,
  }) => showStackedDialog<String>(
    context: context,
    builder: (_) => PlanItemEditorDialog(
      itemId: itemId,
      initialStart: initialStart,
      initialMinutes: initialMinutes,
      initialName: initialName,
      initialTemplateId: initialTemplateId,
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
  final _monthlyExtras = _Extras();
  MonthlyMode _mode = MonthlyMode.dayOfMonth;
  int _nth = 1;
  int _weekday = DateTime.monday;
  int _monthlyStart = 9 * 60;
  bool _monthlyAllDay = false;
  bool _loaded = false;
  PlanItem? _existing;

  /// The collections the item is in (ids; unknown ones are kept as they were).
  List<String> _collectionIds = [];

  /// The average real duration of the finished runs of this item's template (its
  /// name when it has none), shown next to every Minutes field so a typed length
  /// that differs from it is noticed. Null = no finished run yet.
  Duration? _average;
  int _averageSeq = 0;
  Timer? _averageTimer;

  /// Looks the average up for the current template / name (guarded against an
  /// older answer arriving late).
  Future<void> _refreshAverage() async {
    final seq = ++_averageSeq;
    final service = ref.read(actionServiceProvider);
    final templates = ref.read(templatesProvider).value ?? const [];
    final t = templates.where((x) => x.id == _templateId).firstOrNull;
    final name = (t?.name ?? _name.text).trim();
    final avg = name.isEmpty ? null : await service.templateAverage(name);
    if (!mounted || seq != _averageSeq) return;
    setState(() => _average = avg);
  }

  void _refreshAverageSoon() {
    _averageTimer?.cancel();
    _averageTimer = Timer(
      const Duration(milliseconds: 300),
      _refreshAverage,
    );
  }

  /// 'Average 45 min' (+ how the typed [minutes] compare), or null without an
  /// average.
  Widget? _averageNote(String? minutes, Key key) {
    final avg = _average;
    if (avg == null) return null;
    final avgMin = (avg.inSeconds / 60).round();
    final typed = int.tryParse(minutes ?? '');
    final scheme = Theme.of(context).colorScheme;
    String text = 'Average of finished runs: $avgMin min';
    var differs = false;
    if (typed != null && typed != avgMin) {
      differs = true;
      final d = typed - avgMin;
      text += ' · yours is ${d.abs()} min ${d > 0 ? 'longer' : 'shorter'}';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        text,
        key: key,
        style: TextStyle(
          fontSize: 12,
          color: differs ? scheme.error : scheme.onSurfaceVariant,
        ),
      ),
    );
  }

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
        _collectionIds = [...d.collectionIds];
        if (d.cycle != null) {
          _cycleDays.text = '${d.cycle!.cycleDays}';
          // A weekly pattern shows its rows as weekdays (0 = Monday); stored, a
          // row's day counts from the pattern's start date.
          final weekly = d.cycle!.cycleDays == 7;
          final sw = d.startDate.weekday - 1;
          for (final o in d.cycle!.occurrences) {
            final r = _OccRow(
              day: weekly ? (sw + o.day) % 7 : o.day,
              startMin: o.startMin,
              durationMin: o.durationMin,
              name: o.name,
              templateId: o.templateId,
              allDay: o.allDay,
            );
            r.copyFrom(_Extras.from(o.extras));
            _rows.add(r);
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
          _monthlyAllDay = m.allDay;
          if (m.durationMin != null) _manual.text = '${m.durationMin}';
          _monthlyExtras.copyFrom(_Extras.from(m.extras));
        }
      }
    } else {
      final s = widget.initialStart;
      final mins = widget.initialMinutes;
      _name.text = widget.initialName ?? '';
      _templateId = widget.initialTemplateId;
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
    if (mounted) {
      setState(() => _loaded = true);
      _refreshAverage();
    }
  }

  @override
  void dispose() {
    _averageTimer?.cancel();
    _name.dispose();
    _cycleDays.dispose();
    _everyMonths.dispose();
    _monthDay.dispose();
    _manual.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    _monthlyExtras.dispose();
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

  /// Choosing a template names the item after it when the name is empty or still
  /// the previous template's.
  void _chooseTemplate(String? id, List<ActionTemplate> templates) {
    String? nameOf(String? t) =>
        templates.where((x) => x.id == t).map((x) => x.name).firstOrNull;
    final old = nameOf(_templateId);
    final nu = nameOf(id);
    setState(() {
      final cur = _name.text.trim();
      if (nu != null && (cur.isEmpty || cur == old)) _name.text = nu;
      _templateId = id;
    });
    _refreshAverage();
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
      // The pattern starts on the chosen date; a weekly row's weekday is stored
      // as the number of days after it (so the date is never moved).
      final sw = start.weekday - 1;
      int stored(int day) => n == 7 ? (((day - sw) % 7) + 7) % 7 : day % n;
      cycle = CycleRule(
        cycleDays: n,
        occurrences: [
          for (final r in _rows)
            CycleOccurrence(
              day: stored(r.day),
              startMin: r.startMin,
              durationMin: int.tryParse(r.duration.text),
              name: r.name.text.trim().isEmpty ? null : r.name.text.trim(),
              templateId: r.templateId,
              allDay: r.allDay,
              // An all-day row keeps only its transactions.
              extras: r.allDay
                  ? PlanExtras(txTemplateIds: [...r.tx])
                  : r.toExtras(),
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
        allDay: _monthlyAllDay,
        extras: _monthlyAllDay
            ? PlanExtras(txTemplateIds: [..._monthlyExtras.tx])
            : _monthlyExtras.toExtras(),
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
        collectionIds: _collectionIds,
      ),
    );
    if (nav.mounted) nav.pop(id);
  }

  /// The collections the item belongs to: a chip per collection and
  /// '+ New collection'.
  Widget _collectionChips() {
    final collections =
        ref.watch(planCollectionsProvider).value ?? const <PlanCollection>[];
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Collections', style: Theme.of(context).textTheme.titleSmall),
          for (final c in collections)
            FilterChip(
              key: ValueKey('plan-editor-collection-${c.id}'),
              label: Text(c.name),
              visualDensity: VisualDensity.compact,
              selected: _collectionIds.contains(c.id),
              onSelected: (on) => setState(() {
                on ? _collectionIds.add(c.id) : _collectionIds.remove(c.id);
              }),
            ),
          ActionChip(
            key: const ValueKey('plan-editor-collection-new'),
            avatar: const Icon(Icons.add, size: 16),
            label: const Text('New collection'),
            visualDensity: VisualDensity.compact,
            onPressed: () async {
              final plans = ref.read(planServiceProvider);
              final name = await _askCollectionName(context, null);
              if (name == null || name.isEmpty) return;
              final id = await plans.saveCollection(name: name);
              if (mounted) setState(() => _collectionIds.add(id));
            },
          ),
        ],
      ),
    );
  }

  Widget _timeButton(Key key, int minutes, ValueChanged<int> set) =>
      OutlinedButton(
        key: key,
        onPressed: () => _pickTime(minutes, set),
        child: Text(planTime(minutes)),
      );

  /// A labelled switch: ONLY the switch toggles, not the whole block.
  Widget _switchRow(
    Key key,
    String title,
    String? subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
        Switch(key: key, value: value, onChanged: onChanged),
      ],
    ),
  );

  Widget _cycleSection() {
    final n = _days;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Repeats every'),
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
    final phone = usePhoneLayout(context);
    final day = DropdownButton<int>(
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
    );
    final time = _timeButton(
      ValueKey('plan-row-time-$i'),
      r.startMin,
      (v) => r.startMin = v,
    );
    final allDayChip = FilterChip(
      key: ValueKey('plan-row-allday-$i'),
      label: const Text('All day'),
      visualDensity: VisualDensity.compact,
      selected: r.allDay,
      onSelected: (v) => setState(() => r.allDay = v),
    );
    final minutes = SizedBox(
      width: 104,
      child: TextField(
        key: ValueKey('plan-row-duration-$i'),
        controller: r.duration,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(labelText: 'Minutes', isDense: true),
        onChanged: (_) => setState(() {}),
      ),
    );
    final name = TextField(
      key: ValueKey('plan-row-name-$i'),
      controller: r.name,
      decoration: const InputDecoration(labelText: 'Own name', isDense: true),
    );
    final buttons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: ValueKey('plan-row-duplicate-$i'),
          tooltip: 'Duplicate this time',
          icon: const Icon(Icons.copy_all_outlined, size: 18),
          onPressed: () => setState(() => _rows.insert(i + 1, r.duplicate())),
        ),
        IconButton(
          key: ValueKey('plan-row-remove-$i'),
          tooltip: 'Remove',
          icon: const Icon(Icons.close, size: 18),
          onPressed: () => setState(() => _rows.removeAt(i).dispose()),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (phone) ...[
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [day, allDayChip, if (!r.allDay) ...[time, minutes], buttons],
            ),
            const SizedBox(height: 4),
            name,
          ] else
            Row(
              children: [
                day,
                const SizedBox(width: 10),
                allDayChip,
                if (!r.allDay) ...[
                  const SizedBox(width: 10),
                  time,
                  const SizedBox(width: 10),
                  minutes,
                ],
                const SizedBox(width: 10),
                Expanded(child: name),
                buttons,
              ],
            ),
          if (!r.allDay)
            ?_averageNote(r.duration.text, ValueKey('plan-row-avg-$i')),
          _extrasEditor(r, 'row-$i', allRows: true, companions: !r.allDay),
        ],
      ),
    );
  }

  /// Opens a transaction template for editing (a chip was tapped). A template
  /// is shared by every plan row that uses it, so a change shows in all of them
  /// (transactions already created from it keep their own values).
  Future<void> _editTxTemplate(String id) async {
    final all = ref.read(budgetTxTemplatesProvider).value;
    final t = (all ?? const <BudgetTxTemplate>[])
        .where((x) => x.id == id)
        .firstOrNull;
    if (t == null || !mounted) return;
    await TransactionTemplateDialog.show(context, existing: t);
  }

  static const _editTxTip =
      'Edit this transaction (every plan row that uses it changes)';

  // ---- Previous / Next / Transactions of one row --------------------------------

  Widget _extrasEditor(
    _Extras e,
    String prefix, {
    bool allRows = false,
    bool companions = true,
  }) {
    final names = {
      for (final t
          in ref.watch(budgetTxTemplatesProvider).value ??
              const <BudgetTxTemplate>[])
        t.id: t.name.isEmpty ? 'Transaction' : t.name,
    };
    Widget txChips(List<String> ids, String key) => Wrap(
      spacing: 6,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final id in ids)
          InputChip(
            key: ValueKey('$key-open-$id'),
            label: Text(names[id] ?? 'Deleted template'),
            tooltip: _editTxTip,
            visualDensity: VisualDensity.compact,
            onPressed: () => _editTxTemplate(id),
            onDeleted: () => setState(() => ids.remove(id)),
          ),
        ActionChip(
          key: ValueKey(key),
          avatar: const Icon(Icons.add, size: 16),
          label: const Text('Transaction'),
          visualDensity: VisualDensity.compact,
          onPressed: () async {
            final id = await pickTxTemplate(context, excludeIds: ids.toSet());
            if (id != null && mounted) setState(() => ids.add(id));
          },
        ),
      ],
    );

    Widget column(String title, List<_Comp> list, String key) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              IconButton(
                key: ValueKey('$prefix-add-$key'),
                tooltip: 'Add a $key action',
                icon: const Icon(Icons.add, size: 18),
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => list.add(_Comp())),
              ),
            ],
          ),
          for (var j = 0; j < list.length; j++)
            _compEditor(list[j], '$prefix-$key-$j', () {
              setState(() => list.removeAt(j).dispose());
            }),
        ],
      );
    }

    final phone = usePhoneLayout(context);
    final prev = column('Previous', e.prev, 'prev');
    final next = column('Next', e.next, 'next');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: ValueKey('$prefix-extras-toggle'),
            icon: Icon(
              e.open ? Icons.expand_less : Icons.expand_more,
              size: 18,
            ),
            label: Text(() {
              final title = companions
                  ? 'Previous / Next / Transactions'
                  : 'Transactions';
              final n = companions ? e.count : e.tx.length;
              return n == 0 ? title : '$title ($n)';
            }()),
            onPressed: () => setState(() => e.open = !e.open),
          ),
        ),
        if (e.open)
          SectionBlock(
            key: ValueKey('$prefix-extras'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Transactions',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (allRows && _rows.length > 1)
                      TextButton(
                        key: ValueKey('$prefix-tx-all'),
                        onPressed: () => setState(() {
                          for (final o in _rows) {
                            if (identical(o, e)) continue;
                            o.tx
                              ..clear()
                              ..addAll(e.tx);
                          }
                        }),
                        child: const Text('Same for all times'),
                      ),
                  ],
                ),
                txChips(e.tx, '$prefix-tx-add'),
                if (companions) ...[
                  const SizedBox(height: 8),
                  if (phone) ...[
                    prev,
                    const SizedBox(height: 8),
                    next,
                  ] else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: prev),
                        const SizedBox(width: 16),
                        Expanded(child: next),
                      ],
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _compEditor(_Comp c, String key, VoidCallback onRemove) {
    final templates =
        ref.watch(templatesProvider).value ?? const <ActionTemplate>[];
    final names = {
      for (final t
          in ref.watch(budgetTxTemplatesProvider).value ??
              const <BudgetTxTemplate>[])
        t.id: t.name.isEmpty ? 'Transaction' : t.name,
    };
    return Container(
      key: ValueKey(key),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 6),
      decoration: BoxDecoration(
        border: Border.all(color: context.glass.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButton<String?>(
                  key: ValueKey('$key-template'),
                  isExpanded: true,
                  isDense: true,
                  value: templates.any((t) => t.id == c.templateId)
                      ? c.templateId
                      : null,
                  dropdownColor: context.glassFillDialog,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('No template'),
                    ),
                    for (final t in templates)
                      DropdownMenuItem<String?>(
                        value: t.id,
                        child: Text(t.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    c.templateId = v;
                    final t = templates.where((x) => x.id == v).firstOrNull;
                    if (t != null && c.name.text.trim().isEmpty) {
                      c.name.text = t.name;
                    }
                  }),
                ),
              ),
              _EditTemplateButton(
                key: ValueKey('$key-template-edit'),
                template: templates
                    .where((t) => t.id == c.templateId)
                    .firstOrNull,
              ),
              IconButton(
                key: ValueKey('$key-remove'),
                tooltip: 'Remove',
                icon: const Icon(Icons.close, size: 18),
                visualDensity: VisualDensity.compact,
                onPressed: onRemove,
              ),
            ],
          ),
          TextField(
            key: ValueKey('$key-name'),
            controller: c.name,
            decoration: const InputDecoration(labelText: 'Name', isDense: true),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: ValueKey('$key-minutes'),
                  controller: c.minutes,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Minutes',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: ValueKey('$key-gap'),
                  controller: c.gap,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Gap (min)',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final id in c.tx)
                InputChip(
                  key: ValueKey('$key-tx-open-$id'),
                  label: Text(names[id] ?? 'Deleted template'),
                  tooltip: _editTxTip,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _editTxTemplate(id),
                  onDeleted: () => setState(() => c.tx.remove(id)),
                ),
              ActionChip(
                key: ValueKey('$key-tx-add'),
                avatar: const Icon(Icons.add, size: 16),
                label: const Text('Transaction'),
                visualDensity: VisualDensity.compact,
                onPressed: () async {
                  final id = await pickTxTemplate(
                    context,
                    excludeIds: c.tx.toSet(),
                  );
                  if (id != null && mounted) setState(() => c.tx.add(id));
                },
              ),
            ],
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
            FilterChip(
              key: const ValueKey('plan-monthly-allday'),
              label: const Text('All day'),
              visualDensity: VisualDensity.compact,
              selected: _monthlyAllDay,
              onSelected: (v) => setState(() => _monthlyAllDay = v),
            ),
            if (!_monthlyAllDay)
              _timeButton(
                const ValueKey('plan-monthly-time'),
                _monthlyStart,
                (v) => _monthlyStart = v,
              ),
            if (!_monthlyAllDay)
              SizedBox(
              width: 104,
              child: TextField(
                key: const ValueKey('plan-monthly-duration'),
                controller: _manual,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Minutes',
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        if (!_monthlyAllDay)
          ?_averageNote(_manual.text, const ValueKey('plan-monthly-avg')),
        _extrasEditor(
          _monthlyExtras,
          'monthly',
          companions: !_monthlyAllDay,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final templates =
        ref.watch(templatesProvider).value ?? const <ActionTemplate>[];
    final isNew = widget.itemId == null;
    final selected = templates.where((t) => t.id == _templateId).firstOrNull;
    final showUseName =
        selected != null && selected.name.trim() != _name.text.trim();
    return AlertDialog(
      title: Text(isNew ? 'New plan item' : 'Edit plan item'),
      content: SizedBox(
        width: dialogWidth(context, 640),
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
                      onChanged: (_) {
                        setState(() {});
                        _refreshAverageSoon();
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButton<String?>(
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
                      onChanged: (v) => _chooseTemplate(v, templates),
                          ),
                        ),
                        _EditTemplateButton(
                          key: const ValueKey('plan-template-edit'),
                          template: selected,
                        ),
                      ],
                    ),
                    // Like "Use the category's name" on a transaction.
                    if (showUseName)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          key: const ValueKey('plan-name-from-template'),
                          icon: const Icon(
                            Icons.subdirectory_arrow_left,
                            size: 16,
                          ),
                          label: Text('Use "${selected.name}" as the name'),
                          onPressed: () =>
                              setState(() => _name.text = selected.name),
                        ),
                      ),
                    _collectionChips(),
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
                    const SizedBox(height: 18),
                    _switchRow(
                      const ValueKey('plan-forever'),
                      'Keep creating actions (forever)',
                      'The next 8 weeks are filled in automatically.',
                      _forever,
                      (v) => setState(() => _forever = v),
                    ),
                    if (!isNew)
                      _switchRow(
                        const ValueKey('plan-paused'),
                        'Paused',
                        null,
                        _paused,
                        (v) => setState(() => _paused = v),
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

// ---- collections ----------------------------------------------------------------

/// Asks for a collection's name ([initial] null = a new one). Null = cancelled.
Future<String?> _askCollectionName(BuildContext context, String? initial) {
  final controller = TextEditingController(text: initial ?? '');
  return showStackedDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(initial == null ? 'New collection' : 'Rename collection'),
      content: TextField(
        key: const ValueKey('plan-collection-name'),
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('plan-collection-name-save'),
          onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

/// The plan collections: tick the ones whose ghost blocks planning mode shows,
/// create / rename / delete them.
class PlanCollectionsDialog extends ConsumerWidget {
  const PlanCollectionsDialog({super.key});

  static Future<void> show(BuildContext context) => showStackedDialog<void>(
    context: context,
    builder: (_) => const PlanCollectionsDialog(),
  );

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    PlanCollection c,
  ) async {
    final plans = ref.read(planServiceProvider);
    final overlay = rootOverlayOf(context);
    final history = ref.read(undoHistoryProvider.notifier);
    final undo = await plans.deleteCollection(c.id);
    if (undo == null) return;
    offerUndo(
      overlay,
      history,
      'Deleted collection "${c.name}"',
      () => plans.undoDeleteCollection(undo),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.read(planServiceProvider);
    final collections =
        ref.watch(planCollectionsProvider).value ?? const <PlanCollection>[];
    final items = ref.watch(planItemsProvider).value ?? const <PlanItem>[];
    int count(String id) => items
        .where((r) => decodeCollectionIds(r.collections).contains(id))
        .length;
    return AlertDialog(
      title: const Text('Collections'),
      content: SizedBox(
        width: dialogWidth(context, 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tick the collections to show on the calendar. Items that are '
                'in no collection are always shown.',
              ),
              const SizedBox(height: 6),
              Material(
                type: MaterialType.transparency,
                child: Column(
                  children: [
                    if (collections.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('No collections yet.'),
                      ),
                    for (final c in collections)
                      CheckboxListTile(
                        key: ValueKey('plan-collection-${c.id}'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: c.visible,
                        onChanged: (v) =>
                            plans.setCollectionVisible(c.id, v == true),
                        title: Text('${c.name} (${count(c.id)})'),
                        secondary: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              key: ValueKey('plan-collection-rename-${c.id}'),
                              tooltip: 'Rename',
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              onPressed: () async {
                                final name = await _askCollectionName(
                                  context,
                                  c.name,
                                );
                                if (name != null && name.isNotEmpty) {
                                  await plans.saveCollection(
                                    id: c.id,
                                    name: name,
                                  );
                                }
                              },
                            ),
                            IconButton(
                              key: ValueKey('plan-collection-delete-${c.id}'),
                              tooltip: 'Delete (its items stay)',
                              icon: const Icon(Icons.delete_outline, size: 18),
                              onPressed: () => _delete(context, ref, c),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    key: const ValueKey('plan-collection-add'),
                    icon: const Icon(Icons.add),
                    label: const Text('New collection'),
                    onPressed: () async {
                      final name = await _askCollectionName(context, null);
                      if (name != null && name.isNotEmpty) {
                        await plans.saveCollection(name: name);
                      }
                    },
                  ),
                  if (collections.isNotEmpty) ...[
                    TextButton(
                      key: const ValueKey('plan-collections-show-all'),
                      onPressed: () => plans.setAllCollectionsVisible(true),
                      child: const Text('Show all'),
                    ),
                    TextButton(
                      key: const ValueKey('plan-collections-hide-all'),
                      onPressed: () => plans.setAllCollectionsVisible(false),
                      child: const Text('Hide all'),
                    ),
                  ],
                ],
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

/// A pencil that opens the editor of the chosen template (greyed out when the
/// item uses none). The template list refreshes by itself after a save.
class _EditTemplateButton extends StatelessWidget {
  const _EditTemplateButton({super.key, required this.template});
  final ActionTemplate? template;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Edit this template',
    icon: const Icon(Icons.edit_outlined, size: 18),
    visualDensity: VisualDensity.compact,
    onPressed: template == null
        ? null
        : () => TemplatesScreen.showEditTemplate(context, template!),
  );
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
  int _extraActions = 0;
  int _transactions = 0;
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
    var extra = 0, tx = 0;
    for (final o in p.toCreate) {
      extra += o.extras.prev.length + o.extras.next.length;
      tx += o.extras.txTemplateIds.length;
      for (final c in [...o.extras.prev, ...o.extras.next]) {
        tx += c.txTemplateIds.length;
      }
    }
    setState(() {
      _toCreate = p.toCreate.length;
      _extraActions = extra;
      _transactions = tx;
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

  bool _isOn(String id) => _selected == null || _selected!.contains(id);

  void _selectAll(List<PlanItem> items) {
    setState(() => _selected = null);
    _refresh();
  }

  void _selectNone() {
    setState(() => _selected = <String>{});
    _refresh();
  }

  /// Ticks / unticks every id in [ids].
  void _setOn(Iterable<String> ids, bool on, List<PlanItem> all) {
    final cur = {..._selected ?? {for (final i in all) i.id}};
    on ? cur.addAll(ids) : cur.removeAll(ids);
    setState(
      () => _selected = cur.length == all.length ? null : cur,
    );
    _refresh();
  }

  /// The item checkboxes. With collections they are grouped: a tri-state header
  /// per collection ticks all its items, items in no (existing) collection come
  /// last under 'No collection'; an item in two collections shows under both and
  /// shares one state.
  List<Widget> _itemChecklist(List<PlanItem> items) {
    final collections =
        ref.watch(planCollectionsProvider).value ?? const <PlanCollection>[];
    Widget itemTile(PlanItem r, String key, {double indent = 0}) =>
        CheckboxListTile(
          key: ValueKey(key),
          dense: true,
          contentPadding: EdgeInsets.only(left: indent),
          title: Text(r.name),
          value: _isOn(r.id),
          onChanged: (v) => _setOn([r.id], v == true, items),
        );
    if (collections.isEmpty) {
      return [for (final r in items) itemTile(r, 'plan-confirm-item-${r.id}')];
    }
    final members = <String, List<PlanItem>>{
      for (final c in collections) c.id: [],
    };
    final loose = <PlanItem>[];
    for (final r in items) {
      final mine = [
        for (final c in decodeCollectionIds(r.collections))
          if (members.containsKey(c)) c,
      ];
      if (mine.isEmpty) {
        loose.add(r);
      } else {
        for (final c in mine) {
          members[c]!.add(r);
        }
      }
    }
    final shown = <String>{};
    Widget header(String key, String title, List<PlanItem> group) {
      final on = group.where((r) => _isOn(r.id)).length;
      return CheckboxListTile(
        key: ValueKey(key),
        dense: true,
        contentPadding: EdgeInsets.zero,
        tristate: true,
        title: Text(
          '$title (${group.length})',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        value: group.isEmpty || on == 0 ? false : (on == group.length ? true : null),
        onChanged: group.isEmpty
            ? null
            : (_) => _setOn([for (final r in group) r.id], on != group.length, items),
      );
    }

    List<Widget> group(String key, String title, List<PlanItem> list) => [
      header(key, title, list),
      for (final r in list)
        itemTile(
          r,
          shown.add(r.id)
              ? 'plan-confirm-item-${r.id}'
              : 'plan-confirm-item-${r.id}@$key',
          indent: 20,
        ),
    ];
    return [
      for (final c in collections)
        ...group('plan-confirm-collection-${c.id}', c.name, members[c.id]!),
      if (loose.isNotEmpty)
        ...group('plan-confirm-collection-none', 'No collection', loose),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(planItemsProvider).value ?? const <PlanItem>[];
    return AlertDialog(
      title: const Text('Confirm plan'),
      content: SizedBox(
        width: dialogWidth(context, 460),
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
              Row(
                children: [
                  const Expanded(child: Text('Plan items')),
                  TextButton(
                    key: const ValueKey('plan-confirm-all'),
                    onPressed: items.isEmpty ? null : () => _selectAll(items),
                    child: const Text('Select all'),
                  ),
                  TextButton(
                    key: const ValueKey('plan-confirm-none'),
                    onPressed: items.isEmpty ? null : _selectNone,
                    child: const Text('None'),
                  ),
                ],
              ),
              ..._itemChecklist(items),
              const SizedBox(height: 8),
              Text(
                _toCreate == null
                    ? '...'
                    : '$_toCreate action(s) to create'
                          '${_extraActions > 0 ? ' + $_extraActions previous/next' : ''}'
                          '${_transactions > 0 ? ', $_transactions transaction(s)' : ''}'
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
          onPressed: _busy || items.isEmpty || (_selected?.isEmpty ?? false)
              ? null
              : _confirm,
          child: const Text('Create actions'),
        ),
      ],
    );
  }
}

// ---- plan items list ----------------------------------------------------------

/// The names of the collections of [r] that still exist.
List<String> _collectionNameList(PlanItem r, List<PlanCollection> collections) {
  final ids = decodeCollectionIds(r.collections);
  return [
    for (final c in collections)
      if (ids.contains(c.id)) c.name,
  ];
}

/// ' · Sport, Gym' for the collections of [r] that still exist ('' = none).
String _collectionNames(PlanItem r, List<PlanCollection> collections) {
  final names = _collectionNameList(r, collections);
  return names.isEmpty ? '' : ' · ${names.join(', ')}';
}

class PlanItemsDialog extends ConsumerStatefulWidget {
  const PlanItemsDialog({super.key});

  static Future<void> show(BuildContext context) => showStackedDialog<void>(
    context: context,
    builder: (_) => const PlanItemsDialog(),
  );

  @override
  ConsumerState<PlanItemsDialog> createState() => _PlanItemsDialogState();
}

class _PlanItemsDialogState extends ConsumerState<PlanItemsDialog>
    with SearchTargetState<PlanItemsDialog> {
  String _query = '';
  final _searchText = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    registerSearchTarget();
  }

  // Ctrl+F: focus the search field and select its text.
  @override
  void openSearch() => focusSearchField(_searchFocus, _searchText);

  @override
  void dispose() {
    unregisterSearchTarget();
    _searchText.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    PlanItem item,
  ) => askAndDeletePlanItem(context, ref, item.id, item.name);

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
  Widget build(BuildContext context) {
    final items = ref.watch(planItemsProvider).value ?? const <PlanItem>[];
    final collections =
        ref.watch(planCollectionsProvider).value ?? const <PlanCollection>[];
    final plans = ref.read(planServiceProvider);
    final shown = [
      for (final r in items)
        if (planItemMatchesSearch(
          _query,
          name: r.name,
          description: describePlan(plans.decode(r)),
          collectionNames: _collectionNameList(r, collections),
        ))
          r,
    ];
    return AlertDialog(
      title: const Text('Plan items'),
      content: SizedBox(
        width: dialogWidth(context, 480),
        child: items.isEmpty
            ? const Text('Nothing planned yet. Sweep a time on the calendar.')
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      key: const ValueKey('plan-items-search'),
                      controller: _searchText,
                      focusNode: _searchFocus,
                      decoration: const InputDecoration(
                        hintText: 'Search by name or collection',
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                    const SizedBox(height: 8),
                    if (shown.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'No plan item matches.',
                          key: ValueKey('plan-items-no-match'),
                        ),
                      ),
                    for (final r in shown)
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
                          '${r.paused ? ' · paused' : ''}'
                          '${_collectionNames(r, collections)}',
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
