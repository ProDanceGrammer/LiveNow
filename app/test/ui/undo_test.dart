import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/ui/dialog_stack.dart';
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

  testWidgets('undo toast auto-dismisses after 5s; the entry stays undoable', (
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
    expect(find.text('Renamed'), findsOneWidget);
    expect(container.read(undoHistoryProvider), hasLength(1));

    await tester.pump(const Duration(milliseconds: 4500)); // ~4.9s total
    expect(find.text('Renamed'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 700)); // past 5s
    await tester.pump();
    expect(find.text('Renamed'), findsNothing);
    // The toast is gone but the operation can still be undone (Ctrl+Z).
    expect(container.read(undoHistoryProvider), hasLength(1));

    await unmount(tester);
  });

  testWidgets('the Undo toast is above an open dialog and can be clicked', (
    tester,
  ) async {
    await pumpHarness(tester);
    final context = tester.element(find.text('go'));
    // Open a dialog, then trigger the undoable operation from inside it.
    showStackedDialog<void>(
      context: context,
      builder: (_) => Consumer(
        builder: (dialogContext, ref, _) => AlertDialog(
          content: TextButton(
            onPressed: () => runUndoable(
              dialogContext,
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
            child: const Text('go in dialog'),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(() async {
      await tester.tap(find.text('go in dialog'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    expect(find.text('Renamed'), findsOneWidget);
    expect(find.text('Undo').hitTestable(), findsOneWidget);
    expect(await currentName(tester), 'changed');

    await tester.runAsync(() async {
      await tester.tap(find.text('Undo'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    expect(await currentName(tester), 'original');
    expect(find.text('Undo'), findsNothing);
    resetStackedDialogsForTest();
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
          .read(undoHistoryProvider),
      isEmpty,
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

  testWidgets('history keeps the last 10, Ctrl+Z undoes newest first', (
    tester,
  ) async {
    await pumpHarness(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.text('go')),
    );
    final order = <int>[];
    final history = container.read(undoHistoryProvider.notifier);
    final overlay = Overlay.of(tester.element(find.text('go')));
    for (var i = 0; i < 12; i++) {
      offerUndo(overlay, history, 'op $i', () async => order.add(i));
    }
    await tester.pump();
    expect(container.read(undoHistoryProvider), hasLength(kUndoHistoryLimit));
    expect(container.read(undoHistoryProvider).first.description, 'op 2');

    // Newest first, repeatedly; each press takes one step back.
    await tester.runAsync(() async {
      expect(await _undo(container), isTrue);
      expect(await _undo(container), isTrue);
    });
    expect(order, [11, 10]);
    expect(container.read(undoHistoryProvider), hasLength(8));

    // Drain the rest, then there is nothing left to undo.
    await tester.runAsync(() async {
      for (var i = 0; i < 8; i++) {
        await _undo(container);
      }
      expect(await _undo(container), isFalse);
    });
    expect(order.length, 10);
    expect(order.last, 2);
    await tester.pump(const Duration(seconds: 6));
    await unmount(tester);
  });

  testWidgets('a revert that throws drops its entry and does not crash', (
    tester,
  ) async {
    await pumpHarness(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.text('go')),
    );
    final overlay = Overlay.of(tester.element(find.text('go')));
    offerUndo(
      overlay,
      container.read(undoHistoryProvider.notifier),
      'bad',
      () async => throw StateError('row is gone'),
    );
    await tester.pump();
    await tester.runAsync(() async => expect(await _undo(container), isFalse));
    expect(container.read(undoHistoryProvider), isEmpty);
    await tester.pump(const Duration(seconds: 6));
    await unmount(tester);
  });
}

Future<bool> _undo(ProviderContainer c) =>
    undoNewest(c.read(undoHistoryProvider.notifier));
