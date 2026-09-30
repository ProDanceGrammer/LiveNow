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
    expect(find.byType(NotesEditor), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    await teardown(tester);
  });
}
