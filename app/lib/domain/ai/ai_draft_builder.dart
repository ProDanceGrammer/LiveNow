/// Builds the [DraftCard] of a receipt or a bazaar note from what was read
/// (`source`) and what the user decided (`overrides`). Deterministic first: the
/// parsers, the alias memory, the category resolver, the price planner and the
/// FX rules do the work; the model (when there is one) only picks among
/// candidate categories. Reads the database, WRITES NOTHING, so it can be run
/// again after every answer or edit.
library;

import '../../core/ids.dart';
import '../../data/ai/llm_client.dart';
import '../../data/database.dart';
import '../budget_rules.dart';
import '../budget_service.dart';
import 'action_matcher.dart';
import 'ai_alias_db_source.dart';
import 'ai_draft.dart';
import 'ai_protocol.dart';
import 'alias_source.dart';
import 'bazaar_parser.dart';
import 'category_resolver.dart';
import 'dedupe_service.dart';
import 'extracted_receipt.dart';
import 'line_parser.dart';
import 'model_prompts.dart';
import 'price_planner.dart';
import 'receipt_fx_rules.dart';
import 'sum_verifier.dart';
import 'unit_normalizer.dart';

export 'ai_draft.dart';

/// A job that cannot succeed by trying again (no accounts, ...): the runner
/// fails it at once with [message].
class AiJobFailure implements Exception {
  const AiJobFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

class DraftBuild {
  const DraftBuild(this.card, this.questions);
  final DraftCard card;

  /// The questions that are open right now (answers are looked up by id).
  final List<Question> questions;
}

const kShopActionName = '🛒 У магазин';
const kBazaarActionName = '🍓 Базар';

const _snackWords = [
  // Ukrainian / English
  'цукерк', 'шоколад', 'чипс', 'печив', 'вафл', 'батончик', 'пряник',
  'мармелад', 'карамел', 'жуйк', 'драже', 'chips', 'chocolate', 'candy',
  'wafer',
  // Turkish (folded: ç->c ş->s ı->i ö->o ü->u ğ->g)
  'cikolata', 'cips', 'bisk', 'gofret', 'sakiz', 'lokum', 'kraker',
  'berliner', 'hashasli', 'jelibon', 'draje',
];

const _pieceOnlyWords = [
  'зелень', 'кріп', 'петрушк', "м'ят", 'maydanoz', 'dereotu', 'nane', 'roka',
  'tere', 'kisnis', 'feslegen', 'deodorant', 'pecete', 'kagit havlu',
  'tuvalet kagidi', 'yumurta', 'defter', 'dis fircasi',
];

bool isSnackName(String name) {
  final f = foldText(name);
  return _snackWords.any(f.contains);
}

bool isPieceOnlyName(String name) {
  final f = foldText(name);
  return _pieceOnlyWords.any(f.contains);
}

String _stripStars(String s) => s.replaceFirst(RegExp(r'^[\s*]+'), '').trim();

/// The transaction name of a line: shop + product.
String txNameFor(String? merchant, String product) =>
    merchant == null || merchant.trim().isEmpty ? product : '$merchant $product';

String fmtMoney(double v) => v.toStringAsFixed(2);

String fmtQty(double v) {
  var s = v.toStringAsFixed(3);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return s;
}

class _Ctx {
  _Ctx({
    required this.accounts,
    required this.cats,
    required this.base,
    required this.currency,
    required this.merchant,
    required this.overrides,
  }) {
    for (final a in accounts) {
      market.putIfAbsent(a.currency.toUpperCase(), () => a.rateToBase);
    }
    for (final c in cats) {
      byId[c.id] = c;
      final p = c.parentId;
      if (p != null) parents.add(p);
    }
  }

  final List<BudgetAccount> accounts;
  final List<BudgetCategory> cats;
  final String base;
  final String currency;
  final String? merchant;
  final Map<String, dynamic> overrides;
  final market = <String, double>{};
  final byId = <String, BudgetCategory>{};
  final parents = <String>{};
  final questions = <Question>[];
  final blockers = <String>[];
  final notes = <String>[];
  BudgetAccount? useAccount;
  BudgetAccount? defaultCount;
  String? snacksId;
  final _fx = <String, ReceiptFx>{};

  BudgetAccount? account(String? id) {
    for (final a in accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  Map<String, dynamic> lineOv(int i) {
    final l = overrides['lines'];
    if (l is Map && l['$i'] is Map) return Map<String, dynamic>.from(l['$i'] as Map);
    return const {};
  }

  Map<String, dynamic> get llmChoices {
    final m = overrides['llm'];
    if (m is Map) return Map<String, dynamic>.from(m);
    return {};
  }

  void rememberChoice(int i, String id) {
    final m = llmChoices;
    m['$i'] = id;
    overrides['llm'] = m;
  }

  bool isWrapper(BudgetCategory c) {
    final key = CategoryResolver.nameKey(c.name);
    return cats.any((k) => k.parentId == c.id && CategoryResolver.nameKey(k.name) == key);
  }

  /// The bank screenshot sent in the same message (`overrides['screenshot']`):
  /// the shop and charged amounts give the rate, else the rate it states.
  double? get screenshotRate {
    final s = overrides['screenshot'];
    if (s is! Map) return null;
    final use = (s['use'] as num?)?.toDouble();
    final count = (s['count'] as num?)?.toDouble();
    if (use != null && count != null && count > 0 && use > 0) {
      return screenshotRateFromAmounts(useAmount: use, countAmount: count);
    }
    final rate = (s['rate'] as num?)?.toDouble();
    return rate != null && rate > 0 ? rate : null;
  }

  ReceiptFx fx(BudgetAccount count, BudgetAccount use) => _fx.putIfAbsent(
    '${count.id}|${use.id}',
    () => computeReceiptRates(
      countCurrency: count.currency,
      useCurrency: use.currency,
      screenshotRate: screenshotRate,
      marketEurRates: market,
      baseCurrency: base,
    ),
  );
}

class DraftBuilder {
  DraftBuilder({
    required this.db,
    required this.aliases,
    required this.rules,
    this.llm,
  }) : budget = BudgetService(db),
       resolver = CategoryResolver(db, aliases: aliases),
       planner = PricePlanner(db, BudgetService(db)),
       matcher = ActionMatcher(db);

  final AppDatabase db;
  final DbAliasSource aliases;
  final AiRulesMemory rules;
  final LlmClient? llm;
  final BudgetService budget;
  final CategoryResolver resolver;
  final PricePlanner planner;
  final ActionMatcher matcher;

  /// Model replies below this confidence become a question.
  static const double minModelConfidence = 0.6;

  /// Rebuilds the draft of [job]. [previous] keeps lines that are already
  /// committed exactly as they were written.
  Future<DraftBuild> build({
    required AiJob job,
    required String kind,
    required Map<String, dynamic> source,
    required Map<String, dynamic> overrides,
    required DateTime messageTime,
    DraftCard? previous,
  }) async {
    final accounts = await db.select(db.budgetAccountsTable).get();
    if (accounts.isEmpty) {
      throw const AiJobFailure('Немає жодного рахунку в бюджеті: створіть рахунок.');
    }
    final cats = await db.select(db.budgetCategoriesTable).get();
    final base = (await budget.settings()).baseCurrency.toUpperCase();
    return kind == AiJobKind.bazaar
        ? _bazaar(job, source, overrides, messageTime, previous, accounts, cats, base)
        : _receipt(job, source, overrides, messageTime, previous, accounts, cats, base);
  }

  // ---- receipt ------------------------------------------------------------------

  Future<DraftBuild> _receipt(
    AiJob job,
    Map<String, dynamic> source,
    Map<String, dynamic> overrides,
    DateTime messageTime,
    DraftCard? previous,
    List<BudgetAccount> accounts,
    List<BudgetCategory> cats,
    String base,
  ) async {
    final ex = ExtractedReceipt.fromJson(
      source['receipt'] is Map
          ? Map<String, dynamic>.from(source['receipt'] as Map)
          : const {},
    );
    final ctx = _Ctx(
      accounts: accounts,
      cats: cats,
      base: base,
      currency: ex.currency,
      merchant: ex.merchant,
      overrides: overrides,
    );
    ctx.snacksId = await planner.findSnacksCategory();

    // When.
    DateTime? at;
    final forcedAt = DateTime.tryParse('${overrides['at'] ?? ''}');
    if (forcedAt != null) {
      at = forcedAt.toUtc();
    } else {
      final text = ex.terminalDatetimeLocal ?? ex.invoiceDatetimeLocal;
      if (text != null) {
        try {
          at = receiptLocalToUtc(text);
        } on FormatException {
          at = null;
        }
      }
    }
    if (at == null) {
      at = messageTime.toUtc();
      ctx.notes.add('Час чека не прочитано: взято час повідомлення.');
    }

    // Lines.
    final weights = await aliases.weightDefaults();
    final pieceKeys = await aliases.pieceOnlyKeys();
    final parsed = parseReceiptLines(
      [for (final l in ex.lines) _withWeight(l, weights)],
      isPieceOnly: (n) =>
          pieceKeys.contains(normalizeReceiptText(_stripStars(n))) ||
          isPieceOnlyName(n),
    );
    for (final w in parsed.warnings) {
      ctx.notes.add(
        w == 'orphan_discount'
            ? 'Знижка без товару зверху: перевірте суму.'
            : 'Рядок кількості без товару: перевірте суму.',
      );
    }
    final nets = [for (final l in parsed.lines) l.net];

    // Tenders (A6).
    final cardRules = await rules.withPrefix('card.');
    final known4 = {
      for (final k in cardRules.keys)
        if (k != 'card.default') k.substring(5),
    };
    final mineLast4 = overrides['mine_last4']?.toString();
    final myLast4 = {...known4, ?mineLast4};
    var mineIdx = List<int>.generate(parsed.lines.length, (i) => i);
    double? expected = ex.total;
    Tender? mine;
    if (ex.tenders.isNotEmpty) {
      final split = splitTenders(lineNets: nets, tenders: ex.tenders, myLast4: myLast4);
      mine = pickMyTender(ex.tenders, myLast4: myLast4);
      switch (split.status) {
        case SplitStatus.allMine:
          expected = split.myAmount ?? ex.total;
        case SplitStatus.split:
          mineIdx = split.mine;
          expected = split.myAmount;
        case SplitStatus.ambiguous:
          mineIdx = split.mine;
          expected = split.myAmount;
          if (overrides['tender_ok'] != true) {
            ctx.blockers.add('tender');
            ctx.questions.add(
              Question(
                id: 'tender',
                text:
                    'Не певен, які рядки сплачено вашою карткою: '
                    '${[for (final i in mineIdx) parsed.lines[i].name].join(', ')}. '
                    'Це правильно?',
                options: const ['Так', 'Ні'],
                recommended: 0,
              ),
            );
          }
        case SplitStatus.noMatch:
          expected = split.myAmount;
          ctx.notes.add('Рядки не збігаються з сумою вашої оплати.');
        case SplitStatus.unknownTender:
          expected = null;
          ctx.blockers.add('mine');
          ctx.questions.add(
            Question(
              id: 'mine',
              text: 'На чеку кілька оплат. Яка з них ваша?',
              options: [
                for (final t in ex.tenders)
                  '•••• ${t.last4 ?? '?'} — ${t.amount == null ? '?' : fmtMoney(t.amount!)}',
              ],
            ),
          );
      }
    }

    // Accounts.
    await _receiptAccounts(ctx, ex, mine, cardRules);
    String txNameOf(String n) => txNameFor(ex.merchant, n);

    // Lines.
    final prevCommitted = {
      for (final l in previous?.lines ?? const <DraftLine>[])
        if (l.committed) l.index: l,
    };
    final lines = <DraftLine>[];
    for (final i in mineIdx) {
      final p = parsed.lines[i];
      final old = prevCommitted[i];
      if (old != null) {
        lines.add(old);
        continue;
      }
      final line = DraftLine(
        index: i,
        raw: p.raw,
        name: p.name,
        amount: p.net,
        quantity: p.quantity,
        unit: switch (p.unit) {
          UnitKind.kilograms => 'kilogram',
          UnitKind.pieces => 'piece',
          UnitKind.unknown => null,
        },
        unitPrice: p.unitPrice,
        flags: [...p.flags],
      );
      await _finishLine(ctx, line, merchant: ex.merchant, unknownWeight: p.questions.contains(kQuestionUnknownWeight));
      lines.add(line);
    }

    // Expected total after skipped lines.
    double? expectedAdj = expected;
    if (expected != null) {
      var adj = expected;
      for (final l in lines) {
        if (l.skipped && !l.committed) adj -= _origNet(parsed, l.index);
      }
      expectedAdj = adj;
    }
    final sum = _sum(lines, expectedAdj);

    // Duplicate (I6): asked once, before anything was written.
    var duplicate = false;
    if (overrides['dup_ok'] != true && prevCommitted.isEmpty && lines.isNotEmpty) {
      final own = {for (final l in lines) deriveId(job.id, 'tx', l.index)};
      var hits = 0;
      final dedupe = DedupeService(db);
      for (final l in lines) {
        if (l.skipped) continue;
        final found = await dedupe.findDuplicates(
          date: at,
          amount: l.amount,
          text: txNameOf(l.name),
        );
        if (found.any((d) => !own.contains(d.transactionId))) hits++;
      }
      final n = lines.where((l) => !l.skipped).length;
      duplicate = n > 0 && (n <= 2 ? hits == n : hits * 2 > n);
      if (duplicate) {
        ctx.blockers.add('dup');
        ctx.questions.add(
          const Question(
            id: 'dup',
            text: 'Схоже, цей чек уже записано. Додати все одно?',
            options: ['Все одно додати', 'Пропустити'],
          ),
        );
      }
    }

    final action = await _action(at, kShopActionName, null);
    final fxOf = lines.isEmpty
        ? null
        : ctx.fx(
            ctx.account(lines.first.countAccountId) ?? ctx.defaultCount!,
            ctx.useAccount ?? ctx.defaultCount!,
          );

    final card = DraftCard(
      jobKind: AiJobKind.receipt,
      at: at,
      merchant: ex.merchant,
      currency: ex.currency,
      useAccountId: ctx.useAccount?.id,
      useAccountName: ctx.useAccount?.name,
      lines: lines,
      sum: sum,
      action: action,
      fxSource: fxOf == null ? 'market' : fxOf.source.name,
      notes: ctx.notes,
      blockers: ctx.blockers,
      duplicate: duplicate,
      source: source,
      overrides: ctx.overrides,
      handled: previous?.handled ?? [],
      applied: previous?.applied ?? [],
      confirmed: previous?.confirmed ?? false,
      userConfirmed: previous?.userConfirmed ?? false,
      counted: previous?.counted ?? false,
      batchId: previous?.batchId,
    );
    return DraftBuild(card, ctx.questions);
  }

  double _origNet(LineParseResult parsed, int i) => parsed.lines[i].net;

  static ReceiptLine _withWeight(ReceiptLine l, Map<String, double> weights) {
    if (weights.isEmpty) return l;
    final hasPack = l.pack != null &&
        ((l.pack!.grams ?? 0) > 0 || (l.pack!.ml ?? 0) > 0 || (l.pack!.count ?? 0) > 0);
    if (hasPack) return l;
    final g = weights[normalizeReceiptText(_stripStars(l.name ?? l.raw))];
    if (g == null) return l;
    return ReceiptLine(
      raw: l.raw,
      name: l.name,
      lineTotal: l.lineTotal,
      qtyLine: l.qtyLine,
      pack: PackSize(grams: g),
      discount: l.discount,
      vatPct: l.vatPct,
      flags: l.flags,
    );
  }

  /// The paying account and the default "count" account of a receipt.
  Future<void> _receiptAccounts(
    _Ctx ctx,
    ExtractedReceipt ex,
    Tender? mine,
    Map<String, Map<String, dynamic>> cardRules,
  ) async {
    final cur = ex.currency.toUpperCase();
    BudgetAccount? inCurrency() {
      for (final a in ctx.accounts) {
        if (a.currency.toUpperCase() == cur) return a;
      }
      return null;
    }

    if (ex.tenders.isEmpty) {
      ctx.useAccount = inCurrency() ?? ctx.accounts.first;
      ctx.notes.add('Спосіб оплати не вказано: рахунок у валюті чека.');
    } else if (mine == null) {
      ctx.useAccount = null; // 'mine' question is open
    } else if (mine.method == 'cash') {
      ctx.useAccount = inCurrency() ?? ctx.accounts.first;
    } else {
      final last4 = mine.last4 ?? 'default';
      final rule = cardRules['card.$last4'] ?? await rules.get('card.$last4');
      ctx.useAccount = ctx.account(rule?['account_id']?.toString());
      if (ctx.useAccount == null) {
        ctx.blockers.add('card:$last4');
        final foreign = [
          for (var i = 0; i < ctx.accounts.length; i++)
            if (ctx.accounts[i].currency.toUpperCase() != cur) i,
        ];
        ctx.questions.add(
          Question(
            id: 'card:$last4',
            text: mine.last4 == null
                ? 'З якого рахунку оплачено цей чек?'
                : 'До якого рахунку належить картка •••• ${mine.last4}?',
            options: [for (final a in ctx.accounts) a.name],
            recommended: foreign.isEmpty ? null : foreign.first,
          ),
        );
      }
    }
    ctx.defaultCount = inCurrency() ?? ctx.useAccount ?? ctx.accounts.first;
  }

  // ---- bazaar -------------------------------------------------------------------

  Future<DraftBuild> _bazaar(
    AiJob job,
    Map<String, dynamic> source,
    Map<String, dynamic> overrides,
    DateTime messageTime,
    DraftCard? previous,
    List<BudgetAccount> accounts,
    List<BudgetCategory> cats,
    String base,
  ) async {
    final note = parseBazaarNote((source['text'] ?? '').toString());
    final ctx = _Ctx(
      accounts: accounts,
      cats: cats,
      base: base,
      currency: 'TRY',
      merchant: 'Базар',
      overrides: overrides,
    );
    ctx.snacksId = await planner.findSnacksCategory();
    final at = (DateTime.tryParse('${overrides['at'] ?? ''}') ?? messageTime).toUtc();

    // Cash account: TRY, remembered when there are several.
    final tryAccounts = [
      for (final a in accounts)
        if (a.currency.toUpperCase() == 'TRY') a,
    ];
    BudgetAccount? cash;
    if (tryAccounts.length == 1) {
      cash = tryAccounts.first;
    } else {
      final rule = await rules.get('cash.TRY');
      cash = ctx.account(rule?['account_id']?.toString());
      if (cash == null) {
        final pool = tryAccounts.isEmpty ? accounts : tryAccounts;
        ctx.blockers.add('cash_account');
        ctx.questions.add(
          Question(
            id: 'cash_account',
            text: 'З якого рахунку ви платили готівкою на базарі?',
            options: [for (final a in pool) a.name],
          ),
        );
      }
    }
    ctx.useAccount = cash;
    ctx.defaultCount = cash ?? accounts.first;

    final prevCommitted = {
      for (final l in previous?.lines ?? const <DraftLine>[])
        if (l.committed) l.index: l,
    };
    final lines = <DraftLine>[];
    for (var i = 0; i < note.items.length; i++) {
      final it = note.items[i];
      final old = prevCommitted[i];
      if (old != null) {
        lines.add(old);
        continue;
      }
      final line = DraftLine(
        index: i,
        raw: it.name,
        name: it.name,
        amount: it.total,
        quantity: it.quantity,
        unit: it.unit == UnitKind.pieces ? 'piece' : 'kilogram',
        unitPrice: it.unitPrice,
        flags: [...it.flags],
      );
      await _finishLine(ctx, line, merchant: 'Базар', unknownWeight: false);
      lines.add(line);
    }
    for (final u in note.unparsed) {
      ctx.notes.add('Не вдалося прочитати ціну: «$u».');
    }
    if (note.items.isEmpty) {
      ctx.notes.add('У нотатці немає позначених [x] рядків.');
    }
    ctx.notes.add('Час покупки взято з часу повідомлення.');

    final action = await _action(at, kBazaarActionName, 'базар');
    final card = DraftCard(
      jobKind: AiJobKind.bazaar,
      at: at,
      merchant: 'Базар',
      currency: 'TRY',
      useAccountId: cash?.id,
      useAccountName: cash?.name,
      lines: lines,
      // A note has no printed total: the sum is informational.
      sum: DraftSum(
        round2(lines.where((l) => !l.skipped).fold(0.0, (a, l) => a + l.amount)),
        note.total,
        0,
        true,
      ),
      action: action,
      fxSource: 'market',
      notes: ctx.notes,
      blockers: ctx.blockers,
      source: source,
      overrides: ctx.overrides,
      handled: previous?.handled ?? [],
      applied: previous?.applied ?? [],
      confirmed: previous?.confirmed ?? false,
      userConfirmed: previous?.userConfirmed ?? false,
      counted: previous?.counted ?? false,
      batchId: previous?.batchId,
    );
    return DraftBuild(card, ctx.questions);
  }

  // ---- shared -------------------------------------------------------------------

  DraftSum _sum(List<DraftLine> lines, double? expected) {
    final sum = verifySum([
      for (final l in lines)
        if (!l.skipped) l.amount,
    ], expected ?? 0);
    return DraftSum(
      sum.linesSum,
      expected,
      expected == null ? 0 : sum.difference,
      expected != null && sum.ok,
    );
  }

  Future<DraftAction?> _action(DateTime at, String newName, String? marker) async {
    final m = await matcher.match(at, bazaarMarker: marker);
    if (m == null) return DraftAction(name: newName, isNew: true);
    final row = await (db.select(db.actionsTable)..where((t) => t.id.equals(m.actionId))).getSingleOrNull();
    return DraftAction(
      id: m.actionId,
      name: row?.name ?? newName,
      isNew: false,
      matchKind: m.kind.name,
    );
  }

  /// Category, quantity, price plan, rates and open questions of one line.
  Future<void> _finishLine(
    _Ctx ctx,
    DraftLine line, {
    required String? merchant,
    required bool unknownWeight,
  }) async {
    final ov = ctx.lineOv(line.index);
    if (ov['skip'] == true) {
      line.skipped = true;
      return;
    }
    if (line.amount <= 0) {
      line.skipped = true;
      line.flags = [...line.flags, 'zero_amount'];
      return;
    }
    // Edits of the user (tap-to-edit / typed correction).
    final q = (ov['quantity'] as num?)?.toDouble();
    final price = (ov['unit_price'] as num?)?.toDouble();
    if (q != null && q > 0) {
      line.quantity = q;
      if (price == null) line.unitPrice = line.amount / q;
      unknownWeight = false;
    }
    if (price != null && price > 0) {
      line.unitPrice = price;
      if (line.quantity != null) line.amount = _r2(price * line.quantity!);
    }

    final chosen = await _chooseCategory(ctx, line, ov);
    if (chosen == null) return; // a category question is open
    line.categoryId = chosen.id;
    line.categoryName = chosen.name;
    line.snacks = chosen.id == ctx.snacksId;

    final count = ctx.account(chosen.accountCountId) ?? ctx.defaultCount!;
    line.countAccountId = count.id;
    final use = ctx.useAccount ?? count;
    final fx = ctx.fx(count, use);
    line.rateCount = fx.rateCount;
    line.rateInteract = fx.rateInteract;
    final wantUse = ctx.useAccount?.id;

    final unit = BudgetUnit.fromDb(chosen.unit);
    final aggregate = ctx.parents.contains(chosen.id);
    final oneOff = aggregate && !ctx.isWrapper(chosen);

    if (line.snacks) {
      line.quantity = line.amount;
      line.unit = 'piece';
      line.unitPrice = 1;
      return;
    }
    if (!aggregate && unit == BudgetUnit.month) {
      line.quantity = quantityForSpend(amount: line.amount, price: chosen.price, unit: unit);
      line.unit = 'month';
      line.unitPrice = chosen.price ?? line.amount;
      line.flags = [...line.flags, 'budget_category'];
      return;
    }
    if (!aggregate && unit == BudgetUnit.percentPerMonth) {
      line.quantity = line.amount;
      line.unit = 'percent';
      line.unitPrice = null;
      return;
    }
    if (oneOff) {
      // C7: a new named piece leaf under the group.
      final pieces = line.unit == 'piece' && (line.quantity ?? 0) > 0 ? line.quantity! : 1.0;
      line.quantity = pieces;
      line.unit = 'piece';
      line.unitPrice = line.amount / pieces;
      line.oneOffGroupId = chosen.id;
      final plan = await planner.planOneOff(
        name: line.name,
        groupId: chosen.id,
        cost: line.unitPrice!,
        accountCountId: count.id,
        accountUseId: wantUse,
      );
      _applyPlanFlags(line, plan);
      line.categoryName = plan.newLeaf?.name ?? line.categoryName;
      return;
    }
    if (line.quantity == null || line.unitPrice == null) {
      if (unknownWeight || line.quantity == null) {
        line.questionIds = [...line.questionIds, 'weight:${line.index}'];
        ctx.questions.add(
          Question(
            id: 'weight:${line.index}',
            text:
                'Яка вага або об’єм однієї упаковки «${line.name}» '
                '(${fmtMoney(line.amount)} ${ctx.currency})?',
            options: const ['100 г', '200 г', '300 г', '500 г', '1 кг', 'за штуку'],
          ),
        );
      }
      return;
    }
    line.unit ??= unit == BudgetUnit.piece ? 'piece' : 'kilogram';
    final plan = await planner.plan(
      categoryId: chosen.id,
      newPrice: line.unitPrice!,
      accountCountId: count.id,
      accountUseId: wantUse,
    );
    _applyPlanFlags(line, plan);
    if (plan.kind == PlanKind.reuseLeaf) {
      final leaf = ctx.byId[plan.leafId];
      line.categoryId = plan.leafId;
      line.categoryName = leaf?.name ?? line.categoryName;
    } else {
      line.categoryName = plan.newLeaf?.name ?? line.categoryName;
    }
  }

  void _applyPlanFlags(DraftLine line, PricePlan plan) {
    line.newCategory = plan.createsCategories;
    line.priceChange = plan.reason == PlanReason.priceChanged;
    if (plan.reason == PlanReason.accountsIncompatible) {
      line.flags = [...line.flags, 'account_change'];
    }
  }

  /// The category of a line, or null (and a question) when it must be asked.
  Future<BudgetCategory?> _chooseCategory(
    _Ctx ctx,
    DraftLine line,
    Map<String, dynamic> ov,
  ) async {
    final forcedId = ov['category_id']?.toString();
    final forced = forcedId == null ? null : ctx.byId[forcedId];
    if (forced != null) return forced;

    final res = await resolver.resolve(line.name);
    if (res.alias != null && res.best != null) return ctx.byId[res.best!.id];
    if (isSnackName(line.name) && ctx.snacksId != null) {
      return ctx.byId[ctx.snacksId];
    }
    // A group (aggregate that is not a same-name wrapper) is never a product.
    final usable = [
      for (final c in res.candidates)
        if (!(c.isAggregate && !ctx.isWrapper(ctx.byId[c.id]!))) c,
    ];
    BudgetCategory? pick;
    if (usable.isNotEmpty && !res.ambiguous && usable.first.id == res.best?.id) {
      pick = ctx.byId[usable.first.id];
    } else if (usable.isNotEmpty) {
      pick = await _askModel(ctx, line, usable);
    }
    if (pick != null) return pick;

    line.candidates = [
      for (final c in usable.take(4)) DraftChoice(c.id, c.name),
    ];
    line.questionIds = [...line.questionIds, 'cat:${line.index}'];
    ctx.questions.add(
      Question(
        id: 'cat:${line.index}',
        text:
            'Яка категорія для «${line.name}» (${fmtMoney(line.amount)} ${ctx.currency})?'
            '${line.candidates.isEmpty ? ' Напишіть назву категорії.' : ''}',
        options: [for (final c in line.candidates) c.name],
        recommended: line.candidates.isEmpty ? null : 0,
      ),
    );
    return null;
  }

  /// The model picks one of [candidates] (or none). Cached per line in the
  /// overrides, so a rebuild does not ask again; a missing / failing model, or a
  /// low confidence, gives null (the caller asks the user).
  Future<BudgetCategory?> _askModel(
    _Ctx ctx,
    DraftLine line,
    List<CategoryCandidate> candidates,
  ) async {
    final cached = ctx.llmChoices['${line.index}']?.toString();
    if (cached != null) return cached == 'none' ? null : ctx.byId[cached];
    final client = llm;
    if (client == null) return null;
    final list = candidates.take(5).toList();
    final options = [
      for (final c in list)
        CandidateCategory(id: c.id, name: c.name, hint: c.parentName),
    ];
    try {
      final reply = await client.runPrompt(
        candidateChoicePrompt(itemText: line.raw, candidates: options, merchant: ctx.merchant),
      );
      final choice = parseCandidateChoice(reply, options);
      final picked = choice.category;
      if (picked != null && choice.confidence >= minModelConfidence) {
        ctx.rememberChoice(line.index, picked.id);
        return ctx.byId[picked.id];
      }
      ctx.rememberChoice(line.index, 'none');
    } on Object {
      // A failing model is not cached: the next rebuild may try again.
    }
    return null;
  }

  static double _r2(double v) => round2(v);
}
