import 'package:flutter/material.dart';

import '../theme/glass_theme.dart';
import 'continue_icon.dart';

/// Which palette hue a [GlassIconTile] is tinted with.
enum GlassHue { blue, green, lavender, pink, cyan, peach, error }

/// A small tinted icon tile: a rounded square with a pastel tint fill, a thin
/// bright border and a contrasting icon (the hue pushed dark in the light
/// theme, light in the dark one). Deliberately just one DecoratedBox + one
/// Icon (no shadow, gradient or blur): many of these are repeated on screen.
///
/// The tappable area is [size] + [hitExtra] square, so the visible tile can be
/// small while the hit target stays predictable. Needs a [Material] ancestor
/// (for the ink).
class GlassIconTile extends StatefulWidget {
  final IconData icon;
  final GlassHue hue;
  final String tooltip;
  final VoidCallback onTap;

  /// False = dimmed and not tappable (the tooltip still explains why).
  final bool enabled;

  /// Edge of the visible rounded square.
  final double size;
  final double iconSize;

  /// Extra hit area around the visible tile (total, split over both sides).
  final double hitExtra;

  const GlassIconTile({
    super.key,
    required this.icon,
    required this.hue,
    required this.tooltip,
    required this.onTap,
    this.size = 32,
    this.iconSize = 20,
    this.hitExtra = 4,
    this.enabled = true,
  });

  @override
  State<GlassIconTile> createState() => _GlassIconTileState();
}

class _GlassIconTileState extends State<GlassIconTile> {
  bool _hover = false;

  Color _base(BuildContext context) {
    final g = context.glass;
    switch (widget.hue) {
      case GlassHue.blue:
        return g.blue;
      case GlassHue.green:
        return g.green;
      case GlassHue.lavender:
        return g.lavender;
      case GlassHue.pink:
        return g.pink;
      case GlassHue.cyan:
        return g.cyan;
      case GlassHue.peach:
        // The warm end of the palette: the pink accent turned towards amber.
        return HSLColor.fromColor(g.pink).withHue(32).toColor();
      case GlassHue.error:
        return Theme.of(context).colorScheme.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final base = _base(context);
    // Same hue, pushed dark (light theme) or light (dark theme) for contrast.
    final iconColor = HSLColor.fromColor(base)
        .withLightness(g.dark ? 0.82 : 0.30)
        .toColor();
    final tint = (g.dark ? 0.24 : 0.18) + (_hover ? 0.12 : 0.0);
    final radius = BorderRadius.circular(widget.size * 0.375);

    final tile = Tooltip(
      message: widget.tooltip,
      child: InkWell(
        borderRadius: radius,
        onTap: widget.enabled ? widget.onTap : null,
        onHover: (h) => setState(() => _hover = h),
        hoverColor: Colors.transparent,
        splashColor: base.withValues(alpha: 0.2),
        highlightColor: Colors.transparent,
        child: SizedBox(
          width: widget.size + widget.hitExtra,
          height: widget.size + widget.hitExtra,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: base.withValues(alpha: tint),
                borderRadius: radius,
                border: Border.all(
                  color: g.border.withValues(alpha: g.border.a * 0.7),
                ),
              ),
              child: SizedBox(
                width: widget.size,
                height: widget.size,
                child: widget.icon == continueIconData
                    ? Center(
                        child: ContinueIcon(
                          size: widget.iconSize,
                          color: iconColor,
                        ),
                      )
                    : Icon(
                        widget.icon,
                        size: widget.iconSize,
                        color: iconColor,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
    return widget.enabled ? tile : Opacity(opacity: 0.38, child: tile);
  }
}
