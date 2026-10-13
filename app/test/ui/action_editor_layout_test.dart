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
import 'package:livenow/ui/widgets/section_block.dart';

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

  testWidgets('there is no Time tracking panel; Start keeps the dialog open '
      'and reloads the schedule (the schedule is the only source of truth)', (
    tester,
  ) async {
    setup(tester);
    final id = await seedAction(tester, 'Walk');
    await open(tester, existing: await rowOf(tester, id));

    expect(find.text('Time tracking'), findsNothing);
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
    expect(find.text('Time tracking'), findsNothing);
    expect(find.textContaining('Currently running'), findsNothing);
    expect(find.textContaining('Not set'), findsNothing); // schedule reloaded
    expect(find.widgetWithText(TextFormField, 'Walk typed'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6)); // the Undo snackbar
    await teardown(tester);
  });

  testWidgets('Connected actions: headers with a + at their right, nothing '
      'else when empty', (tester) async {
    setup(tester);
    final id = await seedAction(tester, 'Middle');
    await open(tester, existing: await rowOf(tester, id));

    expect(find.text('Connected actions'), findsOneWidget);
    expect(find.text('Previous actions'), findsOneWidget);
    expect(find.text('Next actions'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Previous actions')).dx,
      lessThan(tester.getTopLeft(find.text('Next actions')).dx),
    );
    // The + sits to the right of its title, on the same row.
    final prevTitle = tester.getRect(find.text('Previous actions'));
    final prevPlus = tester.getRect(find.byTooltip('Add previous action'));
    expect(prevPlus.left, greaterThanOrEqualTo(prevTitle.right));
    expect((prevPlus.center.dy - prevTitle.center.dy).abs(), lessThan(8));
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

  testWidgets('Manual parameters holds only the countable activity', (
    tester,
  ) async {
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
    expect(find.text('Postpone flexibility'), findsNothing);
    expect(find.text('Depth (learning)'), findsNothing);
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
    final row = find.widgetWithText(ListTile, 'Run');
    expect(find.text('Linked actions (1)'), findsOneWidget);
    await tester.ensureVisible(row);
    await tester.tap(row);
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

  testWidgets('Done switch: only for an all-day action, right of All day, and '
      'toggling All day does not move it between rows', (tester) async {
    setup(tester);
    final id = await seedAction(tester, 'Chore');
    await open(tester, existing: await rowOf(tester, id));
    final allDay = find.byKey(const ValueKey('editorAllDaySwitch'));
    final done = find.byKey(const ValueKey('editorDoneSwitch'));
    expect(done, findsNothing);
    final y = tester.getCenter(allDay).dy;
    final x = tester.getCenter(allDay).dx;

    await tester.tap(allDay);
    await tester.pump(const Duration(milliseconds: 400));
    expect(done, findsOneWidget);
    expect(tester.getCenter(done).dx, greaterThan(tester.getCenter(allDay).dx));
    expect(tester.getCenter(allDay).dx, x);
    expect(tester.getCenter(allDay).dy, y);
    expect(tester.getCenter(done).dy, y);
    expect(tester.widget<Switch>(done).value, isFalse);

    await tester.tap(allDay);
    await tester.pump(const Duration(milliseconds: 400));
    expect(done, findsNothing);
    expect(tester.getCenter(allDay).dy, y);
    await teardown(tester);
  });

  testWidgets('Done switch writes the done flag straight away', (tester) async {
    setup(tester);
    final id = (await tester.runAsync(
      () => seedContainer
          .read(actionServiceProvider)
          .createAction(
            name: 'Chore',
            isAllDay: true,
            startAt: DateTime.utc(2026, 10, 3),
          ),
    ))!;
    await open(tester, existing: await rowOf(tester, id));
    final done = find.byKey(const ValueKey('editorDoneSwitch'));
    expect(tester.widget<Switch>(done).value, isFalse);
    await tester.tap(done);
    await tester.pump();
    await settle(tester);
    await settle(tester);
    expect((await rowOf(tester, id)).done, isTrue);
    expect(tester.widget<Switch>(done).value, isTrue);
    await tester.pump(const Duration(seconds: 6)); // the Undo toast
    await teardown(tester);
  });

  testWidgets('Countable activity lists templates without a same-name '
      'activity and picking one creates it', (tester) async {
    setup(tester);
    final id = await seedAction(tester, 'Run');
    await tester.runAsync(() async {
      await db
          .into(db.actionTemplatesTable)
          .insert(
            ActionTemplatesTableCompanion.insert(
              id: 'tpl1',
              name: 'Gym',
              payload: '{}',
            ),
          );
      await seedContainer
          .read(actionServiceProvider)
          .createCountableActivity('gym');
      await db
          .into(db.actionTemplatesTable)
          .insert(
            ActionTemplatesTableCompanion.insert(
              id: 'tpl2',
              name: 'Yoga',
              payload: '{}',
            ),
          );
    });
    await open(tester, existing: await rowOf(tester, id));
    await tester.tap(find.text('Manual parameters'));
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    final field = find.byKey(const ValueKey('countableActivityField'));
    await tester.ensureVisible(field);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(field);
    await tester.pump(const Duration(milliseconds: 400));
    // The picker dialog: None on top, New activity... at the bottom.
    expect(find.byKey(const ValueKey('activityNone')), findsOneWidget);
    expect(find.byKey(const ValueKey('activityNew')), findsOneWidget);
    expect(find.text('gym'), findsOneWidget);
    expect(find.text('Gym (template)'), findsNothing); // has an activity
    expect(find.text('Yoga (template)'), findsOneWidget);
    await tester.tap(find.text('Yoga (template)').last);
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    final acts = (await tester.runAsync(
      () => db.select(db.countableActivitiesTable).get(),
    ))!;
    expect(acts.map((a) => a.name), containsAll(['gym', 'Yoga']));
    await teardown(tester);
  });

  testWidgets('Countable activity picker: search filters, None and New stay '
      'pinned, None clears the choice', (tester) async {
    setup(tester);
    final id = await seedAction(tester, 'Run');
    await tester.runAsync(() async {
      final svc = seedContainer.read(actionServiceProvider);
      final a = await svc.createCountableActivity('Swimming');
      await svc.createCountableActivity('Reading');
      await svc.setCountableActivity(id, a);
    });
    await open(tester, existing: await rowOf(tester, id));
    await tester.tap(find.text('Manual parameters'));
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    expect(find.text('Swimming'), findsOneWidget); // in the closed field
    await tester.ensureVisible(
      find.byKey(const ValueKey('countableActivityField')),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('countableActivityField')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Reading'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Search'), 'READ');
    await tester.pump();
    expect(find.text('Reading'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.text('Swimming'),
      ),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('activityNone')), findsOneWidget);
    expect(find.byKey(const ValueKey('activityNew')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('activityNone')));
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('countableActivityField')),
        matching: find.text('None'),
      ),
      findsOneWidget,
    );
    expect(find.text('Swimming'), findsNothing);
    await teardown(tester);
  });

  testWidgets('Action picker rows show the short schedule', (tester) async {
    setup(tester);
    final id = await seedAction(tester, 'Middle');
    await tester.runAsync(
      () => seedContainer
          .read(actionServiceProvider)
          .createAction(
            name: 'Other',
            // Far in the future so the action is always still open (the
            // picker lists open actions only) and never in the current year.
            startAt: DateTime.utc(2099, 10, 3, 10, 0),
            endAt: DateTime.utc(2099, 10, 3, 11, 40),
          ),
    );
    await open(tester, existing: await rowOf(tester, id));
    await tester.tap(find.byTooltip('Add next action'));
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    expect(find.text('Choose an action'), findsOneWidget);
    expect(find.text('Other'), findsOneWidget);
    expect(find.textContaining("3 Oct 99' 13:00-14:40"), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await tester.pump(const Duration(milliseconds: 400));
    await teardown(tester);
  });

  testWidgets('Manual parameters is a section block; a very long countable '
      'activity name is shown whole without an overflow', (tester) async {
    setup(tester);
    final longName =
        'A very long countable activity name that keeps going and going '
        'until it certainly cannot fit on a single line of the dropdown';
    await tester.runAsync(() async {
      final svc = seedContainer.read(actionServiceProvider);
      final act = await svc.createCountableActivity(longName);
      final id = await svc.createAction(name: 'Chore');
      await svc.setCountableActivity(id, act);
    });
    final row = (await tester.runAsync(
      () => db.select(db.actionsTable).getSingle(),
    ))!;
    await open(tester, existing: row);

    final title = find.text('Manual parameters');
    expect(
      find.ancestor(of: title, matching: find.byType(SectionBlock)),
      findsOneWidget,
    );
    await tester.ensureVisible(title);
    await tester.tap(title);
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);

    // The closed field shows the whole name (not clipped to one line).
    expect(find.text(longName), findsOneWidget);
    expect(tester.takeException(), isNull);
    // All four section headers share the horizontal tile padding.
    for (final t in tester.widgetList<ExpansionTile>(
      find.byType(ExpansionTile),
    )) {
      expect(t.tilePadding, kSectionTilePadding);
    }
    await teardown(tester);
  });
}
