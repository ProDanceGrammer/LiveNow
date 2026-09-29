final _prefix = RegExp(r'^\[#(\d+)\]\s*');

/// Splits a `[#n] Base name` title into its sequence number (null when there
/// is no prefix) and the base name.
(int?, String) parseSequencePrefix(String name) {
  final match = _prefix.firstMatch(name);
  if (match == null) return (null, name);
  return (int.parse(match.group(1)!), name.substring(match.end));
}

String formatSequenceName(int number, String baseName) =>
    '[#$number] $baseName';

/// The key two actions are compared by to count as "the same action": the
/// `[#n]` prefix and every digit run are stripped (the Notion prototype's
/// `replaceAll("\d+")`), then the rest is trimmed and lowercased.
String normalizeForMatch(String name) {
  final (_, base) = parseSequencePrefix(name);
  return base.replaceAll(RegExp(r'\d+'), '').trim().toLowerCase();
}
