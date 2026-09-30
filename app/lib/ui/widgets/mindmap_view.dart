import 'dart:math' as math;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/growth_rules.dart';
import '../../domain/metric_service.dart' show MetricCycleException;
import '../../domain/mindmap_layout.dart'
    show
        MindmapPositions,
        layeredLayout,
        shiftIntoView,
        mindmapNodeHeight,
        mindmapNodeWidth,
        radialLayout,
        treeLayout;
import '../providers.dart';
import '../undo.dart';
import '../urgency_colors.dart';
import 'growth_direction_dialog.dart';

const double _handleSize = 16;
const double _edgeHitDistance = 8;
const double _minScale = 0.04;
const double _maxScale = 12;
const double _canvasPadding = 600;

typedef _Edge = ({String from, String to});

/// The relations between growth directions as a mindmap: every direction is a
/// box on one big pannable/zoomable canvas, an arrow runs from a
/// sub-direction to the direction it leads to. Drag a box to move it, drag
/// from the round handle on its right edge onto another box to link them,
/// click an arrow and press Delete to remove the link.
class MindmapView extends ConsumerStatefulWidget {
  const MindmapView({super.key});

  @override
  ConsumerState<MindmapView> createState() => _MindmapViewState();
}

class _MindmapViewState extends ConsumerState<MindmapView> {
  final _controller = TransformationController();
  final _focus = FocusNode(debugLabel: 'mindmap');

  /// Where every node is drawn right now (top-left, canvas coordinates). Only
  /// the node's own widget listens, so dragging never rebuilds the others.
  final Map<String, ValueNotifier<Offset>> _pos = {};

  /// The position each notifier was last set from (saved or laid out), to
  /// tell "the data changed" from "the user is dragging".
  final Map<String, Offset> _applied = {};

  /// Bumped on every move; the edge painter repaints on it.
  final _version = ValueNotifier<int>(0);

  /// The rubber-band line while linking, in canvas coordinates.
  final _rubber = ValueNotifier<({String from, Offset to})?>(null);

  MindmapPositions _layout = const {};
  String _layoutSignature = '';

  /// The selected nodes (a selected edge and selected nodes exclude each other).
  final Set<String> _selected = {};

  /// The selection rectangle being dragged on empty canvas (canvas coords).
  final _marquee = ValueNotifier<Rect?>(null);
  Offset? _marqueeStart;
  int? _marqueePointer;
  bool _marqueeAdditive = false;

  /// The pointer currently panning the canvas (middle/right button, or
  /// Space + left button). While set, node and link drags are ignored.
  int? _panPointer;
  _Edge? _selectedEdge;
  Size _viewport = Size.zero;
  Size _canvas = const Size(2000, 1500);
  bool _fitPending = true;

  /// When set, the next automatic fit frames only these nodes.
  Set<String>? _fitOnly;
  bool _syncScheduled = false;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _version.dispose();
    _rubber.dispose();
    _marquee.dispose();
    for (final n in _pos.values) {
      n.dispose();
    }
    super.dispose();
  }

  double get _scale => _controller.value.getMaxScaleOnAxis();

  // ---- data -> positions ----------------------------------------------------

  /// Recomputes the automatic layout when the graph changed (only needed while
  /// some node has no saved position).
  void _ensureLayout(GrowthSnapshot s) {
    if (s.metrics.every((m) => m.posX != null && m.posY != null)) return;
    final signature =
        '${s.metrics.map((m) => m.id).join(',')}|'
        '${[for (final m in s.metrics)
          for (final d in s.graph.dependsOnOf(m.id)) '$d>${m.id}'].join(',')}';
    if (signature == _layoutSignature) return;
    _layoutSignature = signature;
    _layout = layeredLayout(s.graph, s.metrics);
  }

  Offset _target(GrowthMetric m) {
    if (m.posX != null && m.posY != null) {
      return Offset(math.max(0, m.posX!), math.max(0, m.posY!));
    }
    final p = _layout[m.id];
    return p == null
        ? Offset.zero
        : Offset(math.max(0, p.$1), math.max(0, p.$2));
  }

  /// Creates notifiers for new nodes and, after this frame, moves the ones
  /// whose saved/laid-out position changed (never during build: the nodes
  /// listen to them).
  void _syncPositions(GrowthSnapshot s) {
    final ids = {for (final m in s.metrics) m.id};
    for (final id in _pos.keys.where((k) => !ids.contains(k)).toList()) {
      _pos.remove(id)!.dispose();
      _applied.remove(id);
    }
    var changed = false;
    for (final m in s.metrics) {
      final t = _target(m);
      final n = _pos[m.id];
      if (n == null) {
        _pos[m.id] = ValueNotifier(t);
        _applied[m.id] = t;
      } else if (_applied[m.id] != t) {
        changed = true;
      }
    }
    var maxX = 0.0, maxY = 0.0;
    for (final m in s.metrics) {
      final t = _target(m);
      maxX = math.max(maxX, t.dx);
      maxY = math.max(maxY, t.dy);
    }
    _canvas = Size(
      math.max(2000, maxX + mindmapNodeWidth + _canvasPadding),
      math.max(1500, maxY + mindmapNodeHeight + _canvasPadding),
    );
    if ((changed || _fitPending) && !_syncScheduled) {
      _syncScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncScheduled = false;
        if (!mounted) return;
        final snap = ref.read(growthSnapshotProvider).value;
        if (snap == null) return;
        for (final m in snap.metrics) {
          final t = _target(m);
          if (_applied[m.id] != t) {
            _applied[m.id] = t;
            _pos[m.id]?.value = t;
          }
        }
        _version.value++;
        if (_fitPending && _viewport != Size.zero && snap.metrics.isNotEmpty) {
          _fitPending = false;
          final only = _fitOnly;
          _fitOnly = null;
          _fitAll(only: only);
        }
      });
    }
  }

  List<_Edge> _edges(GrowthSnapshot s) => [
    for (final m in s.metrics)
      for (final d in s.graph.dependsOnOf(m.id))
        if (s.byId.containsKey(d)) (from: d, to: m.id),
  ];

  // ---- toolbar --------------------------------------------------------------

  void _zoomBy(double factor) {
    if (_viewport == Size.zero) return;
    final current = _scale;
    final f = (current * factor).clamp(_minScale, _maxScale) / current;
    final c = Offset(_viewport.width / 2, _viewport.height / 2);
    _controller.value =
        Matrix4.translationValues(c.dx, c.dy, 0) *
        Matrix4.diagonal3Values(f, f, 1) *
        Matrix4.translationValues(-c.dx, -c.dy, 0) *
        _controller.value;
  }

  void _fitAll({Set<String>? only}) {
    if (_viewport == Size.zero || _pos.isEmpty) return;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final e in _pos.entries) {
      if (only != null && !only.contains(e.key)) continue;
      final n = e.value;
      minX = math.min(minX, n.value.dx);
      minY = math.min(minY, n.value.dy);
      maxX = math.max(maxX, n.value.dx + mindmapNodeWidth);
      maxY = math.max(maxY, n.value.dy + mindmapNodeHeight);
    }
    final w = maxX - minX, h = maxY - minY;
    final s = math
        .min((_viewport.width - 40) / w, (_viewport.height - 40) / h)
        .clamp(_minScale, 1.0);
    final cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;
    _controller.value =
        Matrix4.translationValues(
          _viewport.width / 2 - s * cx,
          _viewport.height / 2 - s * cy,
          0,
        ) *
        Matrix4.diagonal3Values(s, s, 1);
  }

  /// Runs a layout with Undo: remembers the positions as stored now.
  Future<void> _runLayout(
    GrowthSnapshot s,
    String description,
    Future<void> Function() apply,
  ) {
    return runUndoableLayout(
      context,
      ref,
      description: description,
      previous: {for (final m in s.metrics) m.id: (m.posX, m.posY)},
      apply: apply,
      afterUndo: () {
        if (!mounted) return;
        _fitPending = true;
        _fitOnly = null;
      },
    );
  }

  /// Every node's current canvas y, so layouts keep the order on screen.
  Map<String, double> get _orderHint => {
    for (final e in _pos.entries) e.key: e.value.value.dy,
  };

  Future<void> _autoLayout(GrowthSnapshot s) {
    final service = ref.read(metricServiceProvider);
    return _runLayout(s, 'Applied auto layout', () async {
      final positions = layeredLayout(s.graph, s.metrics);
      _layout = positions;
      _layoutSignature = '';
      _fitPending = true;
      _fitOnly = null;
      await service.clearPositions();
      await service.savePositions(positions);
    });
  }

  Future<void> _radial(GrowthSnapshot s) {
    if (_selected.length != 1) return Future.value();
    final id = _selected.single;
    final service = ref.read(metricServiceProvider);
    return _runLayout(s, 'Applied radial layout', () {
      _fitPending = true;
      _fitOnly = null;
      return service.savePositions(
        shiftIntoView(radialLayout(s.graph, s.metrics, id)),
      );
    });
  }

  Future<void> _tree(GrowthSnapshot s) {
    final service = ref.read(metricServiceProvider);
    return _runLayout(s, 'Applied tree layout', () {
      _fitPending = true;
      _fitOnly = null;
      return service.savePositions(
        shiftIntoView(treeLayout(s.graph, s.metrics, orderHint: _orderHint)),
      );
    });
  }

  /// The tree of the selected direction, placed below everything else; only
  /// its nodes move.
  Future<void> _treeOfSelected(GrowthSnapshot s) {
    if (_selected.length != 1) return Future.value();
    final tree = treeLayout(
      s.graph,
      s.metrics,
      rootId: _selected.single,
      orderHint: _orderHint,
    );
    if (tree.isEmpty) return Future.value();
    var left = double.infinity, bottom = -double.infinity;
    for (final e in _pos.entries) {
      if (tree.containsKey(e.key)) continue;
      left = math.min(left, e.value.value.dx);
      bottom = math.max(bottom, e.value.value.dy + mindmapNodeHeight);
    }
    final originX = left.isFinite ? left : 100.0;
    final originY = bottom.isFinite ? bottom + 120 : 100.0;
    final minX = tree.values.map((p) => p.$1).reduce(math.min);
    final minY = tree.values.map((p) => p.$2).reduce(math.min);
    final moved = {
      for (final e in tree.entries)
        e.key: (e.value.$1 - minX + originX, e.value.$2 - minY + originY),
    };
    final service = ref.read(metricServiceProvider);
    return _runLayout(s, 'Applied tree of the selected direction', () {
      _fitPending = true;
      _fitOnly = moved.keys.toSet();
      return service.savePositions(moved);
    });
  }

  // ---- nodes ----------------------------------------------------------------

  static bool get _addModifier =>
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isShiftPressed ||
      HardwareKeyboard.instance.isMetaPressed;

  void _setSelection(Set<String> ids) {
    setState(() {
      _selected
        ..clear()
        ..addAll(ids);
      _selectedEdge = null;
    });
  }

  void _selectNode(String id) {
    if (_selected.length == 1 && _selected.contains(id)) return;
    _setSelection({id});
  }

  /// Ctrl/Shift+click: toggles [id] in the selection.
  void _toggleNode(String id) {
    _setSelection(
      _selected.contains(id)
          ? ({..._selected}..remove(id))
          : {..._selected, id},
    );
  }

  /// Pressing a node: an unselected one becomes the only selection (unless
  /// Ctrl/Shift is held, where a click toggles it); a selected one keeps the
  /// selection so the whole group can be dragged.
  void _pressNode(String id) {
    _focus.requestFocus();
    if (_panPointer != null) return;
    if (!_selected.contains(id) && !_addModifier) _selectNode(id);
  }

  /// The nodes a drag that started on [id] moves.
  Set<String> _dragGroup(String id) =>
      _selected.contains(id) ? _selected : {id};

  /// [delta] is already in canvas units: the node sits inside the viewer's
  /// child, so pointer deltas arrive transformed by the zoom.
  void _dragNodes(String id, Offset delta) {
    if (_panPointer != null) return;
    final group = [
      for (final g in _dragGroup(id))
        if (_pos[g] != null) _pos[g]!,
    ];
    if (group.isEmpty) return;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final n in group) {
      minX = math.min(minX, n.value.dx);
      minY = math.min(minY, n.value.dy);
      maxX = math.max(maxX, n.value.dx);
      maxY = math.max(maxY, n.value.dy);
    }
    // One shared delta, limited so that no node leaves the canvas.
    final dx = delta.dx.clamp(-minX, _canvas.width - mindmapNodeWidth - maxX);
    final dy = delta.dy.clamp(-minY, _canvas.height - mindmapNodeHeight - maxY);
    for (final n in group) {
      n.value = n.value + Offset(dx, dy);
    }
    _version.value++;
  }

  void _endDrag(String id) {
    if (_panPointer != null) return;
    ref.read(metricServiceProvider).savePositions({
      for (final g in _dragGroup(id))
        if (_pos[g] != null) g: (_pos[g]!.value.dx, _pos[g]!.value.dy),
    });
  }

  // ---- links ----------------------------------------------------------------

  void _startLink(String id) {
    if (_panPointer != null) return;
    _selectNode(id);
    final p = _pos[id]!.value;
    _rubber.value = (
      from: id,
      to: Offset(p.dx + mindmapNodeWidth, p.dy + mindmapNodeHeight / 2),
    );
  }

  /// [delta] is in canvas units (see [_dragNodes]).
  void _moveLink(Offset delta) {
    final r = _rubber.value;
    if (r == null) return;
    _rubber.value = (from: r.from, to: r.to + delta);
  }

  Future<void> _endLink() async {
    final r = _rubber.value;
    _rubber.value = null;
    if (r == null) return;
    String? target;
    for (final e in _pos.entries) {
      if (e.key == r.from) continue;
      final p = e.value.value;
      if (Rect.fromLTWH(
        p.dx,
        p.dy,
        mindmapNodeWidth,
        mindmapNodeHeight,
      ).contains(r.to)) {
        target = e.key;
      }
    }
    if (target == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(metricServiceProvider)
          .addRelation(fromId: r.from, toId: target);
    } on MetricCycleException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  // ---- edges ----------------------------------------------------------------

  void _tapCanvas(Offset p, List<_Edge> edges) {
    _focus.requestFocus();
    _Edge? hit;
    var best = _edgeHitDistance;
    for (final e in edges) {
      final curve = _edgeCurve(_pos[e.from]?.value, _pos[e.to]?.value);
      if (curve == null) continue;
      final d = curve.distanceTo(p);
      if (d <= best) {
        best = d;
        hit = e;
      }
    }
    setState(() {
      _selectedEdge = hit;
      if (hit != null || !_addModifier) _selected.clear();
    });
  }

  // ---- selection rectangle and panning -----------------------------------------

  bool get _spaceHeld =>
      HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.space);

  void _backgroundDown(PointerDownEvent e) {
    _focus.requestFocus();
    if (e.buttons != kPrimaryButton || _spaceHeld) return;
    _marqueePointer = e.pointer;
    _marqueeStart = e.localPosition;
    _marqueeAdditive = _addModifier;
  }

  void _backgroundMove(PointerMoveEvent e) {
    final start = _marqueeStart;
    if (e.pointer != _marqueePointer || start == null) return;
    if ((e.localPosition - start).distance < 4 && _marquee.value == null) {
      return;
    }
    _marquee.value = Rect.fromPoints(start, e.localPosition);
  }

  void _backgroundUp(PointerEvent e) {
    if (e.pointer != _marqueePointer) return;
    final rect = _marquee.value;
    _marqueePointer = null;
    _marqueeStart = null;
    _marquee.value = null;
    if (rect == null || e is PointerCancelEvent) return;
    final hit = {
      for (final entry in _pos.entries)
        if (Rect.fromLTWH(
          entry.value.value.dx,
          entry.value.value.dy,
          mindmapNodeWidth,
          mindmapNodeHeight,
        ).overlaps(rect))
          entry.key,
    };
    _setSelection(_marqueeAdditive ? {..._selected, ...hit} : hit);
  }

  void _viewportDown(PointerDownEvent e) {
    final pans =
        e.buttons == kMiddleMouseButton ||
        e.buttons == kSecondaryMouseButton ||
        (e.buttons == kPrimaryButton && _spaceHeld);
    if (pans) _panPointer = e.pointer;
  }

  void _viewportMove(PointerMoveEvent e) {
    if (e.pointer != _panPointer) return;
    _controller.value =
        Matrix4.translationValues(e.delta.dx, e.delta.dy, 0) *
        _controller.value;
  }

  void _viewportUp(PointerEvent e) {
    if (e.pointer == _panPointer) _panPointer = null;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (_selected.isEmpty && _selectedEdge == null) {
        return KeyEventResult.ignored;
      }
      _setSelection({});
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyA &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed)) {
      _setSelection(_pos.keys.toSet());
      return KeyEventResult.handled;
    }
    final edge = _selectedEdge;
    if (edge == null) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.delete &&
        event.logicalKey != LogicalKeyboardKey.backspace) {
      return KeyEventResult.ignored;
    }
    _deleteEdge(edge);
    return KeyEventResult.handled;
  }

  void _deleteEdge(_Edge edge) {
    final byId = ref.read(growthSnapshotProvider).value?.byId;
    String label(String id) {
      final m = byId?[id];
      return m == null ? '?' : metricLabel(m.name, m.icon);
    }

    setState(() => _selectedEdge = null);
    runUndoableRemoveRelation(
      context,
      ref,
      fromId: edge.from,
      toId: edge.to,
      description: 'Removed "${label(edge.from)}" → "${label(edge.to)}"',
    );
  }

  // ---- build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ref
        .watch(growthSnapshotProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (s) {
            if (s.metrics.isEmpty) {
              return const Center(child: Text('No growth directions yet.'));
            }
            _selected.removeWhere((id) => !s.byId.containsKey(id));
            _ensureLayout(s);
            _syncPositions(s);
            final edges = _edges(s);
            if (_selectedEdge != null && !edges.contains(_selectedEdge)) {
              _selectedEdge = null;
            }
            return _buildMap(context, s, edges);
          },
        );
  }

  Widget _buildMap(BuildContext context, GrowthSnapshot s, List<_Edge> edges) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final selectedEdge = _selectedEdge;

    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: () => _autoLayout(s),
                        icon: const Icon(Icons.auto_awesome_mosaic_outlined),
                        label: const Text('Auto layout'),
                      ),
                      TextButton.icon(
                        onPressed: () => _tree(s),
                        icon: const Icon(Icons.account_tree),
                        label: const Text('Tree layout'),
                      ),
                      Tooltip(
                        message: _selected.length == 1
                            ? 'Lay the map out in rings around the selected '
                                  'direction'
                            : 'Select exactly one direction first',
                        child: TextButton.icon(
                          onPressed: _selected.length == 1
                              ? () => _radial(s)
                              : null,
                          icon: const Icon(Icons.radar),
                          label: const Text('Radial around selected'),
                        ),
                      ),
                      Tooltip(
                        message: _selected.length == 1
                            ? 'Lay out the selected direction and everything '
                                  'leading into it as a tree below the map'
                            : 'Select exactly one direction first',
                        child: TextButton.icon(
                          onPressed: _selected.length == 1
                              ? () => _treeOfSelected(s)
                              : null,
                          icon: const Icon(Icons.account_tree_outlined),
                          label: const Text('Tree of selected'),
                        ),
                      ),
                    ],
                  ),
                ),
                const Tooltip(
                  message:
                      'Drag on empty space to select; right/middle-drag or '
                      'Space+drag to pan; Ctrl+click adds to selection; '
                      'double-click opens a direction. '
                      'Green arrows lead INTO the selected direction, blue '
                      'arrows go to the directions it leads to',
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.info_outline, size: 20),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.zoom_out),
                  tooltip: 'Zoom out',
                  onPressed: () => _zoomBy(1 / 1.25),
                ),
                IconButton(
                  icon: const Icon(Icons.zoom_in),
                  tooltip: 'Zoom in',
                  onPressed: () => _zoomBy(1.25),
                ),
                IconButton(
                  icon: const Icon(Icons.fit_screen),
                  tooltip: 'Fit all',
                  onPressed: _fitAll,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                _viewport = box.biggest;
                return Listener(
                  onPointerDown: _viewportDown,
                  onPointerMove: _viewportMove,
                  onPointerUp: _viewportUp,
                  onPointerCancel: _viewportUp,
                  child: ClipRect(
                    child: InteractiveViewer(
                      transformationController: _controller,
                      panEnabled: false,
                      constrained: false,
                      minScale: _minScale,
                      maxScale: _maxScale,
                      boundaryMargin: const EdgeInsets.all(1500),
                      child: SizedBox(
                        key: const ValueKey('mindmapCanvas'),
                        width: _canvas.width,
                        height: _canvas.height,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned.fill(
                              child: Listener(
                                behavior: HitTestBehavior.opaque,
                                onPointerDown: _backgroundDown,
                                onPointerMove: _backgroundMove,
                                onPointerUp: _backgroundUp,
                                onPointerCancel: _backgroundUp,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTapUp: (d) =>
                                      _tapCanvas(d.localPosition, edges),
                                  child: RepaintBoundary(
                                    child: CustomPaint(
                                      painter: _EdgePainter(
                                        edges: edges,
                                        positions: _pos,
                                        selected: selectedEdge,
                                        selectedNodes: {..._selected},
                                        highlight: theme.colorScheme.primary,
                                        intoColor: dark
                                            ? Colors.greenAccent.shade400
                                            : Colors.green.shade700,
                                        outOfColor: dark
                                            ? Colors.lightBlueAccent
                                            : Colors.blue.shade700,
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                        repaint: Listenable.merge([
                                          _version,
                                          _rubber,
                                        ]),
                                        rubber: _rubber,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            for (final m in s.metrics)
                              _MindNode(
                                key: ValueKey('mindmapNode-${m.id}'),
                                metric: m,
                                position: _pos[m.id]!,
                                colors: urgencyColors(
                                  s.stats[m.id]?.urgency ?? 0,
                                  dark: dark,
                                ),
                                progress: s.stats[m.id]?.progress ?? 0,
                                selected: _selected.contains(m.id),
                                onTap: () {
                                  _focus.requestFocus();
                                  if (_addModifier) {
                                    _toggleNode(m.id);
                                  } else {
                                    _selectNode(m.id);
                                  }
                                },
                                onOpen: () {
                                  _selectNode(m.id);
                                  GrowthDirectionDialog.show(
                                    context,
                                    existing: m,
                                  );
                                },
                                onSelect: () => _pressNode(m.id),
                                onDrag: (d) => _dragNodes(m.id, d),
                                onDragEnd: () => _endDrag(m.id),
                                onLinkStart: () => _startLink(m.id),
                                onLinkMove: _moveLink,
                                onLinkEnd: _endLink,
                              ),
                            Positioned.fill(
                              child: IgnorePointer(
                                child: ValueListenableBuilder<Rect?>(
                                  valueListenable: _marquee,
                                  builder: (context, r, _) => r == null
                                      ? const SizedBox()
                                      : Stack(
                                          children: [
                                            Positioned.fromRect(
                                              rect: r,
                                              child: DecoratedBox(
                                                decoration: BoxDecoration(
                                                  color: theme
                                                      .colorScheme
                                                      .primary
                                                      .withValues(alpha: 0.15),
                                                  border: Border.all(
                                                    color: theme
                                                        .colorScheme
                                                        .primary,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            ),
                            if (selectedEdge != null)
                              ListenableBuilder(
                                listenable: _version,
                                builder: (context, _) {
                                  final curve = _edgeCurve(
                                    _pos[selectedEdge.from]?.value,
                                    _pos[selectedEdge.to]?.value,
                                  );
                                  if (curve == null) return const SizedBox();
                                  final mid = curve.at(0.5);
                                  return Positioned(
                                    left: mid.dx - 11,
                                    top: mid.dy - 11,
                                    child: SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: Material(
                                        color: theme.colorScheme.errorContainer,
                                        shape: const CircleBorder(),
                                        child: InkWell(
                                          key: const ValueKey(
                                            'mindmapEdgeDelete',
                                          ),
                                          customBorder: const CircleBorder(),
                                          onTap: () =>
                                              _deleteEdge(selectedEdge),
                                          child: Icon(
                                            Icons.close,
                                            size: 14,
                                            color: theme
                                                .colorScheme
                                                .onErrorContainer,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---- geometry ---------------------------------------------------------------

/// An arrow's cubic Bezier from the source box's facing side to the target
/// box's facing side, leaving and entering perpendicular to the boxes.
class _Curve {
  final Offset p0, c1, c2, p3;
  const _Curve(this.p0, this.c1, this.c2, this.p3);

  Offset at(double t) {
    final u = 1 - t;
    return p0 * (u * u * u) +
        c1 * (3 * u * u * t) +
        c2 * (3 * u * t * t) +
        p3 * (t * t * t);
  }

  /// Direction the curve arrives at [p3].
  Offset get endTangent => p3 - c2;

  /// The curve as ~24 line segments' vertices.
  List<Offset> flatten([int segments = 24]) => [
    for (var i = 0; i <= segments; i++) at(i / segments),
  ];

  /// Distance from [p] to the curve.
  double distanceTo(Offset p) {
    final pts = flatten();
    var best = double.infinity;
    for (var i = 0; i < pts.length - 1; i++) {
      best = math.min(best, _distanceToSegment(p, pts[i], pts[i + 1]));
    }
    return best;
  }
}

/// The curve for an arrow from the box at [from] (top-left, canvas coords) to
/// the box at [to]. Null when a node is unknown or the boxes coincide.
_Curve? _edgeCurve(Offset? from, Offset? to) {
  if (from == null || to == null) return null;
  const hw = mindmapNodeWidth / 2, hh = mindmapNodeHeight / 2;
  final a = from + const Offset(hw, hh);
  final b = to + const Offset(hw, hh);
  final d = b - a;
  if (d.distance < 1) return null;
  final Offset p0, p3, n0, n3;
  if (d.dx.abs() >= d.dy.abs()) {
    final right = d.dx > 0;
    p0 = a + Offset(right ? hw : -hw, 0);
    p3 = b + Offset(right ? -hw : hw, 0);
    n0 = Offset(right ? 1 : -1, 0);
    n3 = Offset(right ? -1 : 1, 0);
  } else {
    final down = d.dy > 0;
    p0 = a + Offset(0, down ? hh : -hh);
    p3 = b + Offset(0, down ? -hh : hh);
    n0 = Offset(0, down ? 1 : -1);
    n3 = Offset(0, down ? -1 : 1);
  }
  final k = math.max(48.0, 0.4 * (p3 - p0).distance);
  return _Curve(p0, p0 + n0 * k, p3 + n3 * k, p3);
}

/// The middle of the arrow between two boxes (where the delete button sits).
@visibleForTesting
Offset mindmapEdgeMidpoint(Offset fromTopLeft, Offset toTopLeft) =>
    _edgeCurve(fromTopLeft, toTopLeft)!.at(0.5);

/// How an arrow relates to the selected nodes.
enum MindmapEdgeRole { none, intoSelected, outOfSelected }

/// An arrow runs from a sub-direction ([from]) to the direction it leads to
/// ([to]). Pointing INTO a selected node it is one of that direction's
/// sub-directions; leaving a selected node it points at a direction the
/// selected one leads to. Into wins when both ends are selected.
@visibleForTesting
MindmapEdgeRole mindmapEdgeRole(Set<String> selected, String from, String to) {
  if (selected.contains(to)) return MindmapEdgeRole.intoSelected;
  if (selected.contains(from)) return MindmapEdgeRole.outOfSelected;
  return MindmapEdgeRole.none;
}

/// How opaque an arrow is drawn: see [_EdgePainter].
@visibleForTesting
double mindmapEdgeOpacity({
  required bool anyNodeSelected,
  required bool touchesSelected,
}) {
  if (!anyNodeSelected) return 0.45;
  return touchesSelected ? 1 : 0.15;
}

double _distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 == 0) return (p - a).distance;
  final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

// ---- painting ---------------------------------------------------------------

/// All arrows (and the rubber band) in one painter. Arrows touching a selected
/// node are drawn last in the highlight colour; the others fade.
class _EdgePainter extends CustomPainter {
  final List<_Edge> edges;
  final Map<String, ValueNotifier<Offset>> positions;
  final _Edge? selected;
  final Set<String> selectedNodes;
  final Color color;
  final Color highlight;
  final Color intoColor;
  final Color outOfColor;
  final ValueNotifier<({String from, Offset to})?> rubber;

  _EdgePainter({
    required this.edges,
    required this.positions,
    required this.selected,
    required this.selectedNodes,
    required this.color,
    required this.highlight,
    required this.intoColor,
    required this.outOfColor,
    required this.rubber,
    required Listenable repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final anyNode = selectedNodes.isNotEmpty;
    final hotInto = <_Curve>[];
    final hotOut = <_Curve>[];
    _Curve? chosen;
    final plain = Paint()
      ..color = color.withValues(
        alpha: mindmapEdgeOpacity(
          anyNodeSelected: anyNode,
          touchesSelected: false,
        ),
      )
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (final e in edges) {
      final curve = _edgeCurve(
        positions[e.from]?.value,
        positions[e.to]?.value,
      );
      if (curve == null) continue;
      if (e == selected) {
        chosen = curve;
      } else if (mindmapEdgeRole(selectedNodes, e.from, e.to) ==
          MindmapEdgeRole.intoSelected) {
        hotInto.add(curve);
      } else if (mindmapEdgeRole(selectedNodes, e.from, e.to) ==
          MindmapEdgeRole.outOfSelected) {
        hotOut.add(curve);
      } else {
        _curveArrow(canvas, curve, plain, 8);
      }
    }
    final hotPaint = Paint()
      ..color = highlight
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (final (curves, colour) in [
      (hotOut, outOfColor),
      (hotInto, intoColor),
    ]) {
      final paint = Paint()
        ..color = colour
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke;
      for (final c in curves) {
        _curveArrow(canvas, c, paint, 10);
      }
    }
    if (chosen != null) {
      _curveArrow(
        canvas,
        chosen,
        Paint()
          ..color = highlight
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke,
        12,
      );
    }
    final r = rubber.value;
    final from = r == null ? null : positions[r.from]?.value;
    if (r != null && from != null) {
      final start =
          from + const Offset(mindmapNodeWidth, mindmapNodeHeight / 2);
      canvas.drawLine(start, r.to, hotPaint);
      _head(canvas, r.to, r.to - start, hotPaint.color, 10);
    }
  }

  void _curveArrow(Canvas canvas, _Curve c, Paint paint, double head) {
    canvas.drawPath(
      Path()
        ..moveTo(c.p0.dx, c.p0.dy)
        ..cubicTo(c.c1.dx, c.c1.dy, c.c2.dx, c.c2.dy, c.p3.dx, c.p3.dy),
      paint,
    );
    _head(canvas, c.p3, c.endTangent, paint.color, head);
  }

  void _head(Canvas canvas, Offset tip, Offset dir, Color color, double head) {
    if (dir.distance < 1) return;
    final angle = math.atan2(dir.dy, dir.dx);
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(
        tip.dx - head * math.cos(angle - 0.4),
        tip.dy - head * math.sin(angle - 0.4),
      )
      ..lineTo(
        tip.dx - head * math.cos(angle + 0.4),
        tip.dy - head * math.sin(angle + 0.4),
      )
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_EdgePainter old) =>
      old.edges != edges ||
      old.selected != selected ||
      !setEquals(old.selectedNodes, selectedNodes) ||
      old.color != color ||
      old.highlight != highlight ||
      old.intoColor != intoColor ||
      old.outOfColor != outOfColor;
}

// ---- a node -----------------------------------------------------------------

class _MindNode extends StatelessWidget {
  final GrowthMetric metric;
  final ValueNotifier<Offset> position;
  final ({Color bg, Color fg}) colors;
  final double progress;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onOpen;
  final VoidCallback onSelect;
  final void Function(Offset delta) onDrag;
  final VoidCallback onDragEnd;
  final VoidCallback onLinkStart;
  final void Function(Offset delta) onLinkMove;
  final VoidCallback onLinkEnd;

  const _MindNode({
    super.key,
    required this.metric,
    required this.position,
    required this.colors,
    required this.progress,
    required this.selected,
    required this.onTap,
    required this.onOpen,
    required this.onSelect,
    required this.onDrag,
    required this.onDragEnd,
    required this.onLinkStart,
    required this.onLinkMove,
    required this.onLinkEnd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = (progress / 100).clamp(0.0, 1.0);
    final content = SizedBox(
      width: mindmapNodeWidth + _handleSize / 2,
      height: mindmapNodeHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            width: mindmapNodeWidth,
            height: mindmapNodeHeight,
            child: GestureDetector(
              onTap: onTap,
              onDoubleTap: onOpen,
              onPanDown: (_) => onSelect(),
              onPanUpdate: (d) => onDrag(d.delta),
              onPanEnd: (_) => onDragEnd(),
              onPanCancel: () {},
              child: Container(
                decoration: BoxDecoration(
                  color: colors.bg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected
                        ? theme.colorScheme.onSurface
                        : Colors.black26,
                    width: selected ? 2 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 12, 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            metricLabel(metric.name, metric.icon),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.fg,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 4,
                      child: ColoredBox(
                        color: Colors.grey.withValues(alpha: 0.5),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            key: ValueKey('mindmapProgress-${metric.id}'),
                            widthFactor: fraction,
                            heightFactor: 1,
                            child: const ColoredBox(color: Color(0xFF2E9E44)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: mindmapNodeWidth - _handleSize / 2,
            top: (mindmapNodeHeight - _handleSize) / 2,
            width: _handleSize,
            height: _handleSize,
            child: GestureDetector(
              key: ValueKey('mindmapLinkHandle-${metric.id}'),
              onPanStart: (_) => onLinkStart(),
              onPanUpdate: (d) => onLinkMove(d.delta),
              onPanEnd: (_) => onLinkEnd(),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.surface,
                  border: Border.all(
                    color: theme.colorScheme.onSurface,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return ValueListenableBuilder<Offset>(
      valueListenable: position,
      child: content,
      builder: (context, p, child) =>
          Positioned(left: p.dx, top: p.dy, child: child!),
    );
  }
}
