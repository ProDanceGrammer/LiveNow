/// One row version travelling between devices: the row's synced columns (null
/// for a deletion) and the clock stamp it was written with. [seq] is the
/// sender's log position, used only as a paging cursor.
class SyncChange {
  const SyncChange({
    required this.table,
    required this.rowId,
    required this.hlc,
    required this.origin,
    required this.deleted,
    this.data,
    this.seq = 0,
  });

  final String table;
  final String rowId;
  final String hlc;
  final String origin;
  final bool deleted;
  final Map<String, Object?>? data;
  final int seq;

  Map<String, Object?> toJson() => {
    't': table,
    'id': rowId,
    'hlc': hlc,
    'o': origin,
    'd': deleted,
    'v': data,
    's': seq,
  };

  factory SyncChange.fromJson(Map<String, Object?> j) => SyncChange(
    table: j['t']! as String,
    rowId: j['id']! as String,
    hlc: j['hlc']! as String,
    origin: j['o']! as String,
    deleted: j['d']! as bool,
    data: (j['v'] as Map?)?.cast<String, Object?>(),
    seq: (j['s'] as int?) ?? 0,
  );
}

/// What a device says about itself before a sync.
class SyncHello {
  const SyncHello({
    required this.deviceId,
    required this.schemaVersion,
    required this.seq,
  });
  final String deviceId;
  final int schemaVersion;
  final int seq;

  Map<String, Object?> toJson() => {
    'device': deviceId,
    'schema': schemaVersion,
    'seq': seq,
  };

  factory SyncHello.fromJson(Map<String, Object?> j) => SyncHello(
    deviceId: j['device']! as String,
    schemaVersion: j['schema']! as int,
    seq: j['seq']! as int,
  );
}

/// One page of a pull. [nextSeq] is the cursor to continue from (the last
/// change's position, or the snapshot position once [done]).
class SyncPullPage {
  const SyncPullPage(this.changes, {required this.nextSeq, required this.done});
  final List<SyncChange> changes;
  final int nextSeq;
  final bool done;

  Map<String, Object?> toJson() => {
    'changes': [for (final c in changes) c.toJson()],
    'next': nextSeq,
    'done': done,
  };

  factory SyncPullPage.fromJson(Map<String, Object?> j) => SyncPullPage(
    [
      for (final c in (j['changes']! as List))
        SyncChange.fromJson((c as Map).cast<String, Object?>()),
    ],
    nextSeq: j['next']! as int,
    done: j['done']! as bool,
  );
}

/// A change the merge had to fix up so the data stays valid (a dropped link,
/// a cleared reference, a cycle broken ...). Reported, never silent.
class SyncRepair {
  const SyncRepair(this.kind, this.table, this.rowId);
  final String kind;
  final String table;
  final String rowId;

  @override
  String toString() => '$kind $table/$rowId';
}

/// The outcome of applying a batch of remote changes.
class ApplyResult {
  const ApplyResult({
    this.applied = 0,
    this.conflicts = 0,
    this.repairs = const [],
  });
  final int applied;
  final int conflicts;
  final List<SyncRepair> repairs;

  Map<String, Object?> toJson() => {
    'applied': applied,
    'conflicts': conflicts,
    'repairs': repairs.length,
  };
}

/// An edit that lost a merge against a concurrent edit of the same row.
class SyncConflict {
  const SyncConflict({
    required this.id,
    required this.table,
    required this.rowId,
    required this.label,
    required this.detectedAt,
    required this.loserHlc,
    required this.loserOrigin,
    required this.winnerHlc,
    required this.loserData,
    required this.seen,
  });
  final int id;
  final String table;
  final String rowId;
  final String? label;
  final String detectedAt;
  final String loserHlc;
  final String loserOrigin;
  final String winnerHlc;

  /// The losing version's columns (null when the loser was a deletion).
  final Map<String, Object?>? loserData;
  final bool seen;
}

/// Summary of one whole sync with a peer.
class SyncReport {
  const SyncReport({
    this.pulled = 0,
    this.pushed = 0,
    this.conflicts = 0,
    this.repairs = 0,
  });
  final int pulled;
  final int pushed;
  final int conflicts;
  final int repairs;
}

/// The peers run different database schema versions: update the older one.
class SyncVersionMismatch implements Exception {
  const SyncVersionMismatch(this.local, this.remote);
  final int local;
  final int remote;
  @override
  String toString() =>
      'Sync refused: this device has database version $local, the other has '
      '$remote. Update the app on the older one.';
}
