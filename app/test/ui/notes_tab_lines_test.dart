import 'dart:convert';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/ui/widgets/notes_blocks/notes_blocks.dart';
import 'package:livenow/ui/widgets/notes_editor.dart';

/// Tab / Shift+Tab in a code block act on EVERY selected line (they used to
/// replace the selection with two spaces).
String applyEdits(String text, LineShift s) {
  var t = text;
  for (final e in s.edits) {
    t = t.substring(0, e.offset) + e.insert + t.substring(e.offset + e.remove);
  }
  return t;
}

String jsonOf(List<Node> nodes) =>
    jsonEncode((Document.blank()..insert([0], nodes)).toJson());

void main() {
  group('indentLines / outdentLines', () {
    test('indent: two spaces on every touched line', () {
      final r = indentLines('a\nb\nc', 1, 3);
      expect(applyEdits('a\nb\nc', r), '  a\n  b\nc');
      // The selection still covers the same text.
      final t = applyEdits('a\nb\nc', r);
      expect(t.substring(r.start, r.end), '\n  b');
    });

    test('a selection ending at the start of a line leaves that line alone', () {
      final r = indentLines('a\nb\n', 0, 2);
      expect(applyEdits('a\nb\n', r), '  a\nb\n');
    });

    test('a caret at the start of a line indents just that line', () {
      final r = indentLines('a\nb', 2, 2);
      expect(applyEdits('a\nb', r), 'a\n  b');
      expect((r.start, r.end), (2, 4));
    });

    test('outdent: up to two spaces, tabs, nothing to remove', () {
      const text = '    a\n b\n\tc\nd';
      final r = outdentLines(text, 0, text.length);
      expect(applyEdits(text, r), '  a\nb\nc\nd');
    });

    test('outdent keeps the selection on its text', () {
      const text = '  ab\n  cd';
      final r = outdentLines(text, 3, 8);
      final t = applyEdits(text, r);
      expect(t, 'ab\ncd');
      expect(t.substring(r.start, r.end), 'b\nc');
    });

    test('outdent of an unindented selection changes nothing', () {
      final r = outdentLines('a\nb', 0, 3);
      expect(r.edits, isEmpty);
      expect((r.start, r.end), (0, 3));
    });
  });

  group('in the editor', () {
    Future<NotesEditorState> pump(WidgetTester tester, String code) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: NotesEditor(
                initialJson: jsonOf([codeBlockNode(code)]),
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return tester.state<NotesEditorState>(find.byType(NotesEditor));
    }

    Future<void> tab(WidgetTester tester, {bool shift = false}) async {
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump(const Duration(milliseconds: 50));
    }

    String code(NotesEditorState s) =>
        s.editorState.document.root.children.first.delta!.toPlainText();

    testWidgets('Tab indents every selected line, Shift+Tab takes it back', (
      tester,
    ) async {
      final s = await pump(tester, 'one\ntwo\nthree');
      s.editorState.selection = Selection(
        start: Position(path: [0], offset: 1),
        end: Position(path: [0], offset: 9),
      );
      await tester.pump();

      await tab(tester);
      expect(code(s), '  one\n  two\n  three');
      // The selection moved with the text: still two-thirds of it.
      final sel = s.editorState.selection!.normalized;
      expect(code(s).substring(sel.startIndex, sel.endIndex), 'ne\n  two\n  t');

      await tab(tester, shift: true);
      expect(code(s), 'one\ntwo\nthree');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('Shift+Tab on a caret outdents its line only', (tester) async {
      final s = await pump(tester, '  a\n  b');
      s.editorState.selection = Selection.collapsed(
        Position(path: [0], offset: 6),
      );
      await tester.pump();
      await tab(tester, shift: true);
      expect(code(s), '  a\nb');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('a selection inside ONE line is still replaced by two spaces', (
      tester,
    ) async {
      final s = await pump(tester, 'abcdef');
      s.editorState.selection = Selection(
        start: Position(path: [0], offset: 1),
        end: Position(path: [0], offset: 3),
      );
      await tester.pump();
      await tab(tester);
      expect(code(s), 'a  def');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 500));
    });
  });
}
