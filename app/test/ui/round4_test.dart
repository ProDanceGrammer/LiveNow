import 'dart:convert';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/dependency_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/root_navigator.dart';
import 'package:livenow/ui/widgets/action_editor.dart';
import 'package:livenow/ui/widgets/notes_blocks/notes_blocks.dart';
import 'package:livenow/ui/widgets/notes_editor.dart';

/// Round 4 (after ios-5): Ctrl+Enter in Notes, Markdown copy, Ctrl+S, notes
/// autosave, "Set after previous / before next", the mouse Back button.
void main() {
  setUpAll(initPostponeTimeZoneData);

  String jsonOf(List<Node> nodes) =>
      jsonEncode((Document.blank()..insert([0], nodes)).toJson());

  Future<NotesEditorState> pumpNotes(
    WidgetTester tester,
    String json, {
    VoidCallback? onSave,
  }) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: NotesEditor(
              initialJson: json,
              onChanged: (_) {},
              onSave: onSave,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return tester.state<NotesEditorState>(find.byType(NotesEditor));
  }

  Future<void> ctrlKey(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  group('Notes', () {
    testWidgets('Ctrl+Enter ticks a checkbox, flips a toggle, else saves', (
      tester,
    ) async {
      var saves = 0;
      final state = await pumpNotes(
        tester,
        jsonOf([
          todoListNode(checked: false, text: 'Task'),
          toggleListNode(text: 'Group', collapsed: false),
          paragraphNode(text: 'Plain'),
        ]),
        onSave: () => saves++,
      );
      final ed = state.editorState;

      ed.selection = Selection.collapsed(Position(path: [0], offset: 1));
      await ctrlKey(tester, LogicalKeyboardKey.enter);
      expect(ed.document.nodeAtPath([0])!.attributes['checked'], isTrue);
      await ctrlKey(tester, LogicalKeyboardKey.enter);
      expect(ed.document.nodeAtPath([0])!.attributes['checked'], isFalse);
      expect(saves, 0);

      ed.selection = Selection.collapsed(Position(path: [1], offset: 1));
      await ctrlKey(tester, LogicalKeyboardKey.enter);
      expect(
        ed.document.nodeAtPath([1])!.attributes[toggleListCollapsedKey],
        isTrue,
      );
      expect(saves, 0);

      ed.selection = Selection.collapsed(Position(path: [2], offset: 1));
      await ctrlKey(tester, LogicalKeyboardKey.enter);
      expect(saves, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('Ctrl+C puts Markdown on the clipboard', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
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
      final state = await pumpNotes(
        tester,
        jsonOf([
          todoListNode(checked: true, text: 'Done'),
          todoListNode(checked: false, text: 'Open'),
        ]),
      );
      final ed = state.editorState;
      ed.selection = Selection(
        start: Position(path: [0], offset: 0),
        end: Position(path: [1], offset: 4),
      );
      await ctrlKey(tester, LogicalKeyboardKey.keyC);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      expect(copied, contains('- [x] Done'));
      expect(copied, contains('- [ ] Open'));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
    });
  });

  group('action editor', () {
    late AppDatabase db;

    Future<String> seed(WidgetTester tester) async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      return (await tester.runAsync(
        () => ActionService(db).createAction(
          name: 'Task',
          startAt: DateTime.utc(2026, 10, 10, 7),
          endAt: DateTime.utc(2026, 10, 10, 8),
        ),
      ))!;
    }

    Future<ActionRow> row(WidgetTester tester, String id) async =>
        (await tester.runAsync(
          () => (db.select(
            db.actionsTable,
          )..where((t) => t.id.equals(id))).getSingle(),
        ))!;

    Future<void> openEditor(WidgetTester tester, String id) async {
      tester.view.physicalSize = const Size(1400, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final existing = await row(tester, id);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            navigatorKey: rootNavigatorKey,
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
    }

    Future<void> afterWrite(WidgetTester tester) async {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> close(WidgetTester tester) async {
      resetStackedDialogsForTest();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));
    }

    testWidgets('Ctrl+S saves, keeps the dialog and shows Saved', (
      tester,
    ) async {
      final id = await seed(tester);
      await openEditor(tester, id);
      await tester.enterText(find.byType(TextFormField).first, 'Renamed');
      await ctrlKey(tester, LogicalKeyboardKey.keyS);
      await afterWrite(tester);

      expect((await row(tester, id)).name, 'Renamed');
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);
      expect(find.text('Undo'), findsNothing);
      await close(tester);
    });

    testWidgets('notes autosave 5 s after the last change, silently', (
      tester,
    ) async {
      final id = await seed(tester);
      await openEditor(tester, id);
      await tester.tap(find.text('Notes'));
      await tester.pump(const Duration(milliseconds: 400));
      final state = tester.state<NotesEditorState>(find.byType(NotesEditor));
      final tx = state.editorState.transaction
        ..insertText(
          state.editorState.getNodeAtPath([0])!,
          0,
          'remember',
        );
      await state.editorState.apply(tx);
      // The editor hands its text over after 400 ms; the save follows 5 s later.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 4));
      expect((await row(tester, id)).notes, isNull);
      await tester.pump(const Duration(seconds: 2));
      await afterWrite(tester);
      final saved = await row(tester, id);
      expect(saved.notes, contains('remember'));
      expect(saved.notesText, contains('remember'));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Saved'), findsNothing);
      await close(tester);
    });

    testWidgets('Set after previous / before next fill the form only', (
      tester,
    ) async {
      final id = await seed(tester);
      final deps = DependencyService(db);
      await tester.runAsync(() async {
        final svc = ActionService(db);
        final p1 = await svc.createAction(
          name: 'P1',
          startAt: DateTime.utc(2026, 10, 10, 9),
          endAt: DateTime.utc(2026, 10, 10, 10),
        );
        final p2 = await svc.createAction(
          name: 'P2',
          startAt: DateTime.utc(2026, 10, 10, 6),
          endAt: DateTime.utc(2026, 10, 10, 11),
        );
        final n1 = await svc.createAction(
          name: 'N1',
          startAt: DateTime.utc(2026, 10, 10, 15),
          endAt: DateTime.utc(2026, 10, 10, 16),
        );
        await deps.addDependency(predecessorId: p1, successorId: id);
        await deps.addDependency(predecessorId: p2, successorId: id);
        await deps.addDependency(predecessorId: id, successorId: n1);
      });
      await openEditor(tester, id);
      await tester.pump(const Duration(milliseconds: 300));

      // After the latest previous end (11:00Z): 11:00-12:00Z = 14:00-15:00.
      await tester.tap(find.byTooltip('Set after previous actions'));
      await tester.pump();
      expect(find.textContaining('14:00'), findsWidgets);
      // The database is untouched until Save.
      expect((await row(tester, id)).startAt, contains('07:00'));

      // Before the first next start (15:00Z): 14:00-15:00Z = 17:00-18:00.
      await tester.tap(find.byTooltip('Set before next action'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await afterWrite(tester);
      final saved = await row(tester, id);
      expect(DateTime.parse(saved.startAt!), DateTime.utc(2026, 10, 10, 14));
      expect(DateTime.parse(saved.endAt!), DateTime.utc(2026, 10, 10, 15));
      await close(tester);
    });

    testWidgets('mouse Back closes the editor; Undo reopens it with the edits', (
      tester,
    ) async {
      final id = await seed(tester);
      await openEditor(tester, id);
      await tester.enterText(find.byType(TextFormField).first, 'Half typed');
      await tester.pump();

      final mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kBackMouseButton,
      );
      await mouse.down(const Offset(10, 10));
      await mouse.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AlertDialog), findsNothing);
      // Nothing was saved.
      expect((await row(tester, id)).name, 'Task');
      expect(find.textContaining('Closed'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Half typed'), findsOneWidget);
      await close(tester);
    });

    testWidgets('Back on an untouched editor closes it without an Undo', (
      tester,
    ) async {
      final id = await seed(tester);
      await openEditor(tester, id);
      final mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kBackMouseButton,
      );
      await mouse.down(const Offset(10, 10));
      await mouse.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('Closed'), findsNothing);
      await close(tester);
    });
  });
}
