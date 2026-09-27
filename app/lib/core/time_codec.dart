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
  final utc = value.toUtc();
  String pad(int n, int width) => n.toString().padLeft(width, '0');
  final micros = utc.millisecond * 1000 + utc.microsecond;
  return '${pad(utc.year, 4)}-${pad(utc.month, 2)}-${pad(utc.day, 2)}'
      'T${pad(utc.hour, 2)}:${pad(utc.minute, 2)}:${pad(utc.second, 2)}'
      '.${pad(micros, 6)}Z';
}

DateTime? dateTimeFromDb(String? value) =>
    value == null ? null : DateTime.parse(value).toUtc();
