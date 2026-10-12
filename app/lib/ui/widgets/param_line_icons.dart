import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'param_icons.dart' show Param;

/// The line-style icons (budget + the action editor's section headers), drawn
/// in the same 24x24 design box as the solid [ParamIconPainter] icons: rounded
/// strokes, ONE colour, static geometry built once. See
/// `dev/references/budget/` for the pictures they follow.
bool isLineParam(Param p) => switch (p) {
  Param.plan ||
  Param.actual ||
  Param.categories ||
  Param.accounts ||
  Param.transactions ||
  Param.notes ||
  Param.connected ||
  Param.manual => true,
  _ => false,
};

/// Paints [param] (one of the line icons) into the current 24x24 box.
void paintLineIcon(ui.Canvas canvas, Param param, Color color) {
  final line = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.7
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;
  final fill = Paint()
    ..color = color
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;
  switch (param) {
    case Param.plan:
      _paintPlan(canvas, line, fill);
    case Param.actual:
      _paintActual(canvas, line, fill);
    case Param.categories:
      _paintCategories(canvas, line, fill);
    case Param.accounts:
      _paintPurse(canvas, line, fill);
    case Param.transactions:
      _paintReceipt(canvas, line);
    case Param.notes:
      canvas.drawPath(_P.notes, line);
    case Param.connected:
      canvas.drawPath(_P.connected, line);
    case Param.manual:
      _paintSliders(canvas, line);
    default:
      break;
  }
}

// ---- Plan / Fact: one route, told in two halves --------------------------------
//
// Plan = an OUTLINE pin on the left with a DOTTED trail leaving it to the right;
// Fact = a FILLED pin on the right with a thick SOLID trail arriving from the
// left. Both trails sit at y = 14 on the box edge, so with the Plan icon next
// to the Fact icon the dots run into the solid line and the route continues.

void _paintPlan(ui.Canvas canvas, Paint line, Paint fill) {
  canvas.drawPath(_P.pinPlan, line);
  canvas.drawOval(
    Rect.fromCircle(center: const Offset(7, 7.4), radius: 1.5),
    line,
  );
  for (final d in _P.planDots) {
    canvas.drawCircle(d, 1.05, fill);
  }
}

void _paintActual(ui.Canvas canvas, Paint line, Paint fill) {
  // The hole is punched out of the solid pin (even-odd).
  canvas.drawPath(_P.pinFact, fill);
  canvas.drawPath(_P.factTrail, Paint.from(line)..strokeWidth = 2.6);
}

// ---- Categories: a 2x2 grid of rounded squares ------------------------------------

void _paintCategories(ui.Canvas canvas, Paint line, Paint fill) {
  final thin = Paint.from(line)..strokeWidth = 1.45;
  for (final o in const [
    Offset(1.2, 1.2),
    Offset(13.0, 1.2),
    Offset(1.2, 13.0),
    Offset(13.0, 13.0),
  ]) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(o.dx, o.dy, 9.8, 9.8),
        const Radius.circular(2.6),
      ),
      thin,
    );
  }
  final small = Paint.from(line)..strokeWidth = 1.15;
  // Top-left: a coin with a dollar sign.
  canvas.drawCircle(const Offset(6.1, 6.1), 3.0, small);
  _dollar(canvas, small, const Offset(6.1, 6.1), 1.9);
  // Top-right: a car (transport).
  canvas.drawPath(_P.car, small);
  canvas.drawCircle(const Offset(16.3, 8.9), 0.95, fill);
  canvas.drawCircle(const Offset(19.5, 8.9), 0.95, fill);
  // Bottom-left: a plate with cutlery (restaurants).
  canvas.drawCircle(const Offset(6.1, 18.0), 2.1, small);
  canvas.drawPath(_P.cutlery, small);
  // Bottom-right: a shopping bag.
  canvas.drawPath(_P.bag, small);
}

/// A dollar sign as a stroked path (no font: it must not depend on one).
/// [c] is its centre, [h] its half height.
void _dollar(ui.Canvas canvas, Paint stroke, Offset c, double h) {
  final m = Matrix4.identity()
    ..translateByDouble(c.dx, c.dy, 0, 1)
    ..scaleByDouble(h, h, 1, 1);
  canvas.drawPath(_P.dollar.transform(m.storage), stroke);
}

// ---- Accounts: a purse ------------------------------------------------------------

void _paintPurse(ui.Canvas canvas, Paint line, Paint fill) {
  canvas.drawPath(_P.purse, line);
  // The clasp tab on the right and its button.
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTRB(14.6, 11.4, 22.2, 17.2),
      const Radius.circular(2.2),
    ),
    line,
  );
  canvas.drawCircle(const Offset(17.8, 14.3), 1.05, fill);
}

// ---- Transactions: a receipt with a coin ------------------------------------------

void _paintReceipt(ui.Canvas canvas, Paint line) {
  // The receipt is cut where the coin sits (a clear gap around the coin).
  canvas.save();
  canvas.clipPath(_P.receiptClip);
  canvas.drawPath(_P.receipt, line);
  canvas.restore();
  canvas.drawCircle(const Offset(16.4, 15.6), 5.2, line);
  _dollar(canvas, Paint.from(line)..strokeWidth = 1.4, const Offset(16.4, 15.6), 2.9);
}

// ---- Manual parameters: three sliders -----------------------------------------------

void _paintSliders(ui.Canvas canvas, Paint line) {
  const rows = [(5.0, 8.0), (12.0, 16.0), (19.0, 10.0)];
  for (final (y, knobX) in rows) {
    canvas.drawLine(Offset(2.5, y), Offset(knobX - 3.0, y), line);
    canvas.drawLine(Offset(knobX + 3.0, y), Offset(21.5, y), line);
    canvas.drawCircle(Offset(knobX, y), 2.2, line);
  }
}

/// Static geometry, built once.
class _P {
  // A pin: head circle (centre C, radius r) joined by two tangents to the tip.
  static Path _pin(Offset c, double r, double tipY) {
    final d = tipY - c.dy;
    final theta = math.acos(r / d);
    final left =
        c +
        Offset(
          r * math.cos(math.pi / 2 + theta),
          r * math.sin(math.pi / 2 + theta),
        );
    return Path()
      ..moveTo(c.dx, tipY)
      ..lineTo(left.dx, left.dy)
      ..arcTo(
        Rect.fromCircle(center: c, radius: r),
        math.pi / 2 + theta,
        2 * math.pi - 2 * theta,
        false,
      )
      ..close();
  }

  /// Plan: the outline pin at the left.
  static final Path pinPlan = _pin(const Offset(7, 7.4), 4.6, 18.4);

  /// Fact: the solid pin at the right, with its eye punched out.
  static final Path pinFact = Path.combine(
    PathOperation.difference,
    _pin(const Offset(17, 7.4), 4.9, 18.6),
    Path()
      ..addOval(Rect.fromCircle(center: const Offset(17, 7.4), radius: 1.8)),
  );

  /// The dotted trail: starts at the Plan pin's tip, ends on the right edge.
  static final Path _planRoute = Path()
    ..moveTo(7, 18.4)
    ..cubicTo(8.2, 20.2, 10.5, 21.2, 13.5, 20.4)
    ..cubicTo(17.5, 19.3, 18.8, 14.0, 24.0, 14.0);

  static final List<Offset> planDots = _dots(_planRoute, 3.3);

  static List<Offset> _dots(Path p, double step) {
    final out = <Offset>[];
    for (final m in p.computeMetrics()) {
      for (var d = step * 0.5; d <= m.length; d += step) {
        out.add(m.getTangentForOffset(d)!.position);
      }
    }
    return out;
  }

  /// The solid trail: enters at the left edge, ends at the Fact pin's tip.
  static final Path factTrail = Path()
    ..moveTo(0, 14.0)
    ..cubicTo(5.2, 14.0, 6.0, 19.6, 11.0, 20.0)
    ..cubicTo(14.0, 20.2, 16.2, 19.6, 17.0, 18.6);

  static final Path car = Path()
    // a small car from the side, in the top-right square: body + cabin
    ..addRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(14.2, 6.3, 21.6, 8.7),
        const Radius.circular(1.0),
      ),
    )
    ..moveTo(15.5, 6.3)
    ..lineTo(16.5, 4.2)
    ..lineTo(19.3, 4.2)
    ..lineTo(20.4, 6.3);

  /// A dollar sign in a unit box (-1..1), scaled by the caller.
  static final Path dollar = Path()
    ..moveTo(0.55, -0.5)
    ..cubicTo(0.2, -0.85, -0.7, -0.8, -0.65, -0.32)
    ..cubicTo(-0.6, 0.12, 0.65, 0.02, 0.65, 0.42)
    ..cubicTo(0.65, 0.85, -0.3, 0.88, -0.6, 0.5)
    ..moveTo(0, -1.0)
    ..lineTo(0, 1.0);

  static final Path cutlery = Path()
    // a fork on the left of the plate and a knife on the right
    ..moveTo(2.6, 15.8)
    ..lineTo(2.6, 20.4)
    ..moveTo(9.6, 15.8)
    ..lineTo(9.6, 20.4);

  static final Path bag = Path()
    ..moveTo(15.2, 16.4)
    ..lineTo(20.4, 16.4)
    ..lineTo(20.9, 21.0)
    ..lineTo(14.7, 21.0)
    ..close()
    ..moveTo(16.4, 16.4)
    ..cubicTo(16.4, 14.2, 19.2, 14.2, 19.2, 16.4);

  /// A purse: a rounded body with a rounded flap line.
  static final Path purse = Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(2.2, 5.0, 21.8, 20.0),
        const Radius.circular(3.4),
      ),
    )
    ..moveTo(4.4, 5.0)
    ..cubicTo(6.0, 2.2, 14.0, 2.2, 17.2, 5.0);

  /// The receipt (a zig-zag bottom, three lines) at the left.
  static final Path receipt = Path()
    ..moveTo(4.0, 2.6)
    ..lineTo(15.0, 2.6)
    ..lineTo(15.0, 20.4)
    ..lineTo(13.2, 19.2)
    ..lineTo(11.4, 20.4)
    ..lineTo(9.6, 19.2)
    ..lineTo(7.8, 20.4)
    ..lineTo(6.0, 19.2)
    ..lineTo(4.0, 20.4)
    ..close()
    ..moveTo(7.0, 7.0)
    ..lineTo(12.0, 7.0)
    ..moveTo(7.0, 10.6)
    ..lineTo(10.4, 10.6)
    ..moveTo(7.0, 14.2)
    ..lineTo(9.6, 14.2);

  /// Everything except a disc a little wider than the coin.
  static final Path receiptClip = Path.combine(
    PathOperation.difference,
    Path()..addRect(const Rect.fromLTWH(-2, -2, 28, 28)),
    Path()
      ..addOval(Rect.fromCircle(center: const Offset(16.4, 15.6), radius: 6.6)),
  );

  /// A page with a folded corner and three lines of text.
  static final Path notes = Path()
    ..moveTo(5.0, 2.8)
    ..lineTo(14.6, 2.8)
    ..lineTo(19.6, 7.8)
    ..lineTo(19.6, 21.2)
    ..lineTo(5.0, 21.2)
    ..close()
    ..moveTo(14.6, 2.8)
    ..lineTo(14.6, 7.8)
    ..lineTo(19.6, 7.8)
    ..moveTo(8.4, 12.6)
    ..lineTo(16.2, 12.6)
    ..moveTo(8.4, 15.8)
    ..lineTo(16.2, 15.8)
    ..moveTo(8.4, 19.0)
    ..lineTo(13.2, 19.0);

  /// Two linked boxes: the previous action and the next one.
  static final Path connected = Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(2.2, 13.4, 8.4, 8.4),
        const Radius.circular(2.2),
      ),
    )
    ..addRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(13.4, 2.2, 8.4, 8.4),
        const Radius.circular(2.2),
      ),
    )
    ..moveTo(6.4, 13.4)
    ..lineTo(6.4, 6.4)
    ..lineTo(13.4, 6.4);
}
