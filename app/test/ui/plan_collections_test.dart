import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/plan_rules.dart';
import 'package:livenow/domain/plan_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/views/calendar_view.dart';

/// Plan collections in the calendar's planning mode: showing / hiding their
/// ghosts, assigning them in the editor and the grouped Confirm dialog.
void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late PlanService plans;
  late String sport, run, cook, swim;

  Finder ghosts() => find.byWidgetPredicate((w) {
    final k = w.key;
    return k is ValueKey<String> &&
        k.value.startsWith('plan-ghost-') &&
        !k.value.startsWith('plan-ghost-handle-');
  });

  Future<void> settle(WidgetTester tester, [int ms = 300]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    resetStackedDialogsForTest();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<String> daily(String name, List<String> collections) => plans.saveItem(
    PlanItemInput(
      name: name,
      kind: PlanKind.cycle,
      startDate: planDate(2026, 1, 5),
      collectionIds: collections,
      cycle: const CycleRule(
        cycleDays: 1,
        occurrences: [
          CycleOccurrence(day: 0, startMin: 20 * 60, durationMin: 30),
        ],
      ),
    ),
  );

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys = ON;'),
      ),
    );
    addTearDown(db.close);
    plans = PlanService(db, ActionService(db));
    await tester.runAsync(() async {
      sport = await plans.saveCollection(name: 'Sport');
      run = await daily('Run', [sport]);
      swim = await daily('Swim', [sport]);
      cook = await daily('Cook', const []);
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          calendarVisibleHoursProvider.overrideWith((ref) => 24),
        ],
        child: const MaterialApp(home: Scaffold(body: CalendarView())),
      ),
    );
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('calendar-planning-toggle')));
    await settle(tester);
  }

  testWidgets('a collection checkbox shows / hides its ghosts', (tester) async {
    await mount(tester);
    expect(ghosts(), findsNWidgets(21)); // 3 items x 7 days
    expect(find.text('Collections'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('plan-bar-collections')));
    await settle(tester);
    await tester.tap(find.byKey(ValueKey('plan-collection-$sport')));
    await settle(tester);
    // Run and Swim are hidden, the item in no collection stays.
    expect(ghosts(), findsNWidgets(7));
    expect(find.textContaining('1 hidden'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('plan-collection-$sport')));
    await settle(tester);
    expect(ghosts(), findsNWidgets(21));

    await tester.tap(find.byKey(const ValueKey('plan-collections-hide-all')));
    await settle(tester);
    expect(ghosts(), findsNWidgets(7));
    await tester.tap(find.byKey(const ValueKey('plan-collections-show-all')));
    await settle(tester);
    expect(ghosts(), findsNWidgets(21));
    await unmount(tester);
  });

  testWidgets('a collection can be created and deleted with Undo', (tester) async {
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('plan-bar-collections')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('plan-collection-add')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('plan-collection-name')),
      'Summer',
    );
    await tester.tap(find.byKey(const ValueKey('plan-collection-name-save')));
    await settle(tester);
    expect(find.textContaining('Summer'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('plan-collection-delete-$sport')));
    await settle(tester);
    expect(find.byKey(ValueKey('plan-collection-$sport')), findsNothing);
    // Run and Swim stay on the calendar (no collection = always shown).
    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(find.byKey(ValueKey('plan-collection-$sport')), findsOneWidget);
    final row = (await tester.runAsync(
      () => plans.items().then((l) => l.firstWhere((r) => r.id == run)),
    ))!;
    expect(plans.decode(row).collectionIds, [sport]);
    await unmount(tester);
  });

  testWidgets('the editor puts an item into a new collection', (tester) async {
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('plan-bar-add')));
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('plan-name')), 'Gym drive');
    await tester.tap(find.byKey(const ValueKey('plan-editor-collection-new')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('plan-collection-name')),
      'Winter',
    );
    await tester.tap(find.byKey(const ValueKey('plan-collection-name-save')));
    await settle(tester);
    // The existing one can be ticked too.
    await tester.tap(find.byKey(ValueKey('plan-editor-collection-$sport')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('plan-save')));
    await settle(tester);

    final rows = (await tester.runAsync(() => plans.items()))!;
    final gym = plans.decode(rows.firstWhere((r) => r.name == 'Gym drive'));
    final winter = (await tester.runAsync(() => plans.collections()))!
        .firstWhere((c) => c.name == 'Winter');
    expect(gym.collectionIds.toSet(), {winter.id, sport});
    await unmount(tester);
  });

  testWidgets('the confirm dialog groups items by collection', (tester) async {
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('plan-bar-confirm')));
    await settle(tester);

    expect(find.byKey(ValueKey('plan-confirm-collection-$sport')), findsOneWidget);
    expect(find.byKey(const ValueKey('plan-confirm-collection-none')), findsOneWidget);
    bool on(String key) =>
        tester.widget<CheckboxListTile>(find.byKey(ValueKey(key))).value == true;
    expect(on('plan-confirm-item-$run'), isTrue);

    // The group checkbox unticks both its items, the loose one stays ticked.
    await tester.tap(find.byKey(ValueKey('plan-confirm-collection-$sport')));
    await settle(tester);
    expect(on('plan-confirm-item-$run'), isFalse);
    expect(on('plan-confirm-item-$swim'), isFalse);
    expect(on('plan-confirm-item-$cook'), isTrue);

    await tester.tap(find.byKey(ValueKey('plan-confirm-collection-$sport')));
    await settle(tester);
    expect(on('plan-confirm-item-$run'), isTrue);
    await unmount(tester);
  });

  testWidgets('Select all / None tick or untick every item; Create needs one', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('plan-bar-confirm')));
    await settle(tester);
    bool on(String id) => tester
        .widget<CheckboxListTile>(find.byKey(ValueKey('plan-confirm-item-$id')))
        .value == true;
    FilledButton create() =>
        tester.widget<FilledButton>(find.byKey(const ValueKey('plan-confirm')));

    await tester.tap(find.byKey(const ValueKey('plan-confirm-none')));
    await settle(tester);
    expect([on(run), on(swim), on(cook)], [false, false, false]);
    expect(create().onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('plan-confirm-all')));
    await settle(tester);
    expect([on(run), on(swim), on(cook)], [true, true, true]);
    expect(create().onPressed, isNotNull);
    await unmount(tester);
  });
}
