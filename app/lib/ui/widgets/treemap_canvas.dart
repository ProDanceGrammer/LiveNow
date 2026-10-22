import '../shortcut_keys.dart';
import 'dart:math' as math;

import 'package:flutter/gestures.dart'
    show
        GestureBinding,
        PointerEvent,
        PointerScrollEvent,
        PointerSignalEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/treemap_layout.dart';

/// Gap between two blocks (px, before zoom).
const double kTreemapGap = 1.5;

/// A zoomable, scrollable treemap, shared by both modes. The blocks are laid out
/// ONCE for the window size (`squarify` is scale-invariant) and every rectangle
/// is multiplied by the zoom, so zooming makes blocks bigger and small ones get
/// their text. Zoom: Ctrl+wheel, Ctrl+= / Ctrl+- / Ctrl+0, two-finger pinch or the
/// buttons; plain wheel scrolls up/down and Shift+wheel sideways. Only blocks
/// near the viewport get a widget.
class TreemapCanvas extends StatefulWidget {
  const TreemapCanvas({
    super.key,
    required this.items,
    required this.tileBuilder,
  });

  final List<TreemapItem> items;

  /// Builds one block; [rect] is already zoomed and without the gap.
  final Widget Function(String id, Rect rect) tileBuilder;

  @override
  State<TreemapCanvas> createState() => TreemapCanvasState();
}

class TreemapCanvasState extends State<TreemapCanvas> {
  final _h = ScrollController();
  final _v = ScrollController();
  final _focus = FocusNode(debugLabel: 'treemap-canvas');
  final _pointers = <int, Offset>{};

  double _zoom = 1;
  Size _viewport = Size.zero;
  Set<String> _visible = const {};
  bool _pinching = false;
  double _pinchBase = 0;
  double _wheelAccumulated = 0;
  static const _wheelPixelsPerStep = 100.0;

  /// The current zoom (tests read it).
  double get zoom => _zoom;

  @override
  void initState() {
    super.initState();
    _h.addListener(_onScroll);
    _v.addListener(_onScroll);
  }

  @override
  void dispose() {
    _h.dispose();
    _v.dispose();
    _focus.dispose();
    super.dispose();
  }

  double _offset(ScrollController c) => c.hasClients ? c.offset : 0;

  List<TreemapRect> _zoomed(List<TreemapRect> rects) => [
    for (final r in rects)
      TreemapRect(r.id, r.x * _zoom, r.y * _zoom, r.w * _zoom, r.h * _zoom),
  ];

  List<TreemapRect> _near(List<TreemapRect> rects) => visibleTreemapRects(
    _zoomed(rects),
    left: _offset(_h),
    top: _offset(_v),
    width: _viewport.width,
    height: _viewport.height,
    margin: math.max(_viewport.width, _viewport.height) / 2,
  );

  void _onScroll() {
    final rects = squarify(
      widget.items,
      width: _viewport.width,
      height: _viewport.height,
    );
    final ids = {for (final r in _near(rects)) r.id};
    if (ids.length != _visible.length || !ids.containsAll(_visible)) {
      setState(() {});
    }
  }

  /// Zoom to [target], keeping the content under [focal] (viewport pixels) where
  /// it is.
  void _setZoom(double target, Offset focal) {
    if (target == _zoom) return;
    final old = _zoom;
    final cx = (_offset(_h) + focal.dx) / old;
    final cy = (_offset(_v) + focal.dy) / old;
    setState(() => _zoom = target);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      void jump(ScrollController c, double content, double focalPx) {
        if (!c.hasClients) return;
        c.jumpTo(
          (content * target - focalPx).clamp(0.0, c.position.maxScrollExtent),
        );
      }

      jump(_h, cx, focal.dx);
      jump(_v, cy, focal.dy);
    });
  }

  void _step(int dir, [Offset? focal]) => _setZoom(
    stepTreemapZoom(_zoom, dir),
    focal ?? Offset(_viewport.width / 2, _viewport.height / 2),
  );

  void _reset() => _setZoom(1, Offset(_viewport.width / 2, _viewport.height / 2));

  void _onWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        !isPrimaryPressed()) {
      return;
    }
    // The point under the pointer, in viewport pixels.
    final focal = Offset(
      event.localPosition.dx - _offset(_h),
      event.localPosition.dy - _offset(_v),
    );
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      _wheelAccumulated += event.scrollDelta.dy;
      final steps = (_wheelAccumulated / _wheelPixelsPerStep).truncate();
      if (steps == 0) return;
      _wheelAccumulated -= steps * _wheelPixelsPerStep;
      for (var i = 0; i < steps.abs(); i++) {
        // Wheel up (negative) zooms in.
        _step(steps < 0 ? 1 : -1, focal);
      }
    });
  }

  double _pinchDistance() {
    final p = _pointers.values.toList();
    return (p[0] - p[1]).distance;
  }

  void _down(PointerEvent e) {
    _focus.requestFocus();
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 2) {
      _pinchBase = _pinchDistance();
      setState(() => _pinching = true);
    }
  }

  void _move(PointerEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length != 2 || _pinchBase <= 0) return;
    final ratio = _pinchDistance() / _pinchBase;
    if (ratio > 1.3 || ratio < 0.77) {
      final p = _pointers.values.toList();
      final mid = (p[0] + p[1]) / 2;
      _step(
        ratio > 1 ? 1 : -1,
        Offset(mid.dx - _offset(_h), mid.dy - _offset(_v)),
      );
      _pinchBase = _pinchDistance();
    }
  }

  void _up(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pinching && _pointers.length < 2) setState(() => _pinching = false);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        _viewport = Size(box.maxWidth, box.maxHeight);
        final rects = squarify(
          widget.items,
          width: _viewport.width,
          height: _viewport.height,
        );
        final near = _near(rects);
        _visible = {for (final r in near) r.id};
        final physics = _pinching
            ? const NeverScrollableScrollPhysics()
            : null;
        final canvas = SizedBox(
          width: _viewport.width * _zoom,
          height: _viewport.height * _zoom,
          child: Stack(
            children: [
              for (final r in near)
                Positioned(
                  key: ValueKey('treemap-canvas-${r.id}'),
                  left: r.x + kTreemapGap / 2,
                  top: r.y + kTreemapGap / 2,
                  width: math.max(0, r.w - kTreemapGap),
                  height: math.max(0, r.h - kTreemapGap),
                  child: widget.tileBuilder(
                    r.id,
                    Rect.fromLTWH(
                      r.x,
                      r.y,
                      math.max(0, r.w - kTreemapGap),
                      math.max(0, r.h - kTreemapGap),
                    ),
                  ),
                ),
            ],
          ),
        );
        return CallbackShortcuts(
          bindings: {
            for (final k in [LogicalKeyboardKey.equal, LogicalKeyboardKey.add,
              LogicalKeyboardKey.numpadAdd])
              primaryActivator(k): () => _step(1),
            for (final k in [LogicalKeyboardKey.minus,
              LogicalKeyboardKey.numpadSubtract])
              primaryActivator(k): () => _step(-1),
            for (final k in [LogicalKeyboardKey.digit0,
              LogicalKeyboardKey.numpad0])
              primaryActivator(k): _reset,
          },
          child: Focus(
            focusNode: _focus,
            child: Stack(
              children: [
                Listener(
                  onPointerDown: _down,
                  onPointerMove: _move,
                  onPointerUp: _up,
                  onPointerCancel: _up,
                  onPointerSignal: _onWheel,
                  child: Scrollbar(
                    controller: _v,
                    child: SingleChildScrollView(
                      controller: _v,
                      physics: physics,
                      child: SingleChildScrollView(
                        controller: _h,
                        scrollDirection: Axis.horizontal,
                        physics: physics,
                        child: canvas,
                      ),
                    ),
                  ),
                ),
                Positioned(top: 4, right: 8, child: _zoomButtons(context)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _zoomButtons(BuildContext context) {
    final label = _zoom == _zoom.roundToDouble()
        ? '${_zoom.round()}x'
        : '${_zoom}x';
    Widget button(String key, IconData icon, String tip, VoidCallback? onTap) =>
        IconButton(
          key: ValueKey(key),
          icon: Icon(icon, size: 18),
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          padding: EdgeInsets.zero,
          onPressed: onTap,
        );
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            button(
              'treemap-zoom-out',
              Icons.remove,
              'Zoom out',
              _zoom > kTreemapZoomSteps.first ? () => _step(-1) : null,
            ),
            Text(label, key: const ValueKey('treemap-zoom-label')),
            button(
              'treemap-zoom-in',
              Icons.add,
              'Zoom in',
              _zoom < kTreemapZoomSteps.last ? () => _step(1) : null,
            ),
            button(
              'treemap-zoom-reset',
              Icons.fit_screen,
              'Reset zoom',
              _zoom != 1 ? _reset : null,
            ),
          ],
        ),
      ),
    );
  }
}
