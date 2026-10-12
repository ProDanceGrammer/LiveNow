import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/main.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/sync_providers.dart';
import 'package:livenow/ui/widgets/quick_time_edit_dialog.dart';

/// Round 3 (12.10.2026): the end follows the start.
void main() {
  setUpAll(initPostponeTimeZoneData);

  Future<void> pump(
    WidgetTester tester,
    AppDatabase db,
    Widget home, {
    Size size = const Size(1400, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          syncRoleProvider.overrideWithValue(SyncRole.client),
        ],
        child: MaterialApp(home: home),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) async {
    resetStackedDialogsForTest();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('time dialog: moving the start carries the end (same length)', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    TimeEditResult? got;
    // 22:00-23:00 Istanbul (UTC+3) on 12 Oct 2026, with 19 s extra on the end.
    final start = DateTime.utc(2026, 10, 12, 19);
    final end = DateTime.utc(2026, 10, 12, 20, 0, 19);
    await pump(
      tester,
      db,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async =>
              got = await QuickTimeEditDialog.pick(context, start: start, end: end),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Select the hour segment of Start and lower it by one hour.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(got?.start, DateTime.utc(2026, 10, 12, 18));
    expect(got?.end, DateTime.utc(2026, 10, 12, 19, 0, 19));
    await unmount(tester);
  });

  testWidgets('calendar label shows the real end of a 3 minute action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    // 12:00 Istanbul today for 3 min 19 s: drawn 10 min tall, labelled 12:03.
    final today = DateTime.now().toUtc().add(const Duration(hours: 3));
    final start = DateTime.utc(today.year, today.month, today.day, 9);
    await tester.runAsync(
      () => ActionService(db).createAction(
        name: 'Short one',
        startAt: start,
        endAt: start.add(const Duration(minutes: 3, seconds: 19)),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          syncRoleProvider.overrideWithValue(SyncRole.host),
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
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('12:00–12:03', findRichText: true), findsOneWidget);
    expect(find.textContaining('12:00–12:10', findRichText: true), findsNothing);
    await unmount(tester);
  });

  testWidgets('landscape phone: side rail instead of title row and bottom bar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(812, 375);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          syncRoleProvider.overrideWithValue(SyncRole.client),
        ],
        child: const LiveNowApp(),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('phone-rail')), findsOneWidget);
    expect(find.byKey(const ValueKey('phone-nav')), findsNothing);
    expect(find.byType(AppBar), findsNothing);
    // The rail switches sections.
    await tester.tap(find.byKey(const ValueKey('phone-rail-2')));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Overview'), findsWidgets);
    await unmount(tester);
  });
}
