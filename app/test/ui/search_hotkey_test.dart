import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/global_search.dart';
import 'package:livenow/domain/growth_rules.dart' show MetricKind;
import 'package:livenow/domain/metric_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/main.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/widgets/instant_rail.dart';
import 'package:livenow/ui/widgets/global_search_dialog.dart';

/// Ctrl+F opens / focuses the search of the view on screen (also the ones behind a
/// magnifier icon); in a view without a search it opens the Ctrl+K window for that
/// view. Ctrl+K opens the window anywhere and closes it again.
void main() {
  setUpAll(initPostponeTimeZoneData);

  /// A few bounded pumps instead of pumpAndSettle: the Mindmap never settles.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpApp(WidgetTester tester, {bool withDirection = false}) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    // The Mindmap shows its toolbar (and the search) only with directions.
    if (withDirection) {
      await tester.runAsync(
        () => MetricService(db).saveMetric(name: 'Reading', kind: MetricKind.boolean),
      );
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const LiveNowApp(),
      ),
    );
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> ctrl(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);
  }

  Finder tab(String label) => find.descendant(
    of: find.byKey(const ValueKey('actions-switch')),
    matching: find.text(label),
  );

  bool focused(WidgetTester tester, String key) => tester
      .widget<TextField>(find.byKey(ValueKey(key)))
      .focusNode!
      .hasFocus;

  testWidgets('Ctrl+F on the Current board opens the search behind the icon', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.byKey(const ValueKey('current-search-field')), findsNothing);
    await ctrl(tester, LogicalKeyboardKey.keyF);
    expect(find.byKey(const ValueKey('current-search-field')), findsOneWidget);
    expect(focused(tester, 'current-search-field'), isTrue);
    // The icon is still there and still clickable.
    expect(find.byKey(const ValueKey('current-search-toggle')), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('Ctrl+F in All focuses its search (Current stays closed)', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(tab('All'));
    await settle(tester);
    await ctrl(tester, LogicalKeyboardKey.keyF);
    expect(focused(tester, 'allSearchField'), isTrue);
    expect(find.byKey(const ValueKey('current-search-field')), findsNothing);
    await unmount(tester);
  });

  testWidgets('Ctrl+F in Templates and Forms focuses their search', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(tab('Templates'));
    await settle(tester);
    await ctrl(tester, LogicalKeyboardKey.keyF);
    expect(focused(tester, 'templates-search'), isTrue);

    await tester.tap(tab('Forms'));
    await settle(tester);
    await ctrl(tester, LogicalKeyboardKey.keyF);
    expect(focused(tester, 'forms-search'), isTrue);
    await unmount(tester);
  });

  testWidgets('Ctrl+F in the Calendar (no search of its own) opens the Ctrl+K '
      'window on Actions', (tester) async {
    await pumpApp(tester);
    await tester.tap(tab('Calendar'));
    await settle(tester);
    await ctrl(tester, LogicalKeyboardKey.keyF);
    expect(GlobalSearchDialog.isOpen, isTrue);
    final chip = tester.widget<ChoiceChip>(
      find.byKey(ValueKey('global-search-section-${SearchSection.actions.name}')),
    );
    expect(chip.selected, isTrue);
    await ctrl(tester, LogicalKeyboardKey.keyK); // toggles it closed
    expect(GlobalSearchDialog.isOpen, isFalse);
    await unmount(tester);
  });

  testWidgets('Ctrl+K opens the window anywhere and a second press closes it', (
    tester,
  ) async {
    await pumpApp(tester);
    await ctrl(tester, LogicalKeyboardKey.keyK);
    expect(GlobalSearchDialog.isOpen, isTrue);
    expect(find.byKey(const ValueKey('global-search-field')), findsOneWidget);
    // All sections are on ("All" selected).
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('global-search-section-all')))
          .selected,
      isTrue,
    );
    await ctrl(tester, LogicalKeyboardKey.keyK);
    expect(GlobalSearchDialog.isOpen, isFalse);
    expect(find.byKey(const ValueKey('global-search-field')), findsNothing);
    await unmount(tester);
  });

  testWidgets('Ctrl+F with a dialog open and no search in it does nothing', (
    tester,
  ) async {
    await pumpApp(tester);
    await ctrl(tester, LogicalKeyboardKey.keyK);
    expect(GlobalSearchDialog.isOpen, isTrue);
    // The Ctrl+K window itself is the dialog on top: Ctrl+F must not open a
    // second one or the Current board's search behind it.
    await ctrl(tester, LogicalKeyboardKey.keyF);
    expect(find.byKey(const ValueKey('global-search-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('current-search-field')), findsNothing);
    await ctrl(tester, LogicalKeyboardKey.keyK);
    await unmount(tester);
  });

  Finder rail(String label) =>
      find.descendant(of: find.byType(InstantRail), matching: find.text(label));
  Finder growthTab(String label) => find.descendant(
    of: find.byType(TabBar),
    matching: find.text(label),
  );

  testWidgets('Ctrl+F in Growth directions: List / Treemap focus the shared '
      'search, the Mindmap opens its search box', (tester) async {
    await pumpApp(tester, withDirection: true);
    await tester.tap(rail('Growth directions'));
    await settle(tester);

    await tester.tap(growthTab('List'));
    await settle(tester);
    await ctrl(tester, LogicalKeyboardKey.keyF);
    expect(focused(tester, 'growth-search'), isTrue);

    await tester.tap(growthTab('Treemap'));
    await settle(tester);
    await ctrl(tester, LogicalKeyboardKey.keyF);
    expect(focused(tester, 'growth-search'), isTrue);

    await tester.tap(growthTab('Mindmap'));
    await settle(tester);
    expect(find.byKey(const ValueKey('mindmap-search-field')), findsNothing);
    await ctrl(tester, LogicalKeyboardKey.keyF);
    expect(find.byKey(const ValueKey('mindmap-search-field')), findsOneWidget);
    expect(focused(tester, 'mindmap-search-field'), isTrue);

    // Balance has no search: the Ctrl+K window opens on Directions.
    await tester.tap(growthTab('Balance'));
    await settle(tester);
    await ctrl(tester, LogicalKeyboardKey.keyF);
    expect(GlobalSearchDialog.isOpen, isTrue);
    await ctrl(tester, LogicalKeyboardKey.keyK);
    await unmount(tester);
  });

  testWidgets('Ctrl+F in Budget: Categories and Transactions focus their search', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(rail('Budget'));
    await settle(tester);

    await tester.tap(find.descendant(of: find.byType(TabBar), matching: find.text('Categories')));
    await settle(tester);
    await ctrl(tester, LogicalKeyboardKey.keyF);
    expect(focused(tester, 'budget-categories-search'), isTrue);

    await tester.tap(find.descendant(of: find.byType(TabBar), matching: find.text('Transactions')));
    await settle(tester);
    await ctrl(tester, LogicalKeyboardKey.keyF);
    expect(focused(tester, 'budget-transactions-search'), isTrue);
    await unmount(tester);
  });
}
