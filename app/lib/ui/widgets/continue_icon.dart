import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Marker passed where an [IconData] is expected ([QuickActionSpec],
/// [GlassIconTile]): the tile paints [ContinueIcon] instead of a font glyph.
const IconData continueIconData = IconData(0xE0FF, fontFamily: 'ContinueIcon');

/// "Continue with same action": an arc with a dashed start and one arrowhead
/// at its end pointing down-right (one arrow, unlike the old two-arrow
/// refresh glyph).
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

  @override
  void paint(Canvas canvas, Size box) {
    canvas.scale(box.width / 24);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    const c = Offset(11, 15);
    const r = 8.5;
    final rect = Rect.fromCircle(center: c, radius: r);
    // Dashed start (a short stub), a gap, then the solid arc.
    canvas.drawArc(rect, math.pi + 0.1, 0.24, false, line);
    const solidStart = math.pi + 0.62;
    const solidEnd = 2 * math.pi - 0.45;
    canvas.drawArc(rect, solidStart, solidEnd - solidStart, false, line);
    // Arrowhead at the end, pointing along the (clockwise) tangent.
    final tip = c + Offset(math.cos(solidEnd), math.sin(solidEnd)) * r;
    final tangent = Offset(-math.sin(solidEnd), math.cos(solidEnd));
    final back = -tangent;
    Offset rot(Offset v, double a) => Offset(
      v.dx * math.cos(a) - v.dy * math.sin(a),
      v.dx * math.sin(a) + v.dy * math.cos(a),
    );
    final head = Path()
      ..moveTo(tip.dx + rot(back, 0.7).dx * 6.5, tip.dy + rot(back, 0.7).dy * 6.5)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(
        tip.dx + rot(back, -0.7).dx * 6.5,
        tip.dy + rot(back, -0.7).dy * 6.5,
      );
    canvas.drawPath(head, line);
  }

  @override
  bool shouldRepaint(_ContinuePainter old) => old.color != color;
}
