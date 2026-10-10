import 'package:flutter/material.dart';

import '../../domain/budget_io_service.dart';
import '../dialog_stack.dart';

/// What a budget import did: the counts, then everything that was skipped,
/// guessed or needs a manual look.
class BudgetImportSummaryDialog extends StatelessWidget {
  const BudgetImportSummaryDialog({
    super.key,
    required this.summary,
    this.ignoredFiles = const [],
  });

  final BudgetImportSummary summary;

  /// Files that were chosen but not recognised.
  final List<String> ignoredFiles;

  static Future<void> show(
    BuildContext context,
    BudgetImportSummary summary, {
    List<String> ignoredFiles = const [],
  }) => showStackedDialog<void>(
    context: context,
    builder: (_) =>
        BudgetImportSummaryDialog(summary: summary, ignoredFiles: ignoredFiles),
  );

  @override
  Widget build(BuildContext context) {
    final s = summary;
    Widget line(String text) =>
        Padding(padding: const EdgeInsets.only(top: 4), child: Text(text));
    Widget note(String title, List<String> items) => items.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                for (final i in items.take(8)) Text('• $i'),
                if (items.length > 8) Text('… and ${items.length - 8} more'),
              ],
            ),
          );

    return AlertDialog(
      title: const Text('Budget import finished'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              line('${s.accounts} accounts'),
              line('${s.categories} categories'),
              line('${s.transactions} transactions'),
              if (s.linkedToActions > 0)
                line(
                  '${s.linkedToActions} transactions linked to your actions',
                ),
              note('Skipped', [
                if (s.skippedNoCategory > 0)
                  '${s.skippedNoCategory} transaction rows without a category',
                if (s.skippedNoDate > 0)
                  '${s.skippedNoDate} transactions without a date '
                      '(they had no action either)',
                if (s.skippedGroupCategory > 0)
                  '${s.skippedGroupCategory} transactions on a group category',
              ]),
              note('Please check', [
                if (s.actionsNotFound > 0)
                  '${s.actionsNotFound} transactions name an action that is not '
                      'in the app (import your actions first); they keep their '
                      'own date',
                for (final a in s.ratesMissing)
                  'Account "$a": no exchange rate found, left at 1 — set it',
                for (final a in s.currencyGuessed)
                  'Account "$a": currency unknown (XXX) — set it',
                for (final a in s.unknownAccounts)
                  'Account "$a" is used but not in the accounts file (created)',
              ]),
              note(
                'Exchange rate far from the current rate of its account '
                '(typo in the source?)',
                s.suspiciousRates,
              ),
              note('Not found in the file', [
                ...s.unresolvedChildren.map((c) => 'Sub-category $c'),
                ...s.unresolvedPercentSources.map((c) => 'Percent source $c'),
              ]),
              note('Ignored files', ignoredFiles),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          key: const ValueKey('budget-import-ok'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
