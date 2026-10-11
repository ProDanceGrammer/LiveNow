import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data/reminders/local_notifications_sink.dart';
import '../data/reminders/reminder_scheduler.dart';
import 'providers.dart';

const _fileName = 'reminders.txt';

// Never touch the real app-data folder from `flutter test`.
final bool _underTest = Platform.environment.containsKey('FLUTTER_TEST');

Future<File> _file() async =>
    File('${(await getApplicationSupportDirectory()).path}/$_fileName');

/// The Settings switch "Notify me when an action starts or ends". On by
/// default; saved next to `theme_mode.txt`, best-effort, skipped in tests.
class RemindersEnabledNotifier extends Notifier<bool> {
  @override
  bool build() {
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

  Future<void> _save(bool value) async {
    if (_underTest) return;
    try {
      await (await _file()).writeAsString(value ? 'true' : 'false');
    } catch (_) {
      // Best-effort; the in-memory choice still applies.
    }
  }
}

final remindersEnabledProvider =
    NotifierProvider<RemindersEnabledNotifier, bool>(
      RemindersEnabledNotifier.new,
    );

/// Starts the reminders for this session (iOS and Windows only; the shell
/// calls it once, never under `flutter test`). Returns null where there is
/// nothing to do. The caller keeps the scheduler to call `resume()` when the
/// app returns to the foreground and `dispose()` at the end.
ReminderScheduler? startReminders(WidgetRef ref) {
  if (!LocalNotificationsSink.supported) return null;
  final scheduler = ReminderScheduler(
    source: ref.read(viewQueriesProvider).watchUpcoming(),
    sink: LocalNotificationsSink(),
    enabled: ref.read(remindersEnabledProvider),
  )..start();
  ref.listenManual<bool>(
    remindersEnabledProvider,
    (_, on) => scheduler.setEnabled(on),
  );
  return scheduler;
}
