import 'extracted_receipt.dart';
import 'unit_normalizer.dart';

// Line parser (spec U6, U8 plus the unit rules): turns extracted receipt lines
// into priced lines. A quantity line ("2 ad X 16.50", "0.716 kg X 319.00") is
// printed ABOVE its item and applies to the NEXT item; a discount line
// (INDIRIM, negative amount) is taken off the PRECEDING item, so each line
// records the NET paid. Pure; a missing weight stays unknown (U7).

/// A question the user has to answer before the line can be recorded.
const kQuestionUnknownWeight = 'unknown_weight';

class ParsedLine {
  const ParsedLine({
    required this.raw,
    required this.name,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    required this.gross,
    required this.discount,
    required this.net,
    this.piecesPerPack,
    this.flags = const [],
    this.questions = const [],
  });

  final String raw;
  final String name;
  final UnitKind unit;

  /// Kilograms or pieces (packs) bought; null when the weight is unknown.
  final double? quantity;

  /// Price per kilogram / per piece (net / quantity); null when unknown.
  final double? unitPrice;
  final double gross;
  final double discount;

  /// What was really paid: gross - discount.
  final double net;

  /// Pieces inside one pack for pack notation (`30 LU`); [quantity] counts packs.
  final double? piecesPerPack;

  /// Rule ids and notes: U1..U5, U6 (qty line above), U8 (discount), `**`,
  /// qty_price_mismatch, missing_total.
  final List<String> flags;

  /// Question codes, e.g. [kQuestionUnknownWeight].
  final List<String> questions;

  bool get needsQuestion => questions.isNotEmpty;
}

class LineParseResult {
  const LineParseResult(this.lines, this.warnings);
  final List<ParsedLine> lines;

  /// Receipt-level problems: orphan_qty_line, orphan_discount.
  final List<String> warnings;

  double get netSum => _round2(lines.fold(0.0, (a, l) => a + l.net));
  List<ParsedLine> get questionLines => [
    for (final l in lines)
      if (l.needsQuestion) l,
  ];
}

double _round2(double v) => (v * 100).round() / 100;
double _d(String s) => double.parse(s.replaceAll(',', '.'));

final _qtyText = RegExp(
  r'^(\d+(?:[.,]\d+)?)\s*(ad|adet|kg|gr|g)\.?\s*[x*×]\s*(\d+(?:[.,]\d+)?)$',
);
final _priceAtEnd = RegExp(r'^(.*?)\s*\*?\s*(-?\d+[.,]\d{2})\s*$');

QtyLine? _qtyFromText(String raw) {
  final m = _qtyText.firstMatch(foldText(raw).trim());
  if (m == null) return null;
  return QtyLine(qty: _d(m[1]!), unit: m[2], unitPrice: _d(m[3]!));
}

bool _isDiscount(ReceiptLine l) {
  final t = l.lineTotal;
  if (t == null) return false;
  return t < 0 || RegExp(r'^[\s*]*indirim').hasMatch(foldText(l.raw));
}

/// Turns flat raw text lines (OCR output) into [ReceiptLine]s: qty lines,
/// discount lines and `name ... price` lines; anything else is skipped.
List<ReceiptLine> receiptLinesFromText(List<String> text) {
  final out = <ReceiptLine>[];
  for (final line in text) {
    final raw = line.trim();
    if (raw.isEmpty) continue;
    final q = _qtyFromText(raw);
    if (q != null) {
      out.add(ReceiptLine(raw: raw, qtyLine: q));
      continue;
    }
    final m = _priceAtEnd.firstMatch(raw);
    if (m == null) continue;
    final amount = _d(m[2]!);
    if (foldText(raw).contains('indirim')) {
      out.add(ReceiptLine(raw: raw, lineTotal: -amount.abs()));
      continue;
    }
    final starred = raw.startsWith('**');
    out.add(
      ReceiptLine(
        raw: raw,
        name: m[1]!.replaceFirst(RegExp(r'^[\s*]+'), '').trim(),
        lineTotal: amount,
        flags: [if (starred) '**'],
      ),
    );
  }
  return out;
}

class _Draft {
  _Draft(this.line, this.qty, this.fromAbove);
  final ReceiptLine line;
  final QtyLine? qty;
  final bool fromAbove;
  double discount = 0;
}

/// Parses extracted lines. [isPieceOnly] is the per-product "counts by piece"
/// override (U2, e.g. from alias memory or snacks): such a line is 1 piece per
/// pack and never needs a weight.
LineParseResult parseReceiptLines(
  List<ReceiptLine> lines, {
  bool Function(String name)? isPieceOnly,
}) {
  final drafts = <_Draft>[];
  final warnings = <String>[];
  QtyLine? pending;
  for (final l in lines) {
    if (_isDiscount(l)) {
      final amount = (l.lineTotal ?? l.discount).abs();
      if (drafts.isEmpty) {
        warnings.add('orphan_discount');
      } else {
        drafts.last.discount += amount;
      }
      continue;
    }
    final text = _qtyFromText(l.raw);
    if (l.lineTotal == null &&
        (text != null || (l.qtyLine != null && l.name == null))) {
      if (pending != null) warnings.add('orphan_qty_line');
      pending = l.qtyLine ?? text;
      continue;
    }
    final own = l.qtyLine;
    final d = _Draft(l, own ?? pending, own == null && pending != null);
    d.discount += l.discount;
    pending = null;
    drafts.add(d);
  }
  if (pending != null) warnings.add('orphan_qty_line');
  return LineParseResult([
    for (final d in drafts) _build(d, isPieceOnly),
  ], warnings);
}

/// Same as [parseReceiptLines] for a flat list of raw text lines.
LineParseResult parseRawTextLines(
  List<String> text, {
  bool Function(String name)? isPieceOnly,
}) => parseReceiptLines(receiptLinesFromText(text), isPieceOnly: isPieceOnly);

ParsedLine _build(_Draft d, bool Function(String)? isPieceOnly) {
  final l = d.line;
  final name = (l.name ?? l.raw).replaceFirst(RegExp(r'^[\s*]+'), '').trim();
  final q = d.qty;
  final qn = (q?.qty != null && q!.qty! > 0) ? q.qty : null;
  final qUnit = q == null ? null : foldText(q.unit ?? '');
  final flags = <String>[...l.flags];
  if (d.fromAbove) flags.add('U6');

  var gross = l.lineTotal;
  if (gross == null && qn != null && q?.unitPrice != null) {
    gross = _round2(qn * q!.unitPrice!);
  }
  if (gross == null) flags.add('missing_total');
  final g = gross ?? 0.0;
  final net = _round2(g - d.discount);
  if (d.discount > 0) flags.add('U8');
  if (qn != null && q?.unitPrice != null) {
    final tol = g * 0.001 > 0.05 ? g * 0.001 : 0.05;
    if ((qn * q!.unitPrice! - g).abs() > tol) flags.add('qty_price_mismatch');
  }

  ParsedLine make(
    UnitKind unit,
    double? quantity, {
    double? perPack,
    List<String> questions = const [],
  }) => ParsedLine(
    raw: l.raw,
    name: name,
    unit: unit,
    quantity: quantity,
    unitPrice: (quantity != null && quantity > 0) ? net / quantity : null,
    gross: g,
    discount: d.discount,
    net: net,
    piecesPerPack: perPack,
    flags: flags,
    questions: questions,
  );

  // "0.716 kg X 319.00": the weight is on the quantity line itself.
  if (qn != null && (qUnit == 'kg' || qUnit == 'g' || qUnit == 'gr')) {
    if (!flags.contains('U6')) flags.add('U6');
    return make(UnitKind.kilograms, qUnit == 'kg' ? qn : qn / 1000);
  }
  final packs = (qn != null && (qUnit == 'ad' || qUnit == 'adet')) ? qn : 1.0;
  final u = normalizeUnit(
    name,
    pack: l.pack,
    pieceOnly: isPieceOnly?.call(name) ?? false,
  );
  if (u.rule != null) flags.add(u.rule!);
  switch (u.kind) {
    case UnitKind.kilograms:
      return make(UnitKind.kilograms, packs * u.amount!);
    case UnitKind.pieces:
      return make(
        UnitKind.pieces,
        packs,
        perPack: u.rule == 'U5' ? u.amount : null,
      );
    case UnitKind.unknown:
      return make(UnitKind.unknown, null, questions: [kQuestionUnknownWeight]);
  }
}
