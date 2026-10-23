import 'dart:io';

import '../data/accounts/profile_paths.dart';

/// A tiny error log: `error.log` in the signed-in account's folder (the same
/// place as its other files; `LIVENOW_DATA_DIR` is honoured). It exists because a
/// failing quick button used to throw an unhandled async error that nobody saw:
/// the button just "did nothing". Capped at ~200 KB with one `.old` copy. Never
/// throws, and stays silent under `flutter test` unless a test points
/// [errorLogDirectoryOverride] at a temp folder.
class ErrorLog {
  ErrorLog._();

  static const _maxBytes = 200 * 1024;

  /// Tests set this to a temp folder to see what would be written.
  static Directory? errorLogDirectoryOverride;

  static Future<File?> file() async {
    try {
      final dir =
          errorLogDirectoryOverride ??
          (Platform.environment.containsKey('FLUTTER_TEST')
              ? null
              : await profileDirectory());
      if (dir == null) return null;
      return File('${dir.path}${Platform.pathSeparator}error.log');
    } on Object {
      return null;
    }
  }

  /// The log's path for Settings ("where do I find it"), or null.
  static Future<String?> path() async => (await file())?.path;

  /// Appends one entry: when, what was being done ([context]), the error and the
  /// stack trace.
  static Future<void> write(
    Object error,
    StackTrace? stack, {
    String? context,
  }) async {
    try {
      final f = await file();
      if (f == null) return;
      await f.parent.create(recursive: true);
      if (await f.exists() && await f.length() > _maxBytes) {
        final old = File('${f.path}.old');
        if (await old.exists()) await old.delete();
        await f.rename(old.path);
      }
      final lines = StringBuffer()
        ..writeln('--- ${DateTime.now().toIso8601String()}'
            '${context == null ? '' : '  [$context]'}')
        ..writeln(error)
        ..writeln(stack ?? StackTrace.empty);
      await f.writeAsString(lines.toString(), mode: FileMode.append, flush: true);
    } on Object {
      // A log must never be the thing that fails.
    }
  }
}
