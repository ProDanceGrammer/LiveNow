import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/growth_rules.dart';
import 'package:livenow/domain/metric_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/screens/growth_directions_screen.dart';

void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> animate(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> openBravo(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.runAsync(() async {
      final m = MetricService(db);
      final goal = await m.saveMetric(name: 'Goal', kind: MetricKind.boolean);
      await m.saveMetric(
        name: 'Bravo',
        kind: MetricKind.boolean,
        leadsToIds: [goal],
      );
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: GrowthDirectionsScreen()),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('List'));
    await animate(tester);
    await tester.tap(find.text('Bravo'));
    await animate(tester);
    await settle(tester);
  }

  String nameField(WidgetTester tester) => tester
      .widget<TextFormField>(find.byType(TextFormField).first)
      .controller!
      .text;

  testWidgets('clicking a Leads-to chip opens that direction on top', (
    tester,
  ) async {
    await openBravo(tester);
    expect(nameField(tester), 'Bravo');
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.widgetWithText(InputChip, 'Goal'));
    await animate(tester);
    await settle(tester);

    // Stacked: two dialogs, the top one shows the related direction.
    expect(find.byType(AlertDialog, skipOffstage: false), findsNWidgets(2));
    final top = find.byType(AlertDialog).last;
    expect(
      tester
          .widget<TextFormField>(
            find
                .descendant(of: top, matching: find.byType(TextFormField))
                .first,
          )
          .controller!
          .text,
      'Goal',
    );

    await tester.tap(find.descendant(of: top, matching: find.text('Cancel')));
    await animate(tester);
    expect(nameField(tester), 'Bravo');
    await unmount(tester);
  });

  testWidgets('the chip x still removes the relation', (tester) async {
    await openBravo(tester);
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(InputChip, 'Goal'),
        matching: find.byType(Icon),
      ),
    );
    await tester.pump();
    expect(find.widgetWithText(InputChip, 'Goal'), findsNothing);
    expect(find.byType(AlertDialog), findsOneWidget);
    await unmount(tester);
  });
}
