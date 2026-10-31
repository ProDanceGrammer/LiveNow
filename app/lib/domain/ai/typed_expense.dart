/// A purchase told in words ("купив каву 150, хліб 40 готівкою вчора") read into
/// items, a cash flag, a currency, a day and (optionally) an account. Pure: no
/// database, no model. The result becomes an [ExtractedReceipt], so the typed
/// path shares everything the photo path does (names, categories, units, draft).
library;

import 'extracted_receipt.dart';
import 'unit_normalizer.dart' show UnitKind;

class TypedItem {
  const TypedItem({
    required this.raw,
    required this.name,
    required this.amount,
    this.quantity,
    this.unit = UnitKind.unknown,
    this.unitPrice,
  });

  final String raw;
  final String name;

  /// What was paid for the item.
  final double amount;
  final double? quantity;
  final UnitKind unit;
  final double? unitPrice;
}

class TypedExpense {
  const TypedExpense({
    required this.items,
    this.cash = false,
    this.currency,
    this.day,
    this.income = false,
    this.accountIndex,
    this.explicit = false,
    this.unparsed = const [],
  });

  final List<TypedItem> items;
  final bool cash;

  /// ISO code the text names ("лір" -> TRY), else null.
  final String? currency;

  /// The calendar day the text names ("вчора"), else null (the message time).
  final DateTime? day;
  final bool income;

  /// Index into the account names given to [parseTypedExpense], when one is named.
  final int? accountIndex;

  /// Words that only a purchase message has (a verb, cash, a currency, a day, an
  /// account, several items). A bare "кава 150" is not explicit: while a draft
  /// waits it may be a correction of it.
  final bool explicit;

  /// Segments with no readable amount.
  final List<String> unparsed;

  double get total => (items.fold(0.0, (a, i) => a + i.amount) * 100).round() / 100;

  /// The same purchase as a receipt: [currency] is the one the builder settled on.
  ExtractedReceipt toReceipt(String currency) => ExtractedReceipt(
    currency: currency,
    total: total,
    invoiceDatetimeLocal: day == null
        ? null
        : '${day!.year.toString().padLeft(4, '0')}-${_two(day!.month)}-${_two(day!.day)}T12:00:00',
    lines: [
      for (final i in items)
        ReceiptLine(
          raw: i.raw,
          name: i.name,
          lineTotal: i.amount,
          qtyLine: i.quantity == null
              ? null
              : QtyLine(
                  qty: i.quantity,
                  unit: i.unit == UnitKind.kilograms ? 'kg' : 'ad',
                  unitPrice: i.unitPrice,
                ),
        ),
    ],
  );
}

String _two(int n) => n.toString().padLeft(2, '0');

RegExp _word(String alt) => RegExp('(?<![\\p{L}\\d])(?:$alt)(?![\\p{L}\\d])', unicode: true);

/// A currency sign or word may follow a number directly ("150лір").
RegExp _cur(String alt) => RegExp('(?<![\\p{L}])(?:$alt)(?![\\p{L}\\d])', unicode: true);

final _income = _word(
  'отримав|отримала|отримали|надійшло|надійшли|заробив|заробила|дохід|доход|income|received',
);
final _cash = _word(r'готівк\p{L}*|кеш\p{L}*|налом|налічк\p{L}*|cash');
final _beforeYesterday = _word('позавчора');
final _yesterday = _word('вчора|yesterday');
final _today = _word('сьогодні|today');
final _fullDate = RegExp(r'(?<!\d)(\d{1,2})[./](\d{1,2})[./](\d{2,4})(?!\d)');
final _shortDate = RegExp(
  r'(?<![\p{L}\d])(?:за|від|on)\s+(\d{1,2})[./](\d{1,2})(?!\d)',
  unicode: true,
);
final _verb = RegExp(
  r'^\s*(?:купив|купила|купили|витратив|витратила|заплатив|заплатила|оплатив|оплатила|взяв|взяла|bought|paid|spent)(?![\p{L}])\s*',
  unicode: true,
);
final _currencies = <String, RegExp>{
  'TRY': _cur(r'лір\p{L}*|lira|tl|try|₺'),
  'UAH': _cur(r'грн|гривн\p{L}*|uah|₴'),
  'USD': _cur(r'usd|\$|долар\p{L}*|бакс\p{L}*'),
  'EUR': _cur(r'eur|€|євро'),
};
final _preposition = RegExp(
  r'(?:з|із|зі|через|картою|карткою|рахунку|рахунок|на|from|with|by)\s+$',
  unicode: true,
);

const _n = r'(\d+(?:[.,]\d+)?)';
const _u = r'(кг|kg|гр|г|g|штуки|штук|шт|pcs|мл|ml|л|l)';
const _name = r'(.*?\p{L}.*?)';
final _qtyTimes = RegExp('^$_name\\s+$_n\\s*$_u?\\s*[x×*х]\\s*$_n\$', unicode: true);
final _qtyPer = RegExp('^$_name\\s+$_n\\s*$_u\\s+(?:по|@|at)\\s*$_n\$', unicode: true);
final _qtyTotal = RegExp('^$_name\\s+$_n\\s*$_u\\s+$_n\$', unicode: true);
final _plain = RegExp('^$_name\\s+$_n\$', unicode: true);
final _lead = RegExp('^$_n\\s+(\\p{L}.*)\$', unicode: true);

double _d(String s) => double.parse(s.replaceAll(',', '.'));
double _r2(double v) => (v * 100).round() / 100;

/// [accountNames] are the accounts' names without their "(₴)" tag; the account the
/// text names (the longest full name, else a word only one account has) is
/// removed from the text and returned as an index. [now] is the message time in
/// the user's local zone. Null when no item with an amount is found.
TypedExpense? parseTypedExpense(
  String text, {
  required DateTime now,
  List<String> accountNames = const [],
}) {
  var w = text.trim().toLowerCase();
  if (w.isEmpty || w.length > 800) return null;
  var explicit = false;

  final verb = _verb.firstMatch(w);
  if (verb != null) {
    explicit = true;
    w = w.substring(verb.end);
  }
  final income = _income.hasMatch(w);
  if (income) {
    explicit = true;
    w = w.replaceAll(_income, ' ');
  }
  final cash = _cash.hasMatch(w);
  if (cash) {
    explicit = true;
    w = w.replaceAll(_cash, ' ');
  }

  DateTime? day;
  final today = DateTime(now.year, now.month, now.day);
  if (_beforeYesterday.hasMatch(w)) {
    day = DateTime(today.year, today.month, today.day - 2);
    w = w.replaceAll(_beforeYesterday, ' ');
  } else if (_yesterday.hasMatch(w)) {
    day = DateTime(today.year, today.month, today.day - 1);
    w = w.replaceAll(_yesterday, ' ');
  } else if (_today.hasMatch(w)) {
    day = today;
    w = w.replaceAll(_today, ' ');
  } else {
    final m = _fullDate.firstMatch(w);
    if (m != null) {
      day = _dayOf(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!), today);
      w = w.replaceRange(m.start, m.end, ' ');
    } else {
      final s = _shortDate.firstMatch(w);
      if (s != null) {
        day = _dayOf(int.parse(s[1]!), int.parse(s[2]!), null, today);
        w = w.replaceRange(s.start, s.end, ' ');
      }
    }
  }
  if (day != null) explicit = true;

  String? currency;
  for (final e in _currencies.entries) {
    if (e.value.hasMatch(w)) {
      currency ??= e.key;
      w = w.replaceAll(e.value, ' ');
    }
  }
  if (currency != null) explicit = true;

  final account = _findAccount(w, accountNames);
  if (account != null) {
    explicit = true;
    w = w.replaceRange(account.start, account.end, ' ');
  }

  final items = <TypedItem>[];
  final unparsed = <String>[];
  for (final part in w.split(RegExp(r';|\n|,(?!\d)'))) {
    final s = part
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[\s.:\-–—]+|[\s.:\-–—]+$'), '')
        .trim();
    if (s.isEmpty) continue;
    final item = _item(s);
    if (item == null) {
      unparsed.add(s);
    } else {
      items.add(item);
    }
  }
  if (items.isEmpty && income && unparsed.length == 1) {
    // "отримав 5000": nothing is named, the amount is the income.
    final m = RegExp('^$_n\$').firstMatch(unparsed.first);
    if (m != null && _d(m[1]!) > 0) {
      items.add(TypedItem(raw: unparsed.first, name: 'Дохід', amount: _r2(_d(m[1]!))));
      unparsed.clear();
    }
  }
  if (items.isEmpty) return null;
  if (verb != null) {
    // "купив каву": the object is in the accusative; categories are named in the
    // nominative ("кава"), and "каву" would otherwise be read as "кавун".
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      items[i] = TypedItem(
        raw: it.raw,
        name: _nominative(it.name),
        amount: it.amount,
        quantity: it.quantity,
        unit: it.unit,
        unitPrice: it.unitPrice,
      );
    }
  }
  if (items.length > 1) explicit = true;
  return TypedExpense(
    items: items,
    cash: cash,
    currency: currency,
    day: day,
    income: income,
    accountIndex: account?.index,
    explicit: explicit,
    unparsed: unparsed,
  );
}

/// Feminine accusative -> nominative per word ("каву" -> "кава", "цибулю" ->
/// "цибуля"). Short words are left alone.
String _nominative(String name) => name
    .split(' ')
    .map(
      (w) => w.length >= 4 && (w.endsWith('у') || w.endsWith('ю'))
          ? '${w.substring(0, w.length - 1)}${w.endsWith('у') ? 'а' : 'я'}'
          : w,
    )
    .join(' ');

/// A day that is not in the future (a date a year ahead is read as last year's).
DateTime? _dayOf(int d, int m, int? y, DateTime today) {
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  final year = y == null ? today.year : (y < 100 ? 2000 + y : y);
  var v = DateTime(year, m, d);
  if (v.month != m) return null;
  if (y == null && v.isAfter(today)) v = DateTime(year - 1, m, d);
  return v;
}

({int index, int start, int end})? _findAccount(String w, List<String> names) {
  final order = [for (var i = 0; i < names.length; i++) i]
    ..sort((a, b) => names[b].length.compareTo(names[a].length));
  ({int index, int start, int end})? hit;
  for (final i in order) {
    final n = names[i].trim();
    if (n.isEmpty) continue;
    final m = RegExp(
      '(?<![\\p{L}\\d])${RegExp.escape(n)}(?![\\p{L}\\d])',
      unicode: true,
    ).firstMatch(w);
    if (m != null) {
      hit = (index: i, start: m.start, end: m.end);
      break;
    }
  }
  if (hit == null) {
    // A word only one account has ("фоп").
    final owners = <String, Set<int>>{};
    for (var i = 0; i < names.length; i++) {
      for (final t in names[i].split(RegExp(r'[^\p{L}\d]+', unicode: true))) {
        if (t.length >= 3) owners.putIfAbsent(t, () => {}).add(i);
      }
    }
    for (final e in owners.entries) {
      if (e.value.length != 1) continue;
      final m = _word(RegExp.escape(e.key)).firstMatch(w);
      if (m != null) {
        hit = (index: e.value.first, start: m.start, end: m.end);
        break;
      }
    }
  }
  if (hit == null) return null;
  // "з Monobank": the preposition goes with the name.
  final before = _preposition.firstMatch(w.substring(0, hit.start));
  return (index: hit.index, start: before?.start ?? hit.start, end: hit.end);
}

TypedItem? _item(String s) {
  String name(String n) {
    final t = n.trim();
    return t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);
  }

  TypedItem? make(String n, double total, {double? qty, String? unit, double? price}) {
    if (total <= 0 || total >= 10000000 || n.trim().isEmpty) return null;
    final u = unit ?? '';
    final kg = u == 'кг' || u == 'kg';
    final gram = u == 'г' || u == 'гр' || u == 'g';
    final pieces = u == 'шт' || u == 'штук' || u == 'штуки' || u == 'pcs';
    final volume = u == 'л' || u == 'l' || u == 'мл' || u == 'ml';
    if (qty != null && qty > 0 && (kg || gram || pieces)) {
      final q = gram ? qty / 1000 : qty;
      return TypedItem(
        raw: s,
        name: name(n),
        amount: _r2(total),
        quantity: q,
        unit: pieces ? UnitKind.pieces : UnitKind.kilograms,
        unitPrice: price ?? total / q,
      );
    }
    // A volume stays in the name, where the pack size is read from.
    final label = volume && qty != null ? '$n ${_g(qty)} $u' : n;
    return TypedItem(raw: s, name: name(label), amount: _r2(total));
  }

  var m = _qtyTimes.firstMatch(s);
  if (m != null) {
    final q = _d(m[2]!);
    final p = _d(m[4]!);
    return make(m[1]!, q * p, qty: q, unit: m[3], price: p);
  }
  m = _qtyPer.firstMatch(s);
  if (m != null) {
    final q = _d(m[2]!);
    final p = _d(m[4]!);
    return make(m[1]!, q * p, qty: q, unit: m[3], price: p);
  }
  m = _qtyTotal.firstMatch(s);
  if (m != null) return make(m[1]!, _d(m[4]!), qty: _d(m[2]!), unit: m[3]);
  m = _plain.firstMatch(s);
  if (m != null) return make(m[1]!, _d(m[2]!));
  m = _lead.firstMatch(s);
  if (m != null) return make(m[2]!, _d(m[1]!));
  return null;
}

String _g(double v) => v == v.roundToDouble() ? v.round().toString() : v.toString();
