import '../core/ids.dart';
import 'forms.dart';

/// Splits a leading emoji (or a run of symbols) off [text]: ('🎓', 'rest'), or
/// (null, text) when it does not start with one. Only characters from U+2190 up
/// count as symbols, so `#`, digits and letters stay in the text.
(String?, String) splitLeadingIcon(String text) {
  final t = text.trimLeft();
  if (t.isEmpty) return (null, '');
  final runes = t.runes.toList();
  var i = 0;
  while (i < runes.length && _isSymbol(runes[i])) {
    i++;
  }
  if (i == 0) return (null, t.trim());
  final icon = String.fromCharCodes(runes.sublist(0, i)).trim();
  final rest = String.fromCharCodes(runes.sublist(i)).trim();
  return (icon.isEmpty ? null : icon, rest);
}

bool _isSymbol(int r) =>
    r >= 0x2190 ||
    r == 0x200D || // zero-width joiner inside an emoji sequence
    (r >= 0xFE00 && r <= 0xFE0F); // variation selectors

final _bullet = RegExp(r'^(\s*)([-*•·▪◦☐☑✓✔]|\[\s?[xX ]?\s?\])\s+');
final _numbered = RegExp(r'^(\s*)\d+[.)]\s+');
final _hint = RegExp(r'^\s*\((.*)\)\s*$');

/// Turns pasted text into questions. A line that is not a bullet starts a
/// question (a leading emoji becomes its icon); the bulleted or indented lines
/// under it are its options (a leading emoji becomes the option's icon); a line
/// in parentheses right under a question is its hint; blank lines are ignored.
/// Options that come before any heading go to a question called `Question`.
List<FormQuestion> parseOutline(String text) {
  final questions = <FormQuestion>[];
  FormQuestion? current;
  var options = <FormOption>[];

  void flush() {
    final q = current;
    if (q != null) questions.add(q.copyWith(options: options));
    current = null;
    options = <FormOption>[];
  }

  for (final raw in text.replaceAll('\r\n', '\n').split('\n')) {
    final line = raw.trimRight();
    if (line.trim().isEmpty) continue;

    final isOption =
        _bullet.hasMatch(line) ||
        _numbered.hasMatch(line) ||
        (current != null && RegExp(r'^\s{2,}\S').hasMatch(line));

    if (isOption) {
      final body = line
          .replaceFirst(_bullet, '')
          .replaceFirst(_numbered, '')
          .trim();
      final (icon, label) = splitLeadingIcon(body);
      if (label.isEmpty) continue;
      current ??= FormQuestion(id: newId(), title: 'Question');
      options.add(FormOption(id: newId(), label: label, icon: icon));
      continue;
    }

    final hint = _hint.firstMatch(line);
    if (hint != null && current != null && options.isEmpty) {
      current = current!.copyWith(hint: hint.group(1)!.trim());
      continue;
    }

    flush();
    final (icon, title) = splitLeadingIcon(line);
    if (title.isEmpty) continue;
    current = FormQuestion(id: newId(), title: title, icon: icon);
  }
  flush();
  return questions;
}

/// Turns pasted lines into the options of ONE question: every non-empty line is
/// an option (a bullet or number in front is dropped, a leading emoji becomes
/// the option's icon).
List<FormOption> parseOptionLines(String text) {
  final options = <FormOption>[];
  for (final raw in text.replaceAll('\r\n', '\n').split('\n')) {
    final body = raw
        .replaceFirst(_bullet, '')
        .replaceFirst(_numbered, '')
        .trim();
    if (body.isEmpty) continue;
    final (icon, label) = splitLeadingIcon(body);
    if (label.isEmpty) continue;
    options.add(FormOption(id: newId(), label: label, icon: icon));
  }
  return options;
}
