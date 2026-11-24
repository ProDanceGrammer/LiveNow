import '../../search_match.dart' show foldSearch;

/// A date range the user's message asks for: [from] inclusive, [to] exclusive;
/// either end may be open.
class StatementPeriod {
  const StatementPeriod({this.from, this.to});
  final DateTime? from;
  final DateTime? to;

  bool contains(DateTime t) =>
      (from == null || !t.isBefore(from!)) && (to == null || t.isBefore(to!));

  @override
  String toString() => 'StatementPeriod($from .. $to)';
}

RegExp _re(String p) => RegExp(p, unicode: true);

final _months = <RegExp>[
  _re(r'(?<!\p{L})(?:січ\p{L}*|январ\p{L}*|jan(?:uary)?)(?!\p{L})'),
  _re(r'(?<!\p{L})(?:лют\p{L}*|феврал\p{L}*|feb(?:ruary)?)(?!\p{L})'),
  _re(r'(?<!\p{L})(?:берез\p{L}*|март\p{L}*|mar(?:ch)?)(?!\p{L})'),
  _re(r'(?<!\p{L})(?:квіт\p{L}*|апрел\p{L}*|apr(?:il)?)(?!\p{L})'),
  _re(r'(?<!\p{L})(?:трав\p{L}*|ма[йяе]|may)(?!\p{L})'),
  _re(r'(?<!\p{L})(?:черв\p{L}*|июн\p{L}*|jun(?:e)?)(?!\p{L})'),
  _re(r'(?<!\p{L})(?:лип\p{L}*|июл\p{L}*|jul(?:y)?)(?!\p{L})'),
  _re(r'(?<!\p{L})(?:серп\p{L}*|август\p{L}*|aug(?:ust)?)(?!\p{L})'),
  _re(r'(?<!\p{L})(?:верес\p{L}*|сентябр\p{L}*|sep(?:t|tember)?)(?!\p{L})'),
  _re(r'(?<!\p{L})(?:жовт\p{L}*|октябр\p{L}*|oct(?:ober)?)(?!\p{L})'),
  _re(r'(?<!\p{L})(?:листопад\p{L}*|ноябр\p{L}*|nov(?:ember)?)(?!\p{L})'),
  _re(r'(?<!\p{L})(?:груд\p{L}*|декабр\p{L}*|dec(?:ember)?)(?!\p{L})'),
];

final _date = RegExp(r'(?<![\d.])(\d{1,2})[./](\d{1,2})(?:[./](\d{4}|\d{2}))?(?![\d])');
final _fromWord = _re(r'(?<!\p{L})(?:з|із|від|с|from|since|starting)\s*$');
final _afterWord = _re(r'(?<!\p{L})(?:після|после|after)\s*$');
final _toWord = _re(r'(?<!\p{L})(?:до|по|to|until|till|through)\s*$');
final _beforeWord = _re(r'(?<!\p{L})(?:перед|раніше|before)\s*$');

/// "за листопад", "з 15.11", "від 01.11 до 15.11", "after 01.11", "November"
/// -> the range; null when the message names none. A date without a year is the
/// latest one not after [now].
StatementPeriod? periodFromMessage(String? text, DateTime now) {
  if (text == null || text.trim().isEmpty) return null;
  final t = foldSearch(text);

  final found = <(DateTime, String)>[];
  for (final m in _date.allMatches(t)) {
    final day = int.parse(m.group(1)!);
    final month = int.parse(m.group(2)!);
    if (month < 1 || month > 12 || day < 1 || day > 31) continue;
    var year = int.tryParse(m.group(3) ?? '');
    if (year != null && year < 100) year += 2000;
    var d = DateTime(year ?? now.year, month, day);
    if (d.month != month) continue;
    if (year == null && d.isAfter(now)) d = DateTime(now.year - 1, month, day);
    found.add((d, t.substring(0, m.start)));
  }
  if (found.isNotEmpty) return _fromDates(found);

  for (var i = 0; i < _months.length; i++) {
    if (!_months[i].hasMatch(t)) continue;
    final ym = RegExp(r'(?<!\d)(20\d\d)(?!\d)').firstMatch(t);
    var year = ym != null ? int.parse(ym.group(1)!) : now.year;
    if (ym == null && i + 1 > now.month) year -= 1;
    return StatementPeriod(from: DateTime(year, i + 1, 1), to: DateTime(year, i + 2, 1));
  }
  return null;
}

StatementPeriod? _fromDates(List<(DateTime, String)> found) {
  DateTime? from;
  DateTime? to;
  for (final (d, before) in found) {
    if (_afterWord.hasMatch(before)) {
      from = d.add(const Duration(days: 1));
    } else if (_fromWord.hasMatch(before)) {
      from = d;
    } else if (_beforeWord.hasMatch(before)) {
      to = d;
    } else if (_toWord.hasMatch(before)) {
      to = DateTime(d.year, d.month, d.day + 1);
    } else if (found.length >= 2 && from == null && d == found.first.$1) {
      from = d;
    } else if (found.length >= 2 && d == found.last.$1) {
      to = DateTime(d.year, d.month, d.day + 1);
    }
  }
  if (from == null && to == null) return null;
  if (from != null && to != null && !from.isBefore(to)) {
    from = DateTime(from.year - 1, from.month, from.day);
  }
  return StatementPeriod(from: from, to: to);
}
