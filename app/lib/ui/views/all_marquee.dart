import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../all_selection.dart';
import '../undo.dart';
import '../widgets/action_tile.dart';
import 'all_actions_view.dart' show filteredAllActionsProvider;

/// Mouse marquee for the All list: press anywhere on the list and drag to draw a
/// rectangle; the actions it covers are selected. The list scrolls by itself
/// while the pointer is near its top/bottom edge and rows that scrolled past
/// stay covered (their rectangles are remembered in CONTENT coordinates).
/// Ctrl/Shift adds to the current selection. Esc clears, Ctrl+A selects the
/// whole filtered list and Del deletes the selection (one Undo).
///
/// Only a mouse drag starts it; on a touch screen a drag scrolls as usual. A
/// press that does not move (a tap) is left to the row.
class AllMarquee extends ConsumerStatefulWidget {
  const AllMarquee({super.key, required this.builder});

  /// Builds the list; it must use the given controller for its scrolling.
  final Widget Function(ScrollController controller) builder;

  @override
  ConsumerState<AllMarquee> createState() => _AllMarqueeState();
}

class _AllMarqueeState extends ConsumerState<AllMarquee> {
  static const _dragSlop = 4.0;
  static const _edge = 40.0;

  final _scroll = ScrollController();
  final _focus = FocusNode(debugLabel: 'all-marquee');
  final _stackKey = GlobalKey();
  final _rect = ValueNotifier<Rect?>(null);

  int? _pointer;
  Offset _down = Offset.zero; // local coordinates of the press
  double _downScroll = 0;
  Offset _now = Offset.zero; // local coordinates of the pointer
  bool _active = false;
  Set<String> _base = const {};
  late Offset _startContent;
  final _known = <String, Rect>{}; // id -> rect in content coordinates
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    _focus.dispose();
    _rect.dispose();
    super.dispose();
  }

  RenderBox? get _box =>
      _stackKey.currentContext?.findRenderObject() as RenderBox?;

  double get _offset => _scroll.hasClients ? _scroll.offset : 0;

  void _down_(PointerDownEvent e) {
    if (e.kind != PointerDeviceKind.mouse ||
        e.buttons != kPrimaryMouseButton) {
      return;
    }
    final box = _box;
    if (box == null) return;
    _focus.requestFocus();
    _pointer = e.pointer;
    _down = box.globalToLocal(e.position);
    _downScroll = _offset;
    _active = false;
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    final box = _box;
    if (box == null) return;
    _now = box.globalToLocal(e.position);
    if (!_active) {
      if ((_now - _down).distance < _dragSlop) return;
      _active = true;
      final kb = HardwareKeyboard.instance;
      _base = kb.isControlPressed || kb.isShiftPressed
          ? {...ref.read(allSelectionProvider)}
          : <String>{};
      _startContent = Offset(_down.dx, _down.dy + _downScroll);
      _known.clear();
      _timer = Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
    }
    _update();
  }

  void _end(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _timer?.cancel();
    _timer = null;
    _rect.value = null;
    _active = false;
    _known.clear();
  }

  /// Near the top/bottom edge: scroll, faster the closer to the edge.
  void _tick() {
    final box = _box;
    if (!_active || box == null || !_scroll.hasClients) return;
    final h = box.size.height;
    var delta = 0.0;
    if (_now.dy < _edge) {
      delta = -(_edge - _now.dy).clamp(2.0, _edge) / 2;
    } else if (_now.dy > h - _edge) {
      delta = (_now.dy - (h - _edge)).clamp(2.0, _edge) / 2;
    }
    if (delta != 0) {
      final p = _scroll.position;
      final target = (p.pixels + delta).clamp(
        p.minScrollExtent,
        p.maxScrollExtent,
      );
      if (target != p.pixels) {
        _scroll.jumpTo(target);
        _update();
      }
    }
  }

  /// Remember the rectangle of every built row (content coordinates), then
  /// select the rows overlapping the marquee: remembered ones included.
  void _update() {
    final box = _box;
    if (box == null) return;
    final offset = _offset;
    void visit(Element e) {
      if (e.widget is ActionTile) {
        final ro = e.renderObject;
        if (ro is RenderBox && ro.attached && ro.hasSize) {
          final topLeft = box.globalToLocal(ro.localToGlobal(Offset.zero));
          _known[(e.widget as ActionTile).action.id] =
              (topLeft + Offset(0, offset)) & ro.size;
        }
        return; // nothing below a tile is a tile
      }
      e.visitChildren(visit);
    }

    (_stackKey.currentContext as Element).visitChildren(visit);

    final nowContent = Offset(_now.dx, _now.dy + offset);
    final content = Rect.fromPoints(_startContent, nowContent);
    final hits = <String>{
      for (final e in _known.entries)
        if (e.value.overlaps(content)) e.key,
    };
    ref.read(allSelectionProvider.notifier).setAll({..._base, ...hits});
    _rect.value = Rect.fromPoints(
      Offset(_startContent.dx, _startContent.dy - offset),
      _now,
    );
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final selection = ref.read(allSelectionProvider.notifier);
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (selection.state.isEmpty) return KeyEventResult.ignored;
      selection.clear();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyA &&
        HardwareKeyboard.instance.isControlPressed) {
      final items = ref.read(filteredAllActionsProvider).value ?? const [];
      selection.setAll([for (final a in items) a.id]);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete && selection.state.isNotEmpty) {
      final ids = selection.state.toList();
      selection.clear();
      runUndoableDeleteMany(context, ref, ids);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Focus(
      focusNode: _focus,
      onKeyEvent: _key,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _down_,
        onPointerMove: _move,
        onPointerUp: _end,
        onPointerCancel: _end,
        child: Stack(
          key: _stackKey,
          children: [
            widget.builder(_scroll),
            Positioned.fill(
              child: IgnorePointer(
                child: ValueListenableBuilder<Rect?>(
                  valueListenable: _rect,
                  builder: (context, r, _) => r == null
                      ? const SizedBox.shrink()
                      : CustomPaint(
                          key: const ValueKey('all-marquee-rect'),
                          painter: _RectPainter(
                            r,
                            scheme.primary.withValues(alpha: 0.18),
                            scheme.primary,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RectPainter extends CustomPainter {
  _RectPainter(this.rect, this.fill, this.line);

  final Rect rect;
  final Color fill;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(rect, Paint()..color = fill);
    canvas.drawRect(
      rect,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(_RectPainter old) =>
      old.rect != rect || old.fill != fill || old.line != line;
}
