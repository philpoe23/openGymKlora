import 'package:flutter/material.dart';

import 'tokens.dart';

ThemeData kloraLight() => _build(KSurfaces.light, Brightness.light);
ThemeData kloraDark() => _build(KSurfaces.dark, Brightness.dark);

/// The current surfaces, picked from the theme's brightness.
KSurfaces surfacesOf(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? KSurfaces.dark : KSurfaces.light;

ThemeData _build(KSurfaces s, Brightness b) {
  final scheme = ColorScheme(
    brightness: b,
    primary: s.accent,
    onPrimary: s.onAccent,
    secondary: K.rackLilac,
    onSecondary: K.rackLilacInk,
    error: const Color(0xFFC0392B),
    onError: Colors.white,
    surface: s.slab,
    onSurface: s.ink,
    surfaceContainerLowest: s.ground,
    surfaceContainerLow: s.raised,
    surfaceContainer: s.slab,
    surfaceContainerHigh: s.slab2,
    surfaceContainerHighest: s.slab3,
    outline: s.slab3,
  );
  // Rubik throughout; display sizes tight and heavy like the web (DESIGN.md typography).
  final base = Typography.material2021(platform: TargetPlatform.android).black.apply(
        fontFamily: K.font,
        bodyColor: s.ink,
        displayColor: s.ink,
      );
  final text = base.copyWith(
    displayLarge: base.displayLarge?.copyWith(fontSize: 48, fontWeight: FontWeight.w600, height: 0.98, letterSpacing: -1.6),
    headlineLarge: base.headlineLarge?.copyWith(fontSize: 34, fontWeight: FontWeight.w600, height: 1.06, letterSpacing: -0.75),
    titleLarge: base.titleLarge?.copyWith(fontSize: 22, fontWeight: FontWeight.w600, height: 1.1, letterSpacing: -0.4),
    titleMedium: base.titleMedium?.copyWith(fontSize: 17, fontWeight: FontWeight.w500, letterSpacing: -0.17),
    bodyLarge: base.bodyLarge?.copyWith(fontSize: 16, height: 1.4),
    bodyMedium: base.bodyMedium?.copyWith(fontSize: 15, height: 1.4),
    labelLarge: base.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
    labelSmall: base.labelSmall?.copyWith(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.6),
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(K.radiusPill));
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    fontFamily: K.font,
    textTheme: text,
    scaffoldBackgroundColor: s.ground,
    canvasColor: s.ground,
    appBarTheme: AppBarTheme(
      // Transparent: a screen's bar sits on its glass backdrop (lib/ui/widgets/glass.dart).
      backgroundColor: Colors.transparent,
      foregroundColor: s.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
    ),
    cardTheme: CardThemeData(
      color: s.slab,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(K.radius)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: s.accent,
        foregroundColor: s.onAccent,
        minimumSize: const Size(48, 52),
        shape: shape,
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: s.ink,
        side: BorderSide(color: s.slab3),
        minimumSize: const Size(48, 48),
        shape: shape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: s.accent)),
    inputDecorationTheme: InputDecorationTheme(
      // A field is a clear well in the glass: a translucent fill, a white hairline rim, and the
      // rim turning into a 2px hot-rose ring on focus (DESIGN.md Inputs).
      filled: true,
      fillColor: b == Brightness.dark ? s.slab2.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.55),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(K.radiusSm),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: b == Brightness.dark ? 0.12 : 0.8)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(K.radiusSm),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: b == Brightness.dark ? 0.12 : 0.8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(K.radiusSm),
        borderSide: BorderSide(color: s.accent, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    dividerTheme: DividerThemeData(color: s.slab3, thickness: 1, space: 1),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: s.ink,
      contentTextStyle: TextStyle(color: s.ground, fontFamily: K.font),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(K.radiusSm)),
    ),
  );
}
