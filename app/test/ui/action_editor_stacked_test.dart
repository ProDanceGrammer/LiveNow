import 'package:appflowy_editor/appflowy_editor.dart' show TextTransaction;
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/growth_rules.dart';
import 'package:livenow/domain/postpone_rules.dart' show initPostponeTimeZoneData;
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/open_entity.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/widgets/action_editor.dart';
import 'package:livenow/ui/widgets/notes_editor.dart';

const _json1 =
    '{"document":{"type":"page","children":[{"type":"paragraph","data":{"delta":[{"insert":"Hi"}]}}]}}';
const _json2 =
    '{"document":{"type":"page","children":[{"type":"paragraph","data":{"delta":[{"insert":"Bye"}]}}]}}';

/// Stacked editors over one row: a lower dialog must follow what an upper one
/// saved, and opening another item saves the whole form of the dialog below.
void main() {
  late AppDatabase db;
  late WidgetRef homeRef;

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
  }

  Future<void> pumpOpen(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
  }

  void setup(WidgetTester tester) {
    initPostponeTimeZoneData();
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    resetStackedDialogsForTest();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
  }

  Future<ActionRow> seed(
    WidgetTester tester,
    String name, {
    String? notes,
  }) async {
    return (await tester.runAsync(() async {
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      final id = await container
          .read(actionServiceProvider)
          .createAction(name: name, notes: notes);
      return (db.select(
        db.actionsTable,
      )..where((t) => t.id.equals(id))).getSingle();
    }))!;
  }

  Future<ActionRow> rowOf(WidgetTester tester, String id) async =>
      (await tester.runAsync(
        () => (db.select(
          db.actionsTable,
        )..where((t) => t.id.equals(id))).getSingle(),
      ))!;

  /// Mounts a home page and opens [first] in an editor (a Consumer keeps a
  /// `ref` for the openers, which need one).
  Future<void> openFirst(WidgetTester tester, ActionRow first) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              homeRef = ref;
              return TextButton(
                onPressed: () =>
                    ActionEditorDialog.show(context, existing: first),
                child: const Text('open'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await pumpOpen(tester);
  }

  /// The context of the TOPMOST action dialog (what a chip inside it has).
  BuildContext topDialog(WidgetTester tester) => tester.element(
    find.byKey(const ValueKey('action-editor-dialog')).last,
  );

  Future<void> openById(WidgetTester tester, String id) async {
    final ctx = topDialog(tester);
    // ignore: unawaited_futures
    openActionById(ctx, homeRef, id);
    await pumpOpen(tester);
  }

  NotesEditorState notesAt(WidgetTester tester, {required bool first}) {
    final f = find.byType(NotesEditor);
    return tester.state<NotesEditorState>(first ? f.first : f.last);
  }

  String textOf(NotesEditorState s) => s.editorState.document.root.children
      .map((n) => n.delta?.toPlainText() ?? '')
      .join('\n');

  Future<void> typeInto(WidgetTester tester, NotesEditorState s, String t) async {
    final es = s.editorState;
    await es.apply(es.transaction..insertText(es.document.root.children.first, 0, t));
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> teardown(WidgetTester tester) async {
    await settle(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Finder blocksField() => find.byKey(const ValueKey('diary-blocks'));

  testWidgets('a lower dialog follows notes and Blocks saved elsewhere', (
    tester,
  ) async {
    setup(tester);
    final a = await seed(tester, 'Task', notes: _json1);
    await openFirst(tester, a);
    expect(textOf(notesAt(tester, first: true)), 'Hi');

    await tester.runAsync(
      () => (db.update(db.actionsTable)..where((t) => t.id.equals(a.id))).write(
        ActionsTableCompanion(notes: Value(_json2), resultNote: Value('KBT')),
      ),
    );
    await pumpOpen(tester);
    expect(textOf(notesAt(tester, first: true)), 'Bye');
    expect(tester.widget<TextField>(blocksField()).controller!.text, 'KBT');

    // A later Save of the lower dialog does not bring the old notes back.
    await tester.enterText(find.byType(TextFormField).first, 'Renamed');
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 400));
    final after = await rowOf(tester, a.id);
    expect(after.name, 'Renamed');
    expect(after.notes, _json2);
    expect(after.resultNote, 'KBT');
    await teardown(tester);
  });

  testWidgets('a lower dialog keeps its own unsaved notes', (tester) async {
    setup(tester);
    final a = await seed(tester, 'Task', notes: _json1);
    await openFirst(tester, a);
    await typeInto(tester, notesAt(tester, first: true), 'x');
    expect(textOf(notesAt(tester, first: true)), 'xHi');

    await tester.runAsync(
      () => (db.update(db.actionsTable)..where((t) => t.id.equals(a.id))).write(
        ActionsTableCompanion(notes: Value(_json2)),
      ),
    );
    await pumpOpen(tester);
    expect(textOf(notesAt(tester, first: true)), 'xHi');
    await teardown(tester);
  });

  testWidgets('A -> P -> A again: saving the upper A updates the lower A', (
    tester,
  ) async {
    setup(tester);
    final a = await seed(tester, 'Task A', notes: _json1);
    final p = await seed(tester, 'Task P');
    await openFirst(tester, a);
    await openById(tester, p.id);
    await openById(tester, a.id);
    expect(find.byKey(const ValueKey('action-editor-dialog')), findsNWidgets(3));

    // The upper copy of A: new notes and Blocks, then Save.
    final upper = notesAt(tester, first: false);
    await typeInto(tester, upper, 'New ');
    await tester.enterText(blocksField().last, 'KBT');
    await tester.tap(find.text('Save').last);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await pumpOpen(tester);

    final saved = await rowOf(tester, a.id);
    expect(saved.notes, contains('New '));
    expect(saved.resultNote, 'KBT');
    // The first (lower) A shows exactly that.
    final lower = notesAt(tester, first: true);
    expect(textOf(lower), 'New Hi');
    expect(tester.widget<TextField>(blocksField().first).controller!.text, 'KBT');
    await teardown(tester);
  });

  testWidgets('opening another action saves the whole open form first', (
    tester,
  ) async {
    setup(tester);
    final a = await seed(tester, 'Task A', notes: _json1);
    final p = await seed(tester, 'Task P');
    await openFirst(tester, a);
    await tester.enterText(find.byType(TextFormField).first, 'Renamed');
    await typeInto(tester, notesAt(tester, first: true), 'N');
    await tester.enterText(blocksField(), 'KBT');

    await openById(tester, p.id);
    final saved = await rowOf(tester, a.id);
    expect(saved.name, 'Renamed');
    expect(saved.notes, contains('NHi'));
    expect(saved.resultNote, 'KBT');
    // The dialog below stays open and is not "dirty" any more.
    expect(find.byKey(const ValueKey('action-editor-dialog')), findsNWidgets(2));

    // The same action opened over it loads the saved row.
    await openById(tester, a.id);
    expect(textOf(notesAt(tester, first: false)), 'NHi');
    expect(tester.widget<TextField>(blocksField().last).controller!.text, 'KBT');
    await teardown(tester);
  });

  testWidgets('an invalid form does not block opening another item', (
    tester,
  ) async {
    setup(tester);
    final a = await seed(tester, 'Task A', notes: _json1);
    final p = await seed(tester, 'Task P');
    await openFirst(tester, a);
    await tester.enterText(find.byType(TextFormField).first, '');
    await openById(tester, p.id);
    expect(find.byKey(const ValueKey('action-editor-dialog')), findsNWidgets(2));
    expect((await rowOf(tester, a.id)).name, 'Task A');
    await teardown(tester);
  });

  testWidgets('opening a direction saves the open action form first', (
    tester,
  ) async {
    setup(tester);
    final a = await seed(tester, 'Task A');
    final dirId = (await tester.runAsync(() async {
      final c = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      return c
          .read(metricServiceProvider)
          .saveMetric(name: 'Dir', kind: MetricKind.count, window: MetricWindow.week);
    }))!;
    await openFirst(tester, a);
    await tester.enterText(find.byType(TextFormField).first, 'Renamed');
    final ctx = topDialog(tester);
    // ignore: unawaited_futures
    openDirectionById(ctx, homeRef, dirId);
    await pumpOpen(tester);
    expect((await rowOf(tester, a.id)).name, 'Renamed');
    await teardown(tester);
  });
}
