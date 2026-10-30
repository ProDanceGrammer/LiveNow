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
final _rate = RegExp(
  r'(?:курс|kurs|rate)\D{0,12}?(\d+(?:[.,]\d+)?)',
  caseSensitive: false,
  unicode: true,
);

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
  return ScreenshotReading(useAmount: useAmount, countAmount: countAmount, rate: rate);
}
