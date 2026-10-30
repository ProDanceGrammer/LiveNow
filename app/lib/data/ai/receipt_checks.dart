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
ExtractedReceipt repairArithmetic(ExtractedReceipt r) {
  final lines = <ReceiptLine>[];
  final low = [...r.lowConfidenceFields];
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
      lines.add(copyLine(l, lineTotal: expected, flags: [...l.flags, 'repaired_line_total']));
      low.add('lines[$i].line_total');
    } else {
      lines.add(l);
    }
  }
  return copyReceipt(r, lines: lines, lowConfidenceFields: low);
}

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
