import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/growth_rules.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/widgets/action_editor.dart';
import 'package:livenow/ui/widgets/growth_direction_dialog.dart';
import 'package:livenow/ui/widgets/param_icons.dart';
import 'package:livenow/ui/widgets/section_block.dart';

/// The growth direction dialog layout: three blocks, Depends on | Leads to
/// side by side with the + at the right of each title, and the linked actions
/// as a list sorted by distance from now.
void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late ProviderContainer seed;

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> openDialog(WidgetTester tester, String metricId) async {
    final m = (await tester.runAsync(
      () => (db.select(
        db.metricsTable,
      )..where((t) => t.id.equals(metricId))).getSingle(),
    ))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => GrowthDirectionDialog.show(
                  context,
                  existing: GrowthMetric.fromRow(m),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
  }

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('three blocks, two columns with + at the right of the titles, '
      'linked actions sorted by distance', (tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(resetStackedDialogsForTest);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    seed = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(seed.dispose);

    final now = DateTime.now().toUtc();
    late String metricId;
    await tester.runAsync(() async {
      metricId = await seed
          .read(metricServiceProvider)
          .saveMetric(
            name: 'Stay fit',
            kind: MetricKind.count,
            window: MetricWindow.week,
          );
      final svc = seed.read(actionServiceProvider);
      Future<void> make(String name, Duration? offset) => svc.createAction(
        name: name,
        metricIds: [metricId],
        startAt: offset == null ? null : now.add(offset),
        endAt: offset == null
            ? null
            : now.add(offset + const Duration(hours: 1)),
      );
      await make('Far future', const Duration(days: 5));
      await make('No time', null);
      await make('Near past', const Duration(hours: -2));
      await make('Mid future', const Duration(days: 1));
      await make('Far past', const Duration(days: -3));
    });
    await openDialog(tester, metricId);

    expect(find.byType(SectionBlock), findsNWidgets(3));
    final dialog = tester.getSize(find.byType(AlertDialog));
    expect(dialog.width, greaterThanOrEqualTo(720));

    // Two columns, titles on the same row, + at the right of each title.
    final dep = tester.getRect(find.text('Depends on'));
    final leads = tester.getRect(find.text('Leads to'));
    expect(leads.left, greaterThan(dep.right));
    expect((leads.top - dep.top).abs(), lessThan(2));
    final plus = find.byTooltip('Add…');
    expect(plus, findsNWidgets(2));
    final p0 = tester.getRect(plus.at(0)), p1 = tester.getRect(plus.at(1));
    expect(p0.left, greaterThanOrEqualTo(dep.right));
    expect(p1.left, greaterThanOrEqualTo(leads.right));
    expect(p1.left, greaterThan(p0.right));
    expect(find.text('Add…'), findsNothing); // no text button below the chips

    // Linked actions: pure distance from now, no-time last.
    expect(find.text('Linked actions (5)'), findsOneWidget);
    final names = [
      'Near past',
      'Mid future',
      'Far past',
      'Far future',
      'No time',
    ];
    final ys = [for (final n in names) tester.getTopLeft(find.text(n)).dy];
    final sortedYs = [...ys]..sort();
    expect(ys, sortedYs);
    expect(find.text('No time'), findsOneWidget);
    // Rows show a short schedule such as "3 Oct 13:00-14:00".
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Near past'),
        matching: find.textContaining(RegExp(r'\d{1,2} \w{3}.* \d\d:\d\d-')),
      ),
      findsOneWidget,
    );

    // Tap opens the action's editor on top.
    await tester.tap(find.widgetWithText(ListTile, 'Mid future'));
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    expect(find.byType(ActionEditorDialog), findsOneWidget);
    await teardown(tester);
  });

  testWidgets('link with +, unlink with x, info row shows five icons', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(resetStackedDialogsForTest);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    seed = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(seed.dispose);

    late String metricId, actionId;
    await tester.runAsync(() async {
      metricId = await seed
          .read(metricServiceProvider)
          .saveMetric(
            name: 'Stay fit',
            kind: MetricKind.count,
            window: MetricWindow.week,
          );
      actionId = await seed
          .read(actionServiceProvider)
          .createAction(name: 'Go running');
    });
    await openDialog(tester, metricId);

    // Info row (count direction): five icons with tooltips, numbers as text.
    for (final t in [
      'Weight',
      'Level',
      'Progress',
      'Urgency to Keep in Balance',
      'Fact: reached so far',
    ]) {
      expect(find.byTooltip(t), findsWidgets, reason: t);
    }
    expect(find.byType(ParamIcon), findsNWidgets(5));
    expect(find.byKey(const ValueKey('dialogProgressBar')), findsOneWidget);
    expect(find.text('0.0%'), findsOneWidget);

    expect(find.text('Linked actions (0)'), findsOneWidget);
    await tester.tap(find.byTooltip('Link an action'));
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    await tester.tap(find.widgetWithText(ListTile, 'Go running'));
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    expect(find.text('Linked actions (1)'), findsOneWidget);
    expect(find.byKey(ValueKey('linked-action-$actionId')), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('unlink-action-$actionId')));
    await tester.pump(const Duration(milliseconds: 100));
    await settle(tester);
    expect(find.text('Linked actions (0)'), findsOneWidget);
    expect(find.byKey(ValueKey('linked-action-$actionId')), findsNothing);
    await teardown(tester);
  });

  Future<String> seedMetric(
    WidgetTester tester,
    MetricKind kind, {
    bool doneAction = false,
  }) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(resetStackedDialogsForTest);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    seed = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(seed.dispose);
    late String metricId;
    await tester.runAsync(() async {
      metricId = await seed
          .read(metricServiceProvider)
          .saveMetric(name: 'Stay fit', kind: kind, window: MetricWindow.week);
      if (doneAction) {
        final now = DateTime.now().toUtc();
        await seed
            .read(actionServiceProvider)
            .createAction(
              name: 'Swim',
              metricIds: [metricId],
              startAt: now.subtract(const Duration(hours: 4)),
              endAt: now.subtract(const Duration(hours: 2, minutes: 30)),
            );
      }
    });
    return metricId;
  }

  testWidgets('info row order and a done linked action changes the fact '
      '(count)', (tester) async {
    final id = await seedMetric(tester, MetricKind.count, doneAction: true);
    await openDialog(tester, id);
    final x = [
      for (final t in [
        'Level',
        'Progress',
        'Weight',
        'Urgency to Keep in Balance',
        'Fact: reached so far',
      ])
        tester.getTopLeft(find.byTooltip(t).first).dx,
    ];
    expect([...x]..sort(), x);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('dialogFact')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    await teardown(tester);
  });

  testWidgets('hours direction shows the fact in hours', (tester) async {
    final id = await seedMetric(tester, MetricKind.hours, doneAction: true);
    await openDialog(tester, id);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('dialogFact')),
        matching: find.text('1.5 h'),
      ),
      findsOneWidget,
    );
    await teardown(tester);
  });

  testWidgets('boolean direction shows four icons and no fact', (tester) async {
    final id = await seedMetric(tester, MetricKind.boolean);
    await openDialog(tester, id);
    expect(find.byType(ParamIcon), findsNWidgets(4));
    expect(find.byKey(const ValueKey('dialogFact')), findsNothing);
    expect(find.byTooltip('Fact: reached so far'), findsNothing);
    await teardown(tester);
  });
}
