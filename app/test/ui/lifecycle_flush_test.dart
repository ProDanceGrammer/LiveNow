import 'package:appflowy_editor/appflowy_editor.dart' show TextTransaction;
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

/// Going to the background (`inactive` / `paused`): the Notes typed in the last
/// moments must not wait in the 400 ms debounce, nor the editor's 5 s quiet
/// period, because the OS may end the app there.

void lifecycle(WidgetTester tester, List<AppLifecycleState> states) {
  for (final s in states) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
}

/// resumed -> inactive -> hidden -> paused, as an OS backgrounds the app.
void background(WidgetTester tester) => lifecycle(tester, [
  AppLifecycleState.inactive,
  AppLifecycleState.hidden,
  AppLifecycleState.paused,
]);

/// paused -> hidden -> inactive -> resumed (the only legal way back).
void resume(WidgetTester tester) => lifecycle(tester, [
  AppLifecycleState.hidden,
  AppLifecycleState.inactive,
  AppLifecycleState.resumed,
]);

void main() {
  late AppDatabase db;

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
  }

  testWidgets('NotesEditor hands over a pending change when the app is paused', (
    tester,
  ) async {
    final emitted = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: NotesEditor(initialJson: _json1, onChanged: emitted.add),
          ),
        ),
      ),
    );
    await tester.pump();
    final state = tester.state<NotesEditorState>(find.byType(NotesEditor));
    final ed = state.editorState;
    await ed.apply(
      ed.transaction..insertText(ed.document.root.children.first, 0, 'X'),
    );
    await tester.pump(const Duration(milliseconds: 10));
    expect(emitted, isEmpty, reason: 'still inside the 400 ms debounce');

    lifecycle(tester, [AppLifecycleState.inactive]);
    expect(emitted, hasLength(1), reason: 'inactive flushes at once');
    expect(emitted.single, contains('XHi'));

    // Nothing pending any more: more signals and the timer add nothing.
    await tester.pump(const Duration(seconds: 1));
    expect(emitted, hasLength(1));

    // A second change, flushed by the later `paused` step.
    await ed.apply(
      ed.transaction..insertText(ed.document.root.children.first, 0, 'Y'),
    );
    await tester.pump(const Duration(milliseconds: 10));
    lifecycle(tester, [AppLifecycleState.hidden]);
    lifecycle(tester, [AppLifecycleState.paused]);
    expect(emitted, hasLength(2), reason: 'paused flushes at once');
    expect(emitted.last, contains('YXHi'));
    lifecycle(tester, [AppLifecycleState.hidden]);
    lifecycle(tester, [AppLifecycleState.inactive]);
    lifecycle(tester, [AppLifecycleState.resumed]);
    resume(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('the action editor writes pending notes to the database on pause', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final row = (await tester.runAsync(() async {
      final c = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      final id = await c
          .read(actionServiceProvider)
          .createAction(name: 'Task', notes: _json1);
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
              onPressed: () => ActionEditorDialog.show(context, existing: row),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);

    final state = tester.state<NotesEditorState>(find.byType(NotesEditor));
    final ed = state.editorState;
    await ed.apply(
      ed.transaction..insertText(ed.document.root.children.first, 0, 'Late '),
    );
    await tester.pump(const Duration(milliseconds: 10));

    Future<String?> storedNotes() async => (await tester.runAsync(
      () => db.select(db.actionsTable).getSingle(),
    ))!.notes;

    expect(await storedNotes(), _json1, reason: 'nothing written yet');

    background(tester);
    await tester.pump();
    await settle(tester);
    expect(await storedNotes(), contains('Late Hi'));

    await settle(tester);
    // `paused` stops frames: bring the app back before unmounting.
    resume(tester);
    await tester.pumpWidget(const SizedBox());
    // Drift cancels its streams on zero-duration timers, in several rounds.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  });
}
