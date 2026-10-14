import 'dart:math' as math;

import 'package:flutter/painting.dart';

// The colour scale of "Urgency to Keep in Balance" (chosen by the user): red
// (> 500), orange (200..500), light yellow (50..200), lime (0..50), green
// (0..-200) and cyan below -200. The colour is interpolated smoothly between
// the band centres below.

/// Urgency values outside this range get the end colours.
const double kUrgencyMin = -300;
const double kUrgencyMax = 600;

/// One colour step is this many urgency points: widgets `select` the quantised
/// [urgencyKey], so a block repaints only when its colour visibly changes.
const double kUrgencyStep = 5;

/// (urgency, light-theme colour): the band centres.
const List<(double, int)> _anchors = [
  (-300, 0xFF14C5EB), // cyan, "< -200"
  (-100, 0xFF1FE045), // green, "0 .. -200"
  (25, 0xFFBDE21D), // lime, "0 .. 50"
  (125, 0xFFF8D407), // light yellow, "50 .. 200"
  (350, 0xFFDE7E21), // orange, "200 .. 500"
  (600, 0xFFD9263C), // red, "> 500"
];

/// The light theme's scale is the saturated anchors blended this far toward
/// white ("Frosted", chosen by the user): pastel cards that sit on the glass page
/// like the dark theme's deep ones do.
const double _lightFrost = 0.58;

/// PREVIEW (round 19): how the DARK theme's scale is drawn; Settings switches it
/// so the variants can be compared on real screens, the chosen one becomes the
/// only one afterwards. `current` = the anchors pushed 45 % toward the page;
/// `vivid` = pushed less (brighter); `deep` = pushed more; `slate` = pushed
/// toward a blue slate (cooler, less brown on the yellows and oranges).
enum UrgencyDarkStyle {
  current('Current'),
  vivid('Vivid'),
  deep('Deep'),
  slate('Slate');

  final String label;
  const UrgencyDarkStyle(this.label);
}

UrgencyDarkStyle urgencyDarkStyle = UrgencyDarkStyle.current;

int _ck(int key, bool dark) =>
    ((urgencyDarkStyle.index * 4096) + key + 2048) * 2 + (dark ? 1 : 0);

const Color _navy = Color(0xFF1E293B);
const Color _white = Color(0xFFFFFFFF);
const Color _darkPage = Color(0xFF0F172A);

/// The quantised position of [u] on the scale (an int in
/// `urgencyKey(kUrgencyMin) .. urgencyKey(kUrgencyMax)`).
int urgencyKey(double u) =>
    (u.clamp(kUrgencyMin, kUrgencyMax) / kUrgencyStep).round();

Color _lightColorAt(double u) {
  final x = u.clamp(kUrgencyMin, kUrgencyMax);
  for (var i = 1; i < _anchors.length; i++) {
    final (hiU, hiC) = _anchors[i];
    if (x <= hiU) {
      final (loU, loC) = _anchors[i - 1];
      return Color.lerp(Color(loC), Color(hiC), (x - loU) / (hiU - loU))!;
    }
  }
  return Color(_anchors.last.$2);
}

/// The scale's background at [u] (before the legibility nudge).
Color urgencyBackgroundAt(double u, {required bool dark}) {
  final light = _lightColorAt(u);
  if (!dark) return Color.lerp(light, _white, _lightFrost)!;
  // Dark theme: the same hue, pushed deep.
  return switch (urgencyDarkStyle) {
    UrgencyDarkStyle.current => Color.lerp(light, _darkPage, 0.45)!,
    UrgencyDarkStyle.vivid => Color.lerp(light, _darkPage, 0.28)!,
    UrgencyDarkStyle.deep => Color.lerp(light, _darkPage, 0.62)!,
    UrgencyDarkStyle.slate => Color.lerp(light, const Color(0xFF26325A), 0.55)!,
  };
}

double _contrast(Color a, Color b) {
  final l1 = a.computeLuminance(), l2 = b.computeLuminance();
  final hi = math.max(l1, l2), lo = math.min(l1, l2);
  return (hi + 0.05) / (lo + 0.05);
}

/// Text colour with the better contrast against [background].
Color urgencyForeground(Color background) {
  final darkContrast = _contrast(background, _navy);
  final lightContrast = _contrast(background, _white);
  return darkContrast >= lightContrast ? _navy : _white;
}

/// [bg] with the text colour that reads best on it; when even the best text
/// colour is below 4.5:1 the background is moved just far enough away from the
/// text colour (lighter under navy text, darker under white text).
({Color bg, Color fg}) _readable(Color bg) {
  var c = bg;
  for (var i = 0; i < 20; i++) {
    final fg = urgencyForeground(c);
    if (_contrast(c, fg) >= 4.5) return (bg: c, fg: fg);
    c = Color.lerp(c, fg == _navy ? _white : _darkPage, 0.06)!;
  }
  return (bg: c, fg: urgencyForeground(c));
}

final _cache = <int, ({Color bg, Color fg})>{};
final _cacheMuted = <int, ({Color bg, Color fg})>{};

/// Background and text colours for the quantised position [key] on the scale.
({Color bg, Color fg}) urgencyColorsForKey(int key, {required bool dark}) =>
    _cache[_ck(key, dark)] ??= _readable(
      urgencyBackgroundAt(key * kUrgencyStep, dark: dark),
    );

/// Background and text colours for urgency [u] in a light or [dark] theme.
({Color bg, Color fg}) urgencyColors(double u, {required bool dark}) =>
    urgencyColorsForKey(urgencyKey(u), dark: dark);

/// Muted version for DONE actions: the same colour blended ~40 % (light) /
/// ~78 % (dark) over the
/// page [surface] (default: white on light / near-black on dark), with the best
/// text colour (contrast >= 4.5).
({Color bg, Color fg}) urgencyColorsMutedForKey(
  int key, {
  required bool dark,
  Color? surface,
}) {
  Color blended() {
    final base = surface ?? (dark ? _darkPage : _white);
    return Color.alphaBlend(
      urgencyBackgroundAt(key * kUrgencyStep, dark: dark).withValues(
        // On the dark theme the page is almost black, so 40 % made done
        // actions far darker than the others: keep them a little darker only.
        alpha: dark ? 0.78 : 0.4,
      ),
      base,
    );
  }

  if (surface != null) return _readable(blended());
  return _cacheMuted[_ck(key, dark)] ??= _readable(blended());
}

({Color bg, Color fg}) urgencyColorsMuted(
  double urgency, {
  required bool dark,
  Color? surface,
}) => urgencyColorsMutedForKey(
  urgencyKey(urgency),
  dark: dark,
  surface: surface,
);

/// A RUNNING action: indigo, the one hue the scale does not use, drawn like the
/// scale itself (frosted on the light theme, pushed toward the page on the dark
/// one) so it belongs to the palette but is never mistaken for an urgency.
({Color bg, Color fg}) runningColors({required bool dark}) => dark
    ? _readable(Color.lerp(const Color(0xFF6A63FF), _darkPage, 0.30)!)
    : _readable(Color.lerp(const Color(0xFF4B44F0), _white, 0.50)!);

/// A 1 px outline for a block filled with [bg]: its own colour, darker on the
/// light theme and lighter on the dark one, so it separates the block from the
/// page behind it without a neutral line that could be read as data.
Color urgencyOutline(Color bg, {required bool dark}) =>
    Color.lerp(bg, dark ? _white : _darkPage, dark ? 0.28 : 0.30)!;

/// The "fill me in" look: an action with no growth direction, or a direction
/// with no dated action in its period, is WHITE (a light grey on the dark
/// theme) so it stands out from the coloured, already-linked ones. [done]
/// mutes the text (the strikethrough on all-day items does the rest).
({Color bg, Color fg}) emptyColors({required bool dark, bool done = false}) => (
  bg: Color(dark ? 0xFFD5DAE3 : 0xFFFFFFFF),
  fg: Color(done ? 0xFF475569 : 0xFF1E293B),
);
