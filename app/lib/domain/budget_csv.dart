import '../core/text_rules.dart';
import 'actions_csv.dart' show parseDatetimeCell;
import 'budget_rules.dart';
import 'growth_import.dart' show parseCsv;

// Parser for the Notion budget exports (Accounts / Categories / Transactions).
// Pure: no database. The exports are lossy, so everything that has to be
// guessed is resolved by documented heuristics and reported in the result
// instead of failing:
//  * Accounts carry no currency or rate: the currency is inferred from the
//    name ("(€)", "Euro", "(₴)", "Turkish Lira", "(TL)", BTC, USDT ...) and the
//    rate is the latest one typed on a transaction that used the account.
//  * Category names repeat (price variants). A parent lists its children by
//    NAME; each child name is matched to a not-yet-claimed row of that name
//    (same accounts preferred). Transactions pick, among the leaf rows of a
//    category name, the one whose accounts and price agree best.
//  * Notion sentinels (-1, 0) for price/frequency/units mean "unknown".

enum BudgetCsvKind { accounts, categories, transactions }

/// Which export a file is, judged by its header; null if unrecognised.
BudgetCsvKind? detectBudgetCsv(String text) {
  final rows = parseCsv(text);
  if (rows.isEmpty) return null;
  final header = rows.first.map((h) => h.trim().toLowerCase()).toList();
  bool has(String part) => header.any((h) => h.contains(part));
  if (has('category name') && has('unit of measure')) {
    return BudgetCsvKind.categories;
  }
  if (has('currency to interact') && has('quantity')) {
    return BudgetCsvKind.transactions;
  }
  if (header.contains('name') && has('type') && !has('quantity')) {
    return BudgetCsvKind.accounts;
  }
  return null;
}

/// Guesses an ISO-like currency code from an account name; null = unknown.
String? inferCurrency(String accountName) {
  final n = accountName.toLowerCase();
  bool any(List<String> parts) => parts.any(n.contains);
  if (any(['usdt'])) return 'USDT';
  if (any(['btc'])) return 'BTC';
  if (any(['€', 'euro', 'eur'])) return 'EUR';
  if (any(['₴', 'uah', 'грн', 'гривн'])) return 'UAH';
  if (any(['turkish lira', '(tl)', '₺', 'try', 'ліра', 'ліри'])) return 'TRY';
  if (any(['\$', 'usd', 'dollar'])) return 'USD';
  return null;
}

class ImportedAccount {
  ImportedAccount({
    required this.name,
    this.type,
    required this.currency,
    required this.rateToBase,
    this.openingBalance = 0,
    this.currencyGuessed = false,
    this.rateFound = true,
  });

  final String name;
  final String? type;
  final String currency;
  double rateToBase;
  final double openingBalance;

  /// The currency could not be inferred from the name (set to XXX).
  final bool currencyGuessed;

  /// No transaction carried a rate for it (kept at 1: edit it by hand).
  bool rateFound;
}

class ImportedCategory {
  ImportedCategory({
    required this.name,
    required this.unit,
    this.accountUseName,
    this.accountCountName,
    this.percentOfName,
    this.childNames = const [],
    this.price,
    this.percent,
    this.frequencyMonths,
    this.unitsPerMonth,
    this.endDate,
    this.oneTime = false,
    this.isIncome = false,
  });

  final String name;
  final BudgetUnit unit;
  final String? accountUseName;
  final String? accountCountName;
  final String? percentOfName;
  final List<String> childNames;
  final double? price;
  final double? percent;
  final double? frequencyMonths;
  final double? unitsPerMonth;
  final DateTime? endDate;
  final bool oneTime;
  final bool isIncome;

  /// Index into [ParsedBudgetImport.categories].
  int? parentIndex;
  int? percentSourceIndex;
}

class ImportedTransaction {
  ImportedTransaction({
    required this.categoryIndex,
    required this.name,
    required this.quantity,
    this.price,
    required this.date,
    this.actionName,
    this.accountUseName,
    this.accountCountName,
    this.rateCount,
    this.rateInteract,
  });

  final int categoryIndex;
  final String name;
  final double quantity;
  final double? price;
  final DateTime date;
  final String? actionName;
  final String? accountUseName;
  final String? accountCountName;
  final double? rateCount;
  final double? rateInteract;
}

class ParsedBudgetImport {
  ParsedBudgetImport({
    required this.accounts,
    required this.categories,
    required this.transactions,
    this.skippedNoCategory = 0,
    this.skippedNoDate = 0,
    this.skippedGroupCategory = 0,
    this.unresolvedChildren = const [],
    this.unresolvedPercentSources = const [],
    this.unknownAccounts = const [],
    this.suspiciousRates = const [],
  });

  final List<ImportedAccount> accounts;
  final List<ImportedCategory> categories;
  final List<ImportedTransaction> transactions;

  /// Transaction rows without a category / without a date (and therefore no
  /// action either) / whose category is a group.
  final int skippedNoCategory;
  final int skippedNoDate;
  final int skippedGroupCategory;

  /// "Parent: child" pairs no row could be found for.
  final List<String> unresolvedChildren;
  final List<String> unresolvedPercentSources;

  /// Account names used by categories/transactions but missing from the
  /// accounts file (created on the fly).
  final List<String> unknownAccounts;

  /// Transactions whose typed exchange rate is far (x2) from the account's
  /// current one: usually a typo in the source (e.g. a rate of 1 for lira).
  final List<String> suspiciousRates;
}

// ---- parsing ----------------------------------------------------------------

double? _number(String s) {
  final v = double.tryParse(s.trim().replaceAll(',', '.'));
  return v;
}

/// Notion uses -1 (and 0) for "unknown".
double? _known(String s) {
  final v = _number(s);
  return v == null || v <= 0 ? null : v;
}

bool _yes(String s) {
  final v = s.trim().toLowerCase();
  return v == 'yes' || v == 'true' || v == '1';
}

BudgetUnit _unit(String s) {
  switch (s.trim().toLowerCase()) {
    case 'piece':
      return BudgetUnit.piece;
    case 'kilogram':
      return BudgetUnit.kilogram;
    case 'percent per month':
      return BudgetUnit.percentPerMonth;
    default:
      return BudgetUnit.month;
  }
}

class _Table {
  _Table(this.rows)
    : _index = {
        for (var i = 0; i < (rows.isEmpty ? 0 : rows.first.length); i++)
          rows.first[i].trim().toLowerCase(): i,
      };

  final List<List<String>> rows;
  final Map<String, int> _index;

  int? col(bool Function(String header) match) {
    for (final e in _index.entries) {
      if (match(e.key)) return e.value;
    }
    return null;
  }

  /// A cell's text; the apostrophe our own export puts before a formula-looking
  /// value is taken off again.
  String cell(List<String> row, int? i) =>
      i == null || i >= row.length ? '' : unguardCsvCell(row[i].trim());
}

/// Parses whichever of the three exports are given. Throws [FormatException]
/// for a file that does not look like its kind, or transactions without
/// categories.
ParsedBudgetImport parseBudgetCsvs({
  String? accountsCsv,
  String? categoriesCsv,
  String? transactionsCsv,
}) {
  final categories = <ImportedCategory>[];
  if (categoriesCsv != null) _parseCategories(categoriesCsv, categories);
  final unresolvedChildren = _linkChildren(categories);
  final unresolvedPercent = _linkPercentSources(categories);

  final accountRows = accountsCsv == null
      ? <_AccountRow>[]
      : _parseAccounts(accountsCsv);

  final txs = <ImportedTransaction>[];
  var noCategory = 0, noDate = 0, group = 0;
  if (transactionsCsv != null) {
    if (categories.isEmpty) {
      throw const FormatException(
        'Transactions need the Categories file: add it to the import.',
      );
    }
    final r = _parseTransactions(transactionsCsv, categories, txs);
    noCategory = r.noCategory;
    noDate = r.noDate;
    group = r.group;
  }

  final accounts = _buildAccounts(accountRows, categories, txs);
  final known = {for (final a in accountRows) a.name};
  final unknown = <String>{};
  void note(String? n) {
    if (n != null && n.isNotEmpty && !known.contains(n)) unknown.add(n);
  }

  for (final c in categories) {
    note(c.accountUseName);
    note(c.accountCountName);
  }
  for (final t in txs) {
    note(t.accountUseName);
    note(t.accountCountName);
  }

  final rateOf = {for (final a in accounts) a.name: a.rateToBase};
  final suspicious = <String>[];
  void checkRate(ImportedTransaction t, String? account, double? rate) {
    final reference = rateOf[account];
    if (rate == null || reference == null || reference <= 0) return;
    final ratio = rate / reference;
    if (ratio >= 0.5 && ratio <= 2) return;
    final day = t.date.toUtc().toIso8601String().substring(0, 10);
    final name = t.name.isEmpty ? '(no name)' : t.name;
    suspicious.add(
      '$name, $day: rate ${rate.toString()} vs $reference ($account)',
    );
  }

  for (final t in txs) {
    checkRate(t, t.accountCountName, t.rateCount);
    checkRate(t, t.accountUseName, t.rateInteract);
  }

  return ParsedBudgetImport(
    accounts: accounts,
    categories: categories,
    transactions: txs,
    suspiciousRates: suspicious,
    skippedNoCategory: noCategory,
    skippedNoDate: noDate,
    skippedGroupCategory: group,
    unresolvedChildren: unresolvedChildren,
    unresolvedPercentSources: unresolvedPercent,
    unknownAccounts: unknown.toList()..sort(),
  );
}

class _AccountRow {
  _AccountRow(this.name, this.type, this.currency, this.rate, this.opening);
  final String name;
  final String? type;
  final String? currency;
  final double? rate;
  final double opening;
}

List<_AccountRow> _parseAccounts(String text) {
  final t = _Table(parseCsv(text));
  if (t.rows.isEmpty) {
    throw const FormatException('The accounts file is empty.');
  }
  final name = t.col((h) => h == 'name');
  if (name == null) {
    throw const FormatException('Accounts: missing column Name');
  }
  final type = t.col((h) => h == 'type');
  final currency = t.col((h) => h == 'currency');
  final rate = t.col((h) => h.startsWith('rate'));
  final opening = t.col((h) => h.startsWith('opening'));
  final out = <_AccountRow>[];
  for (final row in t.rows.skip(1)) {
    final n = t.cell(row, name);
    if (n.isEmpty) continue;
    final ty = t.cell(row, type);
    final cur = t.cell(row, currency);
    out.add(
      _AccountRow(
        n,
        ty.isEmpty ? null : ty,
        cur.isEmpty ? null : cur.toUpperCase(),
        _known(t.cell(row, rate)),
        _number(t.cell(row, opening)) ?? 0,
      ),
    );
  }
  return out;
}

void _parseCategories(String text, List<ImportedCategory> out) {
  final t = _Table(parseCsv(text));
  if (t.rows.isEmpty) {
    throw const FormatException('The categories file is empty.');
  }
  final name = t.col((h) => h.contains('category name'));
  if (name == null) {
    throw const FormatException('Categories: missing column Category name');
  }
  final unit = t.col((h) => h.contains('unit of measure'));
  final use = t.col((h) => h.contains('account to use'));
  final count = t.col((h) => h.contains('account to count'));
  final percentOf = t.col((h) => h.contains('count percent of'));
  final consists = t.col((h) => h.contains('consists of'));
  final price = t.col((h) => h.contains('price per unit'));
  final freq = t.col((h) => h == 'frequency');
  final units = t.col((h) => h.contains('units per month'));
  final end = t.col((h) => h.contains('end date'));
  final once = t.col((h) => h.contains('one-time'));
  final income = t.col((h) => h == 'income');

  String? opt(List<String> row, int? i) {
    final v = t.cell(row, i);
    return v.isEmpty ? null : v;
  }

  for (final row in t.rows.skip(1)) {
    final n = t.cell(row, name);
    if (n.isEmpty) continue;
    final u = _unit(t.cell(row, unit));
    final children = [
      for (final c in t.cell(row, consists).split(','))
        if (c.trim().isNotEmpty) c.trim(),
    ];
    final isGroup = children.isNotEmpty;
    final p = _known(t.cell(row, price));
    out.add(
      ImportedCategory(
        name: n,
        unit: u,
        accountUseName: opt(row, use),
        accountCountName: opt(row, count),
        percentOfName: opt(row, percentOf),
        childNames: children,
        // A group's own numbers are meaningless; a percent row keeps its % in
        // the price column.
        price: isGroup || u == BudgetUnit.percentPerMonth ? null : p,
        percent: !isGroup && u == BudgetUnit.percentPerMonth ? p : null,
        frequencyMonths: isGroup ? null : _known(t.cell(row, freq)),
        unitsPerMonth: isGroup ? null : _known(t.cell(row, units)),
        endDate: parseDatetimeCell(t.cell(row, end))?.start,
        oneTime: _yes(t.cell(row, once)),
        isIncome: _yes(t.cell(row, income)),
      ),
    );
  }
}

bool _isGroup(ImportedCategory c) => c.childNames.isNotEmpty;

/// Assigns every child name to a not-yet-claimed row of that name. Returns the
/// "Parent: child" pairs for which no row exists.
List<String> _linkChildren(List<ImportedCategory> cats) {
  final byName = <String, List<int>>{};
  for (var i = 0; i < cats.length; i++) {
    (byName[cats[i].name] ??= []).add(i);
  }
  bool isAncestor(int candidate, int of) {
    var cur = cats[of].parentIndex;
    var guard = 0;
    while (cur != null && guard++ < 1000) {
      if (cur == candidate) return true;
      cur = cats[cur].parentIndex;
    }
    return false;
  }

  int score(ImportedCategory parent, ImportedCategory child) {
    var s = 0;
    if (child.accountCountName == parent.accountCountName) s += 2;
    if (child.accountUseName == parent.accountUseName) s += 1;
    if (!_isGroup(child)) s += 1; // leaves are the usual children
    return s;
  }

  final unresolved = <String>[];
  for (var p = 0; p < cats.length; p++) {
    final parent = cats[p];
    for (final childName in parent.childNames) {
      int? best;
      var bestScore = -1;
      for (final i in byName[childName] ?? const <int>[]) {
        if (i == p || cats[i].parentIndex != null || isAncestor(i, p)) continue;
        final sc = score(parent, cats[i]);
        if (sc > bestScore) {
          best = i;
          bestScore = sc;
        }
      }
      if (best == null) {
        unresolved.add('${parent.name}: $childName');
      } else {
        cats[best].parentIndex = p;
      }
    }
  }
  return unresolved;
}

List<String> _linkPercentSources(List<ImportedCategory> cats) {
  final unresolved = <String>[];
  for (var i = 0; i < cats.length; i++) {
    final c = cats[i];
    final name = c.percentOfName;
    if (name == null || c.unit != BudgetUnit.percentPerMonth) continue;
    int? best;
    var bestScore = -1;
    for (var j = 0; j < cats.length; j++) {
      final cand = cats[j];
      if (j == i || cand.name != name || _isGroup(cand)) continue;
      final sc =
          (cand.accountCountName == c.accountCountName ? 2 : 0) +
          (cand.unit != BudgetUnit.percentPerMonth ? 1 : 0);
      if (sc > bestScore) {
        best = j;
        bestScore = sc;
      }
    }
    if (best == null) {
      unresolved.add('${c.name}: $name');
    } else {
      c.percentSourceIndex = best;
    }
  }
  return unresolved;
}

({int noCategory, int noDate, int group}) _parseTransactions(
  String text,
  List<ImportedCategory> cats,
  List<ImportedTransaction> out,
) {
  final t = _Table(parseCsv(text));
  if (t.rows.isEmpty) {
    throw const FormatException('The transactions file is empty.');
  }
  final category = t.col((h) => h == 'category');
  if (category == null) {
    throw const FormatException('Transactions: missing column Category');
  }
  final interact = t.col((h) => h.contains('currency to interact'));
  final countCur = t.col((h) => h.contains('currency to count'));
  final action = t.col((h) => h == 'action');
  final name = t.col((h) => h.contains('transaction name'));
  final qty = t.col((h) => h == 'quantity');
  final price = t.col((h) => h == 'price');
  final date = t.col((h) => h == 'date');
  final rateInteract = t.col(
    (h) => h.contains('rate') && h.contains('interact'),
  );
  final rateCount = t.col((h) => h.contains('rate') && !h.contains('interact'));

  final byName = <String, List<int>>{};
  for (var i = 0; i < cats.length; i++) {
    (byName[cats[i].name] ??= []).add(i);
  }

  var noCategory = 0, noDate = 0, group = 0;
  for (final row in t.rows.skip(1)) {
    if (row.every((c) => c.trim().isEmpty)) continue;
    final catName = t.cell(row, category);
    if (catName.isEmpty) {
      noCategory++;
      continue;
    }
    final parsed = parseDatetimeCell(t.cell(row, date));
    if (parsed == null) {
      noDate++;
      continue;
    }
    final interactName = t.cell(row, interact);
    final countName = t.cell(row, countCur);
    final p = _known(t.cell(row, price));

    final candidates = byName[catName] ?? const <int>[];
    int? best;
    var bestScore = -1;
    var sawGroup = false;
    for (final i in candidates) {
      final c = cats[i];
      if (_isGroup(c)) {
        sawGroup = true;
        continue;
      }
      var s = 0;
      if (interactName.isNotEmpty && c.accountUseName == interactName) s += 2;
      if (countName.isNotEmpty && c.accountCountName == countName) s += 2;
      if (p != null && c.price == p) s += 1;
      if (s > bestScore) {
        best = i;
        bestScore = s;
      }
    }
    if (best == null) {
      if (sawGroup) group++;
      continue;
    }

    final actionName = t.cell(row, action);
    out.add(
      ImportedTransaction(
        categoryIndex: best,
        name: t.cell(row, name),
        quantity: _number(t.cell(row, qty)) ?? 1,
        price: p,
        date: parsed.start,
        actionName: actionName.isEmpty ? null : actionName,
        accountUseName: interactName.isEmpty ? null : interactName,
        accountCountName: countName.isEmpty ? null : countName,
        rateCount: _known(t.cell(row, rateCount)),
        rateInteract: _known(t.cell(row, rateInteract)),
      ),
    );
  }
  return (noCategory: noCategory, noDate: noDate, group: group);
}

/// Builds the accounts: the listed ones first, then any only referenced by
/// categories/transactions. The rate is the one from the latest transaction
/// that used the account (as counting or interacting account).
List<ImportedAccount> _buildAccounts(
  List<_AccountRow> rows,
  List<ImportedCategory> cats,
  List<ImportedTransaction> txs,
) {
  final latest = <String, ({DateTime date, double rate})>{};
  void see(String? account, double? rate, DateTime date) {
    if (account == null || rate == null || rate <= 0) return;
    final cur = latest[account];
    if (cur == null || date.isAfter(cur.date)) {
      latest[account] = (date: date, rate: rate);
    }
  }

  for (final t in txs) {
    see(t.accountCountName, t.rateCount, t.date);
    see(t.accountUseName, t.rateInteract, t.date);
  }

  final names = <String>[];
  void add(String? n) {
    if (n != null && n.isNotEmpty && !names.contains(n)) names.add(n);
  }

  for (final r in rows) {
    add(r.name);
  }
  for (final c in cats) {
    add(c.accountUseName);
    add(c.accountCountName);
  }
  for (final t in txs) {
    add(t.accountUseName);
    add(t.accountCountName);
  }

  final byName = {for (final r in rows) r.name: r};
  return [
    for (final n in names)
      () {
        final row = byName[n];
        final inferred = row?.currency ?? inferCurrency(n);
        final currency = inferred ?? 'XXX';
        final seen = latest[n]?.rate;
        final isEur = currency == 'EUR';
        final rate = row?.rate ?? (isEur ? 1.0 : seen) ?? 1.0;
        return ImportedAccount(
          name: n,
          type: row?.type,
          currency: currency,
          rateToBase: rate,
          openingBalance: row?.opening ?? 0,
          currencyGuessed: inferred == null,
          rateFound: row?.rate != null || isEur || seen != null,
        );
      }(),
  ];
}
