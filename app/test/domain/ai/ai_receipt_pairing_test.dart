// A receipt whose TOPLAM/KREDI rows come after the 14th OCR row must still pair with
// the bank screenshot of the same payment (the first version only looked at the head).
// All texts are invented.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/ids.dart';
import 'package:livenow/data/ai/llm_client.dart';
import 'package:livenow/data/ai/ocr_client.dart';
import 'package:livenow/data/ai/receipt_extractors.dart';
import 'package:livenow/domain/ai/ai_protocol.dart';
import 'package:livenow/domain/postpone_rules.dart';

import '../../data/ai/mock_llm_server.dart';
import 'ai_runner_support.dart';

const _tl = 'ТL';

List<String> _shot({
  required String name,
  required String chip,
  required String date,
  required String amount,
  required String shop,
  required String rate,
  required String balance,
}) => [
  '16:30',
  name,
  chip,
  date,
  amount,
  'У валюті $shop $_tl, курс $rate',
  'Опис та #теги',
  'Завантажити файл',
  'Залишок',
  balance,
  'VISA  Оплата карткою через терминал',
];

void main() {
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

  /// 9 header rows, 5 items (rows 10..14 are the 14th row and beyond), then the totals.
  Map<String, Object> longReceipt() {
    final rows = <List<(String, double, double)>>[
      [('ORNEK MARKET TICARET A.S.', 100, 250)],
      [('TEST MAH. DENEME SOK.', 100, 220)],
      [('NO 7', 100, 60)],
      [('TESTKENT ANTALYA', 100, 180)],
      [('VERGI NO 1234567890', 100, 220)],
      [('ORNEK KURUMLAR V.D', 100, 220)],
      [('TARIH : 19/10/2026', 100, 200)],
      [('SAAT : 16:23:03', 100, 180)],
      [('FIS NO : 0042', 100, 150)],
      [('SUT 1', 120, 90), ('%01', 370, 25), ('*59,00', 450, 80)],
      [('DANA KIYMA', 120, 90), ('%01', 370, 25), ('*340,00', 450, 80)],
      [('EKMEK', 120, 90), ('%01', 370, 25), ('*20,00', 450, 80)],
      [('MAKARNA', 120, 90), ('%01', 370, 25), ('*179,00', 450, 80)],
      [('EKMEK', 120, 90), ('%01', 370, 25), ('*20,00', 450, 80)],
      [('TOPKDV', 120, 100), ('*6,02', 450, 70)],
      [('TOPLAM', 120, 100), ('*618,00', 450, 80)],
      [('KREDI', 120, 100), ('*618,00', 450, 80)],
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

  final bankShot = _shot(
    name: 'TESTKENT ORNEK MAH',
    chip: 'Продукти та супермаркети',
    date: '19 жовтня 2026, 16:23',
    amount: '-566.15',
    shop: '618.00',
    rate: '0.9161',
    balance: '712.40',
  );
  final otherShot = _shot(
    name: 'Громадський транспорт',
    chip: 'Подорожі',
    date: '19 жовтня 2026, 10:10',
    amount: '-45.86',
    shop: '50.00',
    rate: '0.9172',
    balance: '1 200.10',
  );
  const receiptUk = ['ORNEK MARKET TICARET A.S.', 'TARIH : 19/10/2026'];

  test('a screenshot whose lira sum is the receipt total printed after row 14 pairs with that receipt', () async {
    ocrServer.healthLangs = ['default', 'uk'];
    ocrServer.replyForLang = (image, lang) {
      final m = image.first;
      if (m == 1) return lang == 'uk' ? ocrReply(receiptUk) : longReceipt();
      if (lang == 'uk') return ocrReply(m == 2 ? bankShot : otherShot);
      return ocrReply(['16:30', '-1.00']);
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

    final parent = await env.sendPhotos([1, 2, 3]);
    await env.drain();

    expect(
      (await env.message(parent, AiMessageKind.text))!.body,
      contains('Знайшов 1 чеків і 2 скріншотів'),
    );
    final receipt = await env.draft(deriveId(parent, 'job', 0));
    expect(receipt.json['currency'], 'TRY');
    expect(receipt.sum['expected'], 618.0);
    expect(receipt.json['fx_source'], 'screenshot', reason: 'the bank screen of the same payment gave the rate');
    // The only other job is the unrelated screenshot: no purchase for the 618 TL screen.
    final other = await env.draft(deriveId(parent, 'job', 1));
    expect(other.lines.single['amount'], 50.0);
  });
}
