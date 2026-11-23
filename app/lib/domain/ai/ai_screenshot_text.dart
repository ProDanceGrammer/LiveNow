import 'ai_transfer_text.dart' show parseAmountText;

/// What a bank screenshot says about one card payment: the amount charged in
/// the account currency (`useAmount`, e.g. UAH), the shop amount in the
/// receipt currency (`countAmount`, e.g. TRY) and/or the bank's rate
/// (use units per 1 count unit; spec A4 "курс r").
class ScreenshotReading {
  const ScreenshotReading({
    this.useAmount,
    this.countAmount,
    this.rate,
    this.merchant,
    this.date,
    this.dayGuessed = false,
    this.bankScreen = false,
    this.incoming = false,
    this.uahOnly = false,
    this.bankCategory,
  });

  final double? useAmount;
  final double? countAmount;
  final double? rate;

  /// Where the card paid: the nearest text line above the amount.
  final String? merchant;

  /// When it was paid (wall clock as the bank shows it), when readable.
  final DateTime? date;

  /// OCR read the month and time but lost the day: [date]'s day is the latest
  /// fitting one, and the draft asks the user to check it.
  final bool dayGuessed;

  /// A detail screen of the bank app (balance and tags lines): its main amount
  /// is the one above the balance, whatever symbol OCR made of the "₴".
  final bool bankScreen;

  /// The main amount has no minus: money came in (a top-up, a card-to-card in).
  final bool incoming;

  /// A bank screen with neither a lira amount nor a rate: only hryvnia, so it is
  /// no paper receipt's rate info (a transfer, a top-up, a domestic purchase).
  final bool uahOnly;

  /// The bank's own category chip under the merchant ("Кафе та ресторани"), read from
  /// the Ukrainian text. A hint for the category when the message says nothing about
  /// this screenshot; never set for a card-to-card transfer or a top-up.
  final String? bankCategory;

  bool get hasAnything =>
      rate != null || (useAmount != null && countAmount != null) || (bankScreen && useAmount != null);

  /// The shop amount; from the charged amount and the rate when only those show.
  double? get shopAmount {
    final c = countAmount;
    if (c != null) return c;
    final u = useAmount;
    if (uahOnly) return u;
    final r = rate;
    if (u == null || r == null || r <= 0) return null;
    return (u / r * 100).roundToDouble() / 100;
  }

  Map<String, dynamic> toJson() => {
    'rate': rate,
    'use': useAmount,
    'count': countAmount,
    if (merchant != null) 'merchant': merchant,
    if (date != null) 'date': _isoLocal(date!),
    if (date != null && dayGuessed) 'day_guessed': true,
    if (bankScreen) 'bank_screen': true,
    if (incoming) 'incoming': true,
    if (uahOnly) 'uah_only': true,
    if (bankCategory != null) 'bank_category': bankCategory,
  };

  factory ScreenshotReading.fromJson(Map<String, dynamic> j) => ScreenshotReading(
    rate: (j['rate'] as num?)?.toDouble(),
    useAmount: (j['use'] as num?)?.toDouble(),
    countAmount: (j['count'] as num?)?.toDouble(),
    merchant: j['merchant'] is String ? j['merchant'] as String : null,
    date: j['date'] is String ? DateTime.tryParse(j['date'] as String) : null,
    dayGuessed: j['day_guessed'] == true,
    bankScreen: j['bank_screen'] == true,
    incoming: j['incoming'] == true,
    uahOnly: j['uah_only'] == true,
    bankCategory: j['bank_category'] is String && (j['bank_category'] as String).trim().isNotEmpty
        ? (j['bank_category'] as String).trim()
        : null,
  );
}

/// `yyyy-mm-ddThh:mm:00`, no zone (a receipt's local time).
String _isoLocal(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}'
      'T${two(d.hour)}:${two(d.minute)}:00';
}

/// [ScreenshotReading.date] as a receipt's local date-time text.
String isoLocalOf(DateTime d) => _isoLocal(d);

/// The screenshot that belongs to a receipt of [receiptTotal]: the one whose
/// shop amount equals the total (within 0.5 %, at least 1). When the user sent
/// exactly one receipt ([solo]) with exactly one screenshot they belong
/// together even if the amounts do not match. Otherwise none (the rates then
/// come from the market).
ScreenshotReading? pickScreenshot(
  List<ScreenshotReading> shots,
  double? receiptTotal, {
  required bool solo,
}) {
  if (receiptTotal != null) {
    for (final s in shots) {
      final c = s.countAmount;
      if (c == null) continue;
      final tol = c * 0.005 > 1.0 ? c * 0.005 : 1.0;
      if ((c - receiptTotal).abs() <= tol) return s;
    }
  }
  return solo && shots.length == 1 ? shots.first : null;
}

const _num = r'(\d[\d\s  .,]*\d|\d)';
final _use = RegExp(
  '$_num\\s*(?:₴|грн|uah)(?![\\p{L}])',
  caseSensitive: false,
  unicode: true,
);
final _count = RegExp(
  // The Ukrainian model reads the Latin "TL" with a Cyrillic "Т" ("130.00 ТL").
  '$_num\\s*(?:₺|[tт]l|try)(?![\\p{L}])|(?:₺|[tт]l|try)\\s*$_num',
  caseSensitive: false,
  unicode: true,
);
// OCR without a Cyrillic model reads "курс" as the Latin look-alike "kypc" and
// "₴" as a stray symbol, but keeps the digits: accept both spellings.
final _rate = RegExp(
  r'(?:курс|kurs|kypc|rate)\D{0,12}?(\d+(?:[.,]\d+)?)',
  caseSensitive: false,
  unicode: true,
);

/// A charged amount shown with a leading minus (`-3 043.80`), whatever symbol
/// follows. Only trusted together with a rate (see [parseBankScreenshot]).
final _charged = RegExp(r'(?:^|[\s(])[-−–]\s*(\d[\d\s  .,]*[.,]\d{2})(?!\d)');

/// Reads the OCR text of a bank screenshot. Tolerant: whatever is not found is
/// null. The amount in hryvnia is the one with a `₴`/`грн` marker, the lira one
/// has `₺`/`TL`; the rate follows the word `курс`.
ScreenshotReading parseBankScreenshot(String text, {DateTime? now}) {
  double? useAmount;
  for (final m in _use.allMatches(text)) {
    final v = parseAmountText(m.group(1)!);
    if (v != null && (useAmount == null || v > useAmount)) useAmount = v;
  }
  double? countAmount;
  for (final m in _count.allMatches(text)) {
    final v = parseAmountText((m.group(1) ?? m.group(2))!);
    if (v != null && (countAmount == null || v > countAmount)) countAmount = v;
  }
  double? rate;
  final r = _rate.firstMatch(text);
  if (r != null) {
    final v = double.tryParse(r.group(1)!.replaceAll(',', '.'));
    if (v != null && v > 0) rate = v;
  }
  // No readable currency sign: the leading-minus amount is what was charged, but
  // only on a page that also states a rate (a receipt's discount line is not).
  if (useAmount == null && rate != null) {
    for (final m in _charged.allMatches(text)) {
      final v = parseAmountText(m.group(1)!);
      if (v != null && (useAmount == null || v > useAmount)) useAmount = v;
    }
  }
  final when = _readDate(text, now: now ?? DateTime.now(), strict: true);
  // A detail screen of the bank app: its main amount is the first amount line above
  // the balance, even when a real "₴" was read (the largest ₴ is then the BALANCE).
  // Without a lira amount and a rate it is hryvnia only (transfer, top-up, domestic buy).
  final bank = _bankScreenOf(text, hasDate: when != null);
  var incoming = false;
  var uahOnly = false;
  if (bank != null) {
    useAmount = bank.amount;
    // "-49." with the small decimals lost: the lira amount and the rate give them.
    if (bank.partial && countAmount != null && rate != null) {
      final derived = (countAmount * rate * 100).roundToDouble() / 100;
      if ((derived - bank.amount).abs() < 1) useAmount = derived;
    }
    uahOnly = countAmount == null && rate == null;
    incoming = uahOnly && bank.incoming;
  }
  final lines = text.split(RegExp(r'\r?\n'));
  final names = _nameAndChip(lines);
  return ScreenshotReading(
    useAmount: useAmount,
    countAmount: countAmount,
    rate: rate,
    // A transfer or top-up has no shop: Monobank's own caption stands there.
    merchant: lines.any(_isBankCaption) ? null : names?.name ?? _merchantOf(text),
    date: when?.at,
    dayGuessed: when?.dayGuessed ?? false,
    bankScreen: bank != null,
    incoming: incoming,
    uahOnly: uahOnly,
    bankCategory: bank != null && !lines.any(_isBankCaption) ? names?.chip : null,
  );
}

// ---- a bank app's detail screen without a lira amount --------------------------

final _balanceWord = _fold('залишок');
final _cashbackWord = _fold('кешбек');
final _tagsMark = RegExp(r'#\s*(?:ter|tag|тег)', caseSensitive: false);

/// Whole-line amount: optional sign, a number with two decimals, at most two
/// stray symbols (the "₴" read as `∞`, `会`, `号`, nothing, or as a digit by the Ukrainian model: "-3 491.00 2").
/// Monobank prints the integer large and the decimals small, so OCR may split them
/// ("-45.  .86 2", "-920 .00"): the groups are the integer part and the two decimals.
final _mainAmountLine = RegExp(
  r'^\s*([-−–+])?\s*(\d[\d\s  ]*?)\s*(?:[.,]\s*)?[.,]\s*(\d{2})\s*\S{0,2}\s*$',
);

/// A charged amount whose small decimals OCR lost: "-49." (trusted only with a sign).
final _wholeAmountLine = RegExp(r'^\s*([-−–])\s*(\d{1,9})\s*[.,]\s*$');

/// Monobank's own captions of a card-to-card transfer and a top-up, never a shop.
final _bankCaptions = [_fold('переказ на картку'), _fold('поповнення картки')];

bool _isBankCaption(String line) {
  final f = _fold(line.trim());
  if (f.length < 10) return false;
  for (final c in _bankCaptions) {
    final budget = c.length * 0.2 > 2 ? (c.length * 0.2).floor() : 2;
    if (_editDistance(f, c) <= budget) return true;
  }
  return false;
}

bool _isBalanceLine(String line) {
  bool word(String f) =>
      f.length >= 5 && f.length <= 10 && (_editDistance(f, _balanceWord) <= 1 || f == 'balance');
  final parts = line.trim().split(RegExp(r'\s+'));
  if (word(_fold(parts.join()))) return true;
  // The balance card and the cashback card share one row ("Залишок  Кешбек").
  return parts.length >= 2 &&
      word(_fold(parts.first)) &&
      _editDistance(_fold(parts.skip(1).join()), _cashbackWord) <= 2;
}

/// A detail screen of the bank app (the balance line and the tags line, or the
/// balance line and a date) and the first amount-only line ABOVE the balance:
/// that skips the balance, the chart's amounts and the status-bar time.
({double amount, bool incoming, bool partial})? _bankScreenOf(String text, {required bool hasDate}) {
  final lines = text.split(RegExp(r'\r?\n'));
  final balanceAt = lines.indexWhere(_isBalanceLine);
  if (balanceAt < 0) return null;
  if (!hasDate && !lines.any(_tagsMark.hasMatch)) return null;
  for (var i = 0; i < balanceAt; i++) {
    final m = _mainAmountLine.firstMatch(lines[i]);
    if (m != null) {
      final v = parseAmountText('${m.group(2)!.replaceAll(RegExp(r'\s+'), ' ')}.${m.group(3)}');
      if (v == null) continue;
      return (amount: v, incoming: m.group(1) == null || m.group(1) == '+', partial: false);
    }
    final w = _wholeAmountLine.firstMatch(lines[i]);
    final v = w == null ? null : parseAmountText(w.group(2)!);
    if (v != null) return (amount: v, incoming: false, partial: true);
  }
  return null;
}

final _amountLine = RegExp(
  _num + r'\s*(?:₴|грн|uah|₺|tl|try)(?![\p{L}])|(?:^|\s)[-−–]\s*\d',
  caseSensitive: false,
  unicode: true,
);
final _letters = RegExp(r'\p{L}', unicode: true);

/// Lines of a bank app that are never the merchant.
final _uiLine = RegExp(
  r'^(назад|back|деталі|details|готово|done|поділитися|share|квитанція|receipt|'
  r'успішно|success|оплата|payment|списання|покупка|у валюті|в валюті|курс|kypc|kurs)(?!\p{L})',
  caseSensitive: false,
  unicode: true,
);

final _cyrillic = RegExp(r'[а-яіїєґ]', caseSensitive: false);

/// A detail screen of the bank app reads, from the top: the shop name, the coloured
/// category chip ("Кафе та ресторани"), then the date line. Read in Ukrainian the chip is
/// Cyrillic, so the nearest text line above the date is the chip and the one above it the
/// shop. A non-Cyrillic line there (a Latin reading lost the chip) is not trusted: null.
({String name, String chip})? _nameAndChip(List<String> lines) {
  final dateAt = lines.indexWhere(
    (l) => _year.hasMatch(l) && parseScreenshotDate(l, now: DateTime(2000)) != null,
  );
  if (dateAt <= 0) return null;
  final found = <String>[];
  for (var i = dateAt - 1; i >= 0 && found.length < 2; i--) {
    final raw = lines[i].trim();
    if (_time.hasMatch(raw)) continue;
    final l = raw.replaceFirst(RegExp(r'^[^\p{L}]+', unicode: true), '');
    if (_letters.allMatches(l).length < 3 || _uiLine.hasMatch(l)) continue;
    found.add(l.length <= 80 ? l : l.substring(0, 80));
  }
  if (found.length < 2) return null;
  final letters = _letters.allMatches(found[0]).length;
  if (_cyrillic.allMatches(found[0]).length * 10 < letters * 7) return null;
  return (name: found[1], chip: found[0]);
}

/// The nearest line above the first amount with at least three letters that is
/// not a time, a date or a button of the bank app; a leading icon read as
/// digits is dropped.
String? _merchantOf(String text) {
  final lines = text.split(RegExp(r'\r?\n'));
  // A transfer or top-up has no shop: Monobank's own caption stands there.
  if (lines.any(_isBankCaption)) return null;
  final at = lines.indexWhere(_amountLine.hasMatch);
  if (at <= 0) return null;
  for (var i = at - 1; i >= 0; i--) {
    final raw = lines[i].trim();
    // The payment's day and time, even when OCR turned the month into Latin
    // look-alikes ("nmctonana2026,19:47" for "листопада 2026, 19:47").
    if (parseScreenshotDate(raw, now: DateTime(2000)) != null ||
        _time.hasMatch(raw) ||
        _year.hasMatch(raw)) {
      continue;
    }
    final l = raw.replaceFirst(RegExp(r'^[^\p{L}]+', unicode: true), '');
    if (_letters.allMatches(l).length < 3 || _uiLine.hasMatch(l)) continue;
    return l.length <= 80 ? l : l.substring(0, 80);
  }
  return null;
}

const _months = {
  'січ': 1, 'лют': 2, 'бер': 3, 'кві': 4, 'тра': 5, 'чер': 6,
  'лип': 7, 'сер': 8, 'вер': 9, 'жов': 10, 'лис': 11, 'гру': 12,
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

final _numericDate = RegExp(r'(?<!\d)(\d{1,2})[./](\d{1,2})(?:[./](\d{2}|\d{4}))?(?![\d./])');
final _wordDate = RegExp(
  r'(?<!\d)(\d{1,2})\s+(\p{L}{3,})\.?(?:\s+(\d{4}))?',
  caseSensitive: false,
  unicode: true,
);
final _year = RegExp(r'(?<!\d)20\d\d(?!\d)');
final _time = RegExp(r'(?<!\d)([01]?\d|2[0-3]):([0-5]\d)(?!\d)');

/// A day ("10 листопада [2026]", "10 Nov", "10.11.2026", "10.11 14:32") and,
/// when one stands after it, a time. A numeric day needs a year or a time (an
/// amount like `3.10 TL` is no date). Without a year: the latest such day not
/// after [now]. A screenshot's ([strict]) date line read by OCR without a
/// Cyrillic model ("7nmcTonaqa2026,20:05") is understood too. Null when no day
/// is readable.
DateTime? parseScreenshotDate(String text, {required DateTime now, bool strict = true}) =>
    _readDate(text, now: now, strict: strict)?.at;

({DateTime at, bool dayGuessed})? _readDate(
  String text, {
  required DateTime now,
  required bool strict,
}) {
  for (final w in _wordDate.allMatches(text)) {
    final month = _months[w.group(2)!.toLowerCase().substring(0, 3)];
    if (month == null) continue;
    final y = w.group(3) == null ? null : int.parse(w.group(3)!);
    final at = _dayAt(text, int.parse(w.group(1)!), month, y, w.end, now);
    if (at != null) return (at: at, dayGuessed: false);
  }
  for (final n in _numericDate.allMatches(text)) {
    final yy = n.group(3);
    final y = yy == null ? null : (yy.length == 2 ? 2000 + int.parse(yy) : int.parse(yy));
    if (strict &&
        y == null &&
        _time.matchAsPrefix(text.substring(n.end).replaceFirst(RegExp(r'^[\s,]+'), '')) == null) {
      continue;
    }
    final at = _dayAt(text, int.parse(n.group(1)!), int.parse(n.group(2)!), y, n.end, now);
    if (at != null) return (at: at, dayGuessed: false);
  }
  // Typed text never gets here: a word next to a year is not a month there.
  return strict ? _lookalikeDateIn(text, now) : null;
}

DateTime? _dayAt(String text, int d, int m, int? y, int end, DateTime now) {
  final rest = text.substring(end);
  // The time belongs to the day when it follows it closely ("…, 14:32").
  final t = _time.firstMatch(rest.length > 24 ? rest.substring(0, 24) : rest);
  final hh = t == null ? 12 : int.parse(t.group(1)!);
  final mm = t == null ? 0 : int.parse(t.group(2)!);
  return _dateOf(d, m, y, hh, mm, now);
}

/// Day [d] of month [m] at [hh]:[mm]; without a year [y] the latest such day
/// not after [now] (a day ahead allowed). Null for an impossible day.
DateTime? _dateOf(int d, int m, int? y, int hh, int mm, DateTime now) {
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  var at = DateTime(y ?? now.year, m, d, hh, mm);
  if (at.month != m) return null; // 31.02
  if (y == null && at.isAfter(now.add(const Duration(days: 1)))) {
    at = DateTime(now.year - 1, m, d, hh, mm);
  }
  return at;
}

// ---- a date line read by OCR without a Cyrillic model ------------------------

/// How a Latin recognition model reads each Ukrainian letter, as seen on real
/// bank screenshots ("7nmcTonaqa2026,20:05" for "7 листопада 2026, 20:05").
/// Readings vary (и is also "w"), the month match allows for that.
const _lookalike = {
  'а': 'a', 'б': '6', 'в': 'b', 'г': 'r', 'ґ': 'r', 'д': 'q', 'е': 'e', 'є': 'e',
  'ж': 'k', 'з': '3', 'и': 'm', 'і': 'i', 'ї': 'i', 'й': 'm', 'к': 'k', 'л': 'n',
  'м': 'm', 'н': 'h', 'о': 'o', 'п': 'n', 'р': 'p', 'с': 'c', 'т': 't', 'у': 'y',
  'ф': 'f', 'х': 'x', 'ц': 'u', 'ч': 'y', 'ш': 'w', 'щ': 'w', 'ь': 'b', 'ю': 'io',
  'я': 'g',
};

String _fold(String s) {
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    final c = String.fromCharCode(r);
    b.write(_lookalike[c] ?? c);
  }
  return b.toString();
}

/// Each month's genitive and nominative name, folded to its look-alike.
final _foldedMonths = [
  for (final names in const [
    ['січня', 'січень'], ['лютого', 'лютий'], ['березня', 'березень'],
    ['квітня', 'квітень'], ['травня', 'травень'], ['червня', 'червень'],
    ['липня', 'липень'], ['серпня', 'серпень'], ['вересня', 'вересень'],
    ['жовтня', 'жовтень'], ['листопада', 'листопад'], ['грудня', 'грудень'],
  ])
    [for (final n in names) _fold(n)],
];

/// A word, then a year and/or a time right after it (glued or not): the only
/// shape trusted as a look-alike date. An optional day stands before the word,
/// glued ("7nmc…") or apart ("7 nmc…").
final _lookalikeLine = RegExp(
  r'(?<![\p{L}\d])(?:(\d{1,2})\s+)?([\p{L}\d]{4,24}?)\s*'
  r'(?:(20\d\d)(?!\d)\s*,?\s*(?:([01]?\d|2[0-3]):([0-5]\d)(?!\d))?'
  r'|,?\s*([01]?\d|2[0-3]):([0-5]\d)(?!\d))',
  unicode: true,
);
final _anyLetter = RegExp(r'\p{L}', unicode: true);

/// The month whose look-alike [token] is: within 2 edits for 8+ letters, 1 for
/// 5-7, exact below; null when none or two months fit equally.
({int month, int dist})? _lookalikeMonth(String token) {
  final t = _fold(token);
  if (t.length < 4 || _anyLetter.allMatches(t).length < 3) return null;
  final budget = t.length >= 8 ? 2 : (t.length >= 5 ? 1 : 0);
  int? best;
  var bestDist = budget + 1;
  var tie = false;
  for (var i = 0; i < _foldedMonths.length; i++) {
    for (final name in _foldedMonths[i]) {
      final d = _editDistance(t, name);
      if (d < bestDist) {
        bestDist = d;
        best = i + 1;
        tie = false;
      } else if (d == bestDist && best != null && best != i + 1) {
        tie = true;
      }
    }
  }
  return best == null || tie ? null : (month: best, dist: bestDist);
}

int _editDistance(String a, String b) {
  var prev = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final sub = prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
      final del = prev[j] + 1;
      final ins = cur[j - 1] + 1;
      cur[j] = sub < del ? (sub < ins ? sub : ins) : (del < ins ? del : ins);
    }
    prev = cur;
  }
  return prev[b.length];
}

({DateTime at, bool dayGuessed})? _lookalikeDateIn(String text, DateTime now) {
  for (final m in _lookalikeLine.allMatches(text)) {
    final word = m.group(2)!;
    // Split a day glued in front ("7nmc…"): the split that reads best wins.
    int? day;
    ({int month, int dist})? month;
    final splits = m.group(1) != null ? [0] : [0, 1, 2];
    for (final k in splits) {
      if (k > 0 && (k > word.length - 4 || int.tryParse(word.substring(0, k)) == null)) continue;
      final found = _lookalikeMonth(word.substring(k));
      if (found == null || (month != null && found.dist > month.dist)) continue;
      month = found;
      day = k > 0 ? int.parse(word.substring(0, k)) : null;
    }
    if (month == null) continue;
    day ??= m.group(1) == null ? null : int.parse(m.group(1)!);
    final y = m.group(3) == null ? null : int.parse(m.group(3)!);
    final hhText = m.group(4) ?? m.group(6);
    final hh = hhText == null ? 12 : int.parse(hhText);
    final mm = hhText == null ? 0 : int.parse((m.group(5) ?? m.group(7))!);
    if (day != null) {
      final at = _dateOf(day, month.month, y, hh, mm, now);
      if (at != null) return (at: at, dayGuessed: false);
      continue;
    }
    return (at: _latestDayIn(month.month, y, hh, mm, now), dayGuessed: true);
  }
  return null;
}

/// OCR lost the day: the latest day of month [m] (of [y], else the latest such
/// month) not after [now] on which [hh]:[mm] has passed; the 1st when the whole
/// month lies after [now].
DateTime _latestDayIn(int m, int? y, int hh, int mm, DateTime now) {
  final year = y ?? (m > now.month ? now.year - 1 : now.year);
  if (DateTime(year, m).isAfter(now)) return DateTime(year, m, 1, hh, mm);
  final sameMonth = year == now.year && m == now.month;
  final d = sameMonth ? now.day : DateTime(year, m + 1, 0).day;
  final at = DateTime(year, m, d, hh, mm);
  return at.isAfter(now) && d > 1 ? DateTime(year, m, d - 1, hh, mm) : at;
}

// ---- the message sent with the screenshots -----------------------------------

/// Parts: lines, `;`, and a comma or full stop before a space (`150.50` stays).
final _captionSplit = RegExp(r'[\n;]+|[,.](?=\s)');
final _captionCurrency = RegExp(
  r'(?<![\p{L}])(?:₴|грн\p{L}*|uah|₺|tl|тл|try|лір\p{L}*|lira\p{L}*)(?![\p{L}])',
  caseSensitive: false,
  unicode: true,
);

/// For each of [shots] the part of [caption] about it, as an item name (the
/// amount, day and currency taken out), or null. A part with an amount goes to
/// the screenshot of that shop or charged amount, a part with a day to the
/// screenshots of that day; a part with neither to every screenshot no other
/// part took (the message wins over the merchant read on the screenshot), unless
/// [generic] is false (the generic part then belongs to something else, e.g. the
/// receipts sent in the same message).
List<String?> captionsForShots(
  String? caption,
  List<ScreenshotReading> shots, {
  required DateTime now,
  bool generic = true,
}) => placeCaptions(caption, shots, now: now, generic: generic).captions;

/// [captionsForShots] and the parts (as names) that no screenshot took: a part
/// with an amount or day that fits none, or a second part without either. The
/// rules cannot place those; the runner may ask the model once.
({List<String?> captions, List<String> leftover}) placeCaptions(
  String? caption,
  List<ScreenshotReading> shots, {
  required DateTime now,
  bool generic = true,
}) {
  final out = List<String?>.filled(shots.length, null);
  final leftover = <String>[];
  final text = (caption ?? '').trim();
  if (text.isEmpty || shots.isEmpty) return (captions: out, leftover: leftover);
  final taken = List<bool>.filled(shots.length, false);
  String? genericName;
  var hasGeneric = false;
  // "117, 49 грн" is a list of amounts, not two parts ("10.11.2026, 14:32" is no list).
  final listed = text.replaceAllMapped(
    RegExp(r'(?<=\d|₴|грн|uah)\s*,\s+(?=\d)(?!\d{1,2}:\d{2})', caseSensitive: false),
    (_) => ' і ',
  );
  for (final raw in listed.split(_captionSplit)) {
    var part = raw.trim();
    if (part.isEmpty) continue;
    final day = parseScreenshotDate(part, now: now, strict: false);
    part = part
        .replaceAll(_wordDateIn, ' ')
        .replaceAll(_numericDate, ' ')
        .replaceAll(_time, ' ');
    final amounts = <double>[];
    final nums = RegExp(_num).allMatches(part).toList();
    if (nums.isNotEmpty) {
      // The first number and the ones joined to it by "і" / "та" / "and" / a comma
      // ("117 і 49 грн - кафе"): each is an amount of its own.
      var end = nums.first.end;
      for (final m in nums) {
        if (m != nums.first) {
          final gap = part
              .substring(end, m.start)
              .replaceAll(_captionCurrency, ' ')
              .replaceAll(RegExp(r'[\s,;&+]+'), ' ')
              .trim()
              .toLowerCase();
          if (!const {'', 'і', 'й', 'та', 'и', 'and'}.contains(gap)) break;
        }
        final v = parseAmountText(m.group(1)!);
        if (v == null) break;
        amounts.add(v);
        end = m.end;
      }
      if (amounts.isNotEmpty) part = part.replaceRange(nums.first.start, end, ' ');
    }
    final name = _cleanName(part.replaceAll(_captionCurrency, ' '));
    var placed = false;
    if (amounts.isNotEmpty) {
      for (final amount in amounts) {
        final i = _closestShot(shots, taken, amount);
        if (i == null) continue;
        taken[i] = true;
        out[i] = name;
        placed = true;
      }
    } else if (day != null) {
      for (var i = 0; i < shots.length; i++) {
        final d = shots[i].date;
        if (!taken[i] && d != null && d.year == day.year && d.month == day.month && d.day == day.day) {
          taken[i] = true;
          out[i] = name;
          placed = true;
        }
      }
    } else if (!hasGeneric) {
      hasGeneric = true;
      genericName = name;
      // Without [generic] it names no screenshot: it stays for the receipts.
      placed = generic;
    }
    if (!placed && name != null) leftover.add(name);
  }
  if (generic && genericName != null) {
    for (var i = 0; i < shots.length; i++) {
      if (!taken[i]) out[i] = genericName;
    }
  }
  return (captions: out, leftover: leftover);
}

/// A day written with a month name, wherever it stands (for taking it out).
final _wordDateIn = RegExp(
  r'(?<!\d)\d{1,2}\s+(?:січ|лют|бер|кві|тра|чер|лип|сер|вер|жов|лис|гру|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\p{L}*\.?(?:\s+\d{4})?',
  caseSensitive: false,
  unicode: true,
);

/// The untaken screenshot whose shop or charged amount is nearest to [a] (within the
/// 0.5 % / 1.0 tolerance), else null: "49" is the 49.49 one, not a 50 TL one.
int? _closestShot(List<ScreenshotReading> shots, List<bool> taken, double a) {
  int? best;
  var bestDiff = double.infinity;
  for (var i = 0; i < shots.length; i++) {
    if (taken[i]) continue;
    for (final v in [shots[i].shopAmount, shots[i].useAmount]) {
      if (v == null) continue;
      final tol = v * 0.005 > 1.0 ? v * 0.005 : 1.0;
      final diff = (v - a).abs();
      if (diff <= tol && diff < bestDiff) {
        best = i;
        bestDiff = diff;
      }
    }
  }
  return best;
}

String? _cleanName(String s) {
  final t = s
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[\s\-–—:,.()]+|[\s\-–—:,.()]+$'), '')
      .trim();
  return RegExp(r'\p{L}', unicode: true).hasMatch(t) ? t : null;
}
