import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/data/reminders/local_notifications_sink.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/main.dart';
import 'package:livenow/ui/providers.dart';

/// The Android port: the system holds reminders there (like iOS / macOS), and the
/// Back button steps out of a section before it leaves the app.
void main() {
  setUpAll(initPostponeTimeZoneData);

  test('the system holds the reminders on iOS, macOS and Android only', () {
    expect(LocalNotificationsSink.systemHoldsReminders(TargetPlatform.android), isTrue);
    expect(LocalNotificationsSink.systemHoldsReminders(TargetPlatform.iOS), isTrue);
    expect(LocalNotificationsSink.systemHoldsReminders(TargetPlatform.macOS), isTrue);
    expect(LocalNotificationsSink.systemHoldsReminders(TargetPlatform.windows), isFalse);
    expect(LocalNotificationsSink.systemHoldsReminders(TargetPlatform.linux), isFalse);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpPhone(WidgetTester tester) async {
    // A portrait phone: the bottom navigation bar (800x600 would be landscape).
    tester.view.physicalSize = const Size(400, 800);
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
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Finder bar(String label) => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );

  testWidgets('Back leaves Budget for the Actions section', (
    tester,
  ) async {
    await pumpPhone(tester);
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.tap(bar('Budget'));
    await settle(tester);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );

    await tester.binding.handlePopRoute(); // the Android Back button
    await settle(tester);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
    expect(find.text('Current Actions'), findsWidgets);
    await unmount(tester);
  });
}
