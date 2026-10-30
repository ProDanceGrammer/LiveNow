// At most 9 digits: a longer "number" is not a counter anyone made, and
// `int.parse` would throw on it (and Continue with it). Such a title simply has
// no prefix.
final _prefix = RegExp(r'^\[#(\d{1,9})\]\s*');

/// Splits a `[#n] Base name` title into its sequence number (null when there
/// is no prefix) and the base name.
(int?, String) parseSequencePrefix(String name) {
  final match = _prefix.firstMatch(name);
  if (match == null) return (null, name);
  return (int.parse(match.group(1)!), name.substring(match.end));
}

/// `[n] Base name`; a base name that is empty gives just `[#n]` (no dangling
/// space).
String formatSequenceName(int number, String baseName) =>
    '[#$number] $baseName'.trimRight();

/// The key two actions are compared by to count as "the same action": the
/// `[#n]` prefix and every digit run are stripped (the Notion prototype's
/// `replaceAll("\d+")`), then the rest is trimmed and lowercased.
String normalizeForMatch(String name) {
  final (_, base) = parseSequencePrefix(name);
  return base.replaceAll(_digits, '').trim().toLowerCase();
}

// Hoisted: this runs once per finished action when averages are computed.
final _digits = RegExp(r'\d+');
