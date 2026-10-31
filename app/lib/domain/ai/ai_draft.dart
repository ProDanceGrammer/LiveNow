/// The draft card the hub's job runner shows before (or while) it writes a
/// receipt / bazaar note to the budget. It is the `content_json` of the
/// `ai_messages` row of kind `draft`, and ALSO the runner's working state: it
/// carries the extracted `source` and the user's `overrides`, so any answer or
/// edit simply rebuilds the draft from those (no second OCR / model run).
/// Plain JSON, tolerant parsing (an older app reads what it knows).
library;

/// Line flag: the category is the model's suggestion (the user has not seen it).
const kFlagSuggested = 'suggested';

/// Line flag: the pack weight is the model's estimate, not read or answered.
const kFlagWeightGuess = 'weight_guess';

double? _d(Object? v) =>
    v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
String? _s(Object? v) => v?.toString();
List<String> _strs(Object? v) => [
  if (v is List)
    for (final e in v) e.toString(),
];

/// A category option offered for a line (a question's quick reply).
class DraftChoice {
  const DraftChoice(this.id, this.name);
  final String id;
  final String name;

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
  factory DraftChoice.fromJson(Map<String, dynamic> j) =>
      DraftChoice((j['id'] ?? '').toString(), (j['name'] ?? '').toString());
}

class DraftLine {
  DraftLine({
    required this.index,
    required this.raw,
    required this.name,
    required this.amount,
    this.categoryId,
    this.categoryName,
    this.newCategory = false,
    this.priceChange = false,
    this.quantity,
    this.unit,
    this.unitPrice,
    this.questionIds = const [],
    this.flags = const [],
    this.candidates = const [],
    this.countAccountId,
    this.rateCount,
    this.rateInteract,
    this.snacks = false,
    this.oneOffGroupId,
    this.uaName,
    this.confidence,
    this.committed = false,
    this.skipped = false,
    this.transactionId,
  });

  /// Index of the line among ALL parsed receipt lines (stable, used by edits
  /// and answers; lines of another tender are simply absent from the card).
  final int index;
  final String raw;
  final String name;

  /// What was paid for the line (discounts netted).
  double amount;
  String? categoryId;
  String? categoryName;
  bool newCategory;
  bool priceChange;

  /// Kilograms or pieces; null while the weight is unknown.
  double? quantity;

  /// `kilogram` / `piece` / null.
  String? unit;
  double? unitPrice;

  /// Open question ids about this line (`weight:3`, `cat:3`).
  List<String> questionIds;
  List<String> flags;
  List<DraftChoice> candidates;
  String? countAccountId;
  double? rateCount;
  double? rateInteract;
  bool snacks;

  /// C7: the group a one-off item gets its own leaf under.
  String? oneOffGroupId;

  /// The product in the user's language, when the assistant translated it (also
  /// the name of a new category).
  String? uaName;

  /// 0..1 of the model's category suggestion; null when the program decided.
  double? confidence;
  bool committed;
  bool skipped;
  String? transactionId;

  bool get needsAnswer => questionIds.isNotEmpty;

  /// What to call the product: the translation, else the printed name.
  String get displayName => uaName ?? name;

  /// The category came from the model's suggestion, not from a rule or the user.
  bool get suggested => flags.contains(kFlagSuggested);

  Map<String, dynamic> toJson() => {
    'i': index,
    'raw': raw,
    'name': name,
    'category_id': categoryId,
    'category_name': categoryName,
    'new_category': newCategory,
    'price_change': priceChange,
    'quantity': quantity,
    'unit': unit,
    'unit_price': unitPrice,
    'amount': amount,
    'needs_answer': needsAnswer,
    'questions': questionIds,
    'flags': flags,
    'candidates': [for (final c in candidates) c.toJson()],
    'count_account_id': countAccountId,
    'rate_count': rateCount,
    'rate_interact': rateInteract,
    'snacks': snacks,
    'one_off_group_id': oneOffGroupId,
    'ua_name': uaName,
    'confidence': confidence,
    'committed': committed,
    'skipped': skipped,
    'transaction_id': transactionId,
  };

  factory DraftLine.fromJson(Map<String, dynamic> j) => DraftLine(
    index: (j['i'] as num?)?.toInt() ?? 0,
    raw: (j['raw'] ?? '').toString(),
    name: (j['name'] ?? '').toString(),
    amount: _d(j['amount']) ?? 0,
    categoryId: _s(j['category_id']),
    categoryName: _s(j['category_name']),
    newCategory: j['new_category'] == true,
    priceChange: j['price_change'] == true,
    quantity: _d(j['quantity']),
    unit: _s(j['unit']),
    unitPrice: _d(j['unit_price']),
    questionIds: _strs(j['questions']),
    flags: _strs(j['flags']),
    candidates: [
      if (j['candidates'] is List)
        for (final c in j['candidates'] as List)
          if (c is Map) DraftChoice.fromJson(Map<String, dynamic>.from(c)),
    ],
    countAccountId: _s(j['count_account_id']),
    rateCount: _d(j['rate_count']),
    rateInteract: _d(j['rate_interact']),
    snacks: j['snacks'] == true,
    oneOffGroupId: _s(j['one_off_group_id']),
    uaName: _s(j['ua_name']),
    confidence: _d(j['confidence']),
    committed: j['committed'] == true,
    skipped: j['skipped'] == true,
    transactionId: _s(j['transaction_id']),
  );
}

class DraftSum {
  const DraftSum(this.linesSum, this.expected, this.difference, this.ok);
  final double linesSum;
  final double? expected;
  final double difference;
  final bool ok;

  Map<String, dynamic> toJson() => {
    'lines_sum': linesSum,
    'expected': expected,
    'difference': difference,
    'ok': ok,
  };
  factory DraftSum.fromJson(Map<String, dynamic> j) => DraftSum(
    _d(j['lines_sum']) ?? 0,
    _d(j['expected']),
    _d(j['difference']) ?? 0,
    j['ok'] != false,
  );
}

/// The action the purchase is tied to: an existing one (`matched`) or one that
/// the commit creates (`new`).
class DraftAction {
  const DraftAction({this.id, required this.name, required this.isNew, this.matchKind});
  final String? id;
  final String name;
  final bool isNew;
  final String? matchKind;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'new': isNew,
    'match_kind': matchKind,
  };
  factory DraftAction.fromJson(Map<String, dynamic> j) => DraftAction(
    id: _s(j['id']),
    name: (j['name'] ?? '').toString(),
    isNew: j['new'] == true,
    matchKind: _s(j['match_kind']),
  );
}

class DraftCard {
  DraftCard({
    required this.jobKind,
    required this.at,
    this.merchant,
    this.currency = 'TRY',
    this.useAccountId,
    this.useAccountName,
    this.lines = const [],
    this.sum,
    this.action,
    this.fxSource = 'market',
    this.notes = const [],
    this.blockers = const [],
    this.duplicate = false,
    this.source = const {},
    this.overrides = const {},
    this.handled = const [],
    this.applied = const [],
    this.confirmed = false,
    this.userConfirmed = false,
    this.counted = false,
    this.batchId,
  });

  /// `receipt` or `bazaar`.
  final String jobKind;

  /// When the purchase happened (UTC).
  DateTime at;
  String? merchant;
  String currency;
  String? useAccountId;
  String? useAccountName;
  List<DraftLine> lines;
  DraftSum? sum;
  DraftAction? action;

  /// `market` / `screenshot` / `unresolved`.
  String fxSource;

  /// Assumptions made (shown in the result).
  List<String> notes;

  /// Question ids that block the whole draft (`dup`, `card:6141`, ...).
  List<String> blockers;
  bool duplicate;

  /// What the extractor read (receipt JSON, or the bazaar note text).
  Map<String, dynamic> source;

  /// What the user decided: per-line edits, answers, `dup_ok`, ...
  Map<String, dynamic> overrides;

  /// User message ids already processed.
  List<String> handled;

  /// `<question message id>:<question id>` answers already applied.
  List<String> applied;

  /// The user tapped Confirm (and nothing blocks the commit).
  bool confirmed;
  bool userConfirmed;

  /// `confirmed_count` was already incremented for this job.
  bool counted;
  String? batchId;

  Iterable<DraftLine> get activeLines => lines.where((l) => !l.skipped);
  Iterable<DraftLine> get pendingLines =>
      lines.where((l) => !l.skipped && !l.committed);

  Map<String, dynamic> toJson() => {
    'v': 1,
    'job_kind': jobKind,
    'merchant': merchant,
    'currency': currency,
    'at': at.toUtc().toIso8601String(),
    'use_account_id': useAccountId,
    'use_account_name': useAccountName,
    'lines': [for (final l in lines) l.toJson()],
    'sum': sum?.toJson(),
    'action': action?.toJson(),
    'fx_source': fxSource,
    'notes': notes,
    'blockers': blockers,
    'duplicate': duplicate,
    'source': source,
    'overrides': overrides,
    'handled': handled,
    'applied': applied,
    'confirmed': confirmed,
    'user_confirmed': userConfirmed,
    'counted': counted,
    'batch_id': batchId,
  };

  factory DraftCard.fromJson(Map<String, dynamic> j) => DraftCard(
    jobKind: (j['job_kind'] ?? 'receipt').toString(),
    at: DateTime.tryParse((j['at'] ?? '').toString())?.toUtc() ?? DateTime.now().toUtc(),
    merchant: _s(j['merchant']),
    currency: (j['currency'] ?? 'TRY').toString(),
    useAccountId: _s(j['use_account_id']),
    useAccountName: _s(j['use_account_name']),
    lines: [
      if (j['lines'] is List)
        for (final l in j['lines'] as List)
          if (l is Map) DraftLine.fromJson(Map<String, dynamic>.from(l)),
    ],
    sum: j['sum'] is Map
        ? DraftSum.fromJson(Map<String, dynamic>.from(j['sum'] as Map))
        : null,
    action: j['action'] is Map
        ? DraftAction.fromJson(Map<String, dynamic>.from(j['action'] as Map))
        : null,
    fxSource: (j['fx_source'] ?? 'market').toString(),
    notes: _strs(j['notes']),
    blockers: _strs(j['blockers']),
    duplicate: j['duplicate'] == true,
    source: j['source'] is Map ? Map<String, dynamic>.from(j['source'] as Map) : {},
    overrides: j['overrides'] is Map
        ? Map<String, dynamic>.from(j['overrides'] as Map)
        : {},
    handled: _strs(j['handled']),
    applied: _strs(j['applied']),
    confirmed: j['confirmed'] == true,
    userConfirmed: j['user_confirmed'] == true,
    counted: j['counted'] == true,
    batchId: _s(j['batch_id']),
  );
}
