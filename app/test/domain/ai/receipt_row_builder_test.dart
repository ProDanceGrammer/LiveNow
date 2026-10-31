import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/ai/line_parser.dart';
import 'package:livenow/domain/ai/receipt_row_builder.dart';

/// A word of a photo tilted by [slope]: its baseline runs downhill to the right,
/// so the amounts (far right) sit lower than the names of the SAME printed row.
ReceiptWord word(
  String text,
  double x,
  double rowY,
  double width, {
  double slope = 0.045,
  double h = 10,
}) {
  double y(double px) => rowY + slope * px;
  return ReceiptWord.fromQuad(text, [
    [x, y(x)],
    [x + width, y(x + width)],
    [x + width, y(x + width) + h],
    [x, y(x) + h],
  ]);
}

/// Names at x 120, VAT at 370, amounts at 450; rows 21 px apart (the amount is
/// ~15 px lower than its name because of the tilt, so a fixed y band merges rows).
List<ReceiptWord> receipt({double slope = 0.045}) {
  var i = 0;
  double next() => 250.0 + 21 * i++;
  final out = <ReceiptWord>[];
  void row(List<(String, double, double)> cells) {
    final y = next();
    for (final (t, x, w) in cells) {
      out.add(word(t, x, y, w, slope: slope));
    }
  }

  row([('TARIH:29/10/2026', 120, 170), ('SAAT:22:35', 420, 100)]);
  row([('MIGROS', 200, 80)]);
  row([('RICE PACK 1 KG', 120, 200), ('%1', 370, 25), ('*24.95', 450, 80)]);
  row([('0.800KGX100,00TL/KG', 120, 240)]);
  row([('FAKE FILLET', 120, 190), ('%1', 370, 25), ('*80,00', 450, 80)]);
  row([('** SNACK DEMO', 120, 200), ('%20', 370, 35), ('*7550', 450, 70)]);
  row([('SOME DRINK', 120, 180), ('1%', 370, 25), ('x10.00', 450, 80)]);
  row([('ARA TOPLAM', 255, 110), ('190,45', 430, 90)]);
  row([('TOPKDV', 120, 100), ('x12.00', 445, 80)]);
  row([('TOPLAM', 120, 100), ('*190.45', 430, 90)]);
  row([('#444111******6141', 120, 180), ('ORTAK POS', 300, 100), ('*190.45', 430, 90)]);
  return out;
}

void main() {
  group('rows of a tilted receipt photo', () {
    test('every row keeps its own amount, vat and name', () {
      final r = rebuildReceipt(receipt())!;
      expect(r.consistent, isTrue, reason: r.text);
      expect(r.receipt.total, 190.45);
      final named = r.receipt.lines.where((l) => l.name != null).toList();
      expect([for (final l in named) l.name], [
        'RICE PACK 1 KG',
        'FAKE FILLET',
        'SNACK DEMO',
        'SOME DRINK',
      ]);
      expect([for (final l in named) l.lineTotal], [24.95, 80.0, 75.5, 10.0]);
      expect([for (final l in named) l.vatPct], [1, 1, 20, 1]);
      expect(named[2].flags, ['**']);
    });

    test('the same rows with a flat page, a steeper tilt and a counter-tilt', () {
      for (final s in [0.0, 0.08, -0.05]) {
        final r = rebuildReceipt(receipt(slope: s))!;
        expect(r.consistent, isTrue, reason: 'slope $s: ${r.text}');
        expect(r.receipt.lines.length, 5, reason: 'slope $s');
      }
    });

    test('the qty row joins the item its amount explains', () {
      final r = rebuildReceipt(receipt())!;
      // 0.8 kg x 100 = 80.00 is FAKE FILLET, printed below RICE PACK.
      final parsed = parseReceiptLines(r.receipt.lines);
      final fillet = parsed.lines.firstWhere((l) => l.name == 'FAKE FILLET');
      expect(fillet.quantity, closeTo(0.8, 1e-9));
      expect(fillet.net, 80.0);
      expect(parsed.warnings, isEmpty);
    });

    test('footer: card tender, date, shop', () {
      final r = rebuildReceipt(receipt())!.receipt;
      expect(r.tenders.single.method, 'card');
      expect(r.tenders.single.last4, '6141');
      expect(r.tenders.single.amount, 190.45);
      expect(r.terminalDatetimeLocal, '2026-10-29T22:35:00');
      expect(r.merchant, 'Migros');
    });

    test('lines that do not add up to the total are reported, not hidden', () {
      final words = receipt()..removeWhere((w) => w.text == '*24.95');
      final r = rebuildReceipt(words);
      // The row without an amount is dropped, so the sum is short: inconsistent.
      expect(r, isNotNull);
      expect(r!.consistent, isFalse);
    });

    test('nothing priced: null', () {
      expect(rebuildReceipt([word('HELLO', 10, 10, 50)]), isNull);
    });
  });

  group('receipt numbers', () {
    test('thousands and decimals', () {
      expect(parseReceiptNumber('3.302,06'), 3302.06);
      expect(parseReceiptNumber('3,302.06'), 3302.06);
      expect(parseReceiptNumber('3.302.06'), 3302.06);
      expect(parseReceiptNumber('1.234.567'), 1234567);
      expect(parseReceiptNumber('0.845'), 0.845);
      expect(parseReceiptNumber('329,95'), 329.95);
      expect(parseReceiptNumber('-12,50'), -12.5);
      expect(parseReceiptNumber('abc'), isNull);
    });
  });

  // The real Migros photo (skewed, 24 lines). Its OCR boxes are a private
  // receipt, so the fixture lives in the git-ignored claude_dev folder and the
  // test only runs where it exists.
  final fixture = File('../claude_dev/ai/fixtures/migros_ocr.json');
  test(
    'the real Migros photo: 24 lines add up to 3302.06',
    () {
      final j = jsonDecode(fixture.readAsStringSync()) as Map<String, dynamic>;
      final words = [
        for (final it in j['items'] as List)
          ReceiptWord.fromQuad(
            (it as Map)['text'] as String,
            [
              for (final p in it['quad'] as List)
                [((p as List)[0] as num).toDouble(), (p[1] as num).toDouble()],
            ],
          ),
      ];
      final r = rebuildReceipt(words)!;
      expect(r.receipt.total, 3302.06, reason: r.text);
      expect(r.consistent, isTrue, reason: r.text);
      final parsed = parseReceiptLines(r.receipt.lines);
      expect(parsed.lines.length, 24, reason: r.text);
      expect(parsed.netSum, 3302.06);
      final byName = {for (final l in parsed.lines) l.name: l};
      expect(byName['ROSHEN BUBBLE SUTLU']!.net, 99.9);
      expect(byName['BANVIT PILIC BONFILE']!.net, 278.81);
      expect(byName['BANVIT PILIC BONFILE']!.quantity, closeTo(0.845, 1e-9));
      expect(byName['DORITOS NACHO MEG']!.net, 75.5);
      expect(r.receipt.tenders.single.last4, '6141');
    },
    skip: fixture.existsSync() ? false : 'private OCR fixture not present',
  );
}
