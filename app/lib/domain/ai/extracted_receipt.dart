/// What a receipt extractor (OCR + text model, or a vision model) returns: the
/// shared contract between the extractors, the parsers and the hub worker.
/// Mirrors the spec's `ExtractedReceipt` JSON (dev/flutter-ai-finance-integration-plan.md
/// section 6). Parsing is tolerant: a missing or malformed field becomes null / a
/// default, never an exception, because the text comes from a small model.
library;

double? _num(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim().replaceAll(',', '.'));
  return null;
}

int? _int(Object? v) => _num(v)?.round();

String? _str(Object? v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

/// "2 ad X 16.50" / "0.716 kg X 319.00": the quantity line printed ABOVE the
/// item it belongs to (rule U6).
class QtyLine {
  const QtyLine({this.qty, this.unit, this.unitPrice});

  final double? qty;
  final String? unit;
  final double? unitPrice;

  factory QtyLine.fromJson(Map<String, dynamic> j) => QtyLine(
    qty: _num(j['qty']),
    unit: _str(j['unit']),
    unitPrice: _num(j['unit_price']),
  );

  Map<String, dynamic> toJson() => {
    'qty': qty,
    'unit': unit,
    'unit_price': unitPrice,
  };
}

/// Pack size read from the product name: grams, millilitres or a piece count.
class PackSize {
  const PackSize({this.grams, this.ml, this.count});

  final double? grams;
  final double? ml;
  final int? count;

  factory PackSize.fromJson(Map<String, dynamic> j) => PackSize(
    grams: _num(j['grams']),
    ml: _num(j['ml']),
    count: _int(j['count']),
  );

  Map<String, dynamic> toJson() => {'grams': grams, 'ml': ml, 'count': count};
}

class ReceiptLine {
  const ReceiptLine({
    required this.raw,
    this.name,
    this.lineTotal,
    this.qtyLine,
    this.pack,
    this.discount = 0,
    this.vatPct,
    this.flags = const [],
  });

  /// The printed text of the line, exactly as read.
  final String raw;

  /// The product name as the extractor cleaned it (may equal [raw]).
  final String? name;

  /// What was paid for the line (before [discount] is taken off).
  final double? lineTotal;
  final QtyLine? qtyLine;
  final PackSize? pack;

  /// A positive amount that was taken off this line (`İNDİRİM`).
  final double discount;
  final double? vatPct;

  /// Marks such as `**` (a discount follows) or `low_confidence`.
  final List<String> flags;

  factory ReceiptLine.fromJson(Map<String, dynamic> j) => ReceiptLine(
    raw: _str(j['raw']) ?? _str(j['name']) ?? '',
    name: _str(j['name']),
    lineTotal: _num(j['line_total']),
    qtyLine: j['qty_line'] is Map
        ? QtyLine.fromJson(Map<String, dynamic>.from(j['qty_line'] as Map))
        : null,
    pack: j['pack'] is Map
        ? PackSize.fromJson(Map<String, dynamic>.from(j['pack'] as Map))
        : null,
    discount: _num(j['discount'])?.abs() ?? 0,
    vatPct: _num(j['vat_pct']),
    flags: [
      if (j['flags'] is List)
        for (final f in j['flags'] as List) f.toString(),
    ],
  );

  Map<String, dynamic> toJson() => {
    'raw': raw,
    'name': name,
    'line_total': lineTotal,
    'qty_line': qtyLine?.toJson(),
    'pack': pack?.toJson(),
    'discount': discount,
    'vat_pct': vatPct,
    'flags': flags,
  };
}

/// One payment on the receipt (a receipt can be paid with two cards).
class Tender {
  const Tender({this.method, this.last4, this.amount});

  /// `card` or `cash` (anything else is kept as read).
  final String? method;
  final String? last4;
  final double? amount;

  factory Tender.fromJson(Map<String, dynamic> j) => Tender(
    method: _str(j['method'])?.toLowerCase(),
    last4: _str(j['last4']),
    amount: _num(j['amount']),
  );

  Map<String, dynamic> toJson() => {
    'method': method,
    'last4': last4,
    'amount': amount,
  };
}

class ExtractedReceipt {
  const ExtractedReceipt({
    this.merchant,
    this.invoiceDatetimeLocal,
    this.terminalDatetimeLocal,
    this.currency = 'TRY',
    this.total,
    this.tenders = const [],
    this.lines = const [],
    this.overallConfidence,
    this.lowConfidenceFields = const [],
  });

  final String? merchant;

  /// Local (receipt-country) wall-clock times, ISO without a zone.
  final String? invoiceDatetimeLocal;
  final String? terminalDatetimeLocal;
  final String currency;
  final double? total;
  final List<Tender> tenders;
  final List<ReceiptLine> lines;
  final double? overallConfidence;
  final List<String> lowConfidenceFields;

  factory ExtractedReceipt.fromJson(Map<String, dynamic> j) {
    final conf = j['confidence'] is Map
        ? Map<String, dynamic>.from(j['confidence'] as Map)
        : const <String, dynamic>{};
    return ExtractedReceipt(
      merchant: _str(j['merchant']),
      invoiceDatetimeLocal: _str(j['invoice_datetime_local']),
      terminalDatetimeLocal: _str(j['terminal_datetime_local']),
      currency: (_str(j['currency']) ?? 'TRY').toUpperCase(),
      total: _num(j['total']),
      tenders: [
        if (j['tenders'] is List)
          for (final t in j['tenders'] as List)
            if (t is Map) Tender.fromJson(Map<String, dynamic>.from(t)),
      ],
      lines: [
        if (j['lines'] is List)
          for (final l in j['lines'] as List)
            if (l is Map) ReceiptLine.fromJson(Map<String, dynamic>.from(l)),
      ],
      overallConfidence: _num(conf['overall']),
      lowConfidenceFields: [
        if (conf['low_confidence_fields'] is List)
          for (final f in conf['low_confidence_fields'] as List) f.toString(),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
    'merchant': merchant,
    'invoice_datetime_local': invoiceDatetimeLocal,
    'terminal_datetime_local': terminalDatetimeLocal,
    'currency': currency,
    'total': total,
    'tenders': [for (final t in tenders) t.toJson()],
    'lines': [for (final l in lines) l.toJson()],
    'confidence': {
      'overall': overallConfidence,
      'low_confidence_fields': lowConfidenceFields,
    },
  };
}
