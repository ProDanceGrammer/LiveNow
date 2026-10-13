import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:livenow/core/ids.dart';
import 'package:livenow/data/backup/backup_import_service.dart';
import 'package:livenow/data/backup/backup_sources.dart';
import 'package:livenow/data/backup/backup_writer.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/data/sync/sync_schema.dart';
import 'package:livenow/data/sync/sync_store.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/budget_io_service.dart';
import 'package:livenow/domain/dependency_service.dart';
import 'package:livenow/domain/full_backup.dart';
import 'package:livenow/domain/growth_rules.dart';
import 'package:livenow/domain/metric_service.dart';
import 'package:livenow/domain/postpone_rules.dart';

import '../domain/budget_csv_test.dart'
    show accountsCsv, categoriesCsv, transactionsCsv;

AppDatabase _db() => AppDatabase.forTesting(
  NativeDatabase.memory(
    setup: (raw) => raw.execute('PRAGMA foreign_keys = ON;'),
  ),
);

/// Every user table as lists of values (derived caches left out), in a stable
/// order: what a round trip must reproduce exactly.
Future<Map<String, List<List<Object?>>>> _dump(AppDatabase db) async {
  final out = <String, List<List<Object?>>>{};
  await for (final c in BackupWriter(db).chunks()) {
    out.putIfAbsent(c.table, () => []).addAll(c.rows);
  }
  return out;
}

Future<void> _seed(AppDatabase db) async {
  final metrics = MetricService(db);
  final goal = await metrics.saveMetric(
    name: '🏃 Health',
    kind: MetricKind.count,
    window: MetricWindow.week,
    target: 3,
    isMain: true,
  );
  final sub = await metrics.saveMetric(
    name: 'Sleep, "well"',
    kind: MetricKind.boolean,
    leadsToIds: [goal],
  );
  final actions = ActionService(db);
  final notes = jsonEncode({
    'document': {
      'type': 'page',
      'children': [
        {
          'type': 'paragraph',
          'data': {
            'delta': [
              {'insert': 'Line one\nLine "two", with comma ✅ 🇺🇦'},
            ],
          },
        },
      ],
    },
  });
  final a1 = await actions.createAction(
    name: 'Run, then "stretch"',
    notes: notes,
    metricIds: [goal, sub],
    startAt: DateTime.utc(2026, 10, 3, 6),
    endAt: DateTime.utc(2026, 10, 3, 7),
  );
  final a2 = await actions.createAction(name: 'Shower', metricIds: [sub]);
  await DependencyService(db).addDependency(predecessorId: a1, successorId: a2);
  await actions.start(a2);
  await db
      .into(db.actionTemplatesTable)
      .insert(
        ActionTemplatesTableCompanion.insert(
          id: newId(),
          name: '💧 Water',
          payload: jsonEncode({
            'name': '💧 Water',
            'estimatedMinutes': 5,
            'metricIds': [sub],
          }),
        ),
      );
  await BudgetIoService(db).importNotionCsvs(
    accountsCsv: accountsCsv,
    categoriesCsv: categoriesCsv,
    transactionsCsv: transactionsCsv,
  );
}

void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late AppDatabase other;
  late Directory dir;

  BackupImportService service(AppDatabase d) => BackupImportService(
    d,
    SyncStore(d),
    afterImport: () => MetricService(d).recomputeWeights(),
  );

  setUp(() async {
    db = _db();
    other = _db();
    dir = Directory.systemTemp.createTempSync('livenow-roundtrip');
    await _seed(db);
  });

  tearDown(() async {
    await db.close();
    await other.close();
    dir.deleteSync(recursive: true);
  });

  test('the table order covers every synced table exactly once', () {
    expect(backupTableOrder.toSet(), syncTables.keys.toSet());
    expect(backupTableOrder.length, syncTables.length);
  });

  Future<void> roundTrip(
    Future<BackupSource> Function() write, {
    required String label,
  }) async {
    final before = await _dump(db);
    expect(before['actions'], isNotEmpty);
    expect(before['budget_transactions'], isNotEmpty);
    final src = await write();
    final summary = await service(other).import(src);
    expect(summary.written, greaterThan(0), reason: label);
    expect(await _dump(other), before, reason: '$label: identical rows');
    // The derived caches were rebuilt.
    final w1 = await db.customSelect('SELECT id, weight FROM metrics').get();
    final w2 = await other.customSelect('SELECT id, weight FROM metrics').get();
    expect(
      {for (final r in w2) r.read<String>('id'): r.read<double>('weight')},
      {for (final r in w1) r.read<String>('id'): r.read<double>('weight')},
    );
    final text = await other
        .customSelect('SELECT notes_text FROM actions WHERE notes IS NOT NULL')
        .getSingle();
    expect(text.read<String?>('notes_text'), contains('line one'));
  }

  test('compact .livenow file round-trips every table', () async {
    await roundTrip(() async {
      final f = File('${dir.path}/a.livenow');
      final n = await BackupWriter(db).writeCompact(f);
      expect(n, greaterThan(10));
      return CompactBackupSource(f);
    }, label: 'compact');
  });

  test('CSV folder round-trips, including NULL vs empty and quotes', () async {
    await roundTrip(() async {
      final files = await BackupWriter(db).writeCsvFolder(Directory(dir.path));
      return CsvFolderBackupSource({
        for (final f in files) f.uri.pathSegments.last: f,
      });
    }, label: 'csv');
  });

  test('SQLite copy round-trips and carries no pairing data', () async {
    await db.customStatement(
      "INSERT INTO sync_state (key, value) VALUES ('secret-test', 'x')",
    );
    await roundTrip(() async {
      final f = File('${dir.path}/copy.db');
      await BackupWriter(db).writeSqliteCopy(f);
      // Looked at with plain sqlite: opening it as an AppDatabase would
      // create a device id again.
      final raw = sqlite.sqlite3.open(f.path);
      try {
        for (final t in ['sync_state', 'sync_peers', 'sync_versions']) {
          expect(
            raw.select('SELECT COUNT(*) AS n FROM $t').first['n'],
            0,
            reason: t,
          );
        }
      } finally {
        raw.close();
      }
      return SqliteBackupSource(f);
    }, label: 'sqlite');
  });

  test('the compact file is much smaller than the plain JSON', () async {
    final f = File('${dir.path}/a.livenow');
    await BackupWriter(db).writeCompact(f);
    final plain = utf8.encode(jsonEncode(await _dump(db))).length;
    expect(f.lengthSync(), lessThan(plain));
  });

  group('merge', () {
    late File file;
    setUp(() async {
      file = File('${dir.path}/a.livenow');
      await BackupWriter(db).writeCompact(file);
      await service(other).import(CompactBackupSource(file));
    });

    Future<String> nameOf(String id) async => (await other
            .customSelect('SELECT name FROM actions WHERE id = ?', variables: [
              Variable.withString(id),
            ])
            .getSingle())
        .read<String>('name');

    test('a newer local row is kept, an older one is overwritten', () async {
      final id = (await other.customSelect('SELECT id FROM actions LIMIT 1')
              .getSingle())
          .read<String>('id');
      final original = await nameOf(id);
      await other.customStatement(
        "UPDATE actions SET name = 'local', updated_at = '2099-01-01T00:00:00.000Z' WHERE id = ?",
        [id],
      );
      final kept = await service(other).import(CompactBackupSource(file));
      expect(await nameOf(id), 'local');
      expect(kept.kept, greaterThan(0));

      await other.customStatement(
        "UPDATE actions SET name = 'stale', updated_at = '2000-01-01T00:00:00.000Z' WHERE id = ?",
        [id],
      );
      await service(other).import(CompactBackupSource(file));
      expect(await nameOf(id), original);
    });

    test('nothing is deleted, rows missing here come back', () async {
      final extra = await ActionService(other).createAction(name: 'Only here');
      await other.customStatement('DELETE FROM action_templates');
      await service(other).import(CompactBackupSource(file));
      expect(await nameOf(extra), 'Only here');
      final t = await other
          .customSelect('SELECT COUNT(*) AS n FROM action_templates')
          .getSingle();
      expect(t.read<int>('n'), 1);
    });

    test('importing the same file twice changes nothing', () async {
      final before = await _dump(other);
      final again = await service(other).import(CompactBackupSource(file));
      expect(again.written, 0);
      expect(await _dump(other), before);
    });

    test('Replace removes rows that are not in the file, after a copy', () async {
      final extra = await ActionService(other).createAction(name: 'Only here');
      final s = await service(other).import(
        CompactBackupSource(file),
        mode: BackupImportMode.replace,
        safetyBackupDir: dir,
      );
      expect(
        await other
            .customSelect('SELECT 1 FROM actions WHERE id = ?', variables: [
              Variable.withString(extra),
            ])
            .get(),
        isEmpty,
      );
      expect(File(s.safetyCopy!).existsSync(), isTrue);
      expect(await _dump(other), await _dump(db));
    });
  });

  group('bad files change nothing', () {
    Future<void> expectRejected(BackupSource src) async {
      final before = await _dump(other);
      await expectLater(service(other).import(src), throwsA(anything));
      expect(await _dump(other), before);
    }

    test('garbage', () async {
      final f = File('${dir.path}/x.livenow')..writeAsStringSync('hello');
      await expectRejected(CompactBackupSource(f));
    });

    test('a cut-off file', () async {
      final f = File('${dir.path}/a.livenow');
      await BackupWriter(db).writeCompact(f);
      final bytes = f.readAsBytesSync();
      final cut = File('${dir.path}/cut.livenow')
        ..writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 2));
      await other.customStatement('DELETE FROM action_templates');
      await expectRejected(CompactBackupSource(cut));
    });

    test('a newer schema is refused', () async {
      final f = File('${dir.path}/new.livenow')
        ..writeAsBytesSync(
          gzip.encode(
            utf8.encode(
              '${encodeHeaderLine(999, DateTime.now())}\n${encodeEndLine(0)}\n',
            ),
          ),
        );
      await expectRejected(CompactBackupSource(f));
    });
  });

  test('references to missing rows are repaired, triggers stay on', () async {
    final f = File('${dir.path}/dangling.livenow');
    final lines = [
      encodeHeaderLine(12, DateTime.now()),
      encodeTableLine('action_metrics', ['id', 'action_id', 'metric_id']),
      jsonEncode([newId(), 'no-such-action', 'no-such-metric']),
      encodeEndLine(1),
    ];
    f.writeAsBytesSync(gzip.encode(utf8.encode('${lines.join('\n')}\n')));
    final s = await service(other).import(CompactBackupSource(f));
    expect(s.repairs, greaterThan(0));
    final rows = await other
        .customSelect('SELECT COUNT(*) AS n FROM action_metrics')
        .getSingle();
    expect(rows.read<int>('n'), 0);
    // Imported rows are stamped local edits, and the switch is back on.
    final flag = await other
        .customSelect('SELECT flag FROM sync_applying')
        .getSingle();
    expect(flag.read<int>('flag'), 0);
    final ok = File('${dir.path}/ok.livenow');
    final okLines = [
      encodeHeaderLine(12, DateTime.now()),
      encodeTableLine('countable_activities', [
        'id',
        'name',
        'created_at',
        'updated_at',
      ]),
      jsonEncode(['c1', 'Reading', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z']),
      encodeEndLine(1),
    ];
    ok.writeAsBytesSync(gzip.encode(utf8.encode('${okLines.join('\n')}\n')));
    await service(other).import(CompactBackupSource(ok));
    final v = await other
        .customSelect(
          "SELECT COUNT(*) AS n FROM sync_versions WHERE tbl = 'countable_activities' AND row_id = 'c1' AND deleted = 0",
        )
        .getSingle();
    expect(v.read<int>('n'), 1);
  });
}
