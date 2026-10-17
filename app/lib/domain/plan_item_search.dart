/// Search in the Plan items list. Matching is done in Dart, not SQL: SQLite's
/// lower() only handles ASCII, so Cyrillic names would not match.
///
/// Every word of [query] must appear (anywhere, any case) in the plan item's
/// [name], its [description] ("Every day 22:00 · 60 min") or one of its
/// [collectionNames]. An empty query matches everything.
bool planItemMatchesSearch(
  String query, {
  required String name,
  String description = '',
  Iterable<String> collectionNames = const [],
}) {
  final words = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty);
  if (words.isEmpty) return true;
  final haystack = [name, description, ...collectionNames].join('\n').toLowerCase();
  return words.every(haystack.contains);
}
