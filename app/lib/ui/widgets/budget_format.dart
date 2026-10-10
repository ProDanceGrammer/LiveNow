import 'package:timezone/timezone.dart' as tz;

import '../../core/settings.dart';

/// Money with two decimals and a real minus sign; `sign` adds '+' to positives.
String budgetMoney(double v, {bool sign = false}) {
  final s = v.abs().toStringAsFixed(2);
  if (v < 0 && s != '0.00') return '−$s';
  return sign && v > 0 ? '+$s' : s;
}

/// A quantity/rate without trailing zeros (2 -> '2', 0.5 -> '0.5'); tiny
/// values (a BTC rate) keep enough digits to stay non-zero.
String budgetNumber(double v) {
  final digits = v != 0 && v.abs() < 0.01 ? 10 : 4;
  final s = v.toStringAsFixed(digits);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

/// Parses a typed number (comma or dot); null for empty/garbage.
double? parseBudgetNumber(String text) =>
    double.tryParse(text.trim().replaceAll(',', '.'));

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

tz.TZDateTime _local(DateTime utc) =>
    tz.TZDateTime.from(utc, tz.getLocation(AppSettings.timeZoneName));

/// `3 Nov` (this year) or `3 Nov 27` (another year), in the app's time zone.
String budgetDate(DateTime utc, {DateTime? now}) {
  final l = _local(utc);
  final year = _local(now ?? DateTime.now().toUtc()).year;
  final suffix = l.year == year
      ? ''
      : " '${(l.year % 100).toString().padLeft(2, '0')}";
  return '${l.day} ${_months[l.month - 1]}$suffix';
}

/// Local noon of the calendar day of [picked] (a date-picker result), as UTC:
/// a date-only transaction must not drift to the previous day.
DateTime budgetNoonUtc(DateTime picked) => tz.TZDateTime(
  tz.getLocation(AppSettings.timeZoneName),
  picked.year,
  picked.month,
  picked.day,
  12,
).toUtc();

/// The calendar day of [utc] in the app's time zone, as a plain local date for
/// a date picker's initial value.
DateTime budgetLocalDay(DateTime utc) {
  final l = _local(utc);
  return DateTime(l.year, l.month, l.day);
}
