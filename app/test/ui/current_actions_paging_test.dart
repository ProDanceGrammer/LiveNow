import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

    // Header shows the TOTAL (120), not the page size.
    expect(find.text('120'), findsOneWidget);
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
    expect(find.text('120'), findsOneWidget);
    expect(find.text('Show more'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
