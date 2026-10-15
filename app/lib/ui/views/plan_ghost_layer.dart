import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import '../../domain/plan_rules.dart';

/// Planning mode's translucent blocks (one per plan occurrence on the viewed
/// days), drawn UNDER the real events. Self-contained: the calendar hands in the
/// geometry and two callbacks, so the plain calendar never builds any of this.
///
/// An occurrence that crosses midnight (a sleep 22:00-07:00) is drawn as one
/// SLICE per day it touches, like a real event: the part after midnight stands at
/// the top of the next day. The host passes occurrences that started up to a week
/// before [firstDay] (and one day after the last), so the pieces on the first
/// visible day and the Previous actions of a block just after the range are there
/// too.
///
/// The Previous / Next actions a row creates with each occurrence are drawn next
/// to it (a Previous one ending [PlanCompanion.gapMinutes] before the block
/// starts, a Next one starting that long after it ends) in a lighter tint with an
/// arrow; they follow the block while it is dragged and open the plan item when
/// edited.
///
/// Desktop: drag a block (any slice) to change its time of day (10-minute steps),
/// drag the bottom edge of its last slice to change its length, double-click to
/// edit the plan item. Phone: long-press then drag to move, tap to edit. A change
/// is reported as the occurrence plus the new start / duration; the host decides
/// whether it is "this day only" or "the whole pattern".
class PlanGhostLayer extends StatefulWidget {
  const PlanGhostLayer({
    super.key,
    required this.firstDay,
    required this.dayCount,
    required this.dayWidth,
    required this.hourHeight,
    required this.phone,
    required this.occurrences,
    required this.onEdit,
    required this.onChanged,
    this.templateNames = const {},
  });

  /// The first visible local date ([planDate]).
  final DateTime firstDay;
  final int dayCount;
  final double dayWidth;
  final double hourHeight;
  final bool phone;
  final List<PlanOccurrence> occurrences;

  /// Template id -> name: a Previous / Next action without a name of its own is
  /// called what its template is called.
  final Map<String, String> templateNames;
  final void Function(PlanOccurrence occ) onEdit;
  final void Function(PlanOccurrence occ, int startMin, int durationMin)
  onChanged;

  @override
  State<PlanGhostLayer> createState() => _PlanGhostLayerState();
}

class _GhostDrag {
  _GhostDrag(this.key, this.resize, this.startY);
  final String key;
  final bool resize;
  final double startY;
  double dy = 0;
}

enum _Kind { main, prev, next }

/// One day's part of an occurrence or of one of its Previous / Next actions.
class _Slot {
  _Slot(
    this.occ,
    this.kind,
    this.index,
    this.companion,
    this.day,
    this.k,
    this.startMin,
    this.endMin,
  );
  final PlanOccurrence occ;
  final _Kind kind;

  /// The position in the row's Previous / Next list (companions only).
  final int index;
  final PlanCompanion? companion;

  /// The visible day column.
  final int day;

  /// Days after (before, when negative) the day the occurrence starts on.
  final int k;

  /// The committed part of the day it covers (minutes; empty = start >= end).
  final int startMin;
  final int endMin;
  int lane = 0;
  int lanes = 1;

  bool get isEmpty => endMin <= startMin;
}

const _kSnap = 10;
const _kMinLen = 10;
const _kDay = 24 * 60;

int _floorDiv(int a, int b) => (a / b).floor();

/// Identifies ONE occurrence: `PlanOccurrence.key` is only `YYYY-MM-DD#row`, which
/// every plan item has on the same day - a drag that compared it alone pulled all
/// of them together.
String _idOf(PlanOccurrence o) => '${o.planItemId}|${o.key}';

class _PlanGhostLayerState extends State<PlanGhostLayer> {
  _GhostDrag? _drag;

  double get _pxPerMin => widget.hourHeight / 60;

  /// The (start, end) of a Previous / Next action in minutes from the midnight of
  /// its occurrence's own day, given the occurrence's [mainStart] / [mainEnd].
  (int, int) _companionSpan(
    _Kind kind,
    PlanCompanion c,
    int mainStart,
    int mainEnd,
  ) {
    if (kind == _Kind.prev) {
      final end = mainStart - c.gapMinutes;
      return (end - c.minutes, end);
    }
    final start = mainEnd + c.gapMinutes;
    return (start, start + c.minutes);
  }

  /// Every slice on the visible days, with lanes packed per day. Slices one day
  /// beyond what a block needs are included (empty until a drag makes it longer,
  /// later or earlier).
  List<_Slot> _slots() {
    final slots = <_Slot>[];

    void add(
      PlanOccurrence o,
      _Kind kind,
      int index,
      PlanCompanion? c,
      int absStart,
      int absEnd,
    ) {
      final occDay = o.date.difference(widget.firstDay).inDays;
      final lo = _floorDiv(absStart, _kDay) - (kind == _Kind.main ? 0 : 1);
      final hi = _floorDiv(absEnd - 1, _kDay) + 1;
      for (var k = lo; k <= hi; k++) {
        final day = occDay + k;
        if (day < 0 || day >= widget.dayCount) continue;
        final base = k * _kDay;
        final s = math.max(absStart, base) - base;
        final e = math.min(absEnd, base + _kDay) - base;
        slots.add(_Slot(o, kind, index, c, day, k, s, e));
      }
    }

    for (final o in widget.occurrences) {
      // All-day occurrences are chips in the all-day strip, not blocks here.
      if (o.allDay) continue;
      final mainStart = o.startMin;
      final mainEnd = o.startMin + o.durationMin;
      add(o, _Kind.main, 0, null, mainStart, mainEnd);
      for (var i = 0; i < o.extras.prev.length; i++) {
        final c = o.extras.prev[i];
        final (s, e) = _companionSpan(_Kind.prev, c, mainStart, mainEnd);
        add(o, _Kind.prev, i, c, s, e);
      }
      for (var i = 0; i < o.extras.next.length; i++) {
        final c = o.extras.next[i];
        final (s, e) = _companionSpan(_Kind.next, c, mainStart, mainEnd);
        add(o, _Kind.next, i, c, s, e);
      }
    }
    // Greedy lanes per day: overlapping ghosts stand side by side.
    for (var d = 0; d < widget.dayCount; d++) {
      final day = slots.where((s) => s.day == d && !s.isEmpty).toList()
        ..sort((a, b) => a.startMin.compareTo(b.startMin));
      var cluster = <_Slot>[];
      var clusterEnd = -1;
      void close() {
        final n = cluster.fold<int>(0, (m, s) => math.max(m, s.lane + 1));
        for (final s in cluster) {
          s.lanes = n;
        }
        cluster = [];
      }

      for (final s in day) {
        if (cluster.isNotEmpty && s.startMin >= clusterEnd) close();
        final taken = {
          for (final c in cluster)
            if (c.endMin > s.startMin) c.lane,
        };
        var lane = 0;
        while (taken.contains(lane)) {
          lane++;
        }
        s.lane = lane;
        cluster.add(s);
        clusterEnd = math.max(clusterEnd, s.endMin);
      }
      close();
    }
    return slots;
  }

  int _deltaMin(double dy) => (dy / _pxPerMin / _kSnap).round() * _kSnap;

  void _finish(_Slot s) {
    final d = _drag;
    setState(() => _drag = null);
    if (d == null) return;
    final delta = _deltaMin(d.dy);
    if (delta == 0) return;
    if (d.resize) {
      final len = math.max(_kMinLen, s.occ.durationMin + delta);
      widget.onChanged(s.occ, s.occ.startMin, len);
    } else {
      final start = (s.occ.startMin + delta).clamp(0, _kDay - _kMinLen);
      widget.onChanged(s.occ, start, s.occ.durationMin);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final slots = _slots();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final s in slots) _ghost(context, scheme, s),
      ],
    );
  }

  String _label(_Slot s, int absStart, int absEnd) {
    final c = s.companion;
    final String name;
    if (c == null) {
      name = s.occ.name;
    } else {
      name =
          c.name ??
          widget.templateNames[c.templateId] ??
          '${s.occ.name} - ${s.kind == _Kind.prev ? 'before' : 'after'}';
    }
    return '$name\n${planTime(absStart)}-${planTime(absEnd)}';
  }

  Widget _ghost(BuildContext context, ColorScheme scheme, _Slot s) {
    final drag = _drag?.key == _idOf(s.occ) ? _drag : null;
    // The occurrence as it is (or as the drag would make it), from its own
    // midnight; this slice is the part that falls on its day.
    var mainStart = s.occ.startMin;
    var mainEnd = s.occ.startMin + s.occ.durationMin;
    if (drag != null) {
      final delta = _deltaMin(drag.dy);
      if (drag.resize) {
        mainEnd = math.max(mainStart + _kMinLen, mainEnd + delta);
      } else {
        final dur = mainEnd - mainStart;
        mainStart = (mainStart + delta).clamp(0, _kDay - _kMinLen);
        mainEnd = mainStart + dur;
      }
    }
    final int absStart, absEnd;
    if (s.kind == _Kind.main) {
      absStart = mainStart;
      absEnd = mainEnd;
    } else {
      (absStart, absEnd) = _companionSpan(
        s.kind,
        s.companion!,
        mainStart,
        mainEnd,
      );
    }
    final base = s.k * _kDay;
    final startMin = math.max(absStart, base) - base;
    final endMin = math.min(absEnd, base + _kDay) - base;
    if (endMin <= startMin) return const SizedBox.shrink();

    final isMain = s.kind == _Kind.main;
    final isLast = isMain && absEnd <= base + _kDay;
    final laneW = (widget.dayWidth - 2) / s.lanes;
    final height = math.max(14.0, (endMin - startMin) * _pxPerMin);
    final color = isMain ? scheme.tertiary : scheme.secondary;
    final label = _label(s, absStart, absEnd);

    Widget body = DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: drag != null ? 0.3 : (isMain ? 0.16 : 0.1),
        ),
        border: Border.all(color: color.withValues(alpha: isMain ? 0.7 : 0.5)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: math.max(1, (height / 11).floor()),
                overflow: TextOverflow.clip,
                style: TextStyle(
                  fontSize: 9.5,
                  height: 1.1,
                  color: scheme.onSurface,
                ),
              ),
            ),
            Icon(
              isMain
                  ? Icons.event_repeat
                  : (s.kind == _Kind.prev
                        ? Icons.keyboard_double_arrow_right
                        : Icons.keyboard_double_arrow_left),
              size: 11,
              color: color,
            ),
          ],
        ),
      ),
    );

    // The drag starts at the pointer DOWN (so the first pixels count) and is
    // measured against that point, not summed from deltas.
    void start(DragStartDetails d, bool resize) => setState(
      () => _drag = _GhostDrag(_idOf(s.occ), resize, d.globalPosition.dy),
    );
    void update(DragUpdateDetails u) =>
        setState(() => _drag?.dy = u.globalPosition.dy - _drag!.startY);

    if (!isMain) {
      // A Previous / Next action is changed in the plan item, not dragged.
      body = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.phone ? () => widget.onEdit(s.occ) : null,
        onDoubleTap: widget.phone ? null : () => widget.onEdit(s.occ),
        child: body,
      );
    } else if (widget.phone) {
      body = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onEdit(s.occ),
        onLongPressStart: (_) => setState(() => _drag = _GhostDrag(_idOf(s.occ), false, 0)),
        onLongPressMoveUpdate: (u) =>
            setState(() => _drag?.dy = u.offsetFromOrigin.dy),
        onLongPressEnd: (_) => _finish(s),
        onLongPressCancel: () => setState(() => _drag = null),
        child: body,
      );
    } else {
      body = Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: () => widget.onEdit(s.occ),
              dragStartBehavior: DragStartBehavior.down,
              onVerticalDragStart: (d) => start(d, false),
              onVerticalDragUpdate: update,
              onVerticalDragEnd: (_) => _finish(s),
              onVerticalDragCancel: () => setState(() => _drag = null),
              child: body,
            ),
          ),
          // The length is changed at the very end of the block: its last slice.
          if (isLast)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 6,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeUpDown,
                child: GestureDetector(
                  key: ValueKey('plan-ghost-handle-${s.occ.planItemId}-${s.occ.key}'),
                  behavior: HitTestBehavior.opaque,
                  dragStartBehavior: DragStartBehavior.down,
                  onVerticalDragStart: (d) => start(d, true),
                  onVerticalDragUpdate: update,
                  onVerticalDragEnd: (_) => _finish(s),
                  onVerticalDragCancel: () => setState(() => _drag = null),
                ),
              ),
            ),
        ],
      );
    }

    final String keySuffix = isMain
        ? (s.k == 0 ? '' : '~${s.k}')
        : '>${s.kind == _Kind.prev ? 'p' : 'n'}${s.index}@${s.k}';
    return Positioned(
      key: ValueKey('plan-ghost-${s.occ.planItemId}-${s.occ.key}$keySuffix'),
      left: s.day * widget.dayWidth + s.lane * laneW,
      top: startMin * _pxPerMin,
      width: laneW,
      height: height,
      child: body,
    );
  }
}
