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

    test('a currency tag does not make the plain name ambiguous', () {
      final names = ['(€) Monobank ФОП', '(₴) Monobank', 'Turkish Lira'];
      expect(matchAccountName('Monobank', names, (n) => n), ['(₴) Monobank']);
      expect(matchAccountName('monobank фоп', names, (n) => n), ['(€) Monobank ФОП']);
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

    test('OCR without Cyrillic: "kypc", a stray symbol for the currency sign', () {
      final r = parseBankScreenshot(
        '5MALANYAKIPA.AVM-5530\n-1 043.80∞\nyBaJoTi1102.06TL,Kypc0.9217',
      );
      expect(r.hasAnything, isTrue);
      expect(r.rate, 0.9217);
      expect(r.countAmount, 1102.06);
      expect(r.useAmount, 1043.8);
    });

    test('a receipt with a discount line and a TL amount is not a screenshot', () {
      final r = parseBankScreenshot('INDIRIM -5,00\nMONEY ILE BU FISINIZDE 86,95TL\nTOPLAM *1.102,06');
      expect(r.hasAnything, isFalse);
    });

    test('nothing readable', () {
      expect(parseBankScreenshot('hello').hasAnything, isFalse);
    });

    test('a reading survives the job payload', () {
      final r = ScreenshotReading.fromJson(
        const ScreenshotReading(useAmount: 361.64, countAmount: 391.5, rate: 0.9237).toJson(),
      );
      expect((r.useAmount, r.countAmount, r.rate), (361.64, 391.5, 0.9237));
    });
  });

  group('which screenshot belongs to which receipt', () {
    const a = ScreenshotReading(useAmount: 361.64, countAmount: 391.5, rate: 0.9237);
    const b = ScreenshotReading(useAmount: 180, countAmount: 200, rate: 0.9);

    test('the one whose shop amount equals the receipt total', () {
      expect(pickScreenshot([a, b], 200.0, solo: false), same(b));
      expect(pickScreenshot([a, b], 391.5, solo: false), same(a));
      expect(pickScreenshot([a, b], 391.0, solo: false), same(a), reason: 'within the tolerance');
    });

    test('no match: only a single receipt with a single screenshot are trusted together', () {
      expect(pickScreenshot([a], 999, solo: true), same(a));
      expect(pickScreenshot([a], 999, solo: false), isNull);
      expect(pickScreenshot([a, b], 999, solo: true), isNull);
      expect(pickScreenshot(const [], 391.5, solo: true), isNull);
    });

    test('a screenshot with only a rate cannot be matched by amount', () {
      const onlyRate = ScreenshotReading(rate: 0.92);
      expect(pickScreenshot([onlyRate], 391.5, solo: false), isNull);
      expect(pickScreenshot([onlyRate], 391.5, solo: true), same(onlyRate));
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
