import 'growth_import.dart' show parseCsv;

/// One row of a category-icons file: the category name and the emoji for it.
class CategoryIcon {
  const CategoryIcon(this.name, this.icon);
  final String name;
  final String icon;
}

/// Reads a category-icons CSV: a header with a `name` and an `icon` column (any
/// other column, such as `row_in_screenshot`, is ignored), then one row per
/// category. Rows without a name or an icon are skipped; if a name appears
/// twice the last row wins.
List<CategoryIcon> parseCategoryIcons(String text) {
  final rows = parseCsv(text.replaceFirst('﻿', ''));
  if (rows.isEmpty) return const [];
  final header = [for (final h in rows.first) h.trim().toLowerCase()];
  final nameAt = header.indexOf('name');
  final iconAt = header.indexOf('icon');
  if (nameAt < 0 || iconAt < 0) return const [];
  final byName = <String, CategoryIcon>{};
  for (final r in rows.skip(1)) {
    if (r.length <= nameAt || r.length <= iconAt) continue;
    final name = r[nameAt].trim();
    final icon = r[iconAt].trim();
    if (name.isEmpty || icon.isEmpty) continue;
    byName[categoryNameKey(name)] = CategoryIcon(name, icon);
  }
  return byName.values.toList();
}

/// Whether [text] looks like a category-icons file (for a helpful message).
bool looksLikeCategoryIcons(String text) {
  final rows = parseCsv(text.replaceFirst('﻿', ''));
  if (rows.isEmpty) return false;
  final header = [for (final h in rows.first) h.trim().toLowerCase()];
  return header.contains('name') && header.contains('icon');
}

/// Names are matched ignoring case, surrounding and doubled spaces and the
/// curly apostrophe (`’` is `'`).
String categoryNameKey(String name) => name
    .replaceAll('’', "'")
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim()
    .toLowerCase();

final _leadingSymbols = RegExp(r'^([^\p{L}\p{N}\s]+)\s+', unicode: true);

/// [name] without a leading emoji (and the space after it): `"👟 Взуття"` ->
/// `"Взуття"`. Only a leading run of real symbols counts (code point from
/// U+2190 up: arrows, symbols, emoji); ASCII punctuation such as `#` or `(`
/// belongs to the name and stays.
String stripLeadingIcon(String name) {
  final m = _leadingSymbols.firstMatch(name);
  if (m == null || !m.group(1)!.runes.any((r) => r >= 0x2190)) return name;
  return name.substring(m.end);
}

/// What applying an icons file did.
class CategoryIconResult {
  const CategoryIconResult({
    required this.updated,
    required this.unchanged,
    required this.notFound,
  });

  /// Categories whose name changed.
  final int updated;

  /// Categories that already had exactly this icon.
  final int unchanged;

  /// Names in the file that no category has.
  final List<String> notFound;
}
