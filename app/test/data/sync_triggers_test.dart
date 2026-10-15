import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/data/sync/sync_schema.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/budget_service.dart';
import 'package:livenow/domain/growth_rules.dart';
import 'package:livenow/domain/metric_service.dart';
import 'package:livenow/domain/postpone_rules.dart';

class _Ver {
  _Ver(this.seq, this.hlc, this.origin, this.deleted);
  final int seq;
  final String hlc;
  final String origin;
  final bool deleted;
}

void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late ActionService actions;

  setUp(() {
    db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys = ON;'),
      ),
    );
    actions = ActionService(db);
  });
  tearDown(() => db.close());

  Future<Map<String, _Ver>> versions() async {
    final rows = await db
        .customSelect(
          'SELECT seq, tbl, row_id, hlc, origin, deleted FROM sync_versions',
        )
        .get();
    return {
      for (final r in rows)
        '${r.read<String>('tbl')}|${r.read<String>('row_id')}': _Ver(
          r.read<int>('seq'),
          r.read<String>('hlc'),
          r.read<String>('origin'),
          r.read<int>('deleted') == 1,
        ),
    };
  }

  Future<String> deviceId() async =>
      (await db
              .customSelect(
                "SELECT value FROM sync_state WHERE key = 'device_id'",
              )
              .getSingle())
          .read<String>('value');

  Future<int> triggerCount() async =>
      (await db
              .customSelect(
                "SELECT COUNT(*) AS n FROM sqlite_master "
                "WHERE type = 'trigger' AND name LIKE 'sync_%'",
              )
              .getSingle())
          .read<int>('n');

  Future<void> exec(String sql, [List<Object?> args = const []]) =>
      db.customStatement(sql, args);

  group('bootstrap', () {
    test(
      'a fresh database has the sync tables, a device id and 48 triggers',
      () async {
        expect(await deviceId(), matches(RegExp(r'^[0-9a-f]{16}$')));
        expect(await triggerCount(), syncTables.length * 3);
        expect(await versions(), isEmpty);
        final applying = await db
            .customSelect('SELECT flag FROM sync_applying')
            .getSingle();
        expect(applying.read<int>('flag'), 0);
      },
    );

    test(
      'the device id never changes between opens of the same database',
      () async {
        final dir = Directory.systemTemp.createTempSync('livenow_sync_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final file = File('${dir.path}/a.sqlite');
        final first = AppDatabase.forTesting(NativeDatabase(file));
        final id1 =
            (await first
                    .customSelect(
                      "SELECT value FROM sync_state WHERE key='device_id'",
                    )
                    .getSingle())
                .read<String>('value');
        await first.close();
        final second = AppDatabase.forTesting(NativeDatabase(file));
        final id2 =
            (await second
                    .customSelect(
                      "SELECT value FROM sync_state WHERE key='device_id'",
                    )
                    .getSingle())
                .read<String>('value');
        await second.close();
        expect(id2, id1);
      },
    );
  });

  group('what gets logged', () {
    test('insert, update and delete of any write path', () async {
      final id = await actions.createAction(name: 'Read');
      final dev = await deviceId();
      var v = (await versions())['actions|$id']!;
      expect(v.deleted, isFalse);
      expect(v.origin, dev);
      expect(v.hlc, endsWith('-$dev'));

      await exec('UPDATE actions SET name = ? WHERE id = ?', ['Read more', id]);
      final updated = (await versions())['actions|$id']!;
      expect(updated.seq, greaterThan(v.seq));
      expect(updated.hlc.compareTo(v.hlc), greaterThan(0));

      await exec('DELETE FROM actions WHERE id = ?', [id]);
      v = (await versions())['actions|$id']!;
      expect(v.deleted, isTrue);
      expect(v.seq, greaterThan(updated.seq));
    });

    test('deleteAction tombstones the action and every child row; undo '
        'resurrects them with newer stamps', () async {
      final id = await actions.createAction(
        name: 'Run',
        startAt: DateTime.utc(2026, 10, 1, 9),
        endAt: DateTime.utc(2026, 10, 1, 10),
      );
      await actions.start(id);
      final before = await versions();
      final occurrence = before.keys.firstWhere(
        (k) => k.startsWith('action_occurrences|'),
      );

      final undo = await actions.deleteAction(id);
      final after = await versions();
      expect(after['actions|$id']!.deleted, isTrue);
      expect(after[occurrence]!.deleted, isTrue);

      await actions.undoDelete(undo);
      final back = await versions();
      expect(back['actions|$id']!.deleted, isFalse);
      expect(back['actions|$id']!.hlc.compareTo(after['actions|$id']!.hlc), 1);
      expect(back[occurrence]!.deleted, isFalse);
    });

    test('budget_settings is keyed by its key column', () async {
      await BudgetService(db).saveSettings(
        const BudgetSettings(
          baseCurrency: 'USD',
          periodMonths: 6,
          tolerance: 5,
        ),
      );
      final v = await versions();
      expect(v.keys, containsAll(['budget_settings|base_currency']));
      expect(v.keys, contains('budget_settings|period_months'));
    });

    test('all 16 tables are tracked', () async {
      final b = BudgetService(db);
      final acc = await b.saveAccount(
        name: 'A',
        currency: 'EUR',
        rateToBase: 1,
      );
      final cat = await b.saveCategory(
        CategoryInput(name: 'C', accountCountId: acc),
      );
      await b.createTransaction(categoryId: cat);
      await b.saveSettings(const BudgetSettings());
      final m1 = await MetricService(db)
          .saveMetric(name: 'M1', kind: MetricKind.boolean);
      final m2 = await MetricService(db)
          .saveMetric(name: 'M2', kind: MetricKind.boolean);
      await MetricService(db).addRelation(fromId: m2, toId: m1);
      final a1 = await actions.createAction(name: 'A1', metricIds: [m1]);
      final a2 = await actions.createAction(name: 'A2');
      await exec(
        "INSERT INTO action_dependencies (id, predecessor_id, successor_id) "
        "VALUES ('d1', '$a1', '$a2')",
      );
      await actions.start(a1);
      await exec(
        "INSERT INTO countable_activities (id, name, created_at, updated_at) VALUES ('ca1', 'Read', 't', 't')",
      );
      await exec(
        "INSERT INTO action_templates (id, name, payload) VALUES ('t1', 'T', '{}')",
      );
      await exec(
        "INSERT INTO saved_views (id, screen, name, created_at, updated_at) VALUES ('sv1', 'budget.tx', 'V', 't', 't')",
      );
      await exec(
        "INSERT INTO plan_items (id, name, start_date, created_at, updated_at) VALUES ('pi1', 'P', '2026-10-19', 't', 't')",
      );
      await exec(
        "INSERT INTO plan_overrides (id, plan_item_id, date, created_at, updated_at) VALUES ('po1', 'pi1', '2026-10-20', 't', 't')",
      );
      await exec(
        "INSERT INTO budget_tx_templates (id, name, created_at, updated_at) VALUES ('bt1', 'T', 't', 't')",
      );
      final tables = {
        for (final k in (await versions()).keys) k.split('|').first,
      };
      expect(tables, syncTables.keys.toSet());
    });
  });

  group('conflict policies of the statement that fires a trigger', () {
    // An INSERT OR REPLACE inside a trigger is overridden by the outer
    // statement's policy; these writes broke the first version of the triggers.
    test('upsert (ON CONFLICT DO UPDATE) of an existing row', () async {
      await exec(
        "INSERT INTO action_templates (id, name, payload) VALUES ('t1', 'A', '{}')",
      );
      final first = (await versions())['action_templates|t1']!;
      await exec(
        "INSERT INTO action_templates (id, name, payload) VALUES ('t1', 'B', '{}') "
        "ON CONFLICT(id) DO UPDATE SET name = excluded.name",
      );
      final second = (await versions())['action_templates|t1']!;
      expect(second.seq, greaterThan(first.seq));
      expect(second.hlc.compareTo(first.hlc), 1);
      expect(second.deleted, isFalse);
    });

    test('INSERT OR REPLACE of an existing row', () async {
      await exec(
        "INSERT INTO action_templates (id, name, payload) VALUES ('t1', 'A', '{}')",
      );
      final first = (await versions())['action_templates|t1']!;
      await exec(
        "INSERT OR REPLACE INTO action_templates (id, name, payload) "
        "VALUES ('t1', 'B', '{}')",
      );
      final second = (await versions())['action_templates|t1']!;
      expect(second.seq, greaterThan(first.seq));
      expect(second.deleted, isFalse);
    });

    test('a bulk delete that SET NULLs children through foreign keys', () async {
      final b = BudgetService(db);
      final acc = await b.saveAccount(
        name: 'A',
        currency: 'EUR',
        rateToBase: 1,
      );
      final parent = await b.saveCategory(const CategoryInput(name: 'P'));
      final child = await b.saveCategory(
        CategoryInput(name: 'C', parentId: parent, accountCountId: acc),
      );
      final tx = await b.createTransaction(categoryId: child);
      final before = await versions();

      await exec('DELETE FROM budget_categories');
      final after = await versions();
      expect(after['budget_categories|$parent']!.deleted, isTrue);
      expect(after['budget_categories|$child']!.deleted, isTrue);
      // The transaction lost its category through SET NULL: logged as an edit.
      expect(
        after['budget_transactions|$tx']!.seq,
        greaterThan(before['budget_transactions|$tx']!.seq),
      );
      expect(after['budget_transactions|$tx']!.deleted, isFalse);
    });

    test('seq numbers every change once, in order', () async {
      final a = await actions.createAction(name: 'a');
      final b = await actions.createAction(name: 'b');
      await exec('UPDATE actions SET name = ? WHERE id = ?', ['a2', a]);
      final v = await versions();
      expect(v['actions|$a']!.seq, greaterThan(v['actions|$b']!.seq));
      final all = v.values.map((e) => e.seq).toList();
      expect(all.toSet().length, all.length); // unique
      final clock = await db
          .customSelect('SELECT seq FROM sync_clock WHERE id = 1')
          .getSingle();
      expect(clock.read<int>('seq'), all.reduce((x, y) => x > y ? x : y));
    });
  });

  group('what is NOT logged', () {
    test('derived cache columns and no-op updates', () async {
      final metric = await MetricService(db)
          .saveMetric(name: 'Fit', kind: MetricKind.boolean);
      final id = await actions.createAction(name: 'x');
      final base = await versions();

      await exec(
        'UPDATE metrics SET weight = 99, importance_level = 7 '
        'WHERE id = ?',
        [metric],
      );
      await exec("UPDATE actions SET notes_text = 'cached' WHERE id = ?", [id]);
      await exec('UPDATE actions SET name = name WHERE id = ?', [id]);
      await exec('UPDATE actions SET name = ? WHERE id = ?', ['x', id]);
      final same = await versions();
      expect(same['metrics|$metric']!.seq, base['metrics|$metric']!.seq);
      expect(same['actions|$id']!.seq, base['actions|$id']!.seq);

      await exec('UPDATE metrics SET name = ? WHERE id = ?', [
        'Fitter',
        metric,
      ]);
      expect(
        (await versions())['metrics|$metric']!.seq,
        greaterThan(base['metrics|$metric']!.seq),
      );
    });

    test('the update trigger lists exactly the synced columns', () async {
      final sql =
          (await db
                  .customSelect(
                    "SELECT sql FROM sqlite_master WHERE name = 'sync_metrics_upd'",
                  )
                  .getSingle())
              .read<String>('sql');
      expect(sql, contains('name'));
      expect(sql, contains('pos_x'));
      expect(sql, isNot(contains('weight')));
      expect(sql, isNot(contains('importance_level')));
      final actionSql =
          (await db
                  .customSelect(
                    "SELECT sql FROM sqlite_master WHERE name = 'sync_actions_upd'",
                  )
                  .getSingle())
              .read<String>('sql');
      expect(actionSql, isNot(contains('notes_text')));
      expect(actionSql, contains('notes,'));
    });

    test('nothing is logged while sync_applying = 1', () async {
      await exec('UPDATE sync_applying SET flag = 1');
      final id = await actions.createAction(name: 'remote');
      await exec('UPDATE actions SET name = ? WHERE id = ?', ['r2', id]);
      await exec('DELETE FROM actions WHERE id = ?', [id]);
      expect(await versions(), isEmpty);
      await exec('UPDATE sync_applying SET flag = 0');
      await actions.createAction(name: 'local');
      expect(await versions(), hasLength(1));
    });
  });

  group('hybrid logical clock', () {
    test(
      'strictly increasing even for many writes in the same millisecond',
      () async {
        final id = await actions.createAction(name: 'tick');
        final seen = <String>[(await versions())['actions|$id']!.hlc];
        for (var i = 0; i < 60; i++) {
          await exec('UPDATE actions SET name = ? WHERE id = ?', ['n$i', id]);
          seen.add((await versions())['actions|$id']!.hlc);
        }
        for (var i = 1; i < seen.length; i++) {
          expect(seen[i].compareTo(seen[i - 1]), 1, reason: 'at $i');
        }
      },
    );

    test(
      'a clock that jumped into the future keeps the stamps ahead',
      () async {
        await exec(
          "UPDATE sync_clock SET last_wall = '2099-01-01T00:00:00.000Z' "
          'WHERE id = 1',
        );
        final id = await actions.createAction(name: 'future');
        final a = (await versions())['actions|$id']!.hlc;
        expect(a, startsWith('2099-01-01T00:00:00.000Z-'));
        await exec('UPDATE actions SET name = ? WHERE id = ?', ['n', id]);
        final b = (await versions())['actions|$id']!.hlc;
        expect(b.compareTo(a), 1); // the counter advances under the same wall
      },
    );

    test('stamps sort as text in clock order', () async {
      final a = await actions.createAction(name: 'a');
      final b = await actions.createAction(name: 'b');
      final v = await versions();
      expect(v['actions|$b']!.hlc.compareTo(v['actions|$a']!.hlc), 1);
      expect(v['actions|$b']!.seq, greaterThan(v['actions|$a']!.seq));
    });
  });

  group('self-healing', () {
    test(
      'ensureSyncTriggers is idempotent and restores a missing trigger',
      () async {
        await ensureSyncTriggers(db);
        expect(await triggerCount(), 48);
        await exec('DROP TRIGGER sync_actions_upd');
        expect(await triggerCount(), 47);
        await ensureSyncTriggers(db);
        expect(await triggerCount(), 48);
        final id = await actions.createAction(name: 'x');
        final before = (await versions())['actions|$id']!.seq;
        await exec('UPDATE actions SET name = ? WHERE id = ?', ['y', id]);
        expect((await versions())['actions|$id']!.seq, greaterThan(before));
      },
    );

    test(
      'rows written without triggers get a version from reconcile',
      () async {
        await exec('UPDATE sync_applying SET flag = 1');
        final id = await actions.createAction(name: 'ghost');
        await exec('UPDATE sync_applying SET flag = 0');
        expect(await versions(), isEmpty);

        await reconcileSyncVersions(db);
        final v = (await versions())['actions|$id']!;
        expect(v.origin, await deviceId());
        expect(v.deleted, isFalse);
        // Idempotent.
        await reconcileSyncVersions(db);
        expect(await versions(), hasLength(1));
      },
    );

    test('new columns are tracked automatically', () async {
      // The column list comes from PRAGMA table_info, minus the explicit
      // exclusions: a newly added column needs no change here.
      expect(await syncedColumns(db, 'actions'), contains('notes'));
      expect(await syncedColumns(db, 'actions'), isNot(contains('notes_text')));
      final metricCols = await syncedColumns(db, 'metrics');
      expect(metricCols, isNot(contains('weight')));
      expect(metricCols, isNot(contains('importance_level')));
    });
  });

  group('migration v10 -> v11', () {
    test(
      'every existing row gets a seed version; triggers and device id exist',
      () async {
        final dir = Directory.systemTemp.createTempSync('livenow_sync_mig_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final file = File('${dir.path}/m.sqlite');

        // Build a v11 database with data...
        final first = AppDatabase.forTesting(NativeDatabase(file));
        final a = await ActionService(first).createAction(name: 'Old action');
        final b = BudgetService(first);
        final acc = await b.saveAccount(
          name: 'A',
          currency: 'EUR',
          rateToBase: 1,
        );
        final cat = await b.saveCategory(
          CategoryInput(name: 'C', accountCountId: acc),
        );
        final tx = await b.createTransaction(categoryId: cat);
        await first.close();

        // ...and turn it back into a v10 one: no sync tables, no triggers.
        final second = AppDatabase.forTesting(
          NativeDatabase(
            file,
            setup: (raw) {
              for (final t in raw.select(
                "SELECT name FROM sqlite_master WHERE type = 'trigger'",
              )) {
                raw.execute('DROP TRIGGER ${t['name']}');
              }
              for (final t in [
                'sync_versions',
                'sync_state',
                'sync_applying',
                'sync_clock',
              ]) {
                raw.execute('DROP TABLE IF EXISTS $t');
              }
              raw.execute('PRAGMA user_version = 10');
            },
          ),
        );
        addTearDown(second.close);

        final rows = await second
            .customSelect(
              'SELECT tbl, row_id, hlc, origin, deleted FROM sync_versions',
            )
            .get();
        final byKey = {
          for (final r in rows)
            '${r.read<String>('tbl')}|${r.read<String>('row_id')}': r,
        };
        expect(
          byKey.keys,
          containsAll([
            'actions|$a',
            'budget_accounts|$acc',
            'budget_categories|$cat',
            'budget_transactions|$tx',
          ]),
        );
        for (final r in rows) {
          expect(r.read<String>('origin'), 'seed');
          expect(r.read<int>('deleted'), 0);
        }
        // updated_at carried over (to the millisecond) as the seed stamp.
        expect(
          byKey['actions|$a']!.read<String>('hlc'),
          endsWith('Z-0000-seed'),
        );
        expect(byKey['budget_settings|x'], isNull);
        final triggers = await second
            .customSelect(
              "SELECT COUNT(*) AS n FROM sqlite_master "
              "WHERE type='trigger' AND name LIKE 'sync_%'",
            )
            .getSingle();
        expect(triggers.read<int>('n'), 48);
        final device = await second
            .customSelect(
              "SELECT value FROM sync_state WHERE key = 'device_id'",
            )
            .getSingle();
        expect(device.read<String>('value'), hasLength(16));
      },
    );
  });

  test('a seeded row is older than any real edit', () {
    expect(syncEpochHlc.compareTo('2026-01-01T00:00:00.000Z-0000-abcd'), -1);
  });

  test('unused import guard', () {
    expect(const Variable<int>(1), isNotNull);
  });
}
