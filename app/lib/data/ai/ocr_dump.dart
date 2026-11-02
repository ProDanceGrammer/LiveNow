/// Keeps the OCR word boxes of a receipt whose lines did not add up to its total,
/// so the failure can be replayed later (`ReceiptWord.fromJson` -> `rebuildReceipt`)
/// and turned into a test. Hub-local (`ai_debug/` next to `error.log`), never
/// synced, newest [keep] files kept. Photos and receipts are private: the folder
/// is not part of any backup or sync.
library;

import 'dart:convert';
import 'dart:io';

import '../../domain/ai/extracted_receipt.dart';
import '../../domain/ai/receipt_row_builder.dart';
import '../accounts/profile_paths.dart';

class OcrDump {
  OcrDump._();

  static const keep = 20;

  /// Tests set this to a temp folder; otherwise nothing is written under `flutter test`.
  static Directory? directoryOverride;

  /// Never throws; null when nothing was written.
  static Future<File?> write(
    List<ReceiptWord> words,
    String ocrText,
    ExtractedReceipt receipt,
  ) async {
    try {
      final base =
          directoryOverride ??
          (Platform.environment.containsKey('FLUTTER_TEST')
              ? null
              : await profileDirectory());
      if (base == null || words.isEmpty) return null;
      final dir = Directory('${base.path}${Platform.pathSeparator}ai_debug');
      await dir.create(recursive: true);
      final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
      final file = File('${dir.path}${Platform.pathSeparator}ocr-$stamp.json');
      await file.writeAsString(
        jsonEncode({
          'words': [for (final w in words) w.toJson()],
          'ocr_text': ocrText,
          'read': receipt.toJson(),
        }),
        flush: true,
      );
      final files = [
        for (final e in dir.listSync())
          if (e is File && e.path.contains('ocr-')) e,
      ]..sort((a, b) => a.path.compareTo(b.path));
      for (final old in files.take((files.length - keep).clamp(0, files.length))) {
        await old.delete();
      }
      return file;
    } on Object {
      return null;
    }
  }
}
