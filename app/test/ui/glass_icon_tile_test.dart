import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/ui/theme/app_theme.dart';
import 'package:livenow/ui/widgets/glass_icon_tile.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('GlassIconTile renders, shows tooltip, taps ($brightness)', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(brightness),
          home: Scaffold(
            body: Center(
              child: GlassIconTile(
                icon: Icons.play_arrow_rounded,
                hue: GlassHue.blue,
                tooltip: 'Start',
                onTap: () => taps++,
                size: 24,
                iconSize: 18,
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(tester.getSize(find.byType(InkWell)), const Size(28, 28));

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: tester.getCenter(find.byType(InkWell)));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Start'), findsOneWidget);
      await gesture.removePointer();

      await tester.tap(find.byType(GlassIconTile));
      expect(taps, 1);
    });
  }
}
