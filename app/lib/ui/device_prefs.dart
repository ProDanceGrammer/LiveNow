import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/accounts/profile_paths.dart';

const _fileName = 'ui_prefs.json';

// Never touch the real app-data folder from `flutter test`.
final bool _underTest = Platform.environment.containsKey('FLUTTER_TEST');

Future<File> _file() async {
  final dir = await (await profileDirectory()).create(recursive: true);
  return File('${dir.path}/$_fileName');
}

/// Small per-device UI choices (which totals to show, whether the Categories
/// toolbar is hidden, ...) in ONE JSON file next to the other device-local
/// settings. A phone and a PC can differ, so these are deliberately NOT synced.
/// Best-effort: skipped under `flutter test`; a missing or damaged file means
/// the defaults.
class DevicePrefsNotifier extends Notifier<Map<String, Object?>> {
  @override
  Map<String, Object?> build() {
    if (!_underTest) _load();
    return const {};
  }

  Future<void> _load() async {
    try {
      final decoded = jsonDecode(await (await _file()).readAsString());
      if (decoded is Map<String, dynamic>) {
        // A write made while the file was loading wins.
        state = {...decoded, ...state};
      }
    } catch (_) {
      // No file yet: keep the defaults.
    }
  }

  void set(String key, Object? value) {
    state = {...state, key: value};
    _save();
  }

  Future<void> _save() async {
    if (_underTest) return;
    try {
      await (await _file()).writeAsString(jsonEncode(state));
    } catch (_) {
      // Best-effort; the in-memory choice still applies.
    }
  }
}

final devicePrefsProvider =
    NotifierProvider<DevicePrefsNotifier, Map<String, Object?>>(
      DevicePrefsNotifier.new,
    );

/// A boolean device preference: `(key, default)`.
final devicePrefBoolProvider = Provider.family<bool, (String, bool)>((
  ref,
  args,
) {
  final v = ref.watch(devicePrefsProvider.select((m) => m[args.$1]));
  return v is bool ? v : args.$2;
});

/// Writes a boolean device preference.
void setDevicePrefBool(WidgetRef ref, String key, bool value) =>
    ref.read(devicePrefsProvider.notifier).set(key, value);
