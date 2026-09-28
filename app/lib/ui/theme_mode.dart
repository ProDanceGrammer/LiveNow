import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

const _fileName = 'theme_mode.txt';

Future<File> _file() async =>
    File('${(await getApplicationSupportDirectory()).path}/$_fileName');

/// Reads the persisted theme choice; any failure (missing file, no plugin
/// in tests, bad contents) falls back to light.
Future<ThemeMode> loadThemeMode() async {
  try {
    final text = (await (await _file()).readAsString()).trim();
    return text == 'dark' ? ThemeMode.dark : ThemeMode.light;
  } catch (_) {
    return ThemeMode.light;
  }
}

Future<void> _saveThemeMode(ThemeMode mode) async {
  try {
    await (await _file()).writeAsString(mode == ThemeMode.dark ? 'dark' : 'light');
  } catch (_) {
    // Persistence is best-effort; the in-memory choice still applies.
  }
}

class ThemeModeNotifier extends Notifier<ThemeMode> {
  ThemeModeNotifier([this._initial = ThemeMode.light]);
  final ThemeMode _initial;

  @override
  ThemeMode build() => _initial;

  void setMode(ThemeMode mode) {
    state = mode;
    _saveThemeMode(mode);
  }

  void toggle() =>
      setMode(state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);
