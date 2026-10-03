import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import 'quick_time_edit_dialog.dart';

/// Underlined, clickable time text of an action (cards, list tiles). Tapping
/// it opens [QuickTimeEditDialog] and saves with Undo. Not used on calendar
/// blocks.
class ActionTimeLabel extends ConsumerWidget {
  final ActionListItem action;
  final String text;
  final TextStyle? style;

  const ActionTimeLabel({
    super.key,
    required this.action,
    required this.text,
    this.style,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = style?.color ?? Theme.of(context).colorScheme.secondary;
    return InkWell(
      onTap: () => QuickTimeEditDialog.editAction(context, ref, action),
      child: Text(
        text,
        style: (style ?? const TextStyle()).copyWith(
          color: color,
          decoration: TextDecoration.underline,
          decorationColor: color.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}
