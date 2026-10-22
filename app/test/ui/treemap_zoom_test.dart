import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/domain/treemap_layout.dart';
import 'package:livenow/ui/widgets/treemap_canvas.dart';

void main() {
  const window = Size(800, 600);

  List<TreemapItem> items(int n) => [
    for (var i = 0; i < n; i++)
      TreemapItem('i${i.toString().padLeft(3, '0')}', (n - i).toDouble()),
  ];

  Future<void> pump(WidgetTester tester, {int n = 4}) async {
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TreemapCanvas(
            items: items(n),
            tileBuilder: (id, rect) => SizedBox.expand(
              key: ValueKey('tile-$id'),
              child: Text('$id ${rect.width.round()}x${rect.height.round()}'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder tile(String id) => find.byKey(ValueKey('tile-$id'));
  // A tile is its zoomed slot minus the fixed gap, so compare the slots.
  double width(WidgetTester t, String id) =>
      t.getSize(tile(id)).width + kTreemapGap;
  TreemapCanvasState state(WidgetTester t) =>
      t.state<TreemapCanvasState>(find.byType(TreemapCanvas));
  String label(WidgetTester t) =>
      t.widget<Text>(find.byKey(const ValueKey('treemap-zoom-label'))).data!;

  testWidgets('at 1x it is exactly the window and the label says 1x', (
    tester,
  ) async {
    await pump(tester);
    expect(label(tester), '1x');
    expect(state(tester).zoom, 1);
    // Reset and Zoom out are disabled at 1x.
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('treemap-zoom-reset')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('treemap-zoom-out')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('the buttons grow a block by the step ratio; reset restores 1x', (
    tester,
  ) async {
    await pump(tester);
    final w1 = width(tester, 'i000');
    await tester.tap(find.byKey(const ValueKey('treemap-zoom-in')));
    await tester.pump();
    expect(label(tester), '1.5x');
    expect(width(tester, 'i000'), closeTo(w1 * 1.5, 0.01));
    await tester.tap(find.byKey(const ValueKey('treemap-zoom-in')));
    await tester.pump();
    expect(label(tester), '2x');
    expect(width(tester, 'i000'), closeTo(w1 * 2, 0.01));

    await tester.tap(find.byKey(const ValueKey('treemap-zoom-out')));
    await tester.pump();
    expect(label(tester), '1.5x');

    await tester.tap(find.byKey(const ValueKey('treemap-zoom-reset')));
    await tester.pump();
    expect(label(tester), '1x');
    expect(width(tester, 'i000'), closeTo(w1, 0.01));
  });

  testWidgets('Ctrl+= , Ctrl+- and Ctrl+0 zoom in, out and reset', (
    tester,
  ) async {
    await pump(tester);
    // A tap gives the canvas the keyboard focus.
    await tester.tapAt(const Offset(100, 100));
    await tester.pump();
    Future<void> ctrl(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    await ctrl(LogicalKeyboardKey.equal);
    expect(state(tester).zoom, 1.5);
    await ctrl(LogicalKeyboardKey.equal);
    expect(state(tester).zoom, 2);
    await ctrl(LogicalKeyboardKey.minus);
    expect(state(tester).zoom, 1.5);
    await ctrl(LogicalKeyboardKey.digit0);
    expect(state(tester).zoom, 1);
  });

  testWidgets('Ctrl+wheel zooms; a plain wheel scrolls and does not', (
    tester,
  ) async {
    await pump(tester);
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    const at = Offset(300, 300);

    // Plain wheel at 1x: nothing to scroll, no zoom.
    await tester.sendEventToBinding(mouse.hover(at));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 100)));
    await tester.pump();
    expect(state(tester).zoom, 1);

    // Ctrl + wheel up (negative) = zoom in.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -100)));
    await tester.pump();
    expect(state(tester).zoom, 1.5);

    // Zoomed in, a plain wheel scrolls the chart vertically, zoom unchanged.
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    final before = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 100)));
    await tester.pump();
    final after = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;
    expect(after, greaterThan(before));
    expect(state(tester).zoom, 1.5);
  });

  testWidgets('a two-finger pinch zooms in and then out', (tester) async {
    await pump(tester);
    final a = await tester.startGesture(const Offset(300, 300));
    final b = await tester.startGesture(const Offset(400, 300));
    // Fingers apart: distance 100 -> 200 is a ratio of 2.
    await b.moveTo(const Offset(500, 300));
    await tester.pump();
    expect(state(tester).zoom, greaterThan(1));
    final zoomed = state(tester).zoom;
    // Fingers together again.
    await b.moveTo(const Offset(350, 300));
    await tester.pump();
    expect(state(tester).zoom, lessThan(zoomed));
    await a.up();
    await b.up();
    await tester.pump();
  });

  testWidgets('at 8x only the blocks near the viewport are built', (
    tester,
  ) async {
    await pump(tester, n: 200);
    final at1 = find.byWidgetPredicate(
      (w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('tile-'),
    );
    expect(at1.evaluate().length, 200);

    for (var i = 0; i < 6; i++) {
      await tester.tap(find.byKey(const ValueKey('treemap-zoom-in')));
      await tester.pump();
    }
    expect(state(tester).zoom, 8);
    expect(at1.evaluate().length, lessThan(100));
  });
}
