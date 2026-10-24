import '../../data/sync/sync_schema.dart' show syncTables;
import 'sync_models.dart';

// Checks one change received from another device BEFORE it is staged or
// merged. A paired device is trusted with its own data, not with the
// integrity of this one: a malformed or hostile change must not overwrite a
// row it does not name, push the local clock into the future, or make the
// merge throw and stay stuck on the same row forever.
//
// Returns null when the change is fine, else a short reason. Rows of tables
// this version does not know are NOT invalid (a newer device may have them);
// the merge skips them.

/// `2026-10-10T12:00:00.123Z-00ab-<device id>`
final _hlcShape = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z-[0-9a-fA-F]{4,8}-[A-Za-z0-9_.:-]{1,64}$',
);

/// How far ahead of this device's clock a stamp may be. Anything further would
/// win every conflict until real time caught up.
const maxStampFuture = Duration(hours: 24);

/// Longest text value of one field (4 Mi characters: big notes pass, a 5 MB
/// payload does not), and the most columns of one row.
const maxFieldChars = 4 * 1024 * 1024;
const maxChangeColumns = 256;
const double _maxSafeInt = 9007199254740991; // 2^53 - 1

const _maxIdLength = 128;
const _maxOriginLength = 64;
const _maxTableLength = 64;

String? validateChange(SyncChange c, {DateTime? now}) {
  if (c.table.isEmpty || c.table.length > _maxTableLength) return 'table';
  if (c.rowId.isEmpty || c.rowId.length > _maxIdLength || _hasControl(c.rowId)) {
    return 'row id';
  }
  if (c.origin.isEmpty ||
      c.origin.length > _maxOriginLength ||
      _hasControl(c.origin)) {
    return 'origin';
  }
  if (!_hlcShape.hasMatch(c.hlc)) return 'clock stamp';
  final wallText = c.hlc.substring(0, 24);
  final wall = DateTime.tryParse(wallText);
  // Dart rolls an impossible date over (2025-02-29 -> Mar 1, month 13 -> next
  // year): such a stamp is not a real instant, so it must round-trip as typed.
  if (wall == null || wall.toIso8601String() != wallText) return 'clock stamp';
  final limit = (now ?? DateTime.now()).toUtc().add(maxStampFuture);
  if (wall.isAfter(limit)) return 'clock stamp in the future';

  final pk = syncTables[c.table];
  if (pk == null) return null; // an unknown table: skipped by the merge
  if (c.deleted) return null;
  final data = c.data;
  if (data == null) return 'missing data';
  if (data.length > maxChangeColumns) return 'too many columns';
  for (final v in data.values) {
    if (v != null && v is! String && v is! num && v is! bool) return 'value';
    // JSON `1e999` decodes to Infinity; nothing the app stores is that large.
    if (v is num && (!v.isFinite || v.abs() > _maxSafeInt)) return 'value';
    if (v is String && v.length > maxFieldChars) return 'value too long';
  }
  // The row must be the one the change names: otherwise the stamp comparison
  // is made on one row and the write lands on another.
  if (data[pk] != c.rowId) return 'row id differs from its key';
  return null;
}

bool _hasControl(String s) => s.codeUnits.any((u) => u < 0x20 || u == 0x7f);
