import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/ai/ai_job_runner.dart' show parseWeightAnswer;
import 'package:livenow/domain/ai/ai_screenshot_text.dart';
import 'package:livenow/domain/ai/ai_transfer_text.dart';

void main() {
  group('A7 transfer text', () {
    test('Ukrainian', () {
      final r = parseTransferText('перевів 12582.50 з ФОП на Monobank')!;
      expect((r.amount, r.from, r.to), (12582.5, 'ФОП', 'Monobank'));
    });

    test('English with thousands separator and a currency sign', () {
      final r = parseTransferText('moved 12,582.50 ₴ from FOP to Monobank')!;
      expect((r.amount, r.from, r.to), (12582.5, 'FOP', 'Monobank'));
    });

    test('spaces as thousands, comma decimals, trailing dot', () {
      final r = parseTransferText('Переказав 12 582,50 грн із ФОП на Моно картку.')!;
      expect((r.amount, r.from, r.to), (12582.5, 'ФОП', 'Моно картку'));
    });

    test('not a transfer: null', () {
      expect(parseTransferText('привіт'), isNull);
      expect(parseTransferText('перевів гроші з ФОП на Monobank'), isNull);
      expect(parseTransferText('перевів 100'), isNull);
    });

    test('amounts', () {
      expect(parseAmountText('1.234,5'), 1234.5);
      expect(parseAmountText('1,234.5'), 1234.5);
      expect(parseAmountText('12,5'), 12.5);
      expect(parseAmountText('abc'), isNull);
    });

    test('account name matching: exact beats partial', () {
      final names = ['ФОП', 'ФОП євро', 'Monobank'];
      expect(matchAccountName('фоп', names, (n) => n), ['ФОП']);
      expect(matchAccountName('моно', names, (n) => n), isEmpty);
      expect(matchAccountName('Monobank card', names, (n) => n), ['Monobank']);
    });
  });

  group('A4 bank screenshot text', () {
    test('amount, shop amount and rate', () {
      final r = parseBankScreenshot('Monobank\nСума 961,69 ₴\nУ валюті 1 051,95 TL\nкурс 0,9142');
      expect(r.useAmount, 961.69);
      expect(r.countAmount, 1051.95);
      expect(r.rate, 0.9142);
      expect(r.hasAnything, isTrue);
    });

    test('nothing readable', () {
      expect(parseBankScreenshot('hello').hasAnything, isFalse);
    });
  });

  test('U7 answers: grams, kilograms, by the piece', () {
    expect(parseWeightAnswer('400 г')!.grams, 400);
    expect(parseWeightAnswer('1 кг')!.grams, 1000);
    expect(parseWeightAnswer('0,5 kg')!.grams, 500);
    expect(parseWeightAnswer('за штуку')!.piece, isTrue);
    expect(parseWeightAnswer('не знаю'), isNull);
  });
}
