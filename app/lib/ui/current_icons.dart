import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

const _fileName = 'current_icons.txt';

// Never touch the real app-data folder from `flutter test`.
final bool _underTest = Platform.environment.containsKey('FLUTTER_TEST');

Future<File> _file() async =>
    File('${(await getApplicationSupportDirectory()).path}/$_fileName');

/// Whether the Current Actions cards show their growth-direction emoji badges.
/// On by default; persisted next to `theme_mode.txt`. Loading and saving are
/// best-effort and skipped in tests, which pass [initial] explicitly.
class CurrentIconsNotifier extends Notifier<bool> {
  CurrentIconsNotifier([this.initial]);

  /// Fixed starting value (tests); null = on, then the saved choice.
  final bool? initial;

  @override
  bool build() {
    final fixed = initial;
    if (fixed != null) return fixed;
    if (!_underTest) _load();
    return true;
  }

  Future<void> _load() async {
    try {
      final text = (await (await _file()).readAsString()).trim();
      if (text == 'false' && state) state = false;
    } catch (_) {
      // Missing file or no plugin: keep the default (on).
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

final currentIconsProvider = NotifierProvider<CurrentIconsNotifier, bool>(
  CurrentIconsNotifier.new,
);
