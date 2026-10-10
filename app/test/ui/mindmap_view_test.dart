import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/data/database.dart';
import 'package:livenow/domain/growth_rules.dart';
import 'package:livenow/domain/metric_service.dart';
import 'package:livenow/domain/mindmap_layout.dart'
    show mindmapNodeHeight, mindmapNodeWidth;
import 'package:livenow/domain/postpone_rules.dart';
import 'package:livenow/ui/providers.dart';
import 'package:livenow/ui/widgets/mindmap_view.dart'
    show
        MindmapEdgeRole,
        mindmapEdgeMidpoint,
        mindmapEdgeOpacity,
        mindmapEdgeRole;
import 'package:livenow/ui/screens/growth_directions_screen.dart';
import 'package:livenow/ui/urgency_colors.dart';

void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  late String mainId, alphaId, betaId;

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

  /// Main (icon P), Alpha -> Main, and an unlinked Beta; positioned so the
  /// test does not depend on the automatic layout unless [placed] is off.
  Future<void> pumpMap(
    WidgetTester tester, {
    bool placed = true,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.runAsync(() async {
      final m = MetricService(db);
      mainId = await m.saveMetric(
        name: 'Main',
        kind: MetricKind.boolean,
        isMain: true,
        icon: const Value('P'),
      );
      alphaId = await m.saveMetric(
        name: 'Alpha',
        kind: MetricKind.count,
        window: MetricWindow.week,
        target: 4,
        leadsToIds: [mainId],
      );
      betaId = await m.saveMetric(
        name: 'Beta',
        kind: MetricKind.count,
        window: MetricWindow.week,
        target: 4,
      );
      if (placed) {
        await m.savePositions({
          mainId: (100.0, 100.0),
          alphaId: (500.0, 100.0),
          betaId: (500.0, 400.0),
        });
      }
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: const GrowthDirectionsScreen(),
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('Mindmap'));
    await animate(tester);
    await settle(tester);
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) async {
    // A node's tap waits 300 ms for a possible second tap (double-click).
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Finder node(String id) => find.byKey(ValueKey('mindmapNode-$id'));
  Finder handle(String id) => find.byKey(ValueKey('mindmapLinkHandle-$id'));

  Future<List<MetricDependency>> deps(WidgetTester tester) async =>
      (await tester.runAsync(
        () => db.select(db.metricDependenciesTable).get(),
      ))!;

  Future<Metric> row(WidgetTester tester, String id) async =>
      (await tester.runAsync(
        () => (db.select(
          db.metricsTable,
        )..where((t) => t.id.equals(id))).getSingle(),
      ))!;

  Future<void> pause(WidgetTester tester) => tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );

  /// A real mouse sends many move events; a single one (tester.drag) is all
  /// swallowed as the drag's slop and moves nothing.
  Future<void> dragSteps(WidgetTester tester, Offset from, Offset delta) async {
    final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
    final dir = delta / delta.distance;
    await g.moveBy(dir * 25);
    await g.moveBy(dir * 25);
    await g.moveBy(delta - dir * 50);
    await g.up();
    await tester.pump();
  }

  /// The node's width on screen (getSize ignores the canvas transform).
  double shownWidth(WidgetTester tester) =>
      tester.getBottomRight(node(alphaId)).dx -
      tester.getTopLeft(node(alphaId)).dx;

  Color? nodeColor(WidgetTester tester, String id) {
    final box = find.descendant(of: node(id), matching: find.byType(Container));
    return ((tester.widget<Container>(box.first)).decoration as BoxDecoration)
        .color;
  }

  testWidgets('nodes show icon and name, coloured by urgency band', (
    tester,
  ) async {
    await pumpMap(tester);
    expect(find.text('P Main'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    // Main: urgency 1000 (critical); Alpha: weight 90, progress 0 -> 90.
    expect(nodeColor(tester, mainId), urgencyColors(1000, dark: false).bg);
    expect(nodeColor(tester, alphaId), urgencyColors(90, dark: false).bg);
    expect(find.byKey(ValueKey('mindmapProgress-$alphaId')), findsOneWidget);
    await unmount(tester);
  });

  test('arrow roles: green into the selection, blue out of it', () {
    // Edge = from (sub-direction) -> to (the direction it leads to).
    expect(mindmapEdgeRole({'x'}, 'a', 'x'), MindmapEdgeRole.intoSelected);
    expect(mindmapEdgeRole({'x'}, 'x', 'b'), MindmapEdgeRole.outOfSelected);
    expect(mindmapEdgeRole({'x'}, 'a', 'b'), MindmapEdgeRole.none);
    expect(mindmapEdgeRole({}, 'a', 'b'), MindmapEdgeRole.none);
    // Both ends selected: it points into a selected node.
    expect(mindmapEdgeRole({'x', 'y'}, 'x', 'y'), MindmapEdgeRole.intoSelected);
  });

  testWidgets('dragging a node stores its new position', (tester) async {
    await pumpMap(tester);
    await dragSteps(
      tester,
      tester.getCenter(node(betaId)),
      const Offset(0, 100),
    );
    await pause(tester);
    await tester.pump();
    final saved = await row(tester, betaId);
    expect(saved.posX, closeTo(500, 0.5));
    expect(saved.posY, inInclusiveRange(450, 500));
    await unmount(tester);
  });

  testWidgets('dragging from a handle onto another node links them', (
    tester,
  ) async {
    await pumpMap(tester);
    await dragSteps(
      tester,
      tester.getCenter(handle(betaId)),
      tester.getCenter(node(mainId)) - tester.getCenter(handle(betaId)),
    );
    await pause(tester);
    await tester.pump();
    final all = await deps(tester);
    expect(
      all.any((e) => e.metricId == mainId && e.dependsOnId == betaId),
      isTrue,
    );
    await unmount(tester);
  });

  testWidgets('a link that would close a loop shows the message', (
    tester,
  ) async {
    await pumpMap(tester);
    // Alpha leads to Main already; Main leading to Alpha would be a loop.
    await dragSteps(
      tester,
      tester.getCenter(handle(mainId)),
      tester.getCenter(node(alphaId)) - tester.getCenter(handle(mainId)),
    );
    await pause(tester);
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);
    expect((await deps(tester)).length, 1);
    await tester.pump(const Duration(seconds: 6));
    await unmount(tester);
  });

  testWidgets('releasing a link over nothing does nothing', (tester) async {
    await pumpMap(tester);
    await dragSteps(
      tester,
      tester.getCenter(handle(betaId)),
      const Offset(0, 200),
    );
    await pause(tester);
    await tester.pump();
    expect((await deps(tester)).length, 1);
    expect(find.byType(SnackBar), findsNothing);
    await unmount(tester);
  });

  testWidgets(
    'selecting an edge and pressing Delete removes it; Undo restores',
    (tester) async {
      await pumpMap(tester);
      final mid =
          (tester.getCenter(node(mainId)) + tester.getCenter(node(alphaId))) /
          2;
      await tester.tapAt(mid);
      await tester.pump();
      expect(find.byKey(const ValueKey('mindmapEdgeDelete')), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await pause(tester);
      await tester.pump();
      expect(await deps(tester), isEmpty);
      expect(find.byKey(const ValueKey('mindmapEdgeDelete')), findsNothing);

      await animate(tester);
      await tester.runAsync(() async {
        await tester.tap(find.text('Undo'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      final restored = await deps(tester);
      expect(restored.single.metricId, mainId);
      expect(restored.single.dependsOnId, alphaId);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await settle(tester);
      await unmount(tester);
    },
  );

  testWidgets('the edge delete button removes the selected edge', (
    tester,
  ) async {
    await pumpMap(tester);
    await tester.tapAt(
      (tester.getCenter(node(mainId)) + tester.getCenter(node(alphaId))) / 2,
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mindmapEdgeDelete')));
    await pause(tester);
    await tester.pump();
    expect(await deps(tester), isEmpty);
    await tester.pump(const Duration(seconds: 6));
    await unmount(tester);
  });

  testWidgets('Radial around selected persists positions', (tester) async {
    await pumpMap(tester);
    final radial = find.widgetWithText(TextButton, 'Radial around selected');
    expect(tester.widget<TextButton>(radial).onPressed, isNull);

    await dragSteps(
      tester,
      tester.getCenter(node(mainId)),
      const Offset(60, 0),
    ); // selects it
    await pause(tester);
    await tester.pump();
    await tester.tap(radial);
    await pause(tester);
    await tester.pump();

    final rows = await tester.runAsync(() => db.select(db.metricsTable).get());
    final moved = rows!.firstWhere((r) => r.id == alphaId);
    expect(
      (moved.posX, moved.posY) != (500.0, 100.0),
      isTrue,
      reason: 'the radial layout was saved',
    );
    await unmount(tester);
  });

  testWidgets('opening does not save a layout; Auto layout does', (
    tester,
  ) async {
    await pumpMap(tester, placed: false);
    expect(node(mainId), findsOneWidget);
    expect((await row(tester, mainId)).posX, isNull);

    await tester.tap(find.text('Auto layout'));
    await pause(tester);
    await tester.pump();
    final saved = await row(tester, mainId);
    expect(saved.posX, isNotNull);
    expect(saved.posY, isNotNull);
    await unmount(tester);
  });

  testWidgets('zoom and fit buttons change the canvas scale', (tester) async {
    await pumpMap(tester);
    final before = shownWidth(tester);
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pump();
    expect(shownWidth(tester), greaterThan(before));
    await tester.tap(find.byTooltip('Fit all'));
    await tester.pump();
    expect(shownWidth(tester), closeTo(before, 0.5));
    await unmount(tester);
  });

  testWidgets('the wheel and the buttons zoom a node to over 2000 px wide', (
    tester,
  ) async {
    // Guards the zoom ceiling: at maximum zoom a 190 px node must fill most
    // of the screen (about 12x), so a single direction is easy to read.
    await pumpMap(tester);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.hover(tester.getCenter(node(alphaId))),
    );
    for (var i = 0; i < 80; i++) {
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -120)));
      await tester.pump();
    }
    expect(shownWidth(tester), greaterThan(2000));

    await tester.tap(find.byTooltip('Fit all'));
    await tester.pump();
    for (var i = 0; i < 30; i++) {
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
    }
    expect(shownWidth(tester), greaterThan(2000));
    await unmount(tester);
  });

  // ---- drag follows the mouse at any zoom -----------------------------------

  for (final zoom in [(-3, 'zoomed out'), (0, 'at 100%'), (5, 'zoomed in')]) {
    testWidgets('a node follows the mouse exactly when ${zoom.$2}', (
      tester,
    ) async {
      await pumpMap(tester);
      for (var i = 0; i < zoom.$1.abs(); i++) {
        await tester.tap(find.byTooltip(zoom.$1 < 0 ? 'Zoom out' : 'Zoom in'));
        await tester.pump();
      }
      final scale = shownWidth(tester) / (mindmapNodeWidth + 8);
      final before = tester.getTopLeft(node(betaId));
      final startY = (await row(tester, betaId)).posY!;

      await dragSteps(
        tester,
        tester.getCenter(node(betaId)),
        const Offset(0, 200),
      );
      await pause(tester);
      await tester.pump();

      final screenMoved = tester.getTopLeft(node(betaId)) - before;
      final canvasMoved = (await row(tester, betaId)).posY! - startY;
      // Same as the pointer, less the few pixels the drag recogniser eats.
      expect(screenMoved.dx, closeTo(0, 0.5));
      expect(screenMoved.dy, inInclusiveRange(140, 200));
      expect(canvasMoved * scale, closeTo(screenMoved.dy, 0.5));
      await unmount(tester);
    });
  }

  // ---- multi-select ----------------------------------------------------------

  bool isSelected(WidgetTester tester, String id) {
    final box = find.descendant(of: node(id), matching: find.byType(Container));
    final deco =
        tester.widget<Container>(box.first).decoration as BoxDecoration;
    return (deco.border as Border).top.width == 2;
  }

  Set<String> selectedIds(WidgetTester tester) => {
    for (final id in [mainId, alphaId, betaId])
      if (isSelected(tester, id)) id,
  };

  /// A left-drag rectangle on the canvas (raw pointer, like a mouse).
  Future<void> marquee(WidgetTester tester, Offset a, Offset b) async {
    final g = await tester.startGesture(a, kind: PointerDeviceKind.mouse);
    await g.moveTo(Offset.lerp(a, b, 0.5)!);
    await g.moveTo(b);
    await g.up();
    await tester.pump();
  }

  Rect around(WidgetTester tester, List<String> ids) => ids
      .map((i) => tester.getRect(node(i)))
      .reduce((r, e) => r.expandToInclude(e));

  testWidgets('a rectangle selects the nodes it touches', (tester) async {
    await pumpMap(tester);
    final r = around(tester, [mainId, alphaId]);
    await marquee(tester, r.topLeft - const Offset(20, 20), r.bottomRight);
    expect(selectedIds(tester), {mainId, alphaId});
    await unmount(tester);
  });

  testWidgets('Ctrl+rectangle adds; a click on empty space clears', (
    tester,
  ) async {
    await pumpMap(tester);
    final b = tester.getRect(node(betaId));
    await marquee(tester, b.topLeft - const Offset(20, 20), b.bottomRight);
    expect(selectedIds(tester), {betaId});

    final m = tester.getRect(node(mainId));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await marquee(tester, m.topLeft - const Offset(20, 20), m.bottomRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(selectedIds(tester), {betaId, mainId});

    await tester.tapAt(m.topLeft - const Offset(60, 60));
    await tester.pump();
    expect(selectedIds(tester), isEmpty);
    await unmount(tester);
  });

  testWidgets('a single click only selects; a double click opens the dialog', (
    tester,
  ) async {
    await pumpMap(tester);
    await tester.tap(node(alphaId));
    await tester.pump(const Duration(milliseconds: 400));
    expect(selectedIds(tester), {alphaId});
    expect(find.byType(AlertDialog), findsNothing);

    await tester.tap(node(betaId));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(node(betaId));
    await animate(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(selectedIds(tester), {betaId});
    await settle(tester);
    await unmount(tester);
  });

  testWidgets('Ctrl+click toggles a node without opening its dialog', (
    tester,
  ) async {
    await pumpMap(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(node(alphaId));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(node(betaId));
    await tester.pump(const Duration(milliseconds: 400));
    expect(selectedIds(tester), {alphaId, betaId});
    await tester.tap(node(alphaId));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(selectedIds(tester), {betaId});
    expect(find.byType(AlertDialog), findsNothing);
    await unmount(tester);
  });

  testWidgets('Ctrl+A selects all, Escape clears; Radial needs exactly one', (
    tester,
  ) async {
    await pumpMap(tester);
    await tester.tapAt(tester.getTopLeft(node(mainId)) - const Offset(60, 60));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(selectedIds(tester), {mainId, alphaId, betaId});
    final radial = find.widgetWithText(TextButton, 'Radial around selected');
    expect(tester.widget<TextButton>(radial).onPressed, isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(selectedIds(tester), isEmpty);
    await unmount(tester);
  });

  testWidgets('dragging one node of a selection moves all and saves once', (
    tester,
  ) async {
    await pumpMap(tester);
    await tester.tapAt(tester.getTopLeft(node(mainId)) - const Offset(60, 60));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    await dragSteps(
      tester,
      tester.getCenter(node(betaId)),
      const Offset(0, 120),
    );
    await pause(tester);
    await tester.pump();

    final m = await row(tester, mainId);
    final a = await row(tester, alphaId);
    final b = await row(tester, betaId);
    final d = m.posY! - 100;
    expect(d, greaterThan(50));
    expect(a.posY! - 100, closeTo(d, 0.01));
    expect(b.posY! - 400, closeTo(d, 0.01));
    expect([m.posX, a.posX, b.posX], [100, 500, 500]);
    await unmount(tester);
  });

  // ---- panning ---------------------------------------------------------------

  Future<Offset> panWith(
    WidgetTester tester, {
    int buttons = kPrimaryButton,
    PointerDeviceKind kind = PointerDeviceKind.mouse,
  }) async {
    final before = tester.getTopLeft(node(mainId));
    final start = before - const Offset(60, 60);
    final g = await tester.startGesture(start, kind: kind, buttons: buttons);
    await g.moveBy(const Offset(40, 20));
    await g.moveBy(const Offset(60, 30));
    await g.up();
    await tester.pump();
    return tester.getTopLeft(node(mainId)) - before;
  }

  testWidgets('middle and right drags pan; a plain left drag does not', (
    tester,
  ) async {
    await pumpMap(tester);
    expect(
      await panWith(tester, buttons: kMiddleMouseButton),
      const Offset(100, 50),
    );
    expect(
      await panWith(tester, buttons: kSecondaryMouseButton),
      const Offset(100, 50),
    );
    expect(await panWith(tester), Offset.zero);
    await unmount(tester);
  });

  testWidgets('Space + left drag pans', (tester) async {
    await pumpMap(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    final moved = await panWith(tester);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    expect(moved, const Offset(100, 50));
    await unmount(tester);
  });

  testWidgets('a finger on empty space pans the map (phone)', (tester) async {
    await pumpMap(tester);
    expect(
      await panWith(tester, kind: PointerDeviceKind.touch),
      const Offset(100, 50),
    );
    await unmount(tester);
  });

  // ---- curved arrows ---------------------------------------------------------

  testWidgets('a diagonal arrow is hit on its curve, not on the chord', (
    tester,
  ) async {
    await pumpMap(tester);
    await tester.runAsync(
      () => MetricService(db).addRelation(fromId: betaId, toId: mainId),
    );
    await settle(tester);
    expect((await deps(tester)).length, 2);

    // Canvas -> screen: the fit scale is 1 for this small map.
    final shift = tester.getTopLeft(node(mainId)) - const Offset(100, 100);
    final mid = mindmapEdgeMidpoint(
      const Offset(500, 400),
      const Offset(100, 100),
    );

    // The straight chord between the box centres, a quarter of the way in,
    // is far from the S-curve.
    final chord = Offset.lerp(
      const Offset(595, 428),
      const Offset(195, 128),
      0.25,
    )!;
    await tester.tapAt(chord + shift);
    await tester.pump();
    expect(find.byKey(const ValueKey('mindmapEdgeDelete')), findsNothing);

    await tester.tapAt(mid + shift);
    await tester.pump();
    final x = find.byKey(const ValueKey('mindmapEdgeDelete'));
    expect(x, findsOneWidget);
    expect((tester.getCenter(x) - (mid + shift)).distance, lessThan(1));

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await pause(tester);
    await tester.pump();
    final left = await deps(tester);
    expect(left.single.dependsOnId, alphaId);
    await tester.pump(const Duration(seconds: 6));
    await unmount(tester);
  });

  test('arrows fade unless they touch a selected node', () {
    expect(
      mindmapEdgeOpacity(anyNodeSelected: false, touchesSelected: false),
      0.45,
    );
    expect(mindmapEdgeOpacity(anyNodeSelected: true, touchesSelected: true), 1);
    expect(
      mindmapEdgeOpacity(anyNodeSelected: true, touchesSelected: false),
      0.15,
    );
  });

  // ---- layout buttons: persist + Undo -----------------------------------------

  Future<Map<String, (double?, double?)>> stored(WidgetTester tester) async {
    final rows = await tester.runAsync(() => db.select(db.metricsTable).get());
    return {for (final r in rows!) r.id: (r.posX, r.posY)};
  }

  Future<void> selectOnly(WidgetTester tester, List<String> ids) async {
    final r = around(tester, ids);
    await marquee(tester, r.topLeft - const Offset(20, 20), r.bottomRight);
  }

  Future<void> undoSnack(WidgetTester tester) async {
    await animate(tester);
    expect(find.text('Undo'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('Undo'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await settle(tester);
  }

  for (final b in [
    ('Auto layout', false),
    ('Tree layout', false),
    ('Radial around selected', true),
    ('Tree of selected', true),
  ]) {
    testWidgets('${b.$1} persists positions and Undo restores them', (
      tester,
    ) async {
      await pumpMap(tester);
      if (b.$2) await selectOnly(tester, [mainId]);
      final before = await stored(tester);

      await tester.tap(find.widgetWithText(TextButton, b.$1));
      await pause(tester);
      await tester.pump();
      final after = await stored(tester);
      expect(after, isNot(before));

      await undoSnack(tester);
      expect(await stored(tester), before);
      await unmount(tester);
    });
  }

  testWidgets('Undo of a layout on an unplaced map restores the nulls', (
    tester,
  ) async {
    await pumpMap(tester, placed: false);
    final before = await stored(tester);
    expect(before.values.every((p) => p == (null, null)), isTrue);
    await tester.tap(find.text('Tree layout'));
    await pause(tester);
    await tester.pump();
    expect((await stored(tester)).values.every((p) => p.$1 != null), isTrue);

    await undoSnack(tester);
    expect(await stored(tester), before);
    await unmount(tester);
  });

  testWidgets(
    'Tree of selected needs exactly one node and moves only the tree',
    (tester) async {
      await pumpMap(tester);
      final button = find.widgetWithText(TextButton, 'Tree of selected');
      expect(tester.widget<TextButton>(button).onPressed, isNull);
      await selectOnly(tester, [mainId, alphaId]);
      expect(tester.widget<TextButton>(button).onPressed, isNull);

      await selectOnly(tester, [mainId]);
      expect(tester.widget<TextButton>(button).onPressed, isNotNull);
      final before = await stored(tester);
      await tester.tap(button);
      await pause(tester);
      await tester.pump();
      final after = await stored(tester);

      // Beta is not part of Main's tree: untouched. Main and Alpha moved below it.
      expect(after[betaId], before[betaId]);
      for (final id in [mainId, alphaId]) {
        expect(
          after[id]!.$2,
          greaterThanOrEqualTo(400 + mindmapNodeHeight + 120),
        );
      }
      expect(after[mainId]!.$1, greaterThanOrEqualTo(500));
      await tester.pump(const Duration(seconds: 6));
      await unmount(tester);
    },
  );

  testWidgets('glass node: fill stays the urgency colour in dark; border '
      'differs selected vs not', (tester) async {
    await pumpMap(tester, brightness: Brightness.dark);
    expect(nodeColor(tester, mainId), urgencyColors(1000, dark: true).bg);
    expect(nodeColor(tester, alphaId), urgencyColors(90, dark: true).bg);

    BoxBorder? border(String id) {
      final box = find.descendant(
        of: node(id),
        matching: find.byType(Container),
      );
      return (tester.widget<Container>(box.first).decoration as BoxDecoration)
          .border;
    }

    final plain = (border(alphaId) as Border).top;
    expect(plain.width, 1);
    await tester.tap(node(alphaId));
    await tester.pump(const Duration(milliseconds: 400));
    final picked = (border(alphaId) as Border).top;
    expect(picked.width, 2);
    expect(picked.color, isNot(plain.color));
    await unmount(tester);
  });
}
