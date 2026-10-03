import 'package:flutter/material.dart';

import '../theme/glass_theme.dart';

/// Header padding shared by every `ExpansionTile` inside a [SectionBlock]: a
/// little horizontal room so the hover/ink area is wider than the title. The
/// block's padding is reduced by the same amount ([kSectionTileBlockPadding]),
/// so titles keep their x.
const EdgeInsets kSectionTilePadding = EdgeInsets.symmetric(horizontal: 8);

/// The [SectionBlock] padding to pair with [kSectionTilePadding] (12 - 8 = 4).
const EdgeInsets kSectionTileBlockPadding = EdgeInsets.symmetric(
  horizontal: 4,
  vertical: 4,
);

/// Body padding of those tiles (a little air below the header).
const EdgeInsets kSectionChildrenPadding = EdgeInsets.only(top: 8, bottom: 8);

/// A rounded, slightly filled panel with a 1 px border (glass tokens) that
/// groups one section of an edit dialog. Plain decoration only (no blur, clip
/// or gradient: see the glass performance rules in CLAUDE.md). Inner
/// `ExpansionTile`s should pass `shape`/`collapsedShape: Border()` so they draw
/// no divider lines inside the block.
class SectionBlock extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  const SectionBlock({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    this.margin = const EdgeInsets.only(top: 8),
  });

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    return Container(
      width: double.infinity,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: g.fill.withValues(alpha: g.fill.a * 0.5),
        borderRadius: BorderRadius.circular(GlassTheme.radiusControl),
        border: Border.all(color: g.border, width: 1),
      ),
      child: child,
    );
  }
}
