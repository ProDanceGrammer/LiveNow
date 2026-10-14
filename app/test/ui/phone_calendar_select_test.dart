import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/main.dart';
import 'package:livenow/ui/calendar_selection.dart';
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/sync_providers.dart';

/// Phone calendar (touch): a plain tap never selects (it opens the editor), a
/// long-press selects, holding twice as long arms the move, and once something is
/// selected a tap adds / removes events.
void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late String idA, idB;

  Future<void> settle(WidgetTester tester, [int ms = 600]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpPhone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final service = ActionService(db);
    final now = DateTime.now();
    await tester.runAsync(() async {
      idA = await service.createAction(
        name: 'Alpha block',
        startAt: now.subtract(const Duration(minutes: 30)),
        endAt: now.add(const Duration(minutes: 30)),
      );
      idB = await service.createAction(
        name: 'Beta block',
        startAt: now.subtract(const Duration(hours: 3)),
        endAt: now.subtract(const Duration(hours: 2)),
      );
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          syncRoleProvider.overrideWithValue(SyncRole.client),
        ],
        child: const LiveNowApp(),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('actions-switch')),
        matching: find.text('Calendar'),
      ),
    );
    await settle(tester, 400);
  }

  Future<void> unmount(WidgetTester tester) async {
    resetStackedDialogsForTest();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Set<String> selection(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first),
      ).read(calendarSelectionProvider);

  Future<void> longPress(WidgetTester tester, Finder f, int ms) async {
    final g = await tester.startGesture(tester.getCenter(f));
    await tester.pump(Duration(milliseconds: ms));
    await g.up();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<DateTime> startOf(WidgetTester tester, String id) async {
    final row = (await tester.runAsync(
      () => (db.select(db.actionsTable)..where((t) => t.id.equals(id))).getSingle(),
    ))!;
    return DateTime.parse(row.startAt!);
  }

  testWidgets('a plain tap opens the editor and selects nothing', (tester) async {
    await pumpPhone(tester);
    await tester.tap(find.textContaining('Alpha block'));
    await settle(tester, 500);
    expect(find.text('Edit action'), findsOneWidget);
    expect(selection(tester), isEmpty);
    await unmount(tester);
  });

  testWidgets('a long-press selects the event and shows the bulk bar', (
    tester,
  ) async {
    await pumpPhone(tester);
    await longPress(tester, find.textContaining('Alpha block'), 650);
    expect(selection(tester), {idA});
    expect(find.byKey(const ValueKey('calendar-bulk-bar')), findsOneWidget);
    // Held 650 ms only: selected, but it was not pulled anywhere.
    expect(find.text('Edit action'), findsNothing);
    await unmount(tester);
  });

  testWidgets('with something selected a tap adds and removes events', (
    tester,
  ) async {
    await pumpPhone(tester);
    await longPress(tester, find.textContaining('Alpha block'), 650);
    expect(selection(tester), {idA});

    await tester.tap(find.textContaining('Beta block'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(selection(tester), {idA, idB});
    // No editor opened by a tap that toggled.
    expect(find.text('Edit action'), findsNothing);

    await tester.tap(find.textContaining('Beta block'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(selection(tester), {idA});
    await unmount(tester);
  });

  testWidgets('holding twice as long arms the move: the block follows the finger', (
    tester,
  ) async {
    await pumpPhone(tester);
    final before = await startOf(tester, idA);
    final g = await tester.startGesture(
      tester.getCenter(find.textContaining('Alpha block')),
    );
    await tester.pump(const Duration(milliseconds: 1100));
    await g.moveBy(const Offset(0, 80));
    await tester.pump(const Duration(milliseconds: 100));
    await g.moveBy(const Offset(0, 40));
    await tester.pump(const Duration(milliseconds: 100));
    await g.up();
    await settle(tester, 400);
    final after = await startOf(tester, idA);
    expect(after.isAfter(before), isTrue, reason: 'pulled down = later');
    expect(selection(tester), contains(idA));
    await unmount(tester);
  });

  testWidgets('moving the finger after only a long-press does not move the block', (
    tester,
  ) async {
    await pumpPhone(tester);
    final before = await startOf(tester, idA);
    final g = await tester.startGesture(
      tester.getCenter(find.textContaining('Alpha block')),
    );
    await tester.pump(const Duration(milliseconds: 650));
    await g.moveBy(const Offset(0, 80));
    await tester.pump(const Duration(milliseconds: 100));
    await g.up();
    await settle(tester, 400);
    expect(await startOf(tester, idA), before);
    expect(selection(tester), {idA});
    await unmount(tester);
  });
}
