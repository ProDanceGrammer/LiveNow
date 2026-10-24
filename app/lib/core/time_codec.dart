import 'dart:async';

import 'error_log.dart';

/// Converts between the app's [DateTime] values and the UTC ISO-8601 text
/// stored in the database (chosen over Drift's native int-based DateTime
/// column so the on-disk format matches a future Postgres/PowerSync target).
///
/// Always writes a fixed-width `yyyy-MM-ddTHH:mm:ss.ffffffZ` (unlike
/// [DateTime.toIso8601String], which omits the microsecond digits when
/// they're zero) so plain text comparison in SQL (`ORDER BY`, range filters
/// in view queries) agrees with chronological order.
String? dateTimeToDb(DateTime? value) {
  if (value == null) return null;
  var utc = value.toUtc();
  // Four year digits keep the text fixed-width (and so sortable): a year the
  // format cannot hold is clamped to its edge rather than written broken.
  if (utc.year > 9999) {
    utc = DateTime.utc(9999, 12, 31, 23, 59, 59, 999, 999);
  } else if (utc.year < 0) {
    utc = DateTime.utc(0);
  }
  String pad(int n, int width) => n.toString().padLeft(width, '0');
  final micros = utc.millisecond * 1000 + utc.microsecond;
  return '${pad(utc.year, 4)}-${pad(utc.month, 2)}-${pad(utc.day, 2)}'
      'T${pad(utc.hour, 2)}:${pad(utc.minute, 2)}:${pad(utc.second, 2)}'
      '.${pad(micros, 6)}Z';
}

/// null for null AND for text that is not a timestamp (a damaged row): the
/// first time each bad text is seen it goes to the error log, so one bad cell
/// cannot make a whole list throw.
DateTime? dateTimeFromDb(String? value) {
  if (value == null) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed != null) return parsed.toUtc();
  if (_loggedBad.length < 50 && _loggedBad.add(value)) {
    unawaited(
      ErrorLog.write(
        FormatException('Not a timestamp', value),
        null,
        context: 'read',
      ),
    );
  }
  return null;
}

final Set<String> _loggedBad = {};
