import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../../domain/action_service.dart' show ScheduleChange;
import '../../domain/time_edit_math.dart';
import '../dialog_stack.dart';
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
      _end = _normalize(v);
    } else {
      _start = _normalize(v);
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

  void _save() {
    if (_error != null) return;
    DateTime back(DateTime wall, DateTime? initial) {
      // Keep the original instant (seconds and all) when nothing changed.
      if (initial != null && _normalize(wallFromUtc(initial)) == wall) {
        return initial;
      }
      return utcFromWall(wall);
    }

    Navigator.of(context).pop(
      TimeEditResult(
        start: back(_start, widget.initialStart),
        end: _end == null ? null : back(_end!, widget.initialEnd),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 400,
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
