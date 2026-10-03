import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/notes_plain_text.dart';

void main() {
  test('extracts lower-cased text from nested blocks, Cyrillic included', () {
    const json =
        '{"document":{"type":"page","children":['
        '{"type":"heading","data":{"level":1,"delta":[{"insert":"Купити "},'
        '{"insert":"МОЛОКО","attributes":{"bold":true}}]}},'
        '{"type":"toggle_list","data":{"delta":[{"insert":"Parent"}]},'
        '"children":[{"type":"todo_list","data":{"checked":false,'
        '"delta":[{"insert":"Child ITEM"}]}}]}]}}';
    expect(notesPlainText(json), 'купити молоко\nparent\nchild item');
  });

  test('null, empty, corrupt or text-less input gives null', () {
    expect(notesPlainText(null), isNull);
    expect(notesPlainText('  '), isNull);
    expect(notesPlainText('not json'), isNull);
    expect(notesPlainText('[1,2]'), isNull);
    expect(
      notesPlainText(
        '{"document":{"type":"page","children":[{"type":"paragraph",'
        '"data":{"delta":[]}}]}}',
      ),
      isNull,
    );
  });
}
