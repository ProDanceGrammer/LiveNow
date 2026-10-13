import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/ui/theme/glass_theme.dart';
import 'package:livenow/ui/urgency_colors.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  for (final dark in [false, true]) {
    final g = dark ? GlassTheme.darkTheme : GlassTheme.light;
    final name = dark ? 'dark' : 'light';
    final page = dark ? const Color(0xFF0F172A) : const Color(0xFFFFFFFF);

    test('urgency icon violet has >= 3:1 on neutral surfaces ($name)', () {
      // Glass fill over the page background, the opaque dialog tones, the page.
      final surfaces = [
        page,
        Color.alphaBlend(g.fill, g.background[1]),
        Color.alphaBlend(g.fillStrong, g.background[1]),
        g.fillDialog,
        g.fillDialogTop,
      ];
      for (final s in surfaces) {
        expect(_contrast(g.urgencyIcon, s), greaterThanOrEqualTo(3.0),
            reason: '$s');
      }
    });

    test('on a tinted block the icon takes the block text colour ($name)', () {
      // The violet token is for neutral surfaces only: every tinted surface
      // (full, muted, white) passes its own foreground, which must read >= 4.5.
      for (var u = -400.0; u <= 700; u += 5) {
        for (final c in [
          urgencyColors(u, dark: dark),
          urgencyColorsMuted(u, dark: dark),
        ]) {
          expect(_contrast(c.fg, c.bg), greaterThanOrEqualTo(4.5),
              reason: 'u=$u');
        }
      }
      for (final done in [false, true]) {
        final e = emptyColors(dark: dark, done: done);
        expect(_contrast(e.fg, e.bg), greaterThanOrEqualTo(4.5));
      }
    });
  }
}
