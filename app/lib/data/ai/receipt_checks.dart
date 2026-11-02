/// Arithmetic checks the extractors apply to what a model returned: the program
/// trusts arithmetic over the model's guess. Pure Dart.
library;

import '../../domain/ai/extracted_receipt.dart';

double _round2(double v) => (v * 100).round() / 100;

/// What was paid for [l] after its discount (null when the amount is unknown).
double? netLineTotal(ReceiptLine l) =>
    l.lineTotal == null ? null : _round2(l.lineTotal! - l.discount);

/// Sum of the net line amounts; null when there are no lines.
double? linesSum(ExtractedReceipt r) {
  if (r.lines.isEmpty) return null;
  var s = 0.0;
  for (final l in r.lines) {
    s += netLineTotal(l) ?? 0;
  }
  return _round2(s);
}

/// True when the receipt has a total and lines and they do not add up.
bool sumMismatch(ExtractedReceipt r, {double tolerance = 0.05}) {
  final s = linesSum(r);
  return r.total != null && s != null && (s - r.total!).abs() > tolerance;
}

ExtractedReceipt copyReceipt(
  ExtractedReceipt r, {
  List<ReceiptLine>? lines,
  double? total,
  List<String>? lowConfidenceFields,
}) => ExtractedReceipt(
  merchant: r.merchant,
  invoiceDatetimeLocal: r.invoiceDatetimeLocal,
  terminalDatetimeLocal: r.terminalDatetimeLocal,
  currency: r.currency,
  total: total ?? r.total,
  tenders: r.tenders,
  lines: lines ?? r.lines,
  overallConfidence: r.overallConfidence,
  lowConfidenceFields: lowConfidenceFields ?? r.lowConfidenceFields,
);

ReceiptLine copyLine(ReceiptLine l, {double? lineTotal, List<String>? flags}) =>
    ReceiptLine(
      raw: l.raw,
      name: l.name,
      lineTotal: lineTotal ?? l.lineTotal,
      qtyLine: l.qtyLine,
      pack: l.pack,
      discount: l.discount,
      vatPct: l.vatPct,
      flags: flags ?? l.flags,
    );

/// `qty * unit_price == line_total` per line. A missing line total is filled in;
/// a wrong one is replaced (arithmetic wins) and the line is flagged. The
/// tolerance covers a weight printed with three decimals.
///
/// A quantity line is only believed when it is plausible: a piece count above 50
/// is a PRICE misread as a quantity (`*109.95 x109.9` read as 109.95 x 109.9
/// = 12078.01). Then the printed total stays and the bad quantity line is dropped.
/// With [ocrText], a printed total that the OCR really contains (while the product
/// does not appear) also wins over the product.
ExtractedReceipt repairArithmetic(ExtractedReceipt r, {String? ocrText}) {
  final lines = <ReceiptLine>[];
  final low = [...r.lowConfidenceFields];
  final seen = ocrText == null ? null : numberTokens(ocrText);
  for (var i = 0; i < r.lines.length; i++) {
    final l = r.lines[i];
    final q = l.qtyLine;
    if (q?.qty == null || q?.unitPrice == null) {
      lines.add(l);
      continue;
    }
    final expected = _round2(q!.qty! * q.unitPrice!);
    final tol = 0.02 + q.unitPrice! * 0.0005;
    if (l.lineTotal == null || (l.lineTotal! - expected).abs() > tol) {
      final weight = const {'g', 'gr'}.contains(q.unit?.toLowerCase());
      final implausible = !weight && q.qty!.abs() > 50;
      final printedSeen =
          seen != null &&
          l.lineTotal != null &&
          seen.contains(cents(l.lineTotal!)) &&
          !seen.contains(cents(expected));
      if (l.lineTotal != null && (implausible || printedSeen)) {
        lines.add(
          ReceiptLine(
            raw: l.raw,
            name: l.name,
            lineTotal: l.lineTotal,
            pack: l.pack,
            discount: l.discount,
            vatPct: l.vatPct,
            flags: [...l.flags, 'dropped_qty_line'],
          ),
        );
        low.add('lines[$i].qty_line');
        continue;
      }
      lines.add(copyLine(l, lineTotal: expected, flags: [...l.flags, 'repaired_line_total']));
      low.add('lines[$i].line_total');
    } else {
      lines.add(l);
    }
  }
  return copyReceipt(r, lines: lines, lowConfidenceFields: low);
}

/// A product name without what the receipt prints around it: the `*32,95` /
/// `x75.5` amount, the `%1` VAT mark and a leading `x` / `*`.
String cleanItemName(String name) {
  var n = name.trim();
  // A trailing `*109.95`, `×109.9` or ` x75,50` (an `x` only before a decimal number,
  // so "MAX 2" stays), optionally followed by TL.
  final amount = RegExp(
    r'(?:\s*[*×]\s*\d[\d.,]*|\s+[xX]\d+[.,]\d+)+(?:\s*(?:tl|₺))?$',
    caseSensitive: false,
  );
  var leaked = false;
  for (var i = 0; i < 4; i++) {
    final before = n;
    final cut = n.replaceFirst(amount, '');
    if (cut != n) leaked = true;
    n = cut;
    // The VAT mark is only noise when an amount was printed after it.
    if (leaked) n = n.replaceFirst(RegExp(r'\s*%\s*\d{1,2}[.,]?$'), '');
    // A garbled one (`1%O1`, `1'O%01`: it holds an O / l / I / quote) always is.
    n = n.replaceFirst(RegExp(r"\s+(?=[^\s]*[OolI'’])[\d'’OolI]{0,3}%[\dOolI'’.,]*$"), '');
    n = n.replaceFirst(RegExp(r'^[×*]+\s*'), '').trim();
    if (n == before) break;
  }
  return n.isEmpty ? name.trim() : n;
}

/// [cleanItemName] on every line (the printed text stays in `raw`).
ExtractedReceipt cleanReceiptNames(ExtractedReceipt r) => copyReceipt(
  r,
  lines: [
    for (final l in r.lines)
      l.name == null ? l : _withNameAndFlags(l, name: cleanItemName(l.name!)),
  ],
);

/// The flags a line may carry from a model: `**` (a discount follows) and
/// `low_confidence`. A small model fills the free-text field with junk
/// (`DISCOUNT` on every line), so everything else is dropped.
const _knownFlags = {'**', 'low_confidence'};

ExtractedReceipt sanitizeFlags(ExtractedReceipt r) => copyReceipt(
  r,
  lines: [
    for (final l in r.lines)
      _withNameAndFlags(l, flags: [for (final f in l.flags) if (_knownFlags.contains(f)) f]),
  ],
);

ReceiptLine _withNameAndFlags(ReceiptLine l, {String? name, List<String>? flags}) =>
    ReceiptLine(
      raw: l.raw,
      name: name ?? l.name,
      lineTotal: l.lineTotal,
      qtyLine: l.qtyLine,
      pack: l.pack,
      discount: l.discount,
      vatPct: l.vatPct,
      flags: flags ?? l.flags,
    );

/// All numbers in [text] as whole hundredths (`1.234,50` -> 123450), so two
/// readings of the same amount compare equal whatever the separators.
Set<int> numberTokens(String text) {
  final out = <int>{};
  for (final m in RegExp(r'\d+(?:[.,]\d+)*').allMatches(text)) {
    final s = m.group(0)!;
    final last = s.lastIndexOf(RegExp(r'[.,]'));
    final String digits;
    final String frac;
    if (last >= 0 && s.length - last - 1 <= 2) {
      digits = s.substring(0, last).replaceAll(RegExp(r'[.,]'), '');
      frac = s.substring(last + 1).padRight(2, '0');
    } else {
      digits = s.replaceAll(RegExp(r'[.,]'), '');
      frac = '00';
    }
    final v = int.tryParse('$digits$frac');
    if (v != null) out.add(v);
  }
  return out;
}

int cents(double v) => (v * 100).round();
