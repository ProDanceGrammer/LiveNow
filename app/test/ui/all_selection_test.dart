import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/all_selection.dart';
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/views/all_actions_view.dart';
import 'package:livenow/ui/widgets/action_picker_dialog.dart';

/// The All list: a checkbox per row, "select all" over the WHOLE filtered list,
/// a mouse marquee, Esc / Del, the bulk bar and no three-dots menu.
void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late ProviderContainer container;
  final ids = <String>[];

  Future<void> settle(WidgetTester tester, [int ms = 300]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pump(
    WidgetTester tester, {
    int count = 6,
    Size size = const Size(1000, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    ids.clear();
    await tester.runAsync(() async {
      final service = ActionService(db);
      for (var i = 0; i < count; i++) {
        ids.add(
          await service.createAction(
            name: 'Action ${i.toString().padLeft(2, '0')}',
            startAt: DateTime.utc(2030, 1, 10 + i, 9),
            endAt: DateTime.utc(2030, 1, 10 + i, 10),
          ),
        );
        // Distinct updated_at so the list order (last edited first) is stable.
        await Future<void>.delayed(const Duration(milliseconds: 4));
      }
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: Scaffold(body: AllActionsView())),
      ),
    );
    container = ProviderScope.containerOf(
      tester.element(find.byType(AllActionsView)),
    );
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    resetStackedDialogsForTest();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Set<String> selected() => container.read(allSelectionProvider);

  testWidgets('a checkbox per row; the header counts and clears', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byKey(const ValueKey('all-bulk-bar')), findsOneWidget);
    expect(find.text('Select all'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('all-check-${ids[0]}')));
    await tester.tap(find.byKey(ValueKey('all-check-${ids[2]}')));
    await tester.pump();
    expect(selected(), {ids[0], ids[2]});
    expect(find.text('2 selected'), findsOneWidget);
    expect(find.byKey(const ValueKey('bulk-directions')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('bulk-clear')));
    await tester.pump();
    expect(selected(), isEmpty);
    expect(find.text('Select all'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('select all covers the whole filtered list, also off-screen rows', (
    tester,
  ) async {
    await pump(tester, count: 30, size: const Size(1000, 500));
    // Far fewer than 30 tiles are built in a 500 px high list.
    expect(
      find.byType(Checkbox).evaluate().length,
      lessThan(30 + 1),
    );
    await tester.tap(find.byKey(const ValueKey('all-select-all')));
    await tester.pump();
    expect(selected().length, 30);
    expect(
      tester.widget<Checkbox>(find.byKey(const ValueKey('all-select-all'))).value,
      isTrue,
    );
    // Unticking one makes the header tri-state.
    await tester.tap(find.byKey(ValueKey('all-check-${ids[29]}')));
    await tester.pump();
    expect(selected().length, 29);
    expect(
      tester.widget<Checkbox>(find.byKey(const ValueKey('all-select-all'))).value,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('all-select-all')));
    await tester.pump();
    expect(selected().length, 30);
    await tester.tap(find.byKey(const ValueKey('all-select-all')));
    await tester.pump();
    expect(selected(), isEmpty);
    await unmount(tester);
  });

  testWidgets('select all follows the search', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const ValueKey('allSearchField')), '03');
    await settle(tester, 600);
    await tester.tap(find.byKey(const ValueKey('all-select-all')));
    await tester.pump();
    expect(selected(), {ids[3]});
    await unmount(tester);
  });

  testWidgets('no three-dots menu on a row', (tester) async {
    await pump(tester);
    expect(find.byType(PopupMenuButton<dynamic>), findsNothing);
    expect(find.byIcon(Icons.more_vert), findsNothing);
    await unmount(tester);
  });

  testWidgets('with a selection a tap toggles the row instead of opening it', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(ValueKey('all-check-${ids[1]}')));
    await tester.pump();
    await tester.tap(find.text('Action 02'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(selected(), {ids[1], ids[2]});
    expect(find.byType(AlertDialog), findsNothing); // no editor opened
    await unmount(tester);
  });

  testWidgets('a mouse drag over the rows selects them; Esc clears', (
    tester,
  ) async {
    await pump(tester);
    final first = tester.getRect(find.byKey(ValueKey('all-tile-${ids[5]}')));
    final third = tester.getRect(find.byKey(ValueKey('all-tile-${ids[3]}')));
    // The list is newest-edited first: ids[5], ids[4], ids[3] are rows 1-3.
    final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await g.down(Offset(first.left - 8, first.top + 4));
    await g.moveTo(Offset(first.right + 8, third.bottom - 4));
    await tester.pump();
    expect(find.byKey(const ValueKey('all-marquee-rect')), findsOneWidget);
    await g.up();
    await tester.pump();
    expect(selected(), {ids[5], ids[4], ids[3]});
    expect(find.byKey(const ValueKey('all-marquee-rect')), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(selected(), isEmpty);
    await unmount(tester);
  });

  testWidgets('a marquee scrolls the list and keeps the rows it passed', (
    tester,
  ) async {
    await pump(tester, count: 30, size: const Size(1000, 500));
    final top = tester.getTopLeft(find.byKey(ValueKey('all-tile-${ids[29]}')));
    final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await g.down(Offset(top.dx - 8, top.dy + 4));
    // Hold the pointer at the bottom edge: the list scrolls by itself.
    await g.moveTo(const Offset(500, 495));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pump();
    // Far more rows than the 5-6 on one screen are selected.
    expect(selected().length, greaterThan(8));
    expect(selected(), contains(ids[29]));
    await unmount(tester);
  });

  testWidgets('Delete removes the selection with one Undo', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(ValueKey('all-check-${ids[0]}')));
    await tester.tap(find.byKey(ValueKey('all-check-${ids[1]}')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('bulk-delete')));
    await settle(tester, 600);
    final left = (await tester.runAsync(
      () => db.select(db.actionsTable).get(),
    ))!;
    expect(left.length, 4);
    expect(find.text('Undo'), findsOneWidget);
    expect(selected(), isEmpty);
    await tester.pump(const Duration(seconds: 6));
    await unmount(tester);
  });

  testWidgets('Shift by moves every selected action, one Undo', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(ValueKey('all-check-${ids[0]}')));
    await tester.tap(find.byKey(ValueKey('all-check-${ids[1]}')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('bulk-date')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('bulk-date-shift')));
    await tester.pump(const Duration(milliseconds: 400));
    // Default: 1 day later.
    await tester.tap(find.byKey(const ValueKey('shift-apply')));
    await settle(tester, 800);

    final rows = (await tester.runAsync(
      () => db.select(db.actionsTable).get(),
    ))!;
    DateTime start(String id) =>
        DateTime.parse(rows.firstWhere((r) => r.id == id).startAt!);
    expect(start(ids[0]), DateTime.utc(2030, 1, 11, 9));
    expect(start(ids[1]), DateTime.utc(2030, 1, 12, 9));
    expect(start(ids[2]), DateTime.utc(2030, 1, 12, 9)); // untouched
    expect(find.text('Undo'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await unmount(tester);
  });

  testWidgets('Next action: the chosen action becomes the next of each', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(ValueKey('all-check-${ids[0]}')));
    await tester.tap(find.byKey(ValueKey('all-check-${ids[1]}')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('bulk-next')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('bulk-links-choose')));
    await settle(tester, 400);
    // The picker offers the unselected actions only.
    final inPicker = find.byType(ActionPickerDialog);
    expect(
      find.descendant(of: inPicker, matching: find.text('Action 00')),
      findsNothing,
    );
    await tester.tap(
      find.descendant(of: inPicker, matching: find.text('Action 04')),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('bulk-links-apply')));
    await settle(tester, 800);

    final edges = (await tester.runAsync(
      () => db.select(db.actionDependenciesTable).get(),
    ))!;
    expect({for (final e in edges) (e.predecessorId, e.successorId)}, {
      (ids[0], ids[4]),
      (ids[1], ids[4]),
    });
    expect(find.text('Undo'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await unmount(tester);
  });

  testWidgets('the bulk bar sets the countable activity of every selected action', (
    tester,
  ) async {
    await pump(tester);
    final activity = (await tester.runAsync(
      () => ActionService(db).createCountableActivity('Reading'),
    ))!;
    await settle(tester);
    await tester.tap(find.byKey(ValueKey('all-check-${ids[0]}')));
    await tester.tap(find.byKey(ValueKey('all-check-${ids[1]}')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('bulk-activity')));
    await settle(tester, 400);
    await tester.tap(find.text('Reading').last);
    await settle(tester, 400);

    Future<List<String?>> activities() async => (await tester.runAsync(
      () async => [
        for (final id in ids.take(3))
          (await (db.select(db.actionsTable)..where((t) => t.id.equals(id)))
                  .getSingle())
              .countableActivityId,
      ],
    ))!;
    expect(await activities(), [activity, activity, null]);

    // Undo puts them back.
    await tester.tap(find.text('Undo'));
    await settle(tester, 400);
    expect(await activities(), [null, null, null]);
    await unmount(tester);
  });
}
