import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/data/queries.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/widgets/action_card.dart';
import 'package:livenow/ui/widgets/round_check.dart';
import 'package:livenow/ui/widgets/glass_icon_tile.dart';

void main() {
  late AppDatabase db;
  late String actionId;

  Future<void> pumpCard(WidgetTester tester, {bool allDay = false}) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    late ActionListItem item;
    await tester.runAsync(() async {
      actionId =
          await ProviderContainer(
                overrides: [databaseProvider.overrideWithValue(db)],
              )
              .read(actionServiceProvider)
              .createAction(name: 'Read a Bible', isAllDay: allDay);
      item = ActionListItem.fromRow(
        await (db.select(
          db.actionsTable,
        )..where((t) => t.id.equals(actionId))).getSingle(),
      );
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Scaffold(body: ActionCard(action: item)),
        ),
      ),
    );
  }

  /// Moves a mouse pointer onto the card (a real hover move, which is what
  /// shows its toolbar). The caller keeps the gesture to move it further.
  Future<TestGesture> hoverCard(WidgetTester tester) async {
    final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await g.addPointer(location: const Offset(2, 2));
    addTearDown(g.removePointer);
    await g.moveTo(tester.getCenter(find.text('Read a Bible')));
    await tester.pump();
    return g;
  }

  int tiles(WidgetTester tester) =>
      tester.widgetList(find.byType(GlassIconTile)).length;

  Future<bool> exists(WidgetTester tester) async => (await tester.runAsync(
    () =>
        (db.select(db.actionsTable)..where((t) => t.id.equals(actionId))).get(),
  ))!.isNotEmpty;

  /// The delete resumes in the fake-async zone after its database work.
  Future<void> afterDelete(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> unmount(WidgetTester tester) async {
    // Let the card's streams deliver before they are disposed.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('trash button deletes without asking, and Undo brings it back', (
    tester,
  ) async {
    await pumpCard(tester);
    await hoverCard(tester);

    await tester.tap(find.byTooltip('Delete'));
    await afterDelete(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Deleted "Read a Bible"'), findsOneWidget);
    expect(await exists(tester), isFalse);

    await tester.runAsync(() async {
      await tester.tap(find.text('Undo'));
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    expect(await exists(tester), isTrue);
    await unmount(tester);
  });

  testWidgets('all-day card has a checkbox that ticks and unticks', (
    tester,
  ) async {
    await pumpCard(tester, allDay: true);
    final box = find.byKey(const ValueKey('allDayCheckbox'));
    expect(box, findsOneWidget);
    expect(tester.widget<RoundCheck>(box).value, isFalse);

    Future<bool> doneInDb() async => (await tester.runAsync(
      () => (db.select(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).getSingle(),
    ))!.done;

    await tester.runAsync(() async {
      await tester.tap(box);
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    expect(await doneInDb(), isTrue);
    await unmount(tester);
  });

  testWidgets('timed card has no checkbox', (tester) async {
    await pumpCard(tester);
    expect(find.byType(RoundCheck), findsNothing);
    await unmount(tester);
  });

  testWidgets('right-click opens a menu with a red Delete', (tester) async {
    await pumpCard(tester);

    await tester.tap(
      find.text('Read a Bible'),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    // The first frame only starts the open animation; the second runs it.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final item = find.widgetWithText(PopupMenuItem<String>, 'Delete');
    expect(item, findsOneWidget);
    final text = tester.widget<Text>(
      find.descendant(of: item, matching: find.text('Delete')),
    );
    expect(text.style?.color, ThemeData().colorScheme.error);

    await tester.tap(find.text('Delete'));
    await afterDelete(tester);
    expect(await exists(tester), isFalse);
    expect(find.text('Deleted "Read a Bible"'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('quick action bar keeps every button, in order', (tester) async {
    await pumpCard(tester);
    await hoverCard(tester);
    final tips = tester
        .widgetList<Tooltip>(find.byType(Tooltip))
        .map((t) => t.message)
        .toList();
    expect(tips, [
      'Start',
      'Finish',
      'Continue with same action',
      'Prolong 30 min',
      'Postpone +1 hour',
      'Postpone +5 hours',
      'Postpone: after work (18:00)',
      'Postpone: tomorrow morning',
      'Postpone: next working morning',
      'Postpone: next week',
      'Postpone: next Monday morning',
      'Delete',
    ]);
    await unmount(tester);
  });

  testWidgets('Start and Finish buttons call the service', (tester) async {
    await pumpCard(tester);
    await hoverCard(tester);
    Future<ActionRow> row() async => (await tester.runAsync(
      () => (db.select(
        db.actionsTable,
      )..where((t) => t.id.equals(actionId))).getSingle(),
    ))!;

    expect((await row()).startAt, isNull);
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Start'));
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pump(const Duration(milliseconds: 400));
    expect((await row()).startAt, isNotNull);

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Finish'));
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pump(const Duration(milliseconds: 400));
    expect((await row()).done, isTrue);
    await unmount(tester);
  });

  testWidgets('nothing hovered builds no buttons; hover shows the toolbar', (
    tester,
  ) async {
    await pumpCard(tester);
    expect(tiles(tester), 0);
    expect(find.byType(Tooltip), findsNothing);

    final g = await hoverCard(tester);
    expect(tiles(tester), 12);

    // Onto the toolbar itself: it stays.
    await g.moveTo(tester.getCenter(find.byTooltip('Finish')));
    await tester.pump();
    expect(tiles(tester), 12);

    // Away from both: it goes.
    await g.moveTo(const Offset(2, 700));
    await tester.pump();
    expect(tiles(tester), 0);
    await unmount(tester);
  });

  testWidgets('the card is compact: no button row inside it', (tester) async {
    await pumpCard(tester);
    expect(tester.getSize(find.byType(ActionCard)).height, lessThan(70));
    await unmount(tester);
  });

  testWidgets('a bare enter without a hover move does not show it', (
    tester,
  ) async {
    await pumpCard(tester);
    final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(g.removePointer);
    await g.addPointer(location: tester.getCenter(find.text('Read a Bible')));
    await tester.pump();
    expect(tiles(tester), 0);
    await g.moveBy(const Offset(3, 0));
    await tester.pump();
    expect(tiles(tester), 12);
    await unmount(tester);
  });

  testWidgets('pressing on the card hides the toolbar until the next move', (
    tester,
  ) async {
    await pumpCard(tester);
    final g = await hoverCard(tester);
    expect(tiles(tester), 12);
    // Ctrl-less press on the time-less card body opens the editor dialog in
    // the real app; here we only check the toolbar goes away on press.
    await g.down(tester.getCenter(find.text('Read a Bible')));
    await tester.pump();
    expect(tiles(tester), 0);
    await g.up();
    await tester.pump(const Duration(milliseconds: 400));
    await unmount(tester);
  });

  testWidgets('Continue works from the toolbar', (tester) async {
    await pumpCard(tester);
    await hoverCard(tester);
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Continue with same action'));
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pump(const Duration(milliseconds: 400));
    final names = (await tester.runAsync(
      () => db.select(db.actionsTable).get(),
    ))!.map((a) => a.name).toList()..sort();
    expect(names, ['[#1] Read a Bible', '[#2] Read a Bible']);
    await unmount(tester);
  });

  testWidgets('only one toolbar when moving between two cards', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    late List<ActionListItem> items;
    await tester.runAsync(() async {
      final c = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      final svc = c.read(actionServiceProvider);
      await svc.createAction(name: 'First');
      await svc.createAction(name: 'Second');
      items = [
        for (final r in await db.select(db.actionsTable).get())
          ActionListItem.fromRow(r),
      ]..sort((a, b) => a.name.compareTo(b.name));
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                // Room above the first card so its toolbar sits above it.
                const SizedBox(height: 100),
                for (final i in items)
                  ActionCard(key: ValueKey(i.id), action: i),
              ],
            ),
          ),
        ),
      ),
    );
    final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await g.addPointer(location: const Offset(2, 2));
    addTearDown(g.removePointer);
    await g.moveTo(tester.getCenter(find.text('First')));
    await tester.pump();
    expect(tiles(tester), 12);
    await g.moveTo(tester.getCenter(find.text('Second')));
    await tester.pump();
    expect(tiles(tester), 12);
    await g.moveTo(const Offset(2, 700));
    await tester.pump();
    expect(tiles(tester), 0);
    await unmount(tester);
  });
  testWidgets('direction emojis show bottom-right, beside the time line', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final withTime = ActionListItem(
      id: 'a1',
      name: 'Timed',
      done: false,
      isAllDay: false,
      startAt: DateTime.utc(2026, 1, 5, 9),
      endAt: DateTime.utc(2026, 1, 5, 10),
    );
    final bare = ActionListItem(
      id: 'a2',
      name: 'Bare',
      done: false,
      isAllDay: true,
    );
    final plain = ActionListItem(
      id: 'a3',
      name: 'Plain',
      done: false,
      isAllDay: true,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          actionDirectionIconsProvider.overrideWithValue({
            'a1': '\u{1F4AA}\u{1F4DA}',
            'a2': '\u{1F3C3}',
          }),
          actionDirectionNamesProvider.overrideWithValue({
            'a1': ['Fitness and reading'],
            'a2': ['Running'],
          }),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                ActionCard(action: withTime),
                ActionCard(action: bare),
                ActionCard(action: plain),
              ],
            ),
          ),
        ),
      ),
    );
    final timed = find.text('\u{1F4AA}\u{1F4DA}');
    expect(timed, findsOneWidget);
    expect(find.text('\u{1F3C3}'), findsOneWidget);
    // Right half of the card, same row as the time label.
    final card = tester.getRect(find.byType(ActionCard).first);
    expect(tester.getCenter(timed).dx, greaterThan(card.center.dx));
    expect(card.height, lessThan(80));
    // Hovering the emoji shows the direction's name as a tooltip.
    expect(find.text('Running'), findsNothing);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('\u{1F3C3}')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Running'), findsOneWidget);
    await mouse.moveTo(const Offset(1300, 850));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Running'), findsNothing);
    // The icon-less all-day card has no second row at all.
    expect(
      tester.getSize(find.byType(ActionCard).last).height,
      lessThan(tester.getSize(find.byType(ActionCard).at(1)).height),
    );
    await unmount(tester);
  });
}
