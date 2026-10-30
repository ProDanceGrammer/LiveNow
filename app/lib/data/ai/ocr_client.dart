/// Client for the hub's local OCR service (`app/windows/hub/ai/ocr_service.py`):
/// `POST /ocr` with the raw image bytes, JSON back with one entry per printed
/// ROW (words on the same baseline are already joined, left to right, rows top to
/// bottom), and `GET /health`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'ai_http.dart';

/// Default port of the OCR service (the sync hub uses 47653).
const kOcrServicePort = 47655;

class OcrLine {
  const OcrLine({
    required this.text,
    this.x0 = 0,
    this.y0 = 0,
    this.x1 = 0,
    this.y1 = 0,
    this.confidence = 1,
  });

  final String text;

  /// Bounding box in image pixels.
  final double x0, y0, x1, y1;
  final double confidence;

  factory OcrLine.fromJson(Map<String, dynamic> j) {
    final box = j['box'];
    double b(int i) =>
        box is List && box.length > i && box[i] is num ? (box[i] as num).toDouble() : 0;
    final conf = j['confidence'];
    return OcrLine(
      text: (j['text'] ?? '').toString(),
      x0: b(0),
      y0: b(1),
      x1: b(2),
      y1: b(3),
      confidence: conf is num ? conf.toDouble() : 1,
    );
  }
}

class OcrResult {
  const OcrResult({required this.lines, this.engine = '', this.width, this.height});

  final List<OcrLine> lines;

  /// `rapidocr` or `tesseract` (whatever the service used).
  final String engine;
  final int? width;
  final int? height;

  /// The receipt as plain text, one row per line.
  String get text => lines.map((l) => l.text).where((t) => t.trim().isNotEmpty).join('\n');

  bool get isEmpty => text.trim().isEmpty;
}

class OcrClient {
  OcrClient({
    String baseUrl = 'http://127.0.0.1:$kOcrServicePort',
    this.requestTimeout = const Duration(minutes: 3),
    this.maxResponseBytes = 4 * 1024 * 1024,
  }) : baseUrl = baseUrl.endsWith('/')
           ? baseUrl.substring(0, baseUrl.length - 1)
           : baseUrl;

  final String baseUrl;
  final Duration requestTimeout;
  final int maxResponseBytes;

  /// True when `/health` answers 200. Never throws.
  Future<bool> health({Duration timeout = const Duration(seconds: 3)}) async {
    try {
      final r = await aiHttpSend(
        'GET',
        Uri.parse('$baseUrl/health'),
        timeout: timeout,
        connectTimeout: timeout,
        maxBytes: 64 * 1024,
      );
      return r.ok;
    } on AiException {
      return false;
    }
  }

  Future<OcrResult> ocr(
    Uint8List image, {
    String? mime,
    AiCancelToken? cancel,
  }) async {
    final r = await aiHttpSend(
      'POST',
      Uri.parse('$baseUrl/ocr'),
      body: image,
      headers: {'content-type': mime ?? 'application/octet-stream'},
      timeout: requestTimeout,
      maxBytes: maxResponseBytes,
      cancel: cancel,
    );
    if (!r.ok) {
      throw AiBadResponseException('OCR service HTTP ${r.status}: ${r.text}', status: r.status);
    }
    try {
      final j = jsonDecode(r.text);
      if (j is! Map || j['lines'] is! List) {
        throw const FormatException('no "lines" list');
      }
      return OcrResult(
        engine: (j['engine'] ?? '').toString(),
        width: (j['width'] as num?)?.round(),
        height: (j['height'] as num?)?.round(),
        lines: [
          for (final l in j['lines'] as List)
            if (l is Map) OcrLine.fromJson(Map<String, dynamic>.from(l)),
        ],
      );
    } on FormatException catch (e) {
      throw AiBadResponseException('OCR service reply: ${e.message}');
    }
  }
}
