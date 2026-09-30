import 'dart:convert';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/ui/widgets/notes_document.dart';

/// Compact tree dump: `type:text` with children in `[...]`, and `!` marking a
/// checked todo.
String dump(Node n) {
  final text = n.delta?.toPlainText();
  final checked = n.attributes['checked'] == true ? '!' : '';
  final kids = n.children.isEmpty ? '' : '[${n.children.map(dump).join(', ')}]';
  return '${n.type}$checked:${text ?? ''}$kids';
}

String dumpDoc(Document d) => d.root.children.map(dump).join(' | ');

const sample = '''
- [ ]  Робоча пошта Kickbite
    - [ ]  Gmail
    - [ ]  Slack
- [ ]  Особиста робоча пошта
    - [ ]  prodancegrammer@gmail.com
    - [ ]  LinkedIn

Особисті акаунти

- [ ]  Telegram
- [ ]  WhatsApp
- [ ]  Viber
- [ ]  Instagram
- [ ]  Messenger
- Archived
    - [ ]  work.ua
    - [ ]  dou.com
    - [ ]  djinni.co
        - [ ]  Нагадати про себе тим, хто прочитав і не відповів
''';

void main() {
  test('markdown sample becomes the exact expected tree', () {
    final doc = markdownToNotesDocument(sample);
    expect(
      dumpDoc(doc),
      'todo_list:Робоча пошта Kickbite[todo_list:Gmail, todo_list:Slack]'
      ' | todo_list:Особиста робоча пошта'
      '[todo_list:prodancegrammer@gmail.com, todo_list:LinkedIn]'
      ' | paragraph:Особисті акаунти'
      ' | todo_list:Telegram | todo_list:WhatsApp | todo_list:Viber'
      ' | todo_list:Instagram | todo_list:Messenger'
      ' | bulleted_list:Archived[todo_list:work.ua, todo_list:dou.com,'
      ' todo_list:djinni.co[todo_list:Нагадати про себе тим, хто прочитав і не відповів]]',
    );
  });

  test('fenced code becomes a code node between surrounding blocks', () {
    final doc = markdownToNotesDocument(
      'before\n\n```dart\nfinal a = 1;\n\nprint(a);\n```\n\n- after\n',
    );
    expect(
      dumpDoc(doc),
      'paragraph:before | code:final a = 1;\n\nprint(a); | bulleted_list:after',
    );
  });

  test('JSON round trip keeps Cyrillic and nesting', () {
    final doc = markdownToNotesDocument(sample);
    final json = notesDocumentToJson(doc)!;
    final back = notesDocumentFromJson(json);
    expect(dumpDoc(back), dumpDoc(doc));
    expect(jsonDecode(json), isA<Map>());
  });

  test('null, empty and corrupt JSON give a blank document', () {
    for (final bad in [
      null,
      '',
      '   ',
      '{not json',
      '[]',
      '{"document": 5}',
      '{"document":{"type":"page"}}',
    ]) {
      final doc = notesDocumentFromJson(bad);
      expect(doc.root.children.length, 1, reason: '$bad');
      expect(doc.root.children.first.type, 'paragraph');
      expect(notesDocumentIsEmpty(doc), isTrue);
    }
  });

  test('empty documents serialise to null, others do not', () {
    expect(notesDocumentToJson(Document.blank(withInitialText: true)), isNull);
    expect(notesDocumentToJson(Document.blank()), isNull);
    final twoBlank = Document.blank()
      ..insert([0], [paragraphNode(), paragraphNode()]);
    expect(notesDocumentToJson(twoBlank), isNull);
    final text = Document.blank()..insert([0], [paragraphNode(text: 'x')]);
    expect(notesDocumentToJson(text), isNotNull);
    final todo = Document.blank()..insert([0], [todoListNode(checked: false)]);
    expect(notesDocumentToJson(todo), isNotNull);
  });

  test('resetChecklist unticks nested items and keeps text', () async {
    final doc = Document.blank()
      ..insert(
        [0],
        [
          todoListNode(
            checked: true,
            text: 'Один',
            children: [todoListNode(checked: true, text: 'Вкладений')],
          ),
          paragraphNode(text: 'p'),
          todoListNode(checked: false, text: 'Три'),
        ],
      );
    final state = EditorState(document: doc);
    await resetChecklist(state);
    expect(
      dumpDoc(state.document),
      'todo_list:Один[todo_list:Вкладений] | paragraph:p | todo_list:Три',
    );
    // No checked items -> no transaction (nothing to undo).
    var changes = 0;
    final sub = state.transactionStream.listen((_) => changes++);
    await resetChecklist(state);
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(changes, 0);
  });
}
