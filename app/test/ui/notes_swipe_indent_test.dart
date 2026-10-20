import 'dart:convert';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/ui/widgets/notes_blocks/swipe_indent.dart';
import 'package:livenow/ui/widgets/notes_editor.dart';

String jsonOf(List<Node> nodes) =>
    jsonEncode((Document.blank()..insert([0], nodes)).toJson());

/// A touch swipe on a line is Tab (right) / Shift+Tab (left).
void main() {
  group('swipeIndentDirection', () {
    test('right = indent, left = outdent, a short move = nothing', () {
      expect(swipeIndentDirection(kSwipeIndentDistance), SwipeIndent.indent);
      expect(swipeIndentDirection(120), SwipeIndent.indent);
      expect(swipeIndentDirection(-kSwipeIndentDistance), SwipeIndent.outdent);
      expect(swipeIndentDirection(-120), SwipeIndent.outdent);
      expect(swipeIndentDirection(kSwipeIndentDistance - 1), SwipeIndent.none);
      expect(swipeIndentDirection(-(kSwipeIndentDistance - 1)), SwipeIndent.none);
      expect(swipeIndentDirection(0), SwipeIndent.none);
    });

    test('it has to be mostly horizontal: a diagonal move is a scroll', () {
      expect(swipeIndentDirection(100, 40), SwipeIndent.indent);
      expect(swipeIndentDirection(-100, -40), SwipeIndent.outdent);
      expect(swipeIndentDirection(100, 60), SwipeIndent.none);
      expect(swipeIndentDirection(60, 60), SwipeIndent.none);
      expect(swipeIndentDirection(0, 120), SwipeIndent.none);
    });
  });

  group('in the editor', () {
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

    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 600));
    }

    Offset centerOf(NotesEditorState s, List<int> path) =>
        s.editorState.getNodeAtPath(path)!.rect.center;

    // A finger moves in small steps (one big jump would hand the arena to the
    // wider-slop pan recognizer under it).
    Future<void> swipe(WidgetTester tester, Offset from, Offset total) async {
      final g = await tester.startGesture(from);
      final steps = (total.distance / 8).ceil();
      for (var i = 0; i < steps; i++) {
        await g.moveBy(total / steps.toDouble());
        await tester.pump(const Duration(milliseconds: 8));
      }
      await g.up();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('a swipe right indents the line under the finger', (
      tester,
    ) async {
      final s = await pump(tester, [
        bulletedListNode(text: 'one'),
        bulletedListNode(text: 'two'),
      ]);
      await swipe(tester, centerOf(s, [1]), const Offset(90, 0));
      final doc = s.editorState.document;
      expect(doc.root.children, hasLength(1));
      expect(doc.nodeAtPath([0, 0])?.delta?.toPlainText(), 'two');
      await unmount(tester);
    });

    testWidgets('a swipe left outdents a nested line', (tester) async {
      final s = await pump(tester, [
        bulletedListNode(
          text: 'one',
          children: [bulletedListNode(text: 'two')],
        ),
      ]);
      expect(s.editorState.document.root.children, hasLength(1));
      await swipe(tester, centerOf(s, [0, 0]), const Offset(-90, 0));
      final doc = s.editorState.document;
      expect(doc.root.children, hasLength(2));
      expect(doc.nodeAtPath([1])?.delta?.toPlainText(), 'two');
      await unmount(tester);
    });

    testWidgets('a short swipe or a vertical drag changes nothing', (
      tester,
    ) async {
      final s = await pump(tester, [
        bulletedListNode(text: 'one'),
        bulletedListNode(text: 'two'),
      ]);
      await swipe(tester, centerOf(s, [1]), const Offset(20, 0));
      await swipe(tester, centerOf(s, [1]), const Offset(0, -60));
      expect(s.editorState.document.root.children, hasLength(2));
      await unmount(tester);
    });

    testWidgets('a mouse drag never indents (it selects text)', (tester) async {
      final s = await pump(tester, [
        bulletedListNode(text: 'one'),
        bulletedListNode(text: 'two'),
      ]);
      final g = await tester.startGesture(
        centerOf(s, [1]),
        kind: PointerDeviceKind.mouse,
      );
      await g.moveBy(const Offset(90, 0));
      await g.up();
      await tester.pump(const Duration(milliseconds: 100));
      expect(s.editorState.document.root.children, hasLength(2));
      await unmount(tester);
    });
  });
}
