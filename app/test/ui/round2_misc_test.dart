import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/ids.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/growth_rules.dart';
import 'package:livenow/domain/metric_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/domain/work_hours.dart';
import 'package:livenow/main.dart';
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/open_entity.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/reminders.dart';
import 'package:livenow/ui/root_navigator.dart';
import 'package:livenow/ui/screens/growth_directions_screen.dart';
import 'package:livenow/ui/screens/settings_screen.dart';
import 'package:livenow/ui/screens/templates_screen.dart';
import 'package:livenow/ui/sync_providers.dart';
import 'package:livenow/ui/widgets/action_editor.dart';
import 'package:livenow/ui/widgets/app_toast.dart';
import 'package:livenow/ui/widgets/growth_direction_dialog.dart';
import 'package:livenow/ui/work_hours.dart';

void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;

  Future<void> settle(WidgetTester tester, [int ms = 400]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    Size size = const Size(1400, 1000),
    Future<void> Function()? seed,
    List<Override> overrides = const [],
    GlobalKey<NavigatorState>? navigatorKey,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    if (seed != null) await tester.runAsync(seed);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          syncRoleProvider.overrideWithValue(SyncRole.client),
          ...overrides,
        ],
        child: MaterialApp(navigatorKey: navigatorKey, home: home),
      ),
    );
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    resetStackedDialogsForTest();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  // ---- mindmap search ----------------------------------------------------------

  testWidgets('mindmap search lists matches and a tap selects that direction', (
    tester,
  ) async {
    late String alpha, beta;
    await pump(
      tester,
      const GrowthDirectionsScreen(),
      seed: () async {
        final m = MetricService(db);
        alpha = await m.saveMetric(
          name: 'Alpha reading',
          kind: MetricKind.boolean,
        );
        beta = await m.saveMetric(
          name: 'Beta running',
          kind: MetricKind.boolean,
        );
      },
    );
    await tester.tap(find.text('Mindmap'));
    await settle(tester, 600);
    await tester.tap(find.byKey(const ValueKey('mindmap-search-toggle')));
    await settle(tester);
    expect(find.byKey(const ValueKey('mindmap-search-field')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('mindmap-search-field')),
      'BETA',
    );
    await settle(tester);
    expect(find.byKey(ValueKey('mindmap-result-$beta')), findsOneWidget);
    expect(find.byKey(ValueKey('mindmap-result-$alpha')), findsNothing);

    await tester.tap(find.byKey(ValueKey('mindmap-result-$beta')));
    await settle(tester);
    expect(
      tester
          .widget<ListTile>(find.byKey(ValueKey('mindmap-result-$beta')))
          .selected,
      isTrue,
    );

    await tester.enterText(
      find.byKey(const ValueKey('mindmap-search-field')),
      'zzz',
    );
    await settle(tester);
    expect(find.byKey(const ValueKey('mindmap-search-empty')), findsOneWidget);

    // Closing the search clears and removes it.
    await tester.tap(find.byTooltip('Close search').first);
    await settle(tester);
    expect(find.byKey(const ValueKey('mindmap-search-field')), findsNothing);
    await unmount(tester);
  });

  // ---- toast above keyboard and bottom navigation -----------------------------------

  testWidgets(
    'a toast sits above the keyboard and above the bottom navigation',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(() => toastBottomInset.value = 0);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () =>
                      showInfoToast(rootOverlayOf(context), 'Hello toast'),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      );

      // Nothing in the way: the usual spot near the bottom edge.
      await tester.tap(find.text('go'));
      await tester.pump();
      var bottom = tester.getRect(find.text('Hello toast')).bottom;
      expect(bottom, greaterThan(812 - 60));

      // The phone's bottom navigation (80 px) is up: the toast clears it.
      toastBottomInset.value = 80;
      await tester.pump();
      bottom = tester.getRect(find.text('Hello toast')).bottom;
      expect(bottom, lessThanOrEqualTo(812 - 80));

      // The keyboard (300 px) is up: the toast sits above it.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      bottom = tester.getRect(find.text('Hello toast')).bottom;
      expect(bottom, lessThanOrEqualTo(812 - 300));
      await tester.pump(const Duration(seconds: 6));
    },
  );

  // ---- Current board, phone landscape -------------------------------------------------

  testWidgets(
    'a phone held sideways shows both Current columns, upright one switch',
    (tester) async {
      Future<void> run(Size size) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        final now = DateTime.now();
        await tester.runAsync(() async {
          final s = ActionService(db);
          await s.createAction(
            name: 'Open one',
            startAt: now.subtract(const Duration(minutes: 10)),
            endAt: now.add(const Duration(hours: 2)),
          );
          await s.createAction(
            name: 'Finished one',
            startAt: now.subtract(const Duration(hours: 5)),
            endAt: now.subtract(const Duration(hours: 4)),
          );
        });
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              databaseProvider.overrideWithValue(db),
              syncRoleProvider.overrideWithValue(SyncRole.client),
            ],
            child: const LiveNowApp(),
          ),
        );
        await settle(tester, 800);
      }

      await run(const Size(812, 375));
      expect(find.byKey(const ValueKey('board-switch-done')), findsNothing);
      expect(find.text('Done Before'), findsOneWidget);
      expect(find.text('Not Done Yet'), findsOneWidget);
      expect(find.text('Open one'), findsOneWidget);
      expect(find.text('Finished one'), findsOneWidget);
      await unmount(tester);

      await run(const Size(375, 812));
      expect(find.byKey(const ValueKey('board-switch-done')), findsOneWidget);
      // Upright: only one column's cards at a time.
      expect(find.text('Open one'), findsOneWidget);
      expect(find.text('Finished one'), findsNothing);
      await unmount(tester);
    },
  );

  // ---- direction <-> action creation ------------------------------------------------------

  testWidgets('a direction can create a new action already linked to it', (
    tester,
  ) async {
    late String dir;
    await pump(
      tester,
      Consumer(
        builder: (context, ref, _) => TextButton(
          onPressed: () => openDirectionById(context, ref, dir),
          child: const Text('open'),
        ),
      ),
      seed: () async {
        dir = await MetricService(db)
            .saveMetric(name: 'Reading', kind: MetricKind.boolean);
      },
    );
    await tester.tap(find.text('open'));
    await settle(tester, 600);
    await tester.tap(find.byKey(const ValueKey('direction-new-action')));
    await settle(tester, 600);
    expect(find.byType(ActionEditorDialog), findsOneWidget);
    // The direction is already chosen in the new action.
    expect(find.widgetWithText(InputChip, 'Reading'), findsOneWidget);

    await tester.enterText(
      find
          .descendant(
            of: find.byType(ActionEditorDialog),
            matching: find.byType(TextFormField),
          )
          .first,
      'Read a book',
    );
    await tester.tap(
      find.descendant(
        of: find.byType(ActionEditorDialog),
        matching: find.text('Save'),
      ),
    );
    await settle(tester, 800);
    final links = (await tester.runAsync(
      () => db.select(db.actionMetricsTable).get(),
    ))!;
    expect(links.map((l) => l.metricId), [dir]);
    await unmount(tester);
  });

  testWidgets('the action editor can create a new direction and uses it', (
    tester,
  ) async {
    await pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => ActionEditorDialog.show(context),
          child: const Text('new action'),
        ),
      ),
    );
    await tester.tap(find.text('new action'));
    await settle(tester, 600);
    await tester.tap(find.byKey(const ValueKey('metric-picker-new')));
    await settle(tester, 600);
    expect(find.byType(GrowthDirectionDialog), findsOneWidget);
    // A new direction has no linked-actions block (nothing to create from yet).
    expect(find.byKey(const ValueKey('direction-new-action')), findsNothing);
    await tester.enterText(
      find
          .descendant(
            of: find.byType(GrowthDirectionDialog),
            matching: find.byType(TextFormField),
          )
          .first,
      'Brand new direction',
    );
    await tester.tap(
      find.descendant(
        of: find.byType(GrowthDirectionDialog),
        matching: find.text('Save'),
      ),
    );
    await settle(tester, 800);
    expect(find.byType(GrowthDirectionDialog), findsNothing);
    // It is chosen in the action editor underneath.
    expect(
      find.widgetWithText(InputChip, 'Brand new direction'),
      findsOneWidget,
    );
    await unmount(tester);
  });

  // ---- templates search -------------------------------------------------------------------

  testWidgets('template search also matches the growth direction names', (
    tester,
  ) async {
    await pump(
      tester,
      const TemplatesScreen(),
      seed: () async {
        final dir = await MetricService(db)
            .saveMetric(name: 'Health', kind: MetricKind.boolean);
        Future<void> template(String name, List<String> ids) => db
            .into(db.actionTemplatesTable)
            .insert(
              ActionTemplatesTableCompanion.insert(
                id: newId(),
                name: name,
                payload: jsonEncode({'name': name, 'metricIds': ids}),
              ),
            );
        await template('Run', [dir]);
        await template('Read', []);
      },
    );
    expect(find.text('Run'), findsOneWidget);
    expect(find.text('Read'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('templates-search')),
      'HEALTH',
    );
    await settle(tester);
    expect(find.text('Run'), findsOneWidget);
    expect(find.text('Read'), findsNothing);
    await unmount(tester);
  });

  // ---- working hours ----------------------------------------------------------------------

  testWidgets('Settings shows the working hours and a change is applied', (
    tester,
  ) async {
    await pump(tester, const SettingsScreen());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    );
    Future<void> see(String key) async =>
        tester.ensureVisible(find.byKey(ValueKey(key)));
    await see('settings-work-end');
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('settings-work-end')),
        matching: find.text('18:00'),
      ),
      findsOneWidget,
    );
    final notifier = container.read(workHoursProvider.notifier);
    expect(
      notifier.set(
        const WorkHours(workEnd: 17 * 60 + 30, morning: 8 * 60 + 15),
      ),
      isNull,
    );
    await settle(tester);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('settings-work-end')),
        matching: find.text('17:30'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('settings-morning')),
        matching: find.text('08:15'),
      ),
      findsOneWidget,
    );
    // An invalid day (ends before it starts) is refused and nothing changes.
    expect(
      notifier.set(const WorkHours(workStart: 20 * 60, workEnd: 8 * 60)),
      isNotNull,
    );
    expect(container.read(workHoursProvider).workEnd, 17 * 60 + 30);
    await unmount(tester);
  });

  testWidgets('postponing reads the configured morning time', (tester) async {
    late String id;
    await pump(
      tester,
      const SizedBox(),
      seed: () async {
        id = await ActionService(db).createAction(
          name: 'x',
          startAt: DateTime.utc(2030, 1, 2, 9), // 12:00 Istanbul
          endAt: DateTime.utc(2030, 1, 2, 10),
        );
      },
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SizedBox)),
    );
    container
        .read(workHoursProvider.notifier)
        .set(const WorkHours(morning: 8 * 60 + 15));
    await tester.runAsync(
      () => container
          .read(actionServiceProvider)
          .postpone(id, PostponeRule.morning),
    );
    final row = (await tester.runAsync(
      () => (db.select(
        db.actionsTable,
      )..where((t) => t.id.equals(id))).getSingle(),
    ))!;
    // 08:15 Istanbul on the 3rd = 05:15 UTC.
    expect(row.startAt, startsWith('2030-01-03T05:15'));
    await unmount(tester);
  });

  // ---- notification tap -----------------------------------------------------------------------

  testWidgets('a tapped notification opens that action\'s editor', (
    tester,
  ) async {
    late String id;
    await pump(
      tester,
      const Scaffold(body: SizedBox()),
      navigatorKey: rootNavigatorKey,
      seed: () async {
        id = await ActionService(db).createAction(name: 'From notification');
      },
    );
    // The function completes only when the editor is closed again, so it is
    // not awaited: give it real time to read the row and open the dialog.
    await tester.runAsync(() async {
      unawaited(openActionFromNotification(db, id, tries: 2));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await settle(tester, 600);
    expect(find.byType(ActionEditorDialog), findsOneWidget);
    expect(find.text('Edit action'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ActionEditorDialog),
        matching: find.text('From notification'),
      ),
      findsOneWidget,
    );
    await unmount(tester);
  });

  testWidgets('a tapped notification of a deleted action says so', (
    tester,
  ) async {
    await pump(
      tester,
      const Scaffold(body: SizedBox()),
      navigatorKey: rootNavigatorKey,
    );
    await tester.runAsync(() async {
      unawaited(openActionFromNotification(db, 'gone', tries: 2));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await settle(tester, 300);
    expect(find.text('That action no longer exists.'), findsOneWidget);
    expect(find.byType(ActionEditorDialog), findsNothing);
    await tester.pump(const Duration(seconds: 6));
    await unmount(tester);
  });
}
