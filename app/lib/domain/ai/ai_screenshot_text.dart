import 'ai_transfer_text.dart' show parseAmountText;

/// What a bank screenshot says about one card payment: the amount charged in
/// the account currency (`useAmount`, e.g. UAH), the shop amount in the
/// receipt currency (`countAmount`, e.g. TRY) and/or the bank's rate
/// (use units per 1 count unit; spec A4 "курс r").
class ScreenshotReading {
  const ScreenshotReading({this.useAmount, this.countAmount, this.rate});

  final double? useAmount;
  final double? countAmount;
  final double? rate;

  bool get hasAnything => rate != null || (useAmount != null && countAmount != null);

  Map<String, dynamic> toJson() => {
    'rate': rate,
    'use': useAmount,
    'count': countAmount,
  };

  factory ScreenshotReading.fromJson(Map<String, dynamic> j) => ScreenshotReading(
    rate: (j['rate'] as num?)?.toDouble(),
    useAmount: (j['use'] as num?)?.toDouble(),
    countAmount: (j['count'] as num?)?.toDouble(),
  );
}

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
  '$_num\\s*(?:₺|tl|try)(?![\\p{L}])|(?:₺|tl|try)\\s*$_num',
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
ScreenshotReading parseBankScreenshot(String text) {
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
  return ScreenshotReading(useAmount: useAmount, countAmount: countAmount, rate: rate);
}
