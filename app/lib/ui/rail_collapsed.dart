import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

const _fileName = 'rail_collapsed.txt';

// Never touch the real app-data folder from `flutter test`.
final bool _underTest = Platform.environment.containsKey('FLUTTER_TEST');

Future<File> _file() async =>
    File('${(await getApplicationSupportDirectory()).path}/$_fileName');

/// Whether the navigation rail is collapsed to its icon-only strip, persisted
/// next to `theme_mode.txt`. Loading and saving are best-effort: in tests the
/// path_provider plugin is missing, so nothing is read or written.
class RailCollapsedNotifier extends Notifier<bool> {
  RailCollapsedNotifier([this._initial = false]);
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
      // Missing file or no plugin: keep the default (expanded).
    }
  }

  void set(bool collapsed) {
    state = collapsed;
    _save(collapsed);
  }

  void toggle() => set(!state);

  Future<void> _save(bool collapsed) async {
    if (_underTest) return;
    try {
      await (await _file()).writeAsString(collapsed ? 'true' : 'false');
    } catch (_) {
      // Best-effort; the in-memory choice still applies.
    }
  }
}

final railCollapsedProvider = NotifierProvider<RailCollapsedNotifier, bool>(
  RailCollapsedNotifier.new,
);
