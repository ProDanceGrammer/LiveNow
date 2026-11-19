import 'alias_source.dart' show normalizeReceiptText;

/// A parsed "I moved money between my accounts" message:
/// `перевів 12582.50 з ФОП на Monobank` / `moved 12,582.50 from FOP to Monobank`.
class TransferRequest {
  const TransferRequest({
    this.amount,
    required this.from,
    required this.to,
    this.date,
  });

  /// In the SOURCE account's currency; null when the message names none (a
  /// screenshot of the transfer then supplies it).
  final double? amount;

  /// When it happened (wall clock), when a screenshot says so.
  final DateTime? date;

  /// Account names as typed (match them with [matchAccountName]).
  final String from;
  final String to;
}

/// "12 582,50", "12,582.50", "12582.50", "12582,5" -> number, or null.
double? parseAmountText(String s) {
  var t = s.replaceAll(RegExp(r'[\s  ]'), '');
  if (t.isEmpty || !RegExp(r'^\d[\d.,]*$').hasMatch(t)) return null;
  final lastDot = t.lastIndexOf('.');
  final lastComma = t.lastIndexOf(',');
  if (lastDot >= 0 && lastComma >= 0) {
    final decimalIsDot = lastDot > lastComma;
    t = decimalIsDot
        ? t.replaceAll(',', '')
        : t.replaceAll('.', '').replaceFirst(',', '.');
  } else if (lastComma >= 0) {
    final after = t.length - lastComma - 1;
    t = (after == 3 && t.indexOf(',') == lastComma && lastComma <= 3)
        ? t.replaceAll(',', '')
        : t.replaceAll(',', '.');
  } else if (lastDot >= 0) {
    final after = t.length - lastDot - 1;
    if (after == 3 && t.indexOf('.') != lastDot) t = t.replaceAll('.', '');
  }
  final v = double.tryParse(t);
  return v != null && v > 0 && v.isFinite ? v : null;
}

const _verbs =
    r'(?:перев[іи]в|переказав|переклав|переніс|перекинув|поклав|відправив|'
    r'moved|transferred|transfer|sent|send|move)';
final _verb = RegExp(
  '(?<![\\p{L}])$_verbs(?![\\p{L}])',
  caseSensitive: false,
  unicode: true,
);
final _amount = RegExp(r'(?<![\p{L}\p{N}.,])\d[\d\s .,]*\d(?![\p{L}\p{N}])|(?<![\p{L}\p{N}.,])\d(?![\p{L}\p{N}.,])', unicode: true);
final _currency = RegExp(
  r'(?<![\p{L}])(?:грн|гривень|гривні|uah|try|tl|eur|usd|лір|ліри|lira|euro|євро|доларів)(?![\p{L}])|[₴₺€$]',
  caseSensitive: false,
  unicode: true,
);
final _names = RegExp(
  r'(?<![\p{L}])(?:з|із|від|from)\s+(.+?)\s+(?:на|до|to|into)\s+(.+?)\s*[.!]?\s*$',
  caseSensitive: false,
  unicode: true,
);

/// Null when the text is not recognisably a transfer (the caller then asks).
TransferRequest? parseTransferText(String text) {
  final t = text.trim();
  if (!_verb.hasMatch(t)) return null;
  final m = _amount.firstMatch(t);
  if (m == null) return null;
  final amount = parseAmountText(m.group(0)!);
  if (amount == null) return null;
  final rest = t
      .replaceRange(m.start, m.end, ' ')
      .replaceAll(_currency, ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final n = _names.firstMatch(rest);
  if (n == null) return null;
  final from = n.group(1)!.trim();
  final to = n.group(2)!.trim();
  if (from.isEmpty || to.isEmpty) return null;
  return TransferRequest(amount: amount, from: from, to: to);
}

/// A message part that is a transfer without a verb: `(з|із|від|from) X
/// (на|до|to|into) Y`, the amount optional. Only a SHAPE: the caller must
/// resolve both names to accounts before it believes it ("кава з молоком на
/// винос" has the same shape).
TransferRequest? parseTransferPart(String part) {
  var t = part.trim();
  double? amount;
  final m = _amount.firstMatch(t);
  if (m != null) {
    amount = parseAmountText(m.group(0)!);
    t = t.replaceRange(m.start, m.end, ' ');
  }
  final rest = t.replaceAll(_currency, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  final n = _names.firstMatch(rest);
  if (n == null) return null;
  final from = n.group(1)!.trim();
  final to = n.group(2)!.trim();
  if (from.isEmpty || to.isEmpty) return null;
  return TransferRequest(amount: amount, from: from, to: to);
}

/// The accounts whose name matches [typed] (folded, either contains the
/// other). Exact matches win over partial ones.
List<T> matchAccountName<T>(
  String typed,
  Iterable<T> accounts,
  String Function(T) nameOf,
) {
  final key = normalizeReceiptText(typed);
  if (key.isEmpty) return const [];
  final exact = [
    for (final a in accounts)
      if (normalizeReceiptText(nameOf(a)) == key) a,
  ];
  if (exact.isNotEmpty) return exact;
  // "Monobank" is the account "(₴) Monobank", not "(€) Monobank ФОП".
  final untagged = [
    for (final a in accounts)
      if (normalizeReceiptText(nameOf(a).replaceFirst(RegExp(r'^\s*\([^)]*\)\s*'), '')) == key) a,
  ];
  if (untagged.isNotEmpty) return untagged;
  return [
    for (final a in accounts)
      if (_partial(normalizeReceiptText(nameOf(a)), key)) a,
  ];
}

bool _partial(String name, String key) =>
    name.isNotEmpty && (name.contains(key) || key.contains(name));

// ---- account names told loosely ------------------------------------------------

const _translit = {
  'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'ґ': 'g', 'д': 'd', 'е': 'e', 'є': 'e',
  'ж': 'z', 'з': 'z', 'и': 'y', 'і': 'i', 'ї': 'i', 'й': 'y', 'к': 'k', 'л': 'l',
  'м': 'm', 'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u',
  'ф': 'f', 'х': 'h', 'ц': 'c', 'ч': 'c', 'ш': 's', 'щ': 's', 'ь': '', 'ю': 'u',
  'я': 'a', 'ы': 'y', 'э': 'e', 'ъ': '',
};

final _fillerWord = RegExp(
  r'^(?:карт\p{L}*|рахун\p{L}*|account|card|мій|моя|мою|my)$',
  caseSensitive: false,
  unicode: true,
);

/// The account currency a word names ("гривневу", "лірову", "євро", "usd"), or null.
String? _currencyOfWord(String w) {
  final l = w.toLowerCase();
  if (RegExp(r'^(?:гривнев\p{L}*|грн|uah|₴)$', unicode: true).hasMatch(l)) return 'UAH';
  if (RegExp(r'^(?:лір\p{L}*|lira|try|tl|тл|₺)$', unicode: true).hasMatch(l)) return 'TRY';
  if (RegExp(r'^(?:євро|eur|€)$', unicode: true).hasMatch(l)) return 'EUR';
  if (RegExp(r'^(?:долар\p{L}*|usd|\$)$', unicode: true).hasMatch(l)) return 'USD';
  return null;
}

String _latin(String w) {
  final b = StringBuffer();
  for (final r in w.toLowerCase().runes) {
    final c = String.fromCharCode(r);
    b.write(_translit[c] ?? c);
  }
  return b.toString();
}

List<String> _words(String s) => [
  for (final m in RegExp(r'[\p{L}\p{N}₴₺€$]+', unicode: true).allMatches(s)) m.group(0)!,
];

int _edits(String a, String b) {
  var prev = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final sub = prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
      final best = sub < prev[j] + 1 ? sub : prev[j] + 1;
      cur[j] = best < cur[j - 1] + 1 ? best : cur[j - 1] + 1;
    }
    prev = cur;
  }
  return prev[b.length];
}

/// Two words read alike once written in Latin letters: 1 edit allowed for 5-7
/// letters, 2 for 8 or more, none below.
bool _alike(String a, String b) {
  final len = a.length < b.length ? a.length : b.length;
  final budget = len >= 8 ? 2 : (len >= 5 ? 1 : 0);
  return _edits(a, b) <= budget;
}

/// The account [typed] means, loosely: ("монобанг гривневу карту" is
/// "(₴) Monobank", "Фоп" is "ФОП"). [matchAccountName] first; else the filler
/// words ("карту", "рахунок") are dropped, a currency word narrows the accounts
/// by currency, the other words must read like the account's own words (Cyrillic
/// written in Latin, small misreadings allowed) and the account that has no
/// other words wins over one that has. A still tied pair is split by
/// [currencyHint] (the currency of the screenshot). Empty or several = not
/// understood: the caller asks.
List<T> resolveAccount<T>(
  String typed,
  Iterable<T> accounts, {
  required String Function(T) nameOf,
  required String Function(T) currencyOf,
  String? currencyHint,
}) {
  final exact = matchAccountName(typed, accounts, nameOf);
  if (exact.length == 1) return exact;
  String? currency;
  final wanted = <String>[];
  for (final w in _words(typed)) {
    if (_fillerWord.hasMatch(w)) continue;
    final c = _currencyOfWord(w);
    if (c != null) {
      currency = c;
      continue;
    }
    wanted.add(_latin(w));
  }
  if (wanted.isEmpty) return exact;
  List<String> own(T a) => [
    for (final w in _words(nameOf(a).replaceFirst(RegExp(r'^\s*\([^)]*\)\s*'), '')))
      if (!_fillerWord.hasMatch(w)) _latin(w),
  ];
  bool covers(List<String> from, String w) => from.any((o) => _alike(w, o));
  var found = [
    for (final a in accounts)
      if (wanted.every((w) => covers(own(a), w))) a,
  ];
  if (currency != null) {
    found = [for (final a in found) if (currencyOf(a).toUpperCase() == currency) a];
  }
  if (found.length > 1) {
    // "Фоп" is the account "ФОП", not "Monobank ФОП".
    final tight = [
      for (final a in found)
        if (own(a).every((o) => covers(wanted, o))) a,
    ];
    if (tight.isNotEmpty) found = tight;
  }
  if (found.length > 1 && currencyHint != null) {
    final byHint = [for (final a in found) if (currencyOf(a).toUpperCase() == currencyHint.toUpperCase()) a];
    if (byHint.isNotEmpty) found = byHint;
  }
  return found;
}
