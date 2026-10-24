import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backup/backup_import_service.dart';
import '../data/backup/backup_sources.dart';
import '../data/backup/backup_writer.dart';
import '../data/sync/sync_backup.dart' show defaultBackupDirectory;
import '../core/text_rules.dart' show InvalidNameException;
import '../domain/budget_csv.dart';
import '../domain/full_backup.dart';
import '../domain/budget_icons.dart';
import '../domain/budget_io_service.dart';
import '../domain/notion_icons.dart';
import 'backup_files.dart' show PickedBackupFile;
import 'backup_providers.dart';
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
  try {
    final text = await ref.read(actionsCsvPickerProvider)();
    if (text == null || !context.mounted) return;
    final result = await service.importCsv(text);
    if (!context.mounted) return;
    await ActionImportSummaryDialog.show(context, result);
  } on FormatException catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Import failed: ${e.message}. Nothing was changed.')),
    );  } on InvalidNameException catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Import failed: ${e.message} Nothing was changed.')),
    );
  }
}

/// The same Notion export -> templates.
Future<void> importTemplatesCsv(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final service = ref.read(templateImportServiceProvider);
  try {
    final text = await ref.read(actionsCsvPickerProvider)();
    if (text == null || !context.mounted) return;
    final result = await service.importCsv(text);
    if (!context.mounted) return;
    await TemplateImportSummaryDialog.show(context, result);
  } on FormatException catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Import failed: ${e.message}. Nothing was changed.')),
    );  } on InvalidNameException catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Import failed: ${e.message} Nothing was changed.')),
    );
  }
}

/// Notion growth directions export (CSV): replaces every direction.
Future<void> importGrowthCsv(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final pick = ref.read(growthCsvPickerProvider);
  final service = ref.read(metricServiceProvider);

  try {
    final text = await pick();
    if (text == null) return;
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
      SnackBar(content: Text('Import failed: ${e.message}. Nothing was changed.')),
    );  } on InvalidNameException catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Import failed: ${e.message} Nothing was changed.')),
    );
  }
}

/// Sets direction icons from saved Notion pages / a name-emoji list.
Future<void> importGrowthIcons(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final service = ref.read(metricServiceProvider);
  try {
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
  } on FormatException catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Import failed: ${e.message}. Nothing was changed.')),
    );  } on InvalidNameException catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Import failed: ${e.message} Nothing was changed.')),
    );
  }
}

/// Budget: one JSON backup, or any of the three Notion CSVs (recognised by
/// their header). Replaces the budget data, after asking when there is some.
Future<void> importBudgetData(BuildContext context, WidgetRef ref) async {
  final overlay = rootOverlayOf(context);
  final io = ref.read(budgetIoServiceProvider);
  final List<PickedFile> files;
  try {
    files = await ref.read(budgetFilesProvider).pickImportFiles();
  } on FormatException catch (e) {
    showInfoToast(overlay, 'Import failed: ${e.message}. Nothing was changed.');
    return;
  }
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
    showInfoToast(overlay, 'Import failed: ${e.message}. Nothing was changed.');
  } on InvalidNameException catch (e) {
    showInfoToast(overlay, 'Import failed: ${e.message} Nothing was changed.');
  }
}

/// Budget category icons: a CSV with `name` and `icon` columns; each matching
/// category's name gets the emoji in front ("👟 Взуття").
Future<void> importBudgetIcons(BuildContext context, WidgetRef ref) async {
  final overlay = rootOverlayOf(context);
  final io = ref.read(budgetIoServiceProvider);
  final List<PickedFile> files;
  try {
    files = await ref.read(budgetFilesProvider).pickImportFiles();
  } on FormatException catch (e) {
    showInfoToast(overlay, 'Import failed: ${e.message}. Nothing was changed.');
    return;
  }
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

// ---- full backup (every table) ----------------------------------------------

Future<void> exportBackupCompact(BuildContext context, WidgetRef ref) async {
  final overlay = rootOverlayOf(context);
  final writer = BackupWriter(ref.read(databaseProvider));
  final path = await ref
      .read(backupFilesProvider)
      .exportFile('livenow-backup-${_today()}.$kBackupExtension', writer.writeCompact);
  if (path != null) showInfoToast(overlay, 'Backup saved: $path');
}

Future<void> exportBackupCsv(BuildContext context, WidgetRef ref) async {
  final overlay = rootOverlayOf(context);
  final writer = BackupWriter(ref.read(databaseProvider));
  final dir = await ref
      .read(backupFilesProvider)
      .exportFolder('livenow-csv-${_today()}', writer.writeCsvFolder);
  if (dir != null) showInfoToast(overlay, 'CSV files saved to $dir');
}

Future<void> exportBackupSqlite(BuildContext context, WidgetRef ref) async {
  final overlay = rootOverlayOf(context);
  final writer = BackupWriter(ref.read(databaseProvider));
  final path = await ref
      .read(backupFilesProvider)
      .exportFile('livenow-${_today()}.db', writer.writeSqliteCopy);
  if (path != null) showInfoToast(overlay, 'Database copy saved: $path');
}

/// The chosen import mode, or null when cancelled.
Future<BackupImportMode?> _askImportMode(BuildContext context) =>
    showStackedDialog<BackupImportMode>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import this backup?'),
        content: const Text(
          'Merge adds what is missing and updates rows that are newer in the '
          'file; nothing is deleted (rows you deleted since may come back).\n\n'
          'Replace everything makes the app match the file exactly. A copy of '
          'the current data is saved first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const ValueKey('backup-import-replace'),
            onPressed: () => Navigator.of(ctx).pop(BackupImportMode.replace),
            child: const Text('Replace everything'),
          ),
          FilledButton(
            key: const ValueKey('backup-import-merge'),
            onPressed: () => Navigator.of(ctx).pop(BackupImportMode.merge),
            child: const Text('Merge'),
          ),
        ],
      ),
    );

/// A .livenow file, a SQLite copy, or the CSV files of a backup (choose them
/// together); then Merge or Replace.
Future<void> importBackup(BuildContext context, WidgetRef ref) async {
  final overlay = rootOverlayOf(context);
  final service = ref.read(backupImportServiceProvider);
  final picked = await ref.read(backupFilesProvider).pickImportFiles();
  if (picked.isEmpty || !context.mounted) return;

  String ext(PickedBackupFile f) => f.name.toLowerCase().split('.').last;
  final compact = [for (final f in picked) if (ext(f) == kBackupExtension) f];
  final dbs = [
    for (final f in picked)
      if (ext(f) == 'db' || ext(f) == 'sqlite') f,
  ];
  final csvs = [for (final f in picked) if (ext(f) == 'csv') f];

  BackupSource? source;
  if (compact.length == 1 && picked.length == 1) {
    source = CompactBackupSource(compact.single.file);
  } else if (dbs.length == 1 && picked.length == 1) {
    source = SqliteBackupSource(dbs.single.file);
  } else if (csvs.isNotEmpty && csvs.length == picked.length) {
    final csv = CsvFolderBackupSource({for (final f in csvs) f.name: f.file});
    if (csv.hasTables) source = csv;
  }
  if (source == null) {
    showInfoToast(
      overlay,
      'Choose one .livenow file, one database copy, or the CSV files of a backup',
    );
    return;
  }

  final mode = await _askImportMode(context);
  if (mode == null || !context.mounted) return;

  showInfoToast(overlay, 'Importing...');
  try {
    final summary = await service.import(
      source,
      mode: mode,
      safetyBackupDir: mode == BackupImportMode.replace
          ? await defaultBackupDirectory()
          : null,
    );
    if (!context.mounted) return;
    await showStackedDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Backup imported'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Text(backupSummaryText(summary)),
          ),
        ),
        actions: [
          FilledButton(
            key: const ValueKey('backup-import-done'),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  } on BackupFormatException catch (e) {
    showInfoToast(overlay, 'Import failed: ${e.message}. Nothing was changed.');
  } catch (e) {
    showInfoToast(overlay, 'Import failed: $e. Nothing was changed.');
  }
}

/// The import result dialog's text.
@visibleForTesting
String backupSummaryText(BackupImportSummary summary) {
  final b = StringBuffer(
    '${summary.written} rows added or updated, '
    '${summary.kept} already up to date.',
  );
  if (summary.repairs > 0) {
    b.write('\n${summary.repairs} broken references were fixed.');
  }
  if (summary.safetyCopy != null) {
    b.write('\nPrevious data saved as ${summary.safetyCopy}');
  }
  b.write('\n');
  for (final e in summary.tables.entries) {
    if (e.value.written + e.value.kept > 0) {
      b.write(
        '\n${e.key}: ${e.value.written} new/updated, '
        '${e.value.kept} unchanged',
      );
    }
  }
  return b.toString();
}
