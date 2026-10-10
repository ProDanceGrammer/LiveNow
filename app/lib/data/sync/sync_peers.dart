import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/time_codec.dart';
import '../database.dart';

/// A paired device: the key both share and how to reach it.
class SyncPeer {
  const SyncPeer({
    required this.deviceId,
    required this.name,
    required this.key,
    required this.lastCounter,
    required this.addresses,
    required this.port,
  });

  final String deviceId;
  final String name;
  final Uint8List key;

  /// Last request counter seen from this peer (when it is a client of ours) or
  /// last one used towards it (when it is our server).
  final int lastCounter;
  final List<String> addresses;
  final int? port;
}

/// The `sync_peers` table (created with the other sync tables).
class SyncPeers {
  SyncPeers(this.db);
  final AppDatabase db;

  Future<SyncPeer?> get(String deviceId) async {
    final r = await db
        .customSelect(
          'SELECT * FROM sync_peers WHERE device_id = ?',
          variables: [Variable.withString(deviceId)],
        )
        .getSingleOrNull();
    return r == null ? null : _from(r);
  }

  Future<List<SyncPeer>> all() async => [
    for (final r
        in await db
            .customSelect('SELECT * FROM sync_peers ORDER BY created_at')
            .get())
      _from(r),
  ];

  /// Adds a peer, or replaces its key/addresses and restarts its counter.
  Future<void> save(SyncPeer p) => db.customStatement(
    'INSERT INTO sync_peers (device_id, name, key, last_counter, addresses, '
    'port, created_at) VALUES (?, ?, ?, ?, ?, ?, ?) '
    'ON CONFLICT (device_id) DO UPDATE SET name = excluded.name, '
    'key = excluded.key, last_counter = 0, addresses = excluded.addresses, '
    'port = excluded.port',
    [
      p.deviceId,
      p.name,
      base64.encode(p.key),
      p.lastCounter,
      jsonEncode(p.addresses),
      p.port,
      dateTimeToDb(DateTime.now().toUtc()),
    ],
  );

  Future<void> setCounter(String deviceId, int counter) => db.customStatement(
    'UPDATE sync_peers SET last_counter = ? WHERE device_id = ?',
    [counter, deviceId],
  );

  /// Reorders the addresses (the one that just worked goes first).
  Future<void> setAddresses(String deviceId, List<String> addresses) =>
      db.customStatement(
        'UPDATE sync_peers SET addresses = ? WHERE device_id = ?',
        [jsonEncode(addresses), deviceId],
      );

  Future<void> remove(String deviceId) => db.customStatement(
    'DELETE FROM sync_peers WHERE device_id = ?',
    [deviceId],
  );

  SyncPeer _from(QueryRow r) => SyncPeer(
    deviceId: r.read<String>('device_id'),
    name: r.read<String>('name'),
    key: base64.decode(r.read<String>('key')),
    lastCounter: r.read<int>('last_counter'),
    addresses: (jsonDecode(r.read<String>('addresses')) as List).cast<String>(),
    port: r.readNullable<int>('port'),
  );
}
