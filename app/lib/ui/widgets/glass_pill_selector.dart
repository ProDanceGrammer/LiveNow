import 'package:flutter/material.dart';

import '../theme/glass_theme.dart';

/// A labelled row of pill buttons where exactly one is selected (a segmented
/// control). Solid fills and no per-item animation, so it stays cheap; the
/// pills wrap onto the next line when the row is too narrow.
class GlassPillSelector<T> extends StatelessWidget {
  const GlassPillSelector({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    this.icons,
  });

  final String label;

  /// Value -> pill text, in display order.
  final Map<T, String> options;

  /// Values drawn as an ICON instead of their text (the text becomes the
  /// tooltip and the semantic label): e.g. the Expense / Income arrows.
  final Map<T, Widget>? icons;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: g.textSecondary),
            ),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final entry in options.entries)
                _Pill(
                  text: entry.value,
                  icon: icons?[entry.key],
                  selected: entry.key == value,
                  fill: g.dark
                      ? const Color(0x14FFFFFF)
                      : const Color(0xFFE4ECFF),
                  border: g.border,
                  selectedFill: scheme.primaryContainer,
                  selectedText: scheme.onPrimaryContainer,
                  selectedBorder: scheme.primary,
                  text0: g.textPrimary,
                  onTap: () => onChanged(entry.key),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.text,
    this.icon,
    required this.selected,
    required this.fill,
    required this.border,
    required this.selectedFill,
    required this.selectedText,
    required this.selectedBorder,
    required this.text0,
    required this.onTap,
  });

  final String text;
  final Widget? icon;
  final bool selected;
  final Color fill;
  final Color border;
  final Color selectedFill;
  final Color selectedText;
  final Color selectedBorder;
  final Color text0;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pill = Semantics(
      button: true,
      selected: selected,
      label: icon == null ? null : text,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? selectedFill : fill,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? selectedBorder : border,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: icon ??
              Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? selectedText : text0,
                ),
              ),
        ),
      ),
    );
    return icon == null ? pill : Tooltip(message: text, child: pill);
  }
}
