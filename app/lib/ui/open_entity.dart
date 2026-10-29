import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/growth_rules.dart';
import 'dialog_stack.dart';
import 'providers.dart';
import 'widgets/action_editor.dart';
import 'widgets/app_toast.dart' show showMissingToast;
import 'widgets/growth_direction_dialog.dart';

// Rule: every entity shown inside an edit menu (chips, lists) must be
// openable from there. Add the matching `open<Entity>ById` here and call it
// from the chip, so a new entity type cannot become a dead end. Each helper
// stacks the editor on top of the current dialog (see `showStackedDialog`),
// so unsaved edits underneath survive and closing returns to them.

/// Opens the editor of the action [id] on top of the current dialog.
Future<void> openActionById(
  BuildContext context,
  WidgetRef ref,
  String id,
) async {
  // Read before the await: the caller's `ref` can be gone afterwards.
  final db = ref.read(databaseProvider);
  // The edit dialog below (if any) saves first, so the row read next is current.
  await saveOpenEditorBeforeOpening();
  final row = await (db.select(
    db.actionsTable,
  )..where((t) => t.id.equals(id))).getSingleOrNull();
  if (!context.mounted) return;
  if (row == null) return showMissingToast(context, 'action');
  await ActionEditorDialog.show(context, existing: row);
}

/// Opens the dialog of the growth direction [id] on top of the current dialog.
Future<void> openDirectionById(
  BuildContext context,
  WidgetRef ref,
  String id,
) async {
  final db = ref.read(databaseProvider);
  await saveOpenEditorBeforeOpening();
  final row = await (db.select(
    db.metricsTable,
  )..where((t) => t.id.equals(id))).getSingleOrNull();
  if (!context.mounted) return;
  if (row == null) return showMissingToast(context, 'growth direction');
  await GrowthDirectionDialog.show(
    context,
    existing: GrowthMetric.fromRow(row),
  );
}
