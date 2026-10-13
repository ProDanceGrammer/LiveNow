import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Marker passed where an [IconData] is expected ([QuickActionSpec],
/// [GlassIconTile]): the tile paints [ContinueIcon] instead of a font glyph.
const IconData continueIconData = IconData(0xE0FF, fontFamily: 'ContinueIcon');

/// "Continue with same action": a single circular arrow (one arc, one filled
/// head), centred in the icon box. [mirrored] flips it left-right (the
/// "previous" counterpart of the forward arrow).
class ContinueIcon extends StatelessWidget {
  const ContinueIcon({
    super.key,
    required this.color,
    this.size = 20,
    this.mirrored = false,
  });

  final Color color;
  final double size;
  final bool mirrored;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _ContinuePainter(color, mirrored),
  );
}

/// [ContinueIcon] in the colour and size of the surrounding [IconTheme], for
/// places that take an icon widget (`IconButton`, `TextButton.icon`).
class ContinueGlyph extends StatelessWidget {
  const ContinueGlyph({super.key, this.mirrored = false});

  final bool mirrored;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    return ContinueIcon(
      color: theme.color ?? Theme.of(context).colorScheme.primary,
      size: theme.size ?? 24,
      mirrored: mirrored,
    );
  }
}

class _ContinuePainter extends CustomPainter {
  _ContinuePainter(this.color, this.mirrored);

  final Color color;
  final bool mirrored;

  /// The phone's icon size in logical px: the look every smaller size copies.
  static const double _referenceSize = 22;

  static double _rad(double deg) => deg * math.pi / 180;

  @override
  void paint(Canvas canvas, Size box) {
    canvas.scale(box.width / 24);
    if (mirrored) {
      // Flip about the box's vertical centre line.
      canvas.translate(24, 0);
      canvas.scale(-1, 1);
    }
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    const c = Offset(12, 12);
    const r = 8.0;

    // One arc (canvas degrees, 0 = 3 o'clock, clockwise positive): from the
    // lower left, over the top, to the right - ending in a filled arrowhead.
    const start = -200.0, end = -35.0;
    final arc = Path()
      ..addArc(
        Rect.fromCircle(center: c, radius: r),
        _rad(start),
        _rad(end - start),
      );

    final a = _rad(end);
    final tip = c + Offset(math.cos(a), math.sin(a)) * r;
    final tangent = Offset(-math.sin(a), math.cos(a)); // clockwise
    final normal = Offset(math.cos(a), math.sin(a));
    final head = Path()
      ..moveTo(tip.dx + tangent.dx * 5.0, tip.dy + tangent.dy * 5.0)
      ..lineTo(
        tip.dx + normal.dx * 4.8 - tangent.dx * 0.6,
        tip.dy + normal.dy * 4.8 - tangent.dy * 0.6,
      )
      ..lineTo(
        tip.dx - normal.dx * 4.8 - tangent.dx * 0.6,
        tip.dy - normal.dy * 4.8 - tangent.dy * 0.6,
      )
      ..close();

    // Centre what is drawn (arc + head) in the icon box. Boxes smaller than the
    // phone's 22 px icon (the desktop's 18 px hover tools) draw the arrow at
    // the phone's absolute size and line weight, so it looks the same
    // everywhere instead of smaller and thinner.
    final bounds = arc.getBounds().expandToInclude(head.getBounds());
    final k = box.width < _referenceSize ? _referenceSize / box.width : 1.0;
    canvas.translate(12, 12);
    canvas.scale(k);
    canvas.translate(-bounds.center.dx, -bounds.center.dy);
    canvas.drawPath(arc, stroke);
    canvas.drawPath(head, fill);
  }

  @override
  bool shouldRepaint(_ContinuePainter old) =>
      old.color != color || old.mirrored != mirrored;
}
