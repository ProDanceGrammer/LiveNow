import 'growth_import.dart';

// Reads the direction icons out of a Notion database page saved from the
// browser ("Save page as… → Webpage, complete"). Each table row is a
// `notion-collection-item` block; its first cell holds the row's icon and
// title. Emoji icons are `<img class="notion-emoji" alt="🚓">`; Notion's
// built-in icons are `<img alt="" src=".../calculator_green_7kh-.svg">`,
// which have no emoji, so they map to one of the same meaning.
// A saved page only contains the rows Notion had rendered (it virtualises
// long tables), so it may cover just some of the directions.

/// Same-sense emoji for Notion's built-in icon names (the part of the file
/// name before the colour). Unknown names are skipped.
const notionBuiltinIconEmoji = <String, String>{
  'calculator': '🧮',
  'redirect': '↪️',
  'following': '👥',
  'arrows-horizontal': '↔️',
  'arrows-vertical': '↕️',
  'checkmark': '✔️',
  'check': '✔️',
  'target': '🎯',
  'star': '⭐',
  'heart': '❤️',
  'home': '🏠',
  'house': '🏠',
  'settings': '⚙️',
  'gear': '⚙️',
  'book': '📖',
  'bookmark': '🔖',
  'calendar': '📅',
  'clock': '🕒',
  'time': '🕒',
  'flag': '🚩',
  'lightbulb': '💡',
  'bulb': '💡',
  'lock': '🔒',
  'key': '🔑',
  'mail': '✉️',
  'email': '✉️',
  'chat': '💬',
  'comment': '💬',
  'trophy': '🏆',
  'rocket': '🚀',
  'fire': '🔥',
  'money': '💵',
  'dollar': '💲',
  'chart': '📊',
  'graph': '📈',
  'search': '🔍',
  'link': '🔗',
  'pin': '📌',
  'bell': '🔔',
  'camera': '📷',
  'music': '🎵',
  'globe': '🌐',
  'user': '👤',
  'person': '👤',
  'people': '👥',
  'group': '👥',
};

final _rowStart = RegExp(
  r'class="notion-selectable notion-page-block notion-collection-item"',
);
final _emojiImg = RegExp(
  r'<img\b[^>]*\bclass="notion-emoji"[^>]*\balt="([^"]*)"|'
  r'<img\b[^>]*\balt="([^"]*)"[^>]*\bclass="notion-emoji"',
);
final _builtinImg = RegExp(
  r'<img\b[^>]*\bsrc="[^"]*?/([a-z0-9-]+?)_[a-z]+_[A-Za-z0-9-]+\.svg"',
);
final _svg = RegExp(r'<svg.*?</svg>', dotAll: true);
final _tags = RegExp(r'<[^>]*>');

/// Direction name → icon emoji for every row of [html] whose first cell has
/// a usable icon. Names are normalized (see [normalizeDirectionName]).
/// [skippedBuiltin] receives the names of rows whose built-in icon has no
/// same-sense emoji in [notionBuiltinIconEmoji].
Map<String, String> parseNotionIcons(
  String html, {
  List<String>? skippedBuiltin,
}) {
  final starts = [for (final m in _rowStart.allMatches(html)) m.start];
  final result = <String, String>{};
  for (var i = 0; i < starts.length; i++) {
    final rowEnd = i + 1 < starts.length ? starts[i + 1] : html.length;
    final c0 = html.indexOf('data-col-index="0"', starts[i]);
    if (c0 < 0 || c0 >= rowEnd) continue;
    var c1 = html.indexOf('data-col-index="1"', c0);
    if (c1 < 0 || c1 > rowEnd) c1 = rowEnd;
    var cell = html.substring(c0, c1);
    // The next cell's opening tag is cut mid-way; drop that dangling `<div `.
    final dangling = cell.lastIndexOf('<');
    if (dangling > cell.lastIndexOf('>')) cell = cell.substring(0, dangling);

    final title = _titleOf(cell);
    if (title.isEmpty) continue;

    String? icon;
    final emoji = _emojiImg.firstMatch(cell);
    if (emoji != null) {
      final alt = _decodeEntities(emoji.group(1) ?? emoji.group(2) ?? '');
      if (alt.isNotEmpty) icon = alt;
    } else {
      final built = _builtinImg.firstMatch(cell);
      if (built != null) {
        icon = notionBuiltinIconEmoji[built.group(1)];
        if (icon == null) skippedBuiltin?.add(title);
      }
    }
    if (icon != null) result[title] = icon;
  }
  return result;
}

/// The row title: the first non-blank text of the first cell (icons carry
/// no text; whatever follows is other content shown in the same cell).
String _titleOf(String cell) {
  // The cell starts with the rest of its own opening tag; skip to its end.
  final open = cell.indexOf('>');
  final body = open < 0 ? cell : cell.substring(open + 1);
  for (final part in body.replaceAll(_svg, '').split(_tags)) {
    final text = _decodeEntities(part).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isNotEmpty) return normalizeDirectionName(text);
  }
  return '';
}

String _decodeEntities(String s) {
  return s
      .replaceAllMapped(
        RegExp(r'&#x([0-9a-fA-F]+);'),
        (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
      )
      .replaceAllMapped(
        RegExp(r'&#(\d+);'),
        (m) => String.fromCharCode(int.parse(m.group(1)!)),
      )
      .replaceAll('&quot;', '"')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&');
}

/// Icons from a plain text file: one `name<TAB>emoji` pair per line.
Map<String, String> parseIconLines(String text) {
  final result = <String, String>{};
  for (final line in text.split(RegExp(r'\r?\n'))) {
    final tab = line.lastIndexOf('\t');
    if (tab <= 0) continue;
    final name = normalizeDirectionName(line.substring(0, tab));
    final icon = line.substring(tab + 1).trim();
    if (name.isNotEmpty && icon.isNotEmpty) result[name] = icon;
  }
  return result;
}

/// Icons from either a saved Notion page or a `name<TAB>emoji` text file.
Map<String, String> parseIconsFile(
  String text, {
  List<String>? skippedBuiltin,
}) => text.contains('notion-collection-item')
    ? parseNotionIcons(text, skippedBuiltin: skippedBuiltin)
    : parseIconLines(text);
