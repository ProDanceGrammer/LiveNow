import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/accounts/profile_paths.dart';

const _fileName = 'calendar_icons.txt';

// Never touch the real app-data folder from `flutter test`.
final bool _underTest = Platform.environment.containsKey('FLUTTER_TEST');

Future<File> _file() async =>
    File('${(await profileDirectory()).path}/$_fileName');

/// Whether the Calendar shows the growth-direction emoji badges on its events.
/// Off by default (badges cost raster time on a busy week); persisted next to
/// `theme_mode.txt`. Loading and saving are best-effort and skipped in tests.
class CalendarIconsNotifier extends Notifier<bool> {
  CalendarIconsNotifier([this._initial = false]);
  final bool _initial;

  @override
  bool build() {
    if (!_initial && !_underTest) _load();
    return _initial;
  }

  Future<void> _load() async {
    try {
      final text = (await (await _file()).readAsString()).trim();
      if (text == 'true' && !state) state = true;
    } catch (_) {
      // Missing file or no plugin: keep the default (off).
    }
  }

  void set(bool value) {
    state = value;
    _save(value);
  }

  void toggle() => set(!state);

  Future<void> _save(bool value) async {
    if (_underTest) return;
    try {
      await (await _file()).writeAsString(value ? 'true' : 'false');
    } catch (_) {
      // Best-effort; the in-memory choice still applies.
    }
  }
}

final calendarIconsProvider = NotifierProvider<CalendarIconsNotifier, bool>(
  CalendarIconsNotifier.new,
);
