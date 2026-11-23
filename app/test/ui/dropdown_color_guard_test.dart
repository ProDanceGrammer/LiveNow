import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The glass theme's `canvasColor` is transparent, and a Material dropdown
/// paints its open menu in that colour unless it is given `dropdownColor`: the
/// menu then shows the dialog through it (bug 2026-11-23 img_3). Every
/// DropdownButton in lib/ must set it.
void main() {
  test('every DropdownButton sets dropdownColor', () {
    final start = RegExp(r'\bDropdownButton(FormField)?(<[^>]*>)?\(');
    final missing = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final s = f.readAsStringSync();
      for (final m in start.allMatches(s)) {
        var i = m.end;
        var depth = 1;
        while (depth > 0 && i < s.length) {
          final c = s[i];
          if (c == '(') depth++;
          if (c == ')') depth--;
          i++;
        }
        if (!s.substring(m.start, i).contains('dropdownColor')) {
          final line = '\n'.allMatches(s.substring(0, m.start)).length + 1;
          missing.add('${f.path}:$line');
        }
      }
    }
    expect(missing, isEmpty);
  });
}
