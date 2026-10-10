import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/sync/sync_schema.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/budget_rules.dart';
import 'package:livenow/domain/budget_service.dart';
import 'package:livenow/domain/dependency_service.dart';
import 'package:livenow/domain/growth_rules.dart';
import 'package:livenow/domain/metric_service.dart';
import 'package:livenow/domain/sync/cycle_repair.dart';

import 'sync_harness.dart';

/// Randomised convergence: three devices (a PC and two phones, star shaped
/// like the real setup) make random edits through the real services, sync at
/// random moments, then sync until quiet. Every device must end up with the
/// same data and valid invariants. A failing run prints its seed: rerun with
/// that seed alone to reproduce the exact operation sequence of the DATA (the
/// clock makes edit ORDER between devices timing-dependent, so the same seed
/// may repair differently, but the invariants must always hold).
void main() {
  const seeds = 25;
  const steps = 100;

  for (var seed = 1; seed <= seeds; seed++) {
    test('three devices converge (seed $seed)', () async {
      final rnd = Random(seed);
      final pc = SyncDevice();
      final phones = [SyncDevice(), SyncDevice()];
      final all = [pc, ...phones];
      for (final d in all) {
        await d.id;
      }
      addTearDown(() async {
        for (final d in all) {
          await d.close();
        }
      });
      final undoDeletes = <SyncDevice, List<DeleteUndo>>{
        for (final d in all) d: [],
      };

      for (var i = 0; i < steps; i++) {
        final d = all[rnd.nextInt(all.length)];
        if (rnd.nextInt(5) == 0) {
          // A sync between a phone and the PC at a random moment.
          await syncWith(phones[rnd.nextInt(2)], pc);
        } else {
          await _randomEdit(d, rnd, undoDeletes[d]!, i);
        }
      }

      // Sync until a whole round moves nothing.
      for (var round = 0; round < 12; round++) {
        var moved = 0;
        for (final p in phones) {
          final r = await syncWith(p, pc);
          moved += r.pulled + r.pushed;
        }
        if (moved == 0) break;
        expect(round, lessThan(11), reason: 'seed $seed never went quiet');
      }

      final want = await pc.dump();
      for (final d in phones) {
        _expectSame(want, await d.dump(), 'seed $seed');
      }
      for (final d in all) {
        await _expectValid(d, 'seed $seed');
      }
    });
  }
}

void _expectSame(
  Map<String, List<Map<String, Object?>>> a,
  Map<String, List<Map<String, Object?>>> b,
  String reason,
) {
  final problems = <String>[];
  for (final t in a.keys) {
    final pk = syncTables[t]!;
    final left = {for (final r in a[t]!) r[pk]: r};
    final right = {for (final r in b[t]!) r[pk]: r};
    for (final id in {...left.keys, ...right.keys}) {
      final l = left[id], r = right[id];
      if (l == null || r == null) {
        problems.add('$t/$id only on ${l == null ? 'second' : 'first'}');
        continue;
      }
      for (final c in l.keys) {
        if (l[c] != r[c]) problems.add('$t/$id.$c: ${l[c]} vs ${r[c]}');
      }
    }
  }
  expect(problems, isEmpty, reason: reason);
}

Future<void> _expectValid(SyncDevice d, String reason) async {
  expect(await d.rows('PRAGMA foreign_key_check'), isEmpty, reason: reason);
  // Every row has a live version and every live version has a row.
  for (final e in syncTables.entries) {
    expect(
      await d.count(
        e.key,
        'NOT EXISTS (SELECT 1 FROM sync_versions v WHERE v.tbl = \'${e.key}\' '
        'AND v.row_id = ${e.key}.${e.value} AND v.deleted = 0)',
      ),
      0,
      reason: '$reason: ${e.key} row without a live version',
    );
    expect(
      (await d.rows(
        'SELECT COUNT(*) AS n FROM sync_versions v WHERE v.tbl = \'${e.key}\' '
        'AND v.deleted = 0 AND NOT EXISTS (SELECT 1 FROM ${e.key} '
        'WHERE ${e.value} = v.row_id)',
      )).single['n'],
      0,
      reason: '$reason: ${e.key} live version without a row',
    );
  }
  Future<void> acyclic(String table, String from, String to) async {
    final rows = await d.rows(
      'SELECT id, $from AS a, $to AS b FROM $table WHERE $to IS NOT NULL',
    );
    final edges = [
      for (final r in rows)
        CycleEdge(r['id']! as String, r['a']! as String, r['b']! as String, ''),
    ];
    expect(
      edgesToBreak(edges),
      isEmpty,
      reason: '$reason: cycle in $table.$to',
    );
  }

  await acyclic('action_dependencies', 'predecessor_id', 'successor_id');
  await acyclic('metric_dependencies', 'depends_on_id', 'metric_id');
  await acyclic('budget_categories', 'id', 'parent_id');
  await acyclic('budget_categories', 'id', 'count_percent_of_id');
  expect(
    await d.rows(
      'SELECT c.id FROM budget_categories c WHERE '
      'EXISTS (SELECT 1 FROM budget_categories k WHERE k.parent_id = c.id) '
      'AND EXISTS (SELECT 1 FROM budget_transactions t '
      'WHERE t.category_id = c.id)',
    ),
    isEmpty,
    reason: '$reason: a group holds transactions',
  );
}

Future<List<String>> _ids(SyncDevice d, String table) async => [
  for (final r in await d.rows('SELECT id FROM $table ORDER BY id'))
    r['id']! as String,
];

T? _pick<T>(Random rnd, List<T> from) =>
    from.isEmpty ? null : from[rnd.nextInt(from.length)];

/// One random user operation on [d]. Failures a user could also hit (a cycle
/// refused, a group that cannot hold a transaction, a row deleted under the
/// feet) are ignored: the service rolled the operation back.
Future<void> _randomEdit(
  SyncDevice d,
  Random rnd,
  List<DeleteUndo> undos,
  int step,
) async {
  final actions = ActionService(d.db);
  final deps = DependencyService(d.db);
  final metrics = MetricService(d.db);
  final budget = BudgetService(d.db);
  final a = await _ids(d, 'actions');
  final m = await _ids(d, 'metrics');
  final cat = await _ids(d, 'budget_categories');
  final acc = await _ids(d, 'budget_accounts');
  final tx = await _ids(d, 'budget_transactions');
  final name = 'n$step-${rnd.nextInt(1000)}';

  try {
    switch (rnd.nextInt(24)) {
      case 0 || 1 || 2:
        await actions.createAction(
          name: name,
          metricIds: [if (m.isNotEmpty && rnd.nextBool()) _pick(rnd, m)!],
        );
      case 3:
        final id = _pick(rnd, a);
        if (id != null) {
          await actions.updateAction(
            actionId: id,
            name: name,
            postponeFlex: 'flexible',
            isAllDay: rnd.nextBool(),
          );
        }
      case 4:
        final id = _pick(rnd, a);
        if (id != null) {
          await actions.updateAction(
            actionId: id,
            name: name,
            postponeFlex: 'flexible',
            isAllDay: false,
            notes: Value(
              '{"document":{"type":"page","children":[{"type":"paragraph",'
              '"data":{"delta":[{"insert":"$name"}]}}]}}',
            ),
          );
        }
      case 5:
        final id = _pick(rnd, a);
        if (id != null) undos.add(await actions.deleteAction(id));
      case 6:
        if (undos.isNotEmpty) {
          await actions.undoDelete(undos.removeLast());
        }
      case 7 || 8:
        final p = _pick(rnd, a), s = _pick(rnd, a);
        if (p != null && s != null) {
          await deps.addDependency(predecessorId: p, successorId: s);
        }
      case 9:
        final p = _pick(rnd, a), s = _pick(rnd, a);
        if (p != null && s != null) {
          await deps.removeDependency(predecessorId: p, successorId: s);
        }
      case 10:
        await metrics.saveMetric(
          name: name,
          kind: rnd.nextBool() ? MetricKind.boolean : MetricKind.count,
          window: MetricWindow.week,
          isMain: rnd.nextInt(4) == 0,
        );
      case 11 || 12:
        final p = _pick(rnd, m), q = _pick(rnd, m);
        if (p != null && q != null) {
          await metrics.addRelation(fromId: p, toId: q);
        }
      case 13:
        final p = _pick(rnd, m), q = _pick(rnd, m);
        if (p != null && q != null) {
          await metrics.removeRelation(fromId: p, toId: q);
        }
      case 14:
        final x = _pick(rnd, a), y = _pick(rnd, m);
        if (x != null && y != null) {
          await metrics.linkAction(x, y);
        }
      case 15:
        final y = _pick(rnd, m);
        if (y != null && rnd.nextBool()) {
          await metrics.deleteMetric(y);
        } else if (y != null) {
          await d.exec('UPDATE metrics SET pos_x = ?, pos_y = 5 WHERE id = ?', [
            rnd.nextInt(100),
            y,
          ]);
        }
      case 16:
        await budget.saveAccount(
          name: name,
          currency: 'EUR',
          rateToBase: 1.0 + rnd.nextInt(5),
        );
      case 17 || 18:
        await budget.saveCategory(
          CategoryInput(
            name: name,
            price: 1.0 + rnd.nextInt(9),
            parentId: rnd.nextBool() ? _pick(rnd, cat) : null,
            accountCountId: rnd.nextBool() ? _pick(rnd, acc) : null,
            unit: rnd.nextInt(5) == 0
                ? BudgetUnit.percentPerMonth
                : BudgetUnit.month,
            percent: 10,
            countPercentOfId: _pick(rnd, cat),
          ),
        );
      case 19:
        final c = _pick(rnd, cat);
        if (c != null) {
          // Re-save with a new parent: the way categories move between groups.
          await budget.saveCategory(
            CategoryInput(
              id: c,
              name: name,
              price: 2,
              parentId: _pick(rnd, cat),
            ),
          );
        }
      case 20 || 21:
        final c = _pick(rnd, cat);
        if (c != null) {
          await budget.createTransaction(categoryId: c, name: name);
        }
      case 22:
        final pick = rnd.nextInt(3);
        if (pick == 0 && cat.isNotEmpty) {
          await budget.deleteCategory(_pick(rnd, cat)!);
        }
        if (pick == 1 && tx.isNotEmpty) {
          await budget.deleteTransaction(_pick(rnd, tx)!);
        }
        if (pick == 2 && acc.isNotEmpty) {
          await budget.deleteAccount(_pick(rnd, acc)!);
        }
      case 23:
        final templates = await _ids(d, 'action_templates');
        final t = _pick(rnd, templates);
        if (t == null || rnd.nextBool()) {
          await d.exec(
            "INSERT INTO action_templates (id, name, payload) VALUES (?, ?, '{}')",
            ['tpl-${rnd.nextInt(1 << 30)}', name],
          );
        } else {
          await d.exec('UPDATE action_templates SET name = ? WHERE id = ?', [
            name,
            t,
          ]);
        }
    }
  } on Exception {
    // Refused by a service rule or constraint: nothing changed.
  } on ArgumentError {
    // Same, for argument checks.
  }
}
