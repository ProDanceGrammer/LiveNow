import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import 'glass_theme.dart';

/// The app's light/dark glass `ThemeData`. Colours come from [GlassTheme];
/// component themes only restyle what already exists (no new widgets).
ThemeData buildAppTheme(Brightness brightness) {
  final g = brightness == Brightness.dark
      ? GlassTheme.darkTheme
      : GlassTheme.light;
  final dark = g.dark;

  final scheme = ColorScheme.fromSeed(seedColor: g.blue, brightness: brightness)
      .copyWith(
        primary: dark ? const Color(0xFF8DB4FA) : const Color(0xFF2F63DB),
        onPrimary: dark ? const Color(0xFF0B1630) : Colors.white,
        primaryContainer: dark
            ? const Color(0xFF2A4A8A)
            : const Color(0xFFBBD2FF),
        onPrimaryContainer: dark
            ? const Color(0xFFDCE8FF)
            : const Color(0xFF1E3A8A),
        secondary: dark ? const Color(0xFF63D0E4) : const Color(0xFF138FB0),
        secondaryContainer: dark
            ? const Color(0xFF1D5A6B)
            : const Color(0xFFB4E8F5),
        onSecondaryContainer: dark
            ? const Color(0xFFD5F3FA)
            : const Color(0xFF0E4A5A),
        tertiary: dark ? const Color(0xFFA99CF5) : const Color(0xFF6650E0),
        tertiaryContainer: dark
            ? const Color(0xFF3F3580)
            : const Color(0xFFD5CBFF),
        onTertiaryContainer: dark
            ? const Color(0xFFE6E0FF)
            : const Color(0xFF3B2F8F),
        surface: dark ? const Color(0xFF111A33) : const Color(0xFFD3E2FF),
        onSurface: g.textPrimary,
        onSurfaceVariant: g.textSecondary,
        surfaceContainerLowest: dark
            ? const Color(0xFF0E1630)
            : const Color(0xFFF2F6FF),
        surfaceContainerLow: dark
            ? const Color(0xFF151F3C)
            : const Color(0xFFE6EEFF),
        surfaceContainer: dark
            ? const Color(0xFF1A2444)
            : const Color(0xFFDCE7FF),
        surfaceContainerHigh: dark
            ? const Color(0xFF212C50)
            : const Color(0xFFD2DFFB),
        surfaceContainerHighest: dark
            ? const Color(0xFF2A3560)
            : const Color(0xFFC6D5F5),
        outline: dark ? const Color(0xFF52618A) : const Color(0xFF6E83B0),
        outlineVariant: dark
            ? const Color(0x33FFFFFF)
            : const Color(0xFFAFC2E8),
        error: dark ? const Color(0xFFF08A8A) : const Color(0xFFD9484F),
        errorContainer: dark
            ? const Color(0xFF5A2530)
            : const Color(0xFFFBDADD),
      );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    // Windows 11's variable UI font has in-between weights (w500); older
    // systems fall back to Segoe UI. Apple and Android phones keep their own
    // system font (these families do not exist there).
    fontFamily: _windowsFonts ? _kFontFamily : null,
    fontFamilyFallback: _windowsFonts ? _kFontFallback : null,
  );
  final text = _heavier(
    base.textTheme.apply(bodyColor: g.textPrimary, displayColor: g.textPrimary),
  );

  final controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(GlassTheme.radiusControl),
  );
  final glassShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(GlassTheme.radiusPanel),
    side: BorderSide(color: g.border, width: 1.2),
  );
  final hover = Colors.white.withValues(alpha: dark ? 0.08 : 0.55);

  return base.copyWith(
    extensions: [g],
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: Colors.transparent,
    textTheme: text,
    primaryTextTheme: text,
    hoverColor: hover,
    splashColor: scheme.primary.withValues(alpha: 0.10),
    highlightColor: scheme.primary.withValues(alpha: 0.06),
    dividerColor: g.border,
    dividerTheme: DividerThemeData(
      color: dark ? const Color(0x26FFFFFF) : const Color(0xCCFFFFFF),
      thickness: 1,
      space: 1,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: g.textPrimary,
      titleTextStyle: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: g.textPrimary,
        letterSpacing: -0.3,
      ),
    ),
    cardTheme: CardThemeData(
      color: g.fill,
      surfaceTintColor: Colors.transparent,
      shadowColor: g.shadow,
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: g.border, width: 1),
      ),
    ),
    dialogTheme: DialogThemeData(
      // The default 40 px side inset leaves a phone only ~295 px of dialog.
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: g.fillDialog,
      surfaceTintColor: Colors.transparent,
      shadowColor: g.shadow,
      elevation: 12,
      shape: GlassDialogBorder(g),
      titleTextStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: g.textPrimary,
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Colors.transparent,
      indicatorColor: scheme.primaryContainer.withValues(
        alpha: dark ? 0.85 : 1,
      ),
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      selectedIconTheme: IconThemeData(color: scheme.primary),
      unselectedIconTheme: IconThemeData(color: g.textSecondary),
      selectedLabelTextStyle: TextStyle(
        fontSize: 13,
        color: scheme.primary,
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelTextStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: g.textSecondary,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: dark ? 0.08 : 0.62),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: _inputBorder(g.border),
      enabledBorder: _inputBorder(g.border),
      focusedBorder: _inputBorder(scheme.primary, width: 1.8),
      errorBorder: _inputBorder(scheme.error),
      focusedErrorBorder: _inputBorder(scheme.error, width: 1.8),
      labelStyle: TextStyle(color: g.textSecondary),
      hintStyle: TextStyle(color: g.textSecondary.withValues(alpha: 0.8)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: controlShape,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: controlShape,
        backgroundColor: g.fill,
        foregroundColor: scheme.primary,
        surfaceTintColor: Colors.transparent,
        shadowColor: g.shadow,
        elevation: 2,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: controlShape,
        foregroundColor: scheme.primary,
        side: BorderSide(color: g.border, width: 1.2),
        backgroundColor: g.fill,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: controlShape,
        foregroundColor: scheme.primary,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: g.textSecondary,
        hoverColor: hover,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GlassTheme.radiusChip),
        ),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: dark ? scheme.primaryContainer : scheme.primary,
      foregroundColor: dark ? scheme.onPrimaryContainer : scheme.onPrimary,
      elevation: 6,
      hoverElevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    tabBarTheme: TabBarThemeData(
      dividerColor: Colors.transparent,
      labelColor: scheme.primary,
      unselectedLabelColor: g.textSecondary,
      labelStyle: const TextStyle(fontWeight: FontWeight.w700),
      indicatorSize: TabBarIndicatorSize.label,
      // Rounded, soft hover instead of the default gray rectangle.
      splashBorderRadius: BorderRadius.circular(16),
      overlayColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.hovered)
            ? scheme.primary.withValues(alpha: 0.08)
            : Colors.transparent,
      ),
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(color: scheme.primary, width: 3),
        borderRadius: BorderRadius.circular(3),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xF22A3560) : const Color(0xF21E293B),
      contentTextStyle: const TextStyle(color: Colors.white),
      actionTextColor: const Color(0xFF9CC4FF),
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white.withValues(alpha: dark ? 0.10 : 0.62),
      selectedColor: scheme.primaryContainer,
      side: BorderSide(color: g.border),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GlassTheme.radiusChip),
      ),
      labelStyle: TextStyle(color: g.textPrimary),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: dark ? const Color(0xF22A3560) : const Color(0xF21E293B),
        borderRadius: BorderRadius.circular(10),
      ),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      waitDuration: const Duration(milliseconds: 400),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: g.fillDialog,
      surfaceTintColor: Colors.transparent,
      shadowColor: g.shadow,
      elevation: 8,
      shape: glassShape,
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(g.fillDialog),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shadowColor: WidgetStatePropertyAll(g.shadow),
        elevation: const WidgetStatePropertyAll(8),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: g.border),
          ),
        ),
      ),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        overlayColor: WidgetStatePropertyAll(
          scheme.primary.withValues(alpha: 0.10),
        ),
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(
        scheme.primary.withValues(alpha: dark ? 0.45 : 0.40),
      ),
      radius: const Radius.circular(8),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: g.textSecondary,
      textColor: g.textPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    expansionTileTheme: ExpansionTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    ),
  );
}

/// Dialog outline with a little "volume", all from cheap solid draws (no
/// blur, gradient or clip): two extra fading shadow rings around the edge and
/// a 1 px highlight line along the top. Nothing is painted over the content
/// (a header band here once washed the title out). Only 1-3 dialogs are ever
/// on screen.
class GlassDialogBorder extends RoundedRectangleBorder {
  GlassDialogBorder(this.g)
    : super(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: g.border, width: 1.2),
      );

  final GlassTheme g;

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final rrect = borderRadius.resolve(textDirection).toRRect(rect);
    // Contact rings just outside the edge (under the Material's own shadow).
    // Not on iOS/Android: next to the screen edge they read as extra stacked
    // shadow layers.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;
    for (var i = 0; i < (_windowsFonts ? 2 : 0); i++) {
      ring.color = g.shadow.withValues(alpha: g.shadow.a * (0.9 - i * 0.4));
      canvas.drawRRect(
        rrect.inflate(2.5 + i * 5).shift(const Offset(0, 3)),
        ring,
      );
    }
    // 1 px highlight along the top edge, inside the border.
    canvas.drawLine(
      Offset(rect.left + 26, rect.top + 1.8),
      Offset(rect.right - 26, rect.top + 1.8),
      Paint()
        ..color = g.highlight.withValues(alpha: g.dark ? 0.35 : 1)
        ..strokeWidth = 1,
    );
    super.paint(canvas, rect, textDirection: textDirection);
  }

  @override
  ShapeBorder scale(double t) => GlassDialogBorder(g);

  @override
  RoundedRectangleBorder copyWith({
    BorderSide? side,
    BorderRadiusGeometry? borderRadius,
  }) => GlassDialogBorder(g);
}

/// Windows (and the other desktops, where the fallbacks still apply) use the
/// Segoe family; iOS and Android use the platform font.
final _windowsFonts =
    defaultTargetPlatform != TargetPlatform.iOS &&
    defaultTargetPlatform != TargetPlatform.android;

const _kFontFamily = 'Segoe UI Variable Text';
const _kFontFallback = ['Segoe UI', 'Roboto', 'Arial'];

/// The stock Material weights (w400 body text) look thin on translucent
/// glass, so lift every style one step; styles that set a weight explicitly
/// (bold names, titles in the screens) are unaffected.
TextTheme _heavier(TextTheme t) {
  TextStyle? w(TextStyle? s, FontWeight weight) =>
      s?.copyWith(fontWeight: weight);
  return t.copyWith(
    displayLarge: w(t.displayLarge, FontWeight.w600),
    displayMedium: w(t.displayMedium, FontWeight.w600),
    displaySmall: w(t.displaySmall, FontWeight.w600),
    headlineLarge: w(t.headlineLarge, FontWeight.w600),
    headlineMedium: w(t.headlineMedium, FontWeight.w600),
    headlineSmall: w(t.headlineSmall, FontWeight.w600),
    titleLarge: w(t.titleLarge, FontWeight.w600),
    titleMedium: w(t.titleMedium, FontWeight.w600),
    titleSmall: w(t.titleSmall, FontWeight.w600),
    labelLarge: w(t.labelLarge, FontWeight.w600),
    labelMedium: w(t.labelMedium, FontWeight.w500),
    labelSmall: w(t.labelSmall, FontWeight.w500),
    bodyLarge: w(t.bodyLarge, FontWeight.w500),
    bodyMedium: w(t.bodyMedium, FontWeight.w500),
    bodySmall: w(t.bodySmall, FontWeight.w500),
  );
}

OutlineInputBorder _inputBorder(Color color, {double width = 1}) =>
    OutlineInputBorder(
      borderRadius: BorderRadius.circular(GlassTheme.radiusControl),
      borderSide: BorderSide(color: color, width: width),
    );
