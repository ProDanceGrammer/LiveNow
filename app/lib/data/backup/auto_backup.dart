import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../database.dart';
import 'backup_writer.dart';

/// Every this often the automatic backup writes a new file.
const Duration kAutoBackupInterval = Duration(hours: 5);

/// A failed run is tried again after this.
const Duration kAutoBackupRetry = Duration(minutes: 30);

/// How many backup files stay in the folder (the newest ones).
const int kAutoBackupKeep = 5;

const String _prefix = 'livenow-backup-';
const String _suffix = '.livenow';

/// The automatic backup's choices and bookkeeping, kept on THIS device.
class AutoBackupSettings {
  const AutoBackupSettings({
    this.enabled = false,
    this.folder,
    this.lastRunAt,
    this.lastSeq = 0,
    this.lastFile,
    this.lastError,
  });

  final bool enabled;
  final String? folder;

  /// When the last run finished (a skipped "nothing changed" run counts).
  final DateTime? lastRunAt;

  /// The change-log position the last written file contained.
  final int lastSeq;
  final String? lastFile;
  final String? lastError;

  bool get ready => enabled && folder != null && folder!.isNotEmpty;

  AutoBackupSettings copyWith({
    bool? enabled,
    String? folder,
    DateTime? lastRunAt,
    int? lastSeq,
    String? lastFile,
    String? lastError,
    bool clearError = false,
  }) => AutoBackupSettings(
    enabled: enabled ?? this.enabled,
    folder: folder ?? this.folder,
    lastRunAt: lastRunAt ?? this.lastRunAt,
    lastSeq: lastSeq ?? this.lastSeq,
    lastFile: lastFile ?? this.lastFile,
    lastError: clearError ? null : (lastError ?? this.lastError),
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'folder': folder,
    'lastRunAt': lastRunAt?.toUtc().toIso8601String(),
    'lastSeq': lastSeq,
    'lastFile': lastFile,
    'lastError': lastError,
  };

  factory AutoBackupSettings.fromJson(Object? j) {
    if (j is! Map) return const AutoBackupSettings();
    return AutoBackupSettings(
      enabled: j['enabled'] == true,
      folder: j['folder'] as String?,
      lastRunAt: DateTime.tryParse('${j['lastRunAt']}'),
      lastSeq: (j['lastSeq'] as num?)?.toInt() ?? 0,
      lastFile: j['lastFile'] as String?,
      lastError: j['lastError'] as String?,
    );
  }
}

/// Reads/writes the settings file (`auto_backup.json`, device-local).
class AutoBackupStore {
  AutoBackupStore(File file) : _file = (() async => file);

  /// For the app: the folder is only known asynchronously.
  AutoBackupStore.lazy(this._file);

  final Future<File> Function() _file;

  Future<AutoBackupSettings> load() async {
    try {
      return AutoBackupSettings.fromJson(
        jsonDecode(await (await _file()).readAsString()),
      );
    } catch (_) {
      return const AutoBackupSettings(); // no file yet, or a damaged one
    }
  }

  Future<void> save(AutoBackupSettings s) async {
    try {
      await (await _file()).writeAsString(jsonEncode(s.toJson()));
    } catch (_) {
      // Best-effort; the next run writes it again.
    }
  }
}

enum AutoBackupOutcome { disabled, notDue, unchanged, written, failed }

class AutoBackupResult {
  const AutoBackupResult(this.outcome, {this.path, this.error});

  final AutoBackupOutcome outcome;
  final String? path;
  final String? error;
}

/// Writes the compact backup into the chosen folder when it is due (every
/// [kAutoBackupInterval]), skips the run when nothing changed since the last
/// file, keeps the newest [kAutoBackupKeep] files, and never throws: a problem
/// (folder gone, disk full) is recorded in the settings and shown in Settings.
class AutoBackupRunner {
  AutoBackupRunner(
    this.db,
    this.store, {
    DateTime Function()? now,
    this.interval = kAutoBackupInterval,
    this.keep = kAutoBackupKeep,
  }) : _now = now ?? DateTime.now;

  final AppDatabase db;
  final AutoBackupStore store;
  final DateTime Function() _now;
  final Duration interval;
  final int keep;

  bool _running = false;

  /// How long until the next run is due (zero when overdue, null when off).
  Duration? timeUntilDue(AutoBackupSettings s) {
    if (!s.ready) return null;
    final last = s.lastRunAt;
    if (last == null) return Duration.zero;
    final left = last.add(interval).difference(_now());
    return left.isNegative ? Duration.zero : left;
  }

  Future<int> _currentSeq() async {
    final r = await db
        .customSelect('SELECT COALESCE(MAX(seq), 0) AS s FROM sync_versions')
        .getSingle();
    return r.read<int>('s');
  }

  /// [force] = "Back up now": ignores the schedule and the unchanged check.
  Future<AutoBackupResult> run({bool force = false}) async {
    if (_running) return const AutoBackupResult(AutoBackupOutcome.notDue);
    _running = true;
    try {
      final s = await store.load();
      if (!s.ready) return const AutoBackupResult(AutoBackupOutcome.disabled);
      if (!force && timeUntilDue(s) != Duration.zero) {
        return const AutoBackupResult(AutoBackupOutcome.notDue);
      }
      final seq = await _currentSeq();
      if (!force && s.lastRunAt != null && seq == s.lastSeq) {
        await store.save(s.copyWith(lastRunAt: _now(), clearError: true));
        return const AutoBackupResult(AutoBackupOutcome.unchanged);
      }
      try {
        final dir = await Directory(s.folder!).create(recursive: true);
        final path = '${dir.path}${Platform.pathSeparator}${_fileName(_now())}';
        await BackupWriter(db).writeCompact(File(path));
        await _prune(dir);
        await store.save(
          s.copyWith(
            lastRunAt: _now(),
            lastSeq: seq,
            lastFile: path,
            clearError: true,
          ),
        );
        return AutoBackupResult(AutoBackupOutcome.written, path: path);
      } catch (e) {
        await store.save(s.copyWith(lastError: '$e'));
        return AutoBackupResult(AutoBackupOutcome.failed, error: '$e');
      }
    } finally {
      _running = false;
    }
  }

  static String _fileName(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    final l = t.toLocal();
    return '$_prefix${l.year}${two(l.month)}${two(l.day)}-'
        '${two(l.hour)}${two(l.minute)}${two(l.second)}$_suffix';
  }

  /// Deletes all but the newest [keep] backup files (by name = by time).
  Future<void> _prune(Directory dir) async {
    final files = <File>[
      await for (final f in dir.list())
        if (f is File &&
            f.uri.pathSegments.last.startsWith(_prefix) &&
            f.path.endsWith(_suffix))
          f,
    ]..sort((a, b) => b.path.compareTo(a.path));
    for (final f in files.skip(keep)) {
      try {
        await f.delete();
      } catch (_) {}
    }
  }
}

/// One timer for the next run: armed from the settings, re-armed after every
/// run (a failed one retries after [kAutoBackupRetry]). Desktop only; the
/// caller starts it once and calls [dispose].
class AutoBackupScheduler {
  AutoBackupScheduler(this.runner, {this.onResult});

  final AutoBackupRunner runner;

  /// Told after every run (the Settings status refreshes from it).
  final void Function(AutoBackupResult result)? onResult;

  Timer? _timer;
  bool _disposed = false;

  /// (Re)arms the timer from the saved settings; call after they change, at
  /// start, and when the app returns to the foreground.
  Future<void> reschedule() async {
    _timer?.cancel();
    _timer = null;
    if (_disposed) return;
    final s = await runner.store.load();
    final wait = runner.timeUntilDue(s);
    if (wait == null) return;
    // Never a hot loop: at least a few seconds after start/changes.
    final delay = wait < const Duration(seconds: 5)
        ? const Duration(seconds: 5)
        : wait;
    _timer = Timer(delay, () async {
      final r = await runner.run();
      onResult?.call(r);
      if (_disposed) return;
      if (r.outcome == AutoBackupOutcome.failed) {
        _timer = Timer(kAutoBackupRetry, reschedule);
      } else {
        await reschedule();
      }
    });
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
