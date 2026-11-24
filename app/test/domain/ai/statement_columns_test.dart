import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/ai/statement/statement_columns.dart';
import 'package:livenow/domain/ai/statement/statement_rows.dart';

const _mono = [
  'Дата i час операції', 'Деталі операції', 'MCC', 'Сума в валюті картки (UAH)',
  'Сума в валюті операції', 'Валюта', 'Курс', 'Сума комісій (UAH)',
  'Сума кешбеку (UAH)', 'Залишок після операції',
];

void main() {
  test('Monobank-like header and rows', () {
    final t = [
      _mono,
      ['22.11.2026 16:28:10', 'Test Market', '5411', '-100.00', '-110.5', 'TRY', '0.905', '—', '1.00', '4000.50'],
      ['21.11.2026 10:00:00', 'Від: Test Person', '4829', '1 200,50', '1 200,50', 'UAH', '—', '—', '—', '5100.00'],
      ['bad date', 'x', '', '1', '', '', '', '', '', ''],
    ];
    final c = detectStatementColumns(t)!;
    expect(c.headerRow, 0);
    expect(c[StatementRole.dateTime], 0);
    expect(c[StatementRole.details], 1);
    expect(c[StatementRole.mcc], 2);
    expect(c[StatementRole.cardAmount], 3);
    expect(c[StatementRole.opAmount], 4);
    expect(c[StatementRole.opCurrency], 5);
    expect(c[StatementRole.rate], 6);
    expect(c[StatementRole.fee], 7);
    expect(c[StatementRole.cashback], 8);
    expect(c[StatementRole.balance], 9);
    expect(c.cardCurrency, 'UAH');
    expect(c.unknown, isEmpty);

    final p = parseStatementRows(t);
    expect(p.rows, hasLength(2));
    expect(p.skipped, hasLength(1));
    final r = p.rows.first;
    expect(r.at, DateTime(2026, 11, 22, 16, 28, 10));
    expect(r.cardAmount, -100.0);
    expect(r.opAmount, -110.5);
    expect(r.opCurrency, 'TRY');
    expect(r.rate, 0.905);
    expect(r.fee, isNull);
    expect(r.cashback, 1.0);
    expect(r.balance, 4000.5);
    expect(r.mcc, 5411);
    expect(r.isForeign, isTrue);
    expect(p.rows[1].cardAmount, 1200.5);
    expect(p.rows[1].isForeign, isFalse);
  });

  test('title rows before the header; Privat-like layout with split columns', () {
    final t = [
      ['Виписка по картці', '', ''],
      ['за період', '', ''],
      ['Дата', 'Час', 'Категорія', 'Опис операції', 'Списання', 'Зарахування', 'Валюта картки', 'Залишок'],
      ['05.11.2026', '09:15', 'Супермаркети', 'Test Shop', '250,00', '', 'UAH', '1000,00'],
      ['06.11.2026', '10:30:05', 'Перекази', 'Від: Some One', '', '300,00', 'UAH', '1300,00'],
    ];
    final c = detectStatementColumns(t)!;
    expect(c.headerRow, 2);
    expect(c[StatementRole.date], 0);
    expect(c[StatementRole.time], 1);
    expect(c[StatementRole.bankCategory], 2);
    expect(c[StatementRole.details], 3);
    expect(c[StatementRole.debit], 4);
    expect(c[StatementRole.credit], 5);
    expect(c[StatementRole.cardCurrency], 6);
    final p = parseStatementRows(t, defaultCardCurrency: 'EUR');
    expect(p.rows, hasLength(2));
    expect(p.rows[0].at, DateTime(2026, 11, 5, 9, 15));
    expect(p.rows[0].cardAmount, -250.0);
    expect(p.rows[0].cardCurrency, 'UAH');
    expect(p.rows[0].bankCategory, 'Супермаркети');
    expect(p.rows[1].at, DateTime(2026, 11, 6, 10, 30, 5));
    expect(p.rows[1].cardAmount, 300.0);
  });

  test('English layout, ISO dates, brackets, currency column', () {
    final t = [
      ['Date', 'Description', 'Amount', 'Currency', 'Balance'],
      ['2026-11-05 08:00', 'Coffee', '(3.50)', 'EUR', '96.50'],
      ['2026-11-06', 'Salary', '+1,000.00', 'EUR', '1096.50'],
    ];
    final c = detectStatementColumns(t)!;
    expect(c[StatementRole.cardCurrency], 3);
    expect(c.has(StatementRole.opCurrency), isFalse);
    final p = parseStatementRows(t);
    expect(p.rows.map((r) => r.cardAmount), [-3.5, 1000.0]);
    expect(p.rows[0].cardCurrency, 'EUR');
    expect(p.rows[1].at, DateTime(2026, 11, 6));
  });

  test('Turkish header and MM/dd/yyyy only when proven', () {
    final t = [
      ['Tarih', 'Açıklama', 'Tutar', 'Bakiye'],
      ['11/25/2026', 'Market', '-10,00', '90,00'],
      ['11/05/2026', 'Cafe', '-5,00', '85,00'],
    ];
    final p = parseStatementRows(t);
    expect(p.rows.map((r) => r.at), [DateTime(2026, 11, 25), DateTime(2026, 11, 5)]);
    final q = parseStatementRows([
      ['Date', 'Description', 'Amount'],
      ['03/04/2026', 'x', '-1'],
    ]);
    expect(q.rows.single.at, DateTime(2026, 4, 3));
  });

  test('no header or unusable header yields warnings, not rows', () {
    expect(parseStatementRows([['a', 'b'], ['1', '2']]).columns, isNull);
    final p = parseStatementRows([['Дата', 'Опис', 'Категорія'], ['01.01.2026', 'x', 'y']]);
    expect(p.rows, isEmpty);
    expect(p.warnings, isNotEmpty);
  });

  test('signed number parsing', () {
    expect(parseSignedAmount('—'), isNull);
    expect(parseSignedAmount('-'), isNull);
    expect(parseSignedAmount(''), isNull);
    expect(parseSignedAmount('−1 200,50 ₴'), -1200.5);
    expect(parseSignedAmount('0.00'), 0.0);
    expect(parseSignedAmount('12'), 12.0);
  });
}
