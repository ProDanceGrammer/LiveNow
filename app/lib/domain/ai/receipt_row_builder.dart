/// Rebuilds the printed ROWS of a receipt photo from raw OCR word boxes.
///
/// A photo of a paper receipt is tilted and the names (left), the VAT `%N` column
/// (middle) and the amounts (right) of ONE printed row land at different heights,
/// so grouping words by a fixed y band glues neighbouring rows together. Here every
/// word's y is first corrected by the page tilt (median slope of the word baselines),
/// then rows are clustered, then each row is read as `name | %vat | *amount`.
/// A `qty x price` row belongs to the item whose amount it explains (above or
/// below it). The total, the card tender, the date and the shop come from the
/// footer. Pure Dart, no model: [RebuiltReceipt.consistent] says whether the lines
/// add up to the printed total.
library;

import 'dart:math' as math;

import 'extracted_receipt.dart';
import 'unit_normalizer.dart' show foldText;

/// One OCR word box: its text, bounding box and (optionally) its baseline slope.
class ReceiptWord {
  const ReceiptWord({
    required this.text,
    required this.x0,
    required this.y0,
    required this.x1,
    required this.y1,
    this.slope,
    this.boxHeight,
  });

  /// From the four corners the OCR engine returns (top-left, top-right,
  /// bottom-right, bottom-left): the top edge gives the local tilt, the left edge
  /// the text height.
  factory ReceiptWord.fromQuad(String text, List<List<double>> quad) {
    final xs = [for (final p in quad) p[0]];
    final ys = [for (final p in quad) p[1]];
    double? slope;
    double? height;
    if (quad.length == 4) {
      final dx = quad[1][0] - quad[0][0];
      if (dx > 1) slope = (quad[1][1] - quad[0][1]) / dx;
      height = math.sqrt(
        math.pow(quad[3][0] - quad[0][0], 2) + math.pow(quad[3][1] - quad[0][1], 2),
      );
    }
    return ReceiptWord(
      text: text,
      x0: xs.reduce(math.min),
      y0: ys.reduce(math.min),
      x1: xs.reduce(math.max),
      y1: ys.reduce(math.max),
      slope: slope,
      boxHeight: height,
    );
  }

  /// For the OCR dump of a receipt that did not add up (replayable in a test).
  factory ReceiptWord.fromJson(Map<String, dynamic> j) => ReceiptWord(
    text: '${j['text'] ?? ''}',
    x0: (j['x0'] as num).toDouble(),
    y0: (j['y0'] as num).toDouble(),
    x1: (j['x1'] as num).toDouble(),
    y1: (j['y1'] as num).toDouble(),
    slope: (j['slope'] as num?)?.toDouble(),
    boxHeight: (j['box_height'] as num?)?.toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'text': text,
    'x0': x0,
    'y0': y0,
    'x1': x1,
    'y1': y1,
    'slope': slope,
    'box_height': boxHeight,
  };

  final String text;
  final double x0, y0, x1, y1;

  /// dy/dx of the word's baseline; null for a box without a quad.
  final double? slope;

  /// Length of the left edge of the quad; null for a plain box.
  final double? boxHeight;

  double get cx => (x0 + x1) / 2;
  double get cy => (y0 + y1) / 2;
  double get height => boxHeight ?? (y1 - y0);
}

/// The receipt read from the boxes, the text of its rows (for a model fallback)
/// and whether the lines add up to the printed total.
class RebuiltReceipt {
  const RebuiltReceipt({
    required this.receipt,
    required this.text,
    required this.consistent,
  });

  final ExtractedReceipt receipt;

  /// One printed row per line, in reading order, amounts included.
  final String text;

  /// Lines found, a total found, and net lines sum == total (within 5 kurus).
  final bool consistent;
}

/// "3.302,06", "3,302.06", "3.302.06" -> 3302.06; "0.845" -> 0.845; "329,95" ->
/// 329.95. The last separator is the decimal one unless it is a thousands
/// separator (several separators, the last followed by 3 digits).
double? parseReceiptNumber(String s) {
  var t = s.replaceAll(RegExp(r'\s'), '');
  var negative = false;
  if (t.startsWith('-')) {
    negative = true;
    t = t.substring(1);
  }
  if (t.isEmpty || !RegExp(r'^\d[\d.,]*$').hasMatch(t)) return null;
  final seps = RegExp(r'[.,]').allMatches(t).length;
  final last = t.lastIndexOf(RegExp(r'[.,]'));
  String digits;
  var frac = '';
  if (last < 0) {
    digits = t;
  } else {
    final after = t.length - last - 1;
    if (after == 0) return null;
    if (after <= 2 || seps == 1) {
      digits = t.substring(0, last).replaceAll(RegExp(r'[.,]'), '');
      frac = t.substring(last + 1);
    } else {
      digits = t.replaceAll(RegExp(r'[.,]'), '');
    }
  }
  final v = double.tryParse(frac.isEmpty ? digits : '$digits.$frac');
  return v == null ? null : (negative ? -v : v);
}

/// A printed money amount: two decimals, or (a lost decimal point, `*7550`)
/// three or more bare digits whose last two are the kurus.
///
/// [marked]: the token followed a `*` / `x` amount marker, so it IS an amount and
/// a lost digit is tolerated: one decimal (`*75.5` -> 75.50).
double? _money(String token, {bool marked = false}) {
  var t = token.replaceAll(RegExp(r'\s'), '');
  var negative = false;
  if (t.startsWith('-')) {
    negative = true;
    t = t.substring(1);
  }
  if (!RegExp(r'^\d[\d.,]*$').hasMatch(t)) return null;
  final last = t.lastIndexOf(RegExp(r'[.,]'));
  double? v;
  if (last < 0) {
    if (t.length < 3) return null;
    v = double.tryParse('${t.substring(0, t.length - 2)}.${t.substring(t.length - 2)}');
  } else {
    final decimals = t.length - last - 1;
    if (decimals != 2 && !(marked && decimals == 1)) return null;
    v = parseReceiptNumber(t);
  }
  return v == null ? null : (negative ? -v : v);
}

/// Splits what OCR glued into one word: `%1*32,95` -> `%1`, `*32,95`;
/// `GRECKA*244,95TL` -> `GRECKA`, `*244,95`. A `*` / `×` may follow anything; an
/// `x` only a non-letter (so a name like `MAX200` is left alone).
List<String> _splitGlued(String text) {
  var t = text;
  final tl = RegExp(r'^(.*\d)\s*(?:tl|₺)$', caseSensitive: false).firstMatch(t);
  if (tl != null) t = tl.group(1)!;
  final m =
      RegExp('^(.*?)([*×$_glyphs]-?\\d[\\d.,]*)\$').firstMatch(t) ??
      RegExp(r'^(.*[^A-Za-zÀ-ɏЀ-ӿ])([xX]-?\d[\d.,]*)$').firstMatch(t);
  if (m == null) return [t];
  final prefix = m.group(1)!;
  if (prefix.isEmpty || RegExp('^[*×$_glyphs]+\$').hasMatch(prefix)) return [t];
  // A masked card number (`#444111***车*6141`) is no amount.
  if (RegExp('[*×$_glyphs]{2,}|\\d{5,}').hasMatch(prefix)) return [t];
  if (_money(m.group(2)!.substring(1), marked: true) == null) return [t];
  return [prefix, m.group(2)!];
}

/// The words of one OCR word: glued amounts split (`_splitGlued`), and a VAT mark
/// at the end of a name word set apart (`MiNiKI %1` -> `MiNiKI`, `%1`).
List<String> _tokens(String text) {
  final out = <String>[];
  for (final p in _splitGlued(text)) {
    final m = _vatTail.firstMatch(p);
    if (m != null && m.start > 0) {
      out
        ..add(p.substring(0, m.start))
        ..add(m.group(1)!);
    } else {
      out.add(p);
    }
  }
  return out;
}

/// What can stand before an amount: the printed `*`, or what OCR made of it
/// (`x`, `$`, `#`, `+`, a CJK/fullwidth glyph like `本`).
const _glyphs = r'$#+¥€~^°�一-鿿＄＃＊＋￥';
final _marker = '[*×xX$_glyphs]';
final _itemAmount = RegExp('^$_marker\\s*(-?\\d[\\d.,]*)\$');
final _anyAmount = RegExp('^(?:$_marker\\s*)?(-?\\d[\\d.,]*)\$');
/// The VAT column: `%1`, `1%`, and the printed `%1.` / `%1,` with its dot.
final _vat1 = RegExp(r'^%\s*(\d{1,2})[.,]?$');
final _vat2 = RegExp(r'^(\d{1,2})\s*%[.,]?$');

/// A VAT mark OCR garbled beyond reading (`1%O1`, `1'O%01`): noise, not a name.
final _vatGarble = RegExp(r"^[\d'’OolI]{0,3}%[\dOolI'’.,]*$");

/// A VAT mark at the END of a name word (`BAR NUGA 240G MiNiKI %1`).
final _vatTail = RegExp(r"\s+(%\s*\d{1,2}[.,]?|[\d'’OolI]{0,3}%[\dOolI'’]*)$");

/// The VAT rates Turkish receipts print; `%12` is a `%1.` read with a stray digit.
double? _vatRate(String digits) {
  const rates = {0, 1, 8, 10, 18, 20};
  final v = int.tryParse(digits);
  if (v == null) return null;
  if (rates.contains(v)) return v.toDouble();
  final first = int.tryParse(digits.substring(0, 1));
  return first != null && rates.contains(first) ? first.toDouble() : null;
}

/// `0.785kg` alone: the head of a qty row whose `X39.00` came as a separate word.
final _qtyHead = RegExp(r'^(\d+(?:[.,]\d+)?)(kg|gr|g|adet|ad)$');
final _qtyRow = RegExp(
  r'^(\d+(?:[.,]\d+)?)(kg|gr|g|adet|ad)[x×*](\d+(?:[.,]\d+)?)(?:tl(?:/(?:kg|ad|adet))?)?$',
);
// The masked card number: `******6141`, with a glyph OCR put between the stars.
final _last4 = RegExp('[*•·$_glyphs]{2,}[*•·$_glyphs\\s]*(\\d{4})');
final _date = RegExp(r'(\d{2})[/.\-](\d{2})[/.\-](20\d{2})');
final _time = RegExp(r'saat\W*(\d{1,2}):(\d{2})');

/// BIM and others print no `SAAT`: the time follows the date (`02.11.202618:01`).
final _dateTime = RegExp(r'(\d{2})[/.\-](\d{2})[/.\-](20\d{2})\D{0,3}(\d{1,2}):(\d{2})');

/// Chains whose name appears somewhere on the receipt (folded) -> display name.
const _chains = <String, String>{
  'migros': 'Migros',
  'carrefour': 'CarrefourSA',
  'a101': 'A101',
  'bim': 'BİM',
  'sok market': 'ŞOK',
  'file market': 'File',
  'macrocenter': 'Macrocenter',
};

class _Row {
  _Row(this.words);
  final List<ReceiptWord> words;

  String name = '';
  double? vat;
  final amounts = <double>[];
  final looseAmounts = <double>[];
  String text = '';

  /// An amount printed as `X39.00`: the unit price of a qty row whose `0.785kg`
  /// came as a separate word.
  bool xAmount = false;
}

/// A letter O between digits (`5O0G`, `1O.50`) is a zero; [s] is folded (lower case).
String _fixO(String s) => s.replaceAllMapped(RegExp(r'(?<=\d)o(?=[\dkg.,])'), (_) => '0');

/// Reads [words] as one receipt; null when it holds no priced rows at all.
RebuiltReceipt? rebuildReceipt(List<ReceiptWord> words) {
  if (words.length < 4) return null;

  // 1. The page tilt: median baseline slope of the wide words.
  final slopes = <double>[
    for (final w in words)
      if (w.slope != null && w.x1 - w.x0 >= 30) w.slope!,
  ]..sort();
  var tilt = slopes.isEmpty ? 0.0 : slopes[slopes.length ~/ 2];
  tilt = tilt.clamp(-0.25, 0.25);
  double yc(ReceiptWord w) => w.cy - tilt * w.cx;

  final heights = [for (final w in words) w.height]..sort();
  final medianHeight = heights[heights.length ~/ 2];
  final sorted = [...words]..sort((a, b) => yc(a).compareTo(yc(b)));

  // The row pitch: boxes are padded (taller than the line spacing), so measure
  // it from the gaps between words that are clearly NOT on the same row.
  final gaps = <double>[
    for (var i = 1; i < sorted.length; i++)
      if (yc(sorted[i]) - yc(sorted[i - 1]) > 0.25 * medianHeight)
        yc(sorted[i]) - yc(sorted[i - 1]),
  ]..sort();
  final pitch = gaps.isEmpty ? medianHeight : gaps[gaps.length ~/ 2];
  final tol = math.max(3.0, 0.45 * pitch);

  // 2. Cluster the tilt-corrected words into rows.
  final groups = <List<ReceiptWord>>[];
  var sum = 0.0;
  for (final w in sorted) {
    final y = yc(w);
    if (groups.isNotEmpty && (y - sum / groups.last.length).abs() <= tol) {
      groups.last.add(w);
      sum += y;
    } else {
      groups.add([w]);
      sum = y;
    }
  }

  // 3. Read each row as name | vat | amounts.
  final rows = <_Row>[];
  for (final g in groups) {
    g.sort((a, b) => a.x0.compareTo(b.x0));
    final r = _Row(g);
    final names = <String>[];
    var lastWasLoose = false; // the row ends with an unmarked `30.62`
    var lastLoose = 0.0;
    for (final t in [for (final w in g) ..._tokens(w.text.trim())]) {
      final vat = _vat1.firstMatch(t) ?? _vat2.firstMatch(t);
      final item = _itemAmount.firstMatch(t);
      final any = _anyAmount.firstMatch(t);
      final marked = item == null ? null : _money(item.group(1)!, marked: true);
      lastWasLoose = false;
      if (vat != null) {
        r.vat = _vatRate(vat.group(1)!) ?? r.vat;
      } else if (t.contains('%') && _vatGarble.hasMatch(t)) {
        // `1%O1`: a VAT mark OCR made unreadable; not part of the name.
      } else if (marked != null) {
        r.amounts.add(marked);
        r.looseAmounts.add(marked);
        if (RegExp(r'^[xX]').hasMatch(t)) r.xAmount = true;
      } else if (item != null && !RegExp(r'^[xX]').hasMatch(t)) {
        // A `*`-marked number that is no amount (`*7`): receipt noise, not a name
        // (an `x` one, like `X6` in "COLA X6", may belong to the name).
        continue;
      } else if (any != null && _money(any.group(1)!) != null) {
        lastLoose = _money(any.group(1)!)!;
        r.looseAmounts.add(lastLoose);
        names.add(t);
        lastWasLoose = RegExp(r'^\d+[.,]\d{2}$').hasMatch(t);
      } else {
        names.add(t);
      }
    }
    // An amount whose marker OCR lost (`LiMON  %1.  30.62`): the row's rightmost
    // unmarked decimal is its amount when the rest still reads as a product name
    // (a qty row `0.785 kg X 39.00` and the footer keep theirs).
    if (r.amounts.isEmpty && lastWasLoose) {
      final all = _fixO(foldText(names.join(' ')).replaceAll(RegExp(r'\s'), ''));
      final rest = names.sublist(0, names.length - 1).join(' ');
      final f = foldText(rest);
      if (_qtyRow.firstMatch(all) == null &&
          RegExp(r'[A-Za-zÀ-ɏЀ-ӿ]{3}').hasMatch(rest) &&
          !f.contains('toplam') &&
          !f.contains('kdv')) {
        r.amounts.add(lastLoose);
        names.removeLast();
      }
    }
    r.name = names.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    r.text = [
      r.name,
      if (r.vat != null) '%${r.vat!.round()}',
      for (final a in r.looseAmounts) a.toStringAsFixed(2),
    ].where((s) => s.isNotEmpty).join('  ');
    rows.add(r);
  }

  // 4. Items end where the totals start.
  bool isFooter(_Row r) {
    final f = foldText(r.name);
    return f.contains('toplam') || f.contains('kdv');
  }

  // A priced TOPLAM / ARA TOPLAM row starts the footer. A header or promo row
  // ("KDV DAHIL") above the items, or a stray `kdv` row between them, must not
  // cut the list short: such rows are skipped below instead. Without a priced
  // total row the first footer-looking row after the first item is the cut.
  bool isTotalRow(_Row r) {
    final f = foldText(r.name).replaceAll(RegExp(r'\s'), '');
    return r.looseAmounts.isNotEmpty &&
        (f == 'toplam' || f == 'geneltoplam' || f == 'aratoplam');
  }

  final firstPriced = rows.indexWhere((r) => r.amounts.isNotEmpty && !isFooter(r));
  var footer = rows.length;
  if (firstPriced >= 0) {
    footer = rows.indexWhere(isTotalRow, firstPriced);
    if (footer < 0) footer = rows.indexWhere(isFooter, firstPriced);
    if (footer < 0) footer = rows.length;
  }

  final lines = <ReceiptLine>[];
  for (final r in rows.take(footer)) {
    if (isFooter(r)) continue;
    final spaceless = _fixO(foldText(r.name).replaceAll(RegExp(r'\s'), ''));
    final head = _qtyHead.firstMatch(spaceless);
    if (head != null && r.amounts.length == 1 && r.xAmount) {
      // `0.785kg` + `X39.00` as two words: a qty row, not a 39.00 item.
      final unit = head.group(2)!;
      lines.add(
        ReceiptLine(
          raw: r.name,
          qtyLine: QtyLine(
            qty: parseReceiptNumber(head.group(1)!),
            unit: unit == 'adet' ? 'ad' : unit,
            unitPrice: r.amounts.single,
          ),
        ),
      );
      continue;
    }
    final q = _qtyRow.firstMatch(spaceless);
    if (q != null && r.amounts.isEmpty) {
      final unit = q.group(2)!;
      lines.add(
        ReceiptLine(
          raw: r.name,
          qtyLine: QtyLine(
            qty: parseReceiptNumber(q.group(1)!),
            unit: unit == 'adet' ? 'ad' : unit,
            unitPrice: parseReceiptNumber(q.group(3)!),
          ),
        ),
      );
      continue;
    }
    if (r.amounts.isEmpty) continue;
    var name = r.name;
    final starred = name.startsWith('**');
    name = name.replaceFirst(RegExp(r'^[\s*]+'), '').trim();
    final amount = r.amounts.last;
    final discount = foldText(name).contains('indirim');
    if (name.isEmpty && !discount) continue;
    lines.add(
      ReceiptLine(
        raw: name,
        name: name,
        lineTotal: discount ? -amount.abs() : amount,
        vatPct: r.vat,
        flags: [if (starred) '**'],
      ),
    );
  }

  final fixed = _attachQtyRows(lines);
  if (fixed.every((l) => l.lineTotal == null)) return null;

  // 5. Footer: total, tender, date, shop.
  double? total;
  double? subtotal;
  for (final r in rows.skip(footer)) {
    final f = foldText(r.name).replaceAll(RegExp(r'\s'), '');
    if (r.looseAmounts.isEmpty) continue;
    if (f == 'toplam' || f == 'geneltoplam') {
      total ??= r.looseAmounts.last;
    } else if (f == 'aratoplam') {
      subtotal ??= r.looseAmounts.last;
    }
  }

  final allText = [for (final w in words) w.text].join(' ');
  final tenders = <Tender>[];
  for (final r in rows.skip(footer)) {
    final rowText = [for (final w in r.words) w.text].join(' ');
    final last4 = _last4.firstMatch(rowText)?.group(1);
    final f = foldText(rowText);
    final card = last4 != null || f.contains('pos') || f.contains('kredi');
    final cash = f.contains('nakit');
    if ((card || cash) && r.looseAmounts.isNotEmpty) {
      tenders.add(
        Tender(
          method: cash && !card ? 'cash' : 'card',
          last4: last4,
          amount: r.looseAmounts.last,
        ),
      );
    }
  }
  total ??= subtotal ?? (tenders.length == 1 ? tenders.first.amount : null);

  String? when;
  final d = _date.firstMatch(allText);
  if (d != null) {
    final t = _time.firstMatch(foldText(allText));
    // No `SAAT` word: the time printed right after the date.
    final dt = t == null ? _dateTime.firstMatch(allText) : null;
    final hh = (t?.group(1) ?? dt?.group(4) ?? '12').padLeft(2, '0');
    final mm = t?.group(2) ?? dt?.group(5) ?? '00';
    when = '${d.group(3)}-${d.group(2)}-${d.group(1)}T$hh:$mm:00';
  }

  final folded = foldText(allText);
  String? merchant;
  for (final e in _chains.entries) {
    if (RegExp('\\b${RegExp.escape(e.key)}\\b').hasMatch(folded)) {
      merchant = e.value;
      break;
    }
  }

  final receipt = ExtractedReceipt(
    merchant: merchant,
    terminalDatetimeLocal: when,
    total: total,
    tenders: tenders,
    lines: fixed,
    lowConfidenceFields: const [],
  );
  final net = fixed.fold(0.0, (a, l) => a + (l.lineTotal ?? 0) - l.discount);
  return RebuiltReceipt(
    receipt: receipt,
    text: [for (final r in rows) r.text].where((s) => s.isNotEmpty).join('\n'),
    consistent: total != null && (net - total).abs() <= 0.05,
  );
}

/// A `qty x price` row stands ABOVE the item it prices on most receipts (rule U6),
/// but the amount tells which one it is: it joins the neighbour whose total equals
/// qty * price; when neither does, the default (the item below) is kept.
List<ReceiptLine> _attachQtyRows(List<ReceiptLine> lines) {
  bool explains(QtyLine q, ReceiptLine? item) {
    final t = item?.lineTotal;
    if (t == null || q.qty == null || q.unitPrice == null) return false;
    return (q.qty! * q.unitPrice! - t).abs() <= math.max(0.05, t * 0.002);
  }

  final out = <ReceiptLine>[];
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    final isQtyRow = l.name == null && l.qtyLine != null;
    if (!isQtyRow) {
      out.add(l);
      continue;
    }
    final next = i + 1 < lines.length ? lines[i + 1] : null;
    final prev = out.isEmpty ? null : out.last;
    final q = l.qtyLine!;
    if (!explains(q, next) &&
        explains(q, prev) &&
        prev!.qtyLine == null &&
        prev.name != null) {
      out[out.length - 1] = ReceiptLine(
        raw: prev.raw,
        name: prev.name,
        lineTotal: prev.lineTotal,
        qtyLine: q,
        pack: prev.pack,
        discount: prev.discount,
        vatPct: prev.vatPct,
        flags: prev.flags,
      );
    } else {
      out.add(l);
    }
  }
  return out;
}
