import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/widgets/action_editor.dart';

/// A NEW action's editor has the same parts as an existing one: the Delete icon
/// (it cancels creating) and Connected actions (previous / next are collected in
/// the form and linked when the action is saved).
void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;

  Future<void> settle(WidgetTester tester, [int ms = 400]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys = ON;'),
      ),
    );
    addTearDown(db.close);
    await tester.runAsync(() async {
      final c = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      await c.read(actionServiceProvider).createAction(
        name: 'Old action',
        startAt: DateTime.utc(2030, 1, 10, 9),
        endAt: DateTime.utc(2030, 1, 10, 10),
      );
      await c.read(actionServiceProvider).createAction(
        name: 'Later action',
        startAt: DateTime.utc(2030, 1, 10, 12),
        endAt: DateTime.utc(2030, 1, 10, 13),
      );
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => ActionEditorDialog.show(context),
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
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<List<ActionRow>> actions(WidgetTester tester) async =>
      (await tester.runAsync(() => db.select(db.actionsTable).get()))!;
  Future<List<ActionDependency>> edges(WidgetTester tester) async => (await tester
      .runAsync(() => db.select(db.actionDependenciesTable).get()))!;

  Future<void> pickOld(
    WidgetTester tester,
    String addTooltip, [
    String name = 'Old action',
  ]) async {
    await tester.tap(find.byTooltip(addTooltip));
    await settle(tester);
    await tester.tap(find.text(name).last);
    await settle(tester);
  }

  testWidgets('a new action shows Connected actions with + for previous and next', (
    tester,
  ) async {
    await mount(tester);
    expect(find.text('Connected actions'), findsOneWidget);
    expect(find.byTooltip('Add previous action'), findsOneWidget);
    expect(find.byTooltip('Add next action'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('Delete on a new action cancels creating it: nothing is written', (
    tester,
  ) async {
    await mount(tester);
    await tester.enterText(find.byType(TextFormField).first, 'Draft');
    await pickOld(tester, 'Add previous action');
    // The chosen action shows as a chip in the form.
    expect(find.widgetWithText(InputChip, 'Old action'), findsOneWidget);

    await tester.tap(find.byTooltip('Cancel creating'));
    await settle(tester, 600);
    expect(find.byType(ActionEditorDialog), findsNothing);
    expect((await actions(tester)).map((a) => a.name).toSet(), {
      'Old action',
      'Later action',
    });
    expect(await edges(tester), isEmpty);
    await unmount(tester);
  });

  testWidgets('previous and next picked in a new action are linked when it is saved', (
    tester,
  ) async {
    await mount(tester);
    await tester.enterText(find.byType(TextFormField).first, 'Fresh');
    await pickOld(tester, 'Add previous action');
    await pickOld(tester, 'Add next action', 'Later action');
    // Nothing is written before Save.
    expect(await edges(tester), isEmpty);
    expect((await actions(tester)).length, 2);

    await tester.tap(find.text('Save'));
    await settle(tester, 600);
    final all = await actions(tester);
    String idOf(String n) => all.firstWhere((a) => a.name == n).id;
    expect(all.length, 3);
    final e = await edges(tester);
    expect(
      {for (final d in e) (d.predecessorId, d.successorId)},
      {
        (idOf('Old action'), idOf('Fresh')),
        (idOf('Fresh'), idOf('Later action')),
      },
    );
    await unmount(tester);
  });
}
