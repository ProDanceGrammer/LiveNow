import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/backup/auto_backup.dart';
import 'package:livenow/data/backup/backup_sources.dart';
import 'package:livenow/data/backup/backup_writer.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/backup_files.dart';
import 'package:livenow/ui/backup_providers.dart';
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/screens/settings_screen.dart';
import 'package:livenow/ui/sync_providers.dart';

/// Replaces the native file dialogs: saves into [dir], "picks" [picked].
class _FakeFiles extends BackupFiles {
  _FakeFiles(this.dir, {this.picked = const [], this.folder});

  final Directory dir;
  final List<PickedBackupFile> picked;
  final String? folder;
  final saved = <String>[];

  @override
  Future<List<PickedBackupFile>> pickImportFiles() async => picked;

  @override
  Future<String?> exportFile(
    String suggestedName,
    Future<void> Function(File out) write,
  ) async {
    final f = File('${dir.path}/$suggestedName');
    await write(f);
    saved.add(f.path);
    return f.path;
  }

  @override
  Future<String?> pickFolder() async => folder;
}

void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('livenow-backup-ui'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> settle(WidgetTester tester, [int ms = 400]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Work started from a button runs in the widget's FAKE zone: it only
  /// advances while pumped, and its file I/O needs real time in between.
  Future<void> until(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 150 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pump(
    WidgetTester tester,
    _FakeFiles files, {
    Future<void> Function(AppDatabase db)? seed,
  }) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    if (seed != null) await tester.runAsync(() => seed(db));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          syncRoleProvider.overrideWithValue(SyncRole.client),
          backupFilesProvider.overrideWithValue(files),
          autoBackupStoreProvider.overrideWithValue(
            AutoBackupStore(File('${dir.path}/auto_backup.json')),
          ),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await settle(tester);
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.dragUntilVisible(
      find.byKey(ValueKey(key)),
      find.byType(ListView),
      const Offset(0, -300),
    );
    // The tile may be built (cache extent) but still off the screen.
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.pump();
    await tester.tap(find.byKey(ValueKey(key)));
    await settle(tester);
  }

  /// A tap whose work has no visible end: wait for [done].
  Future<void> tapUntil(
    WidgetTester tester,
    String key,
    bool Function() done,
  ) async {
    await tester.dragUntilVisible(
      find.byKey(ValueKey(key)),
      find.byType(ListView),
      const Offset(0, -300),
    );
    // The tile may be built (cache extent) but still off the screen.
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.pump();
    await tester.tap(find.byKey(ValueKey(key)));
    await until(tester, done);
  }

  Future<void> unmount(WidgetTester tester) async {
    resetStackedDialogsForTest();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('Export everything writes a readable .livenow file', (
    tester,
  ) async {
    final files = _FakeFiles(dir);
    await pump(
      tester,
      files,
      seed: (db) async {
        await ActionService(db).createAction(name: 'Kept in the backup');
      },
    );
    await tapUntil(tester, 'settings-export-backup', () => files.saved.isNotEmpty);
    expect(files.saved, hasLength(1));
    expect(files.saved.single, endsWith('.livenow'));
    final header = await tester.runAsync(
      () => CompactBackupSource(File(files.saved.single)).header(),
    );
    expect(header!.schemaVersion, db.schemaVersion);
    await unmount(tester);
  });

  testWidgets('Import a backup: choose Merge, see the summary', (tester) async {
    // A backup made elsewhere.
    final source = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(source.close);
    final file = File('${dir.path}/from-elsewhere.livenow');
    await tester.runAsync(() async {
      await ActionService(source).createAction(name: 'From the file');
      await BackupWriter(source).writeCompact(file);
    });
    final files = _FakeFiles(
      dir,
      picked: [PickedBackupFile('from-elsewhere.livenow', file)],
    );
    await pump(tester, files);

    await tapKey(tester, 'settings-import-backup');
    expect(find.byKey(const ValueKey('backup-import-merge')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('backup-import-replace')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('backup-import-merge')));
    await until(
      tester,
      () => find.byKey(const ValueKey('backup-import-done')).evaluate().isNotEmpty,
    );
    expect(find.byKey(const ValueKey('backup-import-done')), findsOneWidget);
    expect(find.textContaining('rows added or updated'), findsOneWidget);

    final names = await tester.runAsync(
      () => db.select(db.actionsTable).get(),
    );
    expect(names!.map((a) => a.name), ['From the file']);
    await tester.tap(find.byKey(const ValueKey('backup-import-done')));
    await settle(tester);
    await unmount(tester);
  });

  testWidgets('a file that is not a backup is refused with a message', (
    tester,
  ) async {
    final bad = File('${dir.path}/notes.txt')..writeAsStringSync('hi');
    final files = _FakeFiles(dir, picked: [PickedBackupFile('notes.txt', bad)]);
    await pump(tester, files);
    await tapKey(tester, 'settings-import-backup');
    expect(find.textContaining('Choose one .livenow file'), findsOneWidget);
    expect(find.byKey(const ValueKey('backup-import-merge')), findsNothing);
    await unmount(tester);
  });

  testWidgets('automatic backup: choose a folder, switch on, Back up now', (
    tester,
  ) async {
    final backups = Directory('${dir.path}/auto')..createSync();
    final files = _FakeFiles(dir, folder: backups.path);
    await pump(
      tester,
      files,
      seed: (db) async {
        await ActionService(db).createAction(name: 'Backed up');
      },
    );
    // Switching on without a folder asks for one first.
    await tapKey(tester, 'settings-auto-backup');
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    );
    final s = container.read(autoBackupSettingsProvider);
    expect(s.enabled, isTrue);
    expect(s.folder, backups.path);

    await tapUntil(
      tester,
      'settings-auto-backup-now',
      () => backups.listSync().whereType<File>().any(
        (f) => f.path.endsWith('.livenow'),
      ),
    );
    await until(
      tester,
      () => find.textContaining('Backup saved').evaluate().isNotEmpty,
    );
    final written = backups
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.livenow'));
    expect(written, hasLength(1));
    expect(find.textContaining('Backup saved'), findsOneWidget);
    await unmount(tester);
  });
}
