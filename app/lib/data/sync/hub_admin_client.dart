import '../../domain/sync/sync_models.dart';
import '../../domain/sync/sync_protocol.dart';
import 'hub_admin.dart';
import 'http_transport.dart';
import 'sync_server.dart';

/// A device the hub knows (a phone, or the desktop window itself).
class HubPeerInfo {
  const HubPeerInfo({
    required this.deviceId,
    required this.name,
    required this.admin,
  });
  final String deviceId;
  final String name;
  final bool admin;
}

/// The desktop window's side of [HubAdmin]: encrypted calls to the hub's
/// local admin routes (pair a phone, answer "Pair this phone?", list / remove
/// devices, read / restore conflicts) over an ordinary [HttpTransport].
class HubAdminClient {
  HubAdminClient(this._t);
  final HttpTransport _t;

  Future<Map<String, Object?>> _call(
    String route, [
    Map<String, Object?> body = const {},
  ]) => _t.call('$adminPrefix$route', body);

  Future<Map<String, Object?>> status() => _call('status');

  /// Opens a pairing window on the hub; returns the code and how long it lasts.
  Future<({PairingUri code, int seconds})> startPairing() async {
    final r = await _call('pairing/start');
    return (
      code: PairingUri.parse(r['uri']! as String),
      seconds: r['seconds']! as int,
    );
  }

  Future<void> cancelPairing() => _call('pairing/cancel');

  /// The phone waiting for the owner's yes or no, if any.
  Future<PairRequest?> pending() async {
    final p = (await _call('pending'))['pending'] as Map?;
    return p == null
        ? null
        : PairRequest(
            deviceId: p['deviceId']! as String,
            name: p['name']! as String,
          );
  }

  Future<void> answer(bool approved) => _call('answer', {'approved': approved});

  Future<List<HubPeerInfo>> peers() async => [
    for (final p in ((await _call('peers'))['peers']! as List).cast<Map>())
      HubPeerInfo(
        deviceId: p['deviceId']! as String,
        name: p['name']! as String,
        admin: p['admin'] == true,
      ),
  ];

  Future<void> removePeer(String deviceId) =>
      _call('peers/remove', {'deviceId': deviceId});

  Future<List<SyncConflict>> conflicts() async => [
    for (final c
        in ((await _call('conflicts'))['conflicts']! as List)
            .cast<Map<dynamic, dynamic>>())
      conflictFromJson(c.cast<String, Object?>()),
  ];

  Future<bool> restoreConflict(int id) async =>
      (await _call('conflicts/restore', {'id': id}))['restored'] == true;

  Future<void> markConflictsSeen() => _call('conflicts/seen');

  /// The hub's AI settings: every key, but the token only as `llm_token_set`.
  Future<Map<String, Object?>> fetchAiSettings() => _call('ai-settings');

  /// Saves the given AI settings (a bad value changes nothing and throws) and
  /// returns the settings as they are now. An empty `llm_token` clears it.
  Future<Map<String, Object?>> saveAiSettings(Map<String, Object?> values) =>
      _call('ai-settings', {'values': values});

  /// Reachability of the model server and the OCR service, the job queue per
  /// state, the model names and the last job error.
  Future<Map<String, Object?>> fetchAiStatus() => _call('ai-status');
}
