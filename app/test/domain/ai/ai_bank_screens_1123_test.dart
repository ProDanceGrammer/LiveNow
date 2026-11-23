// Bug 2026-11-23: nine photos (eight Monobank screens, one BIM receipt) and the message
// "920 грн - айдат. 117 і 49 грн - кафе і ресторани." came out as eight "receipts". The texts
// below are the Ukrainian recogniser's real readings with the balances, names, card digits,
// receipt ids and the sums' small digits ALTERED (the repo is public). The recorded originals
// live in the git-ignored claude_dev/ai/fixtures/photos_1123/.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/ids.dart';
import 'package:livenow/data/ai/llm_client.dart';
import 'package:livenow/data/ai/ocr_client.dart';
import 'package:livenow/domain/ai/ai_protocol.dart';
import 'package:livenow/domain/ai/ai_screenshot_text.dart';
import 'package:livenow/domain/ai/receipt_row_builder.dart';
import 'package:livenow/domain/postpone_rules.dart';

import '../../data/ai/mock_llm_server.dart';
import 'ai_runner_support.dart';
import 'ai_test_support.dart' show Seed;
import 'package:livenow/data/ai/receipt_extractors.dart';
import 'package:livenow/domain/budget_rules.dart' show BudgetUnit;

/// "ТL" is read with a CYRILLIC "Т" by the Ukrainian model.
const _tl = 'ТL';

/// One Monobank detail screen as the Ukrainian model reads it.
List<String> screen({
  required String name,
  required String chip,
  required String date,
  required String amount,
  String? shop,
  String? rate,
  String balance = '3 100.31',
  String? cashback,
  List<String> map = const [],
}) => [
  '19:18',
  ...map,
  name,
  chip,
  date,
  amount,
  if (shop != null) 'У валюті $shop $_tl, курс $rate',
  'Опис та #теги',
  'Завантажити файл',
  if (cashback == null) 'Залишок' else 'Залишок  Кешбек',
  if (cashback == null) balance else '$balanceº  $cashback',
  'VISA  Оплата карткою через терминал',
  'Витратили 321 е за пивроку',
  '183.44',
  'чер  cep  ЛИС',
];

final _odeal = screen(
  name: 'ODEALI/ASIA PACIFIC',
  chip: 'Продукти та супермаркети',
  date: '22 листопада 2026, 17:28',
  amount: '-117.132',
  shop: '130.00',
  rate: '0.9010',
  cashback: '1.17',
);
final _transfer = [
  '19:19',
  'Іван К.',
  'Переказ на картку',
  '12 листопада 2026, 16:37',
  '-920.00',
  'Опис та #теги',
  'Завантажити файл',
  'Залишок',
  '5 000.40',
  'Витратили 11 153 е за пивроку',
  '5998',
  'чер  ЛИС  cep  ЛИС',
];
List<String> _metro(String date, String balance, {String amount = '-45.  .862'}) => screen(
  name: 'Громадський транспорт',
  chip: 'Подорожі',
  date: date,
  amount: amount,
  shop: '50.00',
  rate: '0.9172',
  balance: balance,
  map: const ['Kum', '19:19  123.Sk  125.Sk.', 'Menderes Blv.', 'arbaros Cd.  130.', '.sk  36.Sk'],
);

final _burger = screen(
  name: 'Burger King',
  chip: 'Кафе та ресторани',
  date: '22 листопада 2026, 17:00',
  amount: '-49.',
  shop: '55.00',
  rate: '0.8998',
  balance: '4 000.44',
  cashback: '0.98',
  map: const ['Tokus Cd.', '19:18  Yауla  Tas', 'Tevfikiye Cd.', 'BURGER  Na', 'KING'],
);
final _bimShot = screen(
  name: 'BiM',
  chip: 'Продукти та супермаркети',
  date: '12 листопада 2026, 18:53',
  amount: '-63.292',
  shop: '69.33',
  rate: '0.9128',
  balance: '7 000.39',
  cashback: '0.63',
  map: const ['BIM'],
);

// A paper receipt read in Ukrainian: no balance line, no bank words.
const _bimUk = [
  'E-Arsiv Fatura',
  'BIM BIRLESIK MAGAZALAR A.S.',
  'Buyük MukellefLer VDM 1750000000',
  'FATURA NO:T112026000000001  12.11.2026 18:53  Sira No : 290',
  '1.175 kg X 59.00  ELMA GACA  *69.33  *0.69',
  'TOPLAM KDV  Odenecek KDV Dahil Tutar  *69.33  *69.33',
];

void main() {
  final now = DateTime(2026, 11, 23, 20, 0);

  group('one Monobank screen read in Ukrainian', () {
    test('a card payment: split amount, cashback beside the balance, lira and rate, chip', () {
      final r = parseBankScreenshot(_odeal.join('\n'), now: now);
      expect(r.bankScreen, isTrue);
      expect(r.useAmount, 117.13, reason: '"-117.132": the trailing 2 is the hryvnia sign');
      expect(r.countAmount, 130.0, reason: 'the Cyrillic "Т" of "ТL" still reads as lira');
      expect(r.rate, 0.9010);
      expect(r.uahOnly, isFalse);
      expect(r.incoming, isFalse);
      expect(r.date, DateTime(2026, 11, 22, 17, 28));
      expect(r.merchant, 'ODEALI/ASIA PACIFIC', reason: 'the name line, not the category chip');
      expect(r.bankCategory, 'Продукти та супермаркети');
    });

    test('the integer and the small decimals are split by dots and spaces', () {
      double? amountOf(String line) {
        final lines = [
          'Магазин Х',
          'Продукти та супермаркети',
          '12 листопада 2026, 18:15',
          line,
          'Опис та #теги',
          'Залишок',
          '100.00',
        ];
        return parseBankScreenshot(lines.join('\n'), now: now).useAmount;
      }

      expect(amountOf('-45.  .862'), 45.86);
      expect(amountOf('-45.  .86'), 45.86);
      expect(amountOf('-920 .00'), 920.0);
      expect(amountOf('-117 .13 ₴'), 117.13);
      expect(amountOf('-1 117.13 2'), 1117.13);
      expect(amountOf('-3 491.00'), 3491.0);
    });

    test('lost decimals ("-49.") come back from the lira amount and the rate', () {
      final r = parseBankScreenshot(_burger.join('\n'), now: now);
      expect(r.useAmount, 49.49, reason: '55.00 TL x 0.8998');
      expect(r.countAmount, 55.0);
      expect(r.merchant, 'Burger King');
      expect(r.bankCategory, 'Кафе та ресторани');
      // Without a rate there is nothing to restore them from: the whole amount stands.
      const lone = 'Кав\'ярня\nКафе та ресторани\n22 листопада 2026, 17:00\n-49.\nОпис та #теги\nЗалишок\n4000.44';
      expect(parseBankScreenshot(lone, now: now).useAmount, 49.0);
    });

    test('the balance row shared with Кешбек is the stop line; the cashback is never the amount', () {
      final r = parseBankScreenshot(_burger.join('\n'), now: now);
      expect(r.bankScreen, isTrue);
      // Only the cashback card is above nothing: with no main amount line there is none.
      const noMain = '19:18\nМагазин\nКафе та ресторани\n22 листопада 2026, 17:00\nЗалишок  Кешбек\n4362.44  0.98';
      final n = parseBankScreenshot(noMain, now: now);
      expect(n.bankScreen, isFalse);
      expect(n.useAmount, isNull);
    });

    test('a transfer: hryvnia only, no shop, and Monobank\'s caption is no category', () {
      final r = parseBankScreenshot(_transfer.join('\n'), now: now);
      expect(r.useAmount, 920.0);
      expect(r.uahOnly, isTrue);
      expect(r.incoming, isFalse);
      expect(r.merchant, isNull);
      expect(r.bankCategory, isNull);
      expect(r.date, DateTime(2026, 11, 12, 16, 37));
      const topUp = 'Іван К.\nПоповнення картки\n12 листопада 2026, 16:37\n920.00\n'
          'Опис та #теги\nЗалишок\n5 000.40';
      final t = parseBankScreenshot(topUp, now: now);
      expect(t.incoming, isTrue);
      expect(t.bankCategory, isNull);
    });

    test('a public-transport screen: shop name above the chip, map noise ignored', () {
      final r = parseBankScreenshot(_metro('12 листопада 2026, 18:15', '7 201.54').join('\n'), now: now);
      expect(r.useAmount, 45.86);
      expect(r.countAmount, 50.0);
      expect(r.merchant, 'Громадський транспорт');
      expect(r.bankCategory, 'Подорожі');
    });

    test('a Latin reading that lost the chip keeps the nearest line as the shop, no category', () {
      const latin = '19:18\nODEAL//ASIA PACIFIC\n22  2026, 17:28\n-117.13\nЗалишок\n100.00\n#теги';
      final r = parseBankScreenshot(latin, now: now);
      expect(r.bankCategory, isNull);
      expect(r.merchant, 'ODEAL//ASIA PACIFIC');
    });

    test('the category survives the JSON round trip, and an old row without it still loads', () {
      final r = parseBankScreenshot(_burger.join('\n'), now: now);
      final back = ScreenshotReading.fromJson(jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>);
      expect(back.bankCategory, 'Кафе та ресторани');
      expect(ScreenshotReading.fromJson({'use': 5.0, 'bank_category': 7}).bankCategory, isNull);
      expect(ScreenshotReading.fromJson({'use': 5.0}).bankCategory, isNull);
    });
  });

  group('several amounts in one message part', () {
    final shots = [
      parseBankScreenshot(_metro('12 листопада 2026, 18:15', '7 201.54').join('\n'), now: now),
      parseBankScreenshot(_odeal.join('\n'), now: now),
      parseBankScreenshot(_transfer.join('\n'), now: now),
      parseBankScreenshot(_burger.join('\n'), now: now),
    ];

    List<String?> names(String message) => captionsForShots(message, shots, now: now);

    test('"117 і 49 грн - кафе і ресторани" names both; 49 is the 49.49 one, not the 50 TL one', () {
      expect(
        names('920 грн - айдат.\n117 і 49 грн - кафе і ресторани.'),
        [null, 'кафе і ресторани', 'айдат', 'кафе і ресторани'],
      );
    });

    test('a comma and "та" join amounts too, a date\'s comma does not', () {
      expect(names('117, 49 - кафе і ресторани'), [null, 'кафе і ресторани', null, 'кафе і ресторани']);
      expect(names('117 та 49 грн кафе'), [null, 'кафе', null, 'кафе']);
      expect(names('117 грн, 49 грн - кафе'), [null, 'кафе', null, 'кафе']);
      // One amount stays as before.
      expect(names('920 грн - айдат'), [null, null, 'айдат', null]);
    });
  });

  group('BIM receipt total', () {
    ReceiptWord w(String text, double x, double y, double width) => ReceiptWord.fromQuad(text, [
      [x, y],
      [x + width, y],
      [x + width, y + 10],
      [x, y + 10],
    ]);

    test('"Odenecek KDV Dahil Tutar" is the total, "TOPLAM KDV" is the tax', () {
      final rows = <List<(String, double, double)>>[
        [('E-Arsiv Fatura', 150, 100)],
        [('BIM BIRLESIK MAGAZALAR A.S.', 100, 250)],
        [('FATURA NO:T112026000000001', 100, 220), ('12.11.2026 18:53', 360, 100)],
        [('1.175 kg X 59.00', 120, 150)],
        // The Latin model dropped the "%" of "%1.": a lone "1." follows the name.
        [('ELMA GALA', 120, 90), ('1.', 370, 15), ('*69.33', 450, 80)],
        [('TOPLAM KDV', 120, 100), ('*0.69', 450, 70)],
        [('Odenecek KDV Dahil Tutar', 120, 250), ('*69.33', 450, 80)],
        [('Banka Kredi Karti (1)', 120, 200), ('*69.33', 450, 80)],
        [('IS BANKASI', 120, 100)],
        [('POS:1 - 297519 - H**** C****', 120, 260), ('951038911', 390, 70), ('9510389.11', 470, 90)],
      ];
      final words = <ReceiptWord>[
        for (var i = 0; i < rows.length; i++)
          for (final (t, x, width) in rows[i]) w(t, x, 250.0 + 21 * i, width),
      ];
      final r = rebuildReceipt(words)!;
      expect(r.receipt.total, 69.33);
      expect(r.consistent, isTrue);
      expect(r.receipt.lines.last.name, 'ELMA GALA', reason: 'the lone "1." is the VAT column');
      expect(r.receipt.lines.last.vatPct, 1.0);
      expect(r.receipt.tenders.map((t) => t.amount), [69.33], reason: 'the terminal number is no payment');
    });
  });

  group('the nine photos of the failed message, replayed', () {
    late RunnerEnv env;
    late MockLlmServer llmServer;
    late MockOcrServer ocrServer;

    setUpAll(() {
      HttpOverrides.global = null;
      initPostponeTimeZoneData();
    });
    setUp(() async {
      env = RunnerEnv();
      llmServer = await MockLlmServer.start();
      ocrServer = await MockOcrServer.start();
    });
    tearDown(() async {
      await env.close();
      await llmServer.close();
      await ocrServer.close();
    });

    Map<String, Object> item(String text, double x, double y, double w) => {
      'text': text,
      'quad': [
        [x, y],
        [x + w, y],
        [x + w, y + 10],
        [x, y + 10],
      ],
      'confidence': 0.9,
    };

    /// The default (Latin) recogniser's word boxes of the receipt.
    Map<String, Object> bimDefault() {
      final rows = <List<(String, double, double)>>[
        [('E-Arsiv Fatura', 150, 100)],
        [('BIM BIRLESIK MAGAZALAR A.S.', 100, 250)],
        [('FATURA NO:T112026000000001', 100, 220), ('12.11.2026 18:53', 360, 100)],
        [('1.175 kg X 59.00', 120, 150)],
        [('ELMA GALA', 120, 90), ('%1.', 370, 25), ('*69.33', 450, 80)],
        [('TOPLAM KDV', 120, 100), ('*0.69', 450, 70)],
        [('Odenecek KDV Dahil Tutar', 120, 250), ('*69.33', 450, 80)],
        [('Banka Kredi Karti (1)', 120, 200), ('*69.33', 450, 80)],
      ];
      return {
        'engine': 'mock',
        'width': 800,
        'height': 1600,
        'lines': [
          for (var i = 0; i < rows.length; i++)
            {
              'text': rows[i].map((c) => c.$1).join('  '),
              'box': [10, 20 + i * 30, 700, 40 + i * 30],
              'confidence': 0.95,
            },
        ],
        'items': [
          for (var i = 0; i < rows.length; i++)
            for (final (t, x, width) in rows[i]) item(t, x, 250.0 + 21 * i, width),
        ],
      };
    }

    /// Photos 1..9: ODEAL, BIM receipt, transfer, metro 18:15, metro 21:42, Burger King,
    /// metro 21:42, metro 18:15, BIM card screen.
    final photos = <int, List<String>>{
      1: _odeal,
      2: _bimUk,
      3: _transfer,
      4: _metro('12 листопада 2026, 18:15', '7 201.54'),
      5: _metro('12 листопада 2026, 21:42', '7 000.67', amount: '-45.  .86'),
      6: _burger,
      7: _metro('12 листопада 2026, 21:42', '7 046.53'),
      8: _metro('12 листопада 2026, 18:15', '7 155.68'),
      9: _bimShot,
    };

    test('1 receipt and 8 screenshots; every screen is a purchase with the right amount and day', () async {
      ocrServer.healthLangs = ['default', 'uk'];
      ocrServer.replyForLang = (image, lang) {
        final m = image.first;
        if (lang == 'uk') return ocrReply(photos[m]!);
        if (m == 2) return bimDefault();
        // A Latin read of a bank screen is never used: it would lose the Cyrillic.
        return ocrReply(['19:19', '12  2026, 18:15', '-1.00']);
      };
      final llm = LlmClient(
        baseUrl: llmServer.url,
        model: 'm',
        requestTimeout: const Duration(seconds: 5),
        maxRetries: 0,
        retryBaseDelay: Duration.zero,
      );
      await env.init(
        ocr: OcrClient(baseUrl: ocrServer.url),
        realExtractor: OcrLlmExtractor(ocr: OcrClient(baseUrl: ocrServer.url), llm: llm),
      );
      await env.rules.set('card.default', {'account_id': env.monoAcc});
      final seed = Seed(env.db);
      final group = await seed.group('🍽 Кафе та ресторани');
      final cafe = await seed.leaf('Кафе', price: 1, parentId: group, unit: BudgetUnit.piece);
      final rest = await seed.leaf('Ресторани', price: 1, parentId: group, unit: BudgetUnit.piece);
      final travel = await seed.group('Подорожі');
      final taxi = await seed.leaf('Таксі', price: 1, parentId: travel, unit: BudgetUnit.piece);

      final parent = await env.sendPhotos(
        [for (var m = 1; m <= 9; m++) m],
        caption: '920 грн - айдат.\n117 і 49 грн - кафе і ресторани.',
      );
      await env.drain();

      expect(
        (await env.message(parent, AiMessageKind.text))!.body,
        contains('Знайшов 1 чеків і 8 скріншотів'),
      );
      // Screens cost one (Ukrainian) pass, the receipt two: uk 9 + default 1 (+ the extractor's own).
      expect(ocrServer.callsWithLang('uk'), greaterThanOrEqualTo(9));
      final kid = [for (var i = 0; i < 8; i++) deriveId(parent, 'job', i)];
      for (final k in kid) {
        expect((await env.job(k)).error, anyOf(isNull, isEmpty), reason: k);
      }

      Future<List<String>> optionIds(String job) async {
        final q = jsonDecode((await env.message(job, AiMessageKind.question))!.contentJson)['questions'] as List;
        return [for (final o in (q.first as Map)['option_ids'] as List) '$o'];
      }

      // `at` is UTC (the app zone is UTC+3). The receipt: the lira total, with the BIM card screen (69.33 TL) giving the rate.
      final receipt = await env.draft(kid[0]);
      expect(receipt.json['currency'], 'TRY');
      expect(receipt.sum['expected'], 69.33, reason: '"Odenecek KDV Dahil Tutar" is the total');
      expect(receipt.sum['ok'], isTrue);
      expect(receipt.json['fx_source'], 'screenshot');

      // 117.13: "кафе і ресторани" is a group: asked inside it.
      final odeal = await env.draft(kid[1]);
      expect(odeal.lines.single['name'], 'кафе і ресторани');
      expect(odeal.json['at'], startsWith('2026-11-22T14:28'));
      expect(await optionIds(kid[1]), [cafe, rest, 'create:$group']);

      // 920: a transfer in hryvnia named by the message, on its own day.
      final transfer = await env.draft(kid[2]);
      expect(transfer.lines.single['name'], 'айдат');
      expect(transfer.lines.single['amount'], 920.0);
      expect(transfer.json['currency'], 'UAH', reason: 'a hryvnia-only screen is never lira');
      expect(transfer.json['at'], startsWith('2026-11-12T13:37'));

      // The four public-transport screens: named by the shop, the bank's label is the hint.
      for (final k in [kid[3], kid[4], kid[6], kid[7]]) {
        final d = await env.draft(k);
        expect(d.lines.single['name'], 'Громадський транспорт');
        expect(d.lines.single['amount'], 50.0);
        expect(d.json['currency'], 'TRY');
        expect(d.json['source']['named'], isNot(true), reason: 'the label is a hint, not the user\'s words');
        expect(await optionIds(k), [taxi, 'create:$travel'], reason: 'asked inside the bank\'s "Подорожі"');
      }
      expect((await env.draft(kid[3])).json['at'], startsWith('2026-11-12T15:15'));
      expect((await env.draft(kid[4])).json['at'], startsWith('2026-11-12T18:42'));

      // 49.49: the second amount of the same message part.
      final burger = await env.draft(kid[5]);
      expect(burger.lines.single['name'], 'кафе і ресторани');
      expect(burger.json['at'], startsWith('2026-11-22T14:00'));
      expect(await optionIds(kid[5]), [cafe, rest, 'create:$group']);
    });
  });

  group('what is left of the message for the receipts', () {
    final now = DateTime(2026, 11, 23, 19, 30);
    const shots = [
      ScreenshotReading(useAmount: 920, bankScreen: true, uahOnly: true),
      ScreenshotReading(useAmount: 117.13, countAmount: 130, rate: 0.901, bankScreen: true),
      ScreenshotReading(useAmount: 49.49, countAmount: 55, rate: 0.8998, bankScreen: true),
    ];
    test('parts that took screenshots are not left for the receipt', () {
      final p = placeCaptions(
        '920 грн - айдат.\n117 і 49 грн - кафе і ресторани.',
        shots,
        now: now,
        generic: false,
      );
      expect(p.captions, ['айдат', 'кафе і ресторани', 'кафе і ресторани']);
      expect(p.leftover, isEmpty);
    });
    test('a part without an amount stays for the receipt when not generic', () {
      final p = placeCaptions('920 грн - айдат. яблука для мами', shots, now: now, generic: false);
      expect(p.captions.first, 'айдат');
      expect(p.captions.skip(1), everyElement(isNull));
      expect(p.leftover, ['яблука для мами']);
    });
  });
}
