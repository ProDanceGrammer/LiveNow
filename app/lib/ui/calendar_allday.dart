import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/accounts/profile_paths.dart';

const _fileName = 'calendar_allday.txt';

// Never touch the real app-data folder from `flutter test`.
final bool _underTest = Platform.environment.containsKey('FLUTTER_TEST');

Future<File> _file() async =>
    File('${(await profileDirectory()).path}/$_fileName');

/// Whether the Calendar shows its all-day strip. On by default; the header
/// button (Windows) and the phone's menu switch it. Saved next to
/// `theme_mode.txt`, best-effort, skipped in tests.
class CalendarAllDayNotifier extends Notifier<bool> {
  CalendarAllDayNotifier([this._initial = true]);
  final bool _initial;

  @override
  bool build() {
    if (_initial && !_underTest) _load();
    return _initial;
  }

  Future<void> _load() async {
    try {
      final text = (await (await _file()).readAsString()).trim();
      if (text == 'false' && state) state = false;
    } catch (_) {
      // Missing file or no plugin: keep the default (shown).
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

final calendarAllDayProvider = NotifierProvider<CalendarAllDayNotifier, bool>(
  CalendarAllDayNotifier.new,
);
