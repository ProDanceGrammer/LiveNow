import 'dart:io';

import 'package:flutter/widgets.dart' show OverlayState;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data/database.dart';
import '../data/reminders/local_notifications_sink.dart';
import '../data/reminders/reminder_scheduler.dart';
import 'providers.dart';
import 'root_navigator.dart';
import 'widgets/action_editor.dart';
import 'widgets/app_toast.dart';

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
  final db = ref.read(databaseProvider);
  final sink = LocalNotificationsSink(
    onOpenAction: (id) => openActionFromNotification(db, id),
  );
  // The notification that started the app (tapped while it was closed).
  sink.launchActionId().then((id) {
    if (id != null) openActionFromNotification(db, id);
  });
  final scheduler = ReminderScheduler(
    source: ref.read(viewQueriesProvider).watchUpcoming(),
    sink: sink,
    enabled: ref.read(remindersEnabledProvider),
  )..start();
  ref.listenManual<bool>(
    remindersEnabledProvider,
    (_, on) => scheduler.setEnabled(on),
  );
  return scheduler;
}

/// Opens the editor of action [id] over whatever is on screen (a dialog that
/// is already open stays underneath). At a cold start the navigator may not
/// exist yet, so this waits a little for it. An action deleted since the
/// notification was scheduled gets a short message instead.
Future<void> openActionFromNotification(
  AppDatabase db,
  String id, {
  int tries = 20,
}) async {
  OverlayState? overlay;
  for (var i = 0; i < tries; i++) {
    overlay = rootNavigatorKey.currentState?.overlay;
    if (overlay != null && overlay.mounted) break;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  if (overlay == null || !overlay.mounted) return;
  // A context inside the navigator (its overlay's own), for showing dialogs.
  final context = overlay.context;
  final row = await (db.select(
    db.actionsTable,
  )..where((t) => t.id.equals(id))).getSingleOrNull();
  if (!context.mounted) return;
  if (row == null) {
    showInfoToast(overlay, 'That action no longer exists.');
    return;
  }
  await ActionEditorDialog.show(context, existing: row);
}
