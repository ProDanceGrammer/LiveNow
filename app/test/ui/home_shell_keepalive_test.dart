import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/main.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/screens/growth_directions_screen.dart';
import 'package:livenow/ui/screens/templates_screen.dart';
import 'package:livenow/ui/widgets/instant_rail.dart';
import 'package:livenow/ui/views/all_actions_view.dart';
import 'package:livenow/ui/views/calendar_view.dart';
import 'package:livenow/ui/views/current_actions_view.dart';

Future<void> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const LiveNowApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}

bool _built<T extends Widget>() =>
    find.byType(T, skipOffstage: false).evaluate().isNotEmpty;
bool _shown<T extends Widget>() => find.byType(T).evaluate().isNotEmpty;

final _rail = find.byType(InstantRail);
final _switch = find.byKey(const ValueKey('actions-switch'));
Finder _title(String s) =>
    find.descendant(of: find.byType(AppBar), matching: find.text(s));
Finder _switchLabel(String s) =>
    find.descendant(of: _switch, matching: find.text(s));

void main() {
  setUpAll(initPostponeTimeZoneData);

  testWidgets('sections and Actions sub-views are built on first visit, then '
      'kept alive and hidden', (tester) async {
    await _pumpApp(tester);

    // Only Actions > Current exists at start.
    expect(_built<CurrentActionsView>(), isTrue);
    expect(_shown<CurrentActionsView>(), isTrue);
    expect(_built<CalendarView>(), isFalse);
    expect(_built<AllActionsView>(), isFalse);
    expect(_built<GrowthDirectionsScreen>(), isFalse);
    expect(_built<TemplatesScreen>(), isFalse);

    // Visiting Calendar builds it; Current stays alive but hidden.
    await tester.tap(_switchLabel('Calendar'));
    await tester.pumpAndSettle();
    expect(_shown<CalendarView>(), isTrue);
    expect(_built<CurrentActionsView>(), isTrue);
    expect(_shown<CurrentActionsView>(), isFalse);
    expect(_built<AllActionsView>(), isFalse);

    // Going back reuses the very same elements (no rebuild from scratch).
    final calendarElement = find
        .byType(CalendarView, skipOffstage: false)
        .evaluate()
        .single;
    final currentElement = find
        .byType(CurrentActionsView, skipOffstage: false)
        .evaluate()
        .single;
    await tester.tap(_switchLabel('Current Actions'));
    await tester.pumpAndSettle();
    expect(_shown<CurrentActionsView>(), isTrue);
    expect(_shown<CalendarView>(), isFalse);
    expect(_built<CalendarView>(), isTrue);
    await tester.tap(_switchLabel('Calendar'));
    await tester.pumpAndSettle();
    expect(
      find.byType(CalendarView, skipOffstage: false).evaluate().single,
      same(calendarElement),
    );
    expect(
      find.byType(CurrentActionsView, skipOffstage: false).evaluate().single,
      same(currentElement),
    );

    // Other sections build lazily and the whole Actions section stays alive.
    await tester.tap(_switchLabel('All'));
    await tester.pumpAndSettle();
    expect(_shown<AllActionsView>(), isTrue);
    expect(_built<GrowthDirectionsScreen>(), isFalse);
    expect(_shown<CalendarView>(), isFalse);
    expect(_built<CalendarView>(), isTrue);
    expect(_built<CurrentActionsView>(), isTrue);

    await tester.tap(
      find.descendant(of: _rail, matching: find.text('Growth directions')),
    );
    await tester.pumpAndSettle();
    expect(_shown<GrowthDirectionsScreen>(), isTrue);
    expect(_built<TemplatesScreen>(), isFalse);
    await tester.tap(
      find.descendant(of: _rail, matching: find.text('Templates')),
    );
    await tester.pumpAndSettle();
    expect(_shown<TemplatesScreen>(), isTrue);

    // Back to Actions: the remembered sub-view (All) is shown; Calendar's
    // element survives.
    await tester.tap(
      find.descendant(of: _rail, matching: find.text('Actions')),
    );
    await tester.pumpAndSettle();
    expect(_shown<AllActionsView>(), isTrue);
    expect(_shown<CurrentActionsView>(), isFalse);
    expect(
      find.byType(CalendarView, skipOffstage: false).evaluate().single,
      same(calendarElement),
    );

    // Hidden views take no focus.
    final excluded = tester
        .widgetList<ExcludeFocus>(
          find.byType(ExcludeFocus, skipOffstage: false),
        )
        .where((w) => w.excluding)
        .length;
    expect(excluded, greaterThanOrEqualTo(1));

    await _unmount(tester);
  });

  testWidgets('rail has exactly Actions, Growth directions, Templates, Budget', (
    tester,
  ) async {
    await _pumpApp(tester);

    final labels = tester
        .widget<InstantRail>(_rail)
        .items
        .map((d) => d.label)
        .toList();
    expect(labels, ['Actions', 'Growth directions', 'Templates', 'Budget']);
    expect(
      find.descendant(of: _rail, matching: find.text('Current')),
      findsNothing,
    );
    expect(
      find.descendant(of: _rail, matching: find.text('Calendar')),
      findsNothing,
    );
    expect(
      find.descendant(of: _rail, matching: find.text('Current Actions')),
      findsNothing,
    );

    await _unmount(tester);
  });

  testWidgets('collapsing the rail narrows it to icons and keeps sections '
      'alive', (tester) async {
    await _pumpApp(tester);
    await tester.tap(_switchLabel('Calendar'));
    await tester.pumpAndSettle();
    final calendarElement = find
        .byType(CalendarView, skipOffstage: false)
        .evaluate()
        .single;
    expect(tester.getSize(_rail).width, InstantRail.width);

    await tester.tap(find.byKey(const ValueKey('rail-toggle')));
    await tester.pump();
    expect(tester.getSize(_rail).width, InstantRail.collapsedWidth);
    expect(
      find.descendant(of: _rail, matching: find.text('Actions')),
      findsNothing,
    );
    expect(
      find.descendant(of: _rail, matching: find.byType(Icon)),
      findsNWidgets(5), // toggle + 4 destinations
    );
    expect(
      find.byType(CalendarView, skipOffstage: false).evaluate().single,
      same(calendarElement),
    );
    expect(_shown<CalendarView>(), isTrue);

    await tester.tap(find.byKey(const ValueKey('rail-toggle')));
    await tester.pump();
    expect(tester.getSize(_rail).width, InstantRail.width);
    expect(
      find.byType(CalendarView, skipOffstage: false).evaluate().single,
      same(calendarElement),
    );

    await _unmount(tester);
  });

  testWidgets('rail label Growth directions wraps onto two lines', (
    tester,
  ) async {
    await _pumpApp(tester);
    final box = tester.getSize(
      find.descendant(of: _rail, matching: find.text('Growth directions')),
    );
    expect(box.height, greaterThan(18)); // two lines of a ~12 px label
    expect(box.width, lessThanOrEqualTo(InstantRail.labelWidth));
    await _unmount(tester);
  });

  testWidgets('Actions switch defaults to Current Actions, swaps instantly '
      'and drives the title and FAB', (tester) async {
    await _pumpApp(tester);

    expect(_switch, findsOneWidget);
    expect(_title('Current Actions'), findsOneWidget);
    expect(_title('Calendar'), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    // One frame later (no settling) the swap is already complete.
    await tester.tap(_switchLabel('Calendar'));
    await tester.pump();
    expect(_shown<CalendarView>(), isTrue);
    expect(_shown<CurrentActionsView>(), isFalse);
    expect(_title('Calendar'), findsOneWidget);
    expect(_title('Current Actions'), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    await tester.tap(_switchLabel('Current Actions'));
    await tester.pump();
    expect(_shown<CurrentActionsView>(), isTrue);
    expect(_title('Current Actions'), findsOneWidget);

    // All is a third tab of the Actions switch; the FAB stays.
    await tester.tap(_switchLabel('All'));
    await tester.pump();
    expect(_shown<AllActionsView>(), isTrue);
    expect(_title('All Actions'), findsOneWidget);
    expect(_switch.hitTestable(), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    await tester.tap(
      find.descendant(of: _rail, matching: find.text('Growth directions')),
    );
    await tester.pumpAndSettle();
    expect(_title('Growth directions'), findsOneWidget);
    expect(find.byTooltip('New action'), findsNothing);

    await _unmount(tester);
  });

  testWidgets('Calendar takes keyboard focus as soon as it is shown', (
    tester,
  ) async {
    await _pumpApp(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(InstantRail)),
    );
    expect(container.read(calendarDayCountProvider), 7);

    // Open the Calendar tab and press a digit WITHOUT clicking inside it.
    await tester.tap(_switchLabel('Calendar'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pump();
    expect(container.read(calendarDayCountProvider), 3);

    // Away to Current and back: focus is handed over again.
    await tester.tap(_switchLabel('Current Actions'));
    await tester.pumpAndSettle();
    await tester.tap(_switchLabel('Calendar'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
    await tester.pump();
    expect(container.read(calendarDayCountProvider), 5);

    // Another section and back to Actions (Calendar still active).
    await tester.tap(find.text('Templates'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Actions').first);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
    await tester.pump();
    expect(container.read(calendarDayCountProvider), 4);
    await _unmount(tester);
  });
}
