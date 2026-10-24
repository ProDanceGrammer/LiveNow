// One matching rule for every search in the app: results where the typed text
// is a WHOLE WORD come first ("IT infrastructure", "do it"), then the other
// substring matches ("commit files", "iterations construction"). Everything is
// done in Dart (not SQL) so Cyrillic is case-insensitive too.

/// Lower-cases, turns the typographic apostrophe into a plain one, trims and
/// collapses runs of spaces, so `Don’t  Stop ` and `don't stop` compare equal.
String foldSearch(String s) => s
    .replaceAll('’', "'")
    // Zero-width characters are invisible: they must not hide a match.
    .replaceAll(_invisible, '')
    // Turkish: dotted capital İ lower-cases to "i" + a combining dot in Dart,
    // and dotless ı is a letter of its own; both fold to a plain i so that
    // "istanbul" finds "İstanbul" and "isi" finds "ısı".
    .replaceAll('İ', 'i')
    .replaceAll('ı', 'i')
    .toLowerCase()
    .replaceAll(_combiningDot, '')
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ');

final _combiningDot = String.fromCharCode(0x307);
final _invisible = RegExp('[\u200b-\u200d\u2060\ufeff]');

/// How well [text] matches [query]: 0 = the query stands there as a whole word
/// or phrase (the characters around it are not letters or digits), 1 = it is
/// contained somewhere inside a word, null = no match. An empty query matches
/// everything as tier 1.
int? matchTier(String text, String query) {
  final q = foldSearch(query);
  if (q.isEmpty) return 1;
  final t = foldSearch(text);
  if (!t.contains(q)) return null;
  final whole = RegExp(
    '(?<![\\p{L}\\p{N}])${RegExp.escape(q)}(?![\\p{L}\\p{N}])',
    unicode: true,
  );
  return whole.hasMatch(t) ? 0 : 1;
}

/// Keeps the items that match [query] in at least one of their [texts] and puts
/// the whole-word matches first. [texts] lists an item's searchable strings, the
/// PRIMARY one (its name) first: inside one tier an item found by its name comes
/// before one found only by a secondary text. Otherwise the order is the one the
/// items came in (stable), so a list keeps its own sort inside each tier. An empty
/// query returns the items unchanged.
List<T> rankMatches<T>(
  Iterable<T> items,
  String query,
  List<String> Function(T item) texts,
) => _rank(items, query, texts, keepUnmatched: false);

/// Like [rankMatches] but DROPS nothing: an item none of whose [texts] matches
/// (it was found some other way, e.g. in its notes) goes after the matching ones.
/// For lists whose own filter already decided what is shown.
List<T> orderByMatch<T>(
  Iterable<T> items,
  String query,
  List<String> Function(T item) texts,
) => _rank(items, query, texts, keepUnmatched: true);

List<T> _rank<T>(
  Iterable<T> items,
  String query,
  List<String> Function(T item) texts, {
  required bool keepUnmatched,
}) {
  if (foldSearch(query).isEmpty) return items.toList();
  final ranked = <({T item, int tier, int field, int order})>[];
  var order = 0;
  for (final item in items) {
    int? bestTier;
    var bestField = 0;
    final fields = texts(item);
    for (var i = 0; i < fields.length; i++) {
      final tier = matchTier(fields[i], query);
      if (tier == null) continue;
      if (bestTier == null || tier < bestTier) {
        bestTier = tier;
        bestField = i;
      }
    }
    if (bestTier != null) {
      ranked.add((item: item, tier: bestTier, field: bestField, order: order));
    } else if (keepUnmatched) {
      ranked.add((item: item, tier: 2, field: 0, order: order));
    }
    order++;
  }
  ranked.sort((a, b) {
    final byTier = a.tier.compareTo(b.tier);
    if (byTier != 0) return byTier;
    // Found by the primary text before found only by a secondary one.
    final byField = (a.field == 0 ? 0 : 1).compareTo(b.field == 0 ? 0 : 1);
    return byField != 0 ? byField : a.order.compareTo(b.order);
  });
  return [for (final r in ranked) r.item];
}
