import 'package:uuid/uuid.dart';

final _uuid = Uuid();

/// Time-ordered UUID (v7), used as the primary key on every table so the
/// schema stays compatible with a future PowerSync/Postgres sync layer.
String newId() => _uuid.v7();
