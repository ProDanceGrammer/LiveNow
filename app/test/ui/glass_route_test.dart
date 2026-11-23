import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/ui/theme/app_theme.dart';
import 'package:livenow/ui/widgets/glass.dart';

// Regression (bug 2026-11-23, img_2): a page slide moves the covered route with
// a compositing transform. When something in that route repaints mid-slide, the
// glass windows were cached for the shifted position and stayed wrong after
// the route came back (a lighter, unblurred patch in the bottom bar).
void main() {
  testWidgets('glass windows are right again after a pushed route is popped', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final shot = GlobalKey();
    final bar = GlobalKey();
    ThemeData theme(Brightness b) =>
        buildAppTheme(b).copyWith(platform: TargetPlatform.iOS);
    await tester.pumpWidget(
      RepaintBoundary(
        key: shot,
        child: MaterialApp(
          theme: theme(Brightness.dark),
          builder: (c, child) => GlassBackground(snapshot: true, child: child!),
          home: Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: GlassSurface(
              key: bar,
              radius: 0,
              shadow: false,
              child: const SizedBox(height: 80),
            ),
          ),
        ),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
        await tester.pump(const Duration(milliseconds: 150));
      }
    }

    Future<List<int>> capture() async {
      await settle();
      return (await tester.runAsync(() async {
        final b = shot.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
        final img = await b.toImage();
        final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        return data!.buffer.asUint8List();
      }))!;
    }

    await settle();
    final before = await capture();

    final nav = Navigator.of(tester.element(find.byKey(bar)));
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => const GlassPage(child: Scaffold(body: Text('page'))),
      ),
    );
    await settle();
    nav.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    // The covered route repaints in the middle of the slide.
    tester.renderObject(find.byKey(bar)).markNeedsPaint();
    await tester.pump(const Duration(milliseconds: 60));
    final after = await capture();

    expect(after, before);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
