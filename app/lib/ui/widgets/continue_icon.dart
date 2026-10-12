import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Marker passed where an [IconData] is expected ([QuickActionSpec],
/// [GlassIconTile]): the tile paints [ContinueIcon] instead of a font glyph.
const IconData continueIconData = IconData(0xE0FF, fontFamily: 'ContinueIcon');

/// "Continue with same action": the circular refresh icon, but with ONE arrow
/// (the top one, filled head) instead of two; the lower arc is plain.
class ContinueIcon extends StatelessWidget {
  const ContinueIcon({super.key, required this.color, this.size = 20});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _ContinuePainter(color));
}

class _ContinuePainter extends CustomPainter {
  _ContinuePainter(this.color);

  final Color color;

  static double _rad(double deg) => deg * math.pi / 180;

  @override
  void paint(Canvas canvas, Size box) {
    canvas.scale(box.width / 24);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    const c = Offset(12, 12);
    const r = 7.2;
    final rect = Rect.fromCircle(center: c, radius: r);

    // Top arc (canvas degrees, 0 = 3 o'clock, clockwise positive): from the
    // left, over the top, to the right - ending in the arrowhead.
    const topStart = -165.0, topEnd = -40.0;
    canvas.drawArc(
      rect,
      _rad(topStart),
      _rad(topEnd - topStart),
      false,
      stroke,
    );

    // Plain lower arc (no head).
    const lowStart = 15.0, lowEnd = 140.0;
    canvas.drawArc(
      rect,
      _rad(lowStart),
      _rad(lowEnd - lowStart),
      false,
      stroke,
    );

    // Filled arrowhead at the end of the top arc, pointing along the circle.
    final a = _rad(topEnd);
    final tip = c + Offset(math.cos(a), math.sin(a)) * r;
    final tangent = Offset(-math.sin(a), math.cos(a)); // clockwise
    final normal = Offset(math.cos(a), math.sin(a));
    final head = Path()
      ..moveTo(tip.dx + tangent.dx * 4.6, tip.dy + tangent.dy * 4.6)
      ..lineTo(
        tip.dx + normal.dx * 4.4 - tangent.dx * 0.6,
        tip.dy + normal.dy * 4.4 - tangent.dy * 0.6,
      )
      ..lineTo(
        tip.dx - normal.dx * 4.4 - tangent.dx * 0.6,
        tip.dy - normal.dy * 4.4 - tangent.dy * 0.6,
      )
      ..close();
    canvas.drawPath(head, fill);
  }

  @override
  bool shouldRepaint(_ContinuePainter old) => old.color != color;
}
