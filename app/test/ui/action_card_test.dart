import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/data/queries.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/widgets/action_card.dart';

void main() {
  late AppDatabase db;
  late String actionId;

  Future<void> pumpCard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    late ActionListItem item;
    await tester.runAsync(() async {
      actionId = await ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      ).read(actionServiceProvider).createAction(name: 'Read a Bible');
      item = ActionListItem.fromRow(
        await (db.select(
          db.actionsTable,
        )..where((t) => t.id.equals(actionId))).getSingle(),
      );
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Scaffold(body: ActionCard(action: item)),
        ),
      ),
    );
  }

  Future<bool> exists(WidgetTester tester) async => (await tester.runAsync(
    () =>
        (db.select(db.actionsTable)..where((t) => t.id.equals(actionId))).get(),
  ))!.isNotEmpty;

  /// The delete resumes in the fake-async zone after its database work.
  Future<void> afterDelete(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> unmount(WidgetTester tester) async {
    // Let the card's streams deliver before they are disposed.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('trash button deletes without asking, and Undo brings it back', (
    tester,
  ) async {
    await pumpCard(tester);

    await tester.tap(find.byTooltip('Delete'));
    await afterDelete(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Deleted "Read a Bible"'), findsOneWidget);
    expect(await exists(tester), isFalse);

    await tester.runAsync(() async {
      await tester.tap(find.text('Undo'));
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    expect(await exists(tester), isTrue);
    await unmount(tester);
  });

  testWidgets('right-click opens a menu with a red Delete', (tester) async {
    await pumpCard(tester);

    await tester.tap(
      find.text('Read a Bible'),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    // The first frame only starts the open animation; the second runs it.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final item = find.widgetWithText(PopupMenuItem<String>, 'Delete');
    expect(item, findsOneWidget);
    final text = tester.widget<Text>(
      find.descendant(of: item, matching: find.text('Delete')),
    );
    expect(text.style?.color, ThemeData().colorScheme.error);

    await tester.tap(find.text('Delete'));
    await afterDelete(tester);
    expect(await exists(tester), isFalse);
    expect(find.text('Deleted "Read a Bible"'), findsOneWidget);
    await unmount(tester);
  });
}
