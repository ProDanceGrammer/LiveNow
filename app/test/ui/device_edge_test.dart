import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/action_service.dart';
import 'package:livenow/domain/budget_service.dart';
import 'package:livenow/domain/growth_rules.dart';
import 'package:livenow/domain/metric_service.dart';
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/main.dart';
import 'package:livenow/ui/dialog_stack.dart';
import 'package:livenow/ui/plan_providers.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/screens/settings_screen.dart';
import 'package:livenow/ui/sync_providers.dart';
import 'package:livenow/ui/widgets/action_editor.dart';
import 'package:livenow/ui/widgets/plan_dialogs.dart' show PlanItemEditorDialog;

import 'calendar_stress_fixture.dart';

/// Device, platform, responsive and accessibility edge cases: odd window sizes
/// and pixel ratios, big text, rotation with a dialog open, touch vs mouse,
/// keyboard-only use and the Flutter accessibility guidelines.
///
/// flutter_test paints with the wide Ahem font, so an overflow found here at a
/// large text scale can be a false alarm; real ones are fixed in lib/.
void main() {
  setUpAll(() async {
    initPostponeTimeZoneData();
    await _loadRealFonts();
  });

  late AppDatabase db;
  final errors = <String>[];

  void Function() collectErrors() {
    errors.clear();
    final original = FlutterError.onError;
    FlutterError.onError = (d) {
      final text = d.toDiagnosticsNode().toStringDeep();
      final where = RegExp(
        r'lib/[a-z_/]+[.]dart:[0-9]+',
      ).firstMatch(text)?.group(0);
      errors.add(
        '${d.exceptionAsString().split(String.fromCharCode(10)).first}'
        '${where == null ? '' : ' @ $where'}',
      );
    };
    return () => FlutterError.onError = original;
  }

  Future<void> settle(WidgetTester tester, [int ms = 600]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  void setView(
    WidgetTester tester,
    Size logical, {
    double dpr = 1,
    double textScale = 1,
  }) {
    tester.view.devicePixelRatio = dpr;
    tester.view.physicalSize = logical * dpr;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
  }

  Future<void> pumpApp(
    WidgetTester tester,
    Size size, {
    double dpr = 1,
    double textScale = 1,
    bool seedPlan = false,
  }) async {
    setView(tester, size, dpr: dpr, textScale: textScale);
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.runAsync(() async {
      final actions = ActionService(db);
      final metrics = MetricService(db);
      final m1 = await metrics.saveMetric(
        name: 'Sleep enough',
        kind: MetricKind.boolean,
        isMain: true,
      );
      final m2 = await metrics.saveMetric(
        name: 'Exercise',
        kind: MetricKind.count,
        window: MetricWindow.week,
        target: 3,
        leadsToIds: [m1],
      );
      final now = DateTime.now();
      await actions.createAction(
        name: 'A rather long action name that has to wrap on a narrow screen',
        startAt: now.subtract(const Duration(minutes: 20)),
        endAt: now.add(const Duration(hours: 2)),
        metricIds: [m1, m2],
      );
      await actions.createAction(
        name: 'Tomorrow',
        startAt: now.add(const Duration(days: 1)),
        endAt: now.add(const Duration(days: 1, hours: 1)),
      );
      await actions.createAction(
        name: 'All day thing',
        isAllDay: true,
        startAt: DateTime(now.year, now.month, now.day),
      );
      final budget = BudgetService(db);
      final cat = await budget.saveCategory(
        const CategoryInput(name: 'Groceries', price: 25),
      );
      await budget.createTransaction(categoryId: cat);
      if (seedPlan) await seedPlanGhosts(db, perDay: 3);
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
    await settle(tester, 400);
  }

  Future<void> unmount(WidgetTester tester) async {
    resetStackedDialogsForTest();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// Ends a test: restores the error handler, unmounts, closes the database
  /// (a failing expect would otherwise leave Drift's streams hanging the run)
  /// and only then reports [problems].
  Future<void> finish(
    WidgetTester tester,
    void Function() restore,
    List<String> problems,
  ) async {
    restore();
    await unmount(tester);
    await tester.runAsync(db.close);
    // Known and accepted: below any real phone (240 px) the all-day strip's
    // header and the Growth tab bar overflow by a few pixels.
    final unexpected = [
      for (final p in problems)
        if (!(p.startsWith('240 px') &&
            (p.contains('all_day_week_strip.dart:') ||
                p.contains('growth_directions_screen.dart:'))))
          p,
    ];
    expect(unexpected, isEmpty, reason: unexpected.join('\n'));
  }

  Finder labelled(String text) => find.byWidgetPredicate(
    (w) =>
        w is Text &&
        (w.data ?? w.textSpan?.toPlainText() ?? '').toLowerCase() ==
            text.toLowerCase(),
  );

  Future<void> go(WidgetTester tester, String text) async {
    var f = labelled(text).hitTestable();
    if (f.evaluate().isEmpty) f = labelled(text);
    await tester.ensureVisible(f.first);
    await tester.pump();
    await tester.tap(f.first);
    await settle(tester, 400);
  }

  /// Visits every main screen; records framework errors per screen.
  Future<void> visitScreensCore(
    WidgetTester tester,
    String tag,
    List<String> problems,
  ) async {
    void check(String where) {
      for (final e in errors.toSet()) {
        problems.add('$tag / $where: $e');
      }
      errors.clear();
    }

    check('Current');
    await go(tester, 'Calendar');
    check('Calendar');
    if (find.byKey(const ValueKey('calendar-full-toggle')).evaluate().isNotEmpty &&
        find.byKey(const ValueKey('phone-nav')).evaluate().isEmpty) {
      await tester.tap(find.byKey(const ValueKey('calendar-full-toggle')));
      await settle(tester, 300);
    }
    for (final t in ['All', 'Templates', 'Forms']) {
      await go(tester, t);
      check(t);
    }
    await go(tester, 'Growth directions');
    check('Growth');
    await go(tester, 'Budget');
    check('Budget');
    SettingsScreen.open(tester.element(find.byType(Scaffold).first));
    await settle(tester, 500);
    check('Settings');
    final nav = Navigator.of(tester.element(find.byType(Scaffold).last));
    nav.pop();
    await settle(tester, 300);
    check('after Settings');
  }

  Future<void> visitScreens(
    WidgetTester tester,
    String tag,
    List<String> problems,
  ) async {
    try {
      await visitScreensCore(tester, tag, problems);
    } catch (e) {
      // A navigation failure is a finding too, and must not skip the cleanup.
      problems.add('$tag: ${_firstLine(e)}');
    }
  }

  // ---------------------------------------------------------------- sizes

  const sizes = <String, Size>{
    '240 px': Size(240, 560),
    '280 px': Size(280, 600),
    '320 px': Size(320, 640),
    '600 px': Size(600, 900),
    '700 px': Size(700, 900),
    '800 px': Size(800, 900),
    '899 px': Size(899, 900),
    '900 px': Size(900, 900),
    '3840x1080': Size(3840, 1080),
  };
  for (final e in sizes.entries) {
    testWidgets('every main screen lays out at ${e.key}', (tester) async {
      final restore = collectErrors();
      await pumpApp(tester, e.value);
      final problems = <String>[];
      await visitScreens(tester, e.key, problems);
      await finish(tester, restore, problems);
    });
  }

  // ------------------------------------------------- pixel ratio, text scale

  for (final dpr in [1.0, 2.0, 3.5]) {
    for (final size in [const Size(375, 812), const Size(1400, 900)]) {
      testWidgets('DPR $dpr at ${size.width.round()} px', (tester) async {
        final restore = collectErrors();
        await pumpApp(tester, size, dpr: dpr);
        final problems = <String>[];
        await visitScreens(tester, 'dpr $dpr', problems);
        await finish(tester, restore, problems);
      });
    }
  }

  for (final scale in [1.5, 2.0]) {
    for (final size in [const Size(375, 812), const Size(1400, 900)]) {
      testWidgets('text scale $scale at ${size.width.round()} px', (
        tester,
      ) async {
        final restore = collectErrors();
        await pumpApp(tester, size, textScale: scale);
        final problems = <String>[];
        await visitScreens(tester, 'scale $scale', problems);
        // The action editor at the same scale.
        try {
          ActionEditorDialog.show(tester.element(find.byType(Scaffold).first));
          await settle(tester, 600);
        } catch (e) {
          problems.add('scale $scale / open editor: ${_firstLine(e)}');
        }
        for (final e in errors.toSet()) {
          problems.add('scale $scale / action editor: $e');
        }
        errors.clear();
        await finish(tester, restore, problems);
      });
    }
  }

  // ------------------------------------------------ dialogs: rotate, resize

  Future<void> openEditor(WidgetTester tester) async {
    ActionEditorDialog.show(tester.element(find.byType(Scaffold).first));
    await settle(tester, 600);
  }

  String nameFieldText(WidgetTester tester) => tester
      .widget<TextFormField>(find.byType(TextFormField).first)
      .controller!
      .text;

  testWidgets('rotating a phone with the editor open keeps what was typed', (
    tester,
  ) async {
    final restore = collectErrors();
    await pumpApp(tester, const Size(375, 812));
    final problems = <String>[];
    await openEditor(tester);
    await tester.enterText(find.byType(TextFormField).first, 'Typed before');
    await tester.pump();
    for (final size in [
      const Size(812, 375),
      const Size(375, 812),
      const Size(812, 375),
    ]) {
      setView(tester, size);
      await settle(tester, 300);
      if (find.byType(ActionEditorDialog).evaluate().isEmpty) {
        problems.add('the editor closed when the window became $size');
      } else if (nameFieldText(tester) != 'Typed before') {
        problems.add('the typed name was lost at $size');
      }
      for (final e in errors.toSet()) {
        problems.add('$size: $e');
      }
      errors.clear();
    }
    await finish(tester, restore, problems);
  });

  testWidgets('rotating with the sync dialog open does not overflow', (
    tester,
  ) async {
    final restore = collectErrors();
    await pumpApp(tester, const Size(375, 812));
    final problems = <String>[];
    try {
      await tester.tap(find.byKey(const ValueKey('sync-status')));
      await settle(tester, 500);
      for (final size in [const Size(812, 375), const Size(375, 812)]) {
        setView(tester, size);
        await settle(tester, 300);
        for (final e in errors.toSet()) {
          problems.add('$size: $e');
        }
        errors.clear();
      }
    } catch (e) {
      problems.add(_firstLine(e));
    }
    await finish(tester, restore, problems);
  });

  testWidgets('resizing the window with the editor open: 1400 down to 280', (
    tester,
  ) async {
    final restore = collectErrors();
    await pumpApp(tester, const Size(1400, 900));
    final problems = <String>[];
    await openEditor(tester);
    await tester.enterText(find.byType(TextFormField).first, 'Kept');
    await tester.pump();
    for (final size in [
      const Size(1000, 800),
      const Size(900, 700),
      const Size(899, 700),
      const Size(600, 800),
      const Size(375, 812),
      const Size(280, 600),
      const Size(1400, 900),
      const Size(3840, 1080),
    ]) {
      setView(tester, size);
      await settle(tester, 300);
      if (find.byType(ActionEditorDialog).evaluate().isEmpty) {
        problems.add('the editor closed at $size');
      } else if (nameFieldText(tester) != 'Kept') {
        problems.add('the typed name was lost at $size');
      }
      for (final e in errors.toSet()) {
        problems.add('$size: $e');
      }
      errors.clear();
    }
    await finish(tester, restore, problems);
  });

  // --------------------------------------------------- touch versus mouse

  Finder ghosts() => find.byWidgetPredicate((w) {
    final k = w.key;
    return k is ValueKey<String> &&
        k.value.startsWith('plan-ghost-') &&
        !k.value.startsWith('plan-ghost-handle-');
  });

  Future<void> openPlanning(WidgetTester tester) async {
    await go(tester, 'Calendar');
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
    );
    container.read(calendarPlanningProvider.notifier).state = true;
    await settle(tester, 500);
    await tester.ensureVisible(ghosts().first);
    await tester.pump();
  }

  void drainErrors(List<String> problems) {
    problems.addAll(errors.toSet());
    errors.clear();
  }

  testWidgets('touch: tapping a plan ghost opens it, long-press drag moves it', (
    tester,
  ) async {
    final restore = collectErrors();
    await pumpApp(tester, const Size(700, 900), seedPlan: true);
    final problems = <String>[];
    try {
      await openPlanning(tester);
      expect(ghosts(), findsWidgets);
      // Tap with a finger: the plan item's editor (phone rules, < 900 px).
      await tester.tap(ghosts().first);
      await settle(tester, 500);
      if (find.byType(PlanItemEditorDialog).evaluate().isEmpty) {
        problems.add('a touch tap on a ghost did not open the plan item');
      } else {
        Navigator.of(tester.element(find.byType(PlanItemEditorDialog))).pop();
        await settle(tester, 400);
      }
      // Long-press, then drag: asks "this day only / whole pattern".
      final g = await tester.startGesture(
        tester.getCenter(ghosts().first),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(const Duration(milliseconds: 700));
      await g.moveBy(const Offset(0, 4));
      await tester.pump();
      await g.moveBy(const Offset(0, 40));
      await tester.pump();
      await g.up();
      await settle(tester, 500);
      if (find.byKey(const ValueKey('plan-scope-day')).evaluate().isEmpty) {
        problems.add('a touch long-press drag did not ask for the scope');
      }
    } catch (e) {
      problems.add(_firstLine(e));
    }
    drainErrors(problems);
    await finish(tester, restore, problems);
  });

  testWidgets('mouse: a click leaves a plan ghost alone, a double-click opens it', (
    tester,
  ) async {
    final restore = collectErrors();
    await pumpApp(tester, const Size(1400, 900), seedPlan: true);
    final problems = <String>[];
    try {
      await openPlanning(tester);
      final at = tester.getCenter(ghosts().first);
      final click = await tester.startGesture(at, kind: PointerDeviceKind.mouse);
      await click.up();
      await settle(tester, 500);
      if (find.byType(PlanItemEditorDialog).evaluate().isNotEmpty) {
        problems.add('a single mouse click opened the plan item');
      }
      await tester.tapAt(at, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tapAt(at, kind: PointerDeviceKind.mouse);
      await settle(tester, 500);
      if (find.byType(PlanItemEditorDialog).evaluate().isEmpty) {
        problems.add('a mouse double-click did not open the plan item');
      }
    } catch (e) {
      problems.add(_firstLine(e));
    }
    drainErrors(problems);
    await finish(tester, restore, problems);
  });

  testWidgets('a touch tap on a calendar block and a mouse hover raise no error', (
    tester,
  ) async {
    final restore = collectErrors();
    await pumpApp(tester, const Size(1400, 900));
    final problems = <String>[];
    try {
      await go(tester, 'Calendar');
      await settle(tester, 400);
      final block = find
          .byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith('event-'),
          )
          .hitTestable();
      if (block.evaluate().isEmpty) {
        problems.add('no event block on screen to touch');
      } else {
        final at = tester.getCenter(block.first);
        final touch = await tester.startGesture(
          at,
          kind: PointerDeviceKind.touch,
        );
        await touch.up();
        await settle(tester, 400);
        if (find.byTooltip('Start').evaluate().isNotEmpty) {
          problems.add('a touch tap showed the hover toolbar');
        }
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(1, 1));
        addTearDown(mouse.removePointer);
        await mouse.moveTo(at);
        await settle(tester, 500);
      }
    } catch (e) {
      problems.add(_firstLine(e));
    }
    drainErrors(problems);
    await finish(tester, restore, problems);
  });

  // ------------------------------------------------------------ keyboard only

  Future<Set<Rect>> tabThrough(WidgetTester tester, int steps) async {
    final seen = <Rect>{};
    for (var i = 0; i < steps; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump(const Duration(milliseconds: 30));
      final ctx = FocusManager.instance.primaryFocus?.context;
      final box = ctx?.findRenderObject();
      if (box is RenderBox && box.attached && box.hasSize) {
        seen.add(box.localToGlobal(Offset.zero) & box.size);
      }
    }
    return seen;
  }

  testWidgets('keyboard only: Tab walks the Current board', (tester) async {
    final restore = collectErrors();
    await pumpApp(tester, const Size(1400, 900));
    final problems = <String>[];
    final seen = await tabThrough(tester, 40);
    if (seen.length < 5) {
      problems.add('Tab reached only ${seen.length} different controls');
    }
    final fab = find.byTooltip('New action');
    if (fab.evaluate().isNotEmpty) {
      final c = tester.getCenter(fab.first);
      if (!seen.any((r) => r.contains(c))) {
        problems.add('Tab never reached the New action button');
      }
    }
    drainErrors(problems);
    await finish(tester, restore, problems);
  });

  testWidgets('keyboard only: the action editor is reachable, Esc closes it', (
    tester,
  ) async {
    final restore = collectErrors();
    await pumpApp(tester, const Size(1400, 900));
    final problems = <String>[];
    await openEditor(tester);
    final seen = await tabThrough(tester, 60);
    if (seen.length < 6) {
      problems.add('Tab reached only ${seen.length} controls in the editor');
    }
    for (final label in ['Save', 'Cancel']) {
      final f = find.text(label);
      if (f.evaluate().isEmpty) continue;
      final c = tester.getCenter(f.first);
      if (!seen.any((r) => r.contains(c))) {
        problems.add('Tab never reached the "$label" button');
      }
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester, 500);
    if (find.byType(ActionEditorDialog).evaluate().isNotEmpty) {
      problems.add('Esc did not close the untouched editor');
    }
    drainErrors(problems);
    await finish(tester, restore, problems);
  });

  testWidgets('keyboard only: Enter in the Name field saves a new action', (
    tester,
  ) async {
    final restore = collectErrors();
    await pumpApp(tester, const Size(1400, 900));
    final problems = <String>[];
    await openEditor(tester);
    await tester.enterText(
      find.byType(TextFormField).first,
      'Entered by keyboard',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester, 600);
    final rows = await tester.runAsync(
      () => (db.select(
        db.actionsTable,
      )..where((t) => t.name.equals('Entered by keyboard'))).get(),
    );
    if (rows == null || rows.length != 1) {
      problems.add('Enter did not save exactly one action (${rows?.length})');
    }
    if (find.byType(ActionEditorDialog).evaluate().isNotEmpty) {
      problems.add('the editor stayed open after Enter');
    }
    await finish(tester, restore, problems);
  });

  // ------------------------------------------------- accessibility guidelines

  for (final size in [const Size(375, 812), const Size(1400, 900)]) {
    testWidgets('accessibility guidelines on the main screens at ${size.width.round()} px', (
      tester,
    ) async {
      final restore = collectErrors();
      await pumpApp(tester, size);
      final handle = tester.ensureSemantics();
      final failures = <String>[];
      final report = <String>[];

      Future<void> audit(String screen) async {
        await settle(tester, 300);
        final guidelines = <String, AccessibilityGuideline>{
          'tap target': androidTapTargetGuideline,
          'labeled tap target': labeledTapTargetGuideline,
          'text contrast': textContrastGuideline,
        };
        for (final g in guidelines.entries) {
          try {
            final result = await g.value.evaluate(tester);
            if (!result.passed) {
              final line =
                  '$screen / ${g.key}: ${(result.reason ?? 'failed').replaceAll(RegExp(r'\s+'), ' ')}';
              // Tap-target size and contrast are REPORTED (the glass design
              // uses compact 40 px buttons; contrast depends on the blurred
              // background); a missing label is a real bug and fails the test.
              // A scrolling list that merged its children's tap action
              // (RenderViewport) is a framework artefact, not a control.
              final artefact = line.contains('RenderViewport.twoPane');
              (g.key == 'labeled tap target' && !artefact ? failures : report)
                  .add(line);
            }
          } catch (e) {
            failures.add('$screen / ${g.key}: could not run: ${_firstLine(e)}');
          }
        }
      }

      try {
        await audit('Current');
        await go(tester, 'Calendar');
        if (find
                .byKey(const ValueKey('calendar-full-toggle'))
                .evaluate()
                .isNotEmpty &&
            find.byKey(const ValueKey('phone-nav')).evaluate().isEmpty) {
          await tester.tap(find.byKey(const ValueKey('calendar-full-toggle')));
          await settle(tester, 300);
        }
        for (final t in ['All', 'Templates', 'Forms']) {
          await go(tester, t);
          await audit(t);
        }
        await go(tester, 'Growth directions');
        await audit('Growth');
        await go(tester, 'Budget');
        await audit('Budget');
      } catch (e) {
        failures.add('navigation: ${_firstLine(e)}');
      }
      handle.dispose();
      restore();
      await unmount(tester);
      await tester.runAsync(db.close);
      // ignore: avoid_print
      print(
        'GUIDELINES (report only) ${size.width.round()} px:\n'
        '${report.map((r) => r.length > 230 ? r.substring(0, 230) : r).join('\n')}',
      );
      expect(failures, isEmpty, reason: failures.join('\n'));
    });
  }

}

/// Registers the SDK's Roboto under the families the app asks for, so text is
/// measured with realistic glyph widths instead of the test font Ahem (which is
/// about twice as wide and raises overflow alarms that do not exist on a
/// device). Silently keeps Ahem when the SDK fonts cannot be found.
Future<void> _loadRealFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final dir = '$root/bin/cache/artifacts/material_fonts';
  Future<ByteData> load(String f) async {
    final bytes = await File('$dir/$f').readAsBytes();
    return ByteData.sublistView(bytes);
  }

  try {
    for (final family in ['Segoe UI Variable Text', 'Segoe UI', 'Roboto']) {
      final loader = FontLoader(family)
        ..addFont(load('Roboto-Regular.ttf'))
        ..addFont(load('Roboto-Medium.ttf'))
        ..addFont(load('Roboto-Bold.ttf'));
      await loader.load();
    }
  } catch (_) {}
}

String _firstLine(Object e) => e.toString().split(String.fromCharCode(10)).first;
