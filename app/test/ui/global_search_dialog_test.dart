import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/core/ids.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/growth_rules.dart' show MetricKind;
import 'package:livenow/domain/metric_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/root_navigator.dart';
import 'package:livenow/ui/widgets/action_editor.dart';
import 'package:livenow/ui/widgets/global_search_dialog.dart';

/// The Ctrl+K window: whole words first, section chips, the updated menu, and
/// Enter / a tap opens the thing in its own editor.
void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.runAsync(() async {
      final actions = ActionService(db);
      // Created one after the other: the later one is the newer.
      for (final n in [
        'commit files',
        'IT infrastructure',
        'do it',
        'iterations construction',
      ]) {
        await actions.createAction(name: n);
        await Future<void>.delayed(const Duration(milliseconds: 8));
      }
      await MetricService(db).saveMetric(
        name: 'It is my plan',
        kind: MetricKind.boolean,
      );
      await db
          .into(db.actionTemplatesTable)
          .insert(
            ActionTemplatesTableCompanion.insert(
              id: newId(),
              name: 'Shower',
              payload: '{}',
            ),
          );
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          navigatorKey: rootNavigatorKey,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => GlobalSearchDialog.toggle(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    resetStackedDialogsForTest();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  double y(WidgetTester tester, String title) =>
      tester.getTopLeft(find.text(title)).dy;

  testWidgets('empty query lists the newest things; typing ranks whole words first', (
    tester,
  ) async {
    await open(tester);
    // Newest first, all sections.
    expect(y(tester, 'Shower'), lessThan(y(tester, 'commit files')));

    await tester.enterText(find.byKey(const ValueKey('global-search-field')), 'it');
    await settle(tester);
    // Whole word 'it': "do it", "IT infrastructure", "It is my plan"(direction)
    // - newest first - then the words that only contain it.
    final ordered = [
      'It is my plan',
      'do it',
      'IT infrastructure',
      'iterations construction',
      'commit files',
    ]..sort((a, b) => y(tester, a).compareTo(y(tester, b)));
    expect(ordered, [
      'It is my plan',
      'do it',
      'IT infrastructure',
      'iterations construction',
      'commit files',
    ]);
    expect(find.text('Shower'), findsNothing);
    await unmount(tester);
  });

  testWidgets('a section chip narrows the results; tapping it again shows all', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(find.byKey(const ValueKey('global-search-field')), 'it');
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('global-search-section-directions')));
    await settle(tester);
    expect(find.text('It is my plan'), findsOneWidget);
    expect(find.text('do it'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('global-search-section-actions')));
    await settle(tester);
    expect(find.text('do it'), findsOneWidget);
    expect(find.text('It is my plan'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('global-search-section-all')));
    await settle(tester);
    expect(find.text('do it'), findsOneWidget);
    expect(find.text('It is my plan'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('the updated menu filters by when it last changed', (tester) async {
    await open(tester);
    await tester.enterText(find.byKey(const ValueKey('global-search-field')), 'it');
    await settle(tester);

    // Everything was just made: 'Today' keeps all of it.
    await tester.tap(find.byKey(const ValueKey('global-search-updated')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('global-search-updated-today')));
    await settle(tester);
    expect(find.text('do it'), findsOneWidget);
    expect(find.text('Updated: Today'), findsOneWidget);

    // Age one action's stamp by a year, then ask for the past 7 days.
    await tester.runAsync(
      () => db.customStatement(
        "UPDATE sync_versions SET hlc = '2025-01-01T00:00:00.000Z-0001-x' "
        "WHERE tbl = 'actions' AND row_id IN "
        "(SELECT id FROM actions WHERE name = 'do it')",
      ),
    );
    await tester.tap(find.byKey(const ValueKey('global-search-updated')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('global-search-updated-week')));
    await settle(tester);
    // The index is loaded when the window opens, so reopen it to see the change.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    await tester.tap(find.text('open'));
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('global-search-field')), 'it');
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('global-search-updated')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('global-search-updated-week')));
    await settle(tester);
    expect(find.text('do it'), findsNothing);
    expect(find.text('IT infrastructure'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('Enter opens the first result in its own editor and closes the window', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(
      find.byKey(const ValueKey('global-search-field')),
      'IT infra',
    );
    await settle(tester);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester);
    expect(GlobalSearchDialog.isOpen, isFalse);
    expect(find.byType(ActionEditorDialog), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'IT infrastructure'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('arrow keys move the selection, Enter opens that row', (tester) async {
    await open(tester);
    await tester.enterText(find.byKey(const ValueKey('global-search-field')), 'it');
    await settle(tester);
    // Row order: It is my plan, do it, ... ; go down once -> 'do it'.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await settle(tester);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester);
    expect(find.byType(ActionEditorDialog), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'do it'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a query nothing matches says so', (tester) async {
    await open(tester);
    await tester.enterText(find.byKey(const ValueKey('global-search-field')), 'zzzqq');
    await settle(tester);
    expect(find.byKey(const ValueKey('global-search-empty')), findsOneWidget);
    await unmount(tester);
  });
}
