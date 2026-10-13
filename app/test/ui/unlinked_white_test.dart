import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/data/queries.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/urgency_colors.dart';
import 'package:livenow/ui/widgets/action_card.dart';
import 'package:livenow/ui/widgets/action_tile.dart';

/// An action without any growth direction is WHITE ("fill me in") on the
/// Current card and the All tile; a linked one gets its urgency band; while the
/// links are still loading nothing flashes white.
void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;

  Future<ActionListItem> seed(WidgetTester tester) async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    late ActionListItem item;
    await tester.runAsync(() async {
      final id =
          await ProviderContainer(
                overrides: [databaseProvider.overrideWithValue(db)],
              )
              .read(actionServiceProvider)
              .createAction(name: 'Plain action');
      item = ActionListItem.fromRow(
        await (db.select(db.actionsTable)..where((t) => t.id.equals(id)))
            .getSingle(),
      );
    });
    return item;
  }

  Future<void> pump(
    WidgetTester tester,
    Widget child,
    List<Override> overrides,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db), ...overrides],
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );
    await tester.pump();
  }

  bool hasBg(WidgetTester tester, Color color) => find
      .byWidgetPredicate((w) {
        final d = w is Container
            ? w.decoration
            : w is DecoratedBox
            ? w.decoration
            : null;
        return d is BoxDecoration && d.color == color;
      })
      .evaluate()
      .isNotEmpty;

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  final white = emptyColors(dark: false).bg;

  for (final isCard in [true, false]) {
    final kind = isCard ? 'card' : 'tile';
    Widget widgetFor(ActionListItem a) =>
        isCard ? ActionCard(action: a) : ActionTile(action: a);

    testWidgets('$kind: no direction = white', (tester) async {
      final item = await seed(tester);
      await pump(tester, widgetFor(item), [
        actionsWithDirectionsProvider.overrideWith((ref) => <String>{}),
      ]);
      expect(hasBg(tester, white), isTrue);
      await unmount(tester);
    });

    testWidgets('$kind: a linked action takes its urgency band', (
      tester,
    ) async {
      final item = await seed(tester);
      await pump(tester, widgetFor(item), [
        actionsWithDirectionsProvider.overrideWith((ref) => {item.id}),
        actionUrgencyProvider.overrideWith((ref) => {item.id: 900.0}),
      ]);
      expect(hasBg(tester, white), isFalse);
      expect(hasBg(tester, urgencyColors(900, dark: false).bg), isTrue);
      await unmount(tester);
    });

    testWidgets('$kind: nothing is white while the links load', (tester) async {
      final item = await seed(tester);
      await pump(tester, widgetFor(item), [
        actionsWithDirectionsProvider.overrideWith((ref) => null),
      ]);
      expect(hasBg(tester, white), isFalse);
      await unmount(tester);
    });
  }
}
