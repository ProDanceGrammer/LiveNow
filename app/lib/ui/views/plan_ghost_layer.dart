import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart'
    show DragStartBehavior, PointerDeviceKind, kSecondaryMouseButton;
import 'package:flutter/material.dart';

import '../../domain/duration_rules.dart' show formatDuration;
import '../../domain/plan_rules.dart';
import '../../domain/sequence_naming.dart' show normalizeForMatch;
import 'calendar_layout.dart' show snapToNeighbours;

/// Tint of a plan block whose real average is shorter than planned (the red
/// one is the theme's error colour).
const kPlanFasterColor = Color(0xFF2E9E5B);

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
/// edit the plan item. Dragging with the RIGHT mouse button moves the block with a
/// magnet: it locks onto the start / end of the other plan blocks (off the
/// 10-minute grid too), so plan items line up one after another like real
/// actions do. Phone: long-press then drag to move, tap to edit. A change
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
    this.averages = const {},
  });

  /// `normalizeForMatch(name)` -> mean real length in minutes of its finished
  /// runs: a block is tinted red when that is longer than the block, green when
  /// shorter, and shows it after the time.
  final Map<String, int> averages;

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
  _GhostDrag(
    this.key,
    this.resize,
    this.startY,
    this.originScroll, {
    this.magnet = false,
    this.edges = const [],
  }) : lastY = startY;
  final String key;
  final bool resize;

  /// A right-button drag: the block snaps onto [edges], the start / end instants
  /// (minutes counted from the dragged occurrence's own midnight) of the OTHER
  /// plan blocks on the visible days, sorted.
  final bool magnet;
  final List<int> edges;

  /// Where the pointer went down (global y) and where the grid was scrolled to.
  final double startY;
  final double originScroll;

  /// The pointer's latest global y (the auto-scroll watches it).
  double lastY;
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

/// A dragged block this close (px) to the top / bottom of the grid's viewport
/// scrolls it, [_kScrollStep] px every 30 ms (like a real event's drag).
const _kScrollEdge = 36.0;
const _kScrollStep = 9.0;

class _PlanGhostLayerState extends State<PlanGhostLayer> {
  _GhostDrag? _drag;
  ScrollPosition? _position;
  Timer? _scrollTimer;

  @override
  void dispose() {
    _stopDrag();
    super.dispose();
  }

  /// The drag's vertical distance: the pointer's travel PLUS how far the grid has
  /// scrolled since it began (a wheel turning, or the auto-scroll, moves the
  /// content under a pointer that did not move - the block must follow it).
  double _dyOf(_GhostDrag d) =>
      d.lastY - d.startY + ((_position?.pixels ?? d.originScroll) - d.originScroll);

  /// The edges the magnet can lock onto while [dragged] moves.
  List<int> _edgesFor(PlanOccurrence dragged) {
    final occDay = dragged.date.difference(widget.firstDay).inDays;
    final id = _idOf(dragged);
    final out = <int>{};
    for (final s in _slots()) {
      if (s.isEmpty || _idOf(s.occ) == id) continue;
      final off = (s.day - occDay) * _kDay;
      out
        ..add(off + s.startMin)
        ..add(off + s.endMin);
    }
    return out.toList()..sort();
  }

  void _beginDrag(
    String id,
    bool resize,
    double globalY, {
    PlanOccurrence? magnetFor,
  }) {
    _position = Scrollable.maybeOf(context)?.position;
    _position?.addListener(_onScroll);
    _scrollTimer?.cancel();
    _scrollTimer = Timer.periodic(const Duration(milliseconds: 30), (_) {
      final d = _drag;
      final pos = _position;
      if (d == null || pos == null || !pos.hasPixels) return;
      final box = Scrollable.maybeOf(context)?.context.findRenderObject();
      if (box is! RenderBox || !box.attached) return;
      final top = box.localToGlobal(Offset.zero).dy;
      final bottom = top + box.size.height;
      var step = 0.0;
      if (d.lastY < top + _kScrollEdge) {
        step = -_kScrollStep;
      } else if (d.lastY > bottom - _kScrollEdge) {
        step = _kScrollStep;
      }
      if (step == 0) return;
      final target = (pos.pixels + step).clamp(
        pos.minScrollExtent,
        pos.maxScrollExtent,
      );
      if (target != pos.pixels) pos.jumpTo(target);
    });
    final edges = magnetFor == null ? const <int>[] : _edgesFor(magnetFor);
    setState(
      () => _drag = _GhostDrag(
        id,
        resize,
        globalY,
        _position?.pixels ?? 0,
        magnet: magnetFor != null,
        edges: edges,
      ),
    );
  }

  void _moveDrag(double globalY) => setState(() => _drag?.lastY = globalY);

  void _onScroll() {
    if (mounted && _drag != null) setState(() {});
  }

  void _stopDrag() {
    _scrollTimer?.cancel();
    _scrollTimer = null;
    _position?.removeListener(_onScroll);
    _position = null;
  }

  void _cancelDrag() {
    _stopDrag();
    if (mounted) setState(() => _drag = null);
  }

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
    // Rebuilt only when its inputs change: a drag rebuilds the layer on every
    // pointer move and _edgesFor asks again, and the lane packing below is
    // quadratic per cluster.
    final cached = _slotsCache;
    if (cached != null &&
        identical(_slotsFor, widget.occurrences) &&
        _slotsDays == widget.dayCount &&
        _slotsFirstDay == widget.firstDay) {
      return cached;
    }
    final built = _computeSlots();
    _slotsCache = built;
    _slotsFor = widget.occurrences;
    _slotsDays = widget.dayCount;
    _slotsFirstDay = widget.firstDay;
    return built;
  }

  List<_Slot>? _slotsCache;

  /// The occurrences as the host gave them (row date / row-zone minutes), by id:
  /// the slots hold [PlanOccurrence.displayed] copies.
  final _originals = <String, PlanOccurrence>{};

  /// What a drag / tap reports to the host: the ORIGINAL occurrence, with a
  /// start in the minutes of its own row.
  void _report(PlanOccurrence shown, int startMin, int durationMin) {
    final original = _originals[_idOf(shown)] ?? shown;
    widget.onChanged(
      original,
      original.rowMinutesFor(shown.date, startMin),
      durationMin,
    );
  }

  void _edit(PlanOccurrence shown) =>
      widget.onEdit(_originals[_idOf(shown)] ?? shown);
  List<PlanOccurrence>? _slotsFor;
  int _slotsDays = 0;
  DateTime? _slotsFirstDay;

  List<_Slot> _computeSlots() {
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

    _originals.clear();
    for (final original in widget.occurrences) {
      // All-day occurrences are chips in the all-day strip, not blocks here.
      if (original.allDay) continue;
      // A row with its own timezone is placed where it falls in the app's own.
      final o = original.displayed();
      _originals[_idOf(o)] = original;
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
      // End minute of the last slot placed in each lane of the open cluster.
      final laneEnds = <int>[];
      void close() {
        for (final s in cluster) {
          s.lanes = laneEnds.length;
        }
        cluster = [];
        laneEnds.clear();
      }

      for (final s in day) {
        if (cluster.isNotEmpty && s.startMin >= clusterEnd) close();
        var lane = laneEnds.indexWhere((end) => end <= s.startMin);
        if (lane == -1) {
          lane = laneEnds.length;
          laneEnds.add(s.endMin);
        } else {
          laneEnds[lane] = s.endMin;
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

  /// How many minutes a MOVE drag shifts [o]: on the 10-minute grid, or for a
  /// right-button drag locked onto the nearest other block's start / end when the
  /// block comes within a few pixels of it.
  int _moveDelta(_GhostDrag d, PlanOccurrence o) {
    final dy = _dyOf(d);
    final grid = _deltaMin(dy);
    if (!d.magnet || d.edges.isEmpty) return grid;
    final origin = DateTime.utc(2000);
    final rawStart = origin.add(
      Duration(seconds: ((o.startMin + dy / _pxPerMin) * 60).round()),
    );
    final snap = snapToNeighbours(
      schedule: (
        startAt: rawStart,
        endAt: rawStart.add(Duration(minutes: o.durationMin)),
      ),
      moveWhole: true,
      neighbourEdges: [
        for (final e in d.edges) origin.add(Duration(minutes: e)),
      ],
      pxPerMinute: _pxPerMin,
    );
    if (snap.snappedTo == null) return grid;
    return (snap.schedule.startAt.difference(origin).inSeconds / 60).round() -
        o.startMin;
  }

  /// The right button went down on a block and has not been released: the drag
  /// starts once the pointer has moved a few pixels.
  ({String id, Offset origin})? _secondary;

  void _finish(_Slot s) {
    final d = _drag;
    final dy = d == null ? 0.0 : _dyOf(d);
    _stopDrag();
    setState(() => _drag = null);
    if (d == null) return;
    final delta = d.resize ? _deltaMin(dy) : _moveDelta(d, s.occ);
    if (delta == 0) return;
    if (d.resize) {
      final len = math.max(_kMinLen, s.occ.durationMin + delta);
      _report(s.occ, s.occ.startMin, len);
    } else {
      final start = (s.occ.startMin + delta).clamp(0, _kDay - _kMinLen);
      _report(s.occ, start, s.occ.durationMin);
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

  String _nameOf(_Slot s) {
    final c = s.companion;
    if (c == null) return s.occ.name;
    return c.name ??
        widget.templateNames[c.templateId] ??
        '${s.occ.name} - ${s.kind == _Kind.prev ? 'before' : 'after'}';
  }

  /// The mean real length (minutes) of this block's name, null without history.
  int? _averageOf(_Slot s) {
    if (widget.averages.isEmpty) return null;
    // The match key of a name is computed once, not per rebuild / drag move.
    final name = _nameOf(s);
    return widget.averages[_keys.putIfAbsent(name, () => normalizeForMatch(name))];
  }

  final _keys = <String, String>{};

  String _label(_Slot s, int absStart, int absEnd, int? average) {
    final time = '${planTime(absStart)}-${planTime(absEnd)}';
    final avg = average == null
        ? ''
        : '  ⌀ ${formatDuration(Duration(minutes: average))}';
    return '${_nameOf(s)}\n$time$avg';
  }

  Widget _ghost(BuildContext context, ColorScheme scheme, _Slot s) {
    final drag = _drag?.key == _idOf(s.occ) ? _drag : null;
    // The occurrence as it is (or as the drag would make it), from its own
    // midnight; this slice is the part that falls on its day.
    var mainStart = s.occ.startMin;
    var mainEnd = s.occ.startMin + s.occ.durationMin;
    if (drag != null) {
      final delta = drag.resize
          ? _deltaMin(_dyOf(drag))
          : _moveDelta(drag, s.occ);
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
    final average = _averageOf(s);
    // Slower than planned: red; quicker: green; no history / equal: as before.
    final planned = absEnd - absStart;
    final color = average == null || average == planned
        ? (isMain ? scheme.tertiary : scheme.secondary)
        : (average > planned ? scheme.error : kPlanFasterColor);
    final label = _label(s, absStart, absEnd, average);

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
    void start(DragStartDetails d, bool resize) =>
        _beginDrag(_idOf(s.occ), resize, d.globalPosition.dy);
    void update(DragUpdateDetails u) => _moveDrag(u.globalPosition.dy);

    if (!isMain) {
      // A Previous / Next action is changed in the plan item, not dragged.
      body = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.phone ? () => _edit(s.occ) : null,
        onDoubleTap: widget.phone ? null : () => _edit(s.occ),
        child: body,
      );
    } else if (widget.phone) {
      body = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _edit(s.occ),
        onLongPressStart: (d) =>
            _beginDrag(_idOf(s.occ), false, d.globalPosition.dy),
        onLongPressMoveUpdate: (u) => _moveDrag(u.globalPosition.dy),
        onLongPressEnd: (_) => _finish(s),
        onLongPressCancel: _cancelDrag,
        child: body,
      );
    } else {
      body = Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: () => _edit(s.occ),
              dragStartBehavior: DragStartBehavior.down,
              onVerticalDragStart: (d) => start(d, false),
              onVerticalDragUpdate: update,
              onVerticalDragEnd: (_) => _finish(s),
              onVerticalDragCancel: _cancelDrag,
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
                  onVerticalDragCancel: _cancelDrag,
                ),
              ),
            ),
        ],
      );
      // The right mouse button drags with the magnet (a plain drag recognizer
      // only listens to the primary button), so raw pointer events are used.
      final id = _idOf(s.occ);
      body = Listener(
        onPointerDown: (e) {
          if (e.kind == PointerDeviceKind.mouse &&
              e.buttons == kSecondaryMouseButton) {
            _secondary = (id: id, origin: e.position);
          }
        },
        onPointerMove: (e) {
          final sec = _secondary;
          if (sec == null || sec.id != id) return;
          if (_drag == null) {
            if ((e.position - sec.origin).distance < 4) return;
            _beginDrag(id, false, sec.origin.dy, magnetFor: s.occ);
          }
          _moveDrag(e.position.dy);
        },
        onPointerUp: (_) {
          final had = _secondary != null && _drag != null;
          _secondary = null;
          if (had) _finish(s);
        },
        onPointerCancel: (_) {
          _secondary = null;
          _cancelDrag();
        },
        child: body,
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
