import 'package:flutter/material.dart';

import '../../domain/action_import_service.dart';
import '../../domain/template_import_service.dart';
import '../dialog_stack.dart';

/// Shows what an actions CSV import did: counts plus the lists the user may
/// want to fix (unmatched directions, unresolved references, refused edges).
class ActionImportSummaryDialog extends StatelessWidget {
  const ActionImportSummaryDialog({super.key, required this.result});

  final ActionImportResult result;

  static Future<void> show(BuildContext context, ActionImportResult result) =>
      showStackedDialog<void>(
        context: context,
        builder: (_) => ActionImportSummaryDialog(result: result),
      );

  Widget _list(BuildContext context, String title, List<String> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title (${items.length})',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          for (final s in items) Text(s),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = result;
    return AlertDialog(
      title: const Text('Import finished'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${r.created} created'),
              Text('${r.skippedDuplicates} skipped as duplicates'),
              Text('${r.edgesCreated} next/previous links created'),
              if (r.doneApplied > 0)
                Text('${r.doneApplied} all-day actions had their Done changed'),
              if (r.doneIgnoredTimed > 0)
                Text(
                  '${r.doneIgnoredTimed} Done values ignored on timed actions '
                  '(they are done by their end time)',
                ),
              _list(
                context,
                'Unmatched growth directions',
                r.unmatchedDirections,
              ),
              _list(
                context,
                'Unresolved next/previous references',
                r.unresolvedRefs,
              ),
              _list(context, 'Links refused', r.rejectedEdges),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

/// Summary of a templates CSV import.
class TemplateImportSummaryDialog extends StatelessWidget {
  const TemplateImportSummaryDialog({super.key, required this.result});

  final TemplateImportResult result;

  static Future<void> show(BuildContext context, TemplateImportResult result) =>
      showStackedDialog<void>(
        context: context,
        builder: (_) => TemplateImportSummaryDialog(result: result),
      );

  @override
  Widget build(BuildContext context) {
    final r = result;
    return AlertDialog(
      title: const Text('Import finished'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${r.created} templates created'),
              Text('${r.skipped} skipped (name already a template)'),
              if (r.linksIgnored > 0)
                Text(
                  '${r.linksIgnored} rows had next/previous links (ignored)',
                ),
              if (r.unmatchedDirections.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Unmatched growth directions (${r.unmatchedDirections.length})',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                for (final s in r.unmatchedDirections) Text(s),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
