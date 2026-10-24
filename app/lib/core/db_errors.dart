import 'package:sqlite3/sqlite3.dart' show SqliteException;

/// SQLite primary result codes the UI explains in plain words.
const int _busy = 5, _locked = 6, _readonly = 8, _ioerr = 10, _corrupt = 11;
const int _full = 13, _cantOpen = 14, _perm = 3;

/// The [SqliteException] inside [e] (drift may wrap it), or null.
SqliteException? _sqlite(Object? e, [int depth = 0]) {
  if (e is SqliteException) return e;
  if (e == null || depth > 4) return null;
  for (final inner in _inners(e)) {
    final found = _sqlite(inner, depth + 1);
    if (found != null) return found;
  }
  return null;
}

/// What a wrapper (drift's `DriftWrappedException.cause`, the background
/// isolate's `DriftRemoteException.remoteCause`) carries.
Iterable<Object> _inners(Object e) sync* {
  final d = e as dynamic;
  for (final read in <Object? Function()>[() => d.cause, () => d.remoteCause]) {
    try {
      final v = read();
      if (v != null && !identical(v, e)) yield v;
    } on Object {
      // not that kind of wrapper
    }
  }
}

/// When the exception only survived as text (the database runs in a background
/// isolate for the real app file): `SqliteException(13): ...`.
int? _codeFromText(Object e) {
  final m = RegExp(r'SqliteException\((\d+)\)').firstMatch(e.toString());
  final code = m == null ? null : int.tryParse(m.group(1)!);
  return code == null ? null : code & 0xFF;
}

/// A short, friendly sentence for a database failure the user can act on
/// (disk full, database busy / read-only / damaged), or null when [e] is
/// something else (a bug: show its own text and keep the details in the log).
String? friendlyDbError(Object e) {
  final s = _sqlite(e);
  final code = s != null ? s.resultCode : _codeFromText(e);
  if (code == null) return null;
  switch (code) {
    case _full:
      return 'Disk is full. Free some space and try again';
    case _busy:
    case _locked:
      return 'Database is busy. Try again in a moment';
    case _readonly:
    case _perm:
    case _cantOpen:
      return 'The database file cannot be written (read-only or locked)';
    case _ioerr:
      return 'The disk reported an error while saving';
    case _corrupt:
      return 'The database looks damaged. Restore a backup';
  }
  return null;
}
