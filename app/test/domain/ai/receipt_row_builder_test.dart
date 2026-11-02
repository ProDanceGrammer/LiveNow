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

  /// Rows given as `(cells)`; each cell is (text, x, width). Same geometry as [receipt].
  List<ReceiptWord> rowsOf(List<List<(String, double, double)>> rows) {
    final out = <ReceiptWord>[];
    for (var i = 0; i < rows.length; i++) {
      final y = 250.0 + 21 * i;
      for (final (t, x, w) in rows[i]) {
        out.add(word(t, x, y, w));
      }
    }
    return out;
  }

  group('receipts the OCR garbles (bug reports of 31 Oct)', () {
    test('one-decimal and glued amounts, header and stray KDV rows', () {
      final r = rebuildReceipt(
        rowsOf([
          [('MIGROS', 200, 80)],
          [('KDV DAHIL FIYATLAR', 120, 260)],
          [('BAGDAT DEFNE', 120, 200), ('%1*32,95', 370, 100)],
          [('DORITOS NACHO', 120, 190), ('%1', 370, 25), ('*75.5', 450, 80)],
          [('GRECKA', 120, 100), ('*244,95TL', 430, 100)],
          [('TOPKDV', 120, 100), ('x5.00', 445, 80)],
          [('SNACK', 120, 100), ('%1', 370, 25), ('*10,00', 450, 80)],
          [('ARA TOPLAM', 255, 110), ('363,40', 430, 90)],
          [('TOPLAM', 120, 100), ('*363.40', 430, 90)],
          [('ORTAK POS', 300, 100), ('*363.40', 430, 90)],
        ]),
      )!;
      expect(r.consistent, isTrue, reason: r.text);
      expect([for (final l in r.receipt.lines) l.name], [
        'BAGDAT DEFNE',
        'DORITOS NACHO',
        'GRECKA',
        'SNACK',
      ]);
      expect([for (final l in r.receipt.lines) l.lineTotal], [32.95, 75.5, 244.95, 10.0]);
    });

    test('a long receipt keeps every row', () {
      final rows = <List<(String, double, double)>>[
        [('KDV DAHIL', 120, 120)],
        for (var i = 0; i < 20; i++)
          [
            ('ITEM $i', 120, 100),
            ('%1', 370, 25),
            ('*${(10 + i).toString()},00', 450, 80),
          ],
        [('TOPLAM', 120, 100), ('*${(20 * 10 + 190).toString()},00', 430, 90)],
      ];
      final r = rebuildReceipt(rowsOf(rows))!;
      expect(r.receipt.lines.length, 20, reason: r.text);
      expect(r.consistent, isTrue, reason: r.text);
    });

    test('a name keeps an x-word (COLA X6) and a letter-x before digits', () {
      final r = rebuildReceipt(
        rowsOf([
          [('COLA X6', 120, 100), ('%1', 370, 25), ('*50,00', 450, 80)],
          [('MAX200', 120, 100), ('*10,00', 450, 80)],
          [('TOPLAM', 120, 100), ('*60,00', 430, 90)],
        ]),
      )!;
      expect([for (final l in r.receipt.lines) l.name], ['COLA X6', 'MAX200']);
      expect(r.consistent, isTrue, reason: r.text);
    });
  });

  group('the BIM receipt of 2 Nov (OCR garbles)', () {
    // The tokens exactly as the OCR service returned them for the photo.
    List<ReceiptWord> bim() => rowsOf([
      [('BIM BIRLESIK MAGAZALAR A-S.', 120, 250)],
      [('02.11.202618:01', 120, 150), ('SiraNo:126', 420, 100)],
      [('3.015kgX29.50', 120, 150)],
      [('PATATES', 120, 80), ('%1.', 370, 25), ('*88.94', 450, 80)],
      [('0.534kgX339.00', 120, 150)],
      [('PiLIC BONFILE', 120, 120), ('%1.', 370, 25), ('*181.03', 450, 80)],
      [('0.975 kg X 49.00', 120, 160)],
      [('SALATALIK', 120, 90), ('%1.', 370, 25), ('*47.78', 450, 80)],
      [('TAMBUGDAYEKMK5O0G', 120, 200), ('%12', 370, 25), ('*65.00', 450, 80)],
      [('0.785kgX39.00', 120, 150)],
      [('LiMON', 120, 60), ('%1.', 370, 25), ('*30.62', 450, 80)],
      [('GUNLUK SUT 1L DOST', 120, 200), ('%1.', 370, 25), ('*59.00', 450, 80)],
      [('1.3kgX79.00', 120, 120)],
      [('DOMATES', 120, 80), ('%1.', 370, 25), ('本102.70', 450, 80)],
      [('HiNDi FUME 60G', 120, 150), ('%1,', 370, 25), ('*37.50', 450, 80)],
      [('PiLiC SALAM 150G', 120, 160), ('%1', 370, 25), ('*52.50', 450, 80)],
      [('BAR NUGA 240G MiNiKI %1', 120, 250), ('*65.00', 450, 80)],
      [('TOPLAMKDY', 120, 100), ('*7.23', 450, 80)],
      [('Odenecek KDV Dahil Tutar', 120, 250), (r'$730.07', 450, 80)],
      [('Banka Kredi Karti (1)', 120, 220), ('*730.07', 450, 80)],
      [('l:771804 T:01744855444111***车*6141', 120, 330)],
    ]);

    test('all ten items, the total, the time and the card are read', () {
      final r = rebuildReceipt(bim())!;
      expect(r.consistent, isTrue, reason: r.text);
      expect(r.receipt.total, 730.07);
      expect(r.receipt.merchant, 'BİM');
      expect(r.receipt.terminalDatetimeLocal, '2026-11-02T18:01:00');
      expect(r.receipt.tenders.single.amount, 730.07);
      final named = [for (final l in r.receipt.lines) if (l.name != null) l];
      expect([for (final l in named) l.name], [
        'PATATES',
        'PiLIC BONFILE',
        'SALATALIK',
        'TAMBUGDAYEKMK5O0G',
        'LiMON',
        'GUNLUK SUT 1L DOST',
        'DOMATES',
        'HiNDi FUME 60G',
        'PiLiC SALAM 150G',
        'BAR NUGA 240G MiNiKI',
      ]);
      expect(named[3].vatPct, 1, reason: '%12 is a %1. with a stray digit');
    });

    test('weighed items carry their weight, the pack in the name its size', () {
      final r = rebuildReceipt(bim())!;
      final parsed = parseReceiptLines(r.receipt.lines);
      final byName = {for (final l in parsed.lines) l.name: l};
      expect(byName['LiMON']!.quantity, closeTo(0.785, 1e-9));
      expect(byName['LiMON']!.net, 30.62);
      expect(byName['DOMATES']!.quantity, closeTo(1.3, 1e-9));
      expect(byName['PATATES']!.quantity, closeTo(3.015, 1e-9));
      expect(byName['TAMBUGDAYEKMK5O0G']!.quantity, closeTo(0.5, 1e-9));
      expect(parsed.netSum, 730.07);
    });

    test('a qty row split as `0.785kg` + `X39.00` is not a 39.00 item', () {
      final r = rebuildReceipt(
        rowsOf([
          [('0.785kg', 120, 80), ('X39.00', 300, 70)],
          [('LiMON', 120, 60), ('%1.', 370, 25), ('*30.62', 450, 80)],
          [('TOPLAM', 120, 100), ('*30.62', 430, 90)],
        ]),
      )!;
      expect(r.consistent, isTrue, reason: r.text);
      final parsed = parseReceiptLines(r.receipt.lines);
      expect(parsed.lines.single.name, 'LiMON');
      expect(parsed.lines.single.quantity, closeTo(0.785, 1e-9));
      expect(parsed.lines.single.net, 30.62);
    });

    test('a lost marker: the rightmost unmarked decimal is the amount', () {
      final r = rebuildReceipt(
        rowsOf([
          [('LiMON', 120, 60), ('%1.', 370, 25), ('30.62', 450, 80)],
          [('GUNLUK SUT', 120, 120), ('%1.', 370, 25), ('*59.00', 450, 80)],
          [('TOPLAM', 120, 100), ('*89.62', 430, 90)],
        ]),
      )!;
      expect(r.consistent, isTrue, reason: r.text);
      expect([for (final l in r.receipt.lines) l.name], ['LiMON', 'GUNLUK SUT']);
    });

    test('garbled VAT marks (1%O1, 1\'O%01) stay out of the names', () {
      final r = rebuildReceipt(
        rowsOf([
          [('HARIBO CHAMMALLOHE 1%O1', 120, 260), ('*65,00', 450, 80)],
          [("AMICO BADEM ICI 1'O%01", 120, 260), ('*134,00', 450, 80)],
          [('SAKA SU JO LIF', 120, 160), ('*95,50', 450, 80)],
          [('TOPKDV', 120, 100), ('*2,92', 450, 80)],
          [('TOPLAM TUHo UaOX*294,50', 120, 300)],
          [('KREDi', 120, 80), ('*294,50', 450, 80)],
        ]),
      )!;
      expect(r.consistent, isTrue, reason: r.text);
      expect([for (final l in r.receipt.lines) l.name], [
        'HARIBO CHAMMALLOHE',
        'AMICO BADEM ICI',
        'SAKA SU JO LIF',
      ]);
    });

    // The real photo's OCR boxes are a private receipt: git-ignored fixture.
    final fixture = File('../claude_dev/ai/fixtures/bim_ocr.json');
    test(
      'the real BIM photo adds up to 730.07 without any model',
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
        expect(r.receipt.total, 730.07, reason: r.text);
        expect(r.consistent, isTrue, reason: r.text);
        final parsed = parseReceiptLines(r.receipt.lines);
        expect(parsed.lines.length, 10, reason: r.text);
        expect(r.receipt.terminalDatetimeLocal, '2026-11-02T18:01:00');
      },
      skip: fixture.existsSync() ? false : 'private OCR fixture not present',
    );

    final haribo = File('../claude_dev/ai/fixtures/haribo_ocr.json');
    test(
      'the real HARIBO photo (garbled VAT marks and total row) adds up to 294.50',
      () {
        final j = jsonDecode(haribo.readAsStringSync()) as Map<String, dynamic>;
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
        final lines = [for (final l in r.receipt.lines) '${l.name}=${l.lineTotal}'];
        expect(r.receipt.total, 294.5, reason: r.text);
        expect(r.consistent, isTrue, reason: '$lines\n${r.text}');
        expect([for (final l in r.receipt.lines) l.name], [
          'HARIBO CHAMMALLOHE',
          'AMICO BADEM ICI',
          'SAKA SU JO LIF',
        ], reason: r.text);
      },
      skip: haribo.existsSync() ? false : 'private OCR fixture not present',
    );
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
