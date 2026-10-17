import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/sync/change_validation.dart';
import 'package:livenow/domain/sync/sync_models.dart';

import 'sync_harness.dart';

SyncChange _change({
  String table = 'actions',
  String rowId = 'row1',
  String hlc = '2026-10-10T12:00:00.123Z-0001-devA',
  String origin = 'devA',
  bool deleted = false,
  Map<String, Object?>? data,
}) => SyncChange(
  table: table,
  rowId: rowId,
  hlc: hlc,
  origin: origin,
  deleted: deleted,
  data: deleted ? null : (data ?? {'id': rowId, 'name': 'x'}),
  seq: 1,
);

void main() {
  group('validateChange', () {
    final now = DateTime.utc(2026, 10, 17, 12);

    test('accepts a normal change, a tombstone and an unknown table', () {
      expect(validateChange(_change(), now: now), isNull);
      expect(validateChange(_change(deleted: true), now: now), isNull);
      expect(
        validateChange(_change(table: 'future_table', data: {'x': 1}), now: now),
        isNull,
      );
      // The stamp the seeding migration writes.
      expect(
        validateChange(
          _change(hlc: '1970-01-01T00:00:00.000Z-0000-seed', origin: 'seed'),
          now: now,
        ),
        isNull,
      );
    });

    test('refuses a malformed or far-future clock stamp', () {
      for (final h in [
        '',
        'zzzz',
        '~~~~~~~~~~~~~~~~~~~~~~~~-0000-x',
        '2026-10-10T12:00:00.123Z-00-devA',
        '9999-01-01T00:00:00.000Z-0000-evil',
        '2026-10-19T12:00:00.000Z-0000-evil', // 2 days ahead of `now`
      ]) {
        expect(validateChange(_change(hlc: h), now: now), isNotNull, reason: h);
      }
      // 23 hours ahead is tolerated.
      expect(
        validateChange(
          _change(hlc: '2026-10-18T11:00:00.000Z-0000-devA'),
          now: now,
        ),
        isNull,
      );
    });

    test('refuses odd ids, origins and values', () {
      expect(validateChange(_change(rowId: ''), now: now), isNotNull);
      expect(validateChange(_change(rowId: 'a' * 200), now: now), isNotNull);
      expect(validateChange(_change(rowId: 'a\nb'), now: now), isNotNull);
      expect(validateChange(_change(origin: ''), now: now), isNotNull);
      expect(validateChange(_change(origin: 'o' * 100), now: now), isNotNull);
      expect(
        validateChange(
          _change(data: {'id': 'row1', 'name': <String, Object?>{}}),
          now: now,
        ),
        isNotNull,
      );
    });

    test('refuses data that is not for the row it names', () {
      expect(
        validateChange(_change(data: {'id': 'other', 'name': 'x'}), now: now),
        isNotNull,
      );
      expect(validateChange(_change(data: {'name': 'x'}), now: now), isNotNull);
      // budget_settings is keyed by `key`.
      expect(
        validateChange(
          _change(table: 'budget_settings', rowId: 'k', data: {'key': 'k'}),
          now: now,
        ),
        isNull,
      );
      expect(
        validateChange(
          _change(table: 'budget_settings', rowId: 'k', data: {'key': 'z'}),
          now: now,
        ),
        isNotNull,
      );
    });
  });

  group('in the store', () {
    late SyncDevice a;
    late SyncDevice b;

    setUp(() async {
      a = SyncDevice();
      b = SyncDevice();
      await a.id;
      await b.id;
    });

    tearDown(() async {
      await a.close();
      await b.close();
    });

    Future<SyncChange> realChange(SyncDevice d, String actionId) async {
      final all = await d.store.changesSince(
        0,
        until: await d.store.currentSeq(),
      );
      return all.firstWhere((c) => c.table == 'actions' && c.rowId == actionId);
    }

    test('a change cannot overwrite a row other than the one it names', () async {
      final victim = await ActionService(b.db).createAction(name: 'Victim');
      final x = await ActionService(a.db).createAction(name: 'X');
      final cx = await realChange(a, x);
      final evil = SyncChange(
        table: cx.table,
        rowId: 'zzz-not-the-victim',
        hlc: cx.hlc,
        origin: cx.origin,
        deleted: false,
        data: {...cx.data!, 'id': victim, 'name': 'Hacked'},
        seq: cx.seq,
      );

      await b.store.stage('peer', [evil]);
      await b.store.applyStaged('peer', unsyncedAfterSeq: 0);

      final rows = await b.rows("SELECT name FROM actions WHERE id = '$victim'");
      expect(rows.single['name'], 'Victim');
      expect(await b.count('actions'), 1);
    });

    test('a far-future stamp does not move the local clock', () async {
      final x = await ActionService(a.db).createAction(name: 'X');
      final cx = await realChange(a, x);
      final evil = SyncChange(
        table: cx.table,
        rowId: cx.rowId,
        hlc: '2999-01-01T00:00:00.000Z-0000-evil',
        origin: 'evil',
        deleted: true,
        data: null,
        seq: cx.seq,
      );
      await b.store.stage('peer', [evil]);
      await b.store.applyStaged('peer', unsyncedAfterSeq: 0);

      final mine = await ActionService(b.db).createAction(name: 'Mine');
      final hlc = await b.store.rowHlc('actions', mine);
      expect(hlc, isNot(startsWith('2999')));
    });

    test('a broken row is skipped and the good rows still merge', () async {
      final x = await ActionService(a.db).createAction(name: 'Good');
      final cx = await realChange(a, x);
      // A link row without its two ends: valid-looking, but it cannot merge.
      final broken = SyncChange(
        table: 'action_dependencies',
        rowId: 'link-1',
        hlc: cx.hlc,
        origin: cx.origin,
        deleted: false,
        data: {'id': 'link-1'},
        seq: cx.seq,
      );

      await b.store.stage('peer', [broken, cx]);
      final result = await b.store.applyStaged('peer', unsyncedAfterSeq: 0);

      expect(await b.count('actions'), 1);
      expect(result.repairs.where((r) => r.kind == 'rejected-change'), isNotEmpty);
      // Nothing stays staged, so the next sync is not stuck on the same row.
      expect(await b.count('sync_inbox'), 0);
    });

    test('forgetting a peer drops its staged rows and cursors', () async {
      final x = await ActionService(a.db).createAction(name: 'X');
      await b.store.stage('peer', [await realChange(a, x)]);
      await b.store.setState('pulled:peer', '5');
      expect(await b.count('sync_inbox'), 1);

      await b.store.forgetPeer('peer');

      expect(await b.count('sync_inbox'), 0);
      expect(await b.store.getState('pulled:peer'), isNull);
    });
  });
}
