import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/ai/ocr_dump.dart';
import 'package:livenow/domain/ai/extracted_receipt.dart';
import 'package:livenow/domain/ai/receipt_row_builder.dart';

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ocr_dump_test');
    OcrDump.directoryOverride = tmp;
  });
  tearDown(() {
    OcrDump.directoryOverride = null;
    tmp.deleteSync(recursive: true);
  });

  const word = ReceiptWord(
    text: '*75.5',
    x0: 1,
    y0: 2,
    x1: 30,
    y1: 12,
    slope: 0.04,
    boxHeight: 10,
  );

  test('the dump replays: words survive a JSON round trip', () async {
    final f = await OcrDump.write(
      [word],
      'ocr text',
      const ExtractedReceipt(total: 5, lines: []),
    );
    expect(f, isNotNull);
    final j = jsonDecode(f!.readAsStringSync()) as Map<String, dynamic>;
    final back = ReceiptWord.fromJson(
      Map<String, dynamic>.from((j['words'] as List).single as Map),
    );
    expect(back.text, '*75.5');
    expect(back.slope, 0.04);
    expect(back.boxHeight, 10);
    expect(j['ocr_text'], 'ocr text');
  });

  test('only the newest ${OcrDump.keep} dumps are kept', () async {
    const r = ExtractedReceipt(lines: []);
    final dir = Directory('${tmp.path}${Platform.pathSeparator}ai_debug')
      ..createSync(recursive: true);
    for (var i = 0; i < OcrDump.keep + 5; i++) {
      File('${dir.path}${Platform.pathSeparator}ocr-2020-01-01-$i.json')
          .writeAsStringSync('{}');
    }
    await OcrDump.write([word], '', r);
    expect(dir.listSync().length, OcrDump.keep);
  });

  test('no words: nothing is written', () async {
    expect(await OcrDump.write(const [], '', const ExtractedReceipt(lines: [])), isNull);
  });
}
