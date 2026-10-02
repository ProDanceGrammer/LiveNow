import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One entry of an [InstantRail].
class InstantRailItem {
  const InstantRailItem({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

/// A vertical navigation rail that looks like Material's [NavigationRail]
/// (`labelType: all`, rounded indicator pill behind the selected icon) but
/// changes selection in ONE frame: no indicator slide, no label size/opacity
/// animation and no ink splash. `NavigationRail` runs internal
/// AnimationControllers (and a ripple) that keep repainting a large area for
/// about a second after each click, which is what made section switches janky.
///
/// Colours come from the ambient [NavigationRailThemeData], so the theme stays
/// the single source of the look. Each item is a button with a [Semantics]
/// label and a `selected` flag, is focusable (Tab) and activates with
/// Enter/Space.
class InstantRail extends StatelessWidget {
  const InstantRail({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.collapsed = false,
    this.onToggleCollapsed,
  });

  final List<InstantRailItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// Icon-only strip ([collapsedWidth] wide); the width change is instant.
  final bool collapsed;

  /// Called by the hide/show button; no button is drawn when null.
  final VoidCallback? onToggleCollapsed;

  static const double width = 148;
  static const double collapsedWidth = 56;

  /// Label box: narrower than the rail so 'Growth directions' wraps onto two
  /// lines ('Growth' / 'directions'); every label gets the same two-line
  /// height so the items keep an even rhythm.
  static const double labelWidth = 84;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: collapsed ? collapsedWidth : width,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onToggleCollapsed != null)
              Align(
                alignment: collapsed ? Alignment.center : Alignment.centerRight,
                child: Padding(
                  padding: EdgeInsets.only(right: collapsed ? 0 : 4),
                  child: IconButton(
                    key: const ValueKey('rail-toggle'),
                    visualDensity: VisualDensity.compact,
                    tooltip: collapsed ? 'Show menu' : 'Hide menu',
                    icon: Icon(
                      collapsed ? Icons.menu : Icons.menu_open,
                      size: 22,
                    ),
                    onPressed: onToggleCollapsed,
                  ),
                ),
              ),
            if (onToggleCollapsed != null) const SizedBox(height: 4),
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: EdgeInsets.only(
                  bottom: i == items.length - 1 ? 0 : 12,
                ),
                child: _RailItem(
                  item: items[i],
                  selected: i == selectedIndex,
                  collapsed: collapsed,
                  onTap: () => onSelected(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RailItem extends StatefulWidget {
  const _RailItem({
    required this.item,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final InstantRailItem item;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rail = theme.navigationRailTheme;
    final scheme = theme.colorScheme;
    final selected = widget.selected;

    final iconColor =
        (selected ? rail.selectedIconTheme : rail.unselectedIconTheme)?.color ??
        (selected ? scheme.primary : scheme.onSurfaceVariant);
    final labelStyle =
        (selected
            ? rail.selectedLabelTextStyle
            : rail.unselectedLabelTextStyle) ??
        theme.textTheme.labelMedium!;
    final indicatorColor = rail.indicatorColor ?? scheme.secondaryContainer;
    final shape =
        rail.indicatorShape ??
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));

    final Color pill;
    if (selected) {
      pill = indicatorColor;
    } else if (_hovered || _focused) {
      pill = scheme.onSurface.withValues(alpha: _focused ? 0.12 : 0.08);
    } else {
      pill = Colors.transparent;
    }

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: widget.item.label,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (v) => setState(() => _hovered = v),
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: SizedBox(
            width: widget.collapsed
                ? InstantRail.collapsedWidth
                : InstantRail.width,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: ShapeDecoration(color: pill, shape: shape),
                  child: SizedBox(
                    width: widget.collapsed ? 44 : 56,
                    height: widget.collapsed ? 40 : 32,
                    child: Tooltip(
                      message: widget.collapsed ? widget.item.label : '',
                      child: Icon(widget.item.icon, color: iconColor, size: 24),
                    ),
                  ),
                ),
                if (!widget.collapsed) ...[
                  const SizedBox(height: 4),
                  SizedBox(
                    width: InstantRail.labelWidth,
                    // Two lines of the real font (line height ~1.5) plus slack,
                    // or the second line gets clipped.
                    height: (labelStyle.fontSize ?? 12) * 1.6 * 2 + 4,
                    child: Text(
                      widget.item.label,
                      style: labelStyle,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      softWrap: true,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
