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

  group('bug 2026-11-10 a bank screenshot alone: merchant, day, the message', () {
    final now = DateTime(2026, 11, 10, 20, 24);

    test('the merchant is the line above the amount; a leading icon is dropped', () {
      final r = parseBankScreenshot(
        '5MALANYAKIPA.AVM-5530\n-1 043.80∞\nyBaJoTi1102.06TL,Kypc0.9217',
        now: now,
      );
      expect(r.merchant, 'MALANYAKIPA.AVM-5530');
      final m = parseBankScreenshot(
        '20:24\nНазад\nMIGROS KONYAALTI\n10 листопада, 14:32\n-1 370,00 ₴\nУ валюті 1 486,30 TL\nкурс 0,9217',
        now: now,
      );
      expect(m.merchant, 'MIGROS KONYAALTI');
      expect(m.date, DateTime(2026, 11, 10, 14, 32));
      expect(parseBankScreenshot('-150 ₴ курс 1', now: now).merchant, isNull);
      // img_2: the date line read in Latin look-alikes is not the merchant.
      final l = parseBankScreenshot(
        'Sunset Cafe\nnmctonana2026,19:47\n-1 262,93 ₴\nУ валюті 1 370,00 TL, курс 0,9219',
        now: now,
      );
      expect(l.merchant, 'Sunset Cafe');
      // The day was lost: the latest day of that month when 19:47 had passed.
      expect(l.date, DateTime(2026, 11, 10, 19, 47));
      expect(l.dayGuessed, isTrue);
      expect(ScreenshotReading.fromJson(l.toJson()).dayGuessed, isTrue);
    });

    test('a date line in Latin look-alikes: day glued to the month (dev/bugs/2026-11-11)', () {
      // The real OCR text of the Monobank screenshot "7 листопада 2026, 20:05".
      final r = parseBankScreenshot(
        '20:22\nBREW&CO\nPo3BarM Ta cnopT\n7nmcTonaqa2026,20:05\n-137.94会\n'
        'yBan1oTi150.00TL,Kypc0.9196\nBkakiTbHa3By Mara3wHya6ocaiTy',
        now: now,
      );
      expect(r.date, DateTime(2026, 11, 7, 20, 5));
      expect(r.dayGuessed, isFalse);
      expect(r.countAmount, 150.0);
      expect(r.toJson().containsKey('day_guessed'), isFalse);

      expect(parseScreenshotDate('7 nmcTonaqa 2026, 20:05', now: now), DateTime(2026, 11, 7, 20, 5));
      expect(parseScreenshotDate('7nmctonana,20:05', now: now), DateTime(2026, 11, 7, 20, 5));
      expect(parseScreenshotDate('16epe3hg2026,09:15', now: now), DateTime(2026, 3, 1, 9, 15));
      expect(parseScreenshotDate('14bepechg2026,09:15', now: now), DateTime(2026, 9, 14, 9, 15));
      // No year: the latest such day not after now.
      expect(parseScreenshotDate('3rpyqhg,10:00', now: now), DateTime(2025, 12, 3, 10));
      // Words that are no month stay no date; typed text is never read this way.
      expect(parseScreenshotDate('MIGROS 2026, 10:00', now: now), isNull);
      expect(parseScreenshotDate('Po3BarM Ta cnopT 20:05', now: now), isNull);
      expect(parseScreenshotDate('7nmcTonaqa2026,20:05', now: now, strict: false), isNull);
    });

    test('days: words, numbers with a year or a time; an amount is no day', () {
      expect(parseScreenshotDate('9 листопада 2026', now: now), DateTime(2026, 11, 9, 12));
      expect(parseScreenshotDate('31 Dec 13:05', now: now), DateTime(2025, 12, 31, 13, 5));
      expect(parseScreenshotDate('08.11.2026 09:15', now: now), DateTime(2026, 11, 8, 9, 15));
      expect(parseScreenshotDate('08.11, 09:15', now: now), DateTime(2026, 11, 8, 9, 15));
      expect(parseScreenshotDate('3.10 TL', now: now), isNull);
      expect(parseScreenshotDate('5.30 TL ... 7 листопада', now: now), DateTime(2026, 11, 7, 12));
      expect(parseScreenshotDate('3.10 кава', now: now, strict: false), DateTime(2026, 10, 3, 12));
    });

    test('shop amount from the charged amount and the rate when no TL shows', () {
      final r = parseBankScreenshot('Кафе\n-92,17 ₴\nкурс 0,9217', now: now);
      expect(r.countAmount, isNull);
      expect(r.shopAmount, 100.0);
      final back = ScreenshotReading.fromJson(r.toJson());
      expect(back.merchant, 'Кафе');
      expect(back.shopAmount, 100.0);
    });

    ScreenshotReading shot(double count, {DateTime? date}) =>
        ScreenshotReading(countAmount: count, useAmount: count * 0.92, rate: 0.92, date: date);

    test('the message: by sum, by day, one text for the rest', () {
      final shots = [
        shot(150),
        shot(1370, date: DateTime(2026, 11, 9, 13)),
        shot(80),
      ];
      expect(
        captionsForShots('кава 150, таксі 1370', shots, now: now),
        ['кава', 'таксі', null],
      );
      expect(
        captionsForShots('9.11 вечеря\nпродукти', shots, now: now),
        ['продукти', 'вечеря', 'продукти'],
      );
      expect(captionsForShots('150 ₺ — кава', shots, now: now), ['кава', null, null]);
      expect(captionsForShots('кава', [shot(150)], now: now), ['кава']);
      // Bug 2026-11-10 img_2: two sentences; the first is for all the others.
      expect(
        captionsForShots('кафе і ресторани. 150 лір - сувеніри', shots, now: now),
        ['сувеніри', 'кафе і ресторани', 'кафе і ресторани'],
      );
      expect(captionsForShots('кава 150.50', [shot(150.5)], now: now), ['кава']);
      expect(captionsForShots(null, shots, now: now), [null, null, null]);
      // A sum without a name claims its screenshot (it keeps its merchant).
      expect(captionsForShots('150; обід', shots, now: now), [null, 'обід', 'обід']);
    });
  });
}
