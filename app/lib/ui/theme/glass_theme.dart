import 'package:flutter/material.dart';

/// Design tokens of the light/dark "glass" look: every colour, radius and
/// strength used by glass surfaces lives here (and in `app_theme.dart`), so
/// screens never hard-code them. Available through `context.glass`.
@immutable
class GlassTheme extends ThemeExtension<GlassTheme> {
  const GlassTheme({
    required this.dark,
    required this.background,
    required this.clouds,
    required this.fill,
    required this.fillStrong,
    required this.fillDialog,
    required this.fillDialogTop,
    required this.border,
    required this.highlight,
    required this.shadow,
    required this.textPrimary,
    required this.textSecondary,
    required this.blue,
    required this.cyan,
    required this.lavender,
    required this.green,
    required this.pink,
    this.blurSigma = 18,
  });

  final bool dark;

  /// Three gradient stops, top-left to bottom-right.
  final List<Color> background;

  /// Soft painted cloud tints (top-right, bottom-right, bottom-left, top-left).
  final List<Color> clouds;

  /// Base fill of a glass surface (already translucent).
  final Color fill;

  /// Fill of surfaces that must stay readable over content (dialogs, menus).
  final Color fillStrong;

  /// Fully OPAQUE fill of dialogs and popup menus (a dialog stacked on another
  /// must never show the text below it).
  final Color fillDialog;

  /// Slightly lighter opaque tone of the dialog's header band (two-tone fill).
  final Color fillDialogTop;

  /// Thin bright edge of a glass surface.
  final Color border;

  /// Top-left sheen painted over the fill.
  final Color highlight;
  final Color shadow;
  final Color textPrimary;
  final Color textSecondary;

  /// Pastel accents.
  final Color blue;
  final Color cyan;
  final Color lavender;
  final Color green;
  final Color pink;

  /// Blur of the pre-rendered background that surfaces show through.
  final double blurSigma;

  static const radiusPanel = 24.0;
  static const radiusControl = 16.0;
  static const radiusChip = 12.0;

  static const light = GlassTheme(
    dark: false,
    background: [Color(0xFF9CC3FF), Color(0xFFBBA8FA), Color(0xFF8FD8F0)],
    clouds: [
      Color(0xFFA48CFF), // lavender, top-right
      Color(0xFF6FA5FF), // blue, bottom-right
      Color(0xFF6FD6F0), // cyan, bottom-left
      Color(0xFFB59CFF), // lavender, top-left
    ],
    fill: Color(0x73FFFFFF), // white @ 0.45
    fillStrong: Color(0xEBFFFFFF), // white @ 0.92
    fillDialog: Color(0xFFF1F5FF),
    fillDialogTop: Color(0xFFFFFFFF),
    border: Color(0xF2FFFFFF), // white @ 0.95
    highlight: Color(0x66FFFFFF),
    shadow: Color(0x2E2A2F9E), // indigo @ 0.18
    textPrimary: Color(0xFF14213D),
    textSecondary: Color(0xFF3A4A6B),
    blue: Color(0xFF4F8CF5),
    cyan: Color(0xFF2FB8D6),
    lavender: Color(0xFF8470F0),
    green: Color(0xFF3FC48F),
    pink: Color(0xFFF07BAA),
  );

  static const darkTheme = GlassTheme(
    dark: true,
    background: [Color(0xFF111A33), Color(0xFF1B1840), Color(0xFF0F2742)],
    clouds: [
      Color(0xFF4B3C94),
      Color(0xFF2B4F95),
      Color(0xFF1E6F86),
      Color(0xFF45367F),
    ],
    fill: Color(0x24B4C6FF), // periwinkle white @ 0.14
    fillStrong: Color(0xE61B2447), // navy @ 0.90
    fillDialog: Color(0xFF1B2447),
    fillDialogTop: Color(0xFF232E58),
    border: Color(0x40FFFFFF), // white @ 0.25
    highlight: Color(0x18FFFFFF),
    shadow: Color(0x59000000),
    textPrimary: Color(0xFFE2E8F0),
    textSecondary: Color(0xFFA9B6CB),
    blue: Color(0xFF7DAAF7),
    cyan: Color(0xFF63D0E4),
    lavender: Color(0xFFA99CF5),
    green: Color(0xFF74D9AB),
    pink: Color(0xFFF2A3C3),
  );

  @override
  GlassTheme copyWith({
    bool? dark,
    List<Color>? background,
    List<Color>? clouds,
    Color? fill,
    Color? fillStrong,
    Color? fillDialog,
    Color? fillDialogTop,
    Color? border,
    Color? highlight,
    Color? shadow,
    Color? textPrimary,
    Color? textSecondary,
    Color? blue,
    Color? cyan,
    Color? lavender,
    Color? green,
    Color? pink,
    double? blurSigma,
  }) => GlassTheme(
    dark: dark ?? this.dark,
    background: background ?? this.background,
    clouds: clouds ?? this.clouds,
    fill: fill ?? this.fill,
    fillStrong: fillStrong ?? this.fillStrong,
    fillDialog: fillDialog ?? this.fillDialog,
    fillDialogTop: fillDialogTop ?? this.fillDialogTop,
    border: border ?? this.border,
    highlight: highlight ?? this.highlight,
    shadow: shadow ?? this.shadow,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    blue: blue ?? this.blue,
    cyan: cyan ?? this.cyan,
    lavender: lavender ?? this.lavender,
    green: green ?? this.green,
    pink: pink ?? this.pink,
    blurSigma: blurSigma ?? this.blurSigma,
  );

  @override
  GlassTheme lerp(ThemeExtension<GlassTheme>? other, double t) {
    if (other is! GlassTheme) return this;
    return t < 0.5 ? this : other;
  }
}

extension GlassContext on BuildContext {
  /// The glass tokens of the current theme; falls back to the light/dark set
  /// by brightness so bare test themes work too.
  GlassTheme get glass {
    final theme = Theme.of(this);
    return theme.extension<GlassTheme>() ??
        (theme.brightness == Brightness.dark
            ? GlassTheme.darkTheme
            : GlassTheme.light);
  }
}
