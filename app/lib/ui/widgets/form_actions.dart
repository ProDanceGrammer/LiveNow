import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/form_effects.dart';
import '../../domain/form_service.dart';
import '../dialog_stack.dart';
import '../form_providers.dart';
import '../providers.dart';
import '../undo.dart';
import 'app_toast.dart';
import 'direction_badge.dart' show emojiLabelStyle;
import 'form_fill.dart';

/// The form to fill: the only one when there is just one, else a list with the
/// last used first. Null when there is none (a hint says where to make one) or
/// the owner cancels.
Future<FormItem?> pickForm(BuildContext context, WidgetRef ref) async {
  final forms = await ref.read(formServiceProvider).all();
  if (!context.mounted) return null;
  if (forms.isEmpty) {
    showInfoToast(
      rootOverlayOf(context),
      'No forms yet. Create one in Actions > Forms.',
    );
    return null;
  }
  if (forms.length == 1) return forms.first;
  final last = ref.read(lastFormIdProvider);
  final ordered = [
    ...forms.where((f) => f.id == last),
    ...forms.where((f) => f.id != last),
  ];
  return showStackedDialog<FormItem>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: const Text('Fill a form'),
      children: [
        for (final f in ordered)
          SimpleDialogOption(
            key: ValueKey('form-pick-${f.id}'),
            onPressed: () => Navigator.of(dialogContext).pop(f),
            child: Text(f.def.display, style: emojiLabelStyle),
          ),
      ],
    ),
  );
}

/// Picks a form and lets the owner fill it for [actionIds]: the form and what
/// its answers add, or null when cancelled. Nothing is written here.
Future<({FormItem form, FormEffects effects})?> fillForm(
  BuildContext context,
  WidgetRef ref,
  List<String> actionIds,
) async {
  final form = await pickForm(context, ref);
  if (form == null || !context.mounted) return null;
  ref.read(lastFormIdProvider.notifier).state = form.id;

  // The names go into the header's tooltip (a few are enough).
  final db = ref.read(databaseProvider);
  final shown = actionIds.take(12).toList();
  final names = shown.isEmpty
      ? <String>[]
      : [
          for (final r in await db
              .customSelect(
                'SELECT name FROM actions WHERE id IN '
                '(${List.filled(shown.length, '?').join(',')})',
                variables: [for (final id in shown) Variable.withString(id)],
              )
              .get())
            r.read<String>('name'),
        ];
  if (!context.mounted) return null;

  final effects = await FormFillDialog.show(
    context,
    form: form,
    actionCount: actionIds.length,
    actionNames: names,
  );
  if (effects == null) return null;
  return (form: form, effects: effects);
}

/// "Fill a form" for the selected actions of a bulk bar: pick, fill, and apply
/// as ONE undoable step.
Future<void> runBulkForm(
  BuildContext context,
  WidgetRef ref,
  List<String> actionIds,
) async {
  if (actionIds.isEmpty) return;
  final filled = await fillForm(context, ref, actionIds);
  if (filled == null || !context.mounted) return;
  await runUndoableApplyForm(
    context,
    ref,
    actionIds,
    filled.effects,
    filled.form.name,
  );
}
