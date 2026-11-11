/// Builds the [DraftCard] of a receipt or a bazaar note from what was read
/// (`source`) and what the user decided (`overrides`). Deterministic first: the
/// parsers, the alias memory, the category resolver, the price planner and the
/// FX rules do the work; the model (when there is one) only picks among
/// candidate categories. Reads the database, WRITES NOTHING, so it can be run
/// again after every answer or edit.
library;

import 'dart:math' as math;

import '../../core/ids.dart';
import '../../data/ai/llm_client.dart';
import '../../data/database.dart';
import '../budget_rules.dart';
import '../budget_service.dart';
import 'action_matcher.dart';
import 'ai_alias_db_source.dart';
import 'ai_draft.dart';
import 'ai_item_suggester.dart';
import 'job_progress.dart';
import 'ai_protocol.dart';
import 'alias_source.dart';
import 'receipt_memory.dart';
import 'bazaar_parser.dart';
import 'category_match.dart';
import 'category_resolver.dart';
import 'dedupe_service.dart';
import 'extracted_receipt.dart';
import 'line_parser.dart';
import 'model_prompts.dart';
import 'price_planner.dart';
import 'receipt_fx_rules.dart';
import 'sum_verifier.dart';
import 'tr_glossary.dart';
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
  'cikol', 'doritos', 'halley', 'ulker',
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

/// The quick reply that makes a NEW category named [name] under the existing
/// group [group]; [kCreateOption] reads it back from the answer.
String createOptionLabel(String name, String group) => 'Створити «$name» у «$group»';
final kCreateOption = RegExp(r'^Створити «(.+)» у «(.+)»$');

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
  final suggestions = <int, LineSuggestion>{};
  BudgetAccount? useAccount;
  BudgetAccount? defaultCount;
  String? snacksId;

  /// A typed message that says income / spending: a category of the other kind
  /// is held for Confirm instead of being written. Null for photos.
  bool? wantIncome;

  /// One payment read on a bank screenshot: an amount, no pack or weight.
  bool payment = false;

  /// That payment's line is named by the user's message (not the merchant).
  bool named = false;
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

  /// A twin line takes the category choice (`category_id`, `new_name`) of its
  /// first line, unless it has a choice of its own. Stored in the overrides.
  void inheritCategory(int from, int to) {
    final src = lineOv(from);
    if (src['category_id'] == null || lineOv(to)['category_id'] != null) return;
    final lines = overrides['lines'] is Map
        ? Map<String, dynamic>.from(overrides['lines'] as Map)
        : <String, dynamic>{};
    final own = lines['$to'] is Map ? Map<String, dynamic>.from(lines['$to'] as Map) : <String, dynamic>{};
    own['category_id'] = src['category_id'];
    if (src['new_name'] != null) own['new_name'] = src['new_name'];
    lines['$to'] = own;
    overrides['lines'] = lines;
  }

  Map<String, dynamic> get llmChoices {
    final m = overrides['llm'];
    if (m is Map) return Map<String, dynamic>.from(m);
    return {};
  }

  /// What the user typed for line [i] that matched no category (see the runner).
  String? catMiss(int i) {
    final m = overrides['cat_miss'];
    final v = m is Map ? m['$i']?.toString() : null;
    return v == null || v.trim().isEmpty ? null : v.trim();
  }

  /// The group a new category goes under when nothing better is known: the one
  /// with the most categories in it (a real group, not a price-variant wrapper).
  BudgetCategory? get defaultGroup {
    BudgetCategory? best;
    var bestKids = 0;
    for (final c in cats) {
      if (!parents.contains(c.id) || isWrapper(c)) continue;
      if (wantIncome != null && c.isIncome != wantIncome) continue;
      final kids = cats.where((k) => k.parentId == c.id).length;
      if (kids > bestKids) {
        best = c;
        bestKids = kids;
      }
    }
    return best;
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

/// The outcome of [DraftBuilder._lookup].
class _Lookup {
  const _Lookup(this.pick, this.usable, {required this.decided});
  final BudgetCategory? pick;

  /// Fuzzy candidates that are real products (no groups).
  final List<CategoryCandidate> usable;

  /// A rule picked the category; false means the model or the user must.
  final bool decided;
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

  /// A batched suggestion below this is not pre-filled: the line is asked.
  static const double minSuggestConfidence = 0.4;

  /// Rebuilds the draft of [job]. [previous] keeps lines that are already
  /// committed exactly as they were written.
  Future<DraftBuild> build({
    required AiJob job,
    required String kind,
    required Map<String, dynamic> source,
    required Map<String, dynamic> overrides,
    required DateTime messageTime,
    DraftCard? previous,
    StepReporter? onStep,
  }) async {
    _onStep = onStep;
    try {
      return await _build(job, kind, source, overrides, messageTime, previous);
    } finally {
      _onStep = null;
    }
  }

  /// Told before each model call of the [build] in progress (the status line).
  StepReporter? _onStep;

  Future<DraftBuild> _build(
    AiJob job,
    String kind,
    Map<String, dynamic> source,
    Map<String, dynamic> overrides,
    DateTime messageTime,
    DraftCard? previous,
  ) async {
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
    final receiptJson = source['receipt'] is Map
        ? Map<String, dynamic>.from(source['receipt'] as Map)
        : <String, dynamic>{};
    // A purchase told in words: the payer and the currency come from the text, the
    // remembered cash account, or a question (asked once).
    final typed = source['typed'] is Map
        ? Map<String, dynamic>.from(source['typed'] as Map)
        : null;
    final pay = typed == null ? null : await _typedPay(typed, overrides, accounts);
    if (pay != null) receiptJson['currency'] = pay.currency;
    final ex = ExtractedReceipt.fromJson(receiptJson);
    final ctx = _Ctx(
      accounts: accounts,
      cats: cats,
      base: base,
      currency: ex.currency,
      merchant: ex.merchant,
      overrides: overrides,
    );
    ctx.snacksId = await planner.findSnacksCategory();
    ctx.payment = source['payment'] == true;
    ctx.named = ctx.payment && source['named'] == true;
    if (typed != null) {
      ctx.wantIncome = typed['income'] == true;
      if (typed['unparsed'] is List) {
        for (final u in typed['unparsed'] as List) {
          ctx.notes.add('Не вдалося прочитати суму: «$u».');
        }
      }
    }
    if (pay?.question != null) {
      ctx.blockers.add(pay!.question!.id);
      ctx.questions.add(pay.question!);
    }

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
      if (typed == null) ctx.notes.add('Час чека не прочитано: взято час повідомлення.');
    } else if (forcedAt == null && ctx.payment) {
      // A screenshot-only purchase takes its day from the screenshot.
      final shot = overrides['screenshot'];
      if (shot is Map && shot['day_guessed'] == true) {
        ctx.notes.add('День на скріншоті не прочитано: перевірте дату.');
      }
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
    // The tender the user picked in the "which payment" question, and the shop
    // amount of a bank screenshot sent with the receipt (it names the tender).
    final mineTender = (overrides['mine_tender'] as num?)?.toInt();
    final shot = overrides['screenshot'];
    final shopAmount = shot is Map ? (shot['count'] as num?)?.toDouble() : null;
    var mineIdx = List<int>.generate(parsed.lines.length, (i) => i);
    double? expected = ex.total;
    Tender? mine;
    if (ex.tenders.isNotEmpty) {
      final split = splitTenders(
        lineNets: nets,
        tenders: ex.tenders,
        myLast4: myLast4,
        amountHint: shopAmount,
        mineIndex: mineTender,
      );
      mine = mineTender != null && mineTender >= 0 && mineTender < ex.tenders.length
          ? ex.tenders[mineTender]
          : pickMyTender(ex.tenders, myLast4: myLast4, amountHint: shopAmount);
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
          // An answer that matched no tender is said back, so the card is
          // never the identical question again.
          final miss = overrides['mine_miss']?.toString();
          ctx.questions.add(
            Question(
              id: 'mine',
              text: miss == null
                  ? 'На чеку кілька оплат. Яка з них ваша?'
                  : 'Не знайшов оплату «$miss». На чеку кілька оплат: виберіть вашу зі списку.',
              options: [
                for (final t in ex.tenders)
                  '•••• ${t.last4 ?? '?'} — ${t.amount == null ? '?' : fmtMoney(t.amount!)}',
              ],
              optionIds: [
                for (var i = 0; i < ex.tenders.length; i++) 'tender:$i',
              ],
            ),
          );
      }
    }

    // Accounts.
    if (pay != null) {
      ctx.useAccount = pay.account;
      ctx.defaultCount =
          accounts
              .where((a) => a.currency.toUpperCase() == ex.currency.toUpperCase())
              .firstOrNull ??
          pay.account ??
          accounts.first;
    } else {
      await _receiptAccounts(ctx, ex, mine, cardRules);
    }
    String txNameOf(String n) => txNameFor(ex.merchant, n);

    // Lines.
    final prevCommitted = {
      for (final l in previous?.lines ?? const <DraftLine>[])
        if (l.committed) l.index: l,
    };
    final lines = <DraftLine>[];

    // Lines no rule can place get a Ukrainian name and a suggestion, in one go.
    final wanted = <({int index, String printed})>[];
    final firstWanted = <String>{};
    for (final i in mineIdx) {
      final p = parsed.lines[i];
      final ov = ctx.lineOv(i);
      // The same product twice on one receipt is decided (and asked) once.
      if (!firstWanted.add(twinKey(p.name))) continue;
      if (prevCommitted.containsKey(i) ||
          ov['skip'] == true ||
          ov['category_id'] != null ||
          p.net <= 0) {
        continue;
      }
      if (await _namedGroup(ctx, p.name) == null && !(await _lookup(ctx, p.name)).decided) {
        wanted.add((index: i, printed: _stripStars(p.name)));
      }
    }
    if (wanted.isNotEmpty) {
      await _suggestLines(ctx, wanted, translate: source['keep_names'] != true);
    }

    final firstOf = <String, DraftLine>{};
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
        // The glossary's Ukrainian name needs no model (a model suggestion, when
        // there is one, replaces it later).
        uaName: translateKnown(_stripStars(p.name)) ?? glossaryName(_stripStars(p.name)),
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
      final twin = firstOf[twinKey(p.name)];
      if (twin == null) {
        firstOf[twinKey(p.name)] = line;
      } else if (twin.categoryId == null && !twin.skipped && twin.questionIds.any((q) => q.startsWith('cat:'))) {
        // The first of them is waiting for a category: so is this one (one question,
        // one answer for both).
        line.questionIds = [...twin.questionIds.where((q) => q.startsWith('cat:'))];
        lines.add(line);
        continue;
      } else {
        // The user's pick / the model's suggestion for the first applies to its twins.
        ctx.inheritCategory(twin.index, i);
        final s = ctx.suggestions[twin.index];
        if (s != null) ctx.suggestions[i] = s;
      }
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

    // The same receipt confirmed before (same photo, or same shop / minute / total):
    // show what was saved and ask, before anything else.
    final fp = typed != null || (ex.terminalDatetimeLocal ?? ex.invoiceDatetimeLocal) == null
        ? null
        : ReceiptMemory.fingerprint(merchant: ex.merchant, at: at, total: ex.total);
    if (fp != null) ctx.overrides['fp'] = fp;
    SeenReceipt? seen;
    if (typed == null && overrides['seen_ok'] != true && prevCommitted.isEmpty && lines.isNotEmpty) {
      seen = await ReceiptMemory(db, rules).find(
        sha: overrides['photo_sha']?.toString(),
        fp: fp,
        jobId: job.id,
      );
      if (seen != null) {
        ctx.blockers.add('seen');
        ctx.questions
          ..clear()
          ..add(
            Question(
              id: 'seen',
              text: 'Цей чек уже записано (${seen.lines.length} рядків). Що зробити?',
              options: const ['Залишити як є', 'Обробити ще раз', 'Змінити збережене'],
              optionIds: const ['seen:leave', 'seen:again', 'seen:edit'],
              recommended: 0,
            ),
          );
      }
    }

    // Duplicate (I6): asked once, before anything was written.
    var duplicate = false;
    if (seen == null && overrides['dup_ok'] != true && prevCommitted.isEmpty && lines.isNotEmpty) {
      final own = {for (final l in lines) deriveId(job.id, 'tx', l.index)};
      var hits = 0;
      final dedupe = DedupeService(db);
      for (final l in lines) {
        if (l.skipped) continue;
        // A transaction is saved under the line's displayed (translated) name; an
        // older one may carry the printed name: look for both.
        var other = false;
        for (final n in {l.name, l.displayName}) {
          final found = await dedupe.findDuplicates(
            date: at,
            amount: l.amount,
            text: txNameOf(n),
          );
          if (found.any((d) => !own.contains(d.transactionId))) other = true;
        }
        if (other) hits++;
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
      seen: seen?.toJson(),
    );
    return DraftBuild(card, ctx.questions);
  }

  /// Lines with the same printed name are the same product.
  static String twinKey(String name) => productKey(name);

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

  /// Who paid and in what currency for a purchase told in words. The account is,
  /// in order: the user's answer, the one the text names, the remembered cash
  /// account (for "готівкою"), else a question - which is asked once, because the
  /// cash answer is remembered. The currency is the text's, else the account's.
  Future<({BudgetAccount? account, String currency, Question? question})> _typedPay(
    Map<String, dynamic> typed,
    Map<String, dynamic> overrides,
    List<BudgetAccount> accounts,
  ) async {
    BudgetAccount? byId(Object? id) {
      final s = id?.toString();
      return s == null ? null : accounts.where((a) => a.id == s).firstOrNull;
    }

    final hint = typed['currency']?.toString().toUpperCase();
    final cash = typed['cash'] == true;
    var account = byId(overrides['use_account']) ?? byId(typed['account_id']);
    if (account == null && cash) {
      for (final key in hint != null ? ['cash.$hint', 'cash.default'] : ['cash.default', 'cash.TRY']) {
        final a = byId((await rules.get(key))?['account_id']);
        if (a != null && (hint == null || key == 'cash.$hint' || a.currency.toUpperCase() == hint)) {
          account = a;
          break;
        }
      }
    }
    final currency = hint ?? account?.currency.toUpperCase() ?? 'TRY';
    if (account != null) return (account: account, currency: currency, question: null);
    var pool = cash && hint != null
        ? accounts.where((a) => a.currency.toUpperCase() == hint).toList()
        : accounts;
    if (pool.isEmpty) pool = accounts;
    // Only one account can be meant (the one TRY account for "готівкою ... лір"):
    // nothing to ask.
    if (pool.length == 1) {
      return (account: pool.first, currency: hint ?? pool.first.currency.toUpperCase(), question: null);
    }
    final likely = hint == null
        ? -1
        : pool.indexWhere((a) => a.currency.toUpperCase() == hint);
    return (
      account: null,
      currency: currency,
      question: Question(
        id: cash ? 'cash_account' : 'pay_account',
        text: cash ? 'З якого рахунку ви платили готівкою?' : 'З якого рахунку оплачено?',
        options: [for (final a in pool) a.name],
        recommended: likely < 0 ? null : likely,
      ),
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
      // The printed amount stays when quantity x price only differs by rounding
      // (the list edits quantity and price together), so the sum check is exact.
      final product = line.quantity == null ? null : price * line.quantity!;
      if (product != null && (product - line.amount).abs() > math.max(0.02, line.amount * 0.005)) {
        line.amount = _r2(product);
      }
    }
    final unitEdit = ov['unit'];
    if (unitEdit == 'piece' || unitEdit == 'kilogram') line.unit = unitEdit as String;

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
        name: line.displayName,
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
      // No guessing of a pack's weight (the model's gram estimate is NOT used):
      // the receipt says it, or the user is asked / types it into the list.
      // Told in words ("хліб 40"): nobody knows the pack weight, so take the
      // category's usual price. The amount is exact either way; the quantity is
      // flagged as an estimate.
      final usual = chosen.price ?? 0;
      if (line.quantity == null &&
          (ctx.wantIncome != null || ctx.payment) &&
          unit == BudgetUnit.kilogram &&
          usual > 0 &&
          line.amount > 0) {
        line.quantity = line.amount / usual;
        line.unitPrice = usual;
        line.flags = [...line.flags, kFlagWeightGuess];
        unknownWeight = false;
      } else if (line.quantity == null && ctx.payment && line.amount > 0) {
        // A bank payment of something sold by the piece (or with no usual
        // price): one of it, at the amount paid.
        line.quantity = 1;
        line.unitPrice = line.amount;
        unknownWeight = false;
      }
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
    final pick = await _chooseCategoryRaw(ctx, line, ov);
    final want = ctx.wantIncome;
    if (pick == null || want == null || ov['category_id'] != null) return pick;
    if (pick.isIncome != want) {
      // The wording says one thing, the category is the other: show it as a weak
      // guess so Confirm (never auto mode) decides.
      line.flags = [
        for (final f in line.flags)
          if (f != kFlagSuggested) f,
        kFlagSuggested,
      ];
      line.confidence = 0.3;
      ctx.notes.add(
        want
            ? 'Це схоже на дохід, але «${pick.name}» не категорія доходу: перевірте.'
            : '«${pick.name}» - категорія доходу, а повідомлення про витрату: перевірте.',
      );
    }
    return pick;
  }

  Future<BudgetCategory?> _chooseCategoryRaw(
    _Ctx ctx,
    DraftLine line,
    Map<String, dynamic> ov,
  ) async {
    final forcedId = ov['category_id']?.toString();
    final forced = forcedId == null ? null : ctx.byId[forcedId];
    if (forced != null) {
      // "Create «X» under this group": X names the new category.
      final named = ov['new_name']?.toString();
      if (named != null && named.isNotEmpty && ctx.parents.contains(forced.id)) {
        line.uaName = named;
      }
      return forced;
    }

    final named = await _namedGroup(ctx, line.name);
    if (named != null) return _askInGroup(ctx, line, named);

    final look = await _lookup(ctx, line.name);
    if (look.decided) return look.pick;
    final usable = look.usable;

    // The model's suggestion (translated, chosen among the real categories).
    final sug = ctx.suggestions[line.index];
    if (sug != null && sug.uaName.isNotEmpty) line.uaName = sug.uaName;

    // A new category only when the product does not exist yet: a similar name
    // (printed or translated) at the paid price on compatible accounts IS the
    // product, whatever the model said. Similar ones at another price are asked
    // about, never silently replaced by a new category.
    final similar = await _similar(ctx, line, usable, sug);
    final existingPick = sug != null && sug.categoryId != null;
    if (!existingPick) {
      final matchId = findExistingMatch(
        similar,
        unitPrice: line.unitPrice,
        useAccountId: ctx.useAccount?.id,
      );
      final found = matchId == null ? null : ctx.byId[matchId];
      if (found != null) {
        line.confidence = 0.8;
        line.flags = [...line.flags, kFlagSuggested];
        return found;
      }
    }

    if (sug != null && !(sug.isNew && similar.isNotEmpty)) {
      final target = ctx.byId[sug.categoryId ?? sug.groupId];
      if (target != null && sug.confidence >= minSuggestConfidence) {
        line.confidence = sug.confidence;
        line.flags = [...line.flags, kFlagSuggested];
        return target;
      }
    }

    BudgetCategory? pick;
    if (sug == null && usable.isNotEmpty) pick = await _askModel(ctx, line, usable);
    if (pick != null) return pick;

    // Still open: offer the nearest real categories and, when a group is known, a
    // one-tap "create it". What the user typed last time that matched nothing
    // drives the nearest ones, so a miss gets a different, useful card.
    final miss = ctx.catMiss(line.index);
    var choices = similar;
    if (miss != null) {
      final r = await resolver.resolve(miss, limit: kMaxOffered);
      choices = [
        for (final c in r.candidates)
          if (!(c.isAggregate && !ctx.isWrapper(ctx.byId[c.id]!))) c,
      ];
    }
    // The nearest categories, told apart: no id or label twice (a same-named
    // price variant adds nothing), each with its group (`Їжа › Сир`), usual price
    // and unit, so the user can check what a choice is before tapping it.
    final seen = <String>{};
    // The model's own pick, too weak to apply unasked, is still worth offering.
    final weakPick = miss == null && sug != null ? ctx.byId[sug.categoryId] : null;
    line.candidates = [
      if (weakPick != null && (!ctx.parents.contains(weakPick.id) || ctx.isWrapper(weakPick)))
        _choiceOfCategory(ctx, weakPick),
      for (final c in choices) _choiceOf(ctx, c),
    ].where((c) => seen.add(c.id) && seen.add('label:${c.label}')).take(kMaxOffered).toList();
    final group = ctx.byId[sug?.groupId] ?? ctx.defaultGroup;
    final newName = miss ?? line.displayName;
    final create = group == null ? null : createOptionLabel(newName, group.name);
    line.questionIds = [...line.questionIds, 'cat:${line.index}'];
    ctx.questions.add(
      Question(
        id: 'cat:${line.index}',
        text: miss == null
            ? (line.candidates.isEmpty
                  ? 'Яка категорія для «${line.displayName}» (${fmtMoney(line.amount)} ${ctx.currency})?'
                  : 'Знайшов схожі категорії для «${line.displayName}» '
                        '(${fmtMoney(line.amount)} ${ctx.currency}). Оберіть одну або створіть нову.')
            : 'Не знайшов категорію «$miss». Оберіть найближчу, створіть нову або '
                  'напишіть іншу назву.',
        options: [for (final c in line.candidates) c.label, ?create],
        // A tapped option is answered by its id, never by its text.
        optionIds: [
          for (final c in line.candidates) c.id,
          if (create != null) 'create:${group!.id}',
        ],
        recommended: line.candidates.isNotEmpty ? 0 : (create == null ? null : 0),
      ),
    );
    return null;
  }

  /// What rules alone decide about a printed name: a learned alias, the snacks
  /// category, or ONE clearly best fuzzy match. [_Lookup.decided] is false when
  /// the line still needs the model (or the user).
  Future<_Lookup> _lookup(_Ctx ctx, String name) async {
    var res = await resolver.resolve(name);
    var viaGlossary = false;
    if (res.alias == null) {
      // The categories are Ukrainian, the receipt is Turkish: look for the glossary's
      // translation (no model), so `SALATALIK` finds `Огірки`. The learned alias stays
      // keyed by the printed name (above).
      final q = glossaryQuery(_stripStars(name));
      if (q != null) {
        final g = await resolver.resolve(q);
        if (g.candidates.isNotEmpty) {
          res = g;
          viaGlossary = true;
        }
      }
    }
    if (res.alias != null && res.best != null) {
      return _Lookup(ctx.byId[res.best!.id], const [], decided: true);
    }
    if (isSnackName(name) && ctx.snacksId != null) {
      return _Lookup(ctx.byId[ctx.snacksId], const [], decided: true);
    }
    // A group (aggregate that is not a same-name wrapper) is never a product.
    final usable = [
      for (final c in res.candidates)
        if (!(c.isAggregate && !ctx.isWrapper(ctx.byId[c.id]!))) c,
    ];
    // A translation is a weaker key than a printed name: a partial match
    // (`курка філе` ~ `Курка`, score 0.7) is only offered, never picked unasked.
    final strong = !viaGlossary || usable.isNotEmpty && usable.first.score >= 0.8;
    if (usable.isNotEmpty && !res.ambiguous && usable.first.id == res.best?.id && strong) {
      return _Lookup(ctx.byId[usable.first.id], usable, decided: true);
    }
    return _Lookup(null, usable, decided: false);
  }

  /// How many related categories one question lists.
  static const int kMaxOffered = 8;

  /// How many subcategories a "which one in this group" question lists.
  static const int kMaxInGroup = 15;

  /// The user's message names a GROUP of categories for a bank payment
  /// ("кафе і ресторани" over Кафе / Ресторани): that group, else null. A
  /// clearly best match only; a leaf or a same-name wrapper is not a group.
  Future<BudgetCategory?> _namedGroup(_Ctx ctx, String name) async {
    if (!ctx.named) return null;
    final r = await resolver.resolve(name, limit: 3);
    final top = r.candidates.firstOrNull;
    if (top == null || top.fromAlias || !top.isAggregate || top.score < 0.8) return null;
    final c = ctx.byId[top.id];
    return c == null || ctx.isWrapper(c) ? null : c;
  }

  /// The user named [group]: always asked which of its subcategories (no
  /// model, no memory: the same words may mean another one next time).
  BudgetCategory? _askInGroup(_Ctx ctx, DraftLine line, BudgetCategory group) {
    final leaves = <BudgetCategory>[];
    final todo = [group.id];
    while (todo.isNotEmpty && leaves.length < kMaxInGroup) {
      final p = todo.removeAt(0);
      for (final c in ctx.cats.where((c) => c.parentId == p).toList()
        ..sort((a, b) => a.name.compareTo(b.name))) {
        if (ctx.parents.contains(c.id) && !ctx.isWrapper(c)) {
          todo.add(c.id);
        } else {
          leaves.add(c);
        }
      }
    }
    final inGroup = ctx.overrides['in_group'] is Map
        ? Map<String, dynamic>.from(ctx.overrides['in_group'] as Map)
        : <String, dynamic>{};
    inGroup['${line.index}'] = group.id;
    ctx.overrides['in_group'] = inGroup;
    line.candidates = [for (final c in leaves.take(kMaxInGroup)) _choiceOfCategory(ctx, c)];
    final create = createOptionLabel(line.displayName, group.name);
    line.questionIds = [...line.questionIds, 'cat:${line.index}'];
    ctx.questions.add(
      Question(
        id: 'cat:${line.index}',
        text: 'Яка категорія з «${group.name}» для «${line.displayName}» '
            '(${fmtMoney(line.amount)} ${ctx.currency})?',
        options: [for (final c in line.candidates) c.label, create],
        optionIds: [for (final c in line.candidates) c.id, 'create:${group.id}'],
        recommended: null,
      ),
    );
    return null;
  }

  DraftChoice _choiceOf(_Ctx ctx, CategoryCandidate c) {
    final prices = <double>{
      for (final v in c.variants)
        if (v.price != null) v.price!,
    }.toList()..sort();
    return DraftChoice(
      c.id,
      c.name,
      parentName: c.parentName,
      price: c.isAggregate ? null : c.price,
      unit: c.unit.name,
      countAccount: ctx.account(c.accountCountId)?.name,
      useAccount: ctx.account(c.accountUseId)?.name,
      prices: c.isAggregate ? prices : const [],
    );
  }

  DraftChoice _choiceOfCategory(_Ctx ctx, BudgetCategory c) => DraftChoice(
    c.id,
    c.name,
    parentName: ctx.byId[c.parentId]?.name,
    price: c.price,
    unit: BudgetUnit.fromDb(c.unit).name,
    countAccount: ctx.account(c.accountCountId)?.name,
    useAccount: ctx.account(c.accountUseId)?.name,
  );

  /// Existing products whose name resembles the line: the printed name's matches
  /// ([usable]), the glossary translation's and the model's translated name's.
  /// A group is never a product. Those at the paid price come first, so the
  /// question offers them before the others.
  Future<List<CategoryCandidate>> _similar(
    _Ctx ctx,
    DraftLine line,
    List<CategoryCandidate> usable,
    LineSuggestion? sug,
  ) async {
    final seen = <String>{};
    final all = <CategoryCandidate>[];
    void add(Iterable<CategoryCandidate> cs) {
      for (final c in cs) {
        final cat = ctx.byId[c.id];
        if (cat == null || !seen.add(c.id)) continue;
        if (c.isAggregate && !ctx.isWrapper(cat)) continue;
        all.add(c);
      }
    }

    add(usable);
    add((await resolver.resolve(line.name, limit: kMaxOffered)).candidates);
    final gloss = glossaryQuery(_stripStars(line.name));
    if (gloss != null && gloss != line.name) {
      add((await resolver.resolve(gloss, limit: kMaxOffered)).candidates);
    }
    final ua = sug?.uaName;
    if (ua != null && ua.isNotEmpty && ua != line.name && ua != gloss) {
      add((await resolver.resolve(ua, limit: kMaxOffered)).candidates);
    }
    final price = line.unitPrice;
    if (price == null || !(price > 0)) return all;
    bool atPrice(CategoryCandidate c) =>
        (!c.isAggregate && pricesMatch(c.price, price)) ||
        c.variants.any((v) => pricesMatch(v.price, price));
    return [...all.where(atPrice), ...all.where((c) => !atPrice(c))];
  }

  /// One batched model call per receipt: Ukrainian names and category
  /// suggestions for the lines no rule can place. Cached in `overrides['suggest']`
  /// (a rebuild after an answer or an edit never asks again); a model that cannot
  /// be reached is remembered too (`suggest_failed`), so the lines fall back to
  /// questions without waiting for it on every rebuild.
  Future<void> _suggestLines(
    _Ctx ctx,
    List<({int index, String printed})> wanted, {
    bool translate = true,
  }) async {
    final cached = ctx.overrides['suggest'];
    if (cached is Map) {
      cached.forEach((k, v) {
        final i = int.tryParse('$k');
        if (i != null && v is Map) {
          ctx.suggestions[i] = LineSuggestion.fromJson(Map<String, dynamic>.from(v));
        }
      });
    }
    final client = llm;
    if (client == null || ctx.overrides['suggest_failed'] == true) return;
    final todo = [
      for (final w in wanted)
        if (!ctx.suggestions.containsKey(w.index)) w,
    ];
    if (todo.isEmpty) return;
    final suggester = ItemSuggester(llm: client, resolver: resolver);
    try {
      final got = await suggester.suggest(
        items: todo,
        cats: ctx.cats,
        merchant: ctx.merchant,
        onStep: _onStep,
        translate: translate,
      );
      ctx.suggestions.addAll(got);
      ctx.overrides['suggest'] = {
        for (final e in ctx.suggestions.entries) '${e.key}': e.value.toJson(),
      };
      // A bad reply of the model costs its own call only; the reason stays in the
      // card, so the next miss can be read from the data.
      if (suggester.lastError != null) ctx.overrides['suggest_error'] = suggester.lastError;
    } on Object catch (e) {
      ctx.overrides['suggest_failed'] = true;
      final text = '${e.runtimeType}: $e';
      ctx.overrides['suggest_error'] = text.length <= 200 ? text : '${text.substring(0, 200)}...';
    }
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
      await _onStep?.call(JobSteps.choice);
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
