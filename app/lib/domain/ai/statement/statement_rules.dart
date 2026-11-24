import '../../search_match.dart' show foldSearch;
import '../ai_transfer_text.dart' show matchAccountName, resolveAccount;
import 'mcc_hints.dart';
import 'statement_rows.dart';

enum StatementKind {
  purchase,
  income,
  transferOut,
  transferIn,
  cashbackIncome,
  fee,

  /// One half of a reversal pair: nothing is written.
  cancelled,

  /// A person (or a card/jar not recognised as the user's own): needs a decision
  /// unless [StatementItem.remembered] answers it.
  person,
  unknown,
}

class StatementAccountRef {
  const StatementAccountRef({required this.id, required this.name, required this.currency});
  final String id;
  final String name;
  final String currency;
}

/// A row after the rules. [amount] is positive and in [currency]: the card
/// amount, or, for a card payment in a foreign currency, the operation amount
/// with the rate pair ([rateCount] units cost [rateInteract] card units).
class StatementItem {
  const StatementItem({
    required this.row,
    required this.kind,
    required this.amount,
    required this.currency,
    this.merchant,
    this.hint,
    this.counterAccountId,
    this.partyKey,
    this.partyName,
    this.jarName,
    this.remembered,
    this.rateCount,
    this.rateInteract,
    this.pairIndex,
    this.reason,
  });

  final StatementRow row;
  final StatementKind kind;
  final double amount;
  final String currency;

  /// Text to name the transaction after.
  final String? merchant;

  /// Category words: the bank's category, else the MCC hint.
  final String? hint;

  /// The user's other account of a transfer; null = "my own account, which one?".
  final String? counterAccountId;
  final String? partyKey;
  final String? partyName;
  final String? jarName;

  /// What the caller's memory holds under [partyKey] (opaque here).
  final String? remembered;
  final double? rateCount;
  final double? rateInteract;

  /// For [StatementKind.cancelled]: the row index of the other half.
  final int? pairIndex;
  final String? reason;

  bool get isOut => row.cardAmount < 0;
}

/// Classifies every row by rules only. Items come in row order, a fee item right
/// after its row. [partyMemory] maps a party key to the remembered answer;
/// [cardAccount] maps the last 4 digits of a masked card to an own account id.
List<StatementItem> classifyStatement(
  List<StatementRow> rows, {
  required String statementAccountId,
  required List<StatementAccountRef> accounts,
  Map<String, String> partyMemory = const {},
  String? Function(String last4)? cardAccount,
}) {
  final pairs = _reversalPairs(rows);
  final others = [for (final a in accounts) if (a.id != statementAccountId) a];
  final out = <StatementItem>[];
  for (final row in rows) {
    final pair = pairs[row.index];
    if (pair != null) {
      out.add(StatementItem(
        row: row,
        kind: StatementKind.cancelled,
        amount: row.cardAmount.abs(),
        currency: row.cardCurrency,
        pairIndex: pair,
        merchant: row.details,
      ));
      continue;
    }
    out.add(_classify(row, others, partyMemory, cardAccount));
    final fee = row.fee;
    if (fee != null && fee > 0) {
      out.add(StatementItem(
        row: row,
        kind: StatementKind.fee,
        amount: fee,
        currency: row.cardCurrency,
        merchant: row.details,
      ));
    }
  }
  return out;
}

// ---- reversal pairs -------------------------------------------------------------

final _cancelPrefix = RegExp(
  r'^(?:скасування|скасовано|cancel(?:led|lation)?|reversal|refund of|отмена|возврат|iptal)(?!\p{L})[\s.:\-]*',
  caseSensitive: false,
  unicode: true,
);
final _mask = RegExp(r'\d{4,6}\*{2,}(\d{4})');

/// Row index -> index of its partner, for both halves of every reversal.
Map<int, int> _reversalPairs(List<StatementRow> rows) {
  final result = <int, int>{};
  for (final r in rows) {
    final m = _cancelPrefix.firstMatch(foldSearch(r.details));
    if (m == null || result.containsKey(r.index)) continue;
    final rest = foldSearch(r.details).substring(m.end);
    final mask = _mask.firstMatch(r.details)?.group(1);
    StatementRow? best;
    Duration? bestGap;
    for (final o in rows) {
      if (o.index == r.index || result.containsKey(o.index)) continue;
      if ((o.cardAmount < 0) == (r.cardAmount < 0)) continue;
      if ((o.cardAmount.abs() - r.cardAmount.abs()).abs() > 0.005) continue;
      final gap = o.at.difference(r.at).abs();
      if (gap > const Duration(minutes: 10)) continue;
      final oMask = _mask.firstMatch(o.details)?.group(1);
      final same = rest.isEmpty ||
          foldSearch(o.details) == rest ||
          (mask != null && mask == oMask);
      if (!same) continue;
      if (bestGap == null || gap < bestGap) {
        best = o;
        bestGap = gap;
      }
    }
    if (best != null) {
      result[r.index] = best.index;
      result[best.index] = r.index;
    }
  }
  return result;
}

// ---- one row --------------------------------------------------------------------

final _cashbackPayout = RegExp(r'виведення кешбек|вивід кешбек|cashback payout|cashback withdrawal');
final _ownPhrase = RegExp(r'між власними|власний рахунок|власні рахунки|own account|between my');
final _transferLead = RegExp(
  r'^\s*(?:з|із|на|від|to|from|переказ(?: з| на)?)\s+',
  caseSensitive: false,
  unicode: true,
);
final _jar = RegExp(r'[«"“]([^»"”]+)[»"”]');
final _jarLead = RegExp(r'^(?:поповнення|переказ на|переказ з|з банки|на банку|банка|jar)');
final _partyLead = RegExp(r'^(?:від кого|від|кому|для|from|to|sender|recipient)\s*:\s*(.+)$', caseSensitive: false, unicode: true);
final _nameInitial = RegExp(
  r"^\p{Lu}[\p{L}'’\-]+(?:\s+\p{Lu}[\p{L}'’\-]+)?\s+\p{Lu}\.$",
  unicode: true,
);
final _shopWord = RegExp(
  r'(?<!\p{L})(?:тов|фоп|llc|ltd|inc|bank|банк|казино|casino|shop|market|магазин|аптека|pay|\.com|корп|ресторан|кафе|азс|taxi|таксі)',
  unicode: true,
);

StatementItem _classify(
  StatementRow row,
  List<StatementAccountRef> others,
  Map<String, String> memory,
  String? Function(String last4)? cardAccount,
) {
  final out = row.cardAmount < 0;
  final folded = foldSearch(row.details);
  final amount = row.cardAmount.abs();
  final cur = row.cardCurrency;

  StatementItem make(
    StatementKind kind, {
    String? counter,
    String? party,
    String? partyName,
    String? jar,
    String? hint,
    bool foreign = false,
  }) {
    final useOp = foreign && row.isForeign;
    return StatementItem(
      row: row,
      kind: kind,
      amount: useOp ? row.opAmount!.abs() : amount,
      currency: useOp ? row.opCurrency! : cur,
      merchant: row.details,
      hint: hint,
      counterAccountId: counter,
      partyKey: party,
      partyName: partyName,
      jarName: jar,
      remembered: party == null ? null : memory[party],
      rateCount: useOp ? row.opAmount!.abs() : null,
      rateInteract: useOp ? amount : null,
    );
  }

  StatementItem transfer(String? counter) =>
      make(out ? StatementKind.transferOut : StatementKind.transferIn, counter: counter);

  if (row.cardAmount == 0) return make(StatementKind.unknown);

  // 1. Cashback paid out to the card.
  if (!out && _cashbackPayout.hasMatch(folded)) return make(StatementKind.cashbackIncome);

  // 2. A jar: Поповнення «name».
  final jar = _jar.firstMatch(row.details);
  if (jar != null && _jarLead.hasMatch(folded)) {
    final name = jar.group(1)!.trim();
    final hit = _account(name, others, row.cardCurrency, strict: true);
    if (hit != null) return transfer(hit.id);
    return make(StatementKind.person, party: partyKeyOf(name), partyName: name, jar: name);
  }

  // 3. A masked card number: an own card, else somebody's.
  final mask = _mask.firstMatch(row.details);
  if (mask != null) {
    final last4 = mask.group(1)!;
    final id = cardAccount?.call(last4);
    if (id != null) return transfer(id);
    return make(StatementKind.person, party: 'card $last4', partyName: 'картка *$last4');
  }

  // 4. "З гривневого рахунку ФОП", "На рахунок Ліра": an own account by name.
  final lead = _transferLead.firstMatch(row.details);
  if (lead != null) {
    final rest = row.details.substring(lead.end);
    final hit = _account(rest, others, row.cardCurrency);
    if (hit != null) return transfer(hit.id);
  }
  if (_ownPhrase.hasMatch(folded)) return transfer(null);

  // 5. A person.
  final party = _partyLead.firstMatch(row.details.trim());
  String? name;
  if (party != null) {
    name = party.group(1)!.trim();
  } else if (_nameInitial.hasMatch(row.details.trim())) {
    name = row.details.trim();
  } else if ((row.mcc == 4829 || row.mcc == 6012) &&
      !_shopWord.hasMatch(folded) &&
      !RegExp(r'\d').hasMatch(folded) &&
      folded.split(' ').length <= 4) {
    name = row.details.trim();
  }
  if (name != null && name.isNotEmpty) {
    return make(StatementKind.person, party: partyKeyOf(name), partyName: name);
  }

  // 6. Purchase or income.
  final cat = row.bankCategory;
  final hint = (cat != null && cat.isNotEmpty) ? cat : (row.mcc == null ? null : mccHint(row.mcc!));
  return out
      ? make(StatementKind.purchase, hint: hint, foreign: true)
      : make(StatementKind.income, hint: cat, foreign: true);
}

StatementAccountRef? _account(String typed, List<StatementAccountRef> accounts, String currency, {bool strict = false}) {
  final exact = matchAccountName<StatementAccountRef>(typed, accounts, (a) => a.name);
  if (exact.length == 1) return exact.first;
  if (strict) return null;
  final fuzzy = resolveAccount<StatementAccountRef>(
    typed,
    accounts,
    nameOf: (a) => a.name,
    currencyOf: (a) => a.currency,
    currencyHint: currency,
  );
  return fuzzy.length == 1 ? fuzzy.first : null;
}

/// "Владислав Я.", "Від: Владислав Ярмоленко" -> "владислав я": first name and
/// the first letter of the last word, folded.
String partyKeyOf(String name) {
  final words = foldSearch(name)
      .replaceAll(RegExp(r"[^\p{L}\p{N}' ]", unicode: true), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '';
  if (words.length == 1) return words.first;
  return '${words.first} ${words.last[0]}';
}
