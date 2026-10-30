import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/ai/extracted_receipt.dart';
import 'package:livenow/domain/ai/unit_normalizer.dart';

void main() {
  void kg(String text, double expected, String rule) {
    final r = normalizeUnit(text);
    expect(r.kind, UnitKind.kilograms, reason: text);
    expect(r.amount, closeTo(expected, 1e-9), reason: text);
    expect(r.rule, rule, reason: text);
  }

  test('U1 weight and volume become kilograms, litres are kilograms', () {
    kg('EKMEK KÖY 600G', 0.6, 'U1');
    kg('KURU KAYISI 250 G', 0.25, 'U1');
    kg('DEODORANT 150ML', 0.15, 'U1');
    kg('** CAPPY ATOM 1L', 1, 'U1');
    kg('SUT 1.5 LT', 1.5, 'U1');
    kg('PIRINC 1 KG', 1, 'U1');
    kg('SALAM HİNDİ FIST.50G', 0.05, 'U1');
  });

  test('U1 a trailing printed price is not read as a weight', () {
    expect(normalizeUnit('BERLINER 57.90').kind, UnitKind.unknown);
    kg('HAŞHAŞLI ÇÖREK 150 G 48.00', 0.15, 'U1');
  });

  test('U2 piece-only override stays a piece', () {
    final r = normalizeUnit('BARILLA NAPOLETANA 400 G', pieceOnly: true);
    expect(r.kind, UnitKind.pieces);
    expect(r.amount, 1);
    expect(r.rule, 'U2');
  });

  test('U3 hundreds without a unit are grams', () {
    kg('YULAF500', 0.5, 'U3');
    kg('BULGUR 900', 0.9, 'U3');
  });

  test('U3 a number with a decimal part or four digits is not grams', () {
    expect(normalizeUnit('KEK 12.50').kind, UnitKind.unknown);
    expect(normalizeUnit('X 1000').kind, UnitKind.unknown);
  });

  test('U4 two sizes in one name use the larger', () {
    kg('SUPANGLE 236G&240G', 0.24, 'U4');
    kg('YULAFEZMESİ 350/500G', 0.5, 'U4');
    kg('BISKUVI 500G/350G', 0.5, 'U4');
  });

  test('U5 pack notation 10X40G is 400 g', () {
    kg('LOKUM 10X40G', 0.4, 'U5');
    kg('GOFRET 6 x 25 g', 0.15, 'U5');
  });

  test('U5 30 LU and 70Li are piece counts per pack', () {
    final eggs = normalizeUnit('YUMURTA 30 LU');
    expect(eggs.kind, UnitKind.pieces);
    expect(eggs.amount, 30);
    final bags = normalizeUnit('POSET 70Lİ');
    expect(bags.kind, UnitKind.pieces);
    expect(bags.amount, 70);
  });

  test('U7 unknown weight is unknown with a reason, never assumed', () {
    for (final t in ['SAKA SU', 'NORMAL EKMEK', 'LEZZETLİM DANA KIYMA']) {
      final r = normalizeUnit(t);
      expect(r.kind, UnitKind.unknown, reason: t);
      expect(r.amount, isNull);
      expect(r.reason, isNotNull);
    }
  });

  test('U1 the extractor pack is used only when the name says nothing', () {
    expect(
      normalizeUnit('SAKA SU', pack: const PackSize(ml: 500)).amount,
      closeTo(0.5, 1e-9),
    );
    kg('YULAF 250 G', 0.25, 'U1');
    expect(
      normalizeUnit('YULAF 250 G', pack: const PackSize(grams: 999)).amount,
      closeTo(0.25, 1e-9),
    );
  });
}
