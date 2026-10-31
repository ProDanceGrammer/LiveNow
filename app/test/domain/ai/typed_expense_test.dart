import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/ai/typed_expense.dart';
import 'package:livenow/domain/ai/unit_normalizer.dart' show UnitKind;

void main() {
  final now = DateTime(2026, 10, 31, 14, 30);
  const accounts = ['monobank', 'monobank фоп', 'turkish lira'];

  TypedExpense? parse(String t) => parseTypedExpense(t, now: now, accountNames: accounts);

  test('one item with a verb and a currency word', () {
    final e = parse('купив каву 150 лір')!;
    expect(e.items.single.name, 'Кава');
    expect(e.items.single.amount, 150);
    expect(e.currency, 'TRY');
    expect(e.explicit, isTrue);
    expect(e.cash, isFalse);
  });

  test('several items and cash', () {
    final e = parse('кава 150, хліб 40, сир 220 готівкою')!;
    expect(e.items.map((i) => i.name), ['Кава', 'Хліб', 'Сир']);
    expect(e.items.map((i) => i.amount), [150, 40, 220]);
    expect(e.cash, isTrue);
    expect(e.total, 410);
  });

  test('a bare item is not explicit', () {
    final e = parse('кава 150')!;
    expect(e.explicit, isFalse);
    expect(e.currency, isNull);
    expect(e.day, isNull);
  });

  test('quantity forms: kg + total, pieces times price, grams, per-unit price', () {
    var i = parse('помідори 2 кг 120')!.items.single;
    expect([i.quantity, i.unit, i.amount, i.unitPrice], [2.0, UnitKind.kilograms, 120.0, 60.0]);

    i = parse('помідори 3 шт × 25')!.items.single;
    expect([i.quantity, i.unit, i.amount, i.unitPrice], [3.0, UnitKind.pieces, 75.0, 25.0]);

    i = parse('яблука 500 г 40')!.items.single;
    expect([i.quantity, i.unit, i.amount, i.unitPrice], [0.5, UnitKind.kilograms, 40.0, 80.0]);

    i = parse('картопля 3 кг по 45')!.items.single;
    expect([i.quantity, i.unit, i.amount], [3.0, UnitKind.kilograms, 135.0]);
  });

  test('a decimal comma is not an item separator; a volume stays in the name', () {
    final e = parse('молоко 2,5 л 90')!;
    expect(e.items.single.name, 'Молоко 2.5 л');
    expect(e.items.single.amount, 90);
    expect(e.items.single.quantity, isNull);
  });

  test('day words and dates', () {
    expect(parse('кава 150 вчора')!.day, DateTime(2026, 10, 30));
    expect(parse('кава 150 позавчора')!.day, DateTime(2026, 10, 29));
    expect(parse('кава 150 за 28.10')!.day, DateTime(2026, 10, 28));
    expect(parse('кава 150 12.09.2026')!.day, DateTime(2026, 9, 12));
    // "12.50" is a price, not a date.
    final p = parse('кава 12.50')!;
    expect(p.day, isNull);
    expect(p.items.single.amount, 12.5);
  });

  test('the account named in the text is found and removed from the item', () {
    var e = parse('кава 150 з monobank')!;
    expect(e.accountIndex, 0);
    expect(e.items.single.name, 'Кава');

    e = parse('кава 150 з monobank фоп')!;
    expect(e.accountIndex, 1, reason: 'the longest full name wins');

    e = parse('кава 150 з фоп')!;
    expect(e.accountIndex, 1, reason: 'a word only one account has');
    expect(e.explicit, isTrue);
  });

  test('income', () {
    final e = parse('отримав 5000 від клієнта на фоп')!;
    expect(e.income, isTrue);
    expect(e.items.single.amount, 5000);
    expect(e.accountIndex, 1);
  });

  test('income with only an amount is named "Дохід"', () {
    final e = parse('отримав 5000 грн на monobank')!;
    expect(e.income, isTrue);
    expect(e.items.single.name, 'Дохід');
    expect(e.items.single.amount, 5000);
    expect(e.currency, 'UAH');
    expect(e.accountIndex, 0);
    expect(e.unparsed, isEmpty);
  });

  test('after a verb the accusative becomes the nominative; without one it is kept', () {
    expect(parse('купив каву 150')!.items.single.name, 'Кава');
    expect(parse('купив червону цибулю 40')!.items.single.name, 'Червона цибуля');
    expect(parse('купив хліб 40')!.items.single.name, 'Хліб');
    expect(parse('каву 150')!.items.single.name, 'Каву', reason: 'no verb: left as typed');
  });

  test('currency signs next to the number', () {
    expect(parse('кава 150₺')!.currency, 'TRY');
    expect(parse('кава 4\$')!.currency, 'USD');
    expect(parse('кава 4 €')!.currency, 'EUR');
    expect(parse('кава 150 грн')!.currency, 'UAH');
  });

  test('corrections and chatter are not expenses', () {
    expect(parse('5 - снеки'), isNull);
    expect(parse('рядок 2 категорія снеки'), isNull);
    expect(parse('привіт'), isNull);
    expect(parse(''), isNull);
  });

  test('a segment without an amount is reported, the rest is kept', () {
    final e = parse('кава 150, щось')!;
    expect(e.items.length, 1);
    expect(e.unparsed, ['щось']);
  });

  test('becomes a receipt the photo path can read', () {
    final e = parse('помідори 2 кг 120, кава 150 вчора')!;
    final r = e.toReceipt('TRY');
    expect(r.total, 270);
    expect(r.lines.length, 2);
    expect(r.lines[0].qtyLine!.unit, 'kg');
    expect(r.lines[0].qtyLine!.qty, 2);
    expect(r.invoiceDatetimeLocal, '2026-10-30T12:00:00');
  });
}
