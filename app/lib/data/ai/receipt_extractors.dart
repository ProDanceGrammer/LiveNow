/// The [ReceiptExtractor] implementations. Only [OcrLlmExtractor] runs on the CPU
/// hub; [VlmExtractor] needs a vision model (mock-tested until a GPU or enough RAM
/// exists); [HybridExtractor] compares the two.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../domain/ai/extracted_receipt.dart';
import '../../domain/ai/receipt_extractor.dart';
import 'llm_client.dart';
import 'ocr_client.dart';
import 'receipt_checks.dart';

/// OCR text -> text model with the receipt schema -> arithmetic repair.
class OcrLlmExtractor implements ReceiptExtractor {
  OcrLlmExtractor({required this.ocr, required this.llm, this.cancel});

  final OcrClient ocr;
  final LlmClient llm;
  final AiCancelToken? cancel;

  @override
  Future<ExtractedReceipt> extract(Uint8List image, {String? mime}) async =>
      (await extractWithText(image, mime: mime)).receipt;

  /// Like [extract], also returns the OCR text (the hybrid reconciles against it).
  Future<({ExtractedReceipt receipt, String ocrText})> extractWithText(
    Uint8List image, {
    String? mime,
  }) async {
    // Sequential on purpose: OCR finishes before the model loads (8 GB RAM).
    final read = await ocr.ocr(image, mime: mime, cancel: cancel);
    if (read.isEmpty) {
      throw const ReceiptExtractionException('OCR found no text in the picture');
    }
    final messages = [
      LlmMessage.system(receiptExtractionSystemPrompt),
      LlmMessage.user(receiptExtractionUserPrompt(read.text)),
    ];
    var receipt = await _ask(llm, messages, cancel);
    receipt = repairArithmetic(receipt);
    if (sumMismatch(receipt)) receipt = await _retryOnce(llm, messages, receipt, cancel);
    return (receipt: receipt, ocrText: read.text);
  }
}

/// A vision model reads the picture directly (image as a base64 `image_url`).
class VlmExtractor implements ReceiptExtractor {
  VlmExtractor({required this.llm, this.cancel});

  final LlmClient llm;
  final AiCancelToken? cancel;

  @override
  Future<ExtractedReceipt> extract(Uint8List image, {String? mime}) async {
    final messages = [
      LlmMessage.system(receiptExtractionSystemPrompt),
      LlmMessage.userWithImage(
        receiptVisionUserPrompt,
        image,
        mime: mime ?? 'image/jpeg',
      ),
    ];
    var receipt = repairArithmetic(await _ask(llm, messages, cancel));
    if (sumMismatch(receipt)) receipt = await _retryOnce(llm, messages, receipt, cancel);
    return receipt;
  }
}

/// Runs OCR + text model and, when a [vlm] is configured, the vision model too.
/// Where both read the same line, a number that also appears in the OCR text
/// wins; every disagreement is listed in `lowConfidenceFields`. Without a [vlm]
/// it is just the OCR + text model.
class HybridExtractor implements ReceiptExtractor {
  HybridExtractor({required this.primary, this.vlm});

  final OcrLlmExtractor primary;
  final VlmExtractor? vlm;

  @override
  Future<ExtractedReceipt> extract(Uint8List image, {String? mime}) async {
    final a = await primary.extractWithText(image, mime: mime);
    final v = vlm;
    if (v == null) return a.receipt;
    final ExtractedReceipt b;
    try {
      b = await v.extract(image, mime: mime);
    } on AiException {
      return copyReceipt(
        a.receipt,
        lowConfidenceFields: [...a.receipt.lowConfidenceFields, 'vlm_unavailable'],
      );
    }
    return reconcileReadings(a.receipt, b, a.ocrText);
  }
}

/// Merges the OCR + text reading [a] with the vision reading [b] (see
/// [HybridExtractor]). Public for tests.
ExtractedReceipt reconcileReadings(
  ExtractedReceipt a,
  ExtractedReceipt b,
  String ocrText,
) {
  final seen = numberTokens(ocrText);
  final low = [...a.lowConfidenceFields];
  var total = a.total;
  if (a.total != null && b.total != null && cents(a.total!) != cents(b.total!)) {
    if (!seen.contains(cents(a.total!)) && seen.contains(cents(b.total!))) {
      total = b.total;
    }
    low.add('total');
  }
  if (a.lines.length != b.lines.length) {
    low.add('lines.count');
    return copyReceipt(a, total: total, lowConfidenceFields: low);
  }
  final lines = <ReceiptLine>[];
  for (var i = 0; i < a.lines.length; i++) {
    final x = a.lines[i];
    final y = b.lines[i].lineTotal;
    if (x.lineTotal != null && y != null && cents(x.lineTotal!) != cents(y)) {
      low.add('lines[$i].line_total');
      if (!seen.contains(cents(x.lineTotal!)) && seen.contains(cents(y))) {
        lines.add(copyLine(x, lineTotal: y));
        continue;
      }
    }
    lines.add(x);
  }
  return copyReceipt(a, lines: lines, total: total, lowConfidenceFields: low);
}

Future<ExtractedReceipt> _ask(
  LlmClient llm,
  List<LlmMessage> messages,
  AiCancelToken? cancel,
) async => ExtractedReceipt.fromJson(
  await llm.chatJson(
    messages,
    schema: receiptJsonSchema,
    schemaName: 'extracted_receipt',
    cancel: cancel,
  ),
);

/// One repair attempt after the lines do not add up. Keeps the retry only when
/// it is closer to the total; otherwise keeps the original and flags the total.
Future<ExtractedReceipt> _retryOnce(
  LlmClient llm,
  List<LlmMessage> messages,
  ExtractedReceipt first,
  AiCancelToken? cancel,
) async {
  double gap(ExtractedReceipt r) => ((linesSum(r) ?? 0) - (r.total ?? 0)).abs();
  ExtractedReceipt? second;
  try {
    second = repairArithmetic(
      await _ask(llm, [
        ...messages,
        LlmMessage.user(
          receiptRepairPrompt(
            previousJson: jsonEncode(first.toJson()),
            linesSum: linesSum(first) ?? 0,
            total: first.total ?? 0,
          ),
        ),
      ], cancel),
    );
  } on AiBadResponseException {
    second = null; // a bad retry must not lose the first reading
  }
  final best = second != null && second.total != null && gap(second) < gap(first)
      ? second
      : first;
  return sumMismatch(best)
      ? copyReceipt(best, lowConfidenceFields: [...best.lowConfidenceFields, 'total'])
      : best;
}
