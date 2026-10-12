import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/glass_theme.dart';
import 'param_line_icons.dart';

/// The five parameters shown next to growth-direction / action numbers.
enum Param {
  direction,
  urgency,
  weight,
  progress,
  level,
  fact,

  // Line-style icons (see param_line_icons.dart): the budget's Plan / Fact pair
  // (two halves of one route), its sections, and the action editor's blocks.
  plan,
  actual,
  categories,
  accounts,
  transactions,
  notes,
  connected,
  manual,
}

/// Full tooltip / accessibility names.
const Map<Param, String> kParamNames = {
  Param.direction: 'Direction',
  Param.urgency: 'Urgency to Keep in Balance',
  Param.weight: 'Weight',
  Param.progress: 'Progress',
  Param.level: 'Level',
  Param.fact: 'Fact: reached so far',
  Param.plan: 'Plan',
  Param.actual: 'Fact',
  Param.categories: 'Categories',
  Param.accounts: 'Accounts',
  Param.transactions: 'Transactions',
  Param.notes: 'Notes',
  Param.connected: 'Connected actions',
  Param.manual: 'Manual parameters',
};

/// A small monochrome icon for a [Param], painted from cached static paths in
/// a 24x24 design box (solid fills only, no layers, no blur - glass perf rules).
/// `direction` is the rail's own `Icons.insights`.
class ParamIcon extends StatelessWidget {
  const ParamIcon(this.param,
      {super.key, this.color, this.size = 16, this.tooltip = true, this.tapToShow = false});

  /// A budget Plan icon (outline pin + dotted trail).
  const ParamIcon.plan({Key? key, Color? color, double size = 18})
      : this(Param.plan, key: key, color: color, size: size, tapToShow: true);

  /// A budget Fact icon (solid pin + solid trail); continues [ParamIcon.plan].
  const ParamIcon.actual({Key? key, Color? color, double size = 18})
      : this(Param.actual, key: key, color: color, size: size, tapToShow: true);

  const ParamIcon.direction({Key? key, Color? color, double size = 16, bool tooltip = true})
      : this(Param.direction, key: key, color: color, size: size, tooltip: tooltip);
  const ParamIcon.urgency({Key? key, Color? color, double size = 20, bool tooltip = true})
      : this(Param.urgency, key: key, color: color, size: size, tooltip: tooltip);
  const ParamIcon.weight({Key? key, Color? color, double size = 16, bool tooltip = true})
      : this(Param.weight, key: key, color: color, size: size, tooltip: tooltip);
  const ParamIcon.progress({Key? key, Color? color, double size = 16, bool tooltip = true})
      : this(Param.progress, key: key, color: color, size: size, tooltip: tooltip);
  const ParamIcon.level({Key? key, Color? color, double size = 16, bool tooltip = true})
      : this(Param.level, key: key, color: color, size: size, tooltip: tooltip);
  const ParamIcon.fact({Key? key, Color? color, double size = 16, bool tooltip = true})
      : this(Param.fact, key: key, color: color, size: size, tooltip: tooltip);

  final Param param;
  final Color? color;
  final double size;
  final bool tooltip;

  /// Touch: a tap (not only a long-press) shows the name. Used by the
  /// Plan/Fact icons that replace the words; on Windows hover shows it anyway.
  final bool tapToShow;

  @override
  Widget build(BuildContext context) {
    final c = color ??
        (param == Param.urgency
            ? context.glass.urgencyIcon
            : context.glass.textSecondary);
    final name = kParamNames[param]!;
    final Widget icon = param == Param.direction
        ? Icon(Icons.insights, size: size, color: c)
        : CustomPaint(
            size: Size.square(size),
            painter: ParamIconPainter(param, c, size),
          );
    final Widget sized = SizedBox.square(dimension: size, child: icon);
    final Widget semantic = Semantics(label: name, image: true, child: ExcludeSemantics(child: sized));
    return tooltip
        ? Tooltip(
            message: name,
            triggerMode: tapToShow ? TooltipTriggerMode.tap : null,
            child: semantic,
          )
        : semantic;
  }
}

/// Icon + word (tooltip carries the full parameter name).
class ParamLabel extends StatelessWidget {
  const ParamLabel(this.param, {super.key, this.text, this.style, this.color});

  final Param param;
  final String? text;
  final TextStyle? style;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final name = kParamNames[param]!;
    final base = style ?? DefaultTextStyle.of(context).style;
    final c = color ?? style?.color ?? context.glass.textSecondary;
    return Tooltip(
      message: name,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ParamIcon(param, color: c, size: (base.fontSize ?? 14) + 2, tooltip: false),
          const SizedBox(width: 4),
          Flexible(
            child: Text(text ?? name,
                style: base.copyWith(color: c), overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

/// Icon + value text. The tooltip sits on the icon only, so the text stays an
/// ordinary `Text` (tests keep matching `find.text('910')`).
class ParamValue extends StatelessWidget {
  const ParamValue(this.param, this.text,
      {super.key, this.color, this.iconColor, this.style, this.size = 14});

  const ParamValue.urgency(String text, {Key? key, Color? color, Color? iconColor, TextStyle? style, double size = 20})
      : this(Param.urgency, text,
            key: key, color: color, iconColor: iconColor, style: style, size: size);
  const ParamValue.weight(String text, {Key? key, Color? color, TextStyle? style, double size = 14})
      : this(Param.weight, text, key: key, color: color, style: style, size: size);
  const ParamValue.progress(String text, {Key? key, Color? color, TextStyle? style, double size = 14})
      : this(Param.progress, text, key: key, color: color, style: style, size: size);
  const ParamValue.level(String text, {Key? key, Color? color, TextStyle? style, double size = 14})
      : this(Param.level, text, key: key, color: color, style: style, size: size);
  const ParamValue.fact(String text, {Key? key, Color? color, TextStyle? style, double size = 14})
      : this(Param.fact, text, key: key, color: color, style: style, size: size);
  const ParamValue.plan(String text, {Key? key, Color? color, TextStyle? style, double size = 16})
      : this(Param.plan, text, key: key, color: color, style: style, size: size);
  const ParamValue.actual(String text, {Key? key, Color? color, TextStyle? style, double size = 16})
      : this(Param.actual, text, key: key, color: color, style: style, size: size);

  final Param param;
  final String text;
  final Color? color;

  /// Icon colour; defaults to the violet token for urgency, else [color].
  final Color? iconColor;
  final TextStyle? style;
  final double size;

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final c = color ?? style?.color ?? context.glass.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ParamIcon(param,
            color: iconColor ?? (param == Param.urgency ? context.glass.urgencyIcon : c),
            size: size,
            tapToShow: param == Param.plan || param == Param.actual),
        const SizedBox(width: 3),
        Text(text, style: base.copyWith(color: c)),
      ],
    );
  }
}

/// Paints one parameter icon in the 24x24 design box scaled to [size].
class ParamIconPainter extends CustomPainter {
  ParamIconPainter(this.param, this.color, this.size);

  final Param param;
  final Color color;
  final double size;

  @override
  void paint(Canvas canvas, Size box) {
    canvas.save();
    canvas.scale(size / 24);
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    switch (param) {
      case Param.direction:
        break; // drawn by Icons.insights
      case Param.urgency:
        canvas.drawPath(_Paths.flame, Paint.from(fill)..color = color.withValues(alpha: color.a * 0.75));
        canvas.drawPath(_Paths.scales, fill);
      case Param.weight:
        if (size >= 20) {
          _paintKg(canvas, color);
        } else {
          canvas.drawPath(_Paths.kettlebell, fill);
        }
      case Param.progress:
        canvas.drawPath(_Paths.checkBadge, fill);
        canvas.drawPath(_Paths.barFrame, fill);
        canvas.drawPath(_Paths.barFill, fill);
      case Param.level:
        canvas.drawPath(_Paths.stars, fill);
        canvas.drawPath(
            _Paths.stars,
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4
              ..strokeJoin = StrokeJoin.round
              ..isAntiAlias = true);
      case Param.fact:
        canvas.drawPath(_Paths.target, fill);
      case Param.plan:
      case Param.actual:
      case Param.categories:
      case Param.accounts:
      case Param.transactions:
      case Param.notes:
      case Param.connected:
      case Param.manual:
        paintLineIcon(canvas, param, color);
    }
    canvas.restore();
  }

  // "KG" is punched out of the kettlebell body (only used at >= 20 px).
  static TextPainter? _kg;
  void _paintKg(Canvas canvas, Color c) {
    final tp = _kg ??= TextPainter(
      text: TextSpan(
          text: 'KG',
          style: TextStyle(
              fontSize: 6.6,
              fontWeight: FontWeight.w900,
              height: 1,
              foreground: Paint()..blendMode = BlendMode.clear)),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.saveLayer(const Rect.fromLTWH(0, 0, 24, 24), Paint());
    canvas.drawPath(_Paths.kettlebell, Paint()..color = c);
    tp.paint(canvas, Offset(12 - tp.width / 2, 17 - tp.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(ParamIconPainter old) =>
      old.color != color || old.size != size || old.param != param;
}

/// Static, build-once geometry in the 24x24 box.
class _Paths {
  static final Path flame = _buildFlame();
  static final Path scales = _smallScales(0);
  static final Path kettlebell = _buildKettlebell();
  static final Path barFrame = _buildBarFrame();
  static final Path barFill = _buildBarFill();
  static final Path checkBadge = _buildCheckBadge();
  static final Path stars = _buildStars();
  static final Path target = _buildTarget();

  static Path _buildFlame() {
    final p = Path()
      ..moveTo(13.6, 0.8)
      ..cubicTo(13.2, 3.6, 21.6, 8.2, 21.6, 14.6)
      ..cubicTo(21.6, 19.2, 17.2, 22.8, 12, 22.8)
      ..cubicTo(6.8, 22.8, 2.4, 19.2, 2.4, 14.6)
      ..cubicTo(2.4, 11.6, 4.0, 9.4, 5.6, 8.0)
      ..cubicTo(5.6, 10.0, 6.8, 11.2, 8.0, 11.6)
      ..cubicTo(7.2, 7.0, 10.4, 3.2, 13.6, 0.8)
      ..close();
    // Gap around the scales, built once.
    return Path.combine(PathOperation.difference, p, _smallScales(1.3));
  }

  /// The scales shrunk toward the bottom so the flame shows around them.
  static Path _smallScales(double g) {
    final m = Matrix4.identity()
      ..translateByDouble(12.0, 22.0, 0.0, 1.0)
      ..scaleByDouble(0.74, 0.74, 1.0, 1.0)
      ..translateByDouble(-12.0, -22.0, 0.0, 1.0);
    return _scales(g / 0.74).transform(m.storage);
  }

  /// Balance scales: pivot, beam, two strings + pans, stem, base. [g] grows
  /// every part (used to cut the gap out of the flame).
  static Path _scales(double g) {
    final p = Path();
    // Pivot circle on top.
    p.addOval(Rect.fromCircle(center: const Offset(12, 5.2), radius: 1.9 + g));
    // Beam.
    p.addRRect(RRect.fromRectAndRadius(
        Rect.fromLTRB(3, 7.2, 21, 9.0).inflate(g), Radius.circular(0.9 + g)));
    // Stem and base.
    p.addPath(
        Path()
          ..moveTo(10.9 - g, 8)
          ..lineTo(13.1 + g, 8)
          ..lineTo(13.6 + g, 20)
          ..lineTo(10.4 - g, 20)
          ..close(),
        Offset.zero);
    p.addRRect(RRect.fromRectAndRadius(
        Rect.fromLTRB(7, 19.6, 17, 22.2).inflate(g), Radius.circular(1.2 + g)));
    // Pans (half discs) and their strings (thin triangles).
    for (final cx in const [5.0, 19.0]) {
      final bowl = Path()
        ..moveTo(cx - 3.6 - g, 15)
        ..lineTo(cx + 3.6 + g, 15)
        ..arcToPoint(Offset(cx - 3.6 - g, 15),
            radius: Radius.circular(3.6 + g), clockwise: true)
        ..close();
      p.addPath(bowl, Offset.zero);
      final w = 0.75 + g;
      for (final dx in const [-1.0, 1.0]) {
        final x = cx + dx * 3.1;
        p.addPath(
            Path()
              ..moveTo(cx - w, 8.4)
              ..lineTo(cx + w, 8.4)
              ..lineTo(x + w * dx.sign.abs(), 14.8)
              ..lineTo(x - w, 14.8)
              ..close(),
            Offset.zero);
      }
    }
    return p;
  }

  static Path _buildKettlebell() {
    final ring = Path()
      ..addOval(Rect.fromCircle(center: const Offset(12, 6.6), radius: 4.6));
    final hole = Path()
      ..addOval(Rect.fromCircle(center: const Offset(12, 6.6), radius: 2.1));
    final body = Path()
      ..moveTo(6.4, 9.6)
      ..lineTo(17.6, 9.6)
      ..quadraticBezierTo(18.8, 9.6, 19.1, 10.8)
      ..lineTo(21.8, 20.4)
      ..quadraticBezierTo(22.2, 22.2, 20.4, 22.2)
      ..lineTo(3.6, 22.2)
      ..quadraticBezierTo(1.8, 22.2, 2.2, 20.4)
      ..lineTo(4.9, 10.8)
      ..quadraticBezierTo(5.2, 9.6, 6.4, 9.6)
      ..close();
    final solid = Path.combine(PathOperation.union, ring, body);
    return Path.combine(PathOperation.difference, solid, hole);
  }

  static Path _buildBarFrame() {
    final outer = Path()
      ..addRRect(RRect.fromRectAndRadius(
          const Rect.fromLTRB(1, 14.2, 23, 22.2), const Radius.circular(4)));
    final inner = Path()
      ..addRRect(RRect.fromRectAndRadius(
          const Rect.fromLTRB(2.9, 16.1, 21.1, 20.3), const Radius.circular(2.1)));
    return Path.combine(PathOperation.difference, outer, inner);
  }

  static Path _buildBarFill() => Path()
    ..addRRect(RRect.fromRectAndRadius(
        const Rect.fromLTRB(4.6, 17.5, 14.6, 18.9), const Radius.circular(0.7)));

  static Path _buildCheckBadge() {
    final disc = Path()..addOval(Rect.fromCircle(center: const Offset(12, 7), radius: 6));
    final check = Path()
      ..moveTo(8.8, 7.5)
      ..lineTo(10.0, 6.4)
      ..lineTo(11.3, 7.7)
      ..lineTo(14.2, 4.5)
      ..lineTo(15.5, 5.7)
      ..lineTo(11.3, 10.2)
      ..close();
    return Path.combine(PathOperation.difference, disc, check);
  }

  /// Bullseye: outer ring, inner ring and a centre dot (one solid path).
  static Path _buildTarget() {
    Path ring(double outer, double inner) => Path.combine(
        PathOperation.difference,
        Path()..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: outer)),
        Path()..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: inner)));
    final dot = Path()..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 3.2));
    return Path.combine(PathOperation.union,
        Path.combine(PathOperation.union, ring(10.8, 8.2), ring(6.2, 4.6)), dot);
  }

  static Path _star(double cx, double cy, double r) {
    final p = Path();
    for (var i = 0; i < 10; i++) {
      final rad = i.isEven ? r : r * 0.5;
      final a = -math.pi / 2 + i * math.pi / 5;
      final x = cx + rad * math.cos(a);
      final y = cy + rad * math.sin(a);
      if (i == 0) {
        p.moveTo(x, y);
      } else {
        p.lineTo(x, y);
      }
    }
    return p..close();
  }

  static Path _buildStars() => Path()
    ..addPath(_star(12, 7.4, 5.6), Offset.zero)
    ..addPath(_star(6, 17, 4.9), Offset.zero)
    ..addPath(_star(18, 17, 4.9), Offset.zero);
}
