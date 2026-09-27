import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'widgets/action_editor.dart';

/// Fetches the current row for [actionId] and opens it in the edit dialog.
/// Shared by every view so a tap on any tile behaves the same way.
Future<void> openActionEditor(
  BuildContext context,
  WidgetRef ref,
  String actionId,
) async {
  final db = ref.read(databaseProvider);
  final row = await (db.select(
    db.actionsTable,
  )..where((t) => t.id.equals(actionId))).getSingle();
  if (context.mounted) {
    await ActionEditorDialog.show(context, existing: row);
  }
}
