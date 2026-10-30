import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/ai/extracted_receipt.dart';
import 'package:livenow/domain/ai/line_parser.dart';
import 'package:livenow/domain/ai/sum_verifier.dart';
import 'package:livenow/domain/ai/unit_normalizer.dart';

ReceiptLine item(String raw, double total, {QtyLine? qty}) =>
    ReceiptLine(raw: raw, name: raw, lineTotal: total, qtyLine: qty);

ReceiptLine qtyAbove(String raw) => ReceiptLine(raw: raw);

void main() {
  // Piece-only (snack/hygiene) names the alias memory would supply.
  bool pieceOnly(String n) =>
      n.contains('DEODORANT') ||
      n.contains('BERLINER') ||
      n.contains('MISIR') ||
      n.contains('HAŞHAŞLI') ||
      n.contains('BİSK');

  test('E1 BIM receipt: qty line above, units, snacks, sum 881.40', () {
    final lines = [
      item('HAŞHAŞLI ÇÖREK 150 G', 48.00),
      item('EKMEK KÖY 600G', 64.00),
      qtyAbove('2 ad X 16.50'),
      item('BİSK.PORT.JÖLE.114 G', 33.00),
      item('MISIR CİPSİ 200G', 52.00),
      qtyAbove('2 ad X 32.50'),
      item('SALAM HİNDİ FIST.50G', 65.00),
      item('KURU KAYISI 250 G', 162.50),
      item('DEODORANT 150ML', 289.00),
      item('BERLINER', 57.90),
      item('BİTKİ ÇAYI AÇAİ 34 G', 110.00),
    ];
    final r = parseReceiptLines(lines, isPieceOnly: pieceOnly);
    expect(r.lines, hasLength(9));
    expect(r.warnings, isEmpty);
    expect(r.netSum, 881.40);
    expect(verifySum(r.lines.map((l) => l.net), 881.40).ok, isTrue);
    ParsedLine byName(String s) => r.lines.firstWhere((l) => l.name.contains(s));

    final bread = byName('EKMEK');
    expect(bread.unit, UnitKind.kilograms);
    expect(bread.quantity, closeTo(0.6, 1e-9));
    expect(bread.unitPrice, closeTo(106.6667, 1e-3));

    final salami = byName('SALAM');
    expect(salami.quantity, closeTo(0.1, 1e-9));
    expect(salami.unitPrice, closeTo(650, 1e-6));
    expect(salami.flags, contains('U6'));

    final apricot = byName('KURU');
    expect(apricot.quantity, closeTo(0.25, 1e-9));
    expect(apricot.unitPrice, closeTo(650, 1e-6));

    final tea = byName('BİTKİ');
    expect(tea.quantity, closeTo(0.034, 1e-9));
    expect(tea.unitPrice, closeTo(3235.2941, 1e-3));

    final deo = byName('DEODORANT');
    expect(deo.unit, UnitKind.pieces);
    expect(deo.quantity, 1);
    expect(deo.unitPrice, 289.00);

    // The qty line above gives 2 pieces of the snack: per piece 16.50.
    final snack = byName('BİSK');
    expect(snack.unit, UnitKind.pieces);
    expect(snack.quantity, 2);
    expect(snack.unitPrice, closeTo(16.50, 1e-9));
    expect(r.questionLines, isEmpty);
  });

  test('U6 qty line "N ad X price" applies to the NEXT item only', () {
    final r = parseReceiptLines([
      item('AYRAN 200 ML', 10.00),
      qtyAbove('3 ad X 12.00'),
      item('SUT 1 L', 36.00),
      item('SU 1 L', 8.00),
    ]);
    expect(r.lines[0].quantity, closeTo(0.2, 1e-9));
    expect(r.lines[1].quantity, closeTo(3, 1e-9));
    expect(r.lines[1].unitPrice, closeTo(12.00, 1e-9));
    expect(r.lines[2].quantity, closeTo(1, 1e-9));
  });

  test('U6 kg qty line: quantity and price per kg come from the line', () {
    final r = parseReceiptLines([
      qtyAbove('0.716 kg X 319.00'),
      item('DANA ETI', 228.40),
    ]);
    final l = r.lines.single;
    expect(l.unit, UnitKind.kilograms);
    expect(l.quantity, closeTo(0.716, 1e-9));
    expect(l.unitPrice, closeTo(319.0, 0.3));
    expect(l.flags, isNot(contains('qty_price_mismatch')));
    expect(l.needsQuestion, isFalse);
  });

  test('U6 a dangling qty line is a warning, not a crash', () {
    final r = parseReceiptLines([item('SU 1 L', 8.00), qtyAbove('2 ad X 5.00')]);
    expect(r.lines, hasLength(1));
    expect(r.warnings, contains('orphan_qty_line'));
  });

  test('U6 qty x price that does not match the total is flagged', () {
    final r = parseReceiptLines([
      qtyAbove('2 ad X 16.50'),
      item('BISKUVI 100 G', 50.00),
    ]);
    expect(r.lines.single.flags, contains('qty_price_mismatch'));
  });

  test('U3 hundreds in the name are grams in a parsed line', () {
    final r = parseReceiptLines([item('YULAF500', 40.00)]);
    final l = r.lines.single;
    expect(l.quantity, closeTo(0.5, 1e-9));
    expect(l.unitPrice, closeTo(80, 1e-9));
    expect(l.flags, contains('U3'));
  });

  test('U4 two sizes use the larger in a parsed line', () {
    final l = parseReceiptLines([item('YULAFEZMESİ 350/500G', 50.00)]).lines.single;
    expect(l.quantity, closeTo(0.5, 1e-9));
    expect(l.flags, contains('U4'));
  });

  test('U5 10X40G is 400 g and 30 LU keeps the pack count', () {
    final r = parseReceiptLines([
      item('LOKUM 10X40G', 80.00),
      item('YUMURTA 30 LU', 120.00),
    ]);
    expect(r.lines[0].quantity, closeTo(0.4, 1e-9));
    expect(r.lines[0].unitPrice, closeTo(200, 1e-9));
    expect(r.lines[1].unit, UnitKind.pieces);
    expect(r.lines[1].quantity, 1);
    expect(r.lines[1].piecesPerPack, 30);
  });

  test('U8 discount line is taken off the preceding item (net)', () {
    final r = parseReceiptLines([
      item('** CAPPY ATOM 1L', 80.00),
      const ReceiptLine(raw: 'İNDİRİM', lineTotal: -15.10),
      item('SU 1 L', 5.00),
    ]);
    expect(r.lines, hasLength(2));
    final cappy = r.lines.first;
    expect(cappy.gross, 80.00);
    expect(cappy.discount, closeTo(15.10, 1e-9));
    expect(cappy.net, 64.90);
    expect(cappy.quantity, closeTo(1, 1e-9));
    expect(cappy.unitPrice, closeTo(64.90, 1e-9));
    expect(cappy.flags, contains('U8'));
    expect(r.lines.last.net, 5.00);
  });

  test('U8 the discount field of a line is taken off too', () {
    final l = parseReceiptLines([
      const ReceiptLine(
        raw: 'SUT 1 L',
        name: 'SUT 1 L',
        lineTotal: 40.00,
        discount: 4.00,
      ),
    ]).lines.single;
    expect(l.net, 36.00);
  });

  test('U8 a discount with no item above is a warning', () {
    final r = parseReceiptLines([
      const ReceiptLine(raw: 'İNDİRİM', lineTotal: -3.00),
    ]);
    expect(r.lines, isEmpty);
    expect(r.warnings, contains('orphan_discount'));
  });

  test('E4 Migros discount: 64.90 net, 1 L = 1 kg, sum 654.98', () {
    final r = parseReceiptLines([
      item('** CAPPY ATOM 1L', 80.00),
      const ReceiptLine(raw: 'İNDİRİM', lineTotal: -15.10),
      item('PEYNIR', 200.00),
      item('ZEYTIN', 390.08),
    ], isPieceOnly: (n) => n == 'PEYNIR' || n == 'ZEYTIN');
    expect(r.lines.first.net, 64.90);
    expect(r.lines.first.unit, UnitKind.kilograms);
    expect(r.netSum, 654.98);
    expect(verifySum(r.lines.map((l) => l.net), 654.98).ok, isTrue);
  });

  test('E5 unknown weight: questions, no assumed quantity', () {
    final r = parseReceiptLines([
      item('LEZZETLİM DANA KIYMA', 330.00),
      item('NORMAL EKMEK', 20.00, qty: const QtyLine(qty: 2, unit: 'ad', unitPrice: 10)),
      item('BARILLA NAPOLETANA', 179.00),
      item('SUT 1 L', 40.00),
    ]);
    expect(r.questionLines.map((l) => l.name), [
      'LEZZETLİM DANA KIYMA',
      'NORMAL EKMEK',
      'BARILLA NAPOLETANA',
    ]);
    for (final l in r.questionLines) {
      expect(l.unit, UnitKind.unknown);
      expect(l.quantity, isNull);
      expect(l.unitPrice, isNull);
      expect(l.questions, [kQuestionUnknownWeight]);
    }
    expect(r.lines.last.needsQuestion, isFalse);
    // The money is still known, so the sum check works.
    expect(r.netSum, 569.00);
  });

  test('E5 an alias answer (piece override) removes the question', () {
    final r = parseReceiptLines([
      item('BARILLA NAPOLETANA', 179.00),
    ], isPieceOnly: (n) => n.contains('BARILLA'));
    expect(r.lines.single.needsQuestion, isFalse);
    expect(r.lines.single.unitPrice, 179.00);
  });

  test('U6 U8 a flat list of raw text lines is tolerated', () {
    final r = parseRawTextLines([
      'BIM BIRLESIK MAGAZALAR',
      '2 ad X 32.50',
      'SALAM HİNDİ FIST.50G *65.00',
      '** CAPPY ATOM 1L 80.00',
      'İNDİRİM -15.10',
    ]);
    expect(r.lines.map((l) => l.name).take(2), [
      'SALAM HİNDİ FIST.50G',
      'CAPPY ATOM 1L',
    ]);
    expect(r.lines[0].quantity, closeTo(0.1, 1e-9));
    expect(r.lines[0].unitPrice, closeTo(650, 1e-6));
    expect(r.lines[1].net, 64.90);
    expect(r.lines[1].flags, contains('**'));
  });
}
