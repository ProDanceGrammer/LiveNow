import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/main.dart';
import 'package:livenow/ui/providers.dart';

void main() {
  setUpAll(initPostponeTimeZoneData);

  testWidgets('home shell shows all five views and opens the new-action dialog', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const LiveNowApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Operational'), findsWidgets);
    expect(find.text('TODO'), findsOneWidget);
    expect(find.text('Most Important'), findsOneWidget);
    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('Habits'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('New action'), findsOneWidget);

    // Unmount the tree (and so dispose the Drift-backed providers) while
    // still inside the test body, then advance the fake clock by a
    // non-zero amount so the zero-duration timer Drift schedules when a
    // query stream is cancelled actually fires. A duration-less pump
    // doesn't elapse fake time at all, so that timer is still "pending"
    // when flutter_test's final invariant check runs otherwise.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
