// Bug 2026-11-19: Monobank detail screens (card-to-card, top-up) read through a
// Latin-only OCR. The texts below keep the structure, the symbols and the
// look-alike letters of real dumps; balances, names and comments are invented.
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/ai/ai_screenshot_text.dart';
import 'package:livenow/domain/ai/ai_transfer_text.dart';
import 'package:livenow/domain/ai/model_prompts.dart';

// "Переказ на картку", -3 491.00 (the "₴" read as "∞"), a comment, balance, chart.
const _gift = '16:091\nneTpo P.\nepeka3 Ha kapTky\n18nmconaqa2026,22:23\n-3 491.00 ∞\n'
    'KoMeHT\nOncTa#TerW\n3aBaHTaKWTWpan\n3anMok\n2 150.30 会\n'
    'BuTpaTWnw177153aniBpoky\n7482号\n3 741 \ndah  cep  Bep  KOB';
// The amount is followed by a junk character; another comment.
const _mom = '16:091\nnaBno K.\nepeka3 Ha kapTky\n18nmcToaqa2026,22:22\n-3 071.00 \n'
    'HoBe KoMeHT\nOncTa#TerW\n3aBaHTaKWTWpan\n3anMok\n4 180.20 会\n'
    'BuTpaTWnw177153aniBpoky\n7482号\n3 741 \ndah  cep  Bep  KOB';
// "Поповнення картки": no sign = money came in; the balance has no space.
const _topUp = '16:091\n3 rpMBHeBoro paxyHKy XYZ\nOnOBHeHHA KapTKW\n18ncTonaqa2026,22:19\n'
    '9 026.87 会\nOnncTa#TerW\n3aBaHTaKWTwpann\n3anMWok\n7701.20号\n'
    'BinkpMTW eno3WT\nocTaBWTW 3anMTaHHy';

// A card payment in lira with its rate, as bank screens already were read.
const _lira = '19:271\nBREW CAFE\nPo3BarM Ta cnopT\n7nmcTonaqa2026,20:05\n-137.94会\n'
    'yBan1oTi150.00TL,Kypc0.9196\nOnuc Ta#Tern\n3aBaHTaKTMΦawn\n3anmok\n9801.01号';

// The same screens as the Ukrainian recogniser reads them (real Cyrillic and "₴"); every
// name and amount is invented. [sym] is what the "₴" came out as: the sign, junk or nothing.
String _cyGift(String sym) => '16:09\nПетро Р.\nПереказ на картку\n18 листопада 2026, 22:23\n-3 491.00 $sym\n'
    'Коментар\nОпис та #теги\nЗавантажити квитанцію\nЗалишок\n12 150.30 $sym\n'
    'Витрати за листопад\n27 482 $sym\n3 741 $sym';
String _cyTopUp(String sym) => '16:09\nЗ гривневого рахунку XYZ\nПоповнення картки\n'
    '18 листопада 2026, 22:19\n9 026.87 $sym\nОпис та #теги\nЗалишок\n17 701.20 $sym\n'
    'Відкрити депозит';
String _cyShop(String sym) => '16:09\nЙекмеки\n18 листопада 2026, 21:10\n-450.00 $sym\n'
    'Опис та #теги\nЗалишок\n8 100.00 $sym';
String _cyLira(String sym) => '19:27\nSunset Cafe\n18 листопада 2026, 21:10\n-45,17 $sym\n'
    'У валюті 50,00 TL, курс 0,9034\nОпис та #теги\nЗалишок\n19 801,01 $sym';

// A paper receipt (no bank markers at all).
const _paper = 'BIM BIRLESIK MAGAZALAR\nEKMEK KOY 600G 64,00\nTOPLAM 64,00 TL\n18.11.2026 19:40';

void main() {
  final now = DateTime(2026, 11, 19, 12);

  group('a Monobank detail screen without a lira amount', () {
    test('card-to-card: the main amount above the balance, not the chart', () {
      final r = parseBankScreenshot(_gift, now: now);
      expect(r.bankScreen, isTrue);
      expect(r.useAmount, 3491.0);
      expect(r.countAmount, isNull);
      expect(r.rate, isNull);
      expect(r.uahOnly, isTrue);
      expect(r.incoming, isFalse);
      expect(r.date, DateTime(2026, 11, 18, 22, 23));
      expect(r.dayGuessed, isFalse);
      expect(r.merchant, isNull, reason: 'Monobank\'s own caption is no shop');
      expect(r.hasAnything, isTrue);
      expect(r.shopAmount, 3491.0);
    });

    test('a junk character after the amount is fine', () {
      final r = parseBankScreenshot(_mom, now: now);
      expect(r.useAmount, 3071.0);
      expect(r.incoming, isFalse);
      expect(r.date, DateTime(2026, 11, 18, 22, 22));
      expect(r.merchant, isNull);
    });

    test('a top-up has no sign: incoming', () {
      final r = parseBankScreenshot(_topUp, now: now);
      expect(r.bankScreen, isTrue);
      expect(r.useAmount, 9026.87);
      expect(r.incoming, isTrue);
      expect(r.uahOnly, isTrue);
      expect(r.date, DateTime(2026, 11, 18, 22, 19));
      expect(r.merchant, isNull);
    });

    test('the new flags survive JSON, and an old row without them still reads', () {
      final back = ScreenshotReading.fromJson(parseBankScreenshot(_topUp, now: now).toJson());
      expect(back.bankScreen && back.incoming && back.uahOnly, isTrue);
      expect(back.shopAmount, 9026.87);
      final old = ScreenshotReading.fromJson({'rate': 0.9, 'use': 10.0, 'count': 11.0});
      expect(old.bankScreen || old.incoming || old.uahOnly, isFalse);
    });

    test('a lira payment keeps its rate and is not hryvnia-only', () {
      final r = parseBankScreenshot(_lira, now: now);
      expect(r.bankScreen, isTrue);
      expect(r.uahOnly, isFalse);
      expect(r.rate, 0.9196);
      expect(r.countAmount, 150.0);
      expect(r.merchant, 'Po3BarM Ta cnopT', reason: 'unchanged: the nearest line above the amount');
    });

    test('a paper receipt is no bank screen', () {
      final r = parseBankScreenshot(_paper, now: now);
      expect(r.bankScreen, isFalse);
      expect(r.hasAnything, isFalse);
    });
  });

  group('real Cyrillic: the main amount wins over the largest ₴ (the balance)', () {
    for (final sym in ['₴', '会', '']) {
      final tag = sym.isEmpty ? 'no symbol read' : '"$sym"';
      test('card-to-card, $tag', () {
        final r = parseBankScreenshot(_cyGift(sym), now: now);
        expect(r.bankScreen, isTrue);
        expect(r.useAmount, 3491.0, reason: 'not the 12 150.30 balance nor the 27 482 chart');
        expect(r.uahOnly, isTrue);
        expect(r.incoming, isFalse);
        expect(r.date, DateTime(2026, 11, 18, 22, 23));
        expect(r.merchant, isNull);
        expect(r.shopAmount, 3491.0);
      });
      test('top-up, $tag', () {
        final r = parseBankScreenshot(_cyTopUp(sym), now: now);
        expect(r.useAmount, 9026.87);
        expect(r.incoming, isTrue);
        expect(r.uahOnly, isTrue);
        expect(r.date, DateTime(2026, 11, 18, 22, 19));
        expect(r.merchant, isNull);
      });
      test('a purchase in hryvnia keeps its merchant, $tag', () {
        final r = parseBankScreenshot(_cyShop(sym), now: now);
        expect(r.useAmount, 450.0);
        expect(r.uahOnly, isTrue);
        expect(r.incoming, isFalse);
        expect(r.merchant, 'Йекмеки');
        expect(r.date, DateTime(2026, 11, 18, 21, 10));
      });
      test('a lira payment keeps its rate and lira amount, $tag', () {
        final r = parseBankScreenshot(_cyLira(sym), now: now);
        expect(r.useAmount, 45.17);
        expect(r.countAmount, 50.0);
        expect(r.rate, 0.9034);
        expect(r.uahOnly, isFalse, reason: 'a lira amount is there');
        expect(r.incoming, isFalse);
        expect(r.merchant, 'Sunset Cafe');
      });
    }

    test('the Ukrainian model reads "₴" as a digit "2" (as on the hub)', () {
      const gift = 'Переказ на картку\n18 листопада 2026, 22:23\n-3 491.00 2\nКомент\n'
          'Залишок\n12150.302\nОпис та #теги';
      final r = parseBankScreenshot(gift, now: now);
      expect(r.bankScreen, isTrue);
      expect(r.useAmount, 3491.0, reason: 'the trailing 2 is the hryvnia sign');
      expect(r.incoming, isFalse);
      expect(r.date, DateTime(2026, 11, 18, 22, 23));
      const topUp = 'Поповнення картки\n18 листопада 2026, 22:19\n9 026.872\n'
          'Опис та #теги\nЗалишок\n7701.202';
      final t = parseBankScreenshot(topUp, now: now);
      expect(t.bankScreen, isTrue);
      expect(t.useAmount, 9026.87, reason: 'a glued 2 after the decimals is the sign');
      expect(t.incoming, isTrue);
    });

    test('re-read cues: a signed amount line may be a bank screen, a receipt is not', () {
      final lost = 'Kypc\n-3 491.00 \n18 2026, 22:23';
      expect(looksLikeBankShot(lost, parseBankScreenshot(lost, now: now)), isTrue);
      expect(looksLikeBankShot(_paper, parseBankScreenshot(_paper, now: now)), isFalse);
      expect(looksLikeBankShot(_cyGift('₴'), parseBankScreenshot(_cyGift('₴'), now: now)), isTrue);
    });
  });

  group('the message sent with the screenshots', () {
    const message = '9026 грн із Фоп на монобанг гривневу карту. 3071 подарунок мамі. '
        '3491 кафе і ресторани.';
    final transport = parseBankScreenshot(
      'Sunset Cafe\n18 листопада 2026, 21:10\nСума 45,17 ₴\nУ валюті 50,00 TL\nкурс 0,9034',
      now: now,
    );
    final shots = [
      transport,
      parseBankScreenshot(_gift, now: now),
      parseBankScreenshot(_topUp, now: now),
      parseBankScreenshot(_mom, now: now),
    ];

    test('parts go by amount (9026 fits 9026.87); the transport shot stays nameless', () {
      expect(captionsForShots(message, shots, now: now), [
        null,
        'кафе і ресторани',
        'із Фоп на монобанг гривневу карту',
        'подарунок мамі',
      ]);
    });

    test('generic: false keeps the generic part away from screenshots', () {
      expect(captionsForShots('Це подарунки', shots, now: now), everyElement('Це подарунки'));
      expect(captionsForShots('Це подарунки', shots, now: now, generic: false), everyElement(isNull));
    });

    test('a part that fits no screenshot is left over for the model', () {
      final placed = placeCaptions('кава 777', shots, now: now);
      expect(placed.captions, everyElement(isNull));
      expect(placed.leftover, ['кава']);
      expect(placeCaptions(message, shots, now: now).leftover, isEmpty);
    });
  });

  group('transfers without a verb', () {
    test('parseTransferPart reads from-to with or without an amount', () {
      final r = parseTransferPart('9026 грн із Фоп на монобанг гривневу карту')!;
      expect(r.amount, 9026);
      expect(r.from, 'Фоп');
      expect(r.to, 'монобанг гривневу карту');
      final bare = parseTransferPart('із Фоп на монобанг гривневу карту')!;
      expect(bare.amount, isNull);
      expect(bare.to, 'монобанг гривневу карту');
      expect(parseTransferPart('подарунок мамі'), isNull);
      expect(parseTransferPart('кафе і ресторани'), isNull);
    });

    final names = ['(₴) ФОП', '(₴) Monobank', '(€) Monobank ФОП', 'Готівка TRY'];
    final cur = {'(₴) ФОП': 'UAH', '(₴) Monobank': 'UAH', '(€) Monobank ФОП': 'EUR', 'Готівка TRY': 'TRY'};
    List<String> resolve(String typed, {String? hint}) => resolveAccount(
      typed,
      names,
      nameOf: (n) => n,
      currencyOf: (n) => cur[n]!,
      currencyHint: hint,
    );

    test('fuzzy names, filler words and a currency word', () {
      expect(resolve('Фоп'), ['(₴) ФОП'], reason: '"ФОП", not "Monobank ФОП"');
      expect(resolve('монобанг гривневу карту'), ['(₴) Monobank']);
      expect(resolve('монобанк'), ['(₴) Monobank']);
      expect(resolve('Monobank ФОП'), ['(€) Monobank ФОП']);
      expect(resolve('рахунок ФОП'), ['(₴) ФОП']);
      expect(resolve('євро монобанк'), ['(€) Monobank ФОП']);
    });

    test('the screenshot currency splits a tie; no tie-break guesses', () {
      final both = ['(₴) Monobank', '(€) Monobank'];
      List<String> r(String t, {String? hint}) => resolveAccount(
        t,
        both,
        nameOf: (n) => n,
        currencyOf: (n) => n.contains('₴') ? 'UAH' : 'EUR',
        currencyHint: hint,
      );
      // "Monobank" is an exact match of each untagged name: two accounts.
      expect(r('монобанг'), hasLength(2));
      expect(r('монобанг', hint: 'UAH'), ['(₴) Monobank']);
    });

    test('words that are no account stay unresolved', () {
      expect(resolve('молоком'), isEmpty);
      expect(resolve('винос'), isEmpty);
      expect(resolve('Mono'), isEmpty);
    });
  });

  group('model answers are validated', () {
    test('account pick: outside the list or the same account twice is dropped', () {
      expect(parseAccountPick({'from': 2, 'to': 3}, accountCount: 3), (from: 1, to: 2));
      expect(parseAccountPick({'from': 9, 'to': 1}, accountCount: 3), (from: null, to: 0));
      expect(parseAccountPick({'from': 0, 'to': 'x'}, accountCount: 3), (from: null, to: null));
      expect(parseAccountPick({'from': 2, 'to': 2}, accountCount: 3), (from: null, to: null));
    });

    test('message parts: each part and each screenshot at most once, in range', () {
      final pairs = parseMessageShots({
        'pairs': [
          {'shot': 1, 'part': 2},
          {'shot': 1, 'part': 1},
          {'shot': 2, 'part': 2},
          {'shot': 3, 'part': 1},
          {'shot': 7, 'part': 1},
          {'shot': 2, 'part': 9},
          'junk',
        ],
      }, shotCount: 3, partCount: 2);
      expect(pairs, {0: 1, 2: 0});
      expect(parseMessageShots({'pairs': 'x'}, shotCount: 1, partCount: 1), isEmpty);
    });
  });
}
