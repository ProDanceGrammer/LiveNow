/// Sort key for a name that may start with emoji / decoration: the LEADING run
/// of runes that are neither a letter nor a digit (emoji, ZWJ U+200D, VS16
/// U+FE0F, skin tones U+1F3FB-1F3FF, arrows, quotes, spaces, punctuation) is
/// dropped and the rest lower-cased. Ties are broken by the caller on the full
/// name.
///
/// Limit: Dart compares strings by UTF-16 code unit, so Ukrainian letters that
/// sit outside the main Cyrillic run (і U+0456, ї U+0457, є U+0454, ґ U+0491)
/// sort after 'я', not in dictionary order.
String sortKeyIgnoringEmoji(String name) {
  final runes = name.runes.toList();
  var i = 0;
  while (i < runes.length && !_isLetterOrDigit(runes[i])) {
    i++;
  }
  return String.fromCharCodes(runes.sublist(i)).toLowerCase();
}

/// Compares two names by [sortKeyIgnoringEmoji], then by the full name.
int compareIgnoringEmoji(String a, String b) {
  final c = sortKeyIgnoringEmoji(a).compareTo(sortKeyIgnoringEmoji(b));
  return c != 0 ? c : a.compareTo(b);
}

final _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);

bool _isLetterOrDigit(int rune) {
  // Emoji modifiers/joiners are never letters, but a few emoji-adjacent
  // symbols (keycap digits) are digits: those are real digits, keep them.
  return _letterOrDigit.hasMatch(String.fromCharCode(rune));
}
