import 'dart:ui' show Tristate;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/main.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/screens/growth_directions_screen.dart';
import 'package:livenow/ui/views/all_actions_view.dart';
import 'package:livenow/ui/views/calendar_view.dart';
import 'package:livenow/ui/widgets/instant_rail.dart';

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

/// A section change may leave exactly one transient frame behind: showing a
/// kept-alive section un-mutes its (already finished) tickers and its focus
/// scope changes, each costing one more frame. Nothing may still be animating
/// one frame later (the old NavigationRail kept animating for ~300 ms+).
Future<void> _noLingeringAnimation(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 16));
  expect(tester.hasRunningAnimations, isFalse);
}

final _rail = find.byType(InstantRail);
Finder _railItem(String label) =>
    find.descendant(of: _rail, matching: find.text(label));

void main() {
  setUpAll(initPostponeTimeZoneData);

  testWidgets('rail selection completes in a single pump', (tester) async {
    await _pumpApp(tester);

    // Warm-up: visit every section once and let data loading (spinners)
    // settle, so only the switch itself can be running an animation.
    for (final l in ['Growth directions', 'Templates', 'Actions']) {
      await tester.tap(_railItem(l));
      await tester.pumpAndSettle();
    }

    await tester.tap(_railItem('Growth directions'));
    await tester.pump();
    expect(tester.widget<InstantRail>(_rail).selectedIndex, 1);
    await _noLingeringAnimation(tester);

    await tester.tap(_railItem('Templates'));
    await tester.pump();
    expect(tester.widget<InstantRail>(_rail).selectedIndex, 2);
    await _noLingeringAnimation(tester);

    await tester.tap(_railItem('Actions'));
    await tester.pump();
    expect(tester.widget<InstantRail>(_rail).selectedIndex, 0);
    await _noLingeringAnimation(tester);

    await _unmount(tester);
  });

  testWidgets('Actions sub-view switch completes in a single pump', (
    tester,
  ) async {
    await _pumpApp(tester);
    Finder seg(String l) => find.descendant(
      of: find.byKey(const ValueKey('actions-switch')),
      matching: find.text(l),
    );
    // Warm-up: build Calendar once and let it settle.
    await tester.tap(seg('Calendar'));
    await tester.pumpAndSettle();
    await tester.tap(seg('Current Actions'));
    await tester.pumpAndSettle();

    await tester.tap(seg('Calendar'));
    await tester.pump();
    expect(find.byType(CalendarView), findsOneWidget);
    await _noLingeringAnimation(tester);

    await tester.tap(seg('All'));
    await tester.pumpAndSettle();
    await tester.tap(seg('Calendar'));
    await tester.pump();
    await tester.tap(seg('All'));
    await tester.pump();
    expect(find.byType(AllActionsView), findsOneWidget);
    await _noLingeringAnimation(tester);

    await _unmount(tester);
  });

  testWidgets('Growth directions tabs switch in a single pump', (tester) async {
    await _pumpApp(tester);
    await tester.tap(_railItem('Growth directions'));
    await tester.pumpAndSettle();

    final tabs = find.descendant(
      of: find.byType(GrowthDirectionsScreen),
      matching: find.byType(TabBar),
    );
    expect(tabs, findsOneWidget);
    expect(
      DefaultTabController.of(tester.element(tabs)).animationDuration,
      Duration.zero,
    );

    await tester.tap(find.descendant(of: tabs, matching: find.text('List')));
    await tester.pump();
    expect(DefaultTabController.of(tester.element(tabs)).index, 1);
    expect(DefaultTabController.of(tester.element(tabs)).animation!.value, 1);
    await _noLingeringAnimation(tester);

    await tester.tap(find.descendant(of: tabs, matching: find.text('Balance')));
    await tester.pump();
    expect(DefaultTabController.of(tester.element(tabs)).index, 0);
    await _noLingeringAnimation(tester);

    await _unmount(tester);
  });

  testWidgets('rail semantics: 3 labelled buttons, exactly one selected', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpApp(tester);

    var selected = 0;
    for (final label in ['Actions', 'Growth directions', 'Templates']) {
      final node = tester.getSemantics(_railItem(label));
      final data = node.getSemanticsData();
      expect(data.label, label);
      expect(data.flagsCollection.isButton, isTrue, reason: label);
      if (data.flagsCollection.isSelected == Tristate.isTrue) selected++;
    }
    expect(selected, 1);
    expect(
      tester
          .getSemantics(_railItem('Actions'))
          .getSemanticsData()
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );

    handle.dispose();
    await _unmount(tester);
  });

  testWidgets('rail items activate from the keyboard', (tester) async {
    await _pumpApp(tester);

    // Focus the Growth directions item directly, then activate with Enter
    // and Space.
    Element item(String l) => tester.element(_railItem(l));
    Focus.of(item('Growth directions')).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(tester.widget<InstantRail>(_rail).selectedIndex, 1);

    Focus.of(item('Templates')).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(tester.widget<InstantRail>(_rail).selectedIndex, 2);

    // Tab moves focus to the next rail item.
    Focus.of(item('Actions')).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(tester.widget<InstantRail>(_rail).selectedIndex, 1);

    await _unmount(tester);
  });
}
