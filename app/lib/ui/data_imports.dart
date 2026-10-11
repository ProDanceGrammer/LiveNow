import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/budget_csv.dart';
import '../domain/budget_icons.dart';
import '../domain/budget_io_service.dart';
import '../domain/notion_icons.dart';
import 'budget_files.dart';
import 'dialog_stack.dart';
import 'providers.dart';
import 'screens/actions_section.dart'
    show actionImportServiceProvider, actionsCsvPickerProvider;
import 'screens/growth_directions_screen.dart'
    show growthCsvPickerProvider, notionPagesPickerProvider;
import 'screens/templates_screen.dart' show templateImportServiceProvider;
import 'widgets/action_import_summary_dialog.dart';
import 'widgets/app_toast.dart';
import 'widgets/budget_import_summary_dialog.dart';

// Every import/export flow of the app, as plain functions of a context and a
// ref, so the section screens and the Settings page run the very same code.
// Each one reads what it needs from `context`/`ref` before its first await.

/// Notion actions export (CSV) -> actions.
Future<void> importActionsCsv(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final service = ref.read(actionImportServiceProvider);
  final text = await ref.read(actionsCsvPickerProvider)();
  if (text == null || !context.mounted) return;
  try {
    final result = await service.importCsv(text);
    if (!context.mounted) return;
    await ActionImportSummaryDialog.show(context, result);
  } on FormatException catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Import failed: ${e.message}')),
    );
  }
}

/// The same Notion export -> templates.
Future<void> importTemplatesCsv(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final service = ref.read(templateImportServiceProvider);
  final text = await ref.read(actionsCsvPickerProvider)();
  if (text == null || !context.mounted) return;
  try {
    final result = await service.importCsv(text);
    if (!context.mounted) return;
    await TemplateImportSummaryDialog.show(context, result);
  } on FormatException catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Import failed: ${e.message}')),
    );
  }
}

/// Notion growth directions export (CSV): replaces every direction.
Future<void> importGrowthCsv(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final pick = ref.read(growthCsvPickerProvider);
  final service = ref.read(metricServiceProvider);

  final text = await pick();
  if (text == null) return;
  try {
    final s = await service.importGrowthDirections(text);
    final notes = [
      if (s.skippedBlank > 0) '${s.skippedBlank} empty rows skipped',
      if (s.unsupported.isNotEmpty)
        '${s.unsupported.length} with an unknown type skipped',
      if (s.unresolved.isNotEmpty)
        '${s.unresolved.length} unknown relations ignored',
    ];
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Imported ${s.directions} growth directions '
          'and ${s.relations} relations'
          '${notes.isEmpty ? '' : ' (${notes.join(', ')})'}.',
        ),
      ),
    );
  } on FormatException catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Import failed: ${e.message}')),
    );
  }
}

/// Sets direction icons from saved Notion pages / a name-emoji list.
Future<void> importGrowthIcons(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final service = ref.read(metricServiceProvider);
  final pages = await ref.read(notionPagesPickerProvider)();
  if (pages.isEmpty) return;
  final icons = <String, String>{};
  final skipped = <String>[];
  for (final html in pages) {
    icons.addAll(parseIconsFile(html, skippedBuiltin: skipped));
  }
  final s = await service.applyIcons(icons);
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        'Set ${s.matched} icons'
        '${s.unmatched.isEmpty ? '' : ' (${s.unmatched.length} not in your directions)'}'
        '${skipped.isEmpty ? '' : ', ${skipped.length} with an unknown built-in icon skipped'}.',
      ),
    ),
  );
}

/// Budget: one JSON backup, or any of the three Notion CSVs (recognised by
/// their header). Replaces the budget data, after asking when there is some.
Future<void> importBudgetData(BuildContext context, WidgetRef ref) async {
  final overlay = rootOverlayOf(context);
  final io = ref.read(budgetIoServiceProvider);
  final files = await ref.read(budgetFilesProvider).pickImportFiles();
  if (files.isEmpty || !context.mounted) return;

  String? backup, accounts, categories, transactions;
  final ignored = <String>[];
  for (final f in files) {
    if (BudgetIoService.looksLikeBackup(f.text)) {
      backup = f.text;
      continue;
    }
    switch (detectBudgetCsv(f.text)) {
      case BudgetCsvKind.accounts:
        accounts = f.text;
      case BudgetCsvKind.categories:
        categories = f.text;
      case BudgetCsvKind.transactions:
        transactions = f.text;
      case null:
        ignored.add(f.name);
    }
  }
  final anyCsv = accounts != null || categories != null || transactions != null;
  if (backup == null && !anyCsv) {
    showInfoToast(overlay, 'No budget data found in the chosen files');
    return;
  }
  if (backup != null && anyCsv) {
    showInfoToast(overlay, 'Choose either one backup file or the CSV files');
    return;
  }

  if (await io.hasData()) {
    if (!context.mounted) return;
    final ok = await showStackedDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Replace the budget data?'),
        content: const Text(
          'The accounts, categories and transactions now in the app will be '
          'replaced by the imported ones. Export a backup first if you may '
          'want them back.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-budget-import'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
  }

  try {
    final summary = backup != null
        ? await io.importJson(backup)
        : await io.importNotionCsvs(
            accountsCsv: accounts,
            categoriesCsv: categories,
            transactionsCsv: transactions,
          );
    if (!context.mounted) return;
    await BudgetImportSummaryDialog.show(
      context,
      summary,
      ignoredFiles: ignored,
    );
  } on FormatException catch (e) {
    showInfoToast(overlay, 'Import failed: ${e.message}');
  }
}

/// Budget category icons: a CSV with `name` and `icon` columns; each matching
/// category's name gets the emoji in front ("👟 Взуття").
Future<void> importBudgetIcons(BuildContext context, WidgetRef ref) async {
  final overlay = rootOverlayOf(context);
  final io = ref.read(budgetIoServiceProvider);
  final files = await ref.read(budgetFilesProvider).pickImportFiles();
  if (files.isEmpty || !context.mounted) return;
  final icons = <CategoryIcon>[];
  for (final f in files) {
    icons.addAll(parseCategoryIcons(f.text));
  }
  if (icons.isEmpty) {
    showInfoToast(
      overlay,
      'No icons found: the file needs "name" and "icon" columns',
    );
    return;
  }
  final r = await io.applyCategoryIcons(icons);
  showInfoToast(
    overlay,
    'Icons set on ${r.updated} categories'
    '${r.unchanged > 0 ? ', ${r.unchanged} already had them' : ''}'
    '${r.notFound.isNotEmpty ? ', ${r.notFound.length} names not found' : ''}',
  );
  if (r.notFound.isNotEmpty && context.mounted) {
    await showStackedDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Names without a category'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Text(
              [
                for (final n in r.notFound.take(40)) '• $n',
                if (r.notFound.length > 40)
                  '… and ${r.notFound.length - 40} more',
              ].join(String.fromCharCode(10)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

String _today() {
  final n = DateTime.now();
  String p(int v) => v.toString().padLeft(2, '0');
  return '${n.year}-${p(n.month)}-${p(n.day)}';
}

Future<void> exportBudgetJson(BuildContext context, WidgetRef ref) async {
  final overlay = rootOverlayOf(context);
  final json = await ref.read(budgetIoServiceProvider).exportJson();
  final path = await ref
      .read(budgetFilesProvider)
      .saveText('livenow-budget-${_today()}.json', json);
  if (path != null) showInfoToast(overlay, 'Backup saved: $path');
}

Future<void> exportBudgetCsv(BuildContext context, WidgetRef ref) async {
  final overlay = rootOverlayOf(context);
  final files = await ref.read(budgetIoServiceProvider).exportCsvs();
  final dir = await ref.read(budgetFilesProvider).saveFolder(files);
  if (dir != null) showInfoToast(overlay, '3 CSV files saved to $dir');
}
