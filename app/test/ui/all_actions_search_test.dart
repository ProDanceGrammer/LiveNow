import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/views/all_actions_view.dart';

void main() {
  testWidgets('search filters names case-insensitively incl. Cyrillic', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.runAsync(() async {
      final c = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      final s = c.read(actionServiceProvider);
      await s.createAction(name: 'Купить МОЛОКО');
      await s.createAction(name: 'Сон');
      await s.createAction(name: 'Read a Bible');
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: Scaffold(body: AllActionsView())),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    expect(find.text('Сон'), findsOneWidget);
    expect(find.text('Read a Bible'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('allSearchField')),
      'молоко',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await settle();
    expect(find.text('Купить МОЛОКО'), findsOneWidget);
    expect(find.text('Сон'), findsNothing);
    expect(find.text('Read a Bible'), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('allSearchField')), 'zzz');
    await tester.pump(const Duration(milliseconds: 300));
    await settle();
    expect(find.text('No matching actions.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('allSearchClear')));
    await settle();
    expect(find.text('Сон'), findsOneWidget);
    expect(find.text('Read a Bible'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
