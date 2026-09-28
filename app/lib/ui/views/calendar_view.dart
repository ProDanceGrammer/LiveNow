import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
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
import '../widgets/action_tile.dart';
import 'calendar_layout.dart';

const double _kGutter = 56;
const double _kHandle = 6;
const double _kMinBlockHeight = kPxPerMinute * kMinDurationMinutes;
const double _kToolbarWidth = 96;
const double _kToolbarHeight = 24;
const double _kGridHeight = kHourHeight * 24;

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

    return Column(
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
                  border: Border(left: BorderSide(color: scheme.outlineVariant)),
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
    final bg = running
        ? scheme.primary
        : done
        ? scheme.surfaceContainerHighest
        : scheme.tertiaryContainer;
    final fg = running
        ? scheme.onPrimary
        : done
        ? scheme.onSurfaceVariant
        : scheme.onTertiaryContainer;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: _HoverToolbarHost(
        actionId: item.id,
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(4),
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => openActionEditor(context, ref, item.id),
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
              onFinish: () => _run('Finished', (s) => s.finish(widget.actionId)),
              onWeek: () => _run(
                'Postponed to next week',
                (s) => s.postpone(widget.actionId, PostponeRule.nextWeek),
              ),
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
  final VoidCallback onWeek;

  const _Toolbar({
    required this.onStart,
    required this.onFinish,
    required this.onWeek,
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
          _ToolButton('7⃣📅', 'Postpone +7 days', 40, onWeek),
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
          child: Center(child: Text(emoji, style: const TextStyle(fontSize: 13))),
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

  const _Seg(this.item, this.day, this.start, this.end, this.isStart, this.isEnd);
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
  late final ScrollController _scroll;
  Timer? _tick;
  _Drag? _drag;

  @override
  void initState() {
    super.initState();
    final now = _local(DateTime.now().toUtc());
    final nowMin = now.hour * 60 + now.minute;
    _scroll = ScrollController(
      initialScrollOffset: math.max(0, minutesToPx(nowMin - 60)),
    );
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  List<DateTime> get _dayStarts => [
    for (var i = 0; i <= widget.dayCount; i++)
      calendarAddDays(widget.start, i),
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
    var minutes = snapMinutes(dy);

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
    final scheme = Theme.of(context).colorScheme;
    final dayW = widget.dayWidth;
    final dayStarts = _dayStarts;
    final placed = _layout(dayStarts);
    final now = DateTime.now().toUtc();
    final todayIdx = dayIndexOf(now, widget.start);
    final drag = _drag;

    final children = <Widget>[
      Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(
            painter: _GridPainter(
              dayCount: widget.dayCount,
              dayWidth: dayW,
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
          top: minutesToPx(minutesOfDay(now)) - 1,
          height: 2,
          child: IgnorePointer(
            key: const ValueKey('now-line'),
            child: ColoredBox(color: scheme.error),
          ),
        ),
      if (drag != null) _ghost(drag, dayStarts),
    ];

    return SingleChildScrollView(
      controller: _scroll,
      child: SizedBox(
        height: _kGridHeight + 8,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _kGutter,
              height: _kGridHeight,
              child: Stack(
                children: [
                  for (var h = 1; h < 24; h++)
                    Positioned(
                      top: h * kHourHeight - 7,
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
              height: _kGridHeight,
              child: Stack(clipBehavior: Clip.none, children: children),
            ),
          ],
        ),
      ),
    );
  }

  Widget _blockFor(_Placed p, List<DateTime> dayStarts, bool dragging) {
    final seg = p.event;
    final laneW = widget.dayWidth / p.laneCount;
    final topMin = seg.start.difference(dayStarts[seg.day]).inSeconds / 60;
    final lenMin = seg.end.difference(seg.start).inSeconds / 60;
    final height = math.max(_kMinBlockHeight, minutesToPx(lenMin));
    final key = seg.isStart
        ? ValueKey('event-${seg.item.id}')
        : ValueKey('event-${seg.item.id}-d${seg.day}');
    return Positioned(
      key: key,
      left: seg.day * widget.dayWidth + p.lane * laneW,
      top: minutesToPx(topMin),
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
    final day = dayIndexOf(s.startAt, widget.start).clamp(0, widget.dayCount - 1);
    final topMin = s.startAt.difference(dayStarts[day]).inMinutes;
    final endMin = math.min(1440, s.endAt.difference(dayStarts[day]).inMinutes);
    final p = drag.placed;
    final laneW = widget.dayWidth / p.laneCount;
    return Positioned(
      key: const ValueKey('drag-ghost'),
      left: day * widget.dayWidth + p.lane * laneW,
      top: minutesToPx(topMin),
      width: laneW - 2,
      height: math.max(_kMinBlockHeight, minutesToPx(endMin - topMin)),
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 2, 6, 0),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.35),
            border: Border.all(color: scheme.primary),
            borderRadius: BorderRadius.circular(4),
          ),
          child: ClipRect(
            child: Text(
              '${_hhmm(s.startAt)} – ${_hhmm(s.endAt)}',
              maxLines: 1,
              style: TextStyle(fontSize: 11, color: scheme.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  final int dayCount;
  final double dayWidth;
  final Color color;

  const _GridPainter({
    required this.dayCount,
    required this.dayWidth,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var h = 0; h <= 24; h++) {
      final y = h * kHourHeight;
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
    final bg = running
        ? scheme.primary
        : done
        ? scheme.surfaceContainerHighest
        : scheme.primaryContainer;
    final fg = running
        ? scheme.onPrimary
        : done
        ? scheme.onSurfaceVariant
        : scheme.onPrimaryContainer;
    final name = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: fg,
      decoration: done ? TextDecoration.lineThrough : null,
    );
    final dur = formatActionDuration(item);

    final Widget label = height >= 34
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: name),
              Text(dur, style: TextStyle(fontSize: 11, color: fg)),
            ],
          )
        : Text(
            '${item.name} · $dur',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: name.copyWith(fontSize: 11),
          );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onTap: () => openActionEditor(context, ref, item.id),
      onPanStart: (d) => onDragStart(_kindAt(d.localPosition.dy), d.globalPosition),
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
                  border: Border.all(color: scheme.surface),
                ),
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minHeight: 0,
                    maxHeight: double.infinity,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(6, height >= 20 ? 3 : 0, 6, 0),
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
