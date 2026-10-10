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

  testWidgets(
    'home shell shows all destinations and opens the new-action dialog',
    (tester) async {
      // A desktop-sized window (below 900 px the phone layout is used).
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const LiveNowApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Current Actions is the default view.
      // (once as the page title, once as the Actions section's switch label)
      expect(find.text('Current Actions'), findsNWidgets(2));
      expect(find.text('Actions'), findsOneWidget);
      expect(find.text('Current'), findsNothing);
      expect(find.text('Operational'), findsNothing);
      expect(find.text('TODO'), findsNothing);
      expect(find.text('Most Important'), findsNothing);
      expect(find.text('All'), findsOneWidget); // third Actions tab
      expect(find.text('Growth directions'), findsOneWidget);
      expect(find.text('Templates'), findsOneWidget);

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
    },
  );
}
