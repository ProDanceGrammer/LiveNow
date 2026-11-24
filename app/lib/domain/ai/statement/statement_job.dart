/// The hub side of a bank statement: what is kept between runs ([StatementState]),
/// how the rows become a summary and questions ([StatementPlanner.plan], rules
/// first, the model only for merchants nothing else decided), and the ONE batch
/// that writes them ([StatementWriter]). Everything here is deterministic Dart;
/// the model's picks are validated against the real categories by
/// `ItemSuggester`. The runner (`ai_job_runner.dart`) only moves messages and
/// job states around these pieces.
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Variable;

import '../../../core/ids.dart';
import '../../../core/time_codec.dart';
import '../../../data/database.dart';
import '../../budget_rules.dart';
import '../../budget_service.dart';
import '../../search_match.dart' show foldSearch;
import '../action_matcher.dart' show receiptLocalToUtc;
import '../ai_alias_db_source.dart';
import '../ai_batch_service.dart';
import '../ai_screenshot_text.dart' show isoLocalOf;
import '../ai_transfer_text.dart' show matchAccountName, resolveAccount;
import '../alias_source.dart';
import '../category_resolver.dart';
import '../dedupe_service.dart';
import '../invariant_validator.dart';
import '../transfer_builder.dart';
import '../ai_protocol.dart';
import 'statement_period.dart';
import 'statement_rows.dart';
import 'statement_rules.dart';

/// Question ids of a statement job.
abstract final class StmtQ {
  static const account = 'acct';
  static const cashback = 'cb';
  static const fee = 'fee';
  static String merchant(String key) => 'm:$key';
  static String merchantInGroup(String key) => 'g:$key';
  static String party(String key) => 'p:$key';
  static String counter(String key) => 'x:$key';
}

/// At most this many questions are asked in one round; the rest follows after
/// the answers.
const kStatementQuestionsPerRound = 10;

/// A model pick below this is not used (the merchant is asked instead).
const kStatementModelConfidence = 0.6;

Map<String, dynamic> statementRowToJson(StatementRow r) => {
  'i': r.index,
  'at': r.at.toIso8601String(),
  'd': r.details,
  if (r.mcc != null) 'mcc': r.mcc,
  'ca': r.cardAmount,
  'cc': r.cardCurrency,
  if (r.opAmount != null) 'oa': r.opAmount,
  if (r.opCurrency != null) 'oc': r.opCurrency,
  if (r.rate != null) 'rt': r.rate,
  if (r.fee != null) 'fe': r.fee,
  if (r.cashback != null) 'cb': r.cashback,
  if (r.balance != null) 'bl': r.balance,
  if (r.bankCategory != null) 'bc': r.bankCategory,
};

StatementRow statementRowFromJson(Map<String, dynamic> j) => StatementRow(
  index: (j['i'] as num).toInt(),
  at: DateTime.parse(j['at'] as String),
  details: (j['d'] ?? '').toString(),
  mcc: (j['mcc'] as num?)?.toInt(),
  cardAmount: (j['ca'] as num).toDouble(),
  cardCurrency: (j['cc'] ?? 'UAH').toString(),
  opAmount: (j['oa'] as num?)?.toDouble(),
  opCurrency: j['oc']?.toString(),
  rate: (j['rt'] as num?)?.toDouble(),
  fee: (j['fe'] as num?)?.toDouble(),
  cashback: (j['cb'] as num?)?.toDouble(),
  balance: (j['bl'] as num?)?.toDouble(),
  bankCategory: j['bc']?.toString(),
);

/// What the job keeps between runs: lives in the `state` key of the draft
/// message (so a restart or an answer never re-reads the file, whose synced
/// bytes are dropped once read).
class StatementState {
  StatementState({
    required this.rows,
    required this.fileName,
    required this.cardCurrency,
    required this.signature,
    this.from,
    this.to,
    this.skipped = 0,
    this.warnings = const [],
    this.accountId,
    Map<String, dynamic>? decisions,
    Map<String, String>? llm,
    this.llmDone = false,
    Map<String, String>? misses,
    List<String>? applied,
    List<String>? handled,
    this.stage = 'working',
    this.confirmed = false,
    this.batchId,
  }) : decisions = decisions ?? {},
       llm = llm ?? {},
       misses = misses ?? {},
       applied = applied ?? [],
       handled = handled ?? [];

  final List<StatementRow> rows;
  final String fileName;
  final String cardCurrency;
  final String signature;
  final DateTime? from;
  final DateTime? to;
  final int skipped;
  final List<String> warnings;

  /// The account the file belongs to; null = asked.
  String? accountId;

  /// What the user (or a remembered answer) decided, by question key:
  /// `m:<merchant>` / `p:<party>` -> `{category_id, learn}` | `{account_id}` |
  /// `{skip: true}`; `x:<details>` -> `{account_id}`; `cb` / `fee` -> `{category_id}`.
  final Map<String, dynamic> decisions;

  /// The model's category per merchant key (validated ids), and whether the model
  /// step is over.
  final Map<String, String> llm;
  bool llmDone;

  /// Question id -> the text typed that matched nothing (shown on the next ask).
  final Map<String, String> misses;
  final List<String> applied;
  final List<String> handled;

  /// `working` (read, no summary yet), `asking`, `ready` (waits for Confirm),
  /// `done`.
  String stage;
  bool confirmed;
  String? batchId;

  Map<String, dynamic> toJson() => {
    'rows': [for (final r in rows) statementRowToJson(r)],
    'file_name': fileName,
    'card_currency': cardCurrency,
    'signature': signature,
    if (from != null) 'from': from!.toIso8601String(),
    if (to != null) 'to': to!.toIso8601String(),
    'skipped': skipped,
    'warnings': warnings,
    'account_id': accountId,
    'decisions': decisions,
    'llm': llm,
    'llm_done': llmDone,
    'misses': misses,
    'applied': applied,
    'handled': handled,
    'stage': stage,
    'confirmed': confirmed,
    'batch_id': batchId,
  };

  factory StatementState.fromJson(Map<String, dynamic> j) => StatementState(
    rows: [
      if (j['rows'] is List)
        for (final r in j['rows'] as List)
          if (r is Map) statementRowFromJson(Map<String, dynamic>.from(r)),
    ],
    fileName: (j['file_name'] ?? '').toString(),
    cardCurrency: (j['card_currency'] ?? 'UAH').toString(),
    signature: (j['signature'] ?? '').toString(),
    from: j['from'] == null ? null : DateTime.tryParse(j['from'].toString()),
    to: j['to'] == null ? null : DateTime.tryParse(j['to'].toString()),
    skipped: (j['skipped'] as num?)?.toInt() ?? 0,
    warnings: [
      if (j['warnings'] is List) for (final w in j['warnings'] as List) '$w',
    ],
    accountId: j['account_id']?.toString(),
    decisions: j['decisions'] is Map ? Map<String, dynamic>.from(j['decisions'] as Map) : null,
    llm: j['llm'] is Map
        ? {for (final e in (j['llm'] as Map).entries) '${e.key}': '${e.value}'}
        : null,
    llmDone: j['llm_done'] == true,
    misses: j['misses'] is Map
        ? {for (final e in (j['misses'] as Map).entries) '${e.key}': '${e.value}'}
        : null,
    applied: [if (j['applied'] is List) for (final a in j['applied'] as List) '$a'],
    handled: [if (j['handled'] is List) for (final a in j['handled'] as List) '$a'],
    stage: (j['stage'] ?? 'working').toString(),
    confirmed: j['confirmed'] == true,
    batchId: j['batch_id']?.toString(),
  );
}

/// One thing the Confirm writes.
class StatementEntry {
  const StatementEntry({
    required this.row,
    required this.type,
    required this.name,
    required this.amount,
    required this.currency,
    required this.at,
    this.categoryId,
    this.rateCount,
    this.rateInteract,
    this.srcId,
    this.dstId,
    this.srcAmount,
    this.dstAmount,
    this.suffix = 'stmt',
  });

  /// Row index in the file (the id seed).
  final int row;

  /// `purchase`, `income`, `fee` or `transfer`.
  final String type;
  final String name;
  final double amount;
  final String currency;
  final DateTime at;
  final String? categoryId;
  final double? rateCount;
  final double? rateInteract;

  /// A transfer: the accounts and the amount on each side.
  final String? srcId;
  final String? dstId;
  final double? srcAmount;
  final double? dstAmount;

  /// Id role: `stmt` or `stmt-fee`.
  final String suffix;

  bool get isTransfer => type == 'transfer';
}

/// What [StatementPlanner.plan] found.
class StatementPlan {
  StatementPlan({
    required this.questions,
    required this.entries,
    required this.groups,
    required this.duplicates,
    required this.cancelled,
    required this.modelCandidates,
    required this.learnAliases,
    required this.learnParties,
  });

  final List<Question> questions;
  final List<StatementEntry> entries;

  /// The summary groups, ready for the card's JSON.
  final List<Map<String, dynamic>> groups;
  final List<Map<String, dynamic>> duplicates;
  final List<Map<String, dynamic>> cancelled;

  /// Merchants nothing decided and the model was not asked about yet: key -> text.
  final Map<String, String> modelCandidates;

  /// Merchant key -> (text, category id) to remember on Confirm.
  final Map<String, ({String text, String categoryId})> learnAliases;

  /// Party key -> the answer json to remember on Confirm.
  final Map<String, Map<String, dynamic>> learnParties;
}

double _r2(double v) => (v * 100).round() / 100;

/// Turns a [StatementState] into a [StatementPlan]; reads the database, writes
/// nothing.
class StatementPlanner {
  StatementPlanner(this.db, {required this.aliases, required this.rules, this.now});

  final AppDatabase db;
  final DbAliasSource aliases;
  final AiRulesMemory rules;
  final DateTime Function()? now;

  /// Accounts, those the card currency is in first.
  static List<BudgetAccount> accountsFor(List<BudgetAccount> all, String currency, {String? except}) {
    final list = [
      for (final a in all)
        if (a.id != except) a,
    ];
    list.sort((a, b) {
      final ca = a.currency.toUpperCase() == currency.toUpperCase() ? 0 : 1;
      final cb = b.currency.toUpperCase() == currency.toUpperCase() ? 0 : 1;
      return ca != cb ? ca.compareTo(cb) : a.name.compareTo(b.name);
    });
    return list;
  }

  Future<StatementPlan> plan(StatementState s, String jobId) async {
    final accounts = await db.select(db.budgetAccountsTable).get();
    final cats = await db.select(db.budgetCategoriesTable).get();
    final ctx = _Ctx(this, s, jobId, accounts, cats);
    return ctx.run();
  }
}

/// A question waiting to be built: rows of one merchant / person / details text.
/// A recorded transaction, or a recorded receipt (an AI batch's lines summed).
class _Recorded {
  _Recorded(this.ids, this.name, this.amount, this.at, {required this.batch});
  final Set<String> ids;
  final String name;
  final double amount;
  final DateTime at;
  final bool batch;
}

class _Pending {
  _Pending(this.text);
  final String text;
  int count = 0;
  final Map<String, double> sums = {};
  String? groupId;
  String? remembered;
  String? partyName;

  void add(double amount, String currency) {
    count++;
    sums[currency] = _r2((sums[currency] ?? 0) + amount);
  }

  String get total => sums.entries.map((e) => '${_fmt(e.value)} ${e.key}').join(' + ');
}

String _fmt(double v) => v.toStringAsFixed(2);

class _Ctx {
  _Ctx(this.p, this.s, this.jobId, this.accounts, this.cats)
    : accById = {for (final a in accounts) a.id: a},
      byId = {for (final c in cats) c.id: c} {
    for (final c in cats) {
      final parent = c.parentId;
      if (parent != null && byId.containsKey(parent)) (children[parent] ??= []).add(c);
    }
  }

  final StatementPlanner p;
  final StatementState s;
  final String jobId;
  final List<BudgetAccount> accounts;
  final List<BudgetCategory> cats;
  final Map<String, BudgetAccount> accById;
  final Map<String, BudgetCategory> byId;
  final Map<String, List<BudgetCategory>> children = {};

  late final CategoryResolver resolver = CategoryResolver(p.db, aliases: p.aliases);

  final questions = <Question>[];
  final entries = <StatementEntry>[];
  final duplicates = <Map<String, dynamic>>[];
  final cancelled = <Map<String, dynamic>>[];
  final modelCandidates = <String, String>{};
  final learnAliases = <String, ({String text, String categoryId})>{};
  final learnParties = <String, Map<String, dynamic>>{};

  // Questions are collected by key (first appearance order) and built at the end.
  final _merchantQs = <String, _Pending>{};
  final _partyQs = <String, _Pending>{};
  final _counterQs = <String, _Pending>{};
  _Pending? _cashbackQ;
  _Pending? _feeQ;

  late final Set<String> ownIds;
  late BudgetAccount statement;

  // ---- categories ------------------------------------------------------------

  bool _isWrapper(BudgetCategory c) {
    final key = CategoryResolver.nameKey(c.name);
    return (children[c.id] ?? const []).any((k) => CategoryResolver.nameKey(k.name) == key);
  }

  bool _isGroup(BudgetCategory c) => children.containsKey(c.id) && !_isWrapper(c);

  /// A category a transaction can go to: a leaf, or the leaf of a price-variant
  /// wrapper (the one paid from the statement account first). A group is not one.
  String? _leafId(String? id) {
    final c = id == null ? null : byId[id];
    if (c == null) return null;
    final kids = children[c.id];
    if (kids == null) return c.id;
    if (!_isWrapper(c)) return null;
    final leaves = [
      for (final k in kids)
        if (!children.containsKey(k.id)) k,
    ];
    if (leaves.isEmpty) return null;
    return (leaves.where((k) => k.accountUseId == s.accountId).firstOrNull ?? leaves.first).id;
  }

  bool _fits(String id, bool income) => byId[id]?.isIncome == income;

  String _catName(String id) {
    final c = byId[id];
    if (c == null) return '?';
    final parent = c.parentId == null ? null : byId[c.parentId];
    return parent == null ? c.name : '${parent.name} › ${c.name}';
  }

  /// Leaves under [groupId] (breadth first), at most [max].
  List<BudgetCategory> _leavesUnder(String groupId, {int max = 12}) {
    final out = <BudgetCategory>[];
    final todo = [groupId];
    while (todo.isNotEmpty && out.length < max) {
      final id = todo.removeAt(0);
      for (final c in [...?children[id]]..sort((a, b) => a.name.compareTo(b.name))) {
        if (children.containsKey(c.id) && !_isWrapper(c)) {
          todo.add(c.id);
        } else if (_leafId(c.id) != null) {
          out.add(c);
        }
      }
    }
    return out.take(max).toList();
  }

  final _hintCache = <String, ({String? group, String? leaf})>{};

  Future<({String? group, String? leaf})> _hintPick(String hint, bool income) async {
    final key = '${income ? 'i' : 'e'}|${foldSearch(hint)}';
    final cached = _hintCache[key];
    if (cached != null) return cached;
    final r = await resolver.resolve(hint, limit: 3);
    final top = r.candidates.firstOrNull;
    ({String? group, String? leaf}) out = (group: null, leaf: null);
    if (top != null && top.score >= 0.8) {
      final c = byId[top.id];
      if (c != null && c.isIncome == income) {
        if (top.isAggregate && _isGroup(c)) {
          if (!top.fromAlias) out = (group: c.id, leaf: null);
        } else if (!r.ambiguous) {
          out = (group: null, leaf: _leafId(c.id));
        }
      }
    }
    return _hintCache[key] = out;
  }

  Future<String?> _categoryByText(String typed) async {
    final key = normalizeReceiptText(typed);
    for (final c in cats) {
      if (_leafId(c.id) == c.id && normalizeReceiptText(c.name) == key) return c.id;
    }
    final r = await CategoryResolver(p.db).resolve(typed, limit: 3);
    final best = r.best;
    if (best != null && best.score >= 0.7) return _leafId(best.id);
    return null;
  }

  /// A leaf whose name has one of [words] (folded), income or expense.
  String? _leafNamed(List<String> words, {required bool income}) {
    for (final c in cats) {
      if (c.isIncome != income || _leafId(c.id) != c.id) continue;
      final n = foldSearch(c.name);
      if (words.any(n.contains)) return c.id;
    }
    return null;
  }

  // ---- the plan --------------------------------------------------------------

  Future<StatementPlan> run() async {
    final st = s.accountId == null ? null : accById[s.accountId];
    if (st == null) {
      s.accountId = null;
      final list = StatementPlanner.accountsFor(accounts, s.cardCurrency);
      questions.add(
        Question(
          id: StmtQ.account,
          text: 'Яка це виписка? Оберіть рахунок'
              '${s.fileName.isEmpty ? '' : ' для файлу «${s.fileName}»'} '
              '(валюта картки ${s.cardCurrency}).',
          options: [for (final a in list) '${a.name} (${a.currency})'],
          optionIds: [for (final a in list) a.id],
        ),
      );
      return _result();
    }
    statement = st;
    ownIds = {
      for (final r in s.rows) ...[
        deriveId(jobId, 'stmt', r.index),
        deriveId(jobId, 'stmt-fee', r.index),
        deriveId(jobId, 'transfer-out', r.index),
        deriveId(jobId, 'transfer-in', r.index),
      ],
    };

    final cardMap = <String, String>{};
    for (final e in (await p.rules.withPrefix('card.')).entries) {
      final id = e.value['account_id']?.toString();
      final last4 = e.key.substring('card.'.length);
      if (id != null && RegExp(r'^\d{4}$').hasMatch(last4)) cardMap[last4] = id;
    }
    final memory = {
      for (final e in (await p.rules.withPrefix('stmt.party.')).entries)
        e.key.substring('stmt.party.'.length): jsonEncode(e.value),
    };
    final items = classifyStatement(
      s.rows,
      statementAccountId: st.id,
      accounts: [
        for (final a in accounts) StatementAccountRef(id: a.id, name: a.name, currency: a.currency),
      ],
      partyMemory: memory,
      cardAccount: (last4) => cardMap[last4],
    );

    final dupRows = <int>{};
    for (final it in items) {
      switch (it.kind) {
        case StatementKind.cancelled:
          cancelled.add(_listRow(it, 'скасовано'));
        case StatementKind.unknown:
          cancelled.add(_listRow(it, 'нульова сума'));
        case StatementKind.fee:
          if (!dupRows.contains(it.row.index)) await _fee(it);
        case StatementKind.transferOut:
        case StatementKind.transferIn:
          if (await _isDuplicate(it, asTransfer: true)) {
            dupRows.add(it.row.index);
            duplicates.add(_listRow(it, null));
          } else if (it.counterAccountId != null) {
            _transfer(it, it.counterAccountId!);
          } else {
            _ask(_counterQs, _counterKey(it), it.row.details, it);
          }
        case StatementKind.person:
          await _person(it, dupRows);
        case StatementKind.cashbackIncome:
          if (await _isDuplicate(it, asTransfer: false)) {
            dupRows.add(it.row.index);
            duplicates.add(_listRow(it, null));
          } else {
            await _cashback(it);
          }
        case StatementKind.purchase:
        case StatementKind.income:
          if (await _isDuplicate(it, asTransfer: false)) {
            dupRows.add(it.row.index);
            duplicates.add(_listRow(it, null));
          } else {
            await _merchant(it);
          }
      }
    }
    await _buildQuestions();
    return _result();
  }

  StatementPlan _result() {
    final shown = entries.toList()..sort((a, b) => a.row.compareTo(b.row));
    return StatementPlan(
      questions: questions,
      entries: shown,
      groups: _groups(shown),
      duplicates: duplicates,
      cancelled: cancelled,
      modelCandidates: modelCandidates,
      learnAliases: learnAliases,
      learnParties: learnParties,
    );
  }

  // ---- duplicates ------------------------------------------------------------

  DateTime _utc(StatementRow r) => receiptLocalToUtc(isoLocalOf(r.at));

  /// Whether the row is already in the budget. ONE recorded transaction (or
  /// one recorded receipt: the lines of one AI batch, summed) answers ONE row,
  /// the closest in time first: three 50 TL rides on a day with one recorded
  /// ride leave two to write.
  Future<bool> _isDuplicate(StatementItem it, {required bool asTransfer, bool? transferOut}) async {
    final row = it.row;
    final at = _utc(row);
    final amount = row.cardAmount.abs();
    final pool = await _recorded();
    if (asTransfer) {
      final out = transferOut ?? row.cardAmount < 0;
      final name = out
          ? TransferBuilder.expenseCategoryName(statement.name)
          : TransferBuilder.incomeCategoryName(statement.name);
      return _claim(pool, at, amount, name);
    }
    if (_claim(pool, at, amount, row.details)) return true;
    // A receipt or screenshot recorded in the shop's currency: the day and the
    // amount decide (its name never looks like the bank's string); a receipt
    // counts as the sum of its lines.
    if (row.isForeign && row.opAmount != null) {
      return _claim(pool, at, row.opAmount!.abs(), null, batches: true);
    }
    return _claim(pool, at, amount, null, batches: true, batchesOnly: true);
  }

  List<_Recorded>? _pool;
  final _claimed = <String>{};

  /// Transactions dated around the statement rows, plus one summed entry per
  /// AI batch with several transactions (a receipt's lines).
  Future<List<_Recorded>> _recorded() async {
    final cached = _pool;
    if (cached != null) return cached;
    if (s.rows.isEmpty) return _pool = const [];
    var lo = _utc(s.rows.first), hi = lo;
    for (final r in s.rows) {
      final t = _utc(r);
      if (t.isBefore(lo)) lo = t;
      if (t.isAfter(hi)) hi = t;
    }
    final rows = await p.db
        .customSelect(
          'SELECT t.id AS id, t.name AS name, t.quantity AS quantity, '
          't.unit_price AS unit_price, t.is_amount AS is_amount, '
          'COALESCE(a.start_at, t.occurred_at) AS eff, '
          '(SELECT bi.batch_id FROM ai_batch_items bi WHERE bi.entity_type = ? '
          'AND bi.entity_id = t.id LIMIT 1) AS batch '
          'FROM budget_transactions t LEFT JOIN actions a ON a.id = t.action_id '
          'WHERE COALESCE(a.start_at, t.occurred_at) >= ? '
          'AND COALESCE(a.start_at, t.occurred_at) <= ?',
          variables: [
            Variable.withString(AiEntity.transaction),
            Variable.withString(dateTimeToDb(lo.subtract(const Duration(days: 1)))!),
            Variable.withString(dateTimeToDb(hi.add(const Duration(days: 1)))!),
          ],
        )
        .get();
    final out = <_Recorded>[];
    final byBatch = <String, List<_Recorded>>{};
    for (final r in rows) {
      final id = r.read<String>('id');
      if (ownIds.contains(id)) continue;
      final at = dateTimeFromDb(r.read<String>('eff'));
      if (at == null) continue;
      final q = r.read<double>('quantity');
      final v = r.read<bool>('is_amount') ? q : r.read<double>('unit_price') * q;
      final one = _Recorded({id}, r.read<String>('name'), v, at, batch: false);
      out.add(one);
      final b = r.readNullable<String>('batch');
      if (b != null) (byBatch[b] ??= []).add(one);
    }
    for (final lines in byBatch.values.where((l) => l.length > 1)) {
      final first = lines.map((l) => l.at).reduce((a, b) => a.isBefore(b) ? a : b);
      out.add(
        _Recorded(
          {for (final l in lines) ...l.ids},
          lines.map((l) => l.name).join(', '),
          lines.fold<double>(0, (n, l) => n + l.amount),
          first,
          batch: true,
        ),
      );
    }
    return _pool = out;
  }

  /// Claims the closest unclaimed recorded entry of [amount] within a day of
  /// [at] (names must look alike when [text] is given). Single transactions
  /// only unless [batches]; only receipt sums when [batchesOnly].
  bool _claim(
    List<_Recorded> pool,
    DateTime at,
    double amount,
    String? text, {
    bool batches = false,
    bool batchesOnly = false,
  }) {
    _Recorded? best;
    var bestGap = const Duration(days: 2);
    for (final c in pool) {
      if (c.batch ? !batches : batchesOnly) continue;
      if (c.ids.any(_claimed.contains)) continue;
      final gap = c.at.difference(at).abs();
      if (gap > const Duration(days: 1) || gap >= bestGap) continue;
      final tol = c.batch ? (amount * 0.002).clamp(0.02, 1.0) : DedupeService.amountTolerance;
      if ((c.amount - amount).abs() > tol) continue;
      if (text != null && !DedupeService.namesSimilar(c.name, text)) continue;
      best = c;
      bestGap = gap;
    }
    if (best == null) return false;
    _claimed.addAll(best.ids);
    return true;
  }

  // ---- list rows -------------------------------------------------------------

  Map<String, dynamic> _listRow(StatementItem it, String? reason) => {
    'i': it.row.index,
    'at': isoLocalOf(it.row.at),
    'details': it.row.details,
    'amount': _r2(it.row.cardAmount.abs()),
    'currency': it.row.cardCurrency,
    'reason': ?reason,
  };

  Map<String, dynamic> _entryRow(StatementEntry e, StatementItem? it) => {
    'i': e.row,
    'at': isoLocalOf(_rowAt[e.row] ?? e.at),
    'details': _rowDetails[e.row] ?? e.name,
    'amount': _r2(e.isTransfer ? (e.srcId == statement.id ? e.srcAmount! : e.dstAmount!) : e.amount),
    'currency': e.isTransfer
        ? (e.srcId == statement.id ? statement.currency : statement.currency)
        : e.currency,
    if (e.rateCount != null) 'rate_count': e.rateCount,
    if (e.rateInteract != null) 'rate_interact': e.rateInteract,
    if (e.isTransfer) 'counter_account_id': e.srcId == statement.id ? e.dstId : e.srcId,
    if (e.categoryId != null) 'category_id': e.categoryId,
  };

  final _rowAt = <int, DateTime>{};
  final _rowDetails = <int, String>{};

  void _remember(StatementItem it) {
    _rowAt[it.row.index] = it.row.at;
    _rowDetails[it.row.index] = it.row.details;
  }

  // ---- entries ---------------------------------------------------------------


  void _addTx(StatementItem it, String categoryId, {bool? income, String type = 'purchase', double? amount}) {
    _remember(it);
    final isIncome = income ?? !it.isOut;
    entries.add(
      StatementEntry(
        row: it.row.index,
        type: type == 'purchase' && isIncome ? 'income' : type,
        name: it.merchant ?? it.row.details,
        amount: amount ?? it.amount,
        currency: it.currency,
        at: _utc(it.row),
        categoryId: categoryId,
        rateCount: it.rateCount,
        rateInteract: it.rateInteract,
      ),
    );
  }

  void _transfer(StatementItem it, String counterId) {
    final counter = accById[counterId];
    if (counter == null || counter.id == statement.id) return;
    _remember(it);
    final row = it.row;
    final card = row.cardAmount.abs();
    final out = row.cardAmount < 0;
    double convert(double v, BudgetAccount from, BudgetAccount to) =>
        _r2(v / from.rateToBase * to.rateToBase);
    final src = out ? statement : counter;
    final dst = out ? counter : statement;
    final same = src.currency.toUpperCase() == dst.currency.toUpperCase();
    final other = out ? dst : src;
    final opMatches = row.isForeign &&
        row.opAmount != null &&
        row.opCurrency!.toUpperCase() == other.currency.toUpperCase();
    final otherAmount = same ? card : (opMatches ? row.opAmount!.abs() : convert(card, statement, other));
    entries.add(
      StatementEntry(
        row: row.index,
        type: 'transfer',
        name: 'Переказ',
        amount: card,
        currency: statement.currency,
        at: _utc(row),
        srcId: src.id,
        dstId: dst.id,
        srcAmount: out ? card : otherAmount,
        dstAmount: out ? otherAmount : card,
      ),
    );
  }

  // ---- purchases and income --------------------------------------------------

  String _merchantKey(StatementItem it) => normalizeReceiptText(it.merchant ?? it.row.details);

  void _ask(Map<String, _Pending> into, String key, String text, StatementItem it, {String? group}) {
    final q = into.putIfAbsent(key, () => _Pending(text));
    q.add(it.amount, it.currency);
    if (group != null) q.groupId = group;
  }

  String _counterKey(StatementItem it) => normalizeReceiptText(it.row.details);

  Future<void> _merchant(StatementItem it) async {
    final income = !it.isOut;
    final key = _merchantKey(it);
    final text = it.merchant ?? it.row.details;
    final dec = s.decisions[StmtQ.merchant(key)];
    if (dec is Map) {
      if (dec['skip'] == true) {
        cancelled.add(_listRow(it, 'пропущено'));
        return;
      }
      final id = _leafId(dec['category_id']?.toString());
      if (id != null) {
        _addTx(it, id);
        if (dec['learn'] == true) learnAliases[key] = (text: text, categoryId: id);
        return;
      }
    }
    final alias = await p.aliases.lookup(key);
    final aliasId = alias == null ? null : _leafId(alias.categoryId);
    if (aliasId != null && _fits(aliasId, income)) {
      _addTx(it, aliasId);
      return;
    }
    String? groupId;
    final hint = it.hint;
    if (hint != null && hint.trim().isNotEmpty) {
      final h = await _hintPick(hint, income);
      if (h.leaf != null) {
        _addTx(it, h.leaf!);
        learnAliases[key] = (text: text, categoryId: h.leaf!);
        return;
      }
      groupId = h.group;
    }
    final sug = s.llm[key];
    final sugId = sug == null ? null : _leafId(sug);
    if (groupId == null && sugId != null && _fits(sugId, income)) {
      _addTx(it, sugId);
      learnAliases[key] = (text: text, categoryId: sugId);
      return;
    }
    if (groupId == null && !s.llmDone && !income) modelCandidates[key] = text;
    _ask(_merchantQs, key, text, it, group: groupId);
  }

  Future<void> _cashback(StatementItem it) async {
    final dec = s.decisions[StmtQ.cashback];
    if (dec is Map && dec['skip'] == true) {
      cancelled.add(_listRow(it, 'пропущено'));
      return;
    }
    final id = _leafId(dec is Map ? dec['category_id']?.toString() : null) ??
        _leafNamed(['кешбек', 'кэшбэк', 'cashback'], income: true);
    if (id != null) {
      _addTx(it, id, income: true);
    } else {
      _cashbackQ = (_cashbackQ ?? _Pending('кешбек'))..add(it.amount, it.currency);
    }
  }

  Future<void> _fee(StatementItem it) async {
    final dec = s.decisions[StmtQ.fee];
    if (dec is Map && dec['skip'] == true) return;
    final id = _leafId(dec is Map ? dec['category_id']?.toString() : null) ??
        _leafNamed(['комісі', 'комисси', 'commission', 'fee'], income: false);
    if (id != null) {
      _remember(it);
      entries.add(
        StatementEntry(
          row: it.row.index,
          type: 'fee',
          name: 'Комісія: ${it.row.details}',
          amount: it.amount,
          currency: it.currency,
          at: _utc(it.row),
          categoryId: id,
          suffix: 'stmt-fee',
        ),
      );
    } else {
      _feeQ = (_feeQ ?? _Pending('комісії'))..add(it.amount, it.currency);
    }
  }

  // ---- people ----------------------------------------------------------------

  /// What a remembered answer (its json) points at, or null when it is gone.
  ({String? categoryId, String? accountId})? _remembered(String? json) {
    if (json == null) return null;
    try {
      final j = jsonDecode(json);
      if (j is! Map) return null;
      final cat = _leafId(j['category_id']?.toString());
      final acc = j['account_id']?.toString();
      if (cat != null) return (categoryId: cat, accountId: null);
      if (acc != null && accById.containsKey(acc) && acc != statement.id) {
        return (categoryId: null, accountId: acc);
      }
    } catch (_) {}
    return null;
  }

  Future<void> _person(StatementItem it, Set<int> dupRows) async {
    final key = it.partyKey ?? '';
    final dec = s.decisions[StmtQ.party(key)];
    if (dec is Map) {
      if (dec['skip'] == true) {
        cancelled.add(_listRow(it, 'пропущено'));
        return;
      }
      final acc = dec['account_id']?.toString();
      if (acc != null && accById.containsKey(acc) && acc != statement.id) {
        if (await _isDuplicate(it, asTransfer: true)) {
          dupRows.add(it.row.index);
          duplicates.add(_listRow(it, null));
          return;
        }
        _transfer(it, acc);
        learnParties[key] = {'account_id': acc};
        return;
      }
      final cat = _leafId(dec['category_id']?.toString());
      if (cat != null) {
        if (await _isDuplicate(it, asTransfer: false)) {
          dupRows.add(it.row.index);
          duplicates.add(_listRow(it, null));
          return;
        }
        _addTx(it, cat);
        learnParties[key] = {'category_id': cat};
        return;
      }
    }
    if (await _isDuplicate(it, asTransfer: false)) {
      dupRows.add(it.row.index);
      duplicates.add(_listRow(it, null));
      return;
    }
    final q = _partyQs.putIfAbsent(key, () => _Pending(it.partyName ?? it.row.details));
    q.add(it.amount, it.currency);
    q.partyName = it.partyName ?? it.row.details;
    q.remembered ??= it.remembered;
  }

  // ---- questions -------------------------------------------------------------

  String _miss(String qid) {
    final m = s.misses[qid];
    return m == null ? '' : ' Не знайшов «$m», спробуйте інакше.';
  }

  static const _skipLabel = 'Не записувати';

  Future<void> _buildQuestions() async {
    final out = <Question>[];

    // 1. Statement-wide ones first: they decide many rows.
    final cb = _cashbackQ;
    if (cb != null) {
      final opts = [
        for (final c in cats)
          if (c.isIncome && _leafId(c.id) == c.id) c,
      ].take(8).toList();
      out.add(
        Question(
          id: StmtQ.cashback,
          text: 'Виведення кешбеку (${cb.count} оп., ${cb.total}): у яку категорію доходу?'
              '${_miss(StmtQ.cashback)}',
          options: [for (final c in opts) _catName(c.id), _skipLabel],
          optionIds: [for (final c in opts) c.id, 'skip'],
        ),
      );
    }
    final fee = _feeQ;
    if (fee != null) {
      final opts = [
        for (final c in cats)
          if (!c.isIncome && _leafId(c.id) == c.id) c,
      ]..sort((a, b) => a.name.compareTo(b.name));
      out.add(
        Question(
          id: StmtQ.fee,
          text: 'Комісії банку (${fee.count} оп., ${fee.total}): у яку категорію? '
              'Можна написати назву.${_miss(StmtQ.fee)}',
          options: [for (final c in opts.take(8)) _catName(c.id), _skipLabel],
          optionIds: [for (final c in opts.take(8)) c.id, 'skip'],
        ),
      );
    }

    // 2. Transfers whose other account is unknown.
    final others = StatementPlanner.accountsFor(accounts, s.cardCurrency, except: statement.id);
    for (final e in _counterQs.entries) {
      final q = e.value;
      out.add(
        Question(
          id: StmtQ.counter(e.key),
          text: '«${q.text}» (${q.count} оп., ${q.total}): з яким вашим рахунком це переказ?'
              '${_miss(StmtQ.counter(e.key))}',
          options: [for (final a in others) '${a.name} (${a.currency})', _skipLabel],
          optionIds: [for (final a in others) a.id, 'skip'],
        ),
      );
    }

    // 3. People.
    for (final e in _partyQs.entries) {
      final q = e.value;
      final mem = _remembered(q.remembered);
      final options = <String>[];
      final ids = <String>[];
      var intro = 'Ваш інший рахунок (переказ) чи категорія? Назву категорії можна написати.';
      if (mem != null) {
        final what = mem.categoryId != null
            ? '«${_catName(mem.categoryId!)}»'
            : 'рахунок «${accById[mem.accountId]!.name}»';
        options.add('Так, як минулого разу: $what');
        ids.add('keep');
        intro = 'Минулого разу це було $what. Те саме?';
      }
      for (final a in others) {
        options.add('Мій рахунок: ${a.name}');
        ids.add('acct:${a.id}');
      }
      options.add(_skipLabel);
      ids.add('skip');
      out.add(
        Question(
          id: StmtQ.party(e.key),
          text: '«${q.partyName ?? q.text}» (${q.count} оп., ${q.total}). $intro'
              '${_miss(StmtQ.party(e.key))}',
          options: options,
          optionIds: ids,
          recommended: mem != null ? 0 : null,
        ),
      );
    }

    // 4. Merchants without a category.
    for (final e in _merchantQs.entries) {
      final q = e.value;
      final group = q.groupId;
      final List<BudgetCategory> opts;
      if (group != null) {
        opts = _leavesUnder(group);
      } else {
        final r = await resolver.resolve(q.text, limit: 6);
        final seen = <String>{};
        opts = [
          for (final c in r.candidates)
            if (_leafId(c.id) != null && seen.add(_leafId(c.id)!)) byId[_leafId(c.id)!]!,
        ].take(6).toList();
      }
      final qid = group != null ? StmtQ.merchantInGroup(e.key) : StmtQ.merchant(e.key);
      final inGroup = group == null ? '' : ' з «${byId[group]?.name ?? ''}»';
      out.add(
        Question(
          id: qid,
          text: 'Яка категорія$inGroup для «${q.text}» (${q.count} оп., ${q.total})? '
              'Можна написати назву.${_miss(qid)}',
          options: [for (final c in opts) _catName(c.id), _skipLabel],
          optionIds: [for (final c in opts) c.id, 'skip'],
        ),
      );
    }
    questions.addAll(out.take(kStatementQuestionsPerRound));
  }

  // ---- groups ----------------------------------------------------------------

  List<Map<String, dynamic>> _groups(List<StatementEntry> shown) {
    final order = <String>[];
    final byKey = <String, Map<String, dynamic>>{};
    Map<String, dynamic> group(String key, String kind, String title, {String? categoryId}) =>
        byKey.putIfAbsent(key, () {
          order.add(key);
          return {
            'kind': kind,
            'title': title,
            'category_id': ?categoryId,
            'count': 0,
            'totals': <String, double>{},
            'rows': <Map<String, dynamic>>[],
          };
        });
    for (final e in shown) {
      final Map<String, dynamic> g;
      final String cur;
      final double amount;
      if (e.isTransfer) {
        final src = accById[e.srcId]?.name ?? '?';
        final dst = accById[e.dstId]?.name ?? '?';
        g = group('t|${e.srcId}|${e.dstId}', 'transfer', '$src → $dst');
        cur = statement.currency;
        amount = e.srcId == statement.id ? e.srcAmount! : e.dstAmount!;
      } else if (e.type == 'fee') {
        g = group('fee|${e.categoryId}', 'fee', 'Комісії: ${_catName(e.categoryId!)}', categoryId: e.categoryId);
        cur = e.currency;
        amount = e.amount;
      } else {
        final income = e.type == 'income';
        g = group(
          '${income ? 'i' : 'p'}|${e.categoryId}',
          income ? 'income' : 'purchase',
          _catName(e.categoryId!),
          categoryId: e.categoryId,
        );
        cur = e.currency;
        amount = e.amount;
      }
      g['count'] = (g['count'] as int) + 1;
      final totals = g['totals'] as Map<String, double>;
      totals[cur] = _r2((totals[cur] ?? 0) + amount);
      (g['rows'] as List<Map<String, dynamic>>).add(_entryRow(e, null));
    }
    // Purchases first, then income, transfers, fees; bigger groups first.
    const rank = {'purchase': 0, 'income': 1, 'transfer': 2, 'fee': 3};
    final list = [for (final k in order) byKey[k]!];
    final indexed = list.indexed.toList()
      ..sort((a, b) {
        final ra = rank[a.$2['kind']] ?? 9;
        final rb = rank[b.$2['kind']] ?? 9;
        if (ra != rb) return ra.compareTo(rb);
        final ca = a.$2['count'] as int;
        final cb = b.$2['count'] as int;
        return ca != cb ? cb.compareTo(ca) : a.$1.compareTo(b.$1);
      });
    return [for (final e in indexed) e.$2];
  }
}

// ===========================================================================
// Answers
// ===========================================================================

/// Applies one answered question to [s]'s decisions. Unusable typed text is
/// remembered in `misses` so the question comes back saying so.
Future<void> applyStatementAnswer(AppDatabase db, StatementState s, Question q) async {
  final a = (q.answer ?? '').trim();
  final aid = q.answerId;
  final ctx = _Ctx(
    StatementPlanner(db, aliases: DbAliasSource(db), rules: AiRulesMemory(db)),
    s,
    '',
    await db.select(db.budgetAccountsTable).get(),
    await db.select(db.budgetCategoriesTable).get(),
  );
  BudgetAccount? accountOf(String? id, String text) {
    if (id != null && ctx.accById.containsKey(id)) return ctx.accById[id];
    if (text.isEmpty) return null;
    final hit = matchAccountName(text, ctx.accounts, (x) => x.name);
    if (hit.length == 1) return hit.first;
    final fuzzy = resolveAccount<BudgetAccount>(
      text,
      ctx.accounts,
      nameOf: (x) => x.name,
      currencyOf: (x) => x.currency,
      currencyHint: s.cardCurrency,
    );
    return fuzzy.length == 1 ? fuzzy.first : null;
  }

  void miss() => s.misses[q.id] = a;
  final id = q.id;
  if (id == StmtQ.account) {
    final acc = accountOf(aid, a);
    if (acc == null) {
      miss();
    } else {
      s.accountId = acc.id;
      s.misses.remove(id);
    }
    return;
  }
  if (aid == 'skip' || (aid == null && RegExp(r'^не записувати$', caseSensitive: false, unicode: true).hasMatch(a))) {
    s.decisions[_decisionKey(id)] = {'skip': true};
    return;
  }
  if (id.startsWith('x:')) {
    final acc = accountOf(aid, a);
    if (acc == null || acc.id == s.accountId) {
      miss();
    } else {
      s.decisions[id] = {'account_id': acc.id};
      s.misses.remove(id);
    }
    return;
  }
  if (id.startsWith('p:')) {
    if (aid == 'keep') {
      final mem = (await AiRulesMemory(db).get('stmt.party.${id.substring(2)}'));
      if (mem != null && (mem['category_id'] != null || mem['account_id'] != null)) {
        s.decisions[id] = {
          if (mem['category_id'] != null) 'category_id': mem['category_id'],
          if (mem['account_id'] != null) 'account_id': mem['account_id'],
        };
        s.misses.remove(id);
        return;
      }
    }
    if (aid != null && aid.startsWith('acct:') && ctx.accById.containsKey(aid.substring(5))) {
      s.decisions[id] = {'account_id': aid.substring(5)};
      s.misses.remove(id);
      return;
    }
    final catId = aid != null && ctx.byId.containsKey(aid) ? ctx._leafId(aid) : null;
    if (catId != null) {
      s.decisions[id] = {'category_id': catId};
      s.misses.remove(id);
      return;
    }
    // Typed: an account by name, else a category by name.
    final acc = a.isEmpty ? null : accountOf(null, a);
    if (acc != null && acc.id != s.accountId) {
      s.decisions[id] = {'account_id': acc.id};
      s.misses.remove(id);
      return;
    }
    final typedCat = a.isEmpty ? null : await ctx._categoryByText(a);
    if (typedCat != null) {
      s.decisions[id] = {'category_id': typedCat};
      s.misses.remove(id);
    } else {
      miss();
    }
    return;
  }
  // Category questions: m:, g:, cb, fee.
  final catId = aid != null && ctx.byId.containsKey(aid)
      ? ctx._leafId(aid)
      : (a.isEmpty ? null : await ctx._categoryByText(a));
  if (catId == null) {
    miss();
    return;
  }
  s.misses.remove(id);
  s.decisions[_decisionKey(id)] = {
    'category_id': catId,
    // A pick inside a group the bank's words named is asked again next time.
    if (id.startsWith('m:')) 'learn': true,
  };
}

/// `g:<key>` (a merchant asked inside a group) is stored under `m:<key>`.
String _decisionKey(String questionId) =>
    questionId.startsWith('g:') ? 'm:${questionId.substring(2)}' : questionId;

// ===========================================================================
// Writing
// ===========================================================================

class StatementWriteResult {
  const StatementWriteResult({this.failure, this.batchId, this.transactions = const [], this.transfers = 0});
  final String? failure;
  final String? batchId;
  final List<String> transactions;
  final int transfers;
}

/// Writes a [StatementPlan] in ONE database transaction and ONE undoable batch.
class StatementWriter {
  StatementWriter(this.db, this.budget, this.batches, this.rules, this.aliases);

  final AppDatabase db;
  final BudgetService budget;
  final AiBatchService batches;
  final AiRulesMemory rules;
  final DbAliasSource aliases;

  Future<StatementWriteResult> write({
    required AiJob job,
    required String? messageId,
    required StatementState state,
    required StatementPlan plan,
  }) async {
    final cats = {for (final c in await db.select(db.budgetCategoriesTable).get()) c.id: c};
    final accounts = {for (final a in await db.select(db.budgetAccountsTable).get()) a.id: a};
    final statement = accounts[state.accountId];
    if (statement == null) return const StatementWriteResult(failure: 'Рахунок виписки не знайдено.');

    double rate(String currency) {
      for (final a in accounts.values) {
        if (a.currency.toUpperCase() == currency.toUpperCase() && a.rateToBase > 0) return a.rateToBase;
      }
      return statement.rateToBase > 0 ? statement.rateToBase : 1;
    }

    final single = plan.entries.where((e) => !e.isTransfer).toList();
    final validation = await InvariantValidator(db).validate(
      transactions: [
        for (final e in single)
          PlannedTransaction(
            name: e.name,
            categoryId: e.categoryId,
            quantity: 1,
            amount: e.amount,
            date: e.at,
            rateCount: e.rateCount ?? rate(e.currency),
            rateInteract: e.rateInteract ?? rate(e.currency),
            isIncome: e.type == 'income',
            checkDuplicate: false,
          ),
      ],
    );
    if (!validation.ok) {
      return StatementWriteResult(
        failure: [for (final e in validation.errors) '${e.code}: ${e.message}'].join('\n'),
      );
    }

    return db.transaction(() async {
      final batchId = await batches.startBatch(
        jobId: job.id,
        threadId: job.threadId,
        messageId: messageId,
        summary: 'Виписка ${state.fileName}'.trim(),
      );
      final txIds = <String>[];
      final createdCats = <String>[];
      var transfers = 0;
      var txPos = 10000;
      for (final e in plan.entries) {
        if (e.isTransfer) {
          final src = accounts[e.srcId]!;
          final dst = accounts[e.dstId]!;
          final r = await TransferBuilder(db, budget).create(
            sourceAccountId: src.id,
            destAccountId: dst.id,
            sourceAmount: e.srcAmount!,
            destAmount: e.dstAmount!,
            sourceRate: src.rateToBase,
            destRate: dst.rateToBase,
            date: e.at,
            namespaceId: job.id,
            index: e.row,
          );
          createdCats.addAll(r.createdCategoryIds);
          for (final id in [r.expenseId, r.incomeId]) {
            txIds.add(id);
            await batches.record(
              batchId,
              position: txPos++,
              entityType: AiEntity.transaction,
              entityId: id,
            );
          }
          transfers++;
          continue;
        }
        final cat = cats[e.categoryId]!;
        final isAmount = cat.unit == BudgetUnit.percentPerMonth.db;
        final id = await budget.createTransaction(
          id: deriveId(job.id, e.suffix, e.row),
          categoryId: e.categoryId!,
          name: e.name,
          date: e.at,
          quantity: isAmount ? e.amount : 1,
          unitPrice: isAmount ? null : e.amount,
          rateCount: e.rateCount,
          rateInteract: e.rateInteract,
          updateAccountRate: false,
        );
        txIds.add(id);
        await batches.record(
          batchId,
          position: txPos++,
          entityType: AiEntity.transaction,
          entityId: id,
        );
      }
      var catPos = 0;
      for (final c in createdCats) {
        await batches.record(batchId, position: catPos++, entityType: AiEntity.category, entityId: c);
      }

      // The user saw and confirmed it: remember what they decided.
      for (final e in plan.learnAliases.values) {
        await aliases.remember(e.text, categoryId: e.categoryId);
      }
      for (final e in plan.learnParties.entries) {
        await rules.set('stmt.party.${e.key}', e.value, sourceMessageId: messageId);
      }
      if (state.signature.isNotEmpty) {
        await rules.set('stmt.account.${state.signature}', {'account_id': statement.id}, sourceMessageId: messageId);
      }
      return StatementWriteResult(batchId: batchId, transactions: txIds, transfers: transfers);
    });
  }
}

/// The statement's account from memory or from the caption (null = ask).
Future<String?> statementAccountFor(
  AppDatabase db,
  AiRulesMemory rules, {
  required String signature,
  required String cardCurrency,
  String? caption,
}) async {
  final accounts = await db.select(db.budgetAccountsTable).get();
  final remembered = (await rules.get('stmt.account.$signature'))?['account_id']?.toString();
  if (remembered != null && accounts.any((a) => a.id == remembered)) return remembered;
  final text = (caption ?? '').trim();
  if (text.isEmpty) return null;
  final hit = resolveAccount<BudgetAccount>(
    text,
    accounts,
    nameOf: (a) => a.name,
    currencyOf: (a) => a.currency,
    currencyHint: cardCurrency,
  );
  return hit.length == 1 ? hit.first.id : null;
}

/// The summary card's JSON (the `type: 'statement'` draft content).
Map<String, dynamic> statementContent(
  StatementState s,
  StatementPlan? plan, {
  String? accountName,
  String? resultBatch,
}) {
  final rows = s.rows;
  DateTime? lo, hi;
  for (final r in rows) {
    if (lo == null || r.at.isBefore(lo)) lo = r.at;
    if (hi == null || r.at.isAfter(hi)) hi = r.at;
  }
  return {
    'type': 'statement',
    'v': 1,
    'stage': s.stage,
    'file_name': s.fileName,
    'account_id': s.accountId,
    'account_name': accountName,
    'period': {
      'from': lo == null ? null : isoLocalOf(lo),
      'to': hi == null ? null : isoLocalOf(hi),
    },
    'groups': plan?.groups ?? const [],
    'skipped_duplicates': plan?.duplicates ?? const [],
    'cancelled': plan?.cancelled ?? const [],
    'warnings': s.warnings,
    'open_questions': plan?.questions.length ?? 0,
    'confirmed': s.stage == 'done' || s.confirmed,
    'user_confirmed': s.stage == 'done',
    'batch_id': ?resultBatch,
    'state': s.toJson(),
  };
}

/// Readable text for an older app: counts and totals.
String statementBody(StatementState s, StatementPlan? plan, {String? accountName}) {
  if (plan == null) return 'Читаю виписку «${s.fileName}»...';
  final b = StringBuffer('Виписка «${s.fileName}»');
  if (accountName != null) b.write(', рахунок $accountName');
  b.writeln('.');
  var n = 0;
  for (final g in plan.groups) {
    final totals = (g['totals'] as Map).entries.map((e) => '${_fmt((e.value as num).toDouble())} ${e.key}').join(' + ');
    b.writeln('${g['title']}: ${g['count']} оп., $totals');
    n += g['count'] as int;
  }
  b.write('Разом $n оп.');
  if (plan.duplicates.isNotEmpty) b.write(', уже записано ${plan.duplicates.length}');
  if (plan.cancelled.isNotEmpty) b.write(', скасовано ${plan.cancelled.length}');
  b.write('.');
  if (plan.questions.isNotEmpty) b.write(' Потрібні відповіді на питання.');
  return b.toString();
}

/// Rows of [s] inside the message's period (all when none).
List<StatementRow> rowsInPeriod(List<StatementRow> rows, StatementPeriod? period) =>
    period == null ? rows : [for (final r in rows) if (period.contains(r.at)) r];
