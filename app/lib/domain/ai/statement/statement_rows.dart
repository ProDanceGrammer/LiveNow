import '../ai_transfer_text.dart' show parseAmountText;
import 'statement_columns.dart';

/// One operation of a statement.
class StatementRow {
  const StatementRow({
    required this.index,
    required this.at,
    required this.details,
    required this.cardAmount,
    required this.cardCurrency,
    this.mcc,
    this.opAmount,
    this.opCurrency,
    this.rate,
    this.fee,
    this.cashback,
    this.balance,
    this.bankCategory,
  });

  /// Index of the row in the table (0-based, header included).
  final int index;

  /// Wall-clock time as printed in the file.
  final DateTime at;
  final String details;
  final int? mcc;

  /// Signed: money out is negative.
  final double cardAmount;
  final String cardCurrency;

  /// Signed like [cardAmount]; the amount in the currency of the operation.
  final double? opAmount;
  final String? opCurrency;
  final double? rate;

  /// Positive when the bank took a fee.
  final double? fee;

  /// Positive cashback earned by this operation.
  final double? cashback;
  final double? balance;
  final String? bankCategory;

  /// Paid in a currency other than the card's.
  bool get isForeign =>
      opAmount != null && opCurrency != null && opCurrency != cardCurrency;
}

class StatementSkip {
  const StatementSkip(this.index, this.reason);
  final int index;
  final String reason;
}

class StatementParse {
  const StatementParse({
    required this.rows,
    required this.columns,
    this.skipped = const [],
    this.warnings = const [],
  });

  final List<StatementRow> rows;

  /// Null when no header row was recognised.
  final StatementColumns? columns;
  final List<StatementSkip> skipped;
  final List<String> warnings;
}

StatementParse parseStatementRows(
  List<List<String>> table, {
  String defaultCardCurrency = 'UAH',
}) {
  final cols = detectStatementColumns(table);
  if (cols == null) {
    return const StatementParse(
      rows: [],
      columns: null,
      warnings: ['Не знайдено рядок із назвами колонок (дата, сума, ...).'],
    );
  }
  final warnings = <String>[];
  if (!cols.usable) {
    warnings.add(
      'Не вистачає колонки ${cols.hasWhen ? 'із сумою' : 'з датою'}.',
    );
    return StatementParse(rows: const [], columns: cols, warnings: warnings);
  }

  String cell(List<String> row, StatementRole role) {
    final i = cols[role];
    return i == null || i >= row.length ? '' : row[i].trim();
  }

  final data = <MapEntry<int, List<String>>>[
    for (var i = cols.headerRow + 1; i < table.length; i++) MapEntry(i, table[i]),
  ];
  // dd/MM/yyyy unless the file proves MM/dd/yyyy: a slash date whose SECOND
  // field is above 12 (and none whose first field is).
  final dateRole = cols.has(StatementRole.dateTime) ? StatementRole.dateTime : StatementRole.date;
  var firstAbove = false, secondAbove = false;
  for (final e in data) {
    final m = RegExp(r'^\s*(\d{1,2})/(\d{1,2})/\d{2,4}').firstMatch(cell(e.value, dateRole));
    if (m == null) continue;
    if (int.parse(m.group(1)!) > 12) firstAbove = true;
    if (int.parse(m.group(2)!) > 12) secondAbove = true;
  }
  final mdy = secondAbove && !firstAbove;

  final rows = <StatementRow>[];
  final skipped = <StatementSkip>[];
  for (final e in data) {
    final r = e.value;
    final index = e.key;
    final dateText = cell(r, dateRole);
    var at = parseStatementDate(dateText, monthFirst: mdy);
    if (at == null) {
      skipped.add(StatementSkip(index, 'дата: "$dateText"'));
      continue;
    }
    final timeText = cell(r, StatementRole.time);
    if (timeText.isNotEmpty && !RegExp(r'\d:\d{2}').hasMatch(dateText)) {
      final t = RegExp(r'(\d{1,2})[:.](\d{2})(?:[:.](\d{2}))?').firstMatch(timeText);
      if (t != null) {
        at = DateTime(at.year, at.month, at.day, int.parse(t.group(1)!), int.parse(t.group(2)!),
            int.tryParse(t.group(3) ?? '') ?? 0);
      }
    }

    double? card = parseSignedAmount(cell(r, StatementRole.cardAmount));
    if (card == null) {
      final debit = parseSignedAmount(cell(r, StatementRole.debit));
      final credit = parseSignedAmount(cell(r, StatementRole.credit));
      if (debit != null && debit != 0) {
        card = -debit.abs();
      } else if (credit != null && credit != 0) {
        card = credit.abs();
      } else if (debit != null || credit != null) {
        card = 0;
      }
    }
    var op = parseSignedAmount(cell(r, StatementRole.opAmount));
    final opCur = _currencyCode(cell(r, StatementRole.opCurrency));
    card ??= op;
    if (card == null) {
      skipped.add(StatementSkip(index, 'немає суми'));
      continue;
    }
    if (op != null && card != 0 && (op < 0) != (card < 0)) {
      op = card < 0 ? -op.abs() : op.abs();
    }
    final cardCur = _currencyCode(cell(r, StatementRole.cardCurrency)) ??
        cols.cardCurrency ??
        defaultCardCurrency;
    final mccText = cell(r, StatementRole.mcc);
    final category = cell(r, StatementRole.bankCategory);
    final details = [
      cell(r, StatementRole.details),
      if (cell(r, StatementRole.counterparty).isNotEmpty &&
          cell(r, StatementRole.counterparty) != cell(r, StatementRole.details))
        cell(r, StatementRole.counterparty),
    ].where((s) => s.isNotEmpty).join(' ');
    rows.add(
      StatementRow(
        index: index,
        at: at,
        details: details,
        mcc: int.tryParse(mccText),
        cardAmount: card,
        cardCurrency: cardCur,
        opAmount: op,
        opCurrency: op == null ? null : (opCur ?? cardCur),
        rate: parseAmountText(cell(r, StatementRole.rate)),
        fee: parseAmountText(cell(r, StatementRole.fee).replaceFirst(RegExp(r'^[-−–]'), '')),
        cashback: parseAmountText(cell(r, StatementRole.cashback).replaceFirst(RegExp(r'^[-−–]'), '')),
        balance: parseSignedAmount(cell(r, StatementRole.balance)),
        bankCategory: _isEmptyCell(category) ? null : category,
      ),
    );
  }
  if (cols.unknown.isNotEmpty) {
    warnings.add('Колонки без ролі: ${cols.unknown.join(', ')}.');
  }
  if (rows.isEmpty) warnings.add('Не знайдено жодної операції.');
  return StatementParse(rows: rows, columns: cols, skipped: skipped, warnings: warnings);
}

bool _isEmptyCell(String s) => s.isEmpty || RegExp(r'^[—–−-]+$').hasMatch(s);

/// "UAH", "грн", "₴", "TL" -> ISO code; null when empty.
String? _currencyCode(String s) {
  final t = s.trim();
  if (_isEmptyCell(t)) return null;
  final l = t.toLowerCase();
  if (RegExp(r'^(?:грн|гривн\p{L}*|₴)$', unicode: true).hasMatch(l)) return 'UAH';
  if (RegExp(r'^(?:tl|₺|лір\p{L}*)$', unicode: true).hasMatch(l)) return 'TRY';
  if (l == '€') return 'EUR';
  if (l == r'$') return 'USD';
  final m = RegExp(r'[A-Za-z]{3}').firstMatch(t);
  return m?.group(0)!.toUpperCase();
}

/// "-117,13", "−1 200.50 UAH", "(45.00)", "+12" -> signed number; "—", "-" and
/// "" -> null. A literal zero is 0.0.
double? parseSignedAmount(String s) {
  var t = s.trim();
  if (_isEmptyCell(t)) return null;
  var negative = false;
  if (t.startsWith('(') && t.contains(')')) negative = true;
  if (RegExp(r'^[^\d]*[-−–]').hasMatch(t.split(RegExp(r'\d')).first)) negative = true;
  t = t.replaceAll(RegExp(r'[^\d.,\s  ]'), '');
  final v = parseAmountText(t);
  if (v == null) return RegExp(r'^[0\s.,]+$').hasMatch(t) && t.contains('0') ? 0.0 : null;
  return negative ? -v : v;
}

/// dd.MM.yyyy[ HH:mm[:ss]], yyyy-MM-dd[ HH:mm[:ss]], dd/MM/yyyy (MM/dd when
/// [monthFirst]); null when it is not a date.
DateTime? parseStatementDate(String s, {bool monthFirst = false}) {
  final m = RegExp(
    r'^\s*(\d{1,4})([./-])(\d{1,2})[./-](\d{1,4})(?:[ T,]+(\d{1,2}):(\d{2})(?::(\d{2}))?)?',
  ).firstMatch(s);
  if (m == null) return null;
  final a = m.group(1)!;
  final b = int.parse(m.group(3)!);
  final c = m.group(4)!;
  int year, month, day;
  if (a.length == 4) {
    year = int.parse(a);
    month = b;
    day = int.parse(c);
  } else {
    final first = int.parse(a);
    year = int.parse(c);
    if (c.length <= 2) year += 2000;
    if (monthFirst && m.group(2) == '/') {
      month = first;
      day = b;
    } else {
      day = first;
      month = b;
    }
  }
  if (month < 1 || month > 12 || day < 1 || day > 31 || year < 1990 || year > 2200) return null;
  final d = DateTime(
    year,
    month,
    day,
    int.tryParse(m.group(5) ?? '') ?? 0,
    int.tryParse(m.group(6) ?? '') ?? 0,
    int.tryParse(m.group(7) ?? '') ?? 0,
  );
  return d.month == month ? d : null;
}
