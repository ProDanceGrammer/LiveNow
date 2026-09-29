import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/widgets/action_editor.dart';

void main() {
  testWidgets('tapping a connected action opens its editor on top', (
    tester,
  ) async {
    // Tall enough that the dialog's "Connected actions" section is on screen.
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    late ActionRow current;
    await tester.runAsync(() async {
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      final service = container.read(actionServiceProvider);
      final a = await service.createAction(name: 'Current one');
      final b = await service.createAction(name: 'Next one');
      await container
          .read(dependencyServiceProvider)
          .addDependency(predecessorId: a, successorId: b);
      current = await (db.select(
        db.actionsTable,
      )..where((t) => t.id.equals(a))).getSingle();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  ActionEditorDialog.show(context, existing: current),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ActionEditorDialog), findsOneWidget);

    // Stream providers need real time to emit the edge, then a frame.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(InputChip, 'Next one'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(ActionEditorDialog), findsNWidgets(2));
    expect(find.widgetWithText(TextFormField, 'Next one'), findsOneWidget);

    // Let the second editor's streams deliver a first value before it is
    // unmounted (Riverpod rejects disposing a stream provider mid-load).
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
