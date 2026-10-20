import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/accounts/profile_paths.dart';

const _fileName = 'notch_side.txt';

// Never touch the real app-data folder from `flutter test`.
final bool _underTest = Platform.environment.containsKey('FLUTTER_TEST');

Future<File> _file() async =>
    File('${(await appSupportRoot()).path}/$_fileName');

/// Which side of a phone held SIDEWAYS has the camera notch (true = left).
/// iOS reports the same safe-area inset on both sides, so the app cannot tell:
/// full-screen views keep the inset on this side only and use the other side's
/// band. Persisted next to `rail_collapsed.txt`; best-effort like it.
class NotchSideNotifier extends Notifier<bool> {
  NotchSideNotifier([this._initial = true]);
  final bool _initial;

  @override
  bool build() {
    if (!_underTest) _load();
    return _initial;
  }

  Future<void> _load() async {
    try {
      final text = (await (await _file()).readAsString()).trim();
      if (text == 'right' && state) state = false;
    } catch (_) {
      // Missing file or no plugin: keep the default (left).
    }
  }

  void set(bool left) {
    state = left;
    _save(left);
  }

  Future<void> _save(bool left) async {
    if (_underTest) return;
    try {
      await (await _file()).writeAsString(left ? 'left' : 'right');
    } catch (_) {
      // Best-effort; the in-memory choice still applies.
    }
  }
}

/// True = the notch is on the left when the phone is held sideways.
final notchOnLeftProvider = NotifierProvider<NotchSideNotifier, bool>(
  NotchSideNotifier.new,
);
