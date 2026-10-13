import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data/backup/auto_backup.dart';
import '../data/backup/backup_import_service.dart';
import 'backup_files.dart';
import 'providers.dart';
import 'sync_providers.dart';

// Never touch the real app-data folder from `flutter test`.
final bool _underTest = Platform.environment.containsKey('FLUTTER_TEST');

/// The automatic backup runs where there is a stable folder to write to: the
/// desktop (the phone exports by hand through the share sheet).
bool get autoBackupSupported =>
    !_underTest && !Platform.isIOS && !Platform.isAndroid;

/// Settings shows the automatic-backup block on every desktop (also in tests).
bool get autoBackupVisible => !Platform.isIOS && !Platform.isAndroid;

final backupFilesProvider = Provider<BackupFiles>((ref) => const BackupFiles());

final backupImportServiceProvider = Provider<BackupImportService>((ref) {
  return BackupImportService(
    ref.watch(databaseProvider),
    ref.watch(syncStoreProvider),
    afterImport: () => ref.read(metricServiceProvider).recomputeWeights(),
  );
});

final autoBackupStoreProvider = Provider<AutoBackupStore>(
  (ref) => AutoBackupStore.lazy(() async {
    final override = Platform.environment['LIVENOW_DATA_DIR'];
    final dir = override != null && override.isNotEmpty
        ? Directory(override)
        : await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}auto_backup.json');
  }),
);

final autoBackupRunnerProvider = Provider<AutoBackupRunner>(
  (ref) => AutoBackupRunner(
    ref.watch(databaseProvider),
    ref.watch(autoBackupStoreProvider),
  ),
);

/// One timer for the next automatic backup (desktop). The shell arms it at
/// start and on resume; the settings re-arm it after a change.
final autoBackupSchedulerProvider = Provider<AutoBackupScheduler>((ref) {
  final scheduler = AutoBackupScheduler(
    ref.watch(autoBackupRunnerProvider),
    onResult: (_) => ref.read(autoBackupSettingsProvider.notifier).refresh(),
  );
  ref.onDispose(scheduler.dispose);
  return scheduler;
});

/// The saved automatic-backup settings (and its last result) for Settings.
class AutoBackupSettingsNotifier extends Notifier<AutoBackupSettings> {
  @override
  AutoBackupSettings build() {
    if (!_underTest) refresh();
    return const AutoBackupSettings();
  }

  AutoBackupStore get _store => ref.read(autoBackupStoreProvider);

  Future<void> refresh() async {
    final s = await _store.load();
    if (ref.mounted) state = s;
  }

  Future<void> _change(AutoBackupSettings s) async {
    state = s;
    await _store.save(s);
    if (autoBackupSupported) {
      await ref.read(autoBackupSchedulerProvider).reschedule();
    }
  }

  Future<void> setEnabled(bool on) => _change(state.copyWith(enabled: on));

  Future<void> setFolder(String folder) =>
      _change(state.copyWith(folder: folder, clearError: true));

  /// "Back up now" (ignores the schedule); the result shows in the status.
  Future<AutoBackupResult> backupNow() async {
    final r = await ref.read(autoBackupRunnerProvider).run(force: true);
    await refresh();
    return r;
  }
}

final autoBackupSettingsProvider =
    NotifierProvider<AutoBackupSettingsNotifier, AutoBackupSettings>(
      AutoBackupSettingsNotifier.new,
    );
