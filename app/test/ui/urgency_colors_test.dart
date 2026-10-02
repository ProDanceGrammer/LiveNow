import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/ui/urgency_colors.dart';

void main() {
  test('band boundaries', () {
    final cases = <double, UrgencyBand>{
      -0.001: UrgencyBand.negative,
      0: UrgencyBand.low,
      9.99: UrgencyBand.low,
      10: UrgencyBand.medium,
      99.99: UrgencyBand.medium,
      100: UrgencyBand.high,
      299.99: UrgencyBand.high,
      300: UrgencyBand.veryHigh,
      499.99: UrgencyBand.veryHigh,
      500: UrgencyBand.critical,
      5000: UrgencyBand.critical,
    };
    cases.forEach((u, band) => expect(urgencyBand(u), band, reason: '$u'));
  });

  test('every band and theme has a readable text colour (contrast >= 4.5)', () {
    for (final band in UrgencyBand.values) {
      for (final dark in [false, true]) {
        final bg = urgencyBackground(band, dark: dark);
        final fg = urgencyForeground(bg);
        final l1 = bg.computeLuminance();
        final l2 = fg.computeLuminance();
        final hi = l1 > l2 ? l1 : l2;
        final lo = l1 > l2 ? l2 : l1;
        expect(
          (hi + 0.05) / (lo + 0.05),
          greaterThanOrEqualTo(4.5),
          reason: '$band dark=$dark',
        );
      }
    }
  });

  test('colours differ per band', () {
    for (final dark in [false, true]) {
      final all = {
        for (final b in UrgencyBand.values) urgencyBackground(b, dark: dark),
      };
      expect(all.length, UrgencyBand.values.length);
    }
    expect(
      urgencyColors(600, dark: false).bg,
      urgencyBackground(UrgencyBand.critical, dark: false),
    );
    expect(urgencyForeground(const Color(0xFFFFFFFF)), const Color(0xFF1E293B));
    expect(urgencyForeground(const Color(0xFF0E7490)), const Color(0xFFFFFFFF));
  });
}
