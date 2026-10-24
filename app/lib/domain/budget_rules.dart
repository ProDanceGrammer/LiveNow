import '../core/local_time.dart';
import '../core/number_rules.dart';
import 'name_sort.dart' show sortKeyIgnoringEmoji;

// Budget rules: the Notion "resource expenditure" formulas, rebuilt as pure
// functions (no database) so they stay testable. Deliberate differences from
// the Notion text (all agreed with the author):
//  * NULL instead of the -1 sentinels; a "group" is a category with children.
//  * Percent categories take their % of the source's MONTHLY plan and are
//    multiplied by the months once (Notion multiplied twice).
//  * The plan counts only the months a category is really active inside the
//    period (start of planning .. end date), not "always one month".
//  * Fact cost is the sum of the transactions' own price x quantity (each
//    transaction snapshots its price and rates), never the units.
//  * Child price fallback counts only active children.

/// Average month length used to turn days into months where a whole calendar
/// month is not available.
const double kDaysPerMonth = 30.4375;
const int kDefaultPeriodMonths = 3;
const double kDefaultTolerance = 10;

enum BudgetUnit {
  piece('piece'),
  kilogram('kilogram'),
  month('month'),
  percentPerMonth('percent_per_month');

  const BudgetUnit(this.db);
  final String db;

  static BudgetUnit fromDb(String value) => BudgetUnit.values.firstWhere(
    (u) => u.db == value,
    orElse: () => BudgetUnit.month,
  );
}

double round2(double v) {
  // `double.round()` throws on NaN / Infinity and saturates at 2^63; a value
  // that large has no cents left anyway.
  if (v.isNaN) return 0;
  if (v.isInfinite || v.abs() >= 1e15) return v;
  return (v * 100).round() / 100;
}

/// Fiat-like currencies are rounded to cents; tiny-rate ones (BTC) are not.
double roundForRate(double v, double rate) => rate > 0.5 ? round2(v) : v;

class BudgetAcct {
  const BudgetAcct({
    required this.id,
    required this.currency,
    required this.rateToBase,
    this.openingBalance = 0,
  });

  final String id;
  final String currency;

  /// Units of this currency per 1 unit of the base currency.
  final double rateToBase;
  final double openingBalance;
}

class BudgetCat {
  const BudgetCat({
    required this.id,
    required this.name,
    this.isIncome = false,
    this.oneTime = false,
    this.unit = BudgetUnit.month,
    this.endDate,
    this.price,
    this.percent,
    this.frequencyMonths,
    this.unitsPerMonth,
    this.parentId,
    this.countPercentOfId,
    this.accountCountId,
    this.accountUseId,
  });

  final String id;
  final String name;
  final bool isIncome;
  final bool oneTime;
  final BudgetUnit unit;
  final DateTime? endDate;
  final double? price;
  final double? percent;
  final double? frequencyMonths;
  final double? unitsPerMonth;
  final String? parentId;
  final String? countPercentOfId;
  final String? accountCountId;
  final String? accountUseId;
}

/// A transaction with its EFFECTIVE date (the linked action's start, else its
/// own date) already resolved by the caller.
class BudgetTx {
  const BudgetTx({
    required this.id,
    required this.date,
    this.categoryId,
    this.actionId,
    this.quantity = 1,
    this.unitPrice = 0,
    this.isIncome = false,
    this.isAmount = false,
    this.accountCountId,
    this.accountUseId,
    this.rateCount,
    this.rateInteract,
  });

  final String id;
  final DateTime date;
  final String? categoryId;
  final String? actionId;
  final double quantity;
  final double unitPrice;
  final bool isIncome;
  final bool isAmount;
  final String? accountCountId;
  final String? accountUseId;
  final double? rateCount;
  final double? rateInteract;

  /// Absolute amount in the counting currency.
  double get countAmount => isAmount ? quantity : unitPrice * quantity;
}

/// Fact = the last [months] months up to and including [asOf]'s day,
/// Plan = the next [months] months from [asOf].
class BudgetPeriod {
  const BudgetPeriod({required this.asOf, this.months = kDefaultPeriodMonths});

  final DateTime asOf;
  final int months;

  DateTime get factStart => calendarAddMonths(asOf, -months);

  /// Exclusive: a transaction dated later today still counts as done.
  DateTime get factEnd => asOf.add(const Duration(days: 1));
  DateTime get planEnd => calendarAddMonths(asOf, months);
}

/// Whole calendar months plus the fraction of the next one between [a] and [b]
/// (0 when [b] is not after [a]). Ends exactly one calendar month after the
/// start => 1.0.
double monthsBetween(DateTime a, DateTime b) {
  if (!b.isAfter(a)) return 0;
  var k = 0;
  while (k < 1200 && !calendarAddMonths(a, k + 1).isAfter(b)) {
    k++;
  }
  final lo = calendarAddMonths(a, k);
  final hi = calendarAddMonths(a, k + 1);
  final span = hi.difference(lo).inMinutes;
  final frac = span == 0 ? 0.0 : b.difference(lo).inMinutes / span;
  return k + frac;
}

/// Months of [from]..[to] during which a category is active
/// ([start]..[end], either may be open).
double activeMonths(
  DateTime? start,
  DateTime? end,
  DateTime from,
  DateTime to,
) {
  final s = start != null && start.isAfter(from) ? start : from;
  final e = end != null && end.isBefore(to) ? end : to;
  return monthsBetween(s, e);
}

/// "Date to start planning": the first transaction's date, one month earlier
/// when that date is still in the future (so it is planned in advance).
DateTime? startOfPlanning(Iterable<DateTime> dates, DateTime asOf) {
  DateTime? first;
  for (final d in dates) {
    if (first == null || d.isBefore(first)) first = d;
  }
  if (first == null) return null;
  return first.isAfter(asOf) ? calendarAddMonths(first, -1) : first;
}

class CategoryFigures {
  const CategoryFigures({
    this.isGroup = false,
    this.monthlyPlan,
    this.planCost = 0,
    this.factCost = 0,
    this.factUnits = 0,
    this.planBase = 0,
    this.factBase = 0,
    this.rate,
    this.noRate = false,
  });

  final bool isGroup;

  /// Planned cost per month in the counting currency (absolute); null for
  /// groups and when nothing in the category lets us derive it.
  final double? monthlyPlan;

  /// Planned / actual cost for the period in the counting currency (absolute).
  final double planCost;
  final double factCost;
  final double factUnits;

  /// Signed (income +, expense -) period amounts in the base currency.
  final double planBase;
  final double factBase;

  /// Current rate of the counting currency (units per 1 base), if known.
  final double? rate;

  /// Something here could not be converted to base (missing account/rate); the
  /// base figures leave that part out.
  final bool noRate;
}

class BudgetSnapshot {
  const BudgetSnapshot({
    required this.byCategory,
    required this.planTotal,
    required this.factTotal,
    required this.noRate,
  });

  final Map<String, CategoryFigures> byCategory;

  /// Top-level categories only, so nothing is counted twice.
  final double planTotal;
  final double factTotal;
  final bool noRate;

  /// Last period's result plus the planned next one (the spec's 600 - 700).
  double get position => round2(planTotal + factTotal);
}

BudgetSnapshot computeBudget({
  required List<BudgetCat> categories,
  required List<BudgetAcct> accounts,
  required List<BudgetTx> transactions,
  required BudgetPeriod period,
}) => _Calc(
  [for (final c in categories) _saneCat(c)],
  [for (final a in accounts) _saneAcct(a)],
  [for (final t in transactions) ?_saneTx(t)],
  period,
).run();

// Stored rows can hold values the services now refuse (old imports, sync from
// an older version): NaN, Infinity or absurd magnitudes. They are cleaned here
// so one bad row never turns every total into NaN or throws.
bool _ok(double? v) => v == null || (v.isFinite && v.abs() <= kMaxNumber);
double? _okOrNull(double? v) => _ok(v) ? v : null;

/// A rate so close to 0 that dividing by it overflows is no rate at all.
bool _okRate(double? v) => _ok(v) && (v == null || v <= 0 || v >= 1e-12);
double? _rateOrNull(double? v) => _okRate(v) ? v : null;

BudgetCat _saneCat(BudgetCat c) =>
    _ok(c.price) && _ok(c.percent) && _ok(c.frequencyMonths) && _ok(c.unitsPerMonth)
    ? c
    : BudgetCat(
        id: c.id,
        name: c.name,
        isIncome: c.isIncome,
        oneTime: c.oneTime,
        unit: c.unit,
        endDate: c.endDate,
        price: _okOrNull(c.price),
        percent: _okOrNull(c.percent),
        frequencyMonths: _okOrNull(c.frequencyMonths),
        unitsPerMonth: _okOrNull(c.unitsPerMonth),
        parentId: c.parentId,
        countPercentOfId: c.countPercentOfId,
        accountCountId: c.accountCountId,
        accountUseId: c.accountUseId,
      );

BudgetAcct _saneAcct(BudgetAcct a) => _okRate(a.rateToBase) && _ok(a.openingBalance)
    ? a
    : BudgetAcct(
        id: a.id,
        currency: a.currency,
        // 0 = "no rate" (flagged), never NaN.
        rateToBase: _okRate(a.rateToBase) ? a.rateToBase : 0,
        openingBalance: _ok(a.openingBalance) ? a.openingBalance : 0,
      );

BudgetTx? _saneTx(BudgetTx t) {
  if (!(_ok(t.quantity) && _ok(t.unitPrice))) return null;
  if (_okRate(t.rateCount) && _okRate(t.rateInteract)) return t;
  return BudgetTx(
    id: t.id,
    date: t.date,
    categoryId: t.categoryId,
    actionId: t.actionId,
    quantity: t.quantity,
    unitPrice: t.unitPrice,
    isIncome: t.isIncome,
    isAmount: t.isAmount,
    accountCountId: t.accountCountId,
    accountUseId: t.accountUseId,
    rateCount: _rateOrNull(t.rateCount),
    rateInteract: _rateOrNull(t.rateInteract),
  );
}

class _Calc {
  _Calc(
    List<BudgetCat> cats,
    List<BudgetAcct> accts,
    List<BudgetTx> txs,
    this.p,
  ) : cats = {for (final c in cats) c.id: c},
      accts = {for (final a in accts) a.id: a} {
    for (final c in cats) {
      final parent = c.parentId;
      if (parent != null && this.cats.containsKey(parent)) {
        (kids[parent] ??= []).add(c);
      }
    }
    for (final t in txs) {
      final id = t.categoryId;
      if (id != null) (txByCat[id] ??= []).add(t);
    }
  }

  final BudgetPeriod p;
  final Map<String, BudgetCat> cats;
  final Map<String, BudgetAcct> accts;
  final Map<String, List<BudgetCat>> kids = {};
  final Map<String, List<BudgetTx>> txByCat = {};
  final Map<String, CategoryFigures> memo = {};

  bool _isGroup(BudgetCat c) => (kids[c.id] ?? const []).isNotEmpty;

  static double? _pos(double? v) => v != null && v > 0 ? v : null;

  BudgetSnapshot run() {
    var plan = 0.0, fact = 0.0, noRate = false;
    for (final c in cats.values) {
      if (c.parentId != null && cats.containsKey(c.parentId)) continue;
      final f = figures(c);
      plan += f.planBase;
      fact += f.factBase;
      noRate = noRate || f.noRate;
    }
    // Make sure every category (also deep ones) has figures.
    for (final c in cats.values) {
      figures(c);
    }
    return BudgetSnapshot(
      byCategory: Map.unmodifiable(memo),
      planTotal: round2(plan),
      factTotal: round2(fact),
      noRate: noRate,
    );
  }

  CategoryFigures figures(BudgetCat c) {
    final cached = memo[c.id];
    if (cached != null) return cached;
    // Guard against a corrupt parent cycle while recursing.
    memo[c.id] = const CategoryFigures();
    final result = _isGroup(c) ? _group(c) : _leaf(c);
    memo[c.id] = result;
    return result;
  }

  CategoryFigures _group(BudgetCat c) {
    var plan = 0.0, fact = 0.0, noRate = false;
    for (final k in kids[c.id]!) {
      final f = figures(k);
      plan += f.planBase;
      fact += f.factBase;
      noRate = noRate || f.noRate;
    }
    return CategoryFigures(
      isGroup: true,
      planBase: round2(plan),
      factBase: round2(fact),
      noRate: noRate,
    );
  }

  /// Current rate of the category's counting currency: the latest rate typed
  /// on one of its transactions, else the counting account's rate.
  double? _rate(BudgetCat c) {
    BudgetTx? latest;
    for (final t in txByCat[c.id] ?? const <BudgetTx>[]) {
      if (_pos(t.rateCount) == null || !t.date.isBefore(p.factEnd)) continue;
      if (latest == null || t.date.isAfter(latest.date)) latest = t;
    }
    if (latest != null) return latest.rateCount;
    final a = accts[c.accountCountId];
    return a == null ? null : _pos(a.rateToBase);
  }

  /// [amount] counted in [from]'s currency, re-expressed in [to]'s.
  double? _convert(double amount, BudgetCat from, BudgetCat to) {
    if (from.accountCountId == to.accountCountId) return amount;
    final fa = accts[from.accountCountId], ta = accts[to.accountCountId];
    if (fa == null || ta == null) return null;
    final fr = _pos(fa.rateToBase), tr = _pos(ta.rateToBase);
    if (fr == null || tr == null) return null;
    return amount / fr * tr;
  }

  /// Planned cost per month (counting currency, absolute) of a leaf.
  double? _monthly(BudgetCat c, Set<String> seen) {
    if (_isGroup(c)) return null;
    if (c.unit == BudgetUnit.percentPerMonth) {
      final src = cats[c.countPercentOfId];
      if (src == null || _isGroup(src) || !seen.add(c.id)) return null;
      final m = _monthly(src, seen);
      if (m == null) return null;
      final conv = _convert(m, src, c);
      if (conv == null) return null;
      return conv * (c.percent ?? 0) / 100;
    }
    final price = _pos(c.price);
    final units = _pos(c.unitsPerMonth);
    final freq = _pos(c.frequencyMonths);
    if (price != null && units != null && freq != null) {
      return price * units / freq;
    }
    if (price != null && units != null) return price * units;
    if (price != null && freq != null) return price / freq;
    if (units != null && freq != null) return units / freq;
    final parent = cats[c.parentId];
    if (parent != null) {
      final pu = _pos(parent.unitsPerMonth);
      if (pu != null && price != null) {
        final active = (kids[parent.id] ?? const <BudgetCat>[])
            .where((k) => k.endDate == null || k.endDate!.isAfter(p.asOf))
            .length;
        if (active > 0) return pu / active * price;
      }
    }
    return null;
  }

  Iterable<BudgetTx> _factTxs(BudgetCat c) =>
      (txByCat[c.id] ?? const <BudgetTx>[]).where(
        (t) => !t.date.isBefore(p.factStart) && t.date.isBefore(p.factEnd),
      );

  /// Actual cost over the fact window (counting currency, absolute).
  double _factCost(BudgetCat c, Set<String> seen) {
    if (c.unit == BudgetUnit.percentPerMonth) {
      if (_factTxs(c).isEmpty) return 0;
      final src = cats[c.countPercentOfId];
      if (src == null || _isGroup(src) || !seen.add(c.id)) return 0;
      final conv = _convert(_factCost(src, seen), src, c);
      return conv == null ? 0 : conv * (c.percent ?? 0) / 100;
    }
    var sum = 0.0;
    for (final t in _factTxs(c)) {
      sum += t.countAmount;
    }
    return sum;
  }

  CategoryFigures _leaf(BudgetCat c) {
    final monthly = _monthly(c, {});
    final start = startOfPlanning(
      (txByCat[c.id] ?? const <BudgetTx>[]).map((t) => t.date),
      p.asOf,
    );
    final active = activeMonths(start, c.endDate, p.asOf, p.planEnd);
    final months = c.oneTime ? (active > 0 ? 1.0 : 0.0) : active;
    final planCost = round2((monthly ?? 0) * months);

    final factCost = round2(_factCost(c, {}));
    var factUnits = 0.0;
    for (final t in _factTxs(c)) {
      factUnits += t.quantity;
    }

    final rate = _rate(c);
    var noRate = false;
    var planBase = 0.0;
    if (planCost != 0) {
      if (rate == null) {
        noRate = true;
      } else {
        planBase = planCost / rate;
      }
    }
    var factBase = 0.0;
    if (c.unit == BudgetUnit.percentPerMonth) {
      if (factCost != 0) {
        if (rate == null) {
          noRate = true;
        } else {
          factBase = (c.isIncome ? 1 : -1) * factCost / rate;
        }
      }
    } else {
      for (final t in _factTxs(c)) {
        final r = _pos(t.rateCount) ?? rate;
        if (r == null) {
          noRate = true;
          continue;
        }
        factBase += (t.isIncome ? 1 : -1) * t.countAmount / r;
      }
    }
    return CategoryFigures(
      monthlyPlan: monthly == null ? null : round2(monthly),
      planCost: planCost,
      factCost: factCost,
      factUnits: round3(factUnits),
      planBase: round2(c.isIncome ? planBase : -planBase),
      factBase: round2(factBase),
      rate: rate,
      noRate: noRate,
    );
  }
}

double round3(double v) => (v * 1000).round() / 1000;

enum BoardColumn { over, under, within }

/// Where a category goes on the Over / Under / Within board: actual vs planned
/// magnitude in the base currency, [tolerance] being the "close enough" band.
BoardColumn classifyPlanFact(double fact, double plan, double tolerance) {
  final a = fact.abs(), b = plan.abs();
  if ((a - b).abs() <= tolerance) return BoardColumn.within;
  return a > b ? BoardColumn.over : BoardColumn.under;
}

class AccountBalance {
  const AccountBalance(this.amount, {this.incomplete = false});

  /// In the account's own currency.
  final double amount;

  /// Some transaction could not be converted (missing rate) and is left out.
  final bool incomplete;
}

/// Opening balance plus every transaction that interacts with the account and
/// is dated up to the end of [now]'s day (planned ones stay out).
Map<String, AccountBalance> computeBalances({
  required List<BudgetAcct> accounts,
  required List<BudgetTx> transactions,
  required DateTime now,
}) {
  final byId = {for (final a in accounts) a.id: a};
  final end = now.add(const Duration(days: 1));
  final sums = {for (final a in accounts) a.id: a.openingBalance};
  final incomplete = <String>{};
  for (final t in transactions) {
    final useId = t.accountUseId;
    final use = byId[useId];
    if (use == null || !t.date.isBefore(end)) continue;
    final amount = transactionInteractAmount(t, byId);
    if (amount == null) {
      incomplete.add(use.id);
    } else {
      sums[use.id] = sums[use.id]! + amount;
    }
  }
  return {
    for (final a in accounts)
      a.id: AccountBalance(
        roundForRate(sums[a.id]!, a.rateToBase),
        incomplete: incomplete.contains(a.id),
      ),
  };
}

/// A transaction's signed amount (income +, expense -) in the currency of the
/// account the money moves through (the spec's "Total Income (Interactional
/// Account)"): the counted amount converted from the counting currency via the
/// transaction's own rates, falling back to the accounts' current ones. Null
/// when there is no such account or a rate is missing. Fiat-like results are
/// rounded to cents.
double? transactionInteractAmount(
  BudgetTx t,
  Map<String, BudgetAcct> accountsById,
) {
  final use = accountsById[t.accountUseId];
  if (use == null) return null;
  final signed = (t.isIncome ? 1 : -1) * t.countAmount;
  if (t.accountCountId == t.accountUseId) return signed;
  final rc =
      _posRate(t.rateCount) ??
      _posRate(accountsById[t.accountCountId]?.rateToBase);
  final ri = _posRate(t.rateInteract) ?? _posRate(use.rateToBase);
  if (rc == null || ri == null) return null;
  return roundForRate(signed * ri / rc, ri);
}

double? _posRate(double? v) => v != null && v > 0 ? v : null;

/// A transaction's signed amount in the BASE (main) currency: the counted
/// amount divided by the transaction's own rate (falling back to its counting
/// account's current one) - the same conversion the category Fact uses. Null
/// when the rate is missing.
double? transactionBaseAmount(
  BudgetTx t,
  Map<String, BudgetAcct> accountsById,
) {
  final r =
      _posRate(t.rateCount) ??
      _posRate(accountsById[t.accountCountId]?.rateToBase);
  if (r == null) return null;
  return round2((t.isIncome ? 1 : -1) * t.countAmount / r);
}

/// One transaction in the three currencies it can be read in: [count] (signed,
/// in the counting account's currency), [interact] (the account the money moves
/// through) and [base] (the main currency). Null = not convertible.
typedef TxAmounts = ({double count, double? interact, double? base});

TxAmounts transactionAmounts(BudgetTx t, Map<String, BudgetAcct> accountsById) =>
    (
      count: (t.isIncome ? 1 : -1) * t.countAmount,
      interact: transactionInteractAmount(t, accountsById),
      base: transactionBaseAmount(t, accountsById),
    );

/// For each category, the action of its nearest FUTURE transaction (groups:
/// the nearest among their descendants). Categories with none are absent.
Map<String, String> upcomingActionByCategory({
  required List<BudgetCat> categories,
  required List<BudgetTx> transactions,
  required DateTime now,
}) {
  final parentOf = {for (final c in categories) c.id: c.parentId};
  final best = <String, BudgetTx>{};
  for (final t in transactions) {
    final action = t.actionId;
    var id = t.categoryId;
    if (action == null || id == null || !t.date.isAfter(now)) continue;
    var guard = 0;
    while (id != null && guard++ < 64) {
      final cur = best[id];
      if (cur == null || t.date.isBefore(cur.date)) best[id] = t;
      id = parentOf[id];
    }
  }
  return {for (final e in best.entries) e.key: e.value.actionId!};
}

/// True if making [newParentId] the parent of [id] would close a loop.
bool wouldCreateParentCycle(
  Map<String, String?> parentOf,
  String id,
  String? newParentId,
) => _reaches(parentOf, newParentId, id);

/// True if "[id] takes a percent of [sourceId]" would close a percent loop.
bool wouldCreatePercentCycle(
  Map<String, String?> percentOf,
  String id,
  String? sourceId,
) => _reaches(percentOf, sourceId, id);

bool _reaches(Map<String, String?> next, String? from, String target) {
  var cur = from;
  var guard = 0;
  while (cur != null && guard++ < 10000) {
    if (cur == target) return true;
    cur = next[cur];
  }
  return false;
}

// ---- dashboard filters ------------------------------------------------------

/// True when [c]'s own end date lies before the as-of day (the day itself still
/// counts as active).
bool categoryEnded(BudgetCat c, DateTime asOf) =>
    c.endDate != null && localDayStart(c.endDate!).isBefore(localDayStart(asOf));

/// Ids of the categories the Plan/Fact boards leave out: a leaf by its own end
/// date, a group only when every leaf below it has ended.
Set<String> endedCategoryIds(Iterable<BudgetCat> categories, DateTime asOf) {
  final byId = {for (final c in categories) c.id: c};
  final children = <String, List<BudgetCat>>{};
  for (final c in categories) {
    final p = c.parentId;
    if (p != null && byId.containsKey(p)) (children[p] ??= []).add(c);
  }
  final memo = <String, bool>{};
  bool ended(BudgetCat c, Set<String> path) {
    final cached = memo[c.id];
    if (cached != null) return cached;
    final kids = children[c.id];
    final result = kids == null
        ? categoryEnded(c, asOf)
        // A parent loop cannot happen (it is refused), but never recurse into one.
        : kids.every((k) => !path.contains(k.id) && ended(k, {...path, c.id}));
    return memo[c.id] = result;
  }

  return {
    for (final c in categories)
      if (ended(c, {c.id})) c.id,
  };
}

/// "Leaves only" shows a category higher when the leaves under it differ only
/// by price: a parent whose DIRECT children are all leaves carrying the
/// parent's own name (emoji and case ignored) is shown as one line, and those
/// leaves are hidden.
({Set<String> hide, Set<String> show}) collapseSameNameLeaves(
  Iterable<BudgetCat> categories,
) {
  final byId = {for (final c in categories) c.id: c};
  final children = <String, List<BudgetCat>>{};
  for (final c in categories) {
    final p = c.parentId;
    if (p != null && byId.containsKey(p)) (children[p] ??= []).add(c);
  }
  final hide = <String>{}, show = <String>{};
  children.forEach((parentId, kids) {
    final key = sortKeyIgnoringEmoji(byId[parentId]!.name);
    final allLeavesSameName = kids.every(
      (k) =>
          !children.containsKey(k.id) && sortKeyIgnoringEmoji(k.name) == key,
    );
    if (allLeavesSameName) {
      show.add(parentId);
      hide.addAll(kids.map((k) => k.id));
    }
  });
  return (hide: hide, show: show);
}
