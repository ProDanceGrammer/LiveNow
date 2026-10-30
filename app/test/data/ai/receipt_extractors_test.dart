import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/ai/llm_client.dart';
import 'package:livenow/data/ai/ocr_client.dart';
import 'package:livenow/data/ai/receipt_checks.dart';
import 'package:livenow/data/ai/receipt_extractors.dart';
import 'package:livenow/domain/ai/extracted_receipt.dart';
import 'package:livenow/domain/ai/receipt_extractor.dart';

import 'mock_llm_server.dart';

Map<String, dynamic> _receipt({
  double total = 97.5,
  double secondTotal = 65.0,
  double secondUnit = 32.5,
}) => {
  'merchant': 'BIM',
  'invoice_datetime_local': '2026-10-08T19:39:00',
  'terminal_datetime_local': null,
  'currency': 'TRY',
  'total': total,
  'tenders': [
    {'method': 'card', 'last4': '6141', 'amount': total},
  ],
  'lines': [
    {
      'raw': 'KURU KAYISI 250 G',
      'name': 'kuru kayısı',
      'line_total': 32.5,
      'qty_line': null,
      'pack': {'grams': 250, 'ml': null, 'count': null},
      'discount': 0,
      'vat_pct': 1,
      'flags': <String>[],
    },
    {
      'raw': 'SALAM HINDI FIST.50G',
      'name': 'salam',
      'line_total': secondTotal,
      'qty_line': {'qty': 2, 'unit': 'ad', 'unit_price': secondUnit},
      'pack': null,
      'discount': 0,
      'vat_pct': null,
      'flags': <String>[],
    },
  ],
  'confidence': {'overall': 0.9, 'low_confidence_fields': <String>[]},
};

void main() {
  late MockLlmServer llmServer;
  late MockOcrServer ocrServer;
  final image = Uint8List.fromList(List.generate(64, (i) => i));

  setUpAll(() => HttpOverrides.global = null);
  setUp(() async {
    llmServer = await MockLlmServer.start();
    ocrServer = await MockOcrServer.start();
    ocrServer.reply = ocrReply([
      'BIM BIRLESIK MAGAZALAR',
      'KURU KAYISI 250 G  32,50',
      '2 AD X 32,50',
      'SALAM HINDI FIST.50G  65,00',
      'TOPLAM 97,50',
    ]);
  });
  tearDown(() async {
    await llmServer.close();
    await ocrServer.close();
  });

  LlmClient llm() => LlmClient(
    baseUrl: llmServer.url,
    model: 'm',
    requestTimeout: const Duration(seconds: 5),
    retryBaseDelay: Duration.zero,
  );
  OcrLlmExtractor ocrLlm() => OcrLlmExtractor(ocr: OcrClient(baseUrl: ocrServer.url), llm: llm());

  test('OCR + LLM end to end: OCR text reaches the model, result parsed', () async {
    llmServer.enqueueJson(_receipt());
    final r = await ocrLlm().extract(image, mime: 'image/jpeg');
    expect(r.merchant, 'BIM');
    expect(r.lines.length, 2);
    expect(r.total, 97.5);
    expect(r.lowConfidenceFields, isEmpty);

    expect(ocrServer.requests.single.body, image);
    expect(ocrServer.requests.single.headers['content-type'], 'image/jpeg');
    final msgs = llmServer.chatRequests.single.json['messages'] as List;
    expect(msgs[1]['content'], contains('SALAM HINDI FIST.50G  65,00'));
    final schema = llmServer.chatRequests.single.json['response_format']['json_schema']['schema'];
    expect(schema['required'], contains('lines'));
  });

  test('arithmetic beats the model: wrong line_total is repaired and flagged', () async {
    // 2 x 32.50 = 65.00, the model said 56.00 -> total 88.50 mismatch.
    llmServer.enqueueJson(_receipt(secondTotal: 56.0, total: 97.5));
    final r = await ocrLlm().extract(image);
    expect(r.lines[1].lineTotal, 65.0);
    expect(r.lines[1].flags, contains('repaired_line_total'));
    expect(r.lowConfidenceFields, contains('lines[1].line_total'));
    expect(llmServer.chatRequests.length, 1); // sums now match: no retry
  });

  test('sum mismatch triggers ONE repair retry; better retry is kept', () async {
    final bad = _receipt(total: 120.0); // lines add to 97.5
    llmServer.enqueueJson(bad);
    llmServer.enqueueJson(_receipt(total: 97.5));
    final r = await ocrLlm().extract(image);
    expect(r.total, 97.5);
    expect(llmServer.chatRequests.length, 2);
    final retryMsgs = llmServer.chatRequests[1].json['messages'] as List;
    expect(retryMsgs.last['content'], contains('97.50'));
    expect(retryMsgs.last['content'], contains('120.00'));
  });

  test('retry that does not help keeps the first reading and flags the total', () async {
    llmServer.enqueueJson(_receipt(total: 120.0));
    llmServer.enqueueJson(_receipt(total: 130.0));
    final r = await ocrLlm().extract(image);
    expect(r.total, 120.0);
    expect(r.lowConfidenceFields, contains('total'));
    expect(llmServer.chatRequests.length, 2);
  });

  test('a failing retry does not lose the first reading', () async {
    llmServer.enqueueJson(_receipt(total: 120.0));
    llmServer.enqueueContent('garbage');
    llmServer.enqueueContent('garbage');
    final r = await ocrLlm().extract(image);
    expect(r.lines.length, 2);
    expect(r.lowConfidenceFields, contains('total'));
  });

  test('empty OCR output: no model call, ReceiptExtractionException', () async {
    ocrServer.reply = ocrReply(['   ']);
    await expectLater(ocrLlm().extract(image), throwsA(isA<ReceiptExtractionException>()));
    expect(llmServer.chatRequests, isEmpty);
  });

  test('OCR service error is a typed exception', () async {
    ocrServer.status = 500;
    await expectLater(ocrLlm().extract(image), throwsA(isA<AiBadResponseException>()));
  });

  test('VLM path sends the picture as a base64 image part, no OCR call', () async {
    llmServer.enqueueJson(_receipt());
    final r = await VlmExtractor(llm: llm()).extract(image, mime: 'image/png');
    expect(r.lines.length, 2);
    expect(ocrServer.requests, isEmpty);
    final msgs = llmServer.chatRequests.single.json['messages'] as List;
    final parts = msgs[1]['content'] as List;
    expect(parts[1]['image_url']['url'], 'data:image/png;base64,${base64Encode(image)}');
  });

  test('hybrid without a VLM equals OCR + LLM', () async {
    llmServer.enqueueJson(_receipt());
    final r = await HybridExtractor(primary: ocrLlm()).extract(image);
    expect(r.lines.length, 2);
    expect(llmServer.chatRequests.length, 1);
  });

  test('hybrid: mismatching line is flagged; the value found in the OCR text wins', () async {
    // OCR text has 32,50 and 65,00. Primary read 35.50 (not in the text), the VLM read 32.50.
    final primary = _receipt();
    (primary['lines'] as List)[0]['line_total'] = 35.5;
    primary['total'] = 100.5;
    llmServer.enqueueJson(primary); // OCR+LLM answer (sums match: no retry)
    llmServer.enqueueJson(_receipt()); // VLM answer
    final h = HybridExtractor(
      primary: ocrLlm(),
      vlm: VlmExtractor(llm: llm()),
    );
    final r = await h.extract(image);
    expect(r.lines[0].lineTotal, 32.5);
    expect(r.total, 97.5);
    expect(r.lowConfidenceFields, containsAll(['lines[0].line_total', 'total']));
  });

  test('reconcileReadings: pure behaviour', () {
    final a = ExtractedReceipt.fromJson(_receipt()..['total'] = 99.0);
    final b = ExtractedReceipt.fromJson(_receipt());
    final r = reconcileReadings(a, b, 'TOPLAM 97,50');
    expect(r.total, 97.5); // 97.50 is in the text, 99.00 is not
    expect(r.lowConfidenceFields, contains('total'));

    final shorter = ExtractedReceipt.fromJson(_receipt()..['lines'] = [(_receipt()['lines'] as List).first]);
    expect(reconcileReadings(a, shorter, '').lowConfidenceFields, contains('lines.count'));
  });

  test('hybrid: a VLM failure falls back to the primary and says so', () async {
    llmServer.enqueueJson(_receipt()); // primary
    // VLM gets an empty queue -> 500s
    final h = HybridExtractor(
      primary: ocrLlm(),
      vlm: VlmExtractor(
        llm: LlmClient(baseUrl: llmServer.url, model: 'v', maxRetries: 0, retryBaseDelay: Duration.zero),
      ),
    );
    final r = await h.extract(image);
    expect(r.lowConfidenceFields, contains('vlm_unavailable'));
    expect(r.lines.length, 2);
  });

  test('numberTokens understands thousand and decimal separators', () {
    expect(numberTokens('TOPLAM 1.234,50 x 16.50 y 7,5 z 319'), containsAll([123450, 1650, 750, 31900]));
  });

  test('OcrClient: health and parsed lines', () async {
    final c = OcrClient(baseUrl: ocrServer.url);
    expect(await c.health(), isTrue);
    final r = await c.ocr(image);
    expect(r.engine, 'mock');
    expect(r.lines.first.x1, 700);
    expect(r.text.split('\n').length, 5);
    expect(await OcrClient(baseUrl: 'http://127.0.0.1:1').health(), isFalse);
  });
}
