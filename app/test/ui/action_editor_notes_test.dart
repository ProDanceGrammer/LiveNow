import 'package:appflowy_editor/appflowy_editor.dart' show TextTransaction;
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/widgets/action_editor.dart';
import 'package:livenow/ui/widgets/notes_editor.dart';

const _json1 =
    '{"document":{"type":"page","children":[{"type":"paragraph","data":{"delta":[{"insert":"Hi"}]}}]}}';
const _json2 =
    '{"document":{"type":"page","children":[{"type":"paragraph","data":{"delta":[{"insert":"Bye"}]}}]}}';

void main() {
  late AppDatabase db;

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
  }

  void setup(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
  }

  Future<ActionRow> seed(WidgetTester tester, {String? notes}) async {
    return (await tester.runAsync(() async {
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      final id = await container
          .read(actionServiceProvider)
          .createAction(name: 'Task', notes: notes);
      return (db.select(
        db.actionsTable,
      )..where((t) => t.id.equals(id))).getSingle();
    }))!;
  }

  Future<void> open(
    WidgetTester tester, {
    ActionRow? existing,
    DateTime? start,
    DateTime? end,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => ActionEditorDialog.show(
                context,
                existing: existing,
                initialStart: start,
                initialEnd: end,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
  }

  Future<ActionRow> reload(WidgetTester tester) async =>
      (await tester.runAsync(() => db.select(db.actionsTable).getSingle()))!;

  Future<void> waitForWrite(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text('Save'));
    await waitForWrite(tester);
  }

  Future<void> teardown(WidgetTester tester) async {
    await settle(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  NotesEditor editor(WidgetTester tester) =>
      tester.widget<NotesEditor>(find.byType(NotesEditor));

  Future<void> expandNotes(WidgetTester tester) async {
    await tester.tap(find.text('Notes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  ExpansionTile notesTile(WidgetTester tester) => tester.widget<ExpansionTile>(
    find.widgetWithText(ExpansionTile, 'Notes'),
  );

  NotesEditorState notesState(WidgetTester tester) =>
      tester.state<NotesEditorState>(find.byType(NotesEditor));

  String notesText(WidgetTester tester) => notesState(tester)
      .editorState
      .document
      .root
      .children
      .map((n) => n.delta?.toPlainText() ?? '')
      .join('\n');

  Future<void> typeIntoNotes(WidgetTester tester, String text) async {
    final s = notesState(tester).editorState;
    final node = s.document.root.children.first;
    await s.apply(s.transaction..insertText(node, 0, text));
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('editing passes the stored notes to the editor', (tester) async {
    setup(tester);
    final row = await seed(tester, notes: _json1);
    await open(tester, existing: row);
    expect(editor(tester).initialJson, _json1);
    expect(find.text('Notes'), findsOneWidget);
    await teardown(tester);
  });

  testWidgets('saving untouched keeps notes, even when only name changes', (
    tester,
  ) async {
    setup(tester);
    final row = await seed(tester, notes: _json1);
    await open(tester, existing: row);
    await tester.enterText(find.byType(TextFormField).first, 'Renamed');
    await save(tester);
    final after = await reload(tester);
    expect(after.name, 'Renamed');
    expect(after.notes, _json1);
    await teardown(tester);
  });

  testWidgets('onChanged then Save persists the JSON', (tester) async {
    setup(tester);
    final row = await seed(tester, notes: _json1);
    await open(tester, existing: row);
    editor(tester).onChanged(_json2);
    await save(tester);
    expect((await reload(tester)).notes, _json2);
    await teardown(tester);
  });

  testWidgets('onChanged(null) then Save clears the notes', (tester) async {
    setup(tester);
    final row = await seed(tester, notes: _json1);
    await open(tester, existing: row);
    editor(tester).onChanged(null);
    await save(tester);
    expect((await reload(tester)).notes, isNull);
    await teardown(tester);
  });

  testWidgets('a new action is created with the notes', (tester) async {
    setup(tester);
    await open(tester);
    await expandNotes(tester);
    expect(editor(tester).initialJson, isNull);
    await tester.enterText(find.byType(TextFormField).first, 'Fresh');
    editor(tester).onChanged(_json1);
    await save(tester);
    final row = await reload(tester);
    expect(row.name, 'Fresh');
    expect(row.notes, _json1);
    await teardown(tester);
  });

  testWidgets('expand toggle hides other sections and keeps editor state', (
    tester,
  ) async {
    setup(tester);
    final row = await seed(tester, notes: _json1);
    await open(tester, existing: row);
    expect(find.text('Manual parameters'), findsOneWidget);
    final stateBefore = tester.state(find.byType(NotesEditor));

    editor(tester).onToggleExpand!();
    await tester.pump(const Duration(milliseconds: 400));
    expect(editor(tester).expanded, isTrue);
    expect(find.widgetWithText(TextFormField, 'Task'), findsOneWidget);
    expect(find.text('Manual parameters'), findsNothing);
    expect(find.text('Connected actions'), findsNothing);
    expect(tester.state(find.byType(NotesEditor)), same(stateBefore));

    editor(tester).onToggleExpand!();
    await tester.pump(const Duration(milliseconds: 400));
    expect(editor(tester).expanded, isFalse);
    expect(find.text('Manual parameters'), findsOneWidget);
    expect(tester.state(find.byType(NotesEditor)), same(stateBefore));
    await teardown(tester);
  });

  testWidgets('Enter in Name saves the action together with notes', (
    tester,
  ) async {
    setup(tester);
    final row = await seed(tester, notes: _json1);
    await open(tester, existing: row);
    editor(tester).onChanged(_json2);
    await tester.enterText(find.byType(TextFormField).first, 'Entered');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await waitForWrite(tester);
    final after = await reload(tester);
    expect(after.name, 'Entered');
    expect(after.notes, _json2);
    expect(find.byType(AlertDialog), findsNothing);
    await teardown(tester);
  });

  testWidgets('calendar-drag path still shows the Notes section', (
    tester,
  ) async {
    setup(tester);
    final start = DateTime.utc(2026, 1, 5, 9);
    await open(tester, start: start, end: start.add(const Duration(hours: 1)));
    expect(find.byType(NotesEditor), findsNothing);
    expect(find.text('Notes'), findsOneWidget);
    await expandNotes(tester);
    expect(find.byType(NotesEditor), findsOneWidget);
    await teardown(tester);
  });

  testWidgets('new action: Notes collapsed and no editor built', (
    tester,
  ) async {
    setup(tester);
    final before = NotesEditorState.createdCount;
    await open(tester);
    expect(notesTile(tester).initiallyExpanded, isFalse);
    expect(find.byType(NotesEditor), findsNothing);
    expect(find.text('Reset checkboxes'), findsNothing);
    expect(NotesEditorState.createdCount, before);
    await teardown(tester);
  });

  testWidgets('existing action with notes opens expanded with the content', (
    tester,
  ) async {
    setup(tester);
    final row = await seed(tester, notes: _json1);
    await open(tester, existing: row);
    expect(notesTile(tester).initiallyExpanded, isTrue);
    expect(find.byType(NotesEditor), findsOneWidget);
    expect(
      tester
          .state<NotesEditorState>(find.byType(NotesEditor))
          .editorState
          .document
          .root
          .children
          .first
          .delta
          ?.toPlainText(),
      'Hi',
    );
    expect(find.text('Reset checkboxes'), findsOneWidget);
    await teardown(tester);
  });

  testWidgets('existing action with null or empty notes opens collapsed', (
    tester,
  ) async {
    setup(tester);
    const emptyDoc =
        '{"document":{"type":"page","children":[{"type":"paragraph","data":{"delta":[]}}]}}';
    final row = await seed(tester, notes: emptyDoc);
    await open(tester, existing: row);
    expect(notesTile(tester).initiallyExpanded, isFalse);
    expect(find.byType(NotesEditor), findsNothing);
    await teardown(tester);
  });

  testWidgets('expand, type, collapse, expand again keeps text; Save stores it', (
    tester,
  ) async {
    setup(tester);
    await open(tester);
    await tester.enterText(find.byType(TextFormField).first, 'Typed');
    await expandNotes(tester);
    await typeIntoNotes(tester, 'hello');
    await tester.tap(find.text('Notes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(NotesEditor), findsNothing);
    await tester.tap(find.text('Notes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(NotesEditor), findsOneWidget);
    expect(notesText(tester), 'hello');
    await save(tester);
    final row = await reload(tester);
    expect(row.notes, isNotNull);
    expect(row.notes, contains('hello'));
    await teardown(tester);
  });

  testWidgets('clearing all text then Save stores null', (tester) async {
    setup(tester);
    final row = await seed(tester, notes: _json1);
    await open(tester, existing: row);
    final state = tester.state<NotesEditorState>(find.byType(NotesEditor));
    final node = state.editorState.document.root.children.first;
    await state.editorState.apply(
      state.editorState.transaction..deleteText(node, 0, 2),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await save(tester);
    expect((await reload(tester)).notes, isNull);
    await teardown(tester);
  });

  testWidgets('never opening Notes leaves them null; opened notes survive Save', (
    tester,
  ) async {
    setup(tester);
    await open(tester);
    await tester.enterText(find.byType(TextFormField).first, 'Plain');
    await save(tester);
    expect((await reload(tester)).notes, isNull);
    await teardown(tester);

    final row = await tester.runAsync(
      () => db.select(db.actionsTable).getSingle(),
    );
    await tester.runAsync(
      () => (db.update(db.actionsTable)).write(
        ActionsTableCompanion(notes: Value(_json1)),
      ),
    );
    final withNotes = await reload(tester);
    expect(withNotes.id, row!.id);
    await open(tester, existing: withNotes);
    await tester.enterText(find.byType(TextFormField).first, 'Renamed');
    await save(tester);
    expect((await reload(tester)).notes, _json1);
    await teardown(tester);
  });

  testWidgets('Expand mode needs the section open and survives collapse', (
    tester,
  ) async {
    setup(tester);
    final row = await seed(tester, notes: _json1);
    await open(tester, existing: row);
    editor(tester).onToggleExpand!();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Manual parameters'), findsNothing);
    await tester.tap(find.text('Notes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(NotesEditor), findsNothing);
    expect(find.text('Manual parameters'), findsOneWidget);
    await teardown(tester);
  });
}
