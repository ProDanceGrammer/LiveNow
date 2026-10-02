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
import 'package:livenow/ui/screens/growth_directions_screen.dart';
import 'package:livenow/ui/widgets/mindmap_view.dart' show mindmapLodScale;

/// A 200-node generated map (10 rows x 20 columns, 400 x 200 apart): node
/// (r, c) leads to (r, c-1) and (r-1, c).
const _rows = 10, _cols = 20, _dx = 400.0, _dy = 200.0;

void main() {
  setUpAll(initPostponeTimeZoneData);

  late AppDatabase db;
  final ids = <String, String>{}; // 'r,c' -> id
  String at(int r, int c) => ids['$r,$c']!;

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> pumpBigMap(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    ids.clear();
    await tester.runAsync(() async {
      final m = MetricService(db);
      final positions = <String, (double, double)>{};
      for (var r = 0; r < _rows; r++) {
        for (var c = 0; c < _cols; c++) {
          final id = await m.saveMetric(
            name: 'N$r-$c',
            kind: MetricKind.count,
            window: MetricWindow.week,
            target: 4,
            isMain: r == 0 && c == 0,
            leadsToIds: [
              if (c > 0) ids['$r,${c - 1}']!,
              if (r > 0) ids['${r - 1},$c']!,
            ],
          );
          ids['$r,$c'] = id;
          positions[id] = (100 + c * _dx, 100 + r * _dy);
        }
      }
      await m.savePositions(positions);
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: GrowthDirectionsScreen()),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('Mindmap'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  }

  final anyNode = find.byWidgetPredicate((w) {
    final k = w.key;
    return k is ValueKey<String> && k.value.startsWith('mindmapNode-');
  });
  Finder node(String id) => find.byKey(ValueKey('mindmapNode-$id'));
  Finder handles() => find.byWidgetPredicate((w) {
    final k = w.key;
    return k is ValueKey<String> && k.value.startsWith('mindmapLinkHandle-');
  });
  Finder bars() => find.byWidgetPredicate((w) {
    final k = w.key;
    return k is ValueKey<String> && k.value.startsWith('mindmapProgress-');
  });

  double shownWidth(WidgetTester tester, String id) =>
      tester.getBottomRight(node(id)).dx - tester.getTopLeft(node(id)).dx;

  /// 2 px border = selected (both variants).
  bool isSelected(WidgetTester tester, String id) {
    final box = find.descendant(
      of: node(id),
      matching: find.byType(DecoratedBox),
    );
    final deco = tester.widget<DecoratedBox>(box.first).decoration;
    return ((deco as BoxDecoration).border as Border).top.width == 2;
  }

  int selectedCount(WidgetTester tester) {
    var n = 0;
    for (final id in ids.values) {
      if (node(id).evaluate().isNotEmpty && isSelected(tester, id)) n++;
    }
    return n;
  }

  Future<void> zoomIn(WidgetTester tester, int times) async {
    for (var i = 0; i < times; i++) {
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
    }
  }

  Future<void> fitAll(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Fit all'));
    await tester.pump();
  }

  Future<void> pause(WidgetTester tester) => tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );

  Future<void> dragSteps(WidgetTester tester, Offset from, Offset delta) async {
    final g = await tester.startGesture(from);
    final dir = delta / delta.distance;
    await g.moveBy(dir * 25);
    await g.moveBy(dir * 25);
    await g.moveBy(delta - dir * 50);
    await g.up();
    await tester.pump();
  }

  /// Canvas point -> screen, from a built node whose canvas position is known.
  Offset Function(Offset) mapping(WidgetTester tester, int r, int c) {
    final id = at(r, c);
    final s = shownWidth(tester, id) / (mindmapNodeWidth + 8);
    final origin =
        tester.getTopLeft(node(id)) - Offset(100 + c * _dx, 100 + r * _dy) * s;
    return (p) => origin + p * s;
  }

  testWidgets('zoomed far out, nodes are lite boxes that still work', (
    tester,
  ) async {
    await pumpBigMap(tester);
    // Fit-all of an 8000 px wide map is far below the threshold.
    expect(
      shownWidth(tester, at(0, 0)) / (mindmapNodeWidth + 8),
      lessThan(mindmapLodScale),
    );
    expect(anyNode, findsNWidgets(_rows * _cols));
    expect(handles(), findsNothing);
    expect(bars(), findsNothing);
    expect(
      find.descendant(of: anyNode, matching: find.byType(Text)),
      findsNothing,
    );
    expect(
      find.descendant(of: anyNode, matching: find.byType(DecoratedBox)),
      findsNWidgets(_rows * _cols),
    );

    // Drag stores a new position.
    final before = (await tester.runAsync(
      () => (db.select(
        db.metricsTable,
      )..where((t) => t.id.equals(at(7, 7)))).getSingle(),
    ))!;
    await dragSteps(
      tester,
      tester.getCenter(node(at(7, 7))),
      const Offset(0, 80),
    );
    await pause(tester);
    await tester.pump();
    final after = (await tester.runAsync(
      () => (db.select(
        db.metricsTable,
      )..where((t) => t.id.equals(at(7, 7)))).getSingle(),
    ))!;
    expect(after.posY!, greaterThan(before.posY! + 100));
    // Tap selects.
    await tester.tap(node(at(3, 4)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(selectedCount(tester), 1);
    expect(isSelected(tester, at(3, 4)), isTrue);

    // Double tap opens the dialog.
    await tester.tap(node(at(5, 5)));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(node(at(5, 5)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    await unmount(tester);
  });

  testWidgets('zoomed in, only the nodes near the viewport are built', (
    tester,
  ) async {
    await pumpBigMap(tester);
    await zoomIn(tester, 10);
    final built = anyNode.evaluate().length;
    expect(built, inInclusiveRange(1, 70), reason: 'out of $_rows x $_cols');
    // Full variant above the threshold: text, bars and handles are back.
    expect(handles(), findsNWidgets(built));
    expect(bars(), findsNWidgets(built));
    expect(find.text('N5-10'), findsOneWidget);
    expect(node(at(0, 0)), findsNothing);
    expect(node(at(9, 19)), findsNothing);
    expect(tester.takeException(), isNull);

    // Pan right with the middle button: another column arrives, an old one
    // is dropped.
    final far = at(5, 16);
    expect(node(far), findsNothing);
    for (var i = 0; i < 4; i++) {
      final g = await tester.startGesture(
        const Offset(500, 400),
        buttons: kMiddleMouseButton,
      );
      await g.moveBy(const Offset(-300, 0));
      await g.moveBy(const Offset(-300, 0));
      await g.up();
      await tester.pump();
    }
    expect(node(far), findsOneWidget);
    expect(node(at(5, 2)), findsNothing);
    expect(anyNode.evaluate().length, lessThan(70));

    await fitAll(tester);
    expect(anyNode, findsNWidgets(_rows * _cols));
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('Ctrl+A selects culled nodes too', (tester) async {
    await pumpBigMap(tester);
    await zoomIn(tester, 10);
    expect(node(at(0, 0)), findsNothing);
    // A gap between two rows of the (visible) map: focuses the canvas.
    await tester.tapAt(
      mapping(tester, 5, 10)(const Offset(100 + 10 * _dx, 100 + 5.6 * _dy)),
    );
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(selectedCount(tester), lessThan(70));

    await fitAll(tester);
    expect(anyNode, findsNWidgets(_rows * _cols));
    expect(selectedCount(tester), _rows * _cols);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(selectedCount(tester), 0);
    await unmount(tester);
  });

  testWidgets('a rectangle selects culled nodes it reaches over', (
    tester,
  ) async {
    await pumpBigMap(tester);
    await zoomIn(tester, 10);
    final toScreen = mapping(tester, 5, 10);
    // Start on empty canvas inside the view and sweep far to the left (the
    // pointer may leave the viewport); columns 2..9 of rows ~4-6 are culled.
    final start = toScreen(
      const Offset(100 + 10 * _dx - 60, 100 + 4 * _dy - 40),
    );
    final end = toScreen(const Offset(100 + 2 * _dx - 10, 100 + 6 * _dy + 100));
    expect(end.dx, lessThan(0));
    expect(node(at(5, 3)), findsNothing);
    final g = await tester.startGesture(start);
    await g.moveTo(Offset.lerp(start, end, 0.5)!);
    await g.moveTo(end);
    await g.up();
    await tester.pump();

    await fitAll(tester);
    // Rows 4..6 (their boxes reach into y), columns 2..9 and the part of 10
    // right of the start; compute from geometry rather than by hand.
    final x0 = 100 + 2 * _dx - 10, x1 = 100 + 10 * _dx - 60;
    final y0 = 100 + 4 * _dy - 40, y1 = 100 + 6 * _dy + 100;
    final want = <String>{};
    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        final left = 100 + c * _dx, top = 100 + r * _dy;
        if (left < x1 &&
            left + mindmapNodeWidth > x0 &&
            top < y1 &&
            top + mindmapNodeHeight > y0) {
          want.add(at(r, c));
        }
      }
    }
    expect(want.length, greaterThan(20));
    final got = {
      for (final id in ids.values)
        if (isSelected(tester, id)) id,
    };
    expect(got, want);
    await unmount(tester);
  });

  testWidgets('a link can be dropped on a node that is not built', (
    tester,
  ) async {
    await pumpBigMap(tester);
    await zoomIn(tester, 10);
    final source = at(5, 10), target = at(5, 2);
    expect(node(target), findsNothing);
    final toScreen = mapping(tester, 5, 10);
    final from = tester.getCenter(
      find.byKey(ValueKey('mindmapLinkHandle-$source')),
    );
    final to = toScreen(
      Offset(
        100 + 2 * _dx + mindmapNodeWidth / 2,
        100 + 5 * _dy + mindmapNodeHeight / 2,
      ),
    );
    await dragSteps(tester, from, to - from);
    await pause(tester);
    await tester.pump();
    final all = (await tester.runAsync(
      () => db.select(db.metricDependenciesTable).get(),
    ))!;
    expect(
      all.any((e) => e.metricId == target && e.dependsOnId == source),
      isTrue,
    );
    await unmount(tester);
  });

  testWidgets('a dragged node that leaves the view keeps its gesture', (
    tester,
  ) async {
    await pumpBigMap(tester);
    await zoomIn(tester, 10);
    final id = at(5, 10);
    final g = await tester.startGesture(tester.getCenter(node(id)));
    for (var i = 0; i < 8; i++) {
      await g.moveBy(const Offset(-150, 0));
    }
    expect(node(id), findsOneWidget, reason: 'the dragged node stays built');
    await g.up();
    await pause(tester);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('selected edges and arrows paint with culled endpoints', (
    tester,
  ) async {
    await pumpBigMap(tester);
    await zoomIn(tester, 10);
    // Select a node (its edges go off screen) and pan across the map.
    await tester.tap(node(at(5, 10)));
    await tester.pump(const Duration(milliseconds: 400));
    for (var i = 0; i < 3; i++) {
      final g = await tester.startGesture(
        const Offset(500, 400),
        buttons: kSecondaryMouseButton,
      );
      await g.moveBy(const Offset(400, 100));
      await g.moveBy(const Offset(400, 100));
      await g.up();
      await tester.pump();
    }
    await fitAll(tester);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });
}
