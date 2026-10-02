// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/glass_theme.dart';

// Snapshot glass. Behind every surface there is the same static background
// (gradient + clouds), so instead of a per-surface `BackdropFilter` (a costly
// saveLayer every frame) the background is rendered ONCE, blurred ONCE into a
// small image, and each [GlassSurface] just paints the window of that image
// under itself (one image blit) before its translucent fill, bright edge and
// soft shadow. It looks like frosted glass and stays cheap in scrolling lists.

/// Paints the page background: pale gradient plus soft painted clouds.
void paintGlassBackground(Canvas canvas, Size size, GlassTheme g) {
  final rect = Offset.zero & size;
  canvas.drawRect(
    rect,
    Paint()
      ..shader = ui.Gradient.linear(
        rect.topLeft,
        rect.bottomRight,
        g.background,
        const [0, 0.5, 1],
      ),
  );
  final r = math.min(size.width, size.height);
  _cloud(
    canvas,
    Offset(size.width * 0.93, size.height * 0.03),
    r * 0.26,
    g.clouds[0],
    g.dark,
  );
  _cloud(
    canvas,
    Offset(size.width * 0.9, size.height * 0.99),
    r * 0.24,
    g.clouds[1],
    g.dark,
  );
  _cloud(
    canvas,
    Offset(size.width * 0.04, size.height * 0.97),
    r * 0.18,
    g.clouds[2],
    g.dark,
  );
  _cloud(
    canvas,
    Offset(size.width * 0.0, size.height * 0.02),
    r * 0.15,
    g.clouds[3],
    g.dark,
  );
}

/// A soft cloud: a cluster of overlapping radial puffs.
void _cloud(Canvas canvas, Offset c, double r, Color tint, bool dark) {
  const puffs = [
    (-0.95, 0.20, 0.85),
    (-0.35, -0.30, 1.05),
    (0.35, 0.05, 1.0),
    (0.95, 0.15, 0.80),
    (0.10, 0.50, 0.85),
    (-0.55, 0.55, 0.65),
  ];
  final core = dark ? 0.12 : 0.80;
  final mid = dark ? 0.50 : 0.75;
  // Light clouds are bigger so the sky reads as billowing, not flat.
  if (!dark) r *= 1.35;
  for (final (dx, dy, s) in puffs) {
    final centre = c + Offset(dx * r, dy * r);
    final radius = r * s;
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..shader = ui.Gradient.radial(
          centre,
          radius,
          [
            Colors.white.withValues(alpha: core),
            tint.withValues(alpha: mid),
            tint.withValues(alpha: 0),
          ],
          const [0, 0.55, 1],
        ),
    );
  }
}

/// Surfaces larger than this (logical px squared) skip the blurred window.
const _maxBlurWindowArea = 250000.0;

/// Hands the blurred background to the surfaces below it.
class GlassScope extends InheritedWidget {
  const GlassScope({
    super.key,
    required this.blurred,
    required this.scale,
    required this.originKey,
    required super.child,
  });

  /// The blurred background, or null until the first snapshot is ready.
  final ui.Image? blurred;

  /// Image pixels per logical pixel.
  final double scale;

  /// Key of the box the snapshot was taken from (its origin = image origin).
  final GlobalKey originKey;

  static GlassScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassScope>();

  @override
  bool updateShouldNotify(GlassScope old) =>
      blurred != old.blurred || scale != old.scale;
}

/// The window background (gradient + clouds) and its blurred snapshot. Sits
/// once under the whole app (`MaterialApp.builder`); pages are transparent.
class GlassBackground extends StatefulWidget {
  const GlassBackground({super.key, required this.child, bool? snapshot})
    : _snapshot = snapshot;

  final Widget child;
  final bool? _snapshot;

  /// Off under `flutter test` (image encoding needs real async); tests that
  /// exercise the snapshot pass `snapshot: true` explicitly.
  bool get snapshot =>
      _snapshot ?? !Platform.environment.containsKey('FLUTTER_TEST');

  @override
  State<GlassBackground> createState() => _GlassBackgroundState();
}

class _GlassBackgroundState extends State<GlassBackground> {
  final _originKey = GlobalKey();
  ui.Image? _blurred;
  ui.Image? _sharp;
  double _scale = 0.5;
  Timer? _timer;
  Size? _size;
  double? _dpr;
  bool? _dark;
  int _generation = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _blurred?.dispose();
    _sharp?.dispose();
    super.dispose();
  }

  void _request(Size size, double dpr, GlassTheme g) {
    if (size.isEmpty || (size == _size && dpr == _dpr && g.dark == _dark)) {
      return;
    }
    _size = size;
    _dpr = dpr;
    _dark = g.dark;
    _timer?.cancel();
    final generation = ++_generation;
    // The first snapshot at once; later ones wait for a resize to settle.
    _timer = Timer(
      _blurred == null ? Duration.zero : const Duration(milliseconds: 150),
      () => _render(size, dpr, g, generation),
    );
  }

  Future<void> _render(
    Size size,
    double dpr,
    GlassTheme g,
    int generation,
  ) async {
    // Half resolution is plenty for a blurred picture and 4x cheaper.
    const downscale = 0.5;
    final w = math.max(1, (size.width * dpr * downscale).ceil());
    final h = math.max(1, (size.height * dpr * downscale).ceil());
    final k = w / size.width;

    final sharpRecorder = ui.PictureRecorder();
    final sharpCanvas = Canvas(sharpRecorder)..scale(k);
    paintGlassBackground(sharpCanvas, size, g);
    final sharp = await sharpRecorder.endRecording().toImage(w, h);

    final blurRecorder = ui.PictureRecorder();
    final blurCanvas = Canvas(blurRecorder);
    final sigma = g.blurSigma * dpr * downscale;
    blurCanvas.saveLayer(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: sigma,
          sigmaY: sigma,
          tileMode: TileMode.clamp,
        ),
    );
    blurCanvas.drawImage(sharp, Offset.zero, Paint());
    blurCanvas.restore();
    final blurred = await blurRecorder.endRecording().toImage(w, h);

    if (!mounted || generation != _generation) {
      blurred.dispose();
      sharp.dispose();
      return;
    }
    setState(() {
      _blurred?.dispose();
      _sharp?.dispose();
      _blurred = blurred;
      _sharp = sharp;
      _scale = k;
    });
  }

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, box) {
        if (widget.snapshot) _request(box.biggest, dpr, g);
        return GlassScope(
          blurred: _blurred,
          scale: _scale,
          originKey: _originKey,
          child: Stack(
            fit: StackFit.expand,
            children: [
              RepaintBoundary(
                key: _originKey,
                child: CustomPaint(
                  painter: _BackdropPainter(g, _sharp),
                  size: Size.infinite,
                ),
              ),
              widget.child,
            ],
          ),
        );
      },
    );
  }
}

/// Draws the page background. Once the snapshot exists it is ONE image blit
/// (the raster thread replays everything on screen every frame, and the live
/// gradient + 24 radial cloud puffs were costing ~15 ms of it); the live
/// shader version only shows for the very first frames and in tests.
class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.g, this.image);
  final GlassTheme g;
  final ui.Image? image;

  @override
  void paint(Canvas canvas, Size size) {
    final img = image;
    if (img == null) {
      paintGlassBackground(canvas, size, g);
      return;
    }
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(_BackdropPainter old) => old.g != g || old.image != image;
}

/// A frosted-glass surface: blurred background window + translucent fill +
/// bright edge + soft shadow, then [child]. Outside a [GlassBackground]
/// (e.g. in tests) it degrades to the translucent fill only.
class GlassSurface extends SingleChildRenderObjectWidget {
  const GlassSurface({
    super.key,
    super.child,
    this.radius = GlassTheme.radiusPanel,
    this.strength = 1,
    this.shadow = true,
    this.blurWindow = true,
  });

  final double radius;

  /// Scales the fill opacity (1 = the theme's glass fill, >1 more opaque).
  final double strength;
  final bool shadow;

  /// Paint the blurred background window. Off for surfaces that are scaled
  /// or animated (mindmap nodes): there the blur could not stay aligned.
  final bool blurWindow;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderGlassSurface(
    tokens: context.glass,
    scope: GlassScope.maybeOf(context),
    radius: radius,
    strength: strength,
    shadow: shadow,
    blurWindow: blurWindow,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderGlassSurface renderObject,
  ) {
    renderObject
      ..tokens = context.glass
      ..scope = GlassScope.maybeOf(context)
      ..radius = radius
      ..strength = strength
      ..shadow = shadow
      ..blurWindow = blurWindow;
  }
}

class RenderGlassSurface extends RenderProxyBox {
  RenderGlassSurface({
    required GlassTheme tokens,
    required GlassScope? scope,
    required double radius,
    required double strength,
    required bool shadow,
    required bool blurWindow,
  }) : _tokens = tokens,
       _scope = scope,
       _radius = radius,
       _strength = strength,
       _shadow = shadow,
       _blurWindow = blurWindow;

  GlassTheme _tokens;
  GlassScope? _scope;
  double _radius;
  double _strength;
  bool _shadow;
  bool _blurWindow;

  set tokens(GlassTheme v) {
    if (identical(v, _tokens)) return;
    _tokens = v;
    markNeedsPaint();
  }

  set scope(GlassScope? v) {
    if (_scope?.blurred == v?.blurred && _scope?.scale == v?.scale) {
      _scope = v;
      return;
    }
    _scope = v;
    markNeedsPaint();
  }

  set radius(double v) {
    if (v == _radius) return;
    _radius = v;
    markNeedsPaint();
  }

  set strength(double v) {
    if (v == _strength) return;
    _strength = v;
    markNeedsPaint();
  }

  set shadow(bool v) {
    if (v == _shadow) return;
    _shadow = v;
    markNeedsPaint();
  }

  set blurWindow(bool v) {
    if (v == _blurWindow) return;
    _blurWindow = v;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final rect = offset & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(_radius));
    final t = _tokens;

    if (_shadow) {
      // A cheap soft shadow: a few fading rings just outside the edge. (A
      // blurred mask + inverse clip path per surface was a large part of the
      // frame cost, and the raster thread redraws every surface every frame.)
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4;
      for (var i = 0; i < 3; i++) {
        ring.color = t.shadow.withValues(alpha: t.shadow.a * (1.0 - i * 0.3));
        canvas.drawRRect(
          rrect.inflate(2.0 + i * 4).shift(const Offset(0, 4)),
          ring,
        );
      }
    }

    final image = _scope?.blurred;
    final origin = _scope?.originKey.currentContext?.findRenderObject();
    // The blurred window costs fill-rate in proportion to the area; on a
    // big panel (the board columns) it is nearly invisible over the soft
    // background but made section switches janky, so only small and medium
    // surfaces get it.
    if (_blurWindow &&
        size.width * size.height <= _maxBlurWindowArea &&
        image != null &&
        origin is RenderBox &&
        origin.attached) {
      final p = localToGlobal(Offset.zero) - origin.localToGlobal(Offset.zero);
      final s = _scope!.scale;
      canvas
        ..save()
        ..clipRRect(rrect)
        ..drawImageRect(
          image,
          Rect.fromLTWH(p.dx * s, p.dy * s, size.width * s, size.height * s),
          rect,
          Paint()..filterQuality = FilterQuality.low,
        )
        ..restore();
    }

    final fill = t.fill.withValues(alpha: math.min(1, t.fill.a * _strength));
    canvas.drawRRect(rrect, Paint()..color = fill);
    canvas.drawRRect(
      rrect.deflate(0.6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = t.border,
    );

    super.paint(context, offset);
  }
}

/// A plain [BoxDecoration] with the glass look (translucent fill, bright
/// edge, soft shadow) for places that need a decoration rather than a
/// [GlassSurface] (e.g. scaled mindmap nodes, calendar blocks).
BoxDecoration glassDecoration(
  BuildContext context, {
  double radius = GlassTheme.radiusControl,
  Color? color,
  bool shadow = true,
}) {
  final g = context.glass;
  return BoxDecoration(
    color: color ?? g.fill,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: g.border, width: 1.2),
    boxShadow: shadow
        ? [
            BoxShadow(
              color: g.shadow,
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ]
        : null,
  );
}
