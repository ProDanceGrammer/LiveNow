import '../search_targets.dart';
import '../shortcut_keys.dart';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals, setEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/direction_search.dart';
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
import '../calendar_fullscreen.dart';
import '../layout.dart';
import '../providers.dart';
import '../theme/glass_theme.dart';
import '../touchpad.dart';
import '../undo.dart';
import '../urgency_colors.dart';
import 'direction_menu.dart';
import 'glass.dart';
import 'growth_direction_dialog.dart';

const double _handleSize = 16;
const double _edgeHitDistance = 8;
const double _minScale = 0.04;
const double _maxScale = 30;
const double _canvasPadding = 600;

/// Below this zoom a node's text is unreadable, so a node is drawn as a plain
/// coloured box (no text, progress bar or link handle).
const double mindmapLodScale = 0.35;

/// Ordinary (not highlighted) arrows lose their arrowhead below this zoom.
const double _arrowHeadScale = 0.25;

/// Nodes up to this many viewports beyond each viewport edge are still built,
/// so panning does not make boxes pop in.
const double _cullMargin = 0.5;

typedef _Edge = ({String from, String to});

/// [c] with its HSL lightness set to [lightness]: the pastel glass accents,
/// darkened (or lifted) until they read on a coloured node / the glass panel.
Color _shade(Color c, double lightness) =>
    HSLColor.fromColor(c).withLightness(lightness).toColor();

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

class _MindmapViewState extends ConsumerState<MindmapView>
    with SearchTargetState<MindmapView> {
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

  /// Hash of the graph the cached [_layout] was computed for (0 = none).
  int _layoutSignature = 0;

  /// The snapshot [_edgeList] / positions were derived from: all of that is
  /// redone only when a new snapshot arrives, not on every rebuild.
  GrowthSnapshot? _snapshot;
  List<_Edge> _edgeList = const [];

  /// The nodes that currently exist as widgets (the rest are culled: they only
  /// live in [_pos]) and whether they are drawn as lite boxes. Changed only
  /// by [_refreshView].
  Set<String> _visible = const {};
  bool _lod = false;

  /// True until the first fit-all ran: nodes are not built before that, as the
  /// first frame would draw them all at the wrong zoom.
  bool _firstFit = true;

  /// The node whose drag is running; kept built even if it leaves the view.
  String? _dragId;

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

  /// The search box above the map (toolbar magnifier): typing lists matching
  /// directions, tapping one selects it and centres the map on it.
  bool _searchOpen = false;
  final _searchText = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTransform);
    registerSearchTarget();
  }

  // Ctrl+F: open the search box (it sits behind the magnifier) and focus it.
  @override
  void openSearch() {
    if (!_searchOpen) setState(() => _searchOpen = true);
    focusSearchField(_searchFocus, _searchText);
  }

  @override
  void dispose() {
    unregisterSearchTarget();
    _searchFocus.dispose();
    _controller.removeListener(_onTransform);
    _controller.dispose();
    _focus.dispose();
    _searchText.dispose();
    _version.dispose();
    _rubber.dispose();
    _marquee.dispose();
    for (final n in _pos.values) {
      n.dispose();
    }
    super.dispose();
  }

  // The x scale: getMaxScaleOnAxis would include the z axis (always 1) and
  // report 1 for every zoom-out.
  double get _scale => _controller.value.storage[0];

  // ---- data -> positions ----------------------------------------------------

  /// Recomputes the automatic layout when the graph changed (only needed while
  /// some node has no saved position).
  void _ensureLayout(GrowthSnapshot s, List<_Edge> edges) {
    if (s.metrics.every((m) => m.posX != null && m.posY != null)) return;
    final signature = Object.hash(
      Object.hashAll([for (final m in s.metrics) m.id]),
      Object.hashAll(edges),
    );
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
    var maxX = 0.0, maxY = 0.0;
    for (final m in s.metrics) {
      final t = _target(m);
      final n = _pos[m.id];
      if (n == null) {
        _pos[m.id] = ValueNotifier(t);
        _applied[m.id] = t;
      } else if (_applied[m.id] != t) {
        changed = true;
      }
      maxX = math.max(maxX, t.dx);
      maxY = math.max(maxY, t.dy);
    }
    _canvas = Size(
      math.max(2000, maxX + mindmapNodeWidth + _canvasPadding),
      math.max(1500, maxY + mindmapNodeHeight + _canvasPadding),
    );
    if (changed || _fitPending) _scheduleSync();
  }

  /// After this frame: moves the notifiers to the saved/laid-out positions and
  /// runs a pending fit-all.
  void _scheduleSync() {
    if (_syncScheduled) return;
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
        _firstFit = false;
        final only = _fitOnly;
        _fitOnly = null;
        _fitAll(only: only);
      }
      if (_refreshView()) setState(() {});
    });
  }

  List<_Edge> _edges(GrowthSnapshot s) => [
    for (final m in s.metrics)
      for (final d in s.graph.dependsOnOf(m.id))
        if (s.byId.containsKey(d)) (from: d, to: m.id),
  ];

  // ---- culling and level of detail ----------------------------------------------

  void _onTransform() {
    if (mounted && _refreshView()) setState(() {});
  }

  /// Recomputes which nodes need a widget and the level of detail from the
  /// current zoom/pan and positions. Returns whether either changed, so the
  /// caller only rebuilds when it must (never per pointer-move frame).
  bool _refreshView() {
    final lod = _scale < mindmapLodScale;
    final ids = _visibleIds();
    final changed = lod != _lod || !setEquals(ids, _visible);
    _lod = lod;
    if (changed) _visible = ids;
    return changed;
  }

  Set<String> _visibleIds() {
    if (_firstFit && _fitPending) return const {};
    final inv = Matrix4.tryInvert(_controller.value);
    Rect? area;
    if (_viewport != Size.zero && inv != null) {
      final view = MatrixUtils.transformRect(inv, Offset.zero & _viewport);
      area = Rect.fromLTRB(
        view.left - view.width * _cullMargin,
        view.top - view.height * _cullMargin,
        view.right + view.width * _cullMargin,
        view.bottom + view.height * _cullMargin,
      );
    }
    final ids = <String>{};
    for (final e in _pos.entries) {
      final p = e.value.value;
      if (area == null ||
          area.overlaps(
            Rect.fromLTWH(
              p.dx,
              p.dy,
              mindmapNodeWidth + _handleSize / 2,
              mindmapNodeHeight,
            ),
          )) {
        ids.add(e.key);
      }
    }
    // A gesture in flight must not lose its widget.
    final drag = _dragId, link = _rubber.value?.from;
    if (drag != null && _pos.containsKey(drag)) ids.add(drag);
    if (link != null && _pos.containsKey(link)) ids.add(link);
    return ids;
  }

  // ---- touchpad ---------------------------------------------------------------
  // Two-finger swipe moves the canvas, a pinch zooms about the mouse cursor,
  // Ctrl + two-finger swipe zooms; the mouse wheel zooms about the pointer. All
  // of it is done HERE, not by the InteractiveViewer: its pinch focal point is
  // the gesture's start position plus the fingers' pan, which is not where the
  // cursor is (it zoomed toward a corner), and our own pan in the same events
  // fought its reference-point correction. The viewer's scaling stays OFF
  // ([_touchScale]) except for a finger on a touch screen, where its pinch is
  // right.

  /// The mouse cursor in viewport coordinates (the touchpad moves it too);
  /// null until it has been seen over the map.
  Offset? _cursor;

  /// Whether the viewer may scale (a touch pinch). Off for a mouse / touchpad,
  /// switched on by the first touch and off again when the cursor hovers: set
  /// BEFORE a gesture, because a rebuild during it would be too late.
  bool _touchScale = false;

  /// The cumulative scale of the gesture at its last update.
  double _pzScale = 1;

  bool get _invertX => ref.read(touchpadInvertXProvider);
  bool get _invertY => ref.read(touchpadInvertYProvider);

  void _panCanvas(Offset delta) {
    final d = Offset(_invertX ? -delta.dx : delta.dx, _invertY ? -delta.dy : delta.dy);
    _controller.value = pannedBy(_controller.value, d);
  }

  /// Scroll events over the map. A notched mouse wheel zooms about the pointer
  /// (as the viewer used to: e^(-dy/200) per notch); a touchpad swipe pans, and
  /// with Ctrl held it zooms about the pointer.
  void _onViewportSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final d = event.scrollDelta;
    final focal = _controller.toScene(event.localPosition);
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (!isTouchpadScroll(event)) {
        _controller.value = zoomedAround(
          _controller.value,
          focal,
          math.exp(-d.dy / 200),
          min: _minScale,
          max: _maxScale,
        );
      } else if (isPrimaryPressed()) {
        _controller.value = zoomedAround(
          _controller.value,
          focal,
          zoomFactorFor(d.dy),
          min: _minScale,
          max: _maxScale,
        );
      } else {
        _panCanvas(Offset(-d.dx, -d.dy));
      }
    });
  }

  void _onPanZoomStart(PointerPanZoomStartEvent e) {
    _pzScale = 1;
    _cursor ??= e.localPosition;
  }

  void _onPanZoom(PointerPanZoomUpdateEvent e) {
    // Where the zoom is anchored: the cursor the user sees, as a scene point.
    final focal = _controller.toScene(_cursor ?? e.localPosition);
    if (isPrimaryPressed()) {
      // Ctrl + swipe = zoom about the cursor by the vertical travel.
      _controller.value = zoomedAround(
        _controller.value,
        focal,
        zoomFactorFor(-e.panDelta.dy),
        min: _minScale,
        max: _maxScale,
      );
      return;
    }
    // The pinch: the change since the last update, about the cursor.
    final ratio = e.scale / _pzScale;
    _pzScale = e.scale;
    if (ratio != 1 && ratio.isFinite && ratio > 0) {
      _controller.value = zoomedAround(
        _controller.value,
        focal,
        ratio,
        min: _minScale,
        max: _maxScale,
      );
    }
    _panCanvas(e.panDelta);
  }

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

  /// Search result tapped: selects the direction and centres the map on it, at
  /// least readable (below `mindmapLodScale` a node is only a coloured box).
  void _focusNode(String id) {
    final n = _pos[id];
    if (n == null || _viewport == Size.zero) return;
    _selectNode(id);
    final scale = math.max(_scale, 0.8).clamp(_minScale, _maxScale).toDouble();
    final cx = n.value.dx + mindmapNodeWidth / 2;
    final cy = n.value.dy + mindmapNodeHeight / 2;
    _controller.value =
        Matrix4.translationValues(
          _viewport.width / 2 - scale * cx,
          _viewport.height / 2 - scale * cy,
          0,
        ) *
        Matrix4.diagonal3Values(scale, scale, 1);
    // The keyboard goes away so the map is visible; the list stays for the
    // next pick.
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) _searchText.clear();
    });
  }

  Widget _searchPanel(GrowthSnapshot s) {
    final results = searchDirections(s.metrics, _searchText.text);
    final glass = context.glass;
    final height = MediaQuery.sizeOf(context).height;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: GlassSurface(
        radius: 16,
        shadow: false,
        blurWindow: false,
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 4, 0),
                child: TextField(
                  key: const ValueKey('mindmap-search-field'),
                  controller: _searchText,
                  focusNode: _searchFocus,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Find a direction',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Close search',
                      onPressed: _toggleSearch,
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              if (_searchText.text.trim().isNotEmpty)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: (height * 0.28).clamp(120.0, 260.0),
                  ),
                  child: results.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(14),
                          child: Text(
                            'No direction matches.',
                            key: const ValueKey('mindmap-search-empty'),
                            style: TextStyle(color: glass.textSecondary),
                          ),
                        )
                      : ListView(
                          shrinkWrap: true,
                          children: [
                            for (final m in results)
                              ListTile(
                                key: ValueKey('mindmap-result-${m.id}'),
                                dense: true,
                                selected: _selected.contains(m.id),
                                title: Text(
                                  metricLabel(m.name, m.icon),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () => _focusNode(m.id),
                              ),
                          ],
                        ),
                ),
            ],
          ),
        ),
      ),
    );
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
      _layoutSignature = 0;
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
      isPrimaryPressed() ||
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

  /// Right-click on a node: Open / Duplicate.
  Future<void> _nodeMenu(GrowthMetric m, Offset at) {
    _selectNode(m.id);
    return showDirectionMenu(context, ref, m, at);
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
    _dragId = id;
    // Culled members of a dragged selection may arrive in view.
    if (_refreshView()) setState(() {});
  }

  void _endDrag(String id) {
    _dragId = null;
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
    // A finger on empty space pans the map (there is no mouse to draw a
    // selection rectangle with); pinching zooms, via the InteractiveViewer.
    if (e.kind == PointerDeviceKind.touch) {
      _panPointer = e.pointer;
      return;
    }
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

  void _viewportHover(PointerHoverEvent e) {
    _cursor = e.localPosition;
    if (_touchScale) setState(() => _touchScale = false);
  }

  void _viewportDown(PointerDownEvent e) {
    // The first finger enables the viewer's pinch BEFORE a second one lands.
    if (e.kind == PointerDeviceKind.touch && !_touchScale) {
      setState(() => _touchScale = true);
    }
    final pans =
        e.buttons == kMiddleMouseButton ||
        e.buttons == kSecondaryMouseButton ||
        (e.buttons == kPrimaryButton && _spaceHeld);
    if (pans) _panPointer = e.pointer;
  }

  void _viewportMove(PointerMoveEvent e) {
    _cursor = e.localPosition;
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
        (isPrimaryPressed() ||
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
            if (!identical(s, _snapshot)) {
              // Everything derived from the data is redone per snapshot only.
              _snapshot = s;
              final fresh = _edges(s);
              if (!listEquals(fresh, _edgeList)) _edgeList = fresh;
              _ensureLayout(s, _edgeList);
              _syncPositions(s);
            } else if (_fitPending) {
              _scheduleSync();
            }
            final edges = _edgeList;
            if (_selectedEdge != null && !edges.contains(_selectedEdge)) {
              _selectedEdge = null;
            }
            return _buildMap(context, s, edges);
          },
        );
  }

  /// Phone toolbar: one row of icon buttons (layouts, zoom, fit); there is no
  /// room for the text labels, and the keyboard hint does not apply.
  Widget _phoneToolbar(GrowthSnapshot s) {
    Widget button(IconData icon, String tip, VoidCallback? onPressed) =>
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(icon),
          tooltip: tip,
          onPressed: onPressed,
        );
    final one = _selected.length == 1;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        button(
          _searchOpen ? Icons.search_off : Icons.search,
          _searchOpen ? 'Close search' : 'Find a direction',
          _toggleSearch,
        ),
        button(
          Icons.auto_awesome_mosaic_outlined,
          'Auto layout',
          () => _autoLayout(s),
        ),
        button(Icons.account_tree, 'Tree layout', () => _tree(s)),
        button(
          Icons.radar,
          'Radial around selected',
          one ? () => _radial(s) : null,
        ),
        button(
          Icons.account_tree_outlined,
          'Tree of selected',
          one ? () => _treeOfSelected(s) : null,
        ),
        // Zoom is by pinch on a phone (the buttons made room for full screen).
        button(Icons.fit_screen, 'Fit all', _fitAll),
        button(
          ref.watch(phoneMindmapFullProvider)
              ? Icons.fullscreen_exit
              : Icons.fullscreen,
          ref.watch(phoneMindmapFullProvider)
              ? 'Leave full screen'
              : 'Full screen',
          () => ref.read(phoneMindmapFullProvider.notifier).state = !ref.read(
            phoneMindmapFullProvider,
          ),
        ),
      ],
    );
  }

  Widget _buildMap(BuildContext context, GrowthSnapshot s, List<_Edge> edges) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final needsData = ref.watch(emptyDirectionIdsProvider) ?? const IdSet({});
    final selectedEdge = _selectedEdge;
    final glass = context.glass;

    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: GlassSurface(
              radius: 20,
              shadow: false,
              blurWindow: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: usePhoneLayout(context)
                    ? _phoneToolbar(s)
                    : Row(
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                TextButton.icon(
                                  onPressed: () => _autoLayout(s),
                                  icon: const Icon(
                                    Icons.auto_awesome_mosaic_outlined,
                                  ),
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
                                    icon: const Icon(
                                      Icons.account_tree_outlined,
                                    ),
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
                            key: const ValueKey('mindmap-search-toggle'),
                            icon: Icon(
                              _searchOpen ? Icons.search_off : Icons.search,
                            ),
                            tooltip: _searchOpen
                                ? 'Close search'
                                : 'Find a direction',
                            onPressed: _toggleSearch,
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
            ),
          ),
          if (_searchOpen) _searchPanel(s),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: GlassSurface(
                radius: GlassTheme.radiusPanel,
                shadow: false,
                blurWindow: false,
                child: LayoutBuilder(
                  builder: (context, box) {
                    _viewport = box.biggest;
                    _refreshView();
                    if (_fitPending) _scheduleSync();
                    return Listener(
                      onPointerDown: _viewportDown,
                      onPointerMove: _viewportMove,
                      onPointerUp: _viewportUp,
                      onPointerCancel: _viewportUp,
                      onPointerHover: _viewportHover,
                      onPointerSignal: _onViewportSignal,
                      onPointerPanZoomStart: _onPanZoomStart,
                      onPointerPanZoomUpdate: _onPanZoom,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          GlassTheme.radiusPanel,
                        ),
                        child: InteractiveViewer(
                          transformationController: _controller,
                          panEnabled: false,
                          // Only for a touch pinch: see [_touchScale].
                          scaleEnabled: _touchScale,
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
                                            highlight:
                                                theme.colorScheme.primary,
                                            intoColor: _shade(
                                              glass.green,
                                              dark ? 0.62 : 0.30,
                                            ),
                                            outOfColor: _shade(
                                              glass.blue,
                                              dark ? 0.66 : 0.42,
                                            ),
                                            color: Color.lerp(
                                              theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                              glass.blue,
                                              0.35,
                                            )!,
                                            repaint: Listenable.merge([
                                              _version,
                                              _rubber,
                                              _controller,
                                            ]),
                                            rubber: _rubber,
                                            controller: _controller,
                                            viewport: _viewport,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                for (final m in s.metrics)
                                  if (_visible.contains(m.id))
                                    _MindNode(
                                      key: ValueKey('mindmapNode-${m.id}'),
                                      lite: _lod,
                                      metric: m,
                                      position: _pos[m.id]!,
                                      // White = "fill me in": no dated
                                      // action in its period or the future.
                                      colors: needsData.contains(m.id)
                                          ? emptyColors(dark: dark)
                                          : urgencyColors(
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
                                      onMenu: (p) => _nodeMenu(m, p),
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
                                                          .withValues(
                                                            alpha: 0.15,
                                                          ),
                                                      border: Border.all(
                                                        color: theme
                                                            .colorScheme
                                                            .primary
                                                            .withValues(
                                                              alpha: 0.8,
                                                            ),
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
                                      if (curve == null) {
                                        return const SizedBox();
                                      }
                                      final mid = curve.at(0.5);
                                      return Positioned(
                                        left: mid.dx - 11,
                                        top: mid.dy - 11,
                                        child: SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: Material(
                                            color: theme
                                                .colorScheme
                                                .errorContainer,
                                            shape: const CircleBorder(),
                                            child: InkWell(
                                              key: const ValueKey(
                                                'mindmapEdgeDelete',
                                              ),
                                              customBorder:
                                                  const CircleBorder(),
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

/// The control polygon's bounds (a Bezier stays inside its convex hull),
/// grown for the stroke and arrowhead.
Rect _curveBounds(_Curve c) {
  final xs = [c.p0.dx, c.c1.dx, c.c2.dx, c.p3.dx];
  final ys = [c.p0.dy, c.c1.dy, c.c2.dy, c.p3.dy];
  return Rect.fromLTRB(
    xs.reduce(math.min),
    ys.reduce(math.min),
    xs.reduce(math.max),
    ys.reduce(math.max),
  ).inflate(16);
}

/// All arrows (and the rubber band) in one painter. Arrows touching a selected
/// node are drawn last in the highlight colour; the others fade. Each style
/// (ordinary, into, out of, selected) is ONE path and one drawPath, and arrows
/// outside the visible part of the canvas are skipped.
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
  final TransformationController controller;
  final Size viewport;

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
    required this.controller,
    required this.viewport,
    required Listenable repaint,
  }) : super(repaint: repaint);

  /// The visible canvas area (null = everything), a little inflated.
  Rect? _visibleArea() {
    final inv = Matrix4.tryInvert(controller.value);
    if (inv == null || viewport == Size.zero) return null;
    return MatrixUtils.transformRect(inv, Offset.zero & viewport).inflate(40);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = controller.value.storage[0];
    final area = _visibleArea();
    final anyNode = selectedNodes.isNotEmpty;
    final plainCurves = Path(), plainHeads = Path();
    final intoCurves = Path(), intoHeads = Path();
    final outCurves = Path(), outHeads = Path();
    final chosenCurves = Path(), chosenHeads = Path();
    var drawnPlain = false, drawnInto = false, drawnOut = false;
    var drawnChosen = false;
    final plainHeadsOn = scale >= _arrowHeadScale;
    for (final e in edges) {
      final curve = _edgeCurve(
        positions[e.from]?.value,
        positions[e.to]?.value,
      );
      if (curve == null) continue;
      if (area != null && !area.overlaps(_curveBounds(curve))) continue;
      if (e == selected) {
        _addCurve(chosenCurves, chosenHeads, curve, 12);
        drawnChosen = true;
        continue;
      }
      switch (mindmapEdgeRole(selectedNodes, e.from, e.to)) {
        case MindmapEdgeRole.intoSelected:
          _addCurve(intoCurves, intoHeads, curve, 10);
          drawnInto = true;
        case MindmapEdgeRole.outOfSelected:
          _addCurve(outCurves, outHeads, curve, 10);
          drawnOut = true;
        case MindmapEdgeRole.none:
          _addCurve(plainCurves, plainHeads, curve, 8, withHead: plainHeadsOn);
          drawnPlain = true;
      }
    }
    if (drawnPlain) {
      final c = color.withValues(
        alpha: mindmapEdgeOpacity(
          anyNodeSelected: anyNode,
          touchesSelected: false,
        ),
      );
      _flush(canvas, plainCurves, plainHeads, c, 1);
    }
    if (drawnOut) _flush(canvas, outCurves, outHeads, outOfColor, 2.5);
    if (drawnInto) _flush(canvas, intoCurves, intoHeads, intoColor, 2.5);
    if (drawnChosen) {
      _flush(canvas, chosenCurves, chosenHeads, highlight, 3);
    }
    final r = rubber.value;
    final from = r == null ? null : positions[r.from]?.value;
    if (r != null && from != null) {
      final start =
          from + const Offset(mindmapNodeWidth, mindmapNodeHeight / 2);
      final heads = Path();
      _addHead(heads, r.to, r.to - start, 10);
      canvas.drawLine(
        start,
        r.to,
        Paint()
          ..color = highlight
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
      canvas.drawPath(heads, Paint()..color = highlight);
    }
  }

  void _flush(Canvas canvas, Path curves, Path heads, Color c, double width) {
    canvas.drawPath(
      curves,
      Paint()
        ..color = c
        ..strokeWidth = width
        ..style = PaintingStyle.stroke,
    );
    canvas.drawPath(heads, Paint()..color = c);
  }

  void _addCurve(
    Path curves,
    Path heads,
    _Curve c,
    double size, {
    bool withHead = true,
  }) {
    curves
      ..moveTo(c.p0.dx, c.p0.dy)
      ..cubicTo(c.c1.dx, c.c1.dy, c.c2.dx, c.c2.dy, c.p3.dx, c.p3.dy);
    if (withHead) _addHead(heads, c.p3, c.endTangent, size);
  }

  void _addHead(Path path, Offset tip, Offset dir, double head) {
    if (dir.distance < 1) return;
    final angle = math.atan2(dir.dy, dir.dx);
    path
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
  }

  @override
  bool shouldRepaint(_EdgePainter old) =>
      old.edges != edges ||
      old.selected != selected ||
      old.viewport != viewport ||
      !setEquals(old.selectedNodes, selectedNodes) ||
      old.color != color ||
      old.highlight != highlight ||
      old.intoColor != intoColor ||
      old.outOfColor != outOfColor;
}

// ---- a node -----------------------------------------------------------------

class _MindNode extends StatelessWidget {
  final GrowthMetric metric;

  /// Far zoomed out: just a coloured box, no text, progress bar or handle.
  final bool lite;
  final ValueNotifier<Offset> position;
  final ({Color bg, Color fg}) colors;
  final double progress;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onOpen;
  final void Function(Offset globalPosition) onMenu;
  final VoidCallback onSelect;
  final void Function(Offset delta) onDrag;
  final VoidCallback onDragEnd;
  final VoidCallback onLinkStart;
  final void Function(Offset delta) onLinkMove;
  final VoidCallback onLinkEnd;

  const _MindNode({
    super.key,
    required this.metric,
    required this.lite,
    required this.position,
    required this.colors,
    required this.progress,
    required this.selected,
    required this.onTap,
    required this.onOpen,
    required this.onMenu,
    required this.onSelect,
    required this.onDrag,
    required this.onDragEnd,
    required this.onLinkStart,
    required this.onLinkMove,
    required this.onLinkEnd,
  });

  GestureDetector _gestures(Widget child) => GestureDetector(
    supportedDevices: kNoTrackpadDevices,
    onTap: onTap,
    onDoubleTap: onOpen,
    onSecondaryTapUp: (d) => onMenu(d.globalPosition),
    onPanDown: (_) => onSelect(),
    onPanUpdate: (d) => onDrag(d.delta),
    onPanEnd: (_) => onDragEnd(),
    onPanCancel: () {},
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    if (lite) return _buildLite(theme, glass);
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
            child: _gestures(
              Container(
                decoration: BoxDecoration(
                  color: colors.bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    // The node's own colour, darker (lighter on dark): a
                    // neutral line could be read as data.
                    color: selected
                        ? theme.colorScheme.onSurface
                        : urgencyOutline(colors.bg, dark: glass.dark),
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
                      // The strip uses the node's text colour, so it reads on
                      // every fill (a green fill vanished on green/yellow).
                      child: ColoredBox(
                        color: colors.fg.withValues(alpha: 0.18),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            key: ValueKey('mindmapProgress-${metric.id}'),
                            widthFactor: fraction,
                            heightFactor: 1,
                            child: ColoredBox(
                              color: colors.fg.withValues(alpha: 0.7),
                            ),
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
                  color: Colors.white,
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.7),
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

  /// The cheap variant: one DecoratedBox, same gestures.
  Widget _buildLite(ThemeData theme, GlassTheme glass) {
    final box = _gestures(
      DecoratedBox(
        decoration: BoxDecoration(
          color: colors.bg,
          border: Border.all(
            color: selected
                ? theme.colorScheme.onSurface
                : urgencyOutline(colors.bg, dark: glass.dark),
            width: selected ? 2 : 1,
          ),
        ),
      ),
    );
    return ValueListenableBuilder<Offset>(
      valueListenable: position,
      child: box,
      builder: (context, p, child) => Positioned(
        left: p.dx,
        top: p.dy,
        width: mindmapNodeWidth,
        height: mindmapNodeHeight,
        child: child!,
      ),
    );
  }
}
