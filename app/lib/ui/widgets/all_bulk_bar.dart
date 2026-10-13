import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/bulk_edit_service.dart' show LinkSide;
import '../all_selection.dart';
import '../layout.dart';
import '../undo.dart';
import '../views/all_actions_view.dart' show filteredAllActionsProvider;
import 'bulk_dialogs.dart';
import 'continue_icon.dart';

/// The row above the All list: a tri-state "select all" checkbox (it covers the
/// WHOLE filtered list, also the rows not on screen), how many are selected and,
/// once any is, the bulk actions: growth directions, previous / next action,
/// date, delete. Every bulk edit is one transaction with ONE Undo.
class AllBulkBar extends ConsumerWidget {
  const AllBulkBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(filteredAllActionsProvider).value;
    if (items == null || items.isEmpty) return const SizedBox(height: 8);
    final selection = ref.watch(allSelectionProvider);
    final notifier = ref.read(allSelectionProvider.notifier);
    final n = selection.length;
    final all = n >= items.length;
    final phone = usePhoneLayout(context);

    Widget action(
      String key,
      Widget icon,
      String label,
      VoidCallback onPressed, {
      Color? color,
    }) => phone
        ? IconButton(
            key: ValueKey(key),
            tooltip: label,
            icon: icon,
            color: color,
            onPressed: onPressed,
          )
        : TextButton.icon(
            key: ValueKey(key),
            icon: IconTheme.merge(
              data: const IconThemeData(size: 18),
              child: icon,
            ),
            label: Text(label, style: TextStyle(color: color)),
            style: color == null
                ? null
                : TextButton.styleFrom(foregroundColor: color),
            onPressed: onPressed,
          );

    List<String> ids() => selection.toList();

    return Padding(
      key: const ValueKey('all-bulk-bar'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(
        children: [
          Checkbox(
            key: const ValueKey('all-select-all'),
            tristate: true,
            value: n == 0 ? false : (all ? true : null),
            onChanged: (_) => all
                ? notifier.clear()
                : notifier.setAll([for (final a in items) a.id]),
          ),
          Text(n == 0 ? 'Select all' : '$n selected'),
          if (n > 0)
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    action(
                      'bulk-directions',
                      const Icon(Icons.insights),
                      'Directions',
                      () => runBulkDirections(context, ref, ids()),
                    ),
                    action(
                      'bulk-previous',
                      // The Continue arrow mirrored: the action BEFORE.
                      const ContinueGlyph(mirrored: true),
                      'Previous',
                      () => runBulkLinks(context, ref, ids(), LinkSide.previous),
                    ),
                    action(
                      'bulk-next',
                      // The Continue arrow: the action AFTER.
                      const ContinueGlyph(),
                      'Next',
                      () => runBulkLinks(context, ref, ids(), LinkSide.next),
                    ),
                    action(
                      'bulk-date',
                      const Icon(Icons.event),
                      'Date',
                      () => runBulkDate(context, ref, [
                        for (final a in items)
                          if (selection.contains(a.id)) a,
                      ]),
                    ),
                    action(
                      'bulk-delete',
                      const Icon(Icons.delete_outline),
                      'Delete',
                      () {
                        final list = ids();
                        notifier.clear();
                        runUndoableDeleteMany(context, ref, list);
                      },
                      color: Theme.of(context).colorScheme.error,
                    ),
                    IconButton(
                      key: const ValueKey('bulk-clear'),
                      tooltip: 'Clear selection',
                      icon: const Icon(Icons.close),
                      onPressed: notifier.clear,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
