import 'dart:convert';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/ui/widgets/notes_blocks/notes_blocks.dart';
import 'package:livenow/ui/widgets/notes_document.dart';
import 'package:livenow/ui/widgets/notes_editor.dart';

/// Round 20: a copy / cut / paste inside the app keeps every block exactly (toggles
/// with their collapsed state, bullets, numbers, checkboxes with their value,
/// code), a checkbox toggle with a selection hits every selected checkbox, and a
/// code block can be copied raw.
String dump(Node n) {
  final text = n.delta?.toPlainText();
  final checked = n.attributes['checked'] == true ? '!' : '';
  final closed = n.attributes['collapsed'] == true ? '^' : '';
  final kids = n.children.isEmpty ? '' : '[${n.children.map(dump).join(', ')}]';
  return '${n.type}$checked$closed:${text ?? ''}$kids';
}

String dumpDoc(Document d) => d.root.children.map(dump).join(' | ');

String jsonOf(List<Node> nodes) =>
    jsonEncode((Document.blank()..insert([0], nodes)).toJson());

void main() {
  String? clip;

  void fakeClipboard(WidgetTester tester) {
    clip = null;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clip = (call.arguments as Map)['text'] as String?;
          return null;
        }
        if (call.method == 'Clipboard.getData') {
          return clip == null ? null : <String, dynamic>{'text': clip};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
  }

  Future<NotesEditorState> pumpEditor(
    WidgetTester tester,
    List<Node> nodes, {
    Size size = const Size(1200, 1000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    fakeClipboard(tester);
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

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> ctrl(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    // The clipboard channel is async.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }

  Node structure() => Node(
    type: toggleListBlockType,
    attributes: {
      'delta': (Delta()..insert('Parent')).toJson(),
      toggleListCollapsedKey: true,
    },
    children: [
      bulletedListNode(text: 'bullet'),
      numberedListNode(delta: Delta()..insert('number')),
      todoListNode(checked: true, text: 'done'),
      todoListNode(checked: false, text: 'open'),
      codeBlockNode('print(1)\nprint(2)'),
    ],
  );

  group('lossless copy / cut / paste inside the app', () {
    testWidgets('a closed toggle with bullets, numbers, checkboxes and code', (
      tester,
    ) async {
      final state = await pumpEditor(tester, [structure(), paragraphNode()]);
      final ed = state.editorState;
      final before = dump(ed.document.root.children.first);
      expect(before, contains('toggle_list^:Parent'));

      ed.selection = Selection(
        start: Position(path: [0], offset: 0),
        end: Position(path: [0, 4], offset: 17),
      );
      await tester.pump();
      await ctrl(tester, LogicalKeyboardKey.keyC);
      expect(clip, isNotNull, reason: 'Markdown reached the clipboard');

      ed.selection = Selection.collapsed(Position(path: [1], offset: 0));
      await tester.pump();
      await ctrl(tester, LogicalKeyboardKey.keyV);

      // The empty paragraph was replaced by an exact copy of the toggle.
      expect(ed.document.root.children, hasLength(2));
      expect(dump(ed.document.root.children[1]), before);
      expect(
        ed.document.root.children[1].attributes[toggleListCollapsedKey],
        true,
      );
      await unmount(tester);
    });

    testWidgets('cut keeps the structure too', (tester) async {
      final state = await pumpEditor(tester, [
        todoListNode(checked: true, text: 'first'),
        paragraphNode(text: 'plain'),
        paragraphNode(),
      ]);
      final ed = state.editorState;
      ed.selection = Selection(
        start: Position(path: [0], offset: 0),
        end: Position(path: [0], offset: 5),
      );
      await tester.pump();
      await ctrl(tester, LogicalKeyboardKey.keyX);
      // The text is gone, the clipboard has it.
      expect(dumpDoc(ed.document), isNot(contains('first')));
      expect(clip, isNotNull);

      ed.selection = Selection.collapsed(
        Position(path: [ed.document.root.children.length - 1], offset: 0),
      );
      await tester.pump();
      await ctrl(tester, LogicalKeyboardKey.keyV);
      // (A one-paragraph selection comes back inline as text.)
      expect(dumpDoc(ed.document), contains('first'));
      await unmount(tester);
    });

    testWidgets('text from elsewhere still pastes as plain text', (tester) async {
      final state = await pumpEditor(tester, [
        paragraphNode(text: 'one'),
        paragraphNode(),
      ]);
      final ed = state.editorState;
      // Something was copied here ...
      ed.selection = Selection(
        start: Position(path: [0], offset: 0),
        end: Position(path: [0], offset: 3),
      );
      await tester.pump();
      await ctrl(tester, LogicalKeyboardKey.keyC);
      // ... but the clipboard now holds foreign text.
      clip = 'from elsewhere';
      ed.selection = Selection.collapsed(Position(path: [1], offset: 0));
      await tester.pump();
      await ctrl(tester, LogicalKeyboardKey.keyV);
      expect(dumpDoc(ed.document), contains('from elsewhere'));
      await unmount(tester);
    });

    testWidgets('pasting over a selection replaces it', (tester) async {
      final state = await pumpEditor(tester, [
        todoListNode(checked: true, text: 'keep'),
        paragraphNode(text: 'REPLACE'),
      ]);
      final ed = state.editorState;
      ed.selection = Selection(
        start: Position(path: [0], offset: 0),
        end: Position(path: [0], offset: 4),
      );
      await tester.pump();
      await ctrl(tester, LogicalKeyboardKey.keyC);
      ed.selection = Selection(
        start: Position(path: [1], offset: 0),
        end: Position(path: [1], offset: 7),
      );
      await tester.pump();
      await ctrl(tester, LogicalKeyboardKey.keyV);
      final text = dumpDoc(ed.document);
      expect(text, isNot(contains('REPLACE')));
      expect(text, contains('keep'));
      await unmount(tester);
    });
  });

  group('code blocks', () {
    testWidgets('the Copy button puts the whole code on the clipboard', (
      tester,
    ) async {
      final code = codeBlockNode('a = 1\nb = 2');
      await pumpEditor(tester, [paragraphNode(text: 'x'), code]);
      final button = find.byKey(ValueKey('code-copy-${code.id}'));
      // The document was rebuilt from JSON: ids differ, find by prefix.
      final anyButton = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('code-copy-'),
      );
      expect(button.evaluate().isEmpty ? anyButton : button, findsOneWidget);
      await tester.tap(anyButton);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      expect(clip, 'a = 1\nb = 2');
      expect(find.text('Copied'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      await unmount(tester);
    });

    testWidgets('Ctrl+C on a selection inside code copies the raw text', (
      tester,
    ) async {
      final state = await pumpEditor(tester, [
        codeBlockNode('first line\nsecond line'),
      ]);
      final ed = state.editorState;
      ed.selection = Selection(
        start: Position(path: [0], offset: 0),
        end: Position(path: [0], offset: 10),
      );
      await tester.pump();
      await ctrl(tester, LogicalKeyboardKey.keyC);
      expect(clip, 'first line');
      expect(clip, isNot(contains('```')));
      await unmount(tester);
    });
  });

  group('checkboxes with a selection', () {
    List<Node> three() => [
      todoListNode(checked: false, text: 'a'),
      paragraphNode(text: 'between'),
      todoListNode(checked: true, text: 'b'),
      todoListNode(checked: false, text: 'c'),
    ];

    bool checked(NotesEditorState s, int i) =>
        s.editorState.document.root.children[i].attributes['checked'] == true;

    testWidgets('tapping one ticks every selected checkbox, one Undo reverts', (
      tester,
    ) async {
      final state = await pumpEditor(tester, three());
      final ed = state.editorState;
      final sel = Selection(
        start: Position(path: [0], offset: 0),
        end: Position(path: [3], offset: 1),
      );
      ed.selection = sel;
      await tester.pump();
      // The first (unchecked) box is tapped: all become CHECKED.
      await tester.tap(find.byIcon(Icons.check_box_outline_blank).first);
      await tester.pump();
      expect([checked(state, 0), checked(state, 2), checked(state, 3)], [
        true,
        true,
        true,
      ]);
      // One Undo step restores all three.
      ed.undoManager.undo();
      await tester.pump();
      expect([checked(state, 0), checked(state, 2), checked(state, 3)], [
        false,
        true,
        false,
      ]);
      await unmount(tester);
    });

    testWidgets('tapping a ticked one clears them all', (tester) async {
      final state = await pumpEditor(tester, three());
      final ed = state.editorState;
      ed.selection = Selection(
        start: Position(path: [0], offset: 0),
        end: Position(path: [3], offset: 1),
      );
      await tester.pump();
      await tester.tap(find.byIcon(Icons.check_box).first);
      await tester.pump();
      expect([checked(state, 0), checked(state, 2), checked(state, 3)], [
        false,
        false,
        false,
      ]);
      await unmount(tester);
    });

    testWidgets('a tap outside the selection toggles only that box', (
      tester,
    ) async {
      final state = await pumpEditor(tester, three());
      final ed = state.editorState;
      ed.selection = Selection(
        start: Position(path: [1], offset: 0),
        end: Position(path: [1], offset: 4),
      );
      await tester.pump();
      await tester.tap(find.byIcon(Icons.check_box_outline_blank).first);
      await tester.pump();
      expect([checked(state, 0), checked(state, 2), checked(state, 3)], [
        true,
        true,
        false,
      ]);
      await unmount(tester);
    });

    testWidgets('Ctrl+Enter over a selection ticks them all, then clears them', (
      tester,
    ) async {
      final state = await pumpEditor(tester, three());
      final ed = state.editorState;
      ed.selection = Selection(
        start: Position(path: [0], offset: 0),
        end: Position(path: [3], offset: 1),
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pump();
      expect([checked(state, 0), checked(state, 2), checked(state, 3)], [
        true,
        true,
        true,
      ]);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pump();
      expect([checked(state, 0), checked(state, 2), checked(state, 3)], [
        false,
        false,
        false,
      ]);
      await unmount(tester);
    });
  });
}
