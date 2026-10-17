import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/notion_icons.dart';

String _row(String iconHtml, String title) =>
    '<div class="notion-selectable notion-page-block notion-collection-item">'
    '<div data-col-index="0" style="x"><div>$iconHtml</div>'
    '<div><span>$title</span></div></div>'
    '<div data-col-index="1" style="x"><img class="notion-emoji" alt="🙈"></div>'
    '</div>';

void main() {
  test('reads emoji, maps built-in icons, ignores emoji outside first cell', () {
    final html =
        '<img class="notion-emoji" alt="🧪">' // sidebar, not a row
        '${_row('<img class="notion-emoji" alt="🚓" style="a">', 'Я не в розшуку')}'
        '${_row('<img alt="" src="f_files/calculator_green_7kh-.svg">', 'Знаю витрати')}'
        '${_row('<img alt="" src="f_files/mystery_red_7kh-.svg">', 'Невідомо')}'
        '${_row('', 'Без іконки')}'
        '${_row('<img class="notion-emoji" alt="💪🏻">', 'Здоров&#x27;я &amp; сила')}';
    final skipped = <String>[];
    final icons = parseNotionIcons(html, skippedBuiltin: skipped);
    expect(icons, {
      'Я не в розшуку': '🚓',
      'Знаю витрати': '🧮',
      "Здоров'я & сила": '💪🏻',
    });
    expect(skipped, ['Невідомо']);
  });

  test('hostile character references and long alt text never throw', () {
    final html =
        '${_row('<img class="notion-emoji" alt="&#99999999999;&#xFFFFFFFFF;&#0;&#xD800;ok">', 'Bad refs')}'
        '${_row('<img class="notion-emoji" alt="${'🙂' * 40}">', 'Too long')}'
        '${_row('<img class="notion-emoji" alt="🚓">', 'Fine')}';
    late Map<String, String> icons;
    expect(() => icons = parseNotionIcons(html), returnsNormally);
    // A reference that is not a real code point stays as written, so the
    // text is not an emoji any more but nothing crashes; an absurdly long alt
    // is not stored as an icon.
    expect(icons.containsKey('Too long'), isFalse);
    expect(icons['Fine'], '🚓');
  });

  test('the saved Notion page in dev/references yields its 17 rows', () {
    final f = File(
      '../dev/references/GrowthDirections/(9+) Growth Directions _ Flat _ Notion.htm',
    );
    if (!f.existsSync()) return; // reference file is optional
    final icons = parseNotionIcons(f.readAsStringSync());
    expect(icons.length, 17);
    expect(icons['Я не в розшуку в Туреччині'], '🚓');
  });

  test('parses name<TAB>emoji lines and routes by content', () {
    const tsv = 'Мама має здоров’я\t💪🏻\r\nбез табуляції\r\nX\t\r\nY\t🅱️\n';
    expect(parseIconLines(tsv), {"Мама має здоров'я": '💪🏻', 'Y': '🅱️'});
    expect(parseIconsFile(tsv), parseIconLines(tsv));
  });
}
