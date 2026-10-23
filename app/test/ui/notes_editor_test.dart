import 'dart:convert';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/ui/widgets/notes_document.dart';
import 'package:livenow/ui/widgets/notes_blocks/notes_blocks.dart';
import 'package:livenow/ui/widgets/notes_editor.dart';

String dump(Node n) {
  final text = n.delta?.toPlainText();
  final checked = n.attributes['checked'] == true ? '!' : '';
  final kids = n.children.isEmpty ? '' : '[${n.children.map(dump).join(', ')}]';
  return '${n.type}$checked:${text ?? ''}$kids';
}

String dumpDoc(Document d) => d.root.children.map(dump).join(' | ');

String jsonOf(List<Node> nodes) =>
    jsonEncode((Document.blank()..insert([0], nodes)).toJson());

void main() {
  Future<NotesEditorState> pumpEditor(
    WidgetTester tester, {
    String? json,
    ValueChanged<String?>? onChanged,
    VoidCallback? onToggle,
    bool expanded = false,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Scaffold(
          body: SingleChildScrollView(
            child: NotesEditor(
              key: const ValueKey('ed'),
              initialJson: json,
              onChanged: onChanged ?? (_) {},
              onToggleExpand: onToggle,
              expanded: expanded,
            ),
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

  void mockClipboard(WidgetTester tester, String? text) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.getData' && text != null
          ? <String, dynamic>{'text': text}
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
  }

  testWidgets('builds from saved JSON and shows the toolbar buttons', (
    tester,
  ) async {
    final json = jsonOf([
      todoListNode(checked: true, text: 'Задача'),
      paragraphNode(text: 'Текст'),
    ]);
    final state = await pumpEditor(tester, json: json, onToggle: () {});
    expect(find.byType(AppFlowyEditor), findsOneWidget);
    // Windows: Paste as Markdown is the Ctrl+Shift+V shortcut, no button.
    expect(find.text('Paste as Markdown'), findsNothing);
    expect(find.text('Expand'), findsOneWidget);
    expect(
      dumpDoc(state.editorState.document),
      'todo_list!:Задача | paragraph:Текст',
    );
    // Nothing is focused automatically.
    expect(state.editorState.selection, isNull);
    await unmount(tester);
  });

  testWidgets('corrupt JSON gives a blank editor; dark theme builds', (
    tester,
  ) async {
    final state = await pumpEditor(
      tester,
      json: '{oops',
      brightness: Brightness.dark,
    );
    expect(notesDocumentIsEmpty(state.editorState.document), isTrue);
    await unmount(tester);
  });

  testWidgets('Expand button hidden without callback; label follows flag', (
    tester,
  ) async {
    await pumpEditor(tester);
    expect(find.text('Expand'), findsNothing);
    expect(find.text('Collapse'), findsNothing);
    await unmount(tester);

    var calls = 0;
    await pumpEditor(tester, onToggle: () => calls++, expanded: true);
    expect(find.text('Collapse'), findsOneWidget);
    await tester.tap(find.text('Collapse'));
    expect(calls, 1);
    await unmount(tester);
  });

  testWidgets('an edit reaches onChanged debounced, as valid JSON', (
    tester,
  ) async {
    final calls = <String?>[];
    final state = await pumpEditor(tester, onChanged: calls.add);
    await tester.pump(const Duration(seconds: 1));
    expect(calls, isEmpty, reason: 'no emission for the initial load');

    final ed = state.editorState;
    final t = ed.transaction
      ..insertText(ed.document.root.children.first, 0, 'Привіт, світ');
    await ed.apply(t);
    await tester.pump(const Duration(milliseconds: 100));
    expect(calls, isEmpty, reason: 'still inside the debounce window');
    await tester.pump(const Duration(milliseconds: 500));
    expect(calls, hasLength(1));
    final restored = notesDocumentFromJson(calls.single);
    expect(dumpDoc(restored), 'paragraph:Привіт, світ');
    await unmount(tester);
  });

  testWidgets('pending change is flushed on dispose; emptying emits null', (
    tester,
  ) async {
    final calls = <String?>[];
    final state = await pumpEditor(
      tester,
      json: jsonOf([paragraphNode(text: 'x')]),
      onChanged: calls.add,
    );
    final ed = state.editorState;
    await ed.apply(
      ed.transaction..deleteText(ed.document.root.children.first, 0, 1),
    );
    await unmount(tester); // disposes before the 400 ms elapse
    expect(calls, [null]);
  });

  testWidgets('Paste as Markdown inserts the converted blocks', (tester) async {
    mockClipboard(tester, '- [ ]  Один\n    - [ ]  Два\n\n```\ncode\n```\n');
    final state = await pumpEditor(
      tester,
      json: jsonOf([paragraphNode(text: 'first'), paragraphNode(text: 'last')]),
    );
    final ed = state.editorState;
    ed.selection = Selection.collapsed(Position(path: [0], offset: 2));
    await state.pasteAsMarkdown();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      dumpDoc(ed.document),
      'paragraph:first | todo_list:Один[todo_list:Два] | code:code | paragraph:last',
    );
    expect(ed.selection, Selection.collapsed(Position(path: [2], offset: 4)));
    await unmount(tester);
  });

  testWidgets('Paste as Markdown with an empty clipboard does nothing', (
    tester,
  ) async {
    mockClipboard(tester, null);
    final state = await pumpEditor(
      tester,
      json: jsonOf([paragraphNode(text: 'a')]),
    );
    await state.pasteAsMarkdown();
    await tester.pump(const Duration(milliseconds: 600));
    expect(dumpDoc(state.editorState.document), 'paragraph:a');
    await unmount(tester);
  });

  group('typing shortcuts', () {
    final events = notesCharacterShortcuts();

    /// Types [char] after [text] (cursor at the end of a single paragraph) by
    /// running the matching shortcut handlers, like the keyboard service does.
    Future<EditorState> type(String text, String char) async {
      final state = EditorState(
        document: Document.blank()..insert([0], [paragraphNode(text: text)]),
      );
      state.selection = Selection.collapsed(
        Position(path: [0], offset: text.length),
      );
      for (final e in events.where((e) => e.character == char)) {
        if (await e.handler(state)) break;
      }
      return state;
    }

    test('[] -[] and checked variants make todos', () async {
      expect(dumpDoc((await type('[]', ' ')).document), 'todo_list:');
      expect(dumpDoc((await type('-[]', ' ')).document), 'todo_list:');
      expect(dumpDoc((await type('[x]', ' ')).document), 'todo_list!:');
    });

    test('- * + make bullets, 1. numbered, # heading', () async {
      for (final s in ['-', '*', '+']) {
        expect(
          dumpDoc((await type(s, ' ')).document),
          'bulleted_list:',
          reason: s,
        );
      }
      expect(dumpDoc((await type('1.', ' ')).document), 'numbered_list:');
      final h = await type('#', ' ');
      expect(h.document.root.children.first.type, 'heading');
      expect(h.document.root.children.first.attributes['level'], 1);
    });

    test('quote, divider, arrow and slash do not convert', () async {
      final quote = await type('', '"');
      expect(dumpDoc(quote.document), 'paragraph:');
      for (final s in ['--', '**', '__']) {
        final d = await type(s, s[0]);
        expect(d.document.root.children.first.type, 'paragraph', reason: s);
      }
      expect(
        (await type('=', '>')).document.root.children.first.type,
        'paragraph',
      );
      expect(
        (await type('', '/')).document.root.children.first.type,
        'paragraph',
      );
      expect(
        events.where((e) => e.key.contains('divider') || e.character == '"'),
        isEmpty,
      );
    });

    test('Cyrillic text typed into a todo stays intact', () async {
      final s = await type('[]', ' ');
      final todo = s.document.root.children.first;
      await s.apply(s.transaction..insertText(todo, 0, 'Зателефонувати мамі'));
      expect(dumpDoc(s.document), 'todo_list:Зателефонувати мамі');
    });
  });

  testWidgets('Ctrl+Z inside the editor is consumed by the editor', (
    tester,
  ) async {
    var outer = 0;
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: CallbackShortcuts(
          bindings: {
            LogicalKeySet(
              LogicalKeyboardKey.control,
              LogicalKeyboardKey.keyZ,
            ): () =>
                outer++,
          },
          child: Scaffold(
            body: NotesEditor(
              initialJson: jsonOf([paragraphNode(text: 'abc')]),
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    final state = tester.state<NotesEditorState>(find.byType(NotesEditor));
    final ed = state.editorState;
    ed.selection = Selection.collapsed(Position(path: [0], offset: 3));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await ed.apply(
      ed.transaction..insertText(ed.document.root.children.first, 3, 'd'),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump();
    expect(outer, 0, reason: 'the global undo must not fire');
    expect(dumpDoc(ed.document), 'paragraph:abc');
    await unmount(tester);
  });

  group('leaving and returning to the window', () {
    final windows = TargetPlatformVariant.only(TargetPlatform.windows);
    Future<void> leaveAndReturn(WidgetTester tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    Future<NotesEditorState> focused(WidgetTester tester, Selection sel) async {
      // Flutter suspends the focus on `inactive` only on desktop and web, and
      // only once the focus manager listens to the lifecycle.
      FocusManager.instance.listenToApplicationLifecycleChangesIfSupported();
      final ed = await pumpEditor(
        tester,
        json: jsonOf([paragraphNode(text: 'Hello world')]),
      );
      // A real click gives the editor's focus node the primary focus.
      await tester.tap(find.byType(AppFlowyEditor));
      await tester.pump();
      ed.editorState.updateSelectionWithReason(
        sel,
        reason: SelectionUpdateReason.uiEvent,
      );
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'keyboard service',
      );
      return ed;
    }

    testWidgets('the caret comes back where it was', (tester) async {
      final sel = Selection.collapsed(Position(path: [0], offset: 5));
      final ed = await focused(tester, sel);
      expect(ed.editorState.selection, sel);

      await leaveAndReturn(tester);
      expect(ed.editorState.selection, sel);
      await unmount(tester);
    }, variant: windows);

    testWidgets('a range selection comes back too', (tester) async {
      final sel = Selection(
        start: Position(path: [0], offset: 2),
        end: Position(path: [0], offset: 8),
      );
      final ed = await focused(tester, sel);
      await leaveAndReturn(tester);
      expect(ed.editorState.selection, sel);
      await unmount(tester);
    }, variant: windows);

    testWidgets('typing after returning goes in at the remembered place', (
      tester,
    ) async {
      final ed = await focused(
        tester,
        Selection.collapsed(Position(path: [0], offset: 5)),
      );
      await leaveAndReturn(tester);
      await ed.editorState.insertTextAtCurrentSelection('!');
      await tester.pump();
      expect(dumpDoc(ed.editorState.document), 'paragraph:Hello! world');
      await unmount(tester);
    }, variant: windows);

    testWidgets('a deliberate click-away is not undone by leaving', (
      tester,
    ) async {
      final ed = await focused(
        tester,
        Selection.collapsed(Position(path: [0], offset: 5)),
      );
      // The user clicks away / presses Esc while the window is active.
      ed.editorState.selection = null;
      await tester.pump();
      await leaveAndReturn(tester);
      expect(ed.editorState.selection, isNull);
      await unmount(tester);
    }, variant: windows);
  });

  group('double click in a toggle', () {
    Future<void> doubleTapAt(WidgetTester tester, Offset at) async {
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 100));
    }

    for (final collapsed in [false, true]) {
      testWidgets(
        'selects the word in the title of a ${collapsed ? 'closed' : 'open'} toggle',
        (tester) async {
          final ed = await pumpEditor(
            tester,
            json: jsonOf([
              toggleListNode(
                text: 'Hello world',
                collapsed: collapsed,
                children: [paragraphNode(text: 'inside the toggle')],
              ),
            ]),
          );
          final box = tester.getRect(find.byType(AppFlowyEditor));
          // The first word, right of the chevron.
          await doubleTapAt(tester, Offset(box.left + 52, box.top + 14));
          final sel = ed.editorState.selection;
          expect(sel, isNotNull, reason: 'the word is selected');
          expect(sel!.isCollapsed, isFalse);
          expect(
            ed.editorState.getTextInSelection(sel.normalized).join(),
            'Hello',
          );
          await unmount(tester);
        },
      );
    }
  });
}
