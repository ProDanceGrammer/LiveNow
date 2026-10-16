import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/ui/widgets/notes_blocks/notes_blocks.dart';
import 'package:livenow/ui/widgets/notes_editor.dart';

/// Home / End / line selection, Ctrl+A in code and multi-line paste in a code
/// block.
String jsonOf(List<Node> nodes) =>
    jsonEncode((Document.blank()..insert([0], nodes)).toJson());

void main() {
  test('physicalLineBounds', () {
    expect(physicalLineBounds('ab\ncde\nf', 0), (start: 0, end: 2));
    expect(physicalLineBounds('ab\ncde\nf', 2), (start: 0, end: 2));
    expect(physicalLineBounds('ab\ncde\nf', 3), (start: 3, end: 6));
    expect(physicalLineBounds('ab\ncde\nf', 5), (start: 3, end: 6));
    expect(physicalLineBounds('ab\ncde\nf', 8), (start: 7, end: 8));
    expect(physicalLineBounds('ab\n', 3), (start: 3, end: 3));
    expect(physicalLineBounds('', 0), (start: 0, end: 0));
  });

  Future<NotesEditorState> pump(WidgetTester tester, List<Node> nodes) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: NotesEditor(initialJson: jsonOf(nodes), onChanged: (_) {}),
          ),
        ),
      ),
    );
    await tester.pump();
    return tester.state<NotesEditorState>(find.byType(NotesEditor));
  }

  Future<void> key(
    WidgetTester tester,
    LogicalKeyboardKey k, {
    bool ctrl = false,
    bool shift = false,
  }) async {
    if (ctrl) await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(k);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    if (ctrl) await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump(const Duration(milliseconds: 50));
  }

  Selection at(List<int> path, int from, [int? to]) => Selection(
    start: Position(path: path, offset: from),
    end: Position(path: path, offset: to ?? from),
  );

  testWidgets('Home / End / Shift+End work on the line of a code block', (
    tester,
  ) async {
    final s = await pump(tester, [codeBlockNode('ab\ncde\nf')]);
    final e = s.editorState;
    e.selection = at([0], 5); // inside "cde"
    await tester.pump();

    await key(tester, LogicalKeyboardKey.home);
    expect(e.selection, at([0], 3));
    await key(tester, LogicalKeyboardKey.end);
    expect(e.selection, at([0], 6));

    e.selection = at([0], 4);
    await tester.pump();
    await key(tester, LogicalKeyboardKey.end, shift: true);
    expect(e.selection, at([0], 4, 6));
    await key(tester, LogicalKeyboardKey.home, shift: true);
    // The anchor (4) stays, the caret goes to the line start.
    expect(e.selection, at([0], 4, 3));
  });

  testWidgets('Ctrl+L selects the line; Ctrl+A selects the code, then all', (
    tester,
  ) async {
    final s = await pump(tester, [
      paragraphNode(text: 'before'),
      codeBlockNode('ab\ncde\nf'),
    ]);
    final e = s.editorState;
    e.selection = at([1], 4);
    await tester.pump();

    await key(tester, LogicalKeyboardKey.keyL, ctrl: true);
    expect(e.selection, at([1], 3, 6));

    await key(tester, LogicalKeyboardKey.keyA, ctrl: true);
    expect(e.selection, at([1], 0, 8)); // the whole code block
    await key(tester, LogicalKeyboardKey.keyA, ctrl: true);
    expect(e.selection!.normalized.start.path, [0]); // everything
    expect(e.selection!.normalized.end.path, [1]);
  });

  testWidgets('Ctrl+Home / Ctrl+Shift+End move and select to the edges', (
    tester,
  ) async {
    final s = await pump(tester, [
      paragraphNode(text: 'first'),
      paragraphNode(text: 'second'),
    ]);
    final e = s.editorState;
    e.selection = at([0], 2);
    await tester.pump();
    await key(tester, LogicalKeyboardKey.end, ctrl: true);
    expect(e.selection, at([1], 6));
    await key(tester, LogicalKeyboardKey.home, ctrl: true);
    expect(e.selection, at([0], 0));
    await key(tester, LogicalKeyboardKey.end, ctrl: true, shift: true);
    expect(e.selection, Selection(start: Position(path: [0]), end: Position(path: [1], offset: 6)));
  });

  testWidgets('Ctrl+Shift+Right / Left select words', (tester) async {
    final s = await pump(tester, [paragraphNode(text: 'one two three')]);
    final e = s.editorState;
    e.selection = at([0], 0);
    await tester.pump();
    await key(tester, LogicalKeyboardKey.arrowRight, ctrl: true, shift: true);
    expect(e.selection!.end.offset, greaterThanOrEqualTo(3));
    expect(e.selection!.end.offset, lessThanOrEqualTo(4));
    await key(tester, LogicalKeyboardKey.arrowLeft, ctrl: true, shift: true);
    expect(e.selection!.isCollapsed, isTrue);
  });

  testWidgets('pasting many lines into a code block keeps them ALL in it', (
    tester,
  ) async {
    const clip = 'line 1\r\nline 2\n  line 3';
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') return {'text': clip};
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final s = await pump(tester, [codeBlockNode('xy')]);
    final e = s.editorState;
    e.selection = at([0], 1);
    await tester.pump();

    await key(tester, LogicalKeyboardKey.keyV, ctrl: true);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    expect(e.document.root.children, hasLength(1));
    expect(
      e.document.root.children.first.delta!.toPlainText(),
      'xline 1\nline 2\n  line 3y',
    );
    expect(e.selection, at([0], 1 + 'line 1\nline 2\n  line 3'.length));

    // Ctrl+Shift+V (the Markdown paste) too, over a selection.
    e.selection = at([0], 0, e.document.root.children.first.delta!.length);
    await tester.pump();
    await key(tester, LogicalKeyboardKey.keyV, ctrl: true, shift: true);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(e.document.root.children, hasLength(1));
    expect(
      e.document.root.children.first.delta!.toPlainText(),
      'line 1\nline 2\n  line 3',
    );
  });

  testWidgets('Home / End go to the start / end of the WRAPPED line', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(300, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final text = List.filled(30, 'word').join(' ');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: NotesEditor(
              initialJson: jsonOf([paragraphNode(text: text)]),
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final e = tester.state<NotesEditorState>(find.byType(NotesEditor)).editorState;
    e.selection = at([0], 62);
    await tester.pump();
    await key(tester, LogicalKeyboardKey.home);
    final start = e.selection!.end.offset;
    expect(start, greaterThan(0));
    expect(start, lessThan(62));
    e.selection = at([0], 62);
    await tester.pump();
    await key(tester, LogicalKeyboardKey.end);
    final end = e.selection!.end.offset;
    expect(end, greaterThan(62));
    expect(end, lessThan(text.length));
  });

  testWidgets('a triple click in a code block selects the line, not the block', (
    tester,
  ) async {
    final s = await pump(tester, [codeBlockNode('first line\nsecond line\nthird')]);
    final e = s.editorState;
    await tester.pump(const Duration(milliseconds: 100));
    // Click on the first line of the code text.
    final box = tester.getRect(find.byType(CodeBlockComponentWidget));
    final p = Offset(box.left + 40, box.top + 18);
    for (var i = 0; i < 3; i++) {
      await tester.tapAt(p, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 40));
    }
    await tester.pump(const Duration(milliseconds: 400));
    expect(e.selection, at([0], 0, 10)); // "first line"
  });
}
