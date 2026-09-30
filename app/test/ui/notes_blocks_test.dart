import 'dart:convert';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/ui/widgets/notes_blocks/notes_blocks.dart';

EditorState stateOf(List<Node> children) => EditorState(
  document: Document(root: pageNode(children: children)),
);

void select(EditorState s, List<int> path, [int offset = 0]) {
  s.selection = Selection.collapsed(Position(path: path, offset: offset));
}

Node para(String text) => paragraphNode(text: text);

String textAt(EditorState s, List<int> path) =>
    s.getNodeAtPath(path)!.delta!.toPlainText();

Future<bool> press(CharacterShortcutEvent e, EditorState s) => e.handler(s);

Future<bool> enter(EditorState s) => customNotesCharacterShortcuts()
    .firstWhere(
      (e) => e.character == '\n' && e.key == 'insert new line in toggle list',
    )
    .handler(s);

Future<bool> enterCode(EditorState s) => customNotesCharacterShortcuts()
    .firstWhere((e) => e.key == 'insert new line in code block')
    .handler(s);

Future<Widget> _editorApp(
  WidgetTester tester,
  EditorState s, {
  ThemeData? theme,
}) async {
  final w = MaterialApp(
    theme: theme,
    localizationsDelegates: const [AppFlowyEditorLocalizations.delegate],
    home: Scaffold(
      body: SizedBox(
        width: 700,
        height: 600,
        child: AppFlowyEditor(
          editorState: s,
          blockComponentBuilders: {
            ...standardBlockComponentBuilderMap,
            ...customNotesBlockBuilders(),
          },
          characterShortcutEvents: [
            ...customNotesCharacterShortcuts(),
            ...standardCharacterShortcutEvents,
          ],
          commandShortcutEvents: [
            ...customNotesCommandShortcuts(),
            ...standardCommandShortcutEvents,
          ],
        ),
      ),
    ),
  );
  await tester.pumpWidget(w);
  await tester.pump(const Duration(milliseconds: 50));
  return w;
}

void main() {
  group('node factories and JSON', () {
    test('toggleListNode shape', () {
      final n = toggleListNode(
        text: 'Заголовок',
        collapsed: true,
        children: [para('вкладене')],
      );
      expect(n.type, 'toggle_list');
      expect(n.attributes['collapsed'], true);
      expect(n.delta!.toPlainText(), 'Заголовок');
      expect(n.children.length, 1);
      expect(toggleListNode(text: 'a').attributes['collapsed'], false);
    });

    test('codeBlockNode shape', () {
      final n = codeBlockNode('a\nb');
      expect(n.type, 'code');
      expect(n.delta!.toPlainText(), 'a\nb');
      expect(n.children, isEmpty);
    });

    test('JSON round trip keeps both node types unchanged', () {
      final doc = Document(
        root: pageNode(
          children: [
            toggleListNode(
              text: 'Секція',
              collapsed: true,
              children: [
                para('дитина'),
                toggleListNode(text: 'вкладений'),
              ],
            ),
            codeBlockNode('var x = 1;\nпривіт\n'),
          ],
        ),
      );
      final json = jsonEncode(doc.toJson());
      final back = Document.fromJson(jsonDecode(json) as Map<String, dynamic>);
      expect(jsonEncode(back.toJson()), json);
      final t = back.nodeAtPath([0])!;
      expect(t.type, toggleListBlockType);
      expect(t.attributes['collapsed'], true);
      expect(t.delta!.toPlainText(), 'Секція');
      expect(t.children.length, 2);
      expect(
        back.nodeAtPath([1])!.delta!.toPlainText(),
        'var x = 1;\nпривіт\n',
      );
    });
  });

  group('"> " shortcut', () {
    test('converts at paragraph start and keeps trailing text', () async {
      final s = stateOf([para('>hello')]);
      select(s, [0], 1);
      expect(await press(formatGreaterToToggleList, s), isTrue);
      final n = s.getNodeAtPath([0])!;
      expect(n.type, toggleListBlockType);
      expect(n.delta!.toPlainText(), 'hello');
      expect(n.attributes['collapsed'], false);
    });

    test('converts an empty "> " paragraph', () async {
      final s = stateOf([para('>')]);
      select(s, [0], 1);
      expect(await press(formatGreaterToToggleList, s), isTrue);
      expect(s.getNodeAtPath([0])!.type, toggleListBlockType);
      expect(textAt(s, [0]), '');
    });

    test('does not fire mid-text', () async {
      final s = stateOf([para('a>b')]);
      select(s, [0], 2);
      expect(await press(formatGreaterToToggleList, s), isFalse);
      expect(s.getNodeAtPath([0])!.type, 'paragraph');
      final s2 = stateOf([para('x >')]);
      select(s2, [0], 3);
      expect(await press(formatGreaterToToggleList, s2), isFalse);
    });
  });

  group('triple backtick shortcut', () {
    test('creates an empty code block from an empty "``" paragraph', () async {
      final s = stateOf([para('``')]);
      select(s, [0], 2);
      expect(await press(formatBackticksToCodeBlock, s), isTrue);
      final n = s.getNodeAtPath([0])!;
      expect(n.type, codeBlockType);
      expect(n.delta!.toPlainText(), '');
      expect(s.selection!.start.path, [0]);
    });

    test('does not fire when the paragraph has other text', () async {
      final s = stateOf([para('x``')]);
      select(s, [0], 3);
      expect(await press(formatBackticksToCodeBlock, s), isFalse);
      final s2 = stateOf([para('``x')]);
      select(s2, [0], 2);
      expect(await press(formatBackticksToCodeBlock, s2), isFalse);
    });

    test('runs before the markdown inline-code shortcut in the list', () {
      final all = [
        ...customNotesCharacterShortcuts(),
        ...markdownSyntaxShortcutEvents,
      ];
      expect(
        all.indexOf(formatBackticksToCodeBlock),
        lessThan(all.indexOf(formatBackquoteToCode)),
      );
    });
  });

  group('toggle Enter / Backspace', () {
    test(
      'Enter at end of expanded toggle with children adds first child',
      () async {
        final s = stateOf([
          toggleListNode(text: 'T', children: [para('c1')]),
        ]);
        select(s, [0], 1);
        expect(await enter(s), isTrue);
        final t = s.getNodeAtPath([0])!;
        expect(t.children.length, 2);
        expect(textAt(s, [0, 0]), '');
        expect(textAt(s, [0, 1]), 'c1');
        expect(s.selection!.start.path, [0, 0]);
      },
    );

    test('Enter mid-title moves the tail into the first child', () async {
      final s = stateOf([
        toggleListNode(text: 'Title', children: [para('c1')]),
      ]);
      select(s, [0], 2);
      await enter(s);
      expect(textAt(s, [0]), 'Ti');
      expect(textAt(s, [0, 0]), 'tle');
    });

    test('Enter in a collapsed toggle adds a sibling, children stay', () async {
      final s = stateOf([
        toggleListNode(text: 'T', collapsed: true, children: [para('c1')]),
      ]);
      select(s, [0], 1);
      await enter(s);
      expect(s.document.root.children.length, 2);
      expect(s.getNodeAtPath([0])!.children.length, 1);
      expect(s.getNodeAtPath([1])!.type, 'paragraph');
      expect(s.selection!.start.path, [1]);
    });

    test('Enter in an expanded toggle with no children adds a child', () async {
      // The flow "> Title", Enter, type: the new line belongs INSIDE the toggle.
      final s = stateOf([toggleListNode(text: 'T')]);
      select(s, [0], 1);
      await enter(s);
      expect(s.document.root.children.length, 1);
      expect(s.getNodeAtPath([0])!.children.length, 1);
      expect(s.getNodeAtPath([0, 0])!.type, 'paragraph');
      expect(s.selection!.start.path, [0, 0]);
    });

    test('a second Enter on that empty child leaves the toggle', () async {
      final s = stateOf([toggleListNode(text: 'T')]);
      select(s, [0], 1);
      await enter(s); // creates the child, caret inside it
      await enter(s); // empty child -> moves out
      expect(s.document.root.children.length, 2);
      expect(s.getNodeAtPath([0])!.children, isEmpty);
      expect(s.getNodeAtPath([1])!.type, 'paragraph');
    });

    test(
      'Enter on an empty child paragraph moves it out of the toggle',
      () async {
        final s = stateOf([
          toggleListNode(text: 'T', children: [para('c1'), para('')]),
        ]);
        select(s, [0, 1], 0);
        expect(await enter(s), isTrue);
        expect(s.getNodeAtPath([0])!.children.length, 1);
        expect(s.getNodeAtPath([1])!.type, 'paragraph');
        expect(s.selection!.start.path, [1]);
      },
    );

    test(
      'Enter on a non-empty child paragraph is left to the default',
      () async {
        final s = stateOf([
          toggleListNode(text: 'T', children: [para('c1')]),
        ]);
        select(s, [0, 0], 2);
        expect(await enter(s), isFalse);
      },
    );

    test('Backspace on an empty toggle converts it to a paragraph', () {
      final s = stateOf([toggleListNode(text: '')]);
      select(s, [0], 0);
      expect(toggleListBackspaceCommandResult(s), KeyEventResult.handled);
      expect(s.getNodeAtPath([0])!.type, 'paragraph');
    });

    test('Backspace mid-title is not handled', () {
      final s = stateOf([toggleListNode(text: 'abc')]);
      select(s, [0], 2);
      expect(toggleListBackspaceCommandResult(s), KeyEventResult.ignored);
    });
  });

  group('code block Enter / Tab / Backspace', () {
    test('Enter inserts a newline within the block', () async {
      final s = stateOf([codeBlockNode('ab')]);
      select(s, [0], 1);
      expect(await enterCode(s), isTrue);
      expect(s.document.root.children.length, 1);
      expect(textAt(s, [0]), 'a\nb');
      expect(s.selection!.start.offset, 2);
    });

    test('Enter twice at the end exits the block', () async {
      final s = stateOf([codeBlockNode('ab')]);
      select(s, [0], 2);
      await enterCode(s);
      expect(textAt(s, [0]), 'ab\n');
      await enterCode(s);
      expect(textAt(s, [0]), 'ab');
      expect(s.document.root.children.length, 2);
      expect(s.getNodeAtPath([1])!.type, 'paragraph');
      expect(s.selection!.start.path, [1]);
    });

    test('Enter does not fire outside a code block', () async {
      final s = stateOf([para('x')]);
      select(s, [0], 1);
      expect(await enterCode(s), isFalse);
    });

    test('Tab inserts two spaces', () {
      final s = stateOf([codeBlockNode('ab')]);
      select(s, [0], 1);
      final r = customNotesCommandShortcuts()
          .firstWhere((e) => e.command == 'tab')
          .handler(s);
      expect(r, KeyEventResult.handled);
      expect(textAt(s, [0]), 'a  b');
      expect(s.selection!.start.offset, 3);
    });

    test('Tab outside a code block is ignored', () {
      final s = stateOf([para('x')]);
      select(s, [0], 0);
      final r = customNotesCommandShortcuts()
          .firstWhere((e) => e.command == 'tab')
          .handler(s);
      expect(r, KeyEventResult.ignored);
    });

    test('Backspace on an empty code block converts to a paragraph', () {
      final s = stateOf([codeBlockNode('')]);
      select(s, [0], 0);
      final r = codeBlockBackspaceCommand.handler(s);
      expect(r, KeyEventResult.handled);
      expect(s.getNodeAtPath([0])!.type, 'paragraph');
    });

    test('Backspace on a non-empty code block is ignored', () {
      final s = stateOf([codeBlockNode('x')]);
      select(s, [0], 0);
      expect(codeBlockBackspaceCommand.handler(s), KeyEventResult.ignored);
    });
  });

  group('indent / outdent under a toggle', () {
    test(
      'Tab nests a paragraph into the previous toggle, Shift+Tab undoes',
      () {
        customNotesBlockBuilders();
        final s = stateOf([toggleListNode(text: 'T'), para('p')]);
        select(s, [1], 0);
        indentCommand.handler(s);
        expect(s.document.root.children.length, 1);
        expect(s.getNodeAtPath([0, 0])!.delta!.toPlainText(), 'p');
        select(s, [0, 0], 0);
        outdentCommand.handler(s);
        expect(s.document.root.children.length, 2);
        expect(s.getNodeAtPath([1])!.delta!.toPlainText(), 'p');
      },
    );

    test('Tab nests a toggle into the previous paragraph', () {
      customNotesBlockBuilders();
      final s = stateOf([para('p'), toggleListNode(text: 'T')]);
      select(s, [1], 0);
      indentCommand.handler(s);
      expect(s.getNodeAtPath([0, 0])!.type, toggleListBlockType);
    });
  });

  group('rendering', () {
    testWidgets('collapsing hides children, expanding shows them', (
      tester,
    ) async {
      final s = stateOf([
        toggleListNode(text: 'Toggle', children: [para('c1'), para('c2')]),
      ]);
      await _editorApp(tester, s);
      expect(find.byType(ToggleListBlockComponentWidget), findsOneWidget);
      expect(find.byType(ParagraphBlockComponentWidget), findsNWidgets(2));
      expect(find.byIcon(Icons.expand_more), findsOneWidget);

      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pump(const Duration(milliseconds: 50));
      expect(s.getNodeAtPath([0])!.attributes['collapsed'], true);
      expect(find.byType(ParagraphBlockComponentWidget), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      // children remain in the document and its JSON
      expect(s.getNodeAtPath([0])!.children.length, 2);
      expect(jsonEncode(s.document.toJson()), contains('c2'));

      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pump(const Duration(milliseconds: 50));
      expect(s.getNodeAtPath([0])!.attributes['collapsed'], false);
      expect(find.byType(ParagraphBlockComponentWidget), findsNWidgets(2));
    });

    for (final theme in [ThemeData.light(), ThemeData.dark()]) {
      testWidgets('both blocks render in ${theme.brightness.name} theme', (
        tester,
      ) async {
        final s = stateOf([
          para('intro'),
          toggleListNode(
            text: 'Toggle',
            children: [
              para('child'),
              toggleListNode(
                text: 'nested',
                collapsed: true,
                children: [para('hidden')],
              ),
            ],
          ),
          codeBlockNode('line1\nline2 привіт'),
          codeBlockNode(''),
        ]);
        await _editorApp(tester, s, theme: theme);
        expect(tester.takeException(), isNull);
        expect(find.byType(ToggleListBlockComponentWidget), findsNWidgets(2));
        expect(find.byType(CodeBlockComponentWidget), findsNWidgets(2));
      });
    }
  });
}

KeyEventResult toggleListBackspaceCommandResult(EditorState s) =>
    customNotesCommandShortcuts()
        .firstWhere((e) => e.key == 'toggle list backspace to paragraph')
        .handler(s);
