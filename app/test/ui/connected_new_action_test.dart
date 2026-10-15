import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/ids.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/widgets/action_editor.dart';

/// "Connected actions" in the action editor: '+' offers 'New action...' and
/// 'New from template...'; the new action's editor opens prefilled, right next
/// to this action, and the action is created and linked only when it is saved.
void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late String mainId, shower;
  final mainStart = DateTime.utc(2030, 1, 10, 9);
  final mainEnd = DateTime.utc(2030, 1, 10, 10);

  Future<void> settle(WidgetTester tester, [int ms = 400]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> mount(WidgetTester tester, {bool allDay = false}) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys = ON;'),
      ),
    );
    addTearDown(db.close);
    late ActionRow row;
    await tester.runAsync(() async {
      final c = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      mainId = await c
          .read(actionServiceProvider)
          .createAction(
            name: 'Main',
            startAt: allDay ? DateTime.utc(2030, 1, 9, 21) : mainStart,
            endAt: allDay ? null : mainEnd,
            isAllDay: allDay,
          );
      shower = newId();
      await db
          .into(db.actionTemplatesTable)
          .insert(
            ActionTemplatesTableCompanion.insert(
              id: shower,
              name: 'Shower',
              payload: jsonEncode({
                'name': 'Shower',
                'estimatedMinutes': 20,
                'useAverage': false,
              }),
            ),
          );
      row = await (db.select(
        db.actionsTable,
      )..where((t) => t.id.equals(mainId))).getSingle();
    });
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
    await settle(tester, 600);
  }

  Future<void> unmount(WidgetTester tester) async {
    resetStackedDialogsForTest();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<List<ActionRow>> actions(WidgetTester tester) async =>
      (await tester.runAsync(() => db.select(db.actionsTable).get()))!;

  Future<List<ActionDependency>> edges(WidgetTester tester) async =>
      (await tester.runAsync(() => db.select(db.actionDependenciesTable).get()))!;

  Future<void> addFromTemplate(WidgetTester tester, String tooltip) async {
    await tester.tap(find.byTooltip(tooltip));
    await settle(tester);
    expect(find.byKey(const ValueKey('pick-new-action')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pick-new-from-template')));
    await settle(tester);
    await tester.tap(find.byKey(ValueKey('template-pick-$shower')));
    await settle(tester, 600);
  }

  testWidgets('Previous from a template: prefilled, saved, linked, adjacent', (
    tester,
  ) async {
    await mount(tester);
    await addFromTemplate(tester, 'Add previous action');
    // The child editor is open and prefilled with the template's name.
    expect(find.widgetWithText(TextFormField, 'Shower'), findsOneWidget);

    await tester.tap(find.text('Save').last);
    await settle(tester, 600);

    final all = await actions(tester);
    expect(all, hasLength(2));
    final created = all.firstWhere((a) => a.name == 'Shower');
    // Ends when Main starts, 20 minutes long (the template's).
    expect(DateTime.parse(created.endAt!), mainStart);
    expect(
      DateTime.parse(created.endAt!).difference(DateTime.parse(created.startAt!)),
      const Duration(minutes: 20),
    );
    final e = await edges(tester);
    expect(e, hasLength(1));
    expect((e.single.predecessorId, e.single.successorId), (created.id, mainId));
    await unmount(tester);
  });

  testWidgets('Cancel in the child editor creates nothing', (tester) async {
    await mount(tester);
    await addFromTemplate(tester, 'Add previous action');
    await tester.tap(find.text('Cancel').last);
    await settle(tester);
    expect(await actions(tester), hasLength(1));
    expect(await edges(tester), isEmpty);
    await unmount(tester);
  });

  testWidgets('Next from a template starts when Main ends', (tester) async {
    await mount(tester);
    await addFromTemplate(tester, 'Add next action');
    await tester.tap(find.text('Save').last);
    await settle(tester, 600);

    final created = (await actions(tester)).firstWhere((a) => a.name == 'Shower');
    expect(DateTime.parse(created.startAt!), mainEnd);
    final e = await edges(tester);
    expect((e.single.predecessorId, e.single.successorId), (mainId, created.id));
    await unmount(tester);
  });

  testWidgets('New action... opens a blank editor with adjacent times', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byTooltip('Add next action'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('pick-new-action')));
    await settle(tester, 600);
    await tester.enterText(
      find.byType(TextFormField).last,
      'Walk home',
    );
    await tester.tap(find.text('Save').last);
    await settle(tester, 600);

    final created = (await actions(tester)).firstWhere((a) => a.name == 'Walk home');
    expect(DateTime.parse(created.startAt!), mainEnd);
    expect(
      DateTime.parse(created.endAt!).difference(mainEnd),
      const Duration(hours: 1),
    );
    expect(await edges(tester), hasLength(1));
    await unmount(tester);
  });

  testWidgets('an all-day action gives an unscheduled new one', (tester) async {
    await mount(tester, allDay: true);
    await tester.tap(find.byTooltip('Add previous action'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('pick-new-action')));
    await settle(tester, 600);
    await tester.enterText(find.byType(TextFormField).last, 'Prepare');
    await tester.tap(find.text('Save').last);
    await settle(tester, 600);
    final created = (await actions(tester)).firstWhere((a) => a.name == 'Prepare');
    expect(created.startAt, isNull);
    expect(await edges(tester), hasLength(1));
    await unmount(tester);
  });
}
