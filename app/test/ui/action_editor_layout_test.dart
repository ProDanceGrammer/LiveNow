import 'package:appflowy_editor/appflowy_editor.dart' show Position, Selection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/growth_rules.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/widgets/action_editor.dart';
import 'package:livenow/ui/widgets/growth_direction_dialog.dart';
import 'package:livenow/ui/widgets/notes_editor.dart';

/// The reworked action edit menu: hint-only Name, Ctrl+Enter, hidden Time
/// tracking, two-column Connected actions, opening related entities.
void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late ProviderContainer seedContainer;

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  void setup(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(resetStackedDialogsForTest);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    seedContainer = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(seedContainer.dispose);
  }

  Future<ActionRow> rowOf(WidgetTester tester, String id) async =>
      (await tester.runAsync(
        () => (db.select(
          db.actionsTable,
        )..where((t) => t.id.equals(id))).getSingle(),
      ))!;

  Future<void> open(WidgetTester tester, {ActionRow? existing}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    ActionEditorDialog.show(context, existing: existing),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
  }

  Future<void> teardown(WidgetTester tester) async {
    await settle(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<String> seedAction(WidgetTester tester, String name) async =>
      (await tester.runAsync(
        () =>
            seedContainer.read(actionServiceProvider).createAction(name: name),
      ))!;

  testWidgets('Name is a hint only: the word disappears once filled', (
    tester,
  ) async {
    setup(tester);
    await open(tester);
    double hintOpacity() => tester
        .widget<AnimatedOpacity>(
          find
              .ancestor(
                of: find.text('Name'),
                matching: find.byType(AnimatedOpacity),
              )
              .first,
        )
        .opacity;
    expect(hintOpacity(), 1);
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.decoration?.labelText, isNull);
    expect(field.decoration?.hintText, 'Name');

    await tester.enterText(find.byType(TextFormField).first, 'Filled');
    await tester.pump(const Duration(milliseconds: 400));
    // The hint stays in the tree but is fully transparent once filled.
    expect(hintOpacity(), 0);
    await teardown(tester);
  });

  testWidgets('Ctrl+Enter saves the dialog', (tester) async {
    setup(tester);
    await open(tester);
    await tester.enterText(find.byType(TextFormField).first, 'By shortcut');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 400));

    final saved = (await tester.runAsync(
      () => db.select(db.actionsTable).get(),
    ))!;
    expect(saved.map((a) => a.name), ['By shortcut']);
    expect(find.byType(AlertDialog), findsNothing);
    await teardown(tester);
  });

  testWidgets('Time tracking is hidden until the action has been started; '
      'a button keeps the dialog open and reloads the schedule', (
    tester,
  ) async {
    setup(tester);
    final id = await seedAction(tester, 'Walk');
    await open(tester, existing: await rowOf(tester, id));

    expect(find.text('Time tracking'), findsNothing);
    expect(find.text('Not started yet.'), findsNothing);
    expect(find.text('Done'), findsNothing);
    expect(find.text('Open'), findsNothing);
    final before = find.textContaining('Start: ');
    expect(before, findsOneWidget);
    expect(find.textContaining('Not set'), findsNWidgets(2));

    // Type a name, then press Start in the button row.
    await tester.enterText(find.byType(TextFormField).first, 'Walk typed');
    await tester.tap(find.byTooltip('Start'));
    await tester.pump();
    await settle(tester);
    await settle(tester);

    expect(find.byType(ActionEditorDialog), findsOneWidget);
    expect(find.text('Time tracking'), findsOneWidget);
    expect(find.textContaining('Currently running'), findsOneWidget);
    expect(find.textContaining('Not set'), findsNothing); // schedule reloaded
    expect(find.widgetWithText(TextFormField, 'Walk typed'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6)); // the Undo snackbar
    await teardown(tester);
  });

  testWidgets('Connected actions: Previous left, Next right, only a + when '
      'empty', (tester) async {
    setup(tester);
    final id = await seedAction(tester, 'Middle');
    await open(tester, existing: await rowOf(tester, id));

    expect(find.text('Connected actions'), findsOneWidget);
    expect(find.text('Previous'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Previous')).dx,
      lessThan(tester.getTopLeft(find.text('Next')).dx),
    );
    final connected = find.widgetWithText(ExpansionTile, 'Connected actions');
    expect(
      find.descendant(of: connected, matching: find.text('None')),
      findsNothing,
    );
    expect(find.text('Add previous action'), findsNothing);
    expect(find.text('Add next action'), findsNothing);
    expect(find.byTooltip('Add previous action'), findsOneWidget);
    expect(find.byTooltip('Add next action'), findsOneWidget);
    await teardown(tester);
  });

  testWidgets('Manual parameters is a plain tile holding only the three '
      'parameters', (tester) async {
    setup(tester);
    final id = await seedAction(tester, 'Params');
    await open(tester, existing: await rowOf(tester, id));

    expect(
      find.widgetWithText(ExpansionTile, 'Manual parameters'),
      findsOneWidget,
    );
    await tester.tap(find.text('Manual parameters'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Postpone flexibility'), findsOneWidget);
    expect(find.text('Depth (learning)'), findsOneWidget);
    expect(find.text('Countable activity'), findsOneWidget);
    // Directions and the All-day switch live outside it.
    expect(
      find.descendant(
        of: find.widgetWithText(ExpansionTile, 'Growth directions'),
        matching: find.text('Add…'),
      ),
      findsOneWidget,
    );
    expect(find.text('All day'), findsOneWidget);
    await teardown(tester);
  });

  testWidgets('a direction opens from the action, and the action from the '
      'direction', (tester) async {
    setup(tester);
    late String actionId;
    await tester.runAsync(() async {
      final metricId = await seedContainer
          .read(metricServiceProvider)
          .saveMetric(
            name: 'Stay fit',
            kind: MetricKind.count,
            window: MetricWindow.week,
          );
      actionId = await seedContainer
          .read(actionServiceProvider)
          .createAction(name: 'Run', metricIds: [metricId]);
    });
    await open(tester, existing: await rowOf(tester, actionId));

    await tester.tap(find.widgetWithText(InputChip, 'Stay fit'));
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    expect(find.byType(GrowthDirectionDialog), findsOneWidget);
    expect(find.byType(ActionEditorDialog), findsOneWidget);

    // From the direction back to its action (a second editor on top).
    final chip = find.widgetWithText(ActionChip, 'Run');
    await tester.tap(find.text('Linked actions (1)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    expect(find.byType(ActionEditorDialog), findsNWidgets(2));
    await teardown(tester);
  });

  testWidgets('Ctrl+Enter inside the notes editor saves too', (tester) async {
    setup(tester);
    const notes =
        '{"document":{"type":"page","children":[{"type":"paragraph","data":{"delta":[{"insert":"Hi"}]}}]}}';
    final id = (await tester.runAsync(
      () => seedContainer
          .read(actionServiceProvider)
          .createAction(name: 'Noted', notes: notes),
    ))!;
    await open(tester, existing: await rowOf(tester, id));

    // Put the cursor in the editor so it owns the keyboard focus.
    final editor = tester.state<NotesEditorState>(find.byType(NotesEditor));
    final node = editor.editorState.document.root.children.first;
    await tester.tap(find.byType(NotesEditor));
    await tester.pump();
    editor.editorState.selection = Selection.collapsed(
      Position(path: node.path, offset: 2),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AlertDialog), findsNothing);
    await teardown(tester);
  });
}
