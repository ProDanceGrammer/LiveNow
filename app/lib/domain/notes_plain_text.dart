import 'dart:convert';

/// Lower-cased plain text of a stored `actions.notes` value (the editor's
/// Document JSON: `{"document": {"type": "page", "children": [...]}}`), or
/// null when there is no text. Blocks are separated by a newline. Pure Dart
/// on the raw JSON (no editor package), so the v9 backfill stays cheap and
/// this never throws: corrupt input yields null.
String? notesPlainText(String? json) {
  if (json == null || json.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(json);
    if (decoded is! Map) return null;
    final root = decoded['document'];
    if (root is! Map) return null;
    final lines = <String>[];
    void walk(Object? node) {
      if (node is! Map) return;
      final data = node['data'];
      if (data is Map) {
        final delta = data['delta'];
        if (delta is List) {
          final b = StringBuffer();
          for (final op in delta) {
            if (op is Map && op['insert'] is String) {
              b.write(op['insert'] as String);
            }
          }
          if (b.isNotEmpty) lines.add(b.toString());
        }
      }
      final children = node['children'];
      if (children is List) children.forEach(walk);
    }

    walk(root);
    final text = lines.join('\n').toLowerCase();
    return text.trim().isEmpty ? null : text;
  } catch (_) {
    return null;
  }
}
