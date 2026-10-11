import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/glass_theme.dart';
import 'glass_icon_tile.dart';
import 'quick_action_bar.dart';

/// The phone's long-press menu for a Current card: a list that slides up from
/// the bottom, one labelled row per quick action with the same coloured icon
/// as the icon bar (see [quickActionSpecs]), plus "Select" for bulk delete.
///
/// [context] and [ref] are the card's: the specs are built from them BEFORE the
/// sheet opens, and a chosen action runs after the sheet has closed (the sheet's
/// own context is gone by then, the card's is not).
Future<void> showQuickActionSheet(
  BuildContext context,
  WidgetRef ref, {
  required String actionId,
  required String title,
  required VoidCallback onSelect,
  required VoidCallback onDelete,
}) async {
  final specs = quickActionSpecs(context, ref, actionId, onDelete: onDelete);
  final chosen = await showModalBottomSheet<Object>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _QuickActionSheet(title: title, specs: specs),
  );
  if (chosen == null || !context.mounted) return;
  if (chosen == _selectToken) {
    onSelect();
  } else if (chosen is QuickActionSpec) {
    await chosen.onTap();
  }
}

const _selectToken = Object();

class _QuickActionSheet extends StatelessWidget {
  const _QuickActionSheet({required this.title, required this.specs});

  final String title;
  final List<QuickActionSpec> specs;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final theme = Theme.of(context);

    Widget row(
      IconData icon,
      GlassHue hue,
      String label,
      Object result, {
      Key? key,
    }) => ListTile(
      key: key,
      leading: IgnorePointer(
        child: GlassIconTile(
          icon: icon,
          hue: hue,
          tooltip: '',
          onTap: () {},
          size: 40,
          iconSize: 24,
          hitExtra: 0,
        ),
      ),
      title: Text(label),
      onTap: () => Navigator.of(context).pop(result),
    );

    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 2),
      child: Text(text, style: theme.textTheme.labelMedium),
    );

    final children = <Widget>[];
    var lastGroup = -1;
    for (final s in specs) {
      if (s.group != lastGroup) {
        if (s.group == 1) children.add(header('Postpone'));
        if (s.group == 2) children.add(const Divider(height: 8));
        lastGroup = s.group;
      }
      // Postpone rows drop the repeated "Postpone" prefix under the header.
      final label = s.group == 1
          ? s.label.replaceFirst(RegExp(r'^Postpone:?\s*'), '')
          : s.label;
      children.add(
        row(
          s.icon,
          s.hue,
          label.isEmpty ? s.label : _cap(label),
          s,
          key: ValueKey('quick-action-${s.label}'),
        ),
      );
    }
    // Selecting goes right after the "act now" rows.
    final firstPostpone = specs.indexWhere((s) => s.group == 1);
    final selectRow = row(
      Icons.check_circle_outline_rounded,
      GlassHue.blue,
      'Select',
      _selectToken,
      key: const ValueKey('quick-action-select'),
    );
    // children[0..] holds the 3 act-now rows first (no header for group 0).
    children.insert(
      firstPostpone < 0 ? children.length : firstPostpone,
      selectRow,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: g.fillDialog,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: g.border),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Flexible(child: ListView(shrinkWrap: true, children: children)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _cap(String s) => s[0].toUpperCase() + s.substring(1);
}
