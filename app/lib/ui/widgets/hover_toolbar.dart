import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'glass.dart';

/// Wraps [child] so that resting a mouse pointer on it shows [toolbarBuilder]'s
/// widget in the root overlay, above the child's top-right corner. The child
/// itself builds nothing for the toolbar until it is hovered, which is the
/// point: a board of many cards must not carry a button row each.
///
/// - The toolbar overlaps the child by 3 px, and "shown" is the OR of "pointer
///   over the child" and "pointer over the toolbar", so moving between the two
///   never flickers.
/// - It is shown only after a real hover *move* over the child (not on a bare
///   enter): content that scrolls or re-lays-out under a resting pointer, and a
///   drag (button down, so only move events) sweeping across cards, therefore
///   never flash toolbars. Scrolling the enclosing scrollable hides it.
/// - Only one toolbar exists at a time (showing one hides the previous).
/// - Touch input never hovers, so it never shows.
/// - When there is no room above the child inside its scroll viewport, the
///   toolbar sits over the child's own top-right area instead; it is always
///   clamped on screen.
class HoverToolbarHost extends StatefulWidget {
  final Widget child;

  /// Builds the toolbar's content (without the glass pill; see
  /// [HoverToolbarPill]).
  final WidgetBuilder toolbarBuilder;

  /// Height the toolbar occupies, used to place it above the child.
  final double toolbarHeight;

  const HoverToolbarHost({
    super.key,
    required this.child,
    required this.toolbarBuilder,
    this.toolbarHeight = kHoverToolbarHeight,
  });

  @override
  State<HoverToolbarHost> createState() => _HoverToolbarHostState();
}

/// Default pill height: a 32 px tile plus the pill's padding.
const double kHoverToolbarHeight = 42;

class _HoverToolbarHostState extends State<HoverToolbarHost> {
  /// The one host currently showing its toolbar.
  static _HoverToolbarHostState? _active;

  final _portal = OverlayPortalController();
  bool _overChild = false;
  bool _overBar = false;
  bool _armed = false;
  ScrollPosition? _position;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (!identical(position, _position)) {
      _position?.removeListener(_onScroll);
      _position = position?..addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_onScroll);
    if (identical(_active, this)) _active = null;
    super.dispose();
  }

  void _onScroll() {
    if (!_portal.isShowing && !_armed) return;
    // The toolbar would be left behind by the moving content: hide it until
    // the pointer moves again.
    _armed = false;
    _overBar = false;
    _sync();
  }

  void _sync() {
    if (!mounted) return;
    final show = (_overChild && _armed) || _overBar;
    if (show && !_portal.isShowing) {
      final other = _active;
      if (other != null && !identical(other, this)) other._forceHide();
      _active = this;
      _portal.show();
    } else if (!show && _portal.isShowing) {
      if (identical(_active, this)) _active = null;
      _portal.hide();
    }
  }

  void _forceHide() {
    _armed = false;
    _overBar = false;
    if (mounted && _portal.isShowing) _portal.hide();
  }

  /// Top of the enclosing scroll viewport in overlay coordinates (0 when the
  /// child is not in a scrollable).
  double _viewportTop() {
    final viewport = Scrollable.maybeOf(context)?.context.findRenderObject();
    final overlay = Overlay.maybeOf(context)?.context.findRenderObject();
    if (viewport is! RenderBox || !viewport.attached) return 0;
    return viewport
        .localToGlobal(
          Offset.zero,
          ancestor: overlay is RenderBox ? overlay : null,
        )
        .dy;
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _portal,
      overlayChildBuilder: (_, info) {
        final corner = MatrixUtils.transformPoint(
          info.childPaintTransform,
          Offset(info.childSize.width, 0),
        );
        final h = widget.toolbarHeight;
        // Above the child's top-right corner, overlapping it by 3 px so the
        // pointer never crosses a gap; without room above (the first card
        // under a header), over the child's own top edge area instead.
        final viewportTop = _viewportTop();
        var top = corner.dy - h + 3;
        if (top < viewportTop) {
          top = math.max(corner.dy + 3, viewportTop + 3);
        }
        top = top.clamp(0.0, math.max(0.0, info.overlaySize.height - h));
        final right = (info.overlaySize.width - corner.dx).clamp(
          8.0,
          info.overlaySize.width,
        );
        return Positioned(
          top: top,
          left: 0,
          right: 0,
          child: Padding(
            padding: EdgeInsets.only(left: 8, right: right),
            child: Align(
              alignment: Alignment.centerRight,
              child: MouseRegion(
                onEnter: (_) {
                  _overBar = true;
                  _sync();
                },
                onExit: (_) {
                  _overBar = false;
                  _sync();
                },
                child: widget.toolbarBuilder(context),
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
        onHover: (_) {
          if (_armed) return;
          _armed = true;
          _sync();
        },
        onExit: (_) {
          _overChild = false;
          _armed = false;
          _sync();
        },
        // A press on the child opens an editor / menu or starts a selection:
        // the toolbar must not linger over what opens. It returns on the next
        // hover move.
        child: Listener(
          onPointerDown: (_) {
            if (!_armed && !_portal.isShowing) return;
            _armed = false;
            _sync();
          },
          child: widget.child,
        ),
      ),
    );
  }
}

/// The small glass pill around a hover toolbar's buttons. Scales its content
/// down when the window is narrower than the buttons.
class HoverToolbarPill extends StatelessWidget {
  final Widget child;

  const HoverToolbarPill({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      strength: 1.6,
      radius: 14,
      // The transparent Material is only there so the buttons' ink has
      // something to paint on.
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: FittedBox(fit: BoxFit.scaleDown, child: child),
        ),
      ),
    );
  }
}
