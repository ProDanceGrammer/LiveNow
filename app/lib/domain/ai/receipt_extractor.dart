/// A swappable way to turn a receipt picture into an [ExtractedReceipt]: OCR +
/// text model (runs on the CPU hub), a vision model, or both. Implementations
/// live in `data/ai/receipt_extractors.dart`; this file holds the interface and
/// the schema/prompt constants they share. Pure Dart.
library;

import 'dart:typed_data';

import 'extracted_receipt.dart';

abstract interface class ReceiptExtractor {
  /// Reads the receipt in [image]. Throws a subtype of `AiException`
  /// (data/ai/ai_http.dart) when a service fails, or
  /// [ReceiptExtractionException] when nothing readable came back.
  Future<ExtractedReceipt> extract(Uint8List image, {String? mime});
}

/// The picture held nothing that could be read as a receipt.
class ReceiptExtractionException implements Exception {
  const ReceiptExtractionException(this.message);
  final String message;

  @override
  String toString() => 'ReceiptExtractionException: $message';
}

const _nullableNumber = {
  'type': ['number', 'null'],
};
const _nullableString = {
  'type': ['string', 'null'],
};

/// JSON schema of `ExtractedReceipt.toJson()` (spec section 6), strict-mode
/// friendly: every property is required and may be null.
const Map<String, dynamic> receiptJsonSchema = {
  'type': 'object',
  'additionalProperties': false,
  'required': [
    'merchant',
    'invoice_datetime_local',
    'terminal_datetime_local',
    'currency',
    'total',
    'tenders',
    'lines',
    'confidence',
  ],
  'properties': {
    'merchant': _nullableString,
    'invoice_datetime_local': _nullableString,
    'terminal_datetime_local': _nullableString,
    'currency': {'type': 'string'},
    'total': _nullableNumber,
    'tenders': {
      'type': 'array',
      'items': {
        'type': 'object',
        'additionalProperties': false,
        'required': ['method', 'last4', 'amount'],
        'properties': {
          'method': _nullableString,
          'last4': _nullableString,
          'amount': _nullableNumber,
        },
      },
    },
    'lines': {
      'type': 'array',
      'items': {
        'type': 'object',
        'additionalProperties': false,
        'required': [
          'raw',
          'name',
          'line_total',
          'qty_line',
          'pack',
          'discount',
          'vat_pct',
          'flags',
        ],
        'properties': {
          'raw': {'type': 'string'},
          'name': _nullableString,
          'line_total': _nullableNumber,
          'qty_line': {
            'type': ['object', 'null'],
            'additionalProperties': false,
            'required': ['qty', 'unit', 'unit_price'],
            'properties': {
              'qty': _nullableNumber,
              'unit': _nullableString,
              'unit_price': _nullableNumber,
            },
          },
          'pack': {
            'type': ['object', 'null'],
            'additionalProperties': false,
            'required': ['grams', 'ml', 'count'],
            'properties': {
              'grams': _nullableNumber,
              'ml': _nullableNumber,
              'count': {
                'type': ['integer', 'null'],
              },
            },
          },
          'discount': {'type': 'number'},
          'vat_pct': _nullableNumber,
          'flags': {
            'type': 'array',
            'items': {'type': 'string'},
          },
        },
      },
    },
    'confidence': {
      'type': 'object',
      'additionalProperties': false,
      'required': ['overall', 'low_confidence_fields'],
      'properties': {
        'overall': _nullableNumber,
        'low_confidence_fields': {
          'type': 'array',
          'items': {'type': 'string'},
        },
      },
    },
  },
};

/// System prompt of the extraction call (same for OCR text and for a picture).
const String receiptExtractionSystemPrompt = '''
You read shop receipts (mostly Turkish: BIM, SOK, Migros, A101) and return ONE JSON object that matches the given schema. Copy what is printed; never invent a line or a number. Use null for what you cannot read.
Rules:
- Money is a plain number with a dot (1.234,50 -> 1234.50). Currency TRY unless printed otherwise.
- One entry in "lines" per purchased item, in printed order. "raw" is the printed text of the item, "name" a cleaned product name, "line_total" the amount printed on the item row.
- A quantity row such as "2 AD X 16,50" or "0,716 KG X 319,00" is printed ABOVE the item it belongs to: put it in that item's "qty_line" (qty, unit, unit_price), not as its own line.
- A discount row (INDIRIM) belongs to the item above it: put the positive amount in its "discount".
- Do not turn totals, VAT summary, card slips or the shop address into lines. "total" is the amount paid. "tenders" lists each payment (method card/cash, last 4 digits, amount).
- A number in a product name followed by G, GR, KG, ML or L is its pack size ("pack"); do NOT multiply anything yourself, the program checks the arithmetic.
- List fields you are unsure of in confidence.low_confidence_fields (e.g. "lines[3].line_total").''';

String receiptExtractionUserPrompt(String ocrText) =>
    'Receipt text read by OCR (one printed row per line; digits may be misread):\n'
    '$ocrText\n\nReturn the JSON object.';

const String receiptVisionUserPrompt =
    'This is a photo of a shop receipt. Return the JSON object.';

/// Prompt for the one repair retry after the lines do not add up to the total.
String receiptRepairPrompt({
  required String previousJson,
  required double linesSum,
  required double total,
}) =>
    'Your previous answer was:\n$previousJson\n'
    'The program checked it: the item amounts add up to ${linesSum.toStringAsFixed(2)} '
    'but the receipt total is ${total.toStringAsFixed(2)}. '
    'Read the receipt again and fix the wrong or missing numbers or lines. '
    'Return the corrected JSON object.';
