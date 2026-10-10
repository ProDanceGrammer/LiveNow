import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/budget_io_service.dart';
import 'providers.dart';

/// A file the user chose to import.
class PickedFile {
  const PickedFile(this.name, this.text);

  final String name;
  final String text;
}

/// The native file dialogs of the budget import/export. A class behind a
/// provider so tests can replace the dialogs.
class BudgetFiles {
  const BudgetFiles();

  static const _types = [
    XTypeGroup(label: 'Budget data (CSV, JSON)', extensions: ['csv', 'json']),
  ];

  /// Any number of CSV/JSON files; empty when cancelled.
  Future<List<PickedFile>> pickImportFiles() async {
    final files = await openFiles(acceptedTypeGroups: _types);
    return [for (final f in files) PickedFile(f.name, await f.readAsString())];
  }

  /// Asks where to save one text file; returns the path, null when cancelled.
  Future<String?> saveText(String suggestedName, String text) async {
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: [
        XTypeGroup(
          label: suggestedName.endsWith('.json') ? 'JSON' : 'CSV',
          extensions: [suggestedName.split('.').last],
        ),
      ],
    );
    if (location == null) return null;
    await File(location.path).writeAsString(text);
    return location.path;
  }

  /// Asks for a folder and writes every file into it; returns the folder.
  Future<String?> saveFolder(Map<String, String> files) async {
    final dir = await getDirectoryPath();
    if (dir == null) return null;
    for (final e in files.entries) {
      await File('$dir${Platform.pathSeparator}${e.key}')
          .writeAsString(e.value);
    }
    return dir;
  }
}

final budgetFilesProvider = Provider<BudgetFiles>((ref) => const BudgetFiles());

final budgetIoServiceProvider = Provider<BudgetIoService>(
  (ref) => BudgetIoService(ref.watch(databaseProvider)),
);
