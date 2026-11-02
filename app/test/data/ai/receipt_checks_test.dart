import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/ai/receipt_checks.dart';
import 'package:livenow/domain/ai/extracted_receipt.dart';

ExtractedReceipt receiptOf(List<ReceiptLine> lines, {double? total}) =>
    ExtractedReceipt(total: total, lines: lines);

void main() {
  group('repairArithmetic', () {
    test('a price misread as a quantity keeps the printed total', () {
      // "*109.95 x109.9" read as qty 109.95 x unit price 109.9 = 12078.01.
      final r = repairArithmetic(
        receiptOf([
          const ReceiptLine(
            raw: 'MELIS KORNISON TURSU',
            name: 'MELIS KORNISON TURSU',
            lineTotal: 109.95,
            qtyLine: QtyLine(qty: 109.95, unit: 'ad', unitPrice: 109.9),
          ),
        ]),
      );
      final l = r.lines.single;
      expect(l.lineTotal, 109.95);
      expect(l.qtyLine, isNull);
      expect(l.flags, contains('dropped_qty_line'));
    });

    test('a real quantity line still repairs a wrong total', () {
      final r = repairArithmetic(
        receiptOf([
          const ReceiptLine(
            raw: 'MILK',
            name: 'MILK',
            lineTotal: 100.0,
            qtyLine: QtyLine(qty: 2, unit: 'ad', unitPrice: 122.48),
          ),
        ]),
        ocrText: 'MILK 2 AD X 122,48 *244,96',
      );
      expect(r.lines.single.lineTotal, 244.96);
      expect(r.lines.single.flags, contains('repaired_line_total'));
    });

    test('a printed total the OCR contains beats an unseen product', () {
      final r = repairArithmetic(
        receiptOf([
          const ReceiptLine(
            raw: 'CHEESE',
            name: 'CHEESE',
            lineTotal: 80.0,
            qtyLine: QtyLine(qty: 3, unit: 'ad', unitPrice: 20.0),
          ),
        ]),
        ocrText: 'CHEESE *80,00',
      );
      expect(r.lines.single.lineTotal, 80.0);
      expect(r.lines.single.qtyLine, isNull);
    });

    test('grams may be a large number', () {
      final r = repairArithmetic(
        receiptOf([
          const ReceiptLine(
            raw: 'X',
            name: 'X',
            lineTotal: 1.0,
            qtyLine: QtyLine(qty: 500, unit: 'g', unitPrice: 0.1),
          ),
        ]),
      );
      expect(r.lines.single.lineTotal, 50.0);
    });
  });

  group('cleanItemName', () {
    test('strips the amount and the VAT mark printed after the name', () {
      expect(cleanItemName('BAGDAT DEFNE YAPRAGI %1 *32,95'), 'BAGDAT DEFNE YAPRAGI');
      expect(cleanItemName('× DORITOS NACHO MEG %1 *75.5'), 'DORITOS NACHO MEG');
      expect(cleanItemName('MELIS KORNISON TURSU %1 *109.95 ×109.9'), 'MELIS KORNISON TURSU');
    });

    test('leaves honest names alone', () {
      expect(cleanItemName('MAX 2'), 'MAX 2');
      expect(cleanItemName('SUT %3'), 'SUT %3');
      expect(cleanItemName('COLA X6'), 'COLA X6');
      expect(cleanItemName('**'), '**');
    });
  });
}
