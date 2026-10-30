import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/ai/bazaar_parser.dart';
import 'package:livenow/domain/ai/unit_normalizer.dart';

void main() {
  const note = '''
Базар 12.10
- [x] Кабачки 65/30=2,167
- [x] Морква 20
- [ ] Груші 80
- [x] Зелень 20
- [x] Банани 200/100=2
- [x] Помідори
''';

  BazaarItem item(BazaarNote n, String name) =>
      n.items.firstWhere((i) => i.name == name);

  test('B sample note: bought items, ignored items, unparsed lines', () {
    final n = parseBazaarNote(note);
    expect(n.items.map((i) => i.name), ['Кабачки', 'Морква', 'Зелень', 'Банани']);
    expect(n.ignored, ['Груші 80']);
    expect(n.unparsed, ['Помідори']);
  });

  test('B "Name T/P=Q": total T, price P per kg, quantity Q', () {
    final i = item(parseBazaarNote(note), 'Кабачки');
    expect(i.unit, UnitKind.kilograms);
    expect(i.total, 65);
    expect(i.unitPrice, 30);
    expect(i.quantity, closeTo(2.167, 1e-9));
    expect(i.flags, isNot(contains('qty_mismatch')));
  });

  test('B "Name N" is N per kg, quantity 1', () {
    final i = item(parseBazaarNote(note), 'Морква');
    expect(i.unitPrice, 20);
    expect(i.quantity, 1);
    expect(i.total, 20);
    expect(i.unit, UnitKind.kilograms);
  });

  test('B herbs are always a Piece: price N, quantity 1', () {
    final i = item(parseBazaarNote(note), 'Зелень');
    expect(i.unit, UnitKind.pieces);
    expect(i.unitPrice, 20);
    expect(i.quantity, 1);
    expect(i.flags, contains('herb'));
  });

  test('B "Банани 200/100=2" means price 100 per kg, quantity 2', () {
    final i = item(parseBazaarNote(note), 'Банани');
    expect(i.unitPrice, 100);
    expect(i.quantity, 2);
    expect(i.total, 200);
  });

  test('B a quantity that does not match T/P is corrected and flagged', () {
    final i = parseBazaarNote('- [x] Вишня 90/30=2').items.single;
    expect(i.quantity, closeTo(3, 1e-9));
    expect(i.total, 90);
    expect(i.flags, contains('qty_mismatch'));
  });

  test('B missing =Q is computed from T/P', () {
    final i = parseBazaarNote('- [x] Сливи 45/30').items.single;
    expect(i.quantity, closeTo(1.5, 1e-9));
    expect(i.flags, contains('qty_computed'));
  });

  test('B Cyrillic x and a plain bullet-less checkbox are accepted', () {
    final n = parseBazaarNote('[х] Цибуля 12,5\n[ ] Часник 30');
    expect(n.items.single.unitPrice, 12.5);
    expect(n.ignored, ['Часник 30']);
  });

  test('B note total is the sum of the paid totals', () {
    expect(parseBazaarNote(note).total, 65 + 20 + 20 + 200);
  });
}
