import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/current_selection.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/theme/app_theme.dart';
import 'package:livenow/ui/theme/glass_theme.dart';
import 'package:livenow/ui/views/current_actions_view.dart';
import 'package:livenow/ui/widgets/action_card.dart';
import 'package:livenow/ui/widgets/glass_icon_tile.dart';

void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late ProviderContainer container;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// 5 not-done cards (Task 0..4) in the right column; edges 0->1 and 0->4.
  Future<void> pumpBoard(WidgetTester tester, {ThemeData? theme}) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys = ON;'),
      ),
    );
    addTearDown(db.close);
    await tester.runAsync(() async {
      await db.batch(
        (b) => b.insertAll(db.actionsTable, [
          for (var i = 0; i < 5; i++)
            ActionsTableCompanion.insert(
              id: 'a$i',
              name: 'Task $i',
              done: const Value(false),
              createdAt: 't$i',
              updatedAt: 't$i',
            ),
        ]),
      );
      final deps = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      ).read(dependencyServiceProvider);
      await deps.addDependency(predecessorId: 'a0', successorId: 'a1');
      await deps.addDependency(predecessorId: 'a0', successorId: 'a4');
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: theme,
          home: const Scaffold(body: CurrentActionsView()),
        ),
      ),
    );
    await settle(tester);
    container = ProviderScope.containerOf(
      tester.element(find.byType(CurrentActionsView)),
    );
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// Card rects top to bottom, with the action id of each.
  List<(String, Rect)> cards(WidgetTester tester) {
    final list = [
      for (final e in tester.widgetList<ActionCard>(find.byType(ActionCard)))
        (e.action.id, tester.getRect(find.byKey(ValueKey(e.action.id)))),
    ]..sort((a, b) => a.$2.top.compareTo(b.$2.top));
    return list;
  }

  /// The visible glass part of a card (its box minus the 8x4 margin).
  Rect glass(Rect r) =>
      Rect.fromLTRB(r.left + 8, r.top + 4, r.right - 8, r.bottom - 4);

  /// Drags with the left mouse button from empty space in the left column.
  Future<void> drag(WidgetTester tester, Offset from, Offset to) async {
    final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
    await g.moveTo(Offset.lerp(from, to, 0.5)!);
    await g.moveTo(to);
    await g.up();
    await g.removePointer();
    await tester.pump();
  }

  /// Selects the top three cards by dragging over them.
  Future<List<(String, Rect)>> selectTopThree(WidgetTester tester) async {
    final c = cards(tester);
    await drag(
      tester,
      Offset(50, glass(c[0].$2).top + 2),
      glass(c[2].$2).center,
    );
    return c;
  }

  Future<void> afterDelete(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<Set<String>> actionIds(WidgetTester tester) async =>
      (await tester.runAsync(() => db.select(db.actionsTable).get()))!
          .map((r) => r.id)
          .toSet();

  Future<int> edgeCount(WidgetTester tester) async => (await tester.runAsync(
    () => db.select(db.actionDependenciesTable).get(),
  ))!.length;

  double contrast(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  for (final brightness in Brightness.values) {
    testWidgets('header text is readable on the deeper tint ($brightness)', (
      tester,
    ) async {
      await pumpBoard(tester, theme: buildAppTheme(brightness));
      final g = tester.element(find.byType(CurrentActionsView)).glass;
      final tint =
          tester
                  .widget<DecoratedBox>(
                    find.byKey(const ValueKey('boardHeaderTint')).first,
                  )
                  .decoration
              as BoxDecoration;
      final texts = [
        tester.widget<Text>(find.text('Done Before')),
        tester.widget<Text>(find.text('Not Done Yet')),
        tester.widget<Text>(find.text('5')),
      ];
      // Worst case over every page-background stop and the glass fill.
      for (final bg in g.background) {
        final base = Color.alphaBlend(g.fill, bg);
        final surface = Color.alphaBlend(tint.color!, base);
        for (final t in texts) {
          final c = contrast(t.style!.color!, surface);
          expect(c, greaterThanOrEqualTo(4.5), reason: '$brightness $bg $c');
        }
      }
      // Clearly distinct from a card: a card is just the glass fill.
      final card = Color.alphaBlend(g.fill, g.background[1]);
      final header = Color.alphaBlend(tint.color!, card);
      expect(contrast(header, card), greaterThanOrEqualTo(1.25));
      await unmount(tester);
    });
  }

  testWidgets('dragging a rectangle selects exactly the cards it touches', (
    tester,
  ) async {
    await pumpBoard(tester);
    final c = await selectTopThree(tester);
    expect(container.read(currentSelectionProvider), {
      c[0].$1,
      c[1].$1,
      c[2].$1,
    });
    await unmount(tester);
  });

  testWidgets('Ctrl-drag adds, plain drag replaces', (tester) async {
    await pumpBoard(tester);
    final c = cards(tester);
    final sel = container.read(currentSelectionProvider.notifier);
    sel.state = {c[4].$1};

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await drag(
      tester,
      Offset(50, glass(c[0].$2).top + 2),
      glass(c[1].$2).center,
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(container.read(currentSelectionProvider), {
      c[0].$1,
      c[1].$1,
      c[4].$1,
    });

    await drag(
      tester,
      Offset(50, glass(c[2].$2).top + 2),
      glass(c[3].$2).center,
    );
    expect(container.read(currentSelectionProvider), {c[2].$1, c[3].$1});
    await unmount(tester);
  });

  testWidgets('click on empty space and Escape clear the selection', (
    tester,
  ) async {
    await pumpBoard(tester);
    final c = await selectTopThree(tester);
    expect(container.read(currentSelectionProvider), hasLength(3));

    await tester.tapAt(const Offset(50, 500), kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(container.read(currentSelectionProvider), isEmpty);

    container.read(currentSelectionProvider.notifier).state = {c[0].$1};
    await tester.tapAt(const Offset(50, 500), kind: PointerDeviceKind.mouse);
    container.read(currentSelectionProvider.notifier).state = {c[0].$1};
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(container.read(currentSelectionProvider), isEmpty);
    await unmount(tester);
  });

  testWidgets('Ctrl+click toggles a card without opening the editor', (
    tester,
  ) async {
    await pumpBoard(tester);
    final c = cards(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tapAt(glass(c[1].$2).center, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 400));
    expect(container.read(currentSelectionProvider), {c[1].$1});
    expect(find.byType(Dialog), findsNothing);

    await tester.tapAt(glass(c[2].$2).center, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 400));
    expect(container.read(currentSelectionProvider), {c[1].$1, c[2].$1});

    await tester.tapAt(glass(c[1].$2).center, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(container.read(currentSelectionProvider), {c[2].$1});
    expect(find.byType(Dialog), findsNothing);
    await unmount(tester);
  });

  testWidgets('Delete key removes the whole selection; one Undo restores it', (
    tester,
  ) async {
    await pumpBoard(tester);
    final c = await selectTopThree(tester);
    final gone = {c[0].$1, c[1].$1, c[2].$1};
    expect(await edgeCount(tester), 2);

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await afterDelete(tester);
    expect(await actionIds(tester), {c[3].$1, c[4].$1});
    expect(container.read(currentSelectionProvider), isEmpty);
    expect(find.text('Deleted 3 actions'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Undo'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    final ids = await actionIds(tester);
    expect(ids.containsAll(gone), isTrue);
    expect(ids, hasLength(5));
    expect(await edgeCount(tester), 2);
    await unmount(tester);
  });

  testWidgets('context menu on a 3-selection reads Delete 3 actions', (
    tester,
  ) async {
    await pumpBoard(tester);
    final c = await selectTopThree(tester);
    await tester.tapAt(
      glass(c[1].$2).center,
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Delete 3 actions'), findsOneWidget);

    await tester.tap(find.text('Delete 3 actions'));
    await afterDelete(tester);
    expect(await actionIds(tester), {c[3].$1, c[4].$1});
    await unmount(tester);
  });

  testWidgets('right-click on an unselected card selects only that card', (
    tester,
  ) async {
    await pumpBoard(tester);
    final c = await selectTopThree(tester);
    await tester.tapAt(
      glass(c[4].$2).center,
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(container.read(currentSelectionProvider), {c[4].$1});
    expect(find.text('Delete'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pump(const Duration(milliseconds: 400));
    await unmount(tester);
  });

  testWidgets('selection drops ids that no longer exist', (tester) async {
    await pumpBoard(tester);
    container.read(currentSelectionProvider.notifier).state = {'a0', 'a1'};
    await tester.runAsync(
      () => (db.delete(db.actionsTable)..where((t) => t.id.equals('a1'))).go(),
    );
    await settle(tester);
    expect(container.read(currentSelectionProvider), {'a0'});
    await unmount(tester);
  });

  testWidgets('toolbar Delete on a card in a 3-selection removes all 3; one '
      'Undo restores them', (tester) async {
    await pumpBoard(tester);
    final c = await selectTopThree(tester);
    final gone = {c[0].$1, c[1].$1, c[2].$1};

    final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(g.removePointer);
    await g.addPointer(location: const Offset(50, 600));
    await g.moveTo(glass(c[1].$2).center);
    await tester.pump();
    expect(find.byType(GlassIconTile), findsNWidgets(12));

    await tester.tap(find.byTooltip('Delete'));
    await afterDelete(tester);
    expect(await actionIds(tester), {c[3].$1, c[4].$1});
    expect(container.read(currentSelectionProvider), isEmpty);
    expect(find.text('Deleted 3 actions'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Undo'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    final ids = await actionIds(tester);
    expect(ids.containsAll(gone), isTrue);
    expect(ids, hasLength(5));
    await unmount(tester);
  });

  testWidgets('toolbar Delete on an unselected card deletes only that card', (
    tester,
  ) async {
    await pumpBoard(tester);
    final c = await selectTopThree(tester);
    final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(g.removePointer);
    await g.addPointer(location: const Offset(50, 600));
    await g.moveTo(glass(c[4].$2).center);
    await tester.pump();
    await tester.tap(find.byTooltip('Delete'));
    await afterDelete(tester);
    expect(await actionIds(tester), {c[0].$1, c[1].$1, c[2].$1, c[3].$1});
    await unmount(tester);
  });

  testWidgets('no toolbar while a marquee is dragged over cards', (
    tester,
  ) async {
    await pumpBoard(tester);
    final c = cards(tester);
    expect(find.byType(GlassIconTile), findsNothing);
    final from = Offset(50, glass(c[0].$2).top + 2);
    final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
    await g.moveTo(glass(c[1].$2).center);
    await tester.pump();
    await g.moveTo(glass(c[2].$2).center);
    await tester.pump();
    expect(find.byType(GlassIconTile), findsNothing);
    await g.up();
    await tester.pump();
    expect(find.byType(GlassIconTile), findsNothing);
    await unmount(tester);
  });

  testWidgets(
    'first card under the header: toolbar is on screen and clickable',
    (tester) async {
      await pumpBoard(tester);
      final c = cards(tester);
      final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(g.removePointer);
      await g.addPointer(location: const Offset(50, 600));
      await g.moveTo(glass(c[0].$2).center);
      await tester.pump();
      final bar = tester.getRect(find.byType(GlassIconTile).first);
      expect(bar.top, greaterThanOrEqualTo(0));
      expect(const Rect.fromLTWH(0, 0, 1400, 900).contains(bar.center), isTrue);
      await unmount(tester);
    },
  );
}
