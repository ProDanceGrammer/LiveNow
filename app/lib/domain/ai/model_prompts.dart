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
// (a2) translate item names, then suggest a category for each (batched)
// ---------------------------------------------------------------------------

/// Common Turkish receipt words (folded, no diacritics) and what they mean, so a
/// small model translates instead of transliterating. Small on purpose.
const turkishGlossary =
    'Turkish words: sut=молоко, tavuk/pilic=курка, pirinc=рис, karabugday=гречка, '
    'makarna=макарони, yumurta=яйця, peynir=сир, ekmek=хліб, lavas=лаваш, su=вода, '
    'maden suyu/miner=мінеральна вода, cikolata/cikol=шоколад, bisk/biskuvi=печиво, '
    'kuru erik=чорнослив, kuru kayisi=курага, yaprak=листя, defne=лавровий лист, '
    'sarimsak=часник, salatalik=огірки, tursu=мариновані, yulaf=вівсянка, '
    'ezmesi=паста, sampuan=шампунь, sac maske=маска для волосся, kakao=какао, '
    'seker=цукор, yag=олія, un=борошно, domates=помідори, patates=картопля, '
    'sogan=цибуля, elma=яблука, muz=банани, limon=лимон, mercimek=сочевиця, '
    'nohut=нут, findik=фундук, ceviz=горіхи, bal=мед, recel=джем, zeytin=оливки, '
    'cay=чай, kahve=кава, meyve suyu=сік, sabun=мило, deterjan=пральний порошок, '
    'pecete=серветки, isirgan=кропива, toz=порошок/мелений, iri=великий, '
    'yapragi=листя, kurusu=сушений, salata=салат, krema=крем, yogurt=йогурт.';

/// Item names as printed (Turkish, capitals, OCR slips) -> short Ukrainian product
/// names. One call for the whole receipt; [items] are (number, printed name).
ModelPrompt translateItemsPrompt({
  required List<({int n, String name})> items,
  String? merchant,
  String language = 'Ukrainian',
}) {
  final list = StringBuffer();
  for (final it in items) {
    list.writeln('${it.n}. ${it.name}');
  }
  return ModelPrompt(
    system: modelSystemPrompt(language: language),
    user:
        'Task: translate the product names of a shop receipt into $language.\n'
        '${merchant == null ? '' : 'Shop: $merchant\n'}'
        'The names are printed in capitals, abbreviated, often Turkish, with OCR '
        'typos. Give for each the SHORT ordinary $language name of the PRODUCT a '
        'person would write in a shopping list. Translate the product, never '
        'transliterate the Turkish letters. A brand stays in Latin letters after the '
        'product word. Keep a pack size like 560г. If you cannot tell, copy the '
        'printed name. Every item gets its OWN answer, in the same order.\n'
        '$turkishGlossary\n'
        'Items:\n$list'
        'Reply {"items": [{"n": <number>, "ua": <name>}, ...]} with every number.',
    schemaName: 'translated_items',
    schema: {
      'type': 'object',
      'additionalProperties': false,
      'required': ['items'],
      'properties': {
        'items': {
          'type': 'array',
          'items': {
            'type': 'object',
            'additionalProperties': false,
            'required': ['n', 'ua'],
            'properties': {
              'n': {'type': 'integer'},
              'ua': {'type': 'string'},
            },
          },
        },
      },
    },
  );
}

/// Number -> Ukrainian name; items the model skipped or garbled are absent.
Map<int, String> parseTranslatedItems(Map<String, dynamic> json) {
  final out = <int, String>{};
  final list = json['items'];
  if (list is! List) return out;
  for (final e in list) {
    if (e is! Map) continue;
    final n = e['n'] is num ? (e['n'] as num).round() : int.tryParse('${e['n']}');
    final ua = _tidyName(e['ua']);
    if (n != null && ua != null && ua.length <= 80) out[n] = ua;
  }
  return out;
}

/// A model-written name with tabs, control characters and runs of spaces
/// squeezed to single spaces; null when nothing is left.
String? _tidyName(Object? v) {
  final s = v?.toString().replaceAll(RegExp(r'[\u0000-\u001f\u007f\s]+'), ' ').trim();
  return s == null || s.isEmpty ? null : s;
}

/// What the model has to decide for one item: its name in the user's language
/// and the existing categories that might fit it.
class SuggestItem {
  const SuggestItem({
    required this.n,
    required this.printed,
    required this.ua,
    required this.options,
  });

  final int n;
  final String printed;
  final String ua;
  final List<CandidateCategory> options;
}

/// The model's decision for one item.
class CategorySuggestion {
  const CategorySuggestion({
    required this.n,
    this.option,
    this.group,
    this.newName,
    this.confidence = 0,
    this.grams,
  });

  final int n;

  /// Typical weight in grams of ONE pack as sold; null when the model did not
  /// know (it answers 0 then).
  final double? grams;

  /// The chosen existing category, or null for "new".
  final CandidateCategory? option;

  /// For "new": the parent group (one of the groups offered).
  final CandidateCategory? group;

  /// For "new": the name of the new category.
  final String? newName;
  final double confidence;
}

const _maxOptionKeys = 8;
const _maxGroupKeys = 30;

/// `groups` are the existing groups a NEW category may go under (keys `g1`..).
/// Per item the options are `c1`..`cN`; "new" means none of them fits.
ModelPrompt suggestCategoriesPrompt({
  required List<SuggestItem> items,
  required List<CandidateCategory> groups,
  String? merchant,
  String language = 'Ukrainian',
}) {
  final gs = groups.take(_maxGroupKeys).toList();
  final groupText = [
    for (var i = 0; i < gs.length; i++) 'g${i + 1}: ${gs[i].name}',
  ].join('\n');
  final list = StringBuffer();
  for (final it in items) {
    list.writeln('${it.n}. «${it.ua}» (printed: ${it.printed})');
    final opts = it.options.take(_maxOptionKeys).toList();
    if (opts.isEmpty) {
      list.writeln('   options: none');
    } else {
      list.writeln(
        '   options: ${[for (var i = 0; i < opts.length; i++) '${candidateKey(i)}: ${opts[i].name}'].join(' | ')}',
      );
    }
  }
  return ModelPrompt(
    system: modelSystemPrompt(language: language),
    user:
        'Task: for each purchased item choose the budget category.\n'
        '${merchant == null ? '' : 'Shop: $merchant\n'}'
        'For every item pick the option key whose category is the SAME kind of '
        'product. If no option is the same kind of product pick "new": then choose '
        'the best parent group from the group list and give the new category a '
        'short $language name. Never pick an option that is merely related.\n'
        'Also give "grams": the typical weight in grams of ONE pack as it is sold '
        '(e.g. 200 for a bag of crisps, 1000 for a 1 L bottle of water), or 0 if '
        'you do not know or it is not sold by weight.\n'
        'Groups for a new category:\n$groupText\n'
        'Items:\n$list'
        'Reply {"items": [{"n": <number>, "pick": <c1..c$_maxOptionKeys or "new">, '
        '"group": <g1..g$_maxGroupKeys or "none">, "name": <new category name or "">, '
        '"grams": <number>, "confidence": <0..1>}, ...]} with every number.',
    schemaName: 'category_suggestions',
    schema: {
      'type': 'object',
      'additionalProperties': false,
      'required': ['items'],
      'properties': {
        'items': {
          'type': 'array',
          'items': {
            'type': 'object',
            'additionalProperties': false,
            'required': ['n', 'pick', 'group', 'name', 'grams', 'confidence'],
            'properties': {
              'n': {'type': 'integer'},
              'pick': {
                'type': 'string',
                'enum': [
                  for (var i = 0; i < _maxOptionKeys; i++) candidateKey(i),
                  'new',
                ],
              },
              'group': {
                'type': 'string',
                'enum': [for (var i = 1; i <= _maxGroupKeys; i++) 'g$i', 'none'],
              },
              'name': {'type': 'string'},
              'grams': {'type': 'number', 'minimum': 0},
              'confidence': {'type': 'number', 'minimum': 0, 'maximum': 1},
            },
          },
        },
      },
    },
  );
}

/// Tolerant: a key outside the options/groups that were offered becomes "no
/// pick"; the caller then asks the user.
Map<int, CategorySuggestion> parseCategorySuggestions(
  Map<String, dynamic> json,
  List<SuggestItem> items,
  List<CandidateCategory> groups,
) {
  final byN = {for (final it in items) it.n: it};
  final out = <int, CategorySuggestion>{};
  final list = json['items'];
  if (list is! List) return out;
  for (final e in list) {
    if (e is! Map) continue;
    final n = e['n'] is num ? (e['n'] as num).round() : int.tryParse('${e['n']}');
    final item = n == null ? null : byN[n];
    if (n == null || item == null) continue;
    final conf = e['confidence'];
    final c = conf is num
        ? conf.toDouble().clamp(0.0, 1.0)
        : double.tryParse('$conf')?.clamp(0.0, 1.0) ?? 0.0;
    final pick = e['pick']?.toString().trim().toLowerCase();
    CandidateCategory? option;
    final opts = item.options.take(_maxOptionKeys).toList();
    for (var i = 0; i < opts.length; i++) {
      if (candidateKey(i) == pick) option = opts[i];
    }
    CandidateCategory? group;
    final gKey = e['group']?.toString().trim().toLowerCase();
    final gs = groups.take(_maxGroupKeys).toList();
    for (var i = 0; i < gs.length; i++) {
      if ('g${i + 1}' == gKey) group = gs[i];
    }
    final name = _tidyName(e['name']);
    final g = e['grams'] is num ? (e['grams'] as num).toDouble() : double.tryParse('${e['grams']}');
    out[n] = CategorySuggestion(
      n: n,
      option: option,
      group: group,
      newName: name == null || name.length > 80 ? null : name,
      confidence: c,
      // A pack is 5 g to 10 kg; anything else is a slip, not a weight.
      grams: g != null && g >= 5 && g <= 10000 ? g : null,
    );
  }
  return out;
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
