import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/ui/theme/app_theme.dart';
import 'package:livenow/ui/theme/glass_theme.dart';
import 'package:livenow/ui/widgets/glass.dart';

double _contrast(Color a, Color b) {
  final l1 = a.computeLuminance(), l2 = b.computeLuminance();
  final hi = l1 > l2 ? l1 : l2, lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  for (final brightness in Brightness.values) {
    group('theme ${brightness.name}', () {
      test('builds and carries the glass tokens', () {
        final theme = buildAppTheme(brightness);
        expect(theme.brightness, brightness);
        final g = theme.extension<GlassTheme>();
        expect(g, isNotNull);
        expect(g!.dark, brightness == Brightness.dark);
        expect(theme.scaffoldBackgroundColor, Colors.transparent);
      });

      test('text stays readable on the glass over every background stop', () {
        final g = buildAppTheme(brightness).extension<GlassTheme>()!;
        for (final stop in g.background) {
          final glass = Color.alphaBlend(g.fill, stop);
          expect(
            _contrast(g.textPrimary, glass),
            greaterThanOrEqualTo(7),
            reason: 'primary on $stop',
          );
          expect(
            _contrast(g.textSecondary, glass),
            greaterThanOrEqualTo(4.5),
            reason: 'secondary on $stop',
          );
        }
      });
    });
  }

  testWidgets(
    'context.glass falls back to the brightness set for bare themes',
    (tester) async {
      late GlassTheme seen;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: Builder(
            builder: (context) {
              seen = context.glass;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(seen.dark, isTrue);
    },
  );

  testWidgets(
    'a GlassSurface outside a GlassBackground still draws its child',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: GlassSurface(
              child: SizedBox(width: 80, height: 40, child: Text('hi')),
            ),
          ),
        ),
      );
      expect(find.text('hi'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'GlassBackground renders a blurred snapshot the surfaces can use',
    (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      GlassScope? scope;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: GlassBackground(
            snapshot: true,
            child: Builder(
              builder: (context) {
                scope = GlassScope.maybeOf(context);
                return const Center(
                  child: GlassSurface(child: SizedBox(width: 200, height: 100)),
                );
              },
            ),
          ),
        ),
      );
      expect(scope!.blurred, isNull); // not ready on the first frame
      await tester.pump(
        const Duration(milliseconds: 10),
      ); // fires the render timer
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      await tester.pump();
      expect(scope!.blurred, isNotNull);
      expect(scope!.blurred!.width, 400); // half resolution of 800
      expect(scope!.blurred!.height, 300);
      expect(tester.takeException(), isNull);

      // Switching the theme re-renders it.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 200));
    },
  );
}
