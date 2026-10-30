import 'extracted_receipt.dart' show PackSize;

// Unit normalizer (spec rules U1-U5, U7): turns the text of a product name
// into "how much is ONE pack": kilograms, pieces, or unknown. Pure; never
// assumes a weight (U7). Litres count as kilograms (U1).

enum UnitKind { kilograms, pieces, unknown }

class UnitResult {
  const UnitResult._(this.kind, this.amount, this.rule, this.reason);
  const UnitResult.kilograms(double kg, String rule)
    : this._(UnitKind.kilograms, kg, rule, null);
  const UnitResult.pieces(double count, String rule)
    : this._(UnitKind.pieces, count, rule, null);
  const UnitResult.unknown(String reason)
    : this._(UnitKind.unknown, null, null, reason);

  final UnitKind kind;

  /// Kilograms (or pieces) in one pack; null when [kind] is unknown.
  final double? amount;

  /// Rule that decided it: U1 (plain weight/volume), U2 (piece-only override),
  /// U3 (hundreds = grams), U4 (two sizes -> larger), U5 (pack notation).
  final String? rule;

  /// Why the weight is unknown (U7: the caller must ask).
  final String? reason;
}

const _turkish = {
  'İ': 'i', 'I': 'i', 'ı': 'i', 'Ş': 's', 'ş': 's', 'Ğ': 'g', 'ğ': 'g',
  'Ü': 'u', 'ü': 'u', 'Ö': 'o', 'ö': 'o', 'Ç': 'c', 'ç': 'c',
};

/// Lower-cases and folds Turkish letters to ASCII so one regex fits receipts.
String foldText(String s) {
  final b = StringBuffer();
  for (final ch in s.split('')) {
    b.write(_turkish[ch] ?? ch);
  }
  return b.toString().toLowerCase();
}

const _unit = r'(kg|kgr|gram|gr|g|ml|litre|lt|l|cl)(?![a-z])';
const _num = r'(\d+(?:[.,]\d+)?)';

final _multi = RegExp('(?<!\\d)(\\d+)\\s*[x*]\\s*$_num\\s*$_unit');
final _twoSizes = RegExp('(?<!\\d)$_num\\s*(?:$_unit)?\\s*[&/]\\s*$_num\\s*$_unit');
final _single = RegExp('(?<!\\d)$_num\\s*$_unit');
final _packCount = RegExp(r'(?<!\d)(\d+)\s*l[iu](?![a-z])');
final _hundreds = RegExp(r'(?<![\d.,])(\d{3})(?![\d]|[.,]\d)');
final _trailingPrice = RegExp(r'\s+\*?-?\d+[.,]\d{2}\s*$');

double _d(String s) => double.parse(s.replaceAll(',', '.'));

double _toKg(double v, String unit) => switch (unit) {
  'g' || 'gr' || 'gram' || 'ml' => v / 1000,
  'cl' => v / 100,
  _ => v, // kg, kgr, l, lt, litre (1 L = 1 kg)
};

/// Net content of one pack from its name. [pieceOnly] is the per-product
/// override (U2). [pack] is the extractor's own reading, used only when the
/// name itself says nothing.
UnitResult normalizeUnit(
  String text, {
  PackSize? pack,
  bool pieceOnly = false,
}) {
  if (pieceOnly) return const UnitResult.pieces(1, 'U2');
  final s = foldText(text).replaceFirst(_trailingPrice, '');

  var m = _multi.firstMatch(s);
  if (m != null) {
    final kg = int.parse(m[1]!) * _toKg(_d(m[2]!), m[3]!);
    return UnitResult.kilograms(kg, 'U5');
  }
  m = _twoSizes.firstMatch(s);
  if (m != null) {
    final second = m[4]!;
    final a = _toKg(_d(m[1]!), m[2] ?? second);
    final b = _toKg(_d(m[3]!), second);
    return UnitResult.kilograms(a > b ? a : b, 'U4');
  }
  m = _single.firstMatch(s);
  if (m != null) return UnitResult.kilograms(_toKg(_d(m[1]!), m[2]!), 'U1');
  m = _packCount.firstMatch(s);
  if (m != null) return UnitResult.pieces(_d(m[1]!), 'U5');
  m = _hundreds.firstMatch(s);
  if (m != null) return UnitResult.kilograms(_d(m[1]!) / 1000, 'U3');

  if (pack != null) {
    if (pack.grams != null && pack.grams! > 0) {
      return UnitResult.kilograms(pack.grams! / 1000, 'U1');
    }
    if (pack.ml != null && pack.ml! > 0) {
      return UnitResult.kilograms(pack.ml! / 1000, 'U1');
    }
    if (pack.count != null && pack.count! > 0) {
      return UnitResult.pieces(pack.count!.toDouble(), 'U5');
    }
  }
  return const UnitResult.unknown('no weight or volume in the name');
}
