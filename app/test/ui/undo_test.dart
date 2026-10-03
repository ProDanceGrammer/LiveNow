import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/undo.dart';
import 'package:livenow/ui/widgets/quick_action_bar.dart';

void main() {
  late AppDatabase db;
  late String actionId;

  Future<void> pumpHarness(WidgetTester tester) async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.runAsync(() async {
      actionId = await ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      ).read(actionServiceProvider).createAction(name: 'original');
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => runUndoable(
                  context,
                  ref,
                  actionId,
                  'Renamed',
                  () =>
                      (db.update(
                        db.actionsTable,
                      )..where((t) => t.id.equals(actionId))).write(
                        const ActionsTableCompanion(name: Value('changed')),
                      ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<String> currentName(WidgetTester tester) async =>
      (await tester.runAsync(
        () => (db.select(
          db.actionsTable,
        )..where((t) => t.id.equals(actionId))).getSingle(),
      ))!.name;

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('undo snackbar auto-dismisses after 5s and clears lastUndo', (
    tester,
  ) async {
    await pumpHarness(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.text('go')),
    );

    await tester.runAsync(() async {
      await tester.tap(find.text('go'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // enter animation
    expect(find.text('Renamed'), findsOneWidget);
    expect(container.read(lastUndoProvider), isNotNull);

    await tester.pump(const Duration(milliseconds: 4500)); // ~4.9s total
    expect(find.text('Renamed'), findsOneWidget);
    expect(container.read(lastUndoProvider), isNotNull);

    await tester.pump(
      const Duration(milliseconds: 700),
    ); // past 5s (timer starts after enter animation)
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    // runUndoable was started inside runAsync (real zone), so its closed.then
    // continuation runs on the real event loop: yield to it.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    expect(find.text('Renamed'), findsNothing);
    expect(container.read(lastUndoProvider), isNull);

    await unmount(tester);
  });

  testWidgets('Continue button creates the next action and Undo removes it', (
    tester,
  ) async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.runAsync(() async {
      actionId = await ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      ).read(actionServiceProvider).createAction(name: 'Read');
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Scaffold(body: QuickActionBar(actionId: actionId)),
        ),
      ),
    );

    Future<List<String>> names() async =>
        (await tester.runAsync(() => db.select(db.actionsTable).get()))!
            .map((a) => a.name)
            .toList()
          ..sort();

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Continue with same action'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(await names(), ['[#1] Read', '[#2] Read']);

    await tester.runAsync(() async {
      await tester.tap(find.text('Undo'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    expect(await names(), ['Read']);

    await tester.pump(const Duration(seconds: 1));
    await unmount(tester);
  });

  testWidgets('pressing Undo restores the snapshot', (tester) async {
    await pumpHarness(tester);
    await tester.runAsync(() async {
      await tester.tap(find.text('go'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(await currentName(tester), 'changed');

    await tester.runAsync(() async {
      await tester.tap(find.text('Undo'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    expect(await currentName(tester), 'original');
    expect(
      ProviderScope.containerOf(tester.element(find.text('go')))
          .read(lastUndoProvider),
      isNull,
    );

    await tester.pump(const Duration(seconds: 1));
    await unmount(tester);
  });

  testWidgets('runUndoableToggleDone ticks and Undo unticks', (tester) async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.runAsync(() async {
      actionId = await ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      ).read(actionServiceProvider).createAction(name: 'chk', isAllDay: true);
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => runUndoableToggleDone(context, ref, actionId),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    Future<bool> done() async => (await tester.runAsync(
      () => (db.select(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).getSingle(),
    ))!.done;

    await tester.runAsync(() async {
      await tester.tap(find.text('go'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(await done(), isTrue);

    await tester.runAsync(() async {
      await tester.tap(find.text('Undo'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    expect(await done(), isFalse);

    await tester.pump(const Duration(seconds: 1));
    await unmount(tester);
  });
}
