import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart'
    show
        DragStartBehavior,
        GestureBinding,
        PointerScrollEvent,
        PointerSignalEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show HardwareKeyboard, LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/settings.dart';
import '../../data/queries.dart';
import '../../domain/action_service.dart';
import '../../domain/duration_rules.dart';
import '../../domain/postpone_rules.dart';
import '../edit_action.dart';
import '../providers.dart';
import '../undo.dart';
import '../urgency_colors.dart';
import '../widgets/action_editor.dart';
import '../widgets/action_tile.dart';
import 'calendar_layout.dart';

const double _kGutter = 56;
const double _kHandle = 6;

/// A block is never drawn shorter than this, however far the grid is zoomed
/// out, so a 10-minute event stays easy to grab.
const double _kMinBlockHeight = 8;
const double _kToolbarWidth = 165;
const double _kToolbarHeight = 24;

/// The smallest hour height the grid is drawn with, so a tiny window at the
/// 24-hour zoom stays usable (the grid then scrolls a little).
const double _kMinHourHeight = 12;

const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

tz.TZDateTime _local(DateTime utc) =>
    tz.TZDateTime.from(utc, tz.getLocation(AppSettings.timeZoneName));

String _hhmm(DateTime utc) {
  final l = _local(utc);
  return '${twoDigits(l.hour)}:${twoDigits(l.minute)}';
}

/// End of [a] as drawn: never shorter than the minimum block (10 min).
DateTime _effectiveEnd(ActionListItem a) {
  final start = a.startAt!;
  final d = computeActionDuration(
    startAt: start,
    endAt: a.endAt,
    legacyEstimatedMinutes: a.estimatedMinutes,
  );
  const min = Duration(minutes: kMinDurationMinutes);
  return start.add(d < min ? min : d);
}

/// The Google-Calendar-style time grid: a header (navigation + 2..7 day
/// selector), a day header row, an all-day strip and a scrolling 24 h grid
/// where timed actions can be dragged (move) and edge-dragged (resize).
class CalendarView extends ConsumerWidget {
  const CalendarView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final start = ref.watch(calendarRangeStartProvider);
    final dayCount = ref.watch(calendarDayCountProvider);
    final items = ref.watch(calendarRangeProvider).value;
    final running =
        ref.watch(runningOccurrencesProvider).value ?? const <String>{};

    return _CalendarInput(
      child: Column(
        children: [
          _Header(start: start, dayCount: dayCount),
          const Divider(height: 1),
          Expanded(
            child: items == null
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(
                    builder: (context, box) {
                      final dayW = (box.maxWidth - _kGutter) / dayCount;
                      return Column(
                        children: [
                          _DayHeaderRow(
                            start: start,
                            dayCount: dayCount,
                            dayWidth: dayW,
                          ),
                          _AllDayStrip(
                            start: start,
                            dayCount: dayCount,
                            dayWidth: dayW,
                            items: items,
                            running: running,
                          ),
                          Expanded(
                            child: _TimeGrid(
                              start: start,
                              dayCount: dayCount,
                              dayWidth: dayW,
                              items: items,
                              running: running,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Keyboard and wheel navigation for the whole calendar: Left/Right arrows
/// and Shift+scroll move the range one day at a time, Delete removes the
/// selected event (after confirming). The wrapper owns focus, and takes it
/// back on any click inside the calendar so the keys keep working after a
/// dialog or a header button had it.
class _CalendarInput extends ConsumerStatefulWidget {
  final Widget child;

  const _CalendarInput({required this.child});

  @override
  ConsumerState<_CalendarInput> createState() => _CalendarInputState();
}

class _CalendarInputState extends ConsumerState<_CalendarInput> {
  /// Scroll distance that counts as one day: one mouse-wheel notch reports
  /// 100, a touchpad sends many small deltas that accumulate to the same step.
  static const _pixelsPerDay = 100.0;

  final _focus = FocusNode(debugLabel: 'calendar');
  double _scrollAccumulated = 0;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        !HardwareKeyboard.instance.isShiftPressed) {
      return;
    }
    // Some mice report Shift+wheel on the horizontal axis instead.
    final delta = event.scrollDelta.dy != 0
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    _scrollAccumulated += delta;
    final days = (_scrollAccumulated / _pixelsPerDay).truncate();
    if (days == 0) return;
    _scrollAccumulated -= days * _pixelsPerDay;
    shiftCalendarDays(ref, days);
  }

  void _deleteSelected() {
    final id = ref.read(calendarSelectedActionProvider);
    if (id != null) runUndoableDelete(context, ref, id);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) {
        if (!_focus.hasFocus) _focus.requestFocus();
      },
      onPointerSignal: _onPointerSignal,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              shiftCalendarDays(ref, -1),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              shiftCalendarDays(ref, 1),
          const SingleActivator(LogicalKeyboardKey.delete): _deleteSelected,
          // Ctrl + "+" is Ctrl+= on most layouts (with or without Shift),
          // plus the numpad keys.
          const SingleActivator(LogicalKeyboardKey.equal, control: true): () =>
              zoomCalendar(ref, 1),
          const SingleActivator(
            LogicalKeyboardKey.equal,
            control: true,
            shift: true,
          ): () =>
              zoomCalendar(ref, 1),
          const SingleActivator(
            LogicalKeyboardKey.numpadAdd,
            control: true,
          ): () =>
              zoomCalendar(ref, 1),
          const SingleActivator(LogicalKeyboardKey.minus, control: true): () =>
              zoomCalendar(ref, -1),
          const SingleActivator(
            LogicalKeyboardKey.numpadSubtract,
            control: true,
          ): () =>
              zoomCalendar(ref, -1),
        },
        child: Focus(focusNode: _focus, autofocus: true, child: widget.child),
      ),
    );
  }
}

// ---- header ---------------------------------------------------------------

class _Header extends ConsumerWidget {
  final DateTime start;
  final int dayCount;

  const _Header({required this.start, required this.dayCount});

  String _label() {
    final a = _local(start);
    final b = _local(calendarAddDays(start, dayCount - 1));
    final left = '${_monthNames[a.month - 1]} ${a.day}';
    final right = a.month == b.month
        ? '${b.day}'
        : '${_monthNames[b.month - 1]} ${b.day}';
    return '$left – $right, ${b.year}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous',
            onPressed: () => shiftCalendarRange(ref, -1),
          ),
          OutlinedButton(
            onPressed: () => goToCalendarToday(ref),
            child: const Text('Today'),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next',
            onPressed: () => shiftCalendarRange(ref, 1),
          ),
          const SizedBox(width: 8),
          Text(_label(), style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          // Zoom: how many hours of a day are visible at once.
          IconButton(
            icon: const Icon(Icons.zoom_out),
            tooltip: 'Show more hours (Ctrl+−)',
            onPressed: () => zoomCalendar(ref, -1),
          ),
          Text(
            '${ref.watch(calendarVisibleHoursProvider)} h',
            key: const ValueKey('zoom-label'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          IconButton(
            icon: const Icon(Icons.zoom_in),
            tooltip: 'Show fewer hours (Ctrl++)',
            onPressed: () => zoomCalendar(ref, 1),
          ),
          const SizedBox(width: 12),
          SegmentedButton<int>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              for (var n = 2; n <= 7; n++)
                ButtonSegment(value: n, label: Text('$n'), tooltip: '$n days'),
            ],
            selected: {dayCount},
            onSelectionChanged: (s) => setCalendarDayCount(ref, s.first),
          ),
        ],
      ),
    );
  }
}

class _DayHeaderRow extends StatelessWidget {
  final DateTime start;
  final int dayCount;
  final double dayWidth;

  const _DayHeaderRow({
    required this.start,
    required this.dayCount,
    required this.dayWidth,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = dayIndexOf(DateTime.now().toUtc(), start);
    return Container(
      height: 44,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          const SizedBox(width: _kGutter),
          for (var i = 0; i < dayCount; i++)
            Builder(
              builder: (context) {
                final l = _local(calendarAddDays(start, i));
                final isToday = i == today;
                return SizedBox(
                  key: ValueKey('day-header-$i'),
                  width: dayWidth,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _dayNames[l.weekday - 1],
                        style: TextStyle(
                          color: isToday
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                          fontWeight: isToday ? FontWeight.w600 : null,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        constraints: const BoxConstraints(minWidth: 26),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: isToday ? scheme.primary : null,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Text(
                          '${l.day}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isToday
                                ? scheme.onPrimary
                                : scheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

// ---- all-day strip --------------------------------------------------------

class _AllDayStrip extends StatelessWidget {
  final DateTime start;
  final int dayCount;
  final double dayWidth;
  final List<ActionListItem> items;
  final Set<String> running;

  const _AllDayStrip({
    required this.start,
    required this.dayCount,
    required this.dayWidth,
    required this.items,
    required this.running,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final byDay = <int, List<ActionListItem>>{};
    for (final a in items) {
      if (!a.isAllDay || a.startAt == null) continue;
      final d = dayIndexOf(a.startAt!, start);
      if (d >= 0 && d < dayCount) byDay.putIfAbsent(d, () => []).add(a);
    }
    return Container(
      constraints: const BoxConstraints(minHeight: 30, maxHeight: 96),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SingleChildScrollView(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _kGutter,
              child: Padding(
                padding: const EdgeInsets.only(top: 8, left: 6),
                child: Text(
                  'all-day',
                  style: TextStyle(
                    fontSize: 10,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            for (var i = 0; i < dayCount; i++)
              Container(
                width: dayWidth,
                constraints: const BoxConstraints(minHeight: 30),
                padding: const EdgeInsets.fromLTRB(2, 3, 2, 3),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: scheme.outlineVariant),
                  ),
                ),
                child: Column(
                  children: [
                    for (final a in byDay[i] ?? const <ActionListItem>[])
                      _AllDayChip(
                        key: ValueKey('allday-${a.id}'),
                        item: a,
                        running: running.contains(a.id),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AllDayChip extends ConsumerWidget {
  final ActionListItem item;
  final bool running;

  const _AllDayChip({super.key, required this.item, required this.running});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final done = item.isDoneBefore;
    final urgency = done || running
        ? null
        : ref.watch(actionUrgencyProvider.select((m) => m[item.id]));
    final uc = urgency == null
        ? null
        : urgencyColors(
            urgency,
            dark: Theme.of(context).brightness == Brightness.dark,
          );
    final bg = running
        ? scheme.primary
        : done
        ? scheme.surfaceContainerHighest
        : uc?.bg ?? scheme.tertiaryContainer;
    final fg = running
        ? scheme.onPrimary
        : done
        ? scheme.onSurfaceVariant
        : uc?.fg ?? scheme.onTertiaryContainer;
    final selected = ref.watch(
      calendarSelectedActionProvider.select((id) => id == item.id),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: _HoverToolbarHost(
        actionId: item.id,
        child: Material(
          color: bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: selected
                ? BorderSide(color: scheme.onSurface, width: 2)
                : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            // Click selects (so Delete can act on it); double-click edits.
            onTapDown: (_) =>
                ref.read(calendarSelectedActionProvider.notifier).state =
                    item.id,
            onTap: () {},
            onDoubleTap: () => openActionEditor(context, ref, item.id),
            child: Container(
              height: 22,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              alignment: Alignment.centerLeft,
              child: Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: fg,
                  decoration: done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---- hover toolbar --------------------------------------------------------

/// Wraps [child] so hovering it shows a Start / Finish / +7 days toolbar in
/// the root overlay (so it can overflow a tiny block and is never clipped by
/// the scroll view). The toolbar overlaps the child by a few px and hover is
/// the OR of "over child" and "over toolbar", so moving between the two does
/// not flicker.
class _HoverToolbarHost extends ConsumerStatefulWidget {
  final String actionId;
  final bool suppressed;
  final Widget child;

  const _HoverToolbarHost({
    required this.actionId,
    required this.child,
    this.suppressed = false,
  });

  @override
  ConsumerState<_HoverToolbarHost> createState() => _HoverToolbarHostState();
}

class _HoverToolbarHostState extends ConsumerState<_HoverToolbarHost> {
  final _portal = OverlayPortalController();
  bool _overChild = false;
  bool _overBar = false;

  void _sync() {
    if (!mounted) return;
    final show = _overChild || _overBar;
    if (show && !_portal.isShowing) {
      _portal.show();
    } else if (!show && _portal.isShowing) {
      _portal.hide();
    }
  }

  @override
  void didUpdateWidget(_HoverToolbarHost old) {
    super.didUpdateWidget(old);
    if (widget.suppressed) _overBar = false; // its region is being removed
  }

  Future<void> _run(
    String description,
    Future<void> Function(ActionService) op,
  ) => runUndoable(
    context,
    ref,
    widget.actionId,
    description,
    () => op(ref.read(actionServiceProvider)),
  );

  @override
  Widget build(BuildContext context) {
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _portal,
      overlayChildBuilder: (_, info) {
        if (widget.suppressed) return const SizedBox.shrink();
        // Above the child's top-right corner, overlapping it by 3 px so the
        // pointer never crosses a gap between child and toolbar.
        final corner = MatrixUtils.transformPoint(
          info.childPaintTransform,
          Offset(info.childSize.width, 0),
        );
        return Positioned(
          left: math.max(0, corner.dx - _kToolbarWidth),
          top: math.max(0, corner.dy - _kToolbarHeight + 3),
          child: MouseRegion(
            onEnter: (_) {
              _overBar = true;
              _sync();
            },
            onExit: (_) {
              _overBar = false;
              _sync();
            },
            child: _Toolbar(
              onStart: () => _run('Started', (s) => s.start(widget.actionId)),
              onFinish: () =>
                  _run('Finished', (s) => s.finish(widget.actionId)),
              onContinue: () =>
                  runUndoableContinue(context, ref, widget.actionId),
              onWeek: () => _run(
                'Postponed to next week',
                (s) => s.postpone(widget.actionId, PostponeRule.nextWeek),
              ),
              onDelete: () => runUndoableDelete(context, ref, widget.actionId),
            ),
          ),
        );
      },
      child: MouseRegion(
        onEnter: (_) {
          _overChild = true;
          _sync();
        },
        onExit: (_) {
          _overChild = false;
          _sync();
        },
        child: widget.child,
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  final VoidCallback onStart;
  final VoidCallback onFinish;
  final VoidCallback onContinue;
  final VoidCallback onWeek;
  final VoidCallback onDelete;

  const _Toolbar({
    required this.onStart,
    required this.onFinish,
    required this.onContinue,
    required this.onWeek,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 4,
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToolButton('▶️', 'Start', 28, onStart),
          _ToolButton('🏁', 'Finish', 28, onFinish),
          _ToolButton('⏭️', 'Continue with same action', 28, onContinue),
          _ToolButton('7⃣📅', 'Postpone +7 days', 40, onWeek),
          // Kept apart from the everyday buttons so it isn't hit by accident.
          Container(
            width: 1,
            height: 16,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            color: scheme.outlineVariant,
          ),
          Tooltip(
            message: 'Delete',
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: onDelete,
              child: SizedBox(
                width: 28,
                height: 24,
                child: Icon(
                  Icons.delete_outline,
                  size: 16,
                  color: scheme.error,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final String emoji;
  final String tooltip;
  final double width;
  final VoidCallback onTap;

  const _ToolButton(this.emoji, this.tooltip, this.width, this.onTap);

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: SizedBox(
          width: width,
          height: 24,
          child: Center(
            child: Text(emoji, style: const TextStyle(fontSize: 13)),
          ),
        ),
      ),
    );
  }
}

// ---- time grid ------------------------------------------------------------

/// One drawn piece of a timed action on one day column (an action crossing
/// midnight has one segment per day).
class _Seg {
  final ActionListItem item;
  final int day;
  final DateTime start;
  final DateTime end;
  final bool isStart;
  final bool isEnd;

  const _Seg(
    this.item,
    this.day,
    this.start,
    this.end,
    this.isStart,
    this.isEnd,
  );
}

typedef _Placed = LaneAssignment<_Seg>;

enum _DragKind { move, resizeTop, resizeBottom }

class _Drag {
  final _Placed placed;
  final _DragKind kind;
  final Offset origin;
  final Offset current;

  const _Drag(this.placed, this.kind, this.origin, this.current);

  _Drag at(Offset p) => _Drag(placed, kind, origin, p);
}

class _TimeGrid extends ConsumerStatefulWidget {
  final DateTime start;
  final int dayCount;
  final double dayWidth;
  final List<ActionListItem> items;
  final Set<String> running;

  const _TimeGrid({
    required this.start,
    required this.dayCount,
    required this.dayWidth,
    required this.items,
    required this.running,
  });

  @override
  ConsumerState<_TimeGrid> createState() => _TimeGridState();
}

class _TimeGridState extends ConsumerState<_TimeGrid> {
  /// Created on the first build, once the viewport height (and so the hour
  /// height) is known, so the initial "an hour before now" offset is right.
  ScrollController? _scrollController;
  ScrollController get _scroll => _scrollController!;
  Timer? _tick;
  _Drag? _drag;
  _NewRange? _newRange;

  /// Pixels per hour at the current zoom: viewport height / visible hours.
  /// Refreshed on every build; everything vertical is measured with it.
  double _hourHeight = kHourHeight;
  double _viewportHeight = 0;
  double get _pxPerMinute => _hourHeight / 60;
  double _px(num minutes) => minutesToPx(minutes, pxPerMinute: _pxPerMinute);

  /// The viewport y that stays put while zooming (the pointer for Ctrl+wheel);
  /// null means the viewport's centre.
  double? _zoomFocal;

  /// Ctrl+wheel distance not yet worth a zoom step (see [_onWheel]).
  double _wheelAccumulated = 0;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _scrollController?.dispose();
    super.dispose();
  }

  /// Called just before the zoom level changes (so [_hourHeight] is still the
  /// old one): remembers which time sits at the focal point, then after the
  /// next layout scrolls so the same time is still there.
  void _anchorZoom() {
    final controller = _scrollController;
    if (controller == null || !controller.hasClients) return;
    final focal = (_zoomFocal ?? _viewportHeight / 2).clamp(
      0.0,
      _viewportHeight,
    );
    _zoomFocal = null;
    final minuteAtFocal = (controller.offset + focal) / _pxPerMinute;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.hasClients) return;
      final target = minuteAtFocal * _pxPerMinute - focal;
      controller.jumpTo(target.clamp(0.0, controller.position.maxScrollExtent));
    });
  }

  /// Ctrl+wheel zooms (wheel up = in). Registered with the pointer-signal
  /// resolver from *inside* the scroll view, so it wins over the scrollable's
  /// own claim on the same event and the grid doesn't also scroll.
  void _onWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        !HardwareKeyboard.instance.isControlPressed) {
      return;
    }
    final focalInViewport = event.localPosition.dy - _scroll.offset;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      _wheelAccumulated += event.scrollDelta.dy;
      final steps = (_wheelAccumulated / _wheelPixelsPerStep).truncate();
      if (steps == 0) return;
      _wheelAccumulated -= steps * _wheelPixelsPerStep;
      for (var i = 0; i < steps.abs(); i++) {
        _zoomFocal = focalInViewport;
        zoomCalendar(ref, steps < 0 ? 1 : -1);
      }
    });
  }

  /// One mouse-wheel notch reports 100; a touchpad's small deltas add up.
  static const _wheelPixelsPerStep = 100.0;

  List<DateTime> get _dayStarts => [
    for (var i = 0; i <= widget.dayCount; i++) calendarAddDays(widget.start, i),
  ];

  List<_Placed> _layout(List<DateTime> dayStarts) {
    final byDay = <int, List<_Seg>>{};
    for (final a in widget.items) {
      if (a.isAllDay || a.startAt == null) continue;
      final s = a.startAt!;
      final e = _effectiveEnd(a);
      for (var d = 0; d < widget.dayCount; d++) {
        final ds = dayStarts[d];
        final de = dayStarts[d + 1];
        if (!s.isBefore(de) || !e.isAfter(ds)) continue;
        byDay
            .putIfAbsent(d, () => [])
            .add(
              _Seg(
                a,
                d,
                s.isAfter(ds) ? s : ds,
                e.isBefore(de) ? e : de,
                !s.isBefore(ds),
                !e.isAfter(de),
              ),
            );
      }
    }
    return [
      for (final segs in byDay.values)
        ...packLanes<_Seg>(segs, startOf: (s) => s.start, endOf: (s) => s.end),
    ];
  }

  // -- drag handling --

  void _dragStart(_Placed p, _DragKind kind, Offset pos) =>
      setState(() => _drag = _Drag(p, kind, pos, pos));

  void _dragUpdate(Offset pos) {
    final d = _drag;
    if (d != null) setState(() => _drag = d.at(pos));
  }

  void _dragCancel() => setState(() => _drag = null);

  /// The schedule the pending drag would produce.
  CalendarSchedule _preview(_Drag d) {
    final item = d.placed.event.item;
    final start = item.startAt!;
    final durMin = _effectiveEnd(item).difference(start).inMinutes;
    final startMin = minutesOfDay(start);
    final dy = d.current.dy - d.origin.dy;
    final dx = d.current.dx - d.origin.dx;
    var minutes = snapMinutes(dy, pxPerMinute: _pxPerMinute);

    switch (d.kind) {
      case _DragKind.move:
        var dayDelta = (dx / widget.dayWidth).round();
        if (dayDelta != 0) {
          final orig = dayIndexOf(start, widget.start);
          dayDelta = (orig + dayDelta).clamp(0, widget.dayCount - 1) - orig;
        }
        final hi = durMin <= 1440 - startMin ? 1440 - startMin - durMin : 0;
        minutes = minutes.clamp(-startMin, hi);
        return movedSchedule(
          startAt: start,
          endAt: item.endAt,
          dayDelta: dayDelta,
          minuteDelta: minutes,
          legacyEstimatedMinutes: item.estimatedMinutes,
        );
      case _DragKind.resizeTop:
        return resizedSchedule(
          startAt: start,
          endAt: item.endAt,
          fromTop: true,
          minuteDelta: math.max(minutes, -startMin),
          legacyEstimatedMinutes: item.estimatedMinutes,
        );
      case _DragKind.resizeBottom:
        final endRel = startMin + durMin;
        final dayEndRel = ((endRel - 1) ~/ 1440 + 1) * 1440;
        return resizedSchedule(
          startAt: start,
          endAt: item.endAt,
          fromTop: false,
          minuteDelta: math.min(minutes, dayEndRel - endRel),
          legacyEstimatedMinutes: item.estimatedMinutes,
        );
    }
  }

  Future<void> _dragEnd() async {
    final d = _drag;
    if (d == null) return;
    final item = d.placed.event.item;
    final s = _preview(d);
    final unchanged =
        s.startAt == item.startAt &&
        (s.endAt == item.endAt ||
            (item.endAt == null && s.endAt == _effectiveEnd(item)));
    if (unchanged) {
      setState(() => _drag = null);
      return;
    }
    final resizing = d.kind != _DragKind.move;
    try {
      await runUndoable(
        context,
        ref,
        item.id,
        resizing ? 'Resized' : 'Moved',
        () => ref
            .read(actionServiceProvider)
            .updateSchedule(item.id, startAt: s.startAt, endAt: s.endAt),
      );
    } finally {
      if (mounted) setState(() => _drag = null);
    }
  }

  // -- build --

  @override
  Widget build(BuildContext context) {
    final visibleHours = ref.watch(calendarVisibleHoursProvider);
    ref.listen<int>(calendarVisibleHoursProvider, (_, _) => _anchorZoom());

    return LayoutBuilder(
      builder: (context, box) {
        _viewportHeight = box.maxHeight;
        _hourHeight = math.max(_kMinHourHeight, box.maxHeight / visibleHours);
        _scrollController ??= ScrollController(
          initialScrollOffset: math.max(0, _px(_minutesNow() - 60)),
        );
        return _buildGrid(context);
      },
    );
  }

  int _minutesNow() {
    final now = _local(DateTime.now().toUtc());
    return now.hour * 60 + now.minute;
  }

  Widget _buildGrid(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dayW = widget.dayWidth;
    final dayStarts = _dayStarts;
    final placed = _layout(dayStarts);
    final now = DateTime.now().toUtc();
    final todayIdx = dayIndexOf(now, widget.start);
    final drag = _drag;
    final gridHeight = _hourHeight * 24;

    final children = <Widget>[
      Positioned.fill(
        // Empty grid space: a click clears the selection, a drag sweeps out a
        // time range for a new action. Events sit above and take their own
        // gestures.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onTapDown: (_) =>
              ref.read(calendarSelectedActionProvider.notifier).state = null,
          onPanStart: _createStart,
          onPanUpdate: _createUpdate,
          onPanEnd: (_) => _createEnd(),
          onPanCancel: _createCancel,
          child: CustomPaint(
            painter: _GridPainter(
              dayCount: widget.dayCount,
              dayWidth: dayW,
              hourHeight: _hourHeight,
              color: scheme.outlineVariant,
            ),
          ),
        ),
      ),
      for (final p in placed)
        _blockFor(p, dayStarts, drag != null && identical(drag.placed, p)),
      if (todayIdx >= 0 && todayIdx < widget.dayCount)
        Positioned(
          left: todayIdx * dayW,
          width: dayW,
          top: _px(minutesOfDay(now)) - 1,
          height: 2,
          child: IgnorePointer(
            key: const ValueKey('now-line'),
            child: ColoredBox(color: scheme.error),
          ),
        ),
      if (drag != null) _ghost(drag, dayStarts),
      if (_newRange != null) _createPreview(scheme, _newRange!),
    ];

    return SingleChildScrollView(
      controller: _scroll,
      child: Listener(
        // Translucent: empty grid space has nothing hit-testable in it, and
        // the wheel must still reach us there.
        behavior: HitTestBehavior.translucent,
        onPointerSignal: _onWheel,
        child: SizedBox(
          height: gridHeight + 8,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _kGutter,
                height: gridHeight,
                child: Stack(
                  children: [
                    for (var h = 1; h < 24; h++)
                      Positioned(
                        top: h * _hourHeight - 7,
                        right: 6,
                        child: Text(
                          '${twoDigits(h)}:00',
                          style: TextStyle(
                            fontSize: 10,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                width: dayW * widget.dayCount,
                height: gridHeight,
                child: Stack(clipBehavior: Clip.none, children: children),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _blockFor(_Placed p, List<DateTime> dayStarts, bool dragging) {
    final seg = p.event;
    final laneW = widget.dayWidth / p.laneCount;
    final topMin = seg.start.difference(dayStarts[seg.day]).inSeconds / 60;
    final lenMin = seg.end.difference(seg.start).inSeconds / 60;
    final height = math.max(_kMinBlockHeight, _px(lenMin));
    final key = seg.isStart
        ? ValueKey('event-${seg.item.id}')
        : ValueKey('event-${seg.item.id}-d${seg.day}');
    return Positioned(
      key: key,
      left: seg.day * widget.dayWidth + p.lane * laneW,
      top: _px(topMin),
      width: laneW - 2,
      height: height,
      child: _HoverToolbarHost(
        actionId: seg.item.id,
        suppressed: dragging,
        child: _EventBlock(
          seg: seg,
          height: height,
          running: widget.running.contains(seg.item.id),
          dragging: dragging,
          onDragStart: (kind, pos) => _dragStart(p, kind, pos),
          onDragUpdate: _dragUpdate,
          onDragEnd: _dragEnd,
          onDragCancel: _dragCancel,
        ),
      ),
    );
  }

  Widget _ghost(_Drag drag, List<DateTime> dayStarts) {
    final scheme = Theme.of(context).colorScheme;
    final s = _preview(drag);
    final day = dayIndexOf(
      s.startAt,
      widget.start,
    ).clamp(0, widget.dayCount - 1);
    final topMin = s.startAt.difference(dayStarts[day]).inMinutes;
    final endMin = math.min(1440, s.endAt.difference(dayStarts[day]).inMinutes);
    final p = drag.placed;
    final laneW = widget.dayWidth / p.laneCount;
    return Positioned(
      key: const ValueKey('drag-ghost'),
      left: day * widget.dayWidth + p.lane * laneW,
      top: _px(topMin),
      width: laneW - 2,
      height: math.max(_kMinBlockHeight, _px(endMin - topMin)),
      child: _rangeBox(scheme, '${_hhmm(s.startAt)} – ${_hhmm(s.endAt)}'),
    );
  }

  /// The translucent box with the bold white time chip, shared by the
  /// move/resize ghost and the drag-to-create preview.
  Widget _rangeBox(ColorScheme scheme, String range) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.35),
          border: Border.all(color: scheme.primary),
          borderRadius: BorderRadius.circular(4),
        ),
        // Not clipped: on a short block the chip spills below it rather
        // than being cut off.
        child: Align(
          alignment: Alignment.topLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              // Solid white with dark text in both themes, so the times
              // stay legible over whatever block sits underneath.
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 4),
              ],
            ),
            child: Text(
              range,
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // -- drag-to-create --

  void _createStart(DragStartDetails d) {
    final day = (d.localPosition.dx / widget.dayWidth).floor().clamp(
      0,
      widget.dayCount - 1,
    );
    setState(
      () => _newRange = _NewRange(day, d.localPosition.dy, d.localPosition.dy),
    );
  }

  void _createUpdate(DragUpdateDetails d) {
    final r = _newRange;
    if (r != null) setState(() => _newRange = r.at(d.localPosition.dy));
  }

  void _createCancel() => setState(() => _newRange = null);

  /// The dragged range as UTC start/end: the start snaps down and the end up
  /// to the 10-minute grid, so the slot covers what was swept; at least
  /// [kMinDurationMinutes] long and inside its day.
  (DateTime, DateTime) _newRangeTimes(_NewRange r) {
    int minuteAt(double y, double Function(double) round) {
      final minutes = pxToMinutes(y, pxPerMinute: _pxPerMinute);
      return (round(minutes / kSnapMinutes) * kSnapMinutes).round().clamp(
        0,
        1440,
      );
    }

    var from = minuteAt(
      math.min(r.originY, r.currentY),
      (v) => v.floorToDouble(),
    );
    var to = minuteAt(math.max(r.originY, r.currentY), (v) => v.ceilToDouble());
    if (to - from < kMinDurationMinutes) to = from + kMinDurationMinutes;
    if (to > 1440) {
      to = 1440;
      from = 1440 - kMinDurationMinutes;
    }
    final dayStart = calendarAddDays(widget.start, r.day);
    return (
      dayStart.add(Duration(minutes: from)),
      dayStart.add(Duration(minutes: to)),
    );
  }

  Future<void> _createEnd() async {
    final r = _newRange;
    setState(() => _newRange = null);
    if (r == null) return;
    final (start, end) = _newRangeTimes(r);
    await ActionEditorDialog.show(
      context,
      initialStart: start,
      initialEnd: end,
    );
  }

  Widget _createPreview(ColorScheme scheme, _NewRange r) {
    final (start, end) = _newRangeTimes(r);
    final dayStart = calendarAddDays(widget.start, r.day);
    final topMin = start.difference(dayStart).inMinutes;
    final lenMin = end.difference(start).inMinutes;
    return Positioned(
      key: const ValueKey('create-preview'),
      left: r.day * widget.dayWidth,
      top: _px(topMin),
      width: widget.dayWidth - 2,
      height: math.max(_kMinBlockHeight, _px(lenMin)),
      child: _rangeBox(scheme, '${_hhmm(start)} – ${_hhmm(end)}'),
    );
  }
}

/// A time range being dragged out on empty grid space: the day column it
/// started in and the vertical extent (px inside the grid) so far.
class _NewRange {
  final int day;
  final double originY;
  final double currentY;

  const _NewRange(this.day, this.originY, this.currentY);

  _NewRange at(double y) => _NewRange(day, originY, y);
}

class _GridPainter extends CustomPainter {
  final int dayCount;
  final double dayWidth;
  final double hourHeight;
  final Color color;

  const _GridPainter({
    required this.dayCount,
    required this.dayWidth,
    required this.hourHeight,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var h = 0; h <= 24; h++) {
      final y = h * hourHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    for (var d = 0; d < dayCount; d++) {
      final x = d * dayWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.dayCount != dayCount ||
      old.dayWidth != dayWidth ||
      old.hourHeight != hourHeight ||
      old.color != color;
}

class _EventBlock extends ConsumerWidget {
  final _Seg seg;
  final double height;
  final bool running;
  final bool dragging;
  final void Function(_DragKind, Offset) onDragStart;
  final void Function(Offset) onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onDragCancel;

  const _EventBlock({
    required this.seg,
    required this.height,
    required this.running,
    required this.dragging,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
  });

  void _select(WidgetRef ref, String id) =>
      ref.read(calendarSelectedActionProvider.notifier).state = id;

  _DragKind _kindAt(double dy) {
    final h = math.min(_kHandle, height / 3);
    if (seg.isStart && dy < h) return _DragKind.resizeTop;
    if (seg.isEnd && dy > height - h) return _DragKind.resizeBottom;
    return _DragKind.move;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final item = seg.item;
    final done = item.isDoneBefore;
    final urgency = done || running
        ? null
        : ref.watch(actionUrgencyProvider.select((m) => m[item.id]));
    final uc = urgency == null
        ? null
        : urgencyColors(
            urgency,
            dark: Theme.of(context).brightness == Brightness.dark,
          );
    final bg = running
        ? scheme.primary
        : done
        ? scheme.surfaceContainerHighest
        : uc?.bg ?? scheme.primaryContainer;
    final fg = running
        ? scheme.onPrimary
        : done
        ? scheme.onSurfaceVariant
        : uc?.fg ?? scheme.onPrimaryContainer;
    final name = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: fg,
      decoration: done ? TextDecoration.lineThrough : null,
    );
    final selected = ref.watch(
      calendarSelectedActionProvider.select((id) => id == item.id),
    );
    // The action's own start–end (not this day-slice's), so a block that
    // continues past midnight doesn't read "00:00", and the end is visible
    // without opening the event. The end is the one the block is drawn to.
    final timeRange = '${_hhmm(item.startAt!)}–${_hhmm(_effectiveEnd(item))}';

    final Widget label = height >= 34
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: name,
              ),
              Text(timeRange, style: TextStyle(fontSize: 11, color: fg)),
            ],
          )
        : Text(
            '${item.name} · $timeRange',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: name.copyWith(fontSize: 11),
          );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      // Click selects (so Delete can act on it); double-click edits.
      onTapDown: (_) => _select(ref, item.id),
      onDoubleTap: () => openActionEditor(context, ref, item.id),
      onPanStart: (d) {
        _select(ref, item.id);
        onDragStart(_kindAt(d.localPosition.dy), d.globalPosition);
      },
      onPanUpdate: (d) => onDragUpdate(d.globalPosition),
      onPanEnd: (_) => onDragEnd(),
      onPanCancel: onDragCancel,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Opacity(
              opacity: dragging ? 0.4 : 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(4),
                  border: selected
                      ? Border.all(color: scheme.onSurface, width: 2)
                      : Border.all(color: scheme.surface),
                ),
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minHeight: 0,
                    maxHeight: double.infinity,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        6,
                        height >= 20 ? 3 : 0,
                        6,
                        0,
                      ),
                      child: label,
                    ),
                  ),
                ),
              ),
            ),
            if (seg.isStart)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: math.min(_kHandle, height / 3),
                child: const MouseRegion(
                  cursor: SystemMouseCursors.resizeUpDown,
                  opaque: false,
                ),
              ),
            if (seg.isEnd)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: math.min(_kHandle, height / 3),
                child: const MouseRegion(
                  cursor: SystemMouseCursors.resizeUpDown,
                  opaque: false,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
