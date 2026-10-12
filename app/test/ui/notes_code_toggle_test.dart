import 'dart:convert';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/widgets/action_editor.dart';
import 'package:livenow/ui/widgets/notes_blocks/notes_blocks.dart';
import 'package:livenow/ui/widgets/notes_editor.dart';

/// Editing code blocks that live inside toggle rows (and the other way round),
/// with a mouse: placing the cursor, double-click word selection, the chevron,
/// Enter / Backspace / Tab. Everything is asserted on the editor's document and
/// selection (the editor draws its own text).
final enterInCode = customNotesCharacterShortcuts().firstWhere(
  (e) => e.key == 'insert new line in code block',
);

void main() {
  String jsonOf(List<Node> nodes) =>
      jsonEncode((Document.blank()..insert([0], nodes)).toJson());

  Node toggleWithCode({
    String title = 'Group title',
    String code = 'alpha beta',
    bool collapsed = false,
  }) => toggleListNode(
    text: title,
    collapsed: collapsed,
    children: [
      codeBlockNode(code),
      paragraphNode(text: 'after code'),
    ],
  );

  late NotesEditorState state;
  late List<String?> emitted;
  late int saves;

  Future<void> pumpNotes(WidgetTester tester, List<Node> nodes) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    emitted = [];
    saves = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: NotesEditor(
              initialJson: jsonOf(nodes),
              onChanged: emitted.add,
              onSave: () => saves++,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    state = tester.state<NotesEditorState>(find.byType(NotesEditor));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// Screen point of character [offset] in the node at [path] (via the
  /// editor's own selectable), nudged into the glyph.
  Offset pointAt(WidgetTester tester, List<int> path, int offset) {
    final node = state.editorState.getNodeAtPath(path)!;
    final selectable = node.selectable!;
    final rect = selectable.getCursorRectInPosition(
      Position(path: path, offset: offset),
    )!;
    final global = selectable.localToGlobal(rect.center);
    return global;
  }

  Future<void> click(WidgetTester tester, Offset at, {int times = 1}) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    for (var i = 0; i < times; i++) {
      await mouse.down(at);
      await tester.pump(const Duration(milliseconds: 20));
      await mouse.up();
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pump(const Duration(milliseconds: 400));
  }

  String text(List<int> path) =>
      state.editorState.getNodeAtPath(path)!.delta!.toPlainText();

  testWidgets('a click inside code text in a toggle puts the cursor there', (
    tester,
  ) async {
    await pumpNotes(tester, [toggleWithCode()]);
    await click(tester, pointAt(tester, [0, 0], 3));
    final sel = state.editorState.selection!;
    expect(sel.isCollapsed, isTrue);
    expect(sel.start.path, [0, 0]);
    expect(sel.start.offset, inInclusiveRange(2, 4));
    // The toggle stays open and nothing else changed.
    expect(
      state.editorState.document.nodeAtPath([
        0,
      ])!.attributes[toggleListCollapsedKey],
      isFalse,
    );
    expect(text([0, 0]), 'alpha beta');
    await unmount(tester);
  });

  testWidgets('double-click selects the word in the code, not the toggle', (
    tester,
  ) async {
    await pumpNotes(tester, [toggleWithCode()]);
    await click(tester, pointAt(tester, [0, 0], 8), times: 2);
    final sel = state.editorState.selection!.normalized;
    expect(sel.start.path, [0, 0]);
    expect(sel.end.path, [0, 0]);
    expect(
      state.editorState.getTextInSelection(sel).join(),
      'beta',
      reason: 'the double-clicked word is selected',
    );
    expect(
      state.editorState.document.nodeAtPath([
        0,
      ])!.attributes[toggleListCollapsedKey],
      isFalse,
      reason: 'a double click must not open/close the toggle',
    );
    await unmount(tester);
  });

  testWidgets('double-click on the toggle title selects its word only', (
    tester,
  ) async {
    await pumpNotes(tester, [toggleWithCode(title: 'Group title')]);
    await click(tester, pointAt(tester, [0], 8), times: 2);
    final sel = state.editorState.selection!.normalized;
    expect(sel.start.path, [0]);
    expect(state.editorState.getTextInSelection(sel).join(), 'title');
    expect(
      state.editorState.document.nodeAtPath([
        0,
      ])!.attributes[toggleListCollapsedKey],
      isFalse,
    );
    await unmount(tester);
  });

  testWidgets('typing in the code block keeps the toggle structure', (
    tester,
  ) async {
    await pumpNotes(tester, [toggleWithCode(code: 'ab')]);
    final ed = state.editorState;
    ed.selection = Selection.collapsed(Position(path: [0, 0], offset: 1));
    await ed.apply(
      ed.transaction..insertText(ed.getNodeAtPath([0, 0])!, 1, 'XY'),
    );
    await tester.pump();
    expect(text([0, 0]), 'aXYb');
    expect(ed.document.nodeAtPath([0])!.type, toggleListBlockType);
    expect(ed.document.nodeAtPath([0, 0])!.type, codeBlockType);
    expect(ed.document.nodeAtPath([0])!.children.length, 2);
    // The edit reaches the host as JSON with both blocks intact.
    await tester.pump(const Duration(milliseconds: 600));
    final json = emitted.last!;
    expect(json, contains('"toggle_list"'));
    expect(json, contains('aXYb'));
    await unmount(tester);
  });

  testWidgets('Enter in a code block inside a toggle adds a line, not a row', (
    tester,
  ) async {
    await pumpNotes(tester, [toggleWithCode(code: 'one')]);
    final ed = state.editorState;
    ed.selection = Selection.collapsed(Position(path: [0, 0], offset: 3));
    // Enter is a text-input shortcut (a key event alone does not carry the
    // character), so run it the way the editor does.
    expect(await enterInCode.handler(ed), isTrue);
    await tester.pump();
    expect(
      ed.document.nodeAtPath([0])!.children.length,
      2,
      reason: 'no new child block',
    );
    expect(text([0, 0]), 'one\n');
    expect(
      ed.selection,
      Selection.collapsed(Position(path: [0, 0], offset: 4)),
    );
    expect(saves, 0, reason: 'plain Enter never saves the dialog');

    // Enter again on the empty last line leaves the code: a paragraph appears
    // right after it, still inside the toggle.
    expect(await enterInCode.handler(ed), isTrue);
    await tester.pump();
    final toggle = ed.document.nodeAtPath([0])!;
    expect(toggle.children.map((n) => n.type), [
      codeBlockType,
      'paragraph',
      'paragraph',
    ]);
    expect(text([0, 0]), 'one');
    expect(ed.selection, Selection.collapsed(Position(path: [0, 1])));
    await unmount(tester);
  });

  testWidgets('Tab in code inside a toggle inserts two spaces, no indent', (
    tester,
  ) async {
    await pumpNotes(tester, [toggleWithCode(code: 'ab')]);
    final ed = state.editorState;
    ed.selection = Selection.collapsed(Position(path: [0, 0], offset: 1));
    final tab = customNotesCommandShortcuts().firstWhere(
      (e) => e.key == 'code block tab inserts spaces',
    );
    expect(tab.handler(ed), KeyEventResult.handled);
    await tester.pump();
    expect(text([0, 0]), 'a  b');
    expect(ed.document.nodeAtPath([0, 0])!.type, codeBlockType);
    expect(ed.document.nodeAtPath([0])!.children.length, 2);
    await unmount(tester);
  });

  testWidgets(
    'a click on the paragraph after the code edits it, not the code',
    (tester) async {
      await pumpNotes(tester, [toggleWithCode()]);
      await click(tester, pointAt(tester, [0, 1], 3));
      final sel = state.editorState.selection!;
      expect(sel.start.path, [0, 1]);
      await unmount(tester);
    },
  );

  testWidgets('Ctrl+Enter inside the code saves; on the toggle row it folds', (
    tester,
  ) async {
    await pumpNotes(tester, [toggleWithCode()]);
    final ed = state.editorState;
    ed.selection = Selection.collapsed(Position(path: [0, 0], offset: 2));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(saves, 1, reason: 'a code line is "any other line"');
    expect(
      ed.document.nodeAtPath([0])!.attributes[toggleListCollapsedKey],
      isFalse,
    );

    ed.selection = Selection.collapsed(Position(path: [0], offset: 2));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(
      ed.document.nodeAtPath([0])!.attributes[toggleListCollapsedKey],
      isTrue,
    );
    expect(saves, 1);
    await unmount(tester);
  });

  testWidgets('a collapsed toggle hides its code; the chevron opens it', (
    tester,
  ) async {
    await pumpNotes(tester, [toggleWithCode(collapsed: true)]);
    // The code block is in the document but not built.
    expect(state.editorState.getNodeAtPath([0, 0])!.selectable, isNull);
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      state.editorState.document.nodeAtPath([
        0,
      ])!.attributes[toggleListCollapsedKey],
      isFalse,
    );
    expect(state.editorState.getNodeAtPath([0, 0])!.selectable, isNotNull);
    expect(text([0, 0]), 'alpha beta');
    await unmount(tester);
  });

  testWidgets('selecting across the toggle title into the code and deleting '
      'keeps a valid document', (tester) async {
    await pumpNotes(tester, [toggleWithCode(title: 'Title', code: 'code')]);
    final ed = state.editorState;
    ed.selection = Selection(
      start: Position(path: [0], offset: 3),
      end: Position(path: [0, 0], offset: 2),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump(const Duration(milliseconds: 100));
    // Whatever the merge rule, the result is a readable document: no node
    // lost its delta and the text that was not selected is still there.
    final all = <String>[];
    void walk(Node n) {
      if (n.delta != null) all.add(n.delta!.toPlainText());
      n.children.forEach(walk);
    }

    ed.document.root.children.forEach(walk);
    expect(all.join('|'), contains('Tit'));
    expect(all.join('|'), contains('de'));
    expect(all.join('|'), contains('after code'));
    await unmount(tester);
  });

  testWidgets('Backspace at the start of an empty code line leaves the block '
      'in place inside the toggle', (tester) async {
    await pumpNotes(tester, [toggleWithCode(code: '')]);
    final ed = state.editorState;
    ed.selection = Selection.collapsed(Position(path: [0, 0], offset: 0));
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump(const Duration(milliseconds: 100));
    // The empty code block turns into a paragraph, still a child of the toggle.
    final toggle = ed.document.nodeAtPath([0])!;
    expect(toggle.type, toggleListBlockType);
    expect(toggle.children.length, 2);
    expect(toggle.children.first.type, anyOf(codeBlockType, 'paragraph'));
    await unmount(tester);
  });

  testWidgets('inside the action dialog a double-click in toggled code selects '
      'a word and neither closes, resizes nor rebuilds the editor', (
    tester,
  ) async {
    initPostponeTimeZoneData();
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final notes = jsonOf([toggleWithCode()]);
    final existing = (await tester.runAsync(() async {
      final id = await ActionService(db)
          .createAction(name: 'Task', notes: notes);
      return (db.select(
        db.actionsTable,
      )..where((t) => t.id.equals(id))).getSingle();
    }))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  ActionEditorDialog.show(context, existing: existing),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();

    // The notes section opened by itself (the action has text).
    state = tester.state<NotesEditorState>(find.byType(NotesEditor));
    final built = NotesEditorState.createdCount;
    final dialogSize = tester.getSize(find.byType(AlertDialog));

    await click(tester, pointAt(tester, [0, 0], 8), times: 2);
    final sel = state.editorState.selection!.normalized;
    expect(state.editorState.getTextInSelection(sel).join(), 'beta');
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      tester.getSize(find.byType(AlertDialog)),
      dialogSize,
      reason: 'the dialog did not resize or swap to another mode',
    );
    expect(
      NotesEditorState.createdCount,
      built,
      reason: 'the editor was not rebuilt',
    );
    expect(find.text('Expand'), findsOneWidget, reason: 'still not expanded');

    // Typing replaces the selected word and the edit is the dialog's notes.
    final ed = state.editorState;
    await ed.apply(
      ed.transaction
        ..deleteText(
          ed.getNodeAtPath([0, 0])!,
          sel.startIndex,
          sel.endIndex - sel.startIndex,
        )
        ..insertText(ed.getNodeAtPath([0, 0])!, sel.startIndex, 'gamma'),
    );
    await tester.pump();
    expect(text([0, 0]), 'alpha gamma');
    resetStackedDialogsForTest();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
  });
}
