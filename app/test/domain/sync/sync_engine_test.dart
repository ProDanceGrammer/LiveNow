import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/budget_service.dart';
import 'package:livenow/domain/dependency_service.dart';
import 'package:livenow/domain/growth_rules.dart';
import 'package:livenow/domain/metric_service.dart';
import 'package:livenow/domain/sync/sync_engine.dart';
import 'package:livenow/domain/sync/sync_models.dart';

import 'sync_harness.dart';

const _notes =
    '{"document":{"type":"page","children":[{"type":"paragraph","data":'
    '{"delta":[{"insert":"Hello Notes"}]}}]}}';

void main() {
  late SyncDevice a;
  late SyncDevice b;

  setUp(() async {
    a = SyncDevice();
    b = SyncDevice();
    await a.id; // opens the databases (triggers + clock)
    await b.id;
  });

  tearDown(() async {
    await a.close();
    await b.close();
  });

  /// Both devices, synced both ways until quiet, must hold identical data.
  Future<void> settle() async {
    for (var i = 0; i < 3; i++) {
      await syncWith(a, b);
      await syncWith(b, a);
    }
  }

  Future<void> expectConverged() async {
    await settle();
    expect(await b.dump(), equals(await a.dump()));
    for (final d in [a, b]) {
      expect(await d.rows('PRAGMA foreign_key_check'), isEmpty);
    }
  }

  group('replication', () {
    test('a wiped phone gets back the rows it had written itself', () async {
      // a = PC (serves), b = phone. The phone's own rows reached the PC before
      // the phone was wiped by re-pairing; the PC must send them back.
      await ActionService(a.db).createAction(name: 'From the PC');
      await ActionService(b.db).createAction(name: 'From the phone');
      await syncWith(b, a);
      expect(await a.count('actions'), 2);

      await b.store.wipeForReplace();
      expect(await b.count('actions'), 0);
      await syncWith(b, a);

      expect(await b.count('actions'), 2);
      expect(await b.dump(), equals(await a.dump()));
    });

    test('re-pairing without a wipe loses no edit of either side', () async {
      // Synced once, then both sides edit and the link breaks (unpaired).
      final actionsA = ActionService(a.db);
      final actionsB = ActionService(b.db);
      final shared = await actionsA.createAction(name: 'Shared');
      await syncWith(b, a);
      await b.exec(
        "UPDATE actions SET name = 'Shared, edited on the phone', "
        "updated_at = '9999-01-01T00:00:00.000000Z' WHERE id = '$shared'",
      );
      await actionsB.createAction(name: 'New on the phone');
      await actionsA.createAction(name: 'New on the PC');
      // Re-pair = both forget the cursors for each other, nothing is wiped.
      await b.store.forgetPeer(await a.store.deviceId());
      await a.store.forgetPeer(await b.store.deviceId());

      await syncWith(b, a);

      expect(await a.count('actions'), 3);
      expect(await b.count('actions'), 3);
      final names = [
        for (final r in await a.rows('SELECT name FROM actions'))
          r['name'],
      ];
      expect(names, contains('Shared, edited on the phone'));
      expect(names, contains('New on the phone'));
      expect(await b.dump(), equals(await a.dump()));
    });

    test('a wiped phone gets its own rows back over several pages', () async {
      // The harness pages by 7: 30 phone rows span several pages, and every
      // page after the first starts above position 0.
      final svc = ActionService(b.db);
      for (var i = 0; i < 30; i++) {
        await svc.createAction(name: 'Phone $i');
      }
      await syncWith(b, a);
      expect(await a.count('actions'), 30);

      await b.store.wipeForReplace();
      await syncWith(b, a);

      expect(await b.count('actions'), 30);
      expect(await b.dump(), equals(await a.dump()));
    });

    test('a stale log entry does not cut the rest of a pull short', () async {
      final svc = ActionService(a.db);
      final ids = <String>[];
      for (var i = 0; i < 20; i++) {
        ids.add(await svc.createAction(name: 'PC $i'));
      }
      // Remove one data row without a tombstone (a silent delete): its log
      // entry now points at nothing.
      await a.exec('UPDATE sync_applying SET flag = 1');
      await a.exec("DELETE FROM actions WHERE id = '${ids.first}'");
      await a.exec('UPDATE sync_applying SET flag = 0');

      await syncWith(b, a);

      expect(await b.count('actions'), 19);
    });

    test('rows and their links reach the other device, derived values too', () async {
      final metrics = MetricService(a.db);
      final m = await metrics.saveMetric(
        name: 'Sleep',
        kind: MetricKind.boolean,
        isMain: true,
      );
      final x = await ActionService(a.db)
          .createAction(name: 'X', notes: _notes, metricIds: [m]);

      final r = await syncWith(b, a);
      expect(r.pulled, greaterThan(0));
      expect(await b.dump(), equals(await a.dump()));
      // notes_text and the direction weight are derived on the receiving side.
      final row = await b.rows(
        "SELECT notes_text FROM actions WHERE id = '$x'",
      );
      expect(row.single['notes_text'], contains('hello notes'));
      final weight = await b.rows('SELECT weight FROM metrics');
      expect(weight.single['weight'], 1000);
    });

    test('applying remote changes is not logged as a local edit', () async {
      await ActionService(a.db).createAction(name: 'X');
      await syncWith(b, a);
      expect(await b.count('sync_versions', "origin = '${await b.id}'"), 0);
      // ...so nothing is sent back and a second sync is quiet.
      final again = await syncWith(b, a);
      expect(again.pulled, 0);
      expect(again.pushed, 0);
    });

    test('changes made on both sides meet in the middle', () async {
      await ActionService(a.db).createAction(name: 'From A');
      await ActionService(b.db).createAction(name: 'From B');
      await expectConverged();
      expect(await a.count('actions'), 2);
    });

    test('pages: more rows than one page both ways', () async {
      for (var i = 0; i < 25; i++) {
        await ActionService(a.db).createAction(name: 'A$i');
      }
      for (var i = 0; i < 18; i++) {
        await ActionService(b.db).createAction(name: 'B$i');
      }
      await expectConverged();
      expect(await a.count('actions'), 43);
    });

    test('a schema version mismatch refuses to sync', () async {
      final other = SyncEngine(b.store, a.db.schemaVersion + 1);
      expect(
        other.sync(InProcessTransport(a, await b.id)),
        throwsA(isA<SyncVersionMismatch>()),
      );
    });

    test('a table this version does not know is skipped', () async {
      final r = await b.store.apply(const [
        SyncChange(
          table: 'from_the_future',
          rowId: '1',
          hlc: '2026-10-10T12:00:00.000Z-0000-feed',
          origin: 'feed',
          deleted: false,
          data: {'id': '1'},
        ),
      ], unsyncedAfterSeq: 0);
      expect(r.applied, 0);
    });

    test('the local clock moves past a stamp that is ahead', () async {
      // A device whose clock runs an hour fast (a far-future stamp is refused
      // on purpose, see change_validation_test.dart).
      final ahead = DateTime.now().toUtc().add(const Duration(hours: 1));
      final future = '${ahead.toIso8601String().substring(0, 19)}.000Z-0000-feed';
      await b.store.apply([
        SyncChange(
          table: 'action_templates',
          rowId: 't1',
          hlc: future,
          origin: 'feed',
          deleted: false,
          data: const {'id': 't1', 'name': 'n', 'payload': '{}'},
        ),
      ], unsyncedAfterSeq: 0);
      await b.exec(
        "INSERT INTO action_templates (id, name, payload) VALUES ('t2','m','{}')",
      );
      final hlc = await b.store.rowHlc('action_templates', 't2');
      expect(hlc!.compareTo(future), greaterThan(0));
    });
  });

  group('deletes', () {
    test('a deletion removes the row and its dependants everywhere', () async {
      final svc = ActionService(a.db);
      final x = await svc.createAction(name: 'X');
      final y = await svc.createAction(name: 'Y');
      await DependencyService(a.db)
          .addDependency(predecessorId: x, successorId: y);
      await expectConverged();
      expect(await b.count('action_dependencies'), 1);

      await svc.deleteAction(x);
      await expectConverged();
      expect(await b.count('actions'), 1);
      expect(await b.count('action_dependencies'), 0);
    });

    test('a cascade on the receiving side leaves tombstones for what it removed', () async {
      final x = await ActionService(a.db).createAction(name: 'X');
      await expectConverged();
      // b links something to X while a deletes X: b's link has no parent after
      // the merge, so it must be deleted and that deletion must reach a.
      final m = await MetricService(b.db)
          .saveMetric(name: 'M', kind: MetricKind.boolean);
      await ActionService(b.db).setMetrics(x, [m]);
      await tick();
      await ActionService(a.db).deleteAction(x);
      await expectConverged();
      expect(await a.count('action_metrics'), 0);
      expect(await b.count('action_metrics'), 0);
      expect(await a.count('actions'), 0);
    });

    test('undoing a delete brings the row back on the other device', () async {
      final svc = ActionService(a.db);
      final x = await svc.createAction(name: 'X');
      final y = await svc.createAction(name: 'Y');
      await DependencyService(a.db)
          .addDependency(predecessorId: x, successorId: y);
      await expectConverged();
      final undo = await svc.deleteAction(x);
      await expectConverged();
      expect(await b.count('actions'), 1);
      await tick();
      await svc.undoDelete(undo);
      await expectConverged();
      expect(await b.count('actions'), 2);
      expect(await b.count('action_dependencies'), 1);
    });

    test(
      'a later edit beats an earlier deletion and the other way round',
      () async {
        final svc = ActionService(a.db);
        final x = await svc.createAction(name: 'X');
        final y = await svc.createAction(name: 'Y');
        await expectConverged();

        await svc.deleteAction(x);
        await tick();
        await ActionService(b.db).updateAction(
          actionId: x,
          name: 'X edited',
          postponeFlex: 'flexible',
          isAllDay: false,
        );
        await ActionService(b.db).deleteAction(y);
        await tick();
        await svc.updateAction(
          actionId: y,
          name: 'Y edited',
          postponeFlex: 'flexible',
          isAllDay: false,
        );
        await expectConverged();
        final names = await a.rows('SELECT name FROM actions ORDER BY name');
        expect([for (final r in names) r['name']], ['X edited', 'Y edited']);
      },
    );
  });

  group('transfers', () {
    test(
      'a page cut before a re-edited parent still carries that parent',
      () async {
        final bud = BudgetService(a.db);
        final cat = await bud.saveCategory(
          const CategoryInput(name: 'Food', price: 3),
        );
        final tx = await bud.createTransaction(categoryId: cat);
        final cut = await a.store.currentSeq();
        await tick();
        // The category is edited AFTER the transaction: its single log entry
        // moves beyond the cut.
        await bud.saveCategory(
          CategoryInput(id: cat, name: 'Food 2', price: 3),
        );

        final page = await a.store.changesSince(0, until: cut);
        expect([
          for (final c in page) c.table,
        ], isNot(contains('budget_categories')));
        final shipped = await a.store.withDependencies(page);
        expect([
          for (final c in shipped) c.table,
        ], contains('budget_categories'));

        await b.store.apply(shipped, unsyncedAfterSeq: 0);
        final row = await b.rows(
          "SELECT category_id FROM budget_transactions WHERE id = '$tx'",
        );
        expect(row.single['category_id'], cat);
      },
    );

    test(
      'staged pages are merged together, and survive until merged',
      () async {
        final bud = BudgetService(a.db);
        final cat = await bud.saveCategory(
          const CategoryInput(name: 'Food', price: 3),
        );
        final tx = await bud.createTransaction(categoryId: cat);
        final all = await a.store.changesSince(
          0,
          until: await a.store.currentSeq(),
        );
        final byTable = {for (final c in all) c.table: c};
        // The child page first, the parent page later, merged only at the end.
        await b.store.stage('peer', [byTable['budget_transactions']!]);
        expect(await b.count('budget_transactions'), 0);
        await b.store.stage('peer', [byTable['budget_categories']!]);
        final r = await b.store.applyStaged('peer', unsyncedAfterSeq: 0);
        expect(r.applied, 2);
        expect(r.repairs, isEmpty);
        final row = await b.rows(
          "SELECT category_id FROM budget_transactions WHERE id = '$tx'",
        );
        expect(row.single['category_id'], cat);
        expect(await b.count('sync_inbox'), 0);
      },
    );

    test('a deletion that is overridden by a later edit leaves the references consistent', () async {
      final bud = BudgetService(a.db);
      final cat = await bud.saveCategory(
        const CategoryInput(name: 'Food', price: 3),
      );
      final tx = await bud.createTransaction(categoryId: cat);
      await expectConverged();
      await bud.deleteCategory(cat); // also clears the transaction's category
      await tick();
      await BudgetService(
        b.db,
      ).saveCategory(CategoryInput(id: cat, name: 'Food, renamed', price: 3));
      await expectConverged(); // the later edit revives the category everywhere
      expect(await a.count('budget_categories'), 1);
      final row = await a.rows(
        "SELECT category_id FROM budget_transactions WHERE id = '$tx'",
      );
      expect(row.single['category_id'], isNull); // on both devices alike
    });
  });

  group('conflicts', () {
    Future<String> twoDevicesOneAction() async {
      final x = await ActionService(a.db).createAction(name: 'Original');
      await expectConverged();
      return x;
    }

    Future<void> rename(SyncDevice d, String id, String name) =>
        ActionService(d.db).updateAction(
          actionId: id,
          name: name,
          postponeFlex: 'flexible',
          isAllDay: false,
        );

    test('the newest edit wins and the losing one is kept', () async {
      final x = await twoDevicesOneAction();
      await rename(a, x, 'Edit on A');
      await tick();
      await rename(b, x, 'Edit on B');

      final r = await syncWith(a, b);
      expect(r.conflicts, greaterThan(0));
      await expectConverged();
      expect(
        (await a.rows('SELECT name FROM actions')).single['name'],
        'Edit on B',
      );

      final kept = await a.store.conflicts();
      expect(kept, hasLength(1));
      expect(kept.single.table, 'actions');
      expect(kept.single.loserData!['name'], 'Edit on A');
      expect(kept.single.label, 'Edit on A');
      expect(kept.single.seen, isFalse);
      await a.store.markConflictsSeen();
      expect(await a.store.conflicts(unseenOnly: true), isEmpty);
    });

    test(
      'the local edit wins when it is newer, the other side is kept',
      () async {
        final x = await twoDevicesOneAction();
        await rename(b, x, 'Edit on B');
        await tick();
        await rename(a, x, 'Edit on A');

        await syncWith(a, b);
        await expectConverged();
        expect(
          (await b.rows('SELECT name FROM actions')).single['name'],
          'Edit on A',
        );
        final kept = await a.store.conflicts();
        expect(kept.single.loserData!['name'], 'Edit on B');
      },
    );

    test('an edit made after seeing the other one is no conflict', () async {
      final x = await twoDevicesOneAction();
      await rename(a, x, 'First');
      await syncWith(a, b);
      await tick();
      await rename(b, x, 'Second');
      final r = await syncWith(a, b);
      expect(r.conflicts, 0);
      await expectConverged();
      expect(await a.store.conflicts(), isEmpty);
      expect(await b.store.conflicts(), isEmpty);
    });

    test('notes of the losing side stay in the conflict list', () async {
      final x = await twoDevicesOneAction();
      await a.exec("UPDATE actions SET notes = 'notes on A' WHERE id = ?", [x]);
      await tick();
      await b.exec("UPDATE actions SET notes = 'notes on B' WHERE id = ?", [x]);
      await syncWith(a, b);
      await expectConverged();
      final kept = await a.store.conflicts();
      expect(kept.single.loserData!['notes'], 'notes on A');
      expect(
        (await a.rows('SELECT notes FROM actions')).single['notes'],
        'notes on B',
      );
    });
  });

  group('repairs', () {
    test(
      'the same link made on both devices keeps one row, the lower id',
      () async {
        final svc = ActionService(a.db);
        final x = await svc.createAction(name: 'X');
        final y = await svc.createAction(name: 'Y');
        await expectConverged();
        await a.exec(
          'INSERT INTO action_dependencies (id, predecessor_id, successor_id) VALUES (?,?,?)',
          ['dep-a', x, y],
        );
        await b.exec(
          'INSERT INTO action_dependencies (id, predecessor_id, successor_id) VALUES (?,?,?)',
          ['dep-b', x, y],
        );
        await expectConverged();
        for (final d in [a, b]) {
          final ids = await d.rows('SELECT id FROM action_dependencies');
          expect([for (final r in ids) r['id']], ['dep-a']);
          expect(
            await d.count('sync_versions', "row_id = 'dep-b' AND deleted = 1"),
            1,
          );
        }
      },
    );

    test('the same direction link made on both devices keeps one row', () async {
      final x = await ActionService(a.db).createAction(name: 'X');
      final m = await MetricService(a.db)
          .saveMetric(name: 'M', kind: MetricKind.boolean);
      await expectConverged();
      await a.exec(
        'INSERT INTO action_metrics (id, action_id, metric_id) VALUES (?,?,?)',
        ['am-2', x, m],
      );
      await b.exec(
        'INSERT INTO action_metrics (id, action_id, metric_id) VALUES (?,?,?)',
        ['am-1', x, m],
      );
      await expectConverged();
      expect(await a.count('action_metrics'), 1);
      expect(
        (await a.rows('SELECT id FROM action_metrics')).single['id'],
        'am-1',
      );
    });

    test('a link to a direction deleted elsewhere is dropped', () async {
      final x = await ActionService(a.db).createAction(name: 'X');
      final m = await MetricService(a.db)
          .saveMetric(name: 'M', kind: MetricKind.boolean);
      await expectConverged();
      await MetricService(a.db).deleteMetric(m);
      await tick();
      final y = await ActionService(b.db).createAction(name: 'Y');
      await ActionService(b.db).setMetrics(y, [m]);
      await ActionService(b.db).setMetrics(x, [m]);
      final r = await syncWith(a, b);
      expect(r.repairs, greaterThan(0));
      await expectConverged();
      expect(await a.count('action_metrics'), 0);
      expect(await a.count('metrics'), 0);
    });

    test(
      'a reference to a row deleted elsewhere is cleared, not the row',
      () async {
        final bud = BudgetService(a.db);
        final acc = await bud.saveAccount(
          name: 'Cash',
          currency: 'EUR',
          rateToBase: 1,
        );
        final cat = await bud.saveCategory(
          const CategoryInput(name: 'Food', price: 5),
        );
        await expectConverged();
        await bud.deleteAccount(acc);
        await tick();
        final tx = await BudgetService(b.db).createTransaction(categoryId: cat);
        await b.exec(
          'UPDATE budget_transactions SET account_use_id = ? WHERE id = ?',
          [acc, tx],
        );
        await expectConverged();
        expect(await a.count('budget_transactions'), 1);
        expect(
          (await a.rows('SELECT account_use_id FROM budget_transactions'))
              .single['account_use_id'],
          isNull,
        );
      },
    );

    test(
      'action chains that close a loop across devices lose the newest edge',
      () async {
        final svc = ActionService(a.db);
        final x = await svc.createAction(name: 'X');
        final y = await svc.createAction(name: 'Y');
        await expectConverged();
        await DependencyService(a.db)
            .addDependency(predecessorId: x, successorId: y);
        await tick();
        await DependencyService(b.db)
            .addDependency(predecessorId: y, successorId: x);
        final r = await syncWith(a, b);
        expect(r.repairs, greaterThan(0));
        await expectConverged();
        final edges = await a.rows(
          'SELECT predecessor_id AS p FROM action_dependencies',
        );
        expect(edges, hasLength(1));
        expect(edges.single['p'], x); // the older edge stays
      },
    );

    test('growth directions that close a loop across devices lose the newest relation', () async {
      final ms = MetricService(a.db);
      final p = await ms.saveMetric(name: 'P', kind: MetricKind.boolean);
      final q = await ms.saveMetric(name: 'Q', kind: MetricKind.boolean);
      await expectConverged();
      await ms.addRelation(fromId: p, toId: q);
      await tick();
      await MetricService(b.db).addRelation(fromId: q, toId: p);
      await expectConverged();
      expect(await a.count('metric_dependencies'), 1);
      // The weights follow the merged graph on both devices.
      expect(
        (await a.rows('SELECT weight FROM metrics ORDER BY id')),
        equals(await b.rows('SELECT weight FROM metrics ORDER BY id')),
      );
    });

    test(
      'budget parents that close a loop across devices lose the newest',
      () async {
        final bud = BudgetService(a.db);
        final one = await bud.saveCategory(const CategoryInput(name: 'One'));
        final two = await bud.saveCategory(const CategoryInput(name: 'Two'));
        await expectConverged();
        await bud.saveCategory(
          CategoryInput(id: one, name: 'One', parentId: two),
        );
        await tick();
        await BudgetService(b.db)
            .saveCategory(CategoryInput(id: two, name: 'Two', parentId: one));
        await expectConverged();
        final parents = await a.rows(
          'SELECT parent_id FROM budget_categories WHERE parent_id IS NOT NULL',
        );
        expect(parents, hasLength(1));
        expect(parents.single['parent_id'], two); // One under Two (older) stays
      },
    );

    test('a category that got a sub-category and a transaction on different devices', () async {
      final bud = BudgetService(a.db);
      final food = await bud.saveCategory(
        const CategoryInput(name: 'Food', price: 3),
      );
      await expectConverged();
      await BudgetService(b.db)
          .saveCategory(CategoryInput(name: 'Bread', price: 2, parentId: food));
      await tick();
      await bud.createTransaction(categoryId: food);
      final r = await syncWith(a, b);
      expect(r.repairs, greaterThan(0));
      await expectConverged();
      final groups = await a.rows(
        'SELECT c.id FROM budget_categories c WHERE '
        'EXISTS (SELECT 1 FROM budget_categories k WHERE k.parent_id = c.id) '
        'AND EXISTS (SELECT 1 FROM budget_transactions t WHERE t.category_id = c.id)',
      );
      expect(groups, isEmpty);
      // Nothing was deleted: the newest of the two just lost its link.
      expect(await a.count('budget_transactions'), 1);
      expect(await a.count('budget_categories'), 2);
    });
  });
}
