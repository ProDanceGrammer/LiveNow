import 'package:flutter/cupertino.dart'
    show
        CupertinoDatePicker,
        CupertinoDatePickerMode,
        CupertinoTextThemeData,
        CupertinoTheme,
        CupertinoThemeData;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../../domain/action_service.dart' show ScheduleChange;
import '../../domain/time_edit_math.dart';
import '../dialog_stack.dart';
import '../layout.dart';
import '../time_format.dart';
import '../undo.dart';

/// What [QuickTimeEditDialog] hands back (UTC instants, null = not set).
class TimeEditResult {
  final DateTime? start;
  final DateTime? end;
  const TimeEditResult({this.start, this.end});
}

/// The one calendar-style editor for an action's start/end, opened from
/// cards, list tiles and the action editor's date fields (never from calendar
/// blocks). Keyboard: digits type into the focused segment, Ctrl+Up/Down
/// +/- 1 of it (with carry), Left/Right move hours <-> minutes <-> day <->
/// month <-> year, plain Down jumps to the End row (Up back to Start), Enter
/// saves, Esc cancels. The cursor starts on the Start minutes (the day for
/// all-day actions).
///
/// Segment keys: `time-start-minute`, `time-end-day`, ... (`time-<row>-<unit>`).
class QuickTimeEditDialog extends StatefulWidget {
  final DateTime? initialStart;
  final DateTime? initialEnd;
  final bool isAllDay;

  /// False for a single-value field (the editor's Start / End rows).
  final bool showEnd;
  final String title;

  const QuickTimeEditDialog({
    super.key,
    this.initialStart,
    this.initialEnd,
    this.isAllDay = false,
    this.showEnd = true,
    this.title = 'Edit time',
  });

  /// Opens the dialog and returns the chosen values without saving anything
  /// (null when cancelled).
  static Future<TimeEditResult?> pick(
    BuildContext context, {
    DateTime? start,
    DateTime? end,
    bool isAllDay = false,
    bool showEnd = true,
    String title = 'Edit time',
  }) {
    return showStackedDialog<TimeEditResult>(
      context: context,
      builder: (_) => QuickTimeEditDialog(
        initialStart: start,
        initialEnd: end,
        isAllDay: isAllDay,
        showEnd: showEnd,
        title: title,
      ),
    );
  }

  /// Edits [action]'s schedule and saves it through [runUndoableMoveMany]
  /// (Undo snackbar + Ctrl+Z).
  static Future<void> editAction(
    BuildContext context,
    WidgetRef ref,
    ActionListItem action,
  ) async {
    final result = await pick(
      context,
      start: action.startAt,
      end: action.endAt,
      isAllDay: action.isAllDay,
    );
    if (result == null || !context.mounted) return;
    if (result.start == action.startAt && result.end == action.endAt) return;
    await runUndoableMoveMany(context, ref, [
      ScheduleChange(action.id, startAt: result.start, endAt: result.end),
    ], description: 'Time changed');
  }

  @override
  State<QuickTimeEditDialog> createState() => _QuickTimeEditDialogState();
}

class _QuickTimeEditDialogState extends State<QuickTimeEditDialog> {
  late DateTime _start; // wall values
  DateTime? _end;
  bool _onEnd = false;
  // True once the END itself was edited (then it is saved as typed); until
  // then it only follows the start and keeps its exact length, seconds too.
  bool _endEdited = false;
  late TimeUnit _unit;
  String _typed = '';

  List<TimeUnit> get _order => widget.isAllDay ? dateUnitOrder : timedUnitOrder;

  DateTime _normalize(DateTime w) => widget.isAllDay ? dateOnly(w) : w;

  @override
  void initState() {
    super.initState();
    _start = _normalize(
      wallFromUtc(widget.initialStart ?? DateTime.now().toUtc()),
    );
    _end = widget.showEnd && widget.initialEnd != null
        ? _normalize(wallFromUtc(widget.initialEnd!))
        : null;
    _unit = widget.isAllDay ? TimeUnit.day : TimeUnit.minute;
  }

  DateTime get _current => _onEnd ? _end! : _start;

  void _setCurrent(DateTime v) {
    if (_onEnd) {
      _endEdited = true;
      _end = _normalize(v);
    } else {
      final old = _start;
      _start = _normalize(v);
      // The length stays: moving the start carries the end along.
      final end = _end;
      if (end != null && !widget.isAllDay) {
        _end = end.add(_start.difference(old));
      }
    }
  }

  String? get _error {
    final e = _end;
    if (e != null && e.isBefore(_start)) return 'End is before start';
    return null;
  }

  DateTime _defaultEnd() =>
      _normalize(widget.isAllDay ? _start : addUnit(_start, TimeUnit.hour, 1));

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;

    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _save();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      setState(() {
        _unit = stepUnit(
          _order,
          _unit,
          key == LogicalKeyboardKey.arrowLeft ? -1 : 1,
        );
        _typed = '';
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      final up = key == LogicalKeyboardKey.arrowUp;
      setState(() {
        _typed = '';
        if (ctrl) {
          _setCurrent(addUnit(_current, _unit, up ? 1 : -1));
        } else if (!up && widget.showEnd) {
          _end ??= _defaultEnd();
          _onEnd = true;
        } else if (up) {
          _onEnd = false;
        }
      });
      return KeyEventResult.handled;
    }
    final ch = event.character;
    if (!ctrl && ch != null && ch.length == 1 && '0123456789'.contains(ch)) {
      _typeDigit(ch);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _typeDigit(String digit) {
    final width = _unit == TimeUnit.year ? 4 : 2;
    setState(() {
      _typed = _typed.length >= width ? digit : _typed + digit;
      _setCurrent(setUnit(_current, _unit, int.parse(_typed)));
    });
  }

  void _focusSegment(bool onEnd, TimeUnit unit) {
    setState(() {
      _onEnd = onEnd;
      _unit = unit;
      _typed = '';
    });
  }

  /// Calendar popup for the row's DATE; the time of day stays.
  Future<void> _pickDate(bool onEnd, DateTime value) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: dateOnly(value),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _onEnd = onEnd;
      _typed = '';
      _setCurrent(
        DateTime(
          picked.year,
          picked.month,
          picked.day,
          value.hour,
          value.minute,
          value.second,
        ),
      );
    });
  }

  void _save() {
    if (_error != null) return;
    DateTime back(DateTime wall, DateTime? initial) {
      // Keep the original instant (seconds and all) when nothing changed.
      if (initial != null && _normalize(wallFromUtc(initial)) == wall) {
        return initial;
      }
      return utcFromWall(wall);
    }

    final start = back(_start, widget.initialStart);
    DateTime? end;
    if (_end != null) {
      final iStart = widget.initialStart;
      final iEnd = widget.initialEnd;
      end = (!_endEdited && !widget.isAllDay && iStart != null && iEnd != null)
          // Only the start moved: same length to the second.
          ? iEnd.add(start.difference(iStart))
          : back(_end!, widget.initialEnd);
    }
    Navigator.of(context).pop(TimeEditResult(start: start, end: end));
  }

  String _fmtWall(DateTime w) {
    return formatDateTime(w, includeTime: !widget.isAllDay);
  }

  /// Phone: no keyboard segments - a Start/End switch and one Cupertino wheel
  /// that edits whichever row is chosen (hour/minute/date wheels, scrolled by
  /// finger).
  Widget _phoneBody(String? error) {
    final theme = Theme.of(context);
    Widget chip(String label, bool isEnd, DateTime? value) {
      final selected = _onEnd == isEnd;
      return Expanded(
        child: InkWell(
          key: ValueKey('time-chip-${isEnd ? 'end' : 'start'}'),
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() {
            if (isEnd) _end ??= _defaultEnd();
            _onEnd = isEnd;
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            decoration: BoxDecoration(
              color: selected
                  ? theme.colorScheme.primary.withValues(alpha: 0.22)
                  : null,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
              ),
            ),
            child: Column(
              children: [
                Text(label, style: theme.textTheme.labelSmall),
                Text(
                  value == null ? 'Not set' : _fmtWall(value),
                  style: theme.textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            chip('Start', false, _start),
            if (widget.showEnd) ...[
              const SizedBox(width: 8),
              chip('End', true, _end),
            ],
          ],
        ),
        if (widget.showEnd && _end != null && _onEnd)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const ValueKey('time-end-clear'),
              onPressed: () => setState(() {
                _end = null;
                _onEnd = false;
              }),
              child: const Text('Clear end'),
            ),
          ),
        SizedBox(
          height: 200,
          child: CupertinoTheme(
            data: CupertinoThemeData(
              brightness: theme.brightness,
              textTheme: CupertinoTextThemeData(
                dateTimePickerTextStyle: TextStyle(
                  fontSize: 20,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            child: CupertinoDatePicker(
              // A new picker per row so the wheels jump to that row's value.
              key: ValueKey('time-wheel-${_onEnd ? 'end' : 'start'}'),
              mode: widget.isAllDay
                  ? CupertinoDatePickerMode.date
                  : CupertinoDatePickerMode.dateAndTime,
              use24hFormat: true,
              initialDateTime: _current,
              minimumYear: 2000,
              maximumYear: 2100,
              onDateTimeChanged: (v) => setState(() => _setCurrent(v)),
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              error,
              key: const ValueKey('time-error'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (usePhoneLayout(context)) {
      return AlertDialog(
        title: Text(widget.title),
        content: SizedBox(width: 400, child: _phoneBody(error)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('time-save'),
            onPressed: error == null ? _save : null,
            child: const Text('Save'),
          ),
        ],
      );
    }
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row('Start', false, _start),
              if (widget.showEnd) ...[
                const SizedBox(height: 8),
                _row('End', true, _end),
              ],
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error,
                    key: const ValueKey('time-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                'Ctrl+Up/Down change  ·  Left/Right move  ·  Down: end, Up: start  ·  Enter saves',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: error == null ? _save : null,
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, bool isEnd, DateTime? value) {
    final theme = Theme.of(context);
    final rowName = isEnd ? 'end' : 'start';
    return Row(
      children: [
        SizedBox(width: 48, child: Text(label)),
        if (value == null)
          TextButton(
            key: const ValueKey('time-end-set'),
            onPressed: () => setState(() {
              _end = _defaultEnd();
              _onEnd = true;
            }),
            child: const Text('Not set - set'),
          )
        else ...[
          for (final unit in _order) ...[
            _segment(rowName, isEnd, unit, value, theme),
            if (unit == TimeUnit.hour) const Text(':'),
            if (unit == TimeUnit.day || unit == TimeUnit.month) const Text('/'),
            if (unit == TimeUnit.minute) const SizedBox(width: 12),
          ],
          IconButton(
            key: ValueKey('time-$rowName-calendar'),
            icon: const Icon(Icons.calendar_month, size: 18),
            tooltip: 'Pick date',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            onPressed: () => _pickDate(isEnd, value),
          ),
          if (isEnd)
            IconButton(
              key: const ValueKey('time-end-clear'),
              icon: const Icon(Icons.clear, size: 18),
              tooltip: 'Clear end',
              onPressed: () => setState(() {
                _end = null;
                _onEnd = false;
              }),
            ),
        ],
      ],
    );
  }

  Widget _segment(
    String rowName,
    bool isEnd,
    TimeUnit unit,
    DateTime value,
    ThemeData theme,
  ) {
    final selected = _onEnd == isEnd && _unit == unit;
    final v = unitValue(value, unit);
    final text = unit == TimeUnit.year
        ? v.toString().padLeft(4, '0')
        : twoDigits(v);
    return GestureDetector(
      onTap: () => _focusSegment(isEnd, unit),
      child: Container(
        key: ValueKey('time-$rowName-${unit.name}'),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.25)
              : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          style: theme.textTheme.titleMedium?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
