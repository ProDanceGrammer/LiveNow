import 'dart:io';

import 'package:flutter/widgets.dart';

import 'widgets/app_toast.dart';

/// True where a saved file's folder can be opened (desktop file managers).
bool get canOpenSavedLocation =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

/// Opens the folder of a saved export: a FILE is shown selected in its folder
/// (Explorer / Finder), a FOLDER is opened. Errors are ignored (Explorer
/// always exits with 1).
Future<void> openSavedLocation(String path) async {
  final isDir = FileSystemEntity.isDirectorySync(path);
  try {
    if (Platform.isWindows) {
      await Process.start(
        'explorer.exe',
        isDir ? [path] : ['/select,', path],
      );
    } else if (Platform.isMacOS) {
      await Process.start('open', isDir ? [path] : ['-R', path]);
    } else if (Platform.isLinux) {
      await Process.start('xdg-open', [isDir ? path : File(path).parent.path]);
    }
  } catch (_) {
    // No file manager: nothing to open.
  }
}

/// "`leading` + path" where the path is a link that opens its folder (desktop;
/// plain text on a phone). Stays up longer than a plain toast so the link can
/// be reached. [open] is replaceable for tests.
void showSavedToast(
  OverlayState overlay,
  String leading,
  String path, {
  Future<void> Function(String path) open = openSavedLocation,
  @visibleForTesting bool? linkable,
}) {
  final link = linkable ?? canOpenSavedLocation;
  showAppToast(
    overlay,
    leading: leading,
    name: path,
    onNameTap: link ? () => open(path) : null,
    duration: const Duration(seconds: 10),
  );
}
