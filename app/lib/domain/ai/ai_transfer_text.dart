import 'alias_source.dart' show normalizeReceiptText;

/// A parsed "I moved money between my accounts" message:
/// `перевів 12582.50 з ФОП на Monobank` / `moved 12,582.50 from FOP to Monobank`.
class TransferRequest {
  const TransferRequest({
    required this.amount,
    required this.from,
    required this.to,
  });

  /// In the SOURCE account's currency.
  final double amount;

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
  return [
    for (final a in accounts)
      if (_partial(normalizeReceiptText(nameOf(a)), key)) a,
  ];
}

bool _partial(String name, String key) =>
    name.isNotEmpty && (name.contains(key) || key.contains(name));
