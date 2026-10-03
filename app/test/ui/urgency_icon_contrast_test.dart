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

    test('urgency icon violet has >= 3:1 on every band ($name)', () {
      for (final band in UrgencyBand.values) {
        final bg = urgencyBackground(band, dark: dark);
        expect(_contrast(g.urgencyIcon, bg), greaterThanOrEqualTo(3.0),
            reason: '${band.name} full');
        final muted = urgencyColorsMuted(
          {
            UrgencyBand.negative: -1.0,
            UrgencyBand.low: 5.0,
            UrgencyBand.medium: 50.0,
            UrgencyBand.high: 200.0,
            UrgencyBand.veryHigh: 400.0,
            UrgencyBand.critical: 900.0,
          }[band]!,
          dark: dark,
        ).bg;
        expect(_contrast(g.urgencyIcon, muted), greaterThanOrEqualTo(3.0),
            reason: '${band.name} muted');
      }
    });

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
  }
}
