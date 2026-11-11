import 'ai_transfer_text.dart' show parseAmountText;
import 'extracted_receipt.dart' show Tender;

// Sum verifier (spec I2) and tender splitter (A6). Pure. A mismatch is
// REPORTED, never silently fixed.

class SumCheck {
  const SumCheck(this.linesSum, this.expected, this.difference, this.ok);
  final double linesSum;
  final double expected;

  /// linesSum - expected (positive: the lines add up to more).
  final double difference;
  final bool ok;
}

int _cents(double v) => (v * 100).round();

/// I2: the sum of [nets] must equal [expected] (the receipt total, or the
/// user's own tender amount after the other tenders were taken out) within
/// [tolerance].
SumCheck verifySum(
  Iterable<double> nets,
  double expected, {
  double tolerance = 0.02,
}) {
  final sum = nets.fold<int>(0, (a, v) => a + _cents(v));
  final diff = sum - _cents(expected);
  return SumCheck(
    sum / 100,
    expected,
    diff / 100,
    diff.abs() <= _cents(tolerance),
  );
}

enum SplitStatus {
  /// One tender (or the user's amount covers every line): all lines are theirs.
  allMine,

  /// A unique subset of lines adds up to the user's tender.
  split,

  /// More than one subset adds up to it: ask the user.
  ambiguous,

  /// No subset adds up to it: the lines or the tender were misread.
  noMatch,

  /// The user's own tender could not be identified: ask the user.
  unknownTender,
}

class TenderSplit {
  const TenderSplit(this.status, this.mine, this.others, {this.myAmount});
  final SplitStatus status;

  /// Indices (into the line list) of the user's lines, ascending.
  final List<int> mine;
  final List<int> others;
  final double? myAmount;

  bool get needsQuestion =>
      status == SplitStatus.ambiguous ||
      status == SplitStatus.noMatch ||
      status == SplitStatus.unknownTender;
}

/// The user's own tender: by card last-4, else by the amount from a bank
/// screenshot, else the only tender. Null when it cannot be told.
Tender? pickMyTender(
  List<Tender> tenders, {
  Set<String> myLast4 = const {},
  double? amountHint,
}) {
  if (tenders.length == 1) return tenders.first;
  for (final t in tenders) {
    if (t.last4 != null && myLast4.contains(t.last4)) return t;
  }
  if (amountHint != null) {
    for (final t in tenders) {
      if (t.amount != null && _cents(t.amount!) == _cents(amountHint)) return t;
    }
  }
  return null;
}

/// The tender an answer to "which payment is yours" names (an index into
/// [tenders]): one whose amount equals a number in it (to the cent), else one
/// whose card last-4 is a 4-digit group in it. Null when none matches. An
/// amount comes first: "•••• ? — 2048.41" has no card digits, and its "2048"
/// is not a card.
int? tenderFromAnswer(List<Tender> tenders, String answer) {
  final cents = {
    for (final m in RegExp(r'\d[\d\s.,]*\d|\d').allMatches(answer))
      if (parseAmountText(m.group(0)!) case final v?) _cents(v),
  };
  for (var i = 0; i < tenders.length; i++) {
    final a = tenders[i].amount;
    if (a != null && cents.contains(_cents(a))) return i;
  }
  final groups = {
    for (final m in RegExp(r'(?<!\d)\d{4}(?!\d)').allMatches(answer)) m.group(0)!,
  };
  for (var i = 0; i < tenders.length; i++) {
    final l4 = tenders[i].last4;
    if (l4 != null && groups.contains(l4)) return i;
  }
  return null;
}

/// A6: finds which lines belong to the user's tender by subset-sum over the
/// line nets (in cents). [lineNets] are the lines of the whole receipt.
/// [mineIndex] is the tender the user picked (it wins over every other hint);
/// a picked tender without a readable amount takes every line, so the
/// question is never asked again.
TenderSplit splitTenders({
  required List<double> lineNets,
  required List<Tender> tenders,
  Set<String> myLast4 = const {},
  double? amountHint,
  int? mineIndex,
}) {
  final all = List<int>.generate(lineNets.length, (i) => i);
  final picked = mineIndex != null && mineIndex >= 0 && mineIndex < tenders.length
      ? tenders[mineIndex]
      : null;
  final mine = picked ?? pickMyTender(tenders, myLast4: myLast4, amountHint: amountHint);
  if (tenders.length <= 1 || (picked != null && picked.amount == null)) {
    return TenderSplit(SplitStatus.allMine, all, const [], myAmount: mine?.amount);
  }
  final amount = mine?.amount;
  if (mine == null || amount == null) {
    return const TenderSplit(SplitStatus.unknownTender, [], []);
  }
  final target = _cents(amount);
  final cents = [for (final v in lineNets) _cents(v)];
  if (cents.fold<int>(0, (a, v) => a + v) == target) {
    return TenderSplit(SplitStatus.allMine, all, const [], myAmount: amount);
  }
  // Zero lines cannot change a sum: they stay with the user, out of the search.
  final nonZero = [for (final i in all) if (cents[i] > 0) i]
    ..sort((a, b) => cents[b].compareTo(cents[a]));
  final solutions = _subsetSums([for (final i in nonZero) cents[i]], target);
  if (solutions.isEmpty) {
    return TenderSplit(SplitStatus.noMatch, const [], all, myAmount: amount);
  }
  final pick = {for (final k in solutions.first) nonZero[k]};
  final mineIdx = [
    for (final i in all)
      if (pick.contains(i) || cents[i] == 0) i,
  ];
  final status = solutions.length > 1 ? SplitStatus.ambiguous : SplitStatus.split;
  return TenderSplit(
    status,
    mineIdx,
    [for (final i in all) if (!mineIdx.contains(i)) i],
    myAmount: amount,
  );
}

/// Up to two index subsets of [cents] (descending, all > 0) summing to [target].
List<List<int>> _subsetSums(List<int> cents, int target) {
  final suffix = List<int>.filled(cents.length + 1, 0);
  for (var i = cents.length - 1; i >= 0; i--) {
    suffix[i] = suffix[i + 1] + cents[i];
  }
  final found = <List<int>>[];
  final cur = <int>[];
  var nodes = 0;
  void go(int i, int sum) {
    if (found.length >= 2 || ++nodes > 500000) return;
    if (sum == target) {
      found.add(List.of(cur));
      return;
    }
    if (sum > target || i >= cents.length || sum + suffix[i] < target) return;
    cur.add(i);
    go(i + 1, sum + cents[i]);
    cur.removeLast();
    go(i + 1, sum);
  }

  go(0, 0);
  return found;
}
