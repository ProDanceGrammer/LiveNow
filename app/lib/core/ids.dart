import 'package:uuid/uuid.dart';

final _uuid = Uuid();

/// Time-ordered UUID (v7), used as the primary key on every table so the
/// schema stays compatible with a future PowerSync/Postgres sync layer.
String newId() => _uuid.v7();

/// Deterministic UUIDv5 over `namespaceId|role|index` (namespaceId = the AI
/// job id). Re-running a job derives the SAME ids, so writes are idempotent.
String deriveId(String namespaceId, String role, [int index = 0]) =>
    _uuid.v5(Namespace.url.value, '$namespaceId|$role|$index');
