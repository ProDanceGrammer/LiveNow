import 'dart:convert';

/// The growth direction ids a template's payload links to (empty when the
/// payload is not valid JSON or has none).
List<String> templateMetricIds(String payloadJson) {
  try {
    final data = jsonDecode(payloadJson);
    if (data is Map && data['metricIds'] is List) {
      return [
        for (final id in data['metricIds'] as List)
          if (id is String) id,
      ];
    }
  } catch (_) {
    // A broken payload simply has no directions.
  }
  return const [];
}

/// Does a template match the search [query] (already lower-cased and trimmed)?
/// It does when its own name contains it, or the name of any growth direction
/// it links to does. [directionNames] maps a direction id to its LOWER-CASED
/// name (ids of deleted directions are simply missing). Case-insensitive in
/// Dart, so Cyrillic works. An empty query matches everything.
bool templateMatches({
  required String name,
  required String payloadJson,
  required String query,
  required Map<String, String> directionNames,
}) {
  if (query.isEmpty) return true;
  if (name.toLowerCase().contains(query)) return true;
  for (final id in templateMetricIds(payloadJson)) {
    if (directionNames[id]?.contains(query) ?? false) return true;
  }
  return false;
}
