/// The three small jobs the hub gives the text model. The design is
/// deterministic-first: code parses, matches and applies the rules; the model only
///   (a) picks one of a few candidate categories ([candidateChoicePrompt]),
///   (b) words a short question or summary in the user's language
///       ([writeMessagePrompt]),
///   (c) turns a typed correction into a small intent ([correctionIntentPrompt]).
/// Every task is a [ModelPrompt] (messages + strict JSON schema) with a tolerant
/// parser for the reply, so a 3B model's slips become "unknown"/null, never a
/// crash. Pure Dart: no I/O (spec 10.3 adapted).
library;

/// System prompt shared by the three tasks (adapted from spec 10.3: the model
/// has NO tools and does NO arithmetic here, the code does).
String modelSystemPrompt({String language = 'Ukrainian'}) =>
    '''
You are a small helper inside the user's personal budget app. The user writes in $language; write in $language, briefly. Receipts are mostly Turkish (BIM, SOK, Migros), default currency is Turkish lira.
You never calculate: numbers you are given are already checked by the program, copy them exactly and never invent one.
You never decide what is not in the options you are given. If unsure, choose "none" / "unknown" instead of guessing.
Answer ONLY with one JSON object that matches the requested schema. No prose, no code fence.''';

/// One request to the model: what to say and the shape the answer must take.
class ModelPrompt {
  const ModelPrompt({
    required this.system,
    required this.user,
    required this.schema,
    required this.schemaName,
  });

  final String system;
  final String user;

  /// JSON schema (draft 2020-12 subset every runtime supports) of the reply.
  final Map<String, dynamic> schema;
  final String schemaName;
}

// ---------------------------------------------------------------------------
// (a) candidate category choice
// ---------------------------------------------------------------------------

class CandidateCategory {
  const CandidateCategory({required this.id, required this.name, this.hint});

  /// The category's database id (never shown to the model).
  final String id;
  final String name;

  /// Optional extra context, e.g. the parent group or the unit.
  final String? hint;
}

class CandidateChoice {
  const CandidateChoice({this.category, this.confidence = 0});

  /// The chosen candidate, or null when the model said "none" (or nonsense).
  final CandidateCategory? category;

  /// 0..1, clamped.
  final double confidence;
}

/// Short keys `c1`..`cN` (+ `none`) stand for the candidates, so the enum is
/// tiny and the model never has to copy a long id or a Ukrainian name.
String candidateKey(int index) => 'c${index + 1}';

ModelPrompt candidateChoicePrompt({
  required String itemText,
  required List<CandidateCategory> candidates,
  String? merchant,
  String language = 'Ukrainian',
}) {
  final keys = [for (var i = 0; i < candidates.length; i++) candidateKey(i), 'none'];
  final list = StringBuffer();
  for (var i = 0; i < candidates.length; i++) {
    final c = candidates[i];
    list.writeln(
      '${candidateKey(i)}: ${c.name}${c.hint == null ? '' : ' (${c.hint})'}',
    );
  }
  list.writeln('none: none of the above fits');
  return ModelPrompt(
    system: modelSystemPrompt(language: language),
    user:
        'Task: pick the budget category for one receipt line.\n'
        '${merchant == null ? '' : 'Shop: $merchant\n'}'
        'Receipt line: $itemText\n'
        'Options:\n$list'
        'Reply {"choice": <option key>, "confidence": <0..1>}.',
    schemaName: 'category_choice',
    schema: {
      'type': 'object',
      'additionalProperties': false,
      'required': ['choice', 'confidence'],
      'properties': {
        'choice': {'type': 'string', 'enum': keys},
        'confidence': {'type': 'number', 'minimum': 0, 'maximum': 1},
      },
    },
  );
}

CandidateChoice parseCandidateChoice(
  Map<String, dynamic> json,
  List<CandidateCategory> candidates,
) {
  final key = json['choice']?.toString().trim().toLowerCase();
  final conf = json['confidence'];
  final c = conf is num
      ? conf.toDouble().clamp(0.0, 1.0)
      : double.tryParse('$conf')?.clamp(0.0, 1.0) ?? 0.0;
  for (var i = 0; i < candidates.length; i++) {
    if (candidateKey(i) == key) {
      return CandidateChoice(category: candidates[i], confidence: c);
    }
  }
  return CandidateChoice(confidence: c);
}

// ---------------------------------------------------------------------------
// (b) question / summary writing
// ---------------------------------------------------------------------------

enum WrittenMessageKind { question, summary }

/// Asks the model to word [facts] (plain lines the code prepared, numbers
/// included) as a short [kind] message. The reply is only text.
ModelPrompt writeMessagePrompt({
  required WrittenMessageKind kind,
  required String facts,
  String language = 'Ukrainian',
}) {
  final what = kind == WrittenMessageKind.question
      ? 'Write ONE short, polite question to the user that asks exactly for what '
            'is missing (at most 2 sentences). Do not ask about anything else.'
      : 'Write a compact summary for the user (at most 6 short lines): what was '
            'recorded, the assumptions made, anything still open. Keep every '
            'number and name exactly as given.';
  return ModelPrompt(
    system: modelSystemPrompt(language: language),
    user: '$what\nFacts:\n$facts\nReply {"text": <the message>}.',
    schemaName: 'written_message',
    schema: {
      'type': 'object',
      'additionalProperties': false,
      'required': ['text'],
      'properties': {
        'text': {'type': 'string'},
      },
    },
  );
}

/// The message text, or null when the model returned nothing usable (the caller
/// then falls back to a fixed template).
String? parseWrittenMessage(Map<String, dynamic> json) {
  final t = json['text']?.toString().trim();
  return t == null || t.isEmpty ? null : t;
}

// ---------------------------------------------------------------------------
// (c) correction intent
// ---------------------------------------------------------------------------

enum CorrectionKind {
  setCategory,
  setQuantity,
  setPrice,
  setAccount,
  setDate,
  setAction,
  deleteLine,
  rememberRule,
  confirm,
  reject,
  unknown,
}

const _kindNames = <CorrectionKind, String>{
  CorrectionKind.setCategory: 'set_category',
  CorrectionKind.setQuantity: 'set_quantity',
  CorrectionKind.setPrice: 'set_price',
  CorrectionKind.setAccount: 'set_account',
  CorrectionKind.setDate: 'set_date',
  CorrectionKind.setAction: 'set_action',
  CorrectionKind.deleteLine: 'delete_line',
  CorrectionKind.rememberRule: 'remember_rule',
  CorrectionKind.confirm: 'confirm',
  CorrectionKind.reject: 'reject',
  CorrectionKind.unknown: 'unknown',
};

/// What the user's typed correction means. Names the user typed (a category, an
/// account...) stay TEXT here: the code resolves them against the real data.
class CorrectionIntent {
  const CorrectionIntent({
    required this.kind,
    this.line,
    this.text,
    this.number,
    this.unit,
  });

  final CorrectionKind kind;

  /// 1-based line number the user referred to, when they did.
  final int? line;

  /// Category / account / action / date / rule wording as typed.
  final String? text;

  /// Quantity or price.
  final double? number;
  final String? unit;

  static const unknown = CorrectionIntent(kind: CorrectionKind.unknown);
}

ModelPrompt correctionIntentPrompt({
  required String userText,
  required List<String> lines,
  String language = 'Ukrainian',
}) {
  final numbered = StringBuffer();
  for (var i = 0; i < lines.length; i++) {
    numbered.writeln('${i + 1}. ${lines[i]}');
  }
  return ModelPrompt(
    system: modelSystemPrompt(language: language),
    user:
        'The user corrects a draft receipt. Turn their message into one intent.\n'
        'Intents: ${_kindNames.values.join(', ')}.\n'
        '- set_category: "text" is the category wording; set_quantity/set_price: '
        '"number" (and "unit" for a quantity); set_account / set_date / '
        'set_action: "text"; remember_rule: "text" is the rule as typed; '
        'delete_line needs "line"; confirm/reject need nothing.\n'
        '- "line" is the 1-based number from the list when the user points at a '
        'line, else null. Unused fields are null. If unclear use "unknown".\n'
        'Draft lines:\n$numbered'
        'User message: $userText\n'
        'Reply {"intent","line","text","number","unit"}.',
    schemaName: 'correction_intent',
    schema: {
      'type': 'object',
      'additionalProperties': false,
      'required': ['intent', 'line', 'text', 'number', 'unit'],
      'properties': {
        'intent': {'type': 'string', 'enum': _kindNames.values.toList()},
        'line': {
          'type': ['integer', 'null'],
        },
        'text': {
          'type': ['string', 'null'],
        },
        'number': {
          'type': ['number', 'null'],
        },
        'unit': {
          'type': ['string', 'null'],
        },
      },
    },
  );
}

/// Tolerant: an unknown intent, a line outside 1..[lineCount] or a missing
/// required field turns into [CorrectionIntent.unknown] / null fields.
CorrectionIntent parseCorrectionIntent(
  Map<String, dynamic> json, {
  int? lineCount,
}) {
  final name = json['intent']?.toString().trim().toLowerCase();
  final kind = _kindNames.entries
      .where((e) => e.value == name)
      .map((e) => e.key)
      .firstOrNull;
  if (kind == null || kind == CorrectionKind.unknown) {
    return CorrectionIntent.unknown;
  }
  final rawLine = json['line'];
  var line = rawLine is num ? rawLine.round() : int.tryParse('$rawLine');
  if (line != null && (line < 1 || (lineCount != null && line > lineCount))) {
    line = null;
  }
  final text = json['text']?.toString().trim();
  final rawNum = json['number'];
  final number = rawNum is num
      ? rawNum.toDouble()
      : double.tryParse('$rawNum'.replaceAll(',', '.'));
  final unit = json['unit']?.toString().trim();
  final intent = CorrectionIntent(
    kind: kind,
    line: line,
    text: text == null || text.isEmpty || text == 'null' ? null : text,
    number: number,
    unit: unit == null || unit.isEmpty || unit == 'null' ? null : unit,
  );
  final complete = switch (kind) {
    CorrectionKind.setCategory ||
    CorrectionKind.setAccount ||
    CorrectionKind.setDate ||
    CorrectionKind.setAction ||
    CorrectionKind.rememberRule => intent.text != null,
    CorrectionKind.setQuantity || CorrectionKind.setPrice => intent.number != null,
    CorrectionKind.deleteLine => intent.line != null,
    _ => true,
  };
  return complete ? intent : CorrectionIntent.unknown;
}
