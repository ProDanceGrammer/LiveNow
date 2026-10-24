import 'dart:convert';

import '../core/text_rules.dart';

/// The full-backup file formats (compact `.livenow`, CSV folder, SQLite copy),
/// pure helpers shared by the writer, the readers and the import.

const String kBackupFormat = 'livenow-full';
const int kBackupVersion = 1;
const String kBackupExtension = 'livenow';

/// Rows per batch: big enough to be fast, small enough to keep memory flat.
const int kBackupBatchRows = 500;

/// User-data tables in the order they are inserted (parents first). The sync
/// bookkeeping tables are NOT here: they are device-local (`sync_peers` holds
/// the pairing keys). A test asserts this covers `syncTables`.
const List<String> backupTableOrder = [
  'countable_activities',
  'plan_collections',
  'plan_items',
  'actions',
  'metrics',
  'budget_accounts',
  'budget_categories',
  'budget_tx_templates',
  'budget_transactions',
  'action_dependencies',
  'action_occurrences',
  'action_metrics',
  'metric_dependencies',
  'action_templates',
  'budget_settings',
  'saved_views',
  'forms',
  'plan_overrides',
];

/// A batch of rows of one table. [columns] name the values of every row.
class TableChunk {
  const TableChunk(this.table, this.columns, this.rows);

  final String table;
  final List<String> columns;
  final List<List<Object?>> rows;
}

/// What the file says about itself. A CSV folder without `_meta.csv` has no
/// [schemaVersion] (null = assume it fits).
class BackupHeader {
  const BackupHeader({this.schemaVersion, this.exportedAt});

  final int? schemaVersion;
  final String? exportedAt;
}

/// A file that is not a (complete, readable, compatible) LiveNow backup.
class BackupFormatException implements Exception {
  const BackupFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

// ---- compact format: line-delimited JSON ---------------------------------

String encodeHeaderLine(int schemaVersion, DateTime exportedAt) => jsonEncode({
  'format': kBackupFormat,
  'version': kBackupVersion,
  'schemaVersion': schemaVersion,
  'exportedAt': exportedAt.toUtc().toIso8601String(),
});

String encodeTableLine(String table, List<String> columns) =>
    jsonEncode({'t': table, 'c': columns});

String encodeEndLine(int rows) => jsonEncode({'end': true, 'rows': rows});

BackupHeader parseHeaderLine(String line) {
  final Object? j;
  try {
    j = jsonDecode(line);
  } catch (_) {
    throw const BackupFormatException('This is not a LiveNow backup file.');
  }
  if (j is! Map || j['format'] != kBackupFormat) {
    throw const BackupFormatException('This is not a LiveNow backup file.');
  }
  final v = j['version'];
  if (v is! int || v > kBackupVersion) {
    throw const BackupFormatException(
      'This backup was made by a newer version of LiveNow. Update the app first.',
    );
  }
  final schema = j['schemaVersion'];
  if (schema is! int) {
    throw const BackupFormatException('The backup has no schema version.');
  }
  return BackupHeader(
    schemaVersion: schema,
    exportedAt: j['exportedAt'] as String?,
  );
}

// ---- CSV format ------------------------------------------------------------

/// One CSV cell: NULL = empty, an empty string = `""`, quotes only when needed
/// (RFC 4180), so NULL and '' survive a round trip.
String csvCell(Object? v) {
  if (v == null) return '';
  // Text a spreadsheet would run as a formula gets a leading apostrophe on
  // export (numbers are never touched); CsvFolderBackupSource strips it again.
  final s = v is String ? guardCsvCell(v) : v.toString();
  if (s.isEmpty) return '""';
  if (s.contains(RegExp(r'[",\r\n]')) || s != s.trim()) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

String csvLine(Iterable<Object?> cells) => cells.map(csvCell).join(',');

/// Incremental CSV reader: feed text chunks, get the rows completed so far.
/// An unquoted empty cell is `null`, a quoted empty one `''`.
class CsvRowParser {
  final _row = <String?>[];
  final _cell = StringBuffer();
  bool _inQuotes = false;
  bool _wasQuoted = false;
  bool _pendingQuote = false; // saw a `"` inside quotes: closing or escaped
  bool _cellStarted = false;

  List<List<String?>> add(String chunk) {
    final out = <List<String?>>[];
    for (var i = 0; i < chunk.length; i++) {
      final c = chunk[i];
      if (_pendingQuote) {
        _pendingQuote = false;
        if (c == '"') {
          _cell.write('"'); // escaped quote
          continue;
        }
        _inQuotes = false; // it closed the quoted cell; fall through
      }
      if (_inQuotes) {
        if (c == '"') {
          _pendingQuote = true;
        } else {
          _cell.write(c);
        }
        continue;
      }
      switch (c) {
        case '"':
          if (!_cellStarted) {
            _inQuotes = true;
            _wasQuoted = true;
            _cellStarted = true;
          } else {
            _cell.write(c); // a stray quote inside an unquoted cell
          }
        case ',':
          _endCell();
        case '\r':
          break;
        case '\n':
          _endCell();
          out.add(List.of(_row));
          _row.clear();
        default:
          _cellStarted = true;
          _cell.write(c);
      }
    }
    return out;
  }

  /// The last row when the text did not end with a newline.
  List<List<String?>> close() {
    if (_pendingQuote) {
      _pendingQuote = false;
      _inQuotes = false;
    }
    if (_cellStarted || _row.isNotEmpty) {
      _endCell();
      final out = [List<String?>.of(_row)];
      _row.clear();
      return out;
    }
    return const [];
  }

  void _endCell() {
    final text = _cell.toString();
    _row.add(text.isEmpty && !_wasQuoted ? null : text);
    _cell.clear();
    _wasQuoted = false;
    _cellStarted = false;
  }
}
