import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/time_codec.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/views/current_actions_view.dart';

void main() {
  setUpAll(initPostponeTimeZoneData);

  testWidgets('board shows the total, a page of cards and Show more', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.runAsync(() async {
      await db.batch(
        (b) => b.insertAll(db.actionsTable, [
          for (var i = 0; i < 120; i++)
            ActionsTableCompanion.insert(
              id: 'a$i',
              name: 'Task $i',
              done: const Value(false),
              createdAt: 't',
              updatedAt: 't',
            ),
        ]),
      );
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: Scaffold(body: CurrentActionsView())),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    // The header no longer shows a count.
    expect(find.text('120'), findsNothing);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CurrentActionsView)),
    );
    expect(container.read(currentNotDoneProvider).requireValue, hasLength(100));

    // Scroll to the end of the right column and press Show more.
    final showMore = find.text('Show more');
    await tester.scrollUntilVisible(
      showMore,
      600,
      scrollable: find.byType(Scrollable).last,
      maxScrolls: 200,
    );
    await tester.tap(showMore);
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(container.read(currentNotDoneProvider).requireValue, hasLength(120));
    expect(find.text('120'), findsNothing);
    expect(find.text('Show more'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  test(
    'a timed card moves to Done Before when the board clock passes its end',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final t0 = DateTime.utc(2026, 1, 1, 12);
      await db
          .into(db.actionsTable)
          .insert(
            ActionsTableCompanion.insert(
              id: 'a',
              name: 'Timed',
              startAt: Value(dateTimeToDb(t0.add(const Duration(minutes: 5)))),
              endAt: Value(dateTimeToDb(t0.add(const Duration(minutes: 30)))),
              createdAt: 't',
              updatedAt: 't',
            ),
          );
      final clock = StateProvider<DateTime>((ref) => t0);
      final c = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          currentBoardNowProvider.overrideWith((ref) => ref.watch(clock)),
        ],
      );
      addTearDown(c.dispose);
      Future<void> settle() =>
          Future<void>.delayed(const Duration(milliseconds: 120));
      final subs = [
        c.listen(currentNotDoneProvider, (_, _) {}),
        c.listen(currentDoneProvider, (_, _) {}),
        c.listen(currentNotDoneCountProvider, (_, _) {}),
        c.listen(currentDoneCountProvider, (_, _) {}),
      ];
      addTearDown(() {
        for (final s in subs) {
          s.close();
        }
      });
      await settle();
      expect(c.read(currentNotDoneProvider).requireValue, hasLength(1));
      expect(c.read(currentDoneProvider).requireValue, isEmpty);
      expect(c.read(currentNotDoneCountProvider).requireValue, 1);

      c.read(clock.notifier).state = t0.add(const Duration(minutes: 31));
      await settle();
      expect(c.read(currentNotDoneProvider).requireValue, isEmpty);
      expect(c.read(currentDoneProvider).requireValue, hasLength(1));
      expect(c.read(currentDoneCountProvider).requireValue, 1);
      expect(c.read(currentNotDoneCountProvider).requireValue, 0);
    },
  );
}
