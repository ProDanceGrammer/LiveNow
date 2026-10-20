import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// The folder of the account that is signed in: its database and its own
/// preference files live there. Null until the account gate sets it (and in
/// tests and the sync hub), which means "the app-support root", exactly where
/// everything lived before accounts existed.
Directory? activeProfileDirectory;

/// The app-support root: `LIVENOW_DATA_DIR` (isolated test runs, so they never
/// touch the real data), else the platform's app-support folder. The registry
/// (`accounts.json`), the per-device files and the `profiles/` folders live here.
Future<Directory> appSupportRoot() async {
  final env = Platform.environment['LIVENOW_DATA_DIR'];
  if (env != null && env.isNotEmpty) return Directory(env);
  return getApplicationSupportDirectory();
}

/// Where the signed-in account keeps its files (preferences, backups, the
/// database): its profile folder, or the root while no account is active.
/// Per-DEVICE files (theme, notch side) use [appSupportRoot] instead.
Future<Directory> profileDirectory() async =>
    activeProfileDirectory ?? await appSupportRoot();
