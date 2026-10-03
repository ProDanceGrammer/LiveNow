import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/all_actions_view_rules.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/views/all_actions_view.dart';

String _doc(String text) =>
    '{"document":{"type":"page","children":[{"type":"paragraph",'
    '"data":{"delta":[{"insert":"$text"}]}}]}}';

void main() {
  testWidgets('default order, sort chips, filters and the Notes flag', (
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
      final a = await s.createAction(name: 'Alpha', notes: _doc('Buy MILK'));
      final b = await s.createAction(name: 'Beta');
      await s.createAction(name: 'Gamma');
      // Pin the edit order: Beta oldest, Alpha newest.
      Future<void> stamp(String id, String ts) =>
          (db.update(db.actionsTable)..where((t) => t.id.equals(id))).write(
            ActionsTableCompanion(updatedAt: Value(ts)),
          );
      await stamp(b, '2026-01-01T00:00:00.000000Z');
      await stamp(a, '2026-03-01T00:00:00.000000Z');
    });

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
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

    double y(String name) => tester.getTopLeft(find.text(name)).dy;

    await settle();
    // Default: last edited first (Gamma just created, then Alpha, Beta oldest).
    expect(y('Gamma') < y('Alpha'), isTrue);
    expect(y('Alpha') < y('Beta'), isTrue);

    // Open the panel; the default chip shows and toggles to ascending.
    await tester.tap(find.byKey(const ValueKey('allOptionsToggle')));
    await settle();
    expect(find.byKey(const ValueKey('sortChip-lastEdited')), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('sortChip-lastEdited')),
        matching: find.text('Last edited'),
      ),
    );
    await settle();
    expect(container.read(allActionsSortProvider), [
      const SortKey(SortField.lastEdited),
    ]);
    expect(y('Beta') < y('Alpha'), isTrue);

    // Remove the chip's sort and add a name sort through the menu.
    container.read(allActionsSortProvider.notifier).state = [
      const SortKey(SortField.name, ascending: false),
    ];
    await settle();
    expect(y('Gamma') < y('Beta'), isTrue);
    expect(y('Beta') < y('Alpha'), isTrue);

    // Name filter in the panel.
    await tester.enterText(find.byKey(const ValueKey('filterName')), 'mm');
    await settle();
    expect(find.text('Gamma'), findsOneWidget);
    expect(find.text('Alpha'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('filtersReset')));
    await settle();
    expect(find.text('Alpha'), findsOneWidget);

    // Notes search: off -> no hit, on -> Alpha only.
    await tester.enterText(
      find.byKey(const ValueKey('allSearchField')),
      'milk',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await settle();
    expect(find.text('No matching actions.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('searchFlagNotes')));
    await settle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
