import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/work_hours.dart';

const _fileName = 'work_hours.json';

// Never touch the real app-data folder from `flutter test`.
final bool _underTest = Platform.environment.containsKey('FLUTTER_TEST');

Future<File> _file() async =>
    File('${(await getApplicationSupportDirectory()).path}/$_fileName');

/// The working hours (Settings): work start/end and the morning postpone time.
/// Saved next to `theme_mode.txt` on THIS device (best-effort, skipped in
/// tests); a missing or damaged file means the defaults.
class WorkHoursNotifier extends Notifier<WorkHours> {
  @override
  WorkHours build() {
    if (!_underTest) _load();
    return WorkHours.defaults;
  }

  Future<void> _load() async {
    try {
      final text = await (await _file()).readAsString();
      final loaded = WorkHours.fromJson(jsonDecode(text));
      if (loaded != state) state = loaded;
    } catch (_) {
      // No file yet: keep the defaults.
    }
  }

  /// Applies [hours] when valid; returns the problem otherwise (state kept).
  String? set(WorkHours hours) {
    final problem = hours.problem;
    if (problem != null) return problem;
    state = hours;
    _save(hours);
    return null;
  }

  Future<void> _save(WorkHours hours) async {
    if (_underTest) return;
    try {
      await (await _file()).writeAsString(jsonEncode(hours.toJson()));
    } catch (_) {
      // Best-effort; the in-memory choice still applies.
    }
  }
}

final workHoursProvider = NotifierProvider<WorkHoursNotifier, WorkHours>(
  WorkHoursNotifier.new,
);
