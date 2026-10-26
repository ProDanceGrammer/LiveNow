import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/growth_rules.dart';
import '../undo.dart';
import 'growth_direction_dialog.dart';

/// The right-click / long-press menu of a growth direction (Mindmap node,
/// List row, Balance row): Open or Duplicate (one Undo removes the copy).
/// Created at the file location functionally required by the three callers.
Future<void> showDirectionMenu(
  BuildContext context,
  WidgetRef ref,
  GrowthMetric m,
  Offset globalPosition,
) async {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final choice = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(
      globalPosition & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    items: const [
      PopupMenuItem(
        key: ValueKey('direction-menu-open'),
        value: 'open',
        child: Text('Open'),
      ),
      PopupMenuItem(
        key: ValueKey('direction-menu-duplicate'),
        value: 'duplicate',
        child: Text('Duplicate'),
      ),
    ],
  );
  if (!context.mounted) return;
  if (choice == 'open') {
    GrowthDirectionDialog.show(context, existing: m);
  } else if (choice == 'duplicate') {
    await runUndoableDuplicateMetric(context, ref, id: m.id, name: m.name);
  }
}

/// Where a long press on [context]'s widget happened: its centre (the touch
/// callbacks of ListTile / InkWell give no position).
Offset centerOf(BuildContext context) {
  final box = context.findRenderObject()! as RenderBox;
  return box.localToGlobal(box.size.center(Offset.zero));
}
