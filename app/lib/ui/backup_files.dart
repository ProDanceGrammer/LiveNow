import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// A file the user chose to import.
class PickedBackupFile {
  const PickedBackupFile(this.name, this.file);

  final String name;
  final File file;
}

/// The native file dialogs of the full backup. A class behind a provider so
/// tests can replace the dialogs (see `backupFilesProvider`).
class BackupFiles {
  const BackupFiles();

  static const _types = [
    XTypeGroup(
      label: 'LiveNow backup (.livenow, .db, CSV)',
      extensions: ['livenow', 'db', 'sqlite', 'csv'],
      // iOS needs type identifiers (it ignores extensions); the custom
      // extensions have no registered type, so any data file is allowed.
      uniformTypeIdentifiers: [
        'public.data',
        'public.comma-separated-values-text',
      ],
    ),
  ];

  /// Any number of backup files (several CSV files can be chosen together);
  /// empty when cancelled.
  Future<List<PickedBackupFile>> pickImportFiles() async {
    final files = await openFiles(acceptedTypeGroups: _types);
    return [for (final f in files) PickedBackupFile(f.name, File(f.path))];
  }

  /// A phone has no "save as" dialog: files go to a temp folder and the system
  /// share sheet (Save to Files, AirDrop...) takes it from there.
  static bool get _usesShareSheet => Platform.isIOS || Platform.isAndroid;

  static Future<Directory> _tempDir(String name) async {
    final dir = Directory(
      '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}'
      'livenow_export${Platform.pathSeparator}$name',
    );
    if (await dir.exists()) await dir.delete(recursive: true);
    return dir.create(recursive: true);
  }

  /// On iOS share() returns once the share sheet is done, so the full backup in
  /// the temp folder is deleted at once (elsewhere the next export clears it).
  static Future<void> _removeAfterShare(Directory dir) async {
    if (!Platform.isIOS) return;
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  /// Asks where to save one file, lets [write] fill it, returns its path
  /// (null when cancelled).
  Future<String?> exportFile(
    String suggestedName,
    Future<void> Function(File out) write,
  ) async {
    if (_usesShareSheet) {
      final dir = await _tempDir('file');
      final f = File('${dir.path}${Platform.pathSeparator}$suggestedName');
      try {
        await write(f);
        await SharePlus.instance.share(ShareParams(files: [XFile(f.path)]));
      } finally {
        await _removeAfterShare(dir);
      }
      return f.path;
    }
    final ext = suggestedName.split('.').last;
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: [XTypeGroup(label: ext, extensions: [ext])],
    );
    if (location == null) return null;
    await write(File(location.path));
    return location.path;
  }

  /// Asks for a folder, lets [write] fill a new sub-folder [name] of it,
  /// returns that sub-folder (null when cancelled).
  Future<String?> exportFolder(
    String name,
    Future<List<File>> Function(Directory dir) write,
  ) async {
    if (_usesShareSheet) {
      final dir = await _tempDir(name);
      try {
        final files = await write(dir);
        await SharePlus.instance.share(
          ShareParams(files: [for (final f in files) XFile(f.path)]),
        );
      } finally {
        await _removeAfterShare(dir);
      }
      return dir.path;
    }
    final base = await getDirectoryPath();
    if (base == null) return null;
    final dir = Directory('$base${Platform.pathSeparator}$name');
    await write(dir);
    return dir.path;
  }

  /// A folder for the automatic backups (desktop); null when cancelled.
  Future<String?> pickFolder() => getDirectoryPath();
}
