import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livenow/ui/urgency_colors.dart';

double _contrast(Color a, Color b) {
  final l1 = a.computeLuminance(), l2 = b.computeLuminance();
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

/// Euclidean distance of two colours in 0..255 RGB.
double _distance(Color a, Color b) {
  double d(double x, double y) => (x - y) * 255;
  return (d(a.r, b.r) * d(a.r, b.r) +
          d(a.g, b.g) * d(a.g, b.g) +
          d(a.b, b.b) * d(a.b, b.b))
      .abs();
}

void main() {
  test('the scale is quantised and clamped', () {
    expect(urgencyKey(0), 0);
    expect(urgencyKey(2.4), 0);
    expect(urgencyKey(2.6), 1);
    expect(urgencyKey(-100000), urgencyKey(kUrgencyMin));
    expect(urgencyKey(100000), urgencyKey(kUrgencyMax));
    // Same key = same colour, whatever the exact number.
    expect(urgencyColors(61, dark: false), urgencyColors(62, dark: false));
  });

  test('the light scale is the chosen anchors, frosted 58 % toward white', () {
    Color frost(int anchor) =>
        Color.lerp(Color(anchor), const Color(0xFFFFFFFF), 0.58)!;
    expect(urgencyBackgroundAt(-300, dark: false), frost(0xFF14C5EB));
    expect(urgencyBackgroundAt(-100, dark: false), frost(0xFF1FE045));
    expect(urgencyBackgroundAt(25, dark: false), frost(0xFFBDE21D));
    expect(urgencyBackgroundAt(125, dark: false), frost(0xFFF8D407));
    expect(urgencyBackgroundAt(350, dark: false), frost(0xFFDE7E21));
    expect(urgencyBackgroundAt(600, dark: false), frost(0xFFD9263C));
    // Beyond the ends: the end colours.
    expect(urgencyBackgroundAt(5000, dark: false), frost(0xFFD9263C));
    expect(urgencyBackgroundAt(-5000, dark: false), frost(0xFF14C5EB));
  });

  test('every dark style keeps text readable and the scale smooth', () {
    for (final style in UrgencyDarkStyle.values) {
      urgencyDarkStyle = style;
      var prev = urgencyBackgroundAt(kUrgencyMin, dark: true);
      for (var u = kUrgencyMin; u <= kUrgencyMax; u += 5) {
        final c = urgencyColors(u, dark: true);
        expect(_contrast(c.fg, c.bg), greaterThanOrEqualTo(4.5),
            reason: '$style u=$u');
        final bg = urgencyBackgroundAt(u, dark: true);
        expect(_distance(prev, bg), lessThan(35 * 35 * 1.0),
            reason: '$style u=$u');
        prev = bg;
      }
      final run = runningColors(dark: true);
      expect(_contrast(run.fg, run.bg), greaterThanOrEqualTo(4.5));
    }
    urgencyDarkStyle = UrgencyDarkStyle.current;
  });

  test('it is a smooth gradient: neighbouring steps differ only a little', () {
    for (final dark in [false, true]) {
      var prev = urgencyBackgroundAt(kUrgencyMin, dark: dark);
      for (var u = kUrgencyMin + kUrgencyStep; u <= kUrgencyMax; u += 5) {
        final c = urgencyBackgroundAt(u, dark: dark);
        // distance is squared (0..195075): a step may change a colour by at
        // most ~35 of 255 in RGB.
        expect(_distance(prev, c), lessThan(35 * 35 * 1.0), reason: 'u=$u');
        prev = c;
      }
    }
  });

  test('text is readable (>= 4.5:1) on every colour, full and muted', () {
    for (final dark in [false, true]) {
      for (var u = -400.0; u <= 700; u += 5) {
        for (final c in [
          urgencyColors(u, dark: dark),
          urgencyColorsMuted(u, dark: dark),
        ]) {
          expect(_contrast(c.fg, c.bg), greaterThanOrEqualTo(4.5),
              reason: 'u=$u dark=$dark');
        }
      }
    }
  });

  test('muted differs from full, the outline differs from the fill', () {
    for (final dark in [false, true]) {
      for (final u in [-200.0, -20.0, 30.0, 150.0, 400.0, 900.0]) {
        expect(urgencyColorsMuted(u, dark: dark).bg,
            isNot(urgencyColors(u, dark: dark).bg));
        final bg = urgencyColors(u, dark: dark).bg;
        expect(urgencyOutline(bg, dark: dark), isNot(bg));
      }
    }
  });

  test('running indigo is clearly different from every urgency colour', () {
    for (final dark in [false, true]) {
      final run = runningColors(dark: dark);
      expect(_contrast(run.fg, run.bg), greaterThanOrEqualTo(4.5));
      for (var u = kUrgencyMin; u <= kUrgencyMax; u += 5) {
        expect(
          _distance(run.bg, urgencyColors(u, dark: dark).bg),
          greaterThan(40 * 40.0),
          reason: 'u=$u dark=$dark',
        );
      }
    }
  });

  test('the white "fill me in" look is not on the scale', () {
    expect(emptyColors(dark: false).bg, const Color(0xFFFFFFFF));
    expect(emptyColors(dark: true).bg, isNot(const Color(0xFFFFFFFF)));
    expect(emptyColors(dark: true).bg.computeLuminance(), greaterThan(0.6));
    for (final dark in [false, true]) {
      final e = emptyColors(dark: dark).bg;
      for (var u = kUrgencyMin; u <= kUrgencyMax; u += 5) {
        expect(
          _distance(e, urgencyColors(u, dark: dark).bg),
          greaterThan(25 * 25.0),
          reason: 'u=$u dark=$dark',
        );
      }
      for (final done in [false, true]) {
        final c = emptyColors(dark: dark, done: done);
        expect(_contrast(c.fg, c.bg), greaterThanOrEqualTo(4.5));
      }
    }
  });
}
