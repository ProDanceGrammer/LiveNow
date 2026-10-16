import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/data/sync/sync_schema.dart';
import 'package:livenow/data/sync/sync_store.dart';
import 'package:livenow/domain/metric_service.dart';
import 'package:livenow/domain/sync/sync_engine.dart';
import 'package:livenow/domain/sync/sync_models.dart';

/// One simulated device: its own in-memory database (foreign keys ON, like the
/// real one) with the sync store, host and engine on top.
class SyncDevice {
  SyncDevice() : db = _open() {
    store = SyncStore(
      db,
      afterApply: (tables) async {
        if (tables.contains('metrics') ||
            tables.contains('metric_dependencies')) {
          await MetricService(db).recomputeWeights();
        }
      },
    );
    host = SyncHost(store, kSyncWireVersion);
    engine = SyncEngine(store, kSyncWireVersion, pageSize: 7);
  }

  static AppDatabase _open() => AppDatabase.forTesting(
    NativeDatabase.memory(
      setup: (raw) => raw.execute('PRAGMA foreign_keys = ON;'),
    ),
  );

  final AppDatabase db;
  late final SyncStore store;
  late final SyncHost host;
  late final SyncEngine engine;

  Future<String> get id => store.deviceId();

  Future<void> close() => db.close();

  Future<void> exec(String sql, [List<Object?> args = const []]) =>
      db.customStatement(sql, args);

  Future<List<Map<String, Object?>>> rows(String sql) async => [
    for (final r in await db.customSelect(sql).get()) r.data,
  ];

  Future<int> count(String table, [String where = '1=1']) async =>
      (await rows('SELECT COUNT(*) AS n FROM $table WHERE $where')).single['n']!
          as int;

  /// Every synced table, rows ordered by key: the whole observable state.
  Future<Map<String, List<Map<String, Object?>>>> dump() async => {
    for (final e in syncTables.entries)
      e.key: await rows('SELECT * FROM ${e.key} ORDER BY ${e.value}'),
  };
}

/// Calls another device's host, passing every message through JSON like the
/// network will.
class InProcessTransport implements SyncTransport {
  InProcessTransport(this.server, this.clientId);

  final SyncDevice server;
  final String clientId;

  static T _wire<T>(
    Map<String, Object?> json,
    T Function(Map<String, Object?>) from,
  ) => from((jsonDecode(jsonEncode(json)) as Map).cast<String, Object?>());

  @override
  Future<SyncHello> hello() async =>
      _wire((await server.host.hello()).toJson(), SyncHello.fromJson);

  @override
  Future<SyncPullPage> pull(int sinceSeq, {int limit = 500}) async => _wire(
    (await server.host.pull(clientId, sinceSeq, limit)).toJson(),
    SyncPullPage.fromJson,
  );

  @override
  Future<ApplyResult> push(List<SyncChange> changes, {required bool last}) =>
      server.host.push(clientId, [
        for (final c in changes) _wire(c.toJson(), SyncChange.fromJson),
      ], last: last);
}

/// [client] syncs with [server] (the server is just the peer that serves).
Future<SyncReport> syncWith(SyncDevice client, SyncDevice server) async =>
    client.engine.sync(InProcessTransport(server, await client.id));

/// Keeps the wall clock moving between two scripted edits so "later" is
/// unambiguous even for a coarse timer.
Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 4));

/// A throw-away value for raw inserts.
Variable<String> v(String s) => Variable.withString(s);
