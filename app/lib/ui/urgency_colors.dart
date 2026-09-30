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

/// Background colour of [band]; deeper shades on dark themes.
Color urgencyBackground(UrgencyBand band, {required bool dark}) {
  final (light, deep) = switch (band) {
    UrgencyBand.negative => (0xFFBDBDBD, 0xFF616161), // grey
    UrgencyBand.low => (0xFF81D4FA, 0xFF0277BD), // light blue
    UrgencyBand.medium => (0xFF81C784, 0xFF2E7D32), // green
    UrgencyBand.high => (0xFFFFEB3B, 0xFFF9A825), // yellow
    UrgencyBand.veryHigh => (0xFFEF6C00, 0xFFE65100), // orange
    UrgencyBand.critical => (0xFFD32F2F, 0xFFC62828), // red
  };
  return Color(dark ? deep : light);
}

/// Text colour with the better contrast against [background].
Color urgencyForeground(Color background) {
  const darkText = Color(0xDE000000);
  const lightText = Color(0xFFFFFFFF);
  final bgL = background.computeLuminance();
  final darkContrast = (bgL + 0.05) / (darkText.computeLuminance() + 0.05);
  final lightContrast = 1.05 / (bgL + 0.05);
  return darkContrast >= lightContrast ? darkText : lightText;
}

/// Background and text colours for urgency [u] in a light or [dark] theme.
({Color bg, Color fg}) urgencyColors(double u, {required bool dark}) {
  final bg = urgencyBackground(urgencyBand(u), dark: dark);
  return (bg: bg, fg: urgencyForeground(bg));
}
