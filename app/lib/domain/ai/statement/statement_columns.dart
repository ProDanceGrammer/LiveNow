import '../../search_match.dart' show foldSearch;

/// What a column of a statement holds.
enum StatementRole {
  date,
  time,
  dateTime,
  details,
  counterparty,
  mcc,
  cardAmount,
  opAmount,
  opCurrency,
  cardCurrency,
  rate,
  fee,
  cashback,
  balance,
  debit,
  credit,
  bankCategory,
}

/// The header row of a statement and which column plays which role.
class StatementColumns {
  const StatementColumns({
    required this.headerRow,
    required this.byRole,
    required this.unknown,
    required this.header,
    this.cardCurrency,
  });

  /// Index of the header row in the table; data starts after it.
  final int headerRow;
  final Map<StatementRole, int> byRole;

  /// Non-empty header cells no role was found for.
  final List<String> unknown;
  final List<String> header;

  /// Card currency named in the header, "Сума в валюті картки (UAH)" -> UAH.
  final String? cardCurrency;

  int? operator [](StatementRole r) => byRole[r];
  bool has(StatementRole r) => byRole.containsKey(r);

  bool get hasWhen => has(StatementRole.date) || has(StatementRole.dateTime);
  bool get hasAmount =>
      has(StatementRole.cardAmount) ||
      has(StatementRole.debit) ||
      has(StatementRole.credit) ||
      has(StatementRole.opAmount);

  /// Enough to read rows: a date and an amount.
  bool get usable => hasWhen && hasAmount;

  /// The same layout from the same bank gives the same text (remember the
  /// statement's account under it).
  String get signature =>
      '${[for (final h in header) foldSearch(h)].where((h) => h.isNotEmpty).join('|')}#${cardCurrency ?? ''}';
}

RegExp _re(String p) => RegExp(p, unicode: true);

final _mccWord = _re(r'(?<!\p{L})mcc(?!\p{L})');
final _balanceWord = _re(r'залишок|остаток|balance|bakiye|saldo');
final _cashbackWord = _re(r'кешб|кэшб|cash\s?back');
final _feeWord = _re(r'комісі|комисси|(?<!\p{L})fees?(?!\p{L})|commission|komisyon');
final _rateWord = _re(r'(?<!\p{L})(?:курс|rate|kur|exchange)(?!\p{L})');
final _categoryWord = _re(r'категор|category|kategori');
final _timeWord = _re(r'(?<!\p{L})(?:час|время|time|saat)(?!\p{L})');
final _dateWord = _re(r'дата|date|tarih');
final _debitWord = _re(r'списання|дебет|debit|withdraw|витрат|расход|списани|gider|borç|borc');
final _creditWord = _re(r'зарахування|кредит|credit|deposit|надходж|приход|поступл|зачисл|gelir|alacak');
final _amountWord = _re(r'сума|сумма|amount|tutar|(?<!\p{L})sum(?!\p{L})');
final _currencyWord = _re(r'валют|currency|döviz|doviz|para birimi');
final _cardWord = _re(r'картк|карти|карта|card|kart|рахунк|счет|счёт|account|hesap');
final _opWord = _re(r'операці|транзакці|operation|transaction|işlem|islem');
final _counterWord = _re(
  r'контрагент|отримувач|одержувач|получател|recipient|beneficiary|counterparty|payee|merchant|alıcı|alici',
);
final _detailsWord = _re(
  r'деталі|деталь|опис|призначення|назначение|описание|description|details|açıklama|aciklama|narrative|memo|примітк',
);

/// The role of one header cell (already folded), or null.
StatementRole? roleOfHeader(String folded) {
  final f = folded;
  if (f.isEmpty) return null;
  if (_mccWord.hasMatch(f)) return StatementRole.mcc;
  if (_balanceWord.hasMatch(f)) return StatementRole.balance;
  if (_cashbackWord.hasMatch(f)) return StatementRole.cashback;
  if (_feeWord.hasMatch(f)) return StatementRole.fee;
  if (_rateWord.hasMatch(f)) return StatementRole.rate;
  if (_categoryWord.hasMatch(f)) return StatementRole.bankCategory;
  final hasDate = _dateWord.hasMatch(f);
  final hasTime = _timeWord.hasMatch(f);
  if (hasDate && hasTime) return StatementRole.dateTime;
  if (hasDate) return StatementRole.date;
  if (hasTime) return StatementRole.time;
  if (_debitWord.hasMatch(f)) return StatementRole.debit;
  if (_creditWord.hasMatch(f)) return StatementRole.credit;
  final isCurrency = _currencyWord.hasMatch(f);
  final isAmount = _amountWord.hasMatch(f);
  if (isAmount) {
    // "Сума в валюті операції" is the operation's amount, "в валюті картки" the card's.
    if (_opWord.hasMatch(f) && !_cardWord.hasMatch(f)) return StatementRole.opAmount;
    return StatementRole.cardAmount;
  }
  if (isCurrency) {
    if (_cardWord.hasMatch(f)) return StatementRole.cardCurrency;
    return StatementRole.opCurrency;
  }
  if (_counterWord.hasMatch(f)) return StatementRole.counterparty;
  if (_detailsWord.hasMatch(f)) return StatementRole.details;
  return null;
}

/// Finds the header row among the first 20 rows (3+ cells with a role) and maps
/// the columns; null when no row looks like a header.
StatementColumns? detectStatementColumns(List<List<String>> table) {
  final limit = table.length < 20 ? table.length : 20;
  for (var r = 0; r < limit; r++) {
    final row = table[r];
    final roles = <int, StatementRole>{};
    for (var c = 0; c < row.length; c++) {
      final role = roleOfHeader(foldSearch(row[c]));
      if (role != null) roles[c] = role;
    }
    if (roles.values.toSet().length < 3) continue;
    final byRole = <StatementRole, int>{};
    final unknown = <String>[];
    for (var c = 0; c < row.length; c++) {
      final role = roles[c];
      if (role == null) {
        if (row[c].trim().isNotEmpty) unknown.add(row[c].trim());
      } else {
        byRole.putIfAbsent(role, () => c);
      }
    }
    // "Amount, Currency": with no separate operation amount the currency is the card's.
    if (!byRole.containsKey(StatementRole.opAmount) && byRole.containsKey(StatementRole.opCurrency)) {
      byRole.putIfAbsent(StatementRole.cardCurrency, () => byRole[StatementRole.opCurrency]!);
      byRole.remove(StatementRole.opCurrency);
    }
    String? currency;
    for (final role in [StatementRole.cardAmount, StatementRole.debit, StatementRole.credit, StatementRole.fee]) {
      final c = byRole[role];
      if (c == null) continue;
      final m = RegExp(r'\(([A-Za-z]{3})\)').firstMatch(row[c]);
      if (m != null) {
        currency = m.group(1)!.toUpperCase();
        break;
      }
    }
    return StatementColumns(
      headerRow: r,
      byRole: byRole,
      unknown: unknown,
      header: List.of(row),
      cardCurrency: currency,
    );
  }
  return null;
}
