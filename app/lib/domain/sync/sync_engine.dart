import '../../data/sync/sync_store.dart';
import 'sync_models.dart';

/// What a device can ask of the one it syncs with. The HTTP client implements
/// it over the network; tests call a [SyncHost] directly.
abstract class SyncTransport {
  Future<SyncHello> hello();

  /// Changes the other device logged after [sinceSeq] (its own log position).
  Future<SyncPullPage> pull(int sinceSeq, {int limit = 500});

  /// Sends one page of changes; [last] marks the final page, after which the
  /// other side merges everything it received.
  Future<ApplyResult> push(List<SyncChange> changes, {required bool last});
}

/// The serving side of a sync: answers a peer's pull and applies its push.
/// [peerId] is the device id the peer announced in `hello`.
class SyncHost {
  SyncHost(this.store, this.schemaVersion);

  final SyncStore store;
  final int schemaVersion;

  Future<SyncHello> hello() async => SyncHello(
    deviceId: await store.deviceId(),
    schemaVersion: schemaVersion,
    seq: await store.currentSeq(),
  );

  Future<SyncPullPage> pull(String peerId, int sinceSeq, int limit) async {
    // A peer asking "after N" confirms it holds everything up to N: later,
    // anything of ours stamped after N that it did not see is an unsynced edit.
    await store.setState('served:$peerId', '$sinceSeq');
    final until = await store.currentSeq();
    final changes = await store.changesSince(
      sinceSeq,
      until: until,
      limit: limit,
      excludeOrigin: peerId,
    );
    final more = changes.length >= limit;
    return SyncPullPage(
      await store.withDependencies(changes),
      nextSeq: more ? changes.last.seq : until,
      done: !more,
    );
  }

  /// Pages are only staged; the last one merges them all in one transaction
  /// (a row may arrive a page before the row it refers to).
  Future<ApplyResult> push(
    String peerId,
    List<SyncChange> changes, {
    required bool last,
  }) async {
    await store.stage(peerId, changes);
    if (!last) return const ApplyResult();
    final served = int.tryParse(await store.getState('served:$peerId') ?? '');
    return store.applyStaged(peerId, unsyncedAfterSeq: served ?? 0);
  }
}

/// The client side of a sync: pull what the peer has, push what it lacks, and
/// repeat while a round still moved something (a merge repair on one side
/// produces changes for the other). Cursors per peer live in `sync_state`:
/// `pulled:<peer>` = the peer's log position we hold, `pushed:<peer>` = our log
/// position the peer holds.
class SyncEngine {
  SyncEngine(this.store, this.schemaVersion, {this.pageSize = 500});

  final SyncStore store;
  final int schemaVersion;
  final int pageSize;

  Future<SyncReport> sync(SyncTransport peer, {int maxRounds = 4}) async {
    final hello = await peer.hello();
    if (hello.schemaVersion != schemaVersion) {
      throw SyncVersionMismatch(schemaVersion, hello.schemaVersion);
    }
    final peerId = hello.deviceId;
    var pulled = 0, pushed = 0, conflicts = 0, repairs = 0;
    for (var round = 0; round < maxRounds; round++) {
      final p = await _pull(peer, peerId);
      final q = await _push(peer, peerId);
      pulled += p.changes;
      pushed += q.changes;
      conflicts += p.result.conflicts + q.result.conflicts;
      repairs += p.result.repairs.length + q.result.repairs.length;
      if (p.changes == 0 && q.changes == 0) break;
    }
    return SyncReport(
      pulled: pulled,
      pushed: pushed,
      conflicts: conflicts,
      repairs: repairs,
    );
  }

  Future<({int changes, ApplyResult result})> _pull(
    SyncTransport peer,
    String peerId,
  ) async {
    var cursor = await _cursor('pulled:$peerId');
    final pushedSeq = await _cursor('pushed:$peerId');
    // Pages are staged as they arrive (the cursor follows) and merged once at
    // the end, in one transaction: a row can come before the row it refers to.
    while (true) {
      final page = await peer.pull(cursor, limit: pageSize);
      await store.stage(peerId, page.changes);
      cursor = page.nextSeq;
      await store.setState('pulled:$peerId', '$cursor');
      if (page.done) break;
    }
    final r = await store.applyStaged(peerId, unsyncedAfterSeq: pushedSeq);
    return (changes: r.applied, result: r);
  }

  Future<({int changes, ApplyResult result})> _push(
    SyncTransport peer,
    String peerId,
  ) async {
    var cursor = await _cursor('pushed:$peerId');
    // Everything logged up to here is covered by this push, even rows skipped
    // because they came from the peer; later edits wait for the next round.
    final until = await store.currentSeq();
    var count = 0, conflicts = 0;
    final repairs = <SyncRepair>[];
    while (true) {
      // One extra row tells whether this is the last page.
      final fetched = await store.changesSince(
        cursor,
        until: until,
        limit: pageSize + 1,
        excludeOrigin: peerId,
      );
      final more = fetched.length > pageSize;
      final batch = more ? fetched.sublist(0, pageSize) : fetched;
      if (batch.isNotEmpty) {
        final r = await peer.push(
          await store.withDependencies(batch),
          last: !more,
        );
        count += batch.length;
        conflicts += r.conflicts;
        repairs.addAll(r.repairs);
      }
      cursor = more ? batch.last.seq : until;
      await store.setState('pushed:$peerId', '$cursor');
      if (!more) break;
    }
    return (
      changes: count,
      result: ApplyResult(
        applied: count,
        conflicts: conflicts,
        repairs: repairs,
      ),
    );
  }

  Future<int> _cursor(String key) async =>
      int.tryParse(await store.getState(key) ?? '') ?? 0;
}
