import 'package:flutter/painting.dart';

/// Colour bands for an action's "Urgency to Keep in Balance" (the sum of its
/// growth directions' urgencies).
enum UrgencyBand { negative, low, medium, high, veryHigh, critical }

/// The single place the band boundaries live.
UrgencyBand urgencyBand(double u) {
  if (u < 0) return UrgencyBand.negative;
  if (u < 10) return UrgencyBand.low;
  if (u < 100) return UrgencyBand.medium;
  if (u < 300) return UrgencyBand.high;
  if (u < 500) return UrgencyBand.veryHigh;
  return UrgencyBand.critical;
}

/// Background colour of [band]: soft pastel glass tints on the light theme
/// (navy text), deeper saturated tints on the dark theme (white text).
Color urgencyBackground(UrgencyBand band, {required bool dark}) {
  final (light, deep) = switch (band) {
    UrgencyBand.negative => (0xFFCBD5E1, 0xFF475569), // grey
    UrgencyBand.low => (0xFF9ED8F5, 0xFF0E7490), // light blue
    UrgencyBand.medium => (0xFF9DE4B6, 0xFF15803D), // green
    UrgencyBand.high => (0xFFF8E08A, 0xFFA16207), // yellow
    UrgencyBand.veryHigh => (0xFFFBBD8C, 0xFFC2410C), // orange
    UrgencyBand.critical => (0xFFF5A3A3, 0xFFB91C1C), // red
  };
  return Color(dark ? deep : light);
}

/// Text colour with the better contrast against [background].
Color urgencyForeground(Color background) {
  const darkText = Color(0xFF1E293B); // navy, like the glass theme's text
  const lightText = Color(0xFFFFFFFF);
  final bgL = background.computeLuminance();
  final darkContrast = (bgL + 0.05) / (darkText.computeLuminance() + 0.05);
  final lightContrast = 1.05 / (bgL + 0.05);
  return darkContrast >= lightContrast ? darkText : lightText;
}

/// Background and text colours for urgency [u] in a light or [dark] theme.
({Color bg, Color fg}) urgencyColors(double u, {required bool dark}) =>
    urgencyColorsForBand(urgencyBand(u), dark: dark);

/// [urgencyColors] for an already-resolved [band] (lets callers watch only the
/// band, so a number that stays inside its band causes no rebuild).
({Color bg, Color fg}) urgencyColorsForBand(
  UrgencyBand band, {
  required bool dark,
}) {
  final bg = urgencyBackground(band, dark: dark);
  return (bg: bg, fg: urgencyForeground(bg));
}

/// Muted version of [urgencyColors] for DONE actions: the same band colour
/// blended ~40 % over [surface] (default: the theme's page surface, white on
/// light / near-black on dark), with whichever text colour reads best on the
/// blended result (contrast >= 4.5).
({Color bg, Color fg}) urgencyColorsMuted(
  double urgency, {
  required bool dark,
  Color? surface,
}) => urgencyColorsMutedForBand(
  urgencyBand(urgency),
  dark: dark,
  surface: surface,
);

/// [urgencyColorsMuted] for an already-resolved [band].
({Color bg, Color fg}) urgencyColorsMutedForBand(
  UrgencyBand band, {
  required bool dark,
  Color? surface,
}) {
  final base =
      surface ?? (dark ? const Color(0xFF0F172A) : const Color(0xFFFFFFFF));
  final bg = Color.alphaBlend(
    urgencyBackground(band, dark: dark).withValues(alpha: 0.4),
    base,
  );
  return (bg: bg, fg: urgencyForeground(bg));
}

/// The "fill me in" look: an action with no growth direction, or a direction
/// with no dated action in its period, is WHITE (a light grey on the dark
/// theme) so it stands out from the coloured, already-linked ones. [done]
/// mutes the text (the strikethrough on all-day items does the rest).
({Color bg, Color fg}) emptyColors({required bool dark, bool done = false}) => (
  bg: Color(dark ? 0xFFD5DAE3 : 0xFFFFFFFF),
  fg: Color(done ? 0xFF475569 : 0xFF1E293B),
);
