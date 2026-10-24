import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/open_entity.dart';
import 'package:livenow/ui/providers.dart';

/// An opener asked for a row that is gone (deleted here or on another device
/// while a chip or a search hit was on screen) shows a toast, never throws.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUpAll(initPostponeTimeZoneData);

  testWidgets('opening a missing action / direction toasts instead of failing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      await tester.pump(const Duration(milliseconds: 1));
      await db.close();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => Column(
                children: [
                  TextButton(
                    key: const ValueKey<String>('open-action'),
                    onPressed: () => openActionById(context, ref, 'ghost'),
                    child: const Text('action'),
                  ),
                  TextButton(
                    key: const ValueKey<String>('open-direction'),
                    onPressed: () => openDirectionById(context, ref, 'ghost'),
                    child: const Text('direction'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    Future<void> tapAndSettle(String key) async {
      await tester.tap(find.byKey(ValueKey<String>(key)));
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await tapAndSettle('open-action');
    expect(find.textContaining('That action no longer exists'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // The toast times out on its own.
    await tester.pump(const Duration(seconds: 10));
    await tapAndSettle('open-direction');
    expect(
      find.textContaining('That growth direction no longer exists'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 10));
  });
}
