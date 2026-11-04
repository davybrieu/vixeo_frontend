import 'package:flutter/material.dart';

/// Colors of the Vixeo design system (see the "Charte graphique" artboard).
class VxColors {
  const VxColors._();

  static const background = Color(0xFF070A08);
  static const surface = Color(0xFF101512);
  static const field = Color(0xFF141A16);
  static const surfaceHigh = Color(0xFF1F2722);
  static const line = Color(0xFF2A332D);
  static const lineStrong = Color(0xFF3A453E);

  /// The only accent: main action, focus, progress, active tab.
  static const accent = Color(0xFF2EE58A);
  static const accentHover = Color(0xFF7CF0B4);
  static const onAccent = Color(0xFF03140A);

  static const text = Color(0xFFF1F5F2);
  static const textSecondary = Color(0xFFA9B3AC);
  static const textMuted = Color(0xFF808B84);
  static const textSoft = Color(0xFFC9D1CB);
  static const error = Color(0xFFFF7A7A);

  /// Placeholder tones for posters without an image (and decorative walls).
  static const posterTones = [
    Color(0xFF1B2A22),
    Color(0xFF22261F),
    Color(0xFF1A2230),
    Color(0xFF2A2026),
    Color(0xFF14221E),
    Color(0xFF2B2A1E),
    Color(0xFF1F1B2A),
    Color(0xFF18261F),
  ];

  static Color tone(int seed) => posterTones[seed.abs() % posterTones.length];
}

/// Fonts: Sora for titles, Inter for text. Bundled in the app (`assets/fonts`, OFL licence, declared
/// in `pubspec.yaml`): nothing is downloaded at launch, so no request reaches Google's servers.
class VxFonts {
  const VxFonts._();

  static const display = 'Sora';
  static const text = 'Inter';
}

/// Title style (Sora), e.g. `VxText.title(28)`.
class VxText {
  const VxText._();

  static TextStyle title(double size, {FontWeight weight = FontWeight.w700, Color color = VxColors.text}) =>
      TextStyle(fontFamily: VxFonts.display, fontSize: size, fontWeight: weight, color: color, height: 1.15);

  static TextStyle body(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color color = VxColors.text,
    double height = 1.45,
  }) => TextStyle(fontFamily: VxFonts.text, fontSize: size, fontWeight: weight, color: color, height: height);
}

ThemeData buildVixeoTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: VxColors.background,
    colorScheme: const ColorScheme.dark(
      primary: VxColors.accent,
      onPrimary: VxColors.onAccent,
      secondary: VxColors.accent,
      onSecondary: VxColors.onAccent,
      surface: VxColors.background,
      onSurface: VxColors.text,
      surfaceContainerHighest: VxColors.surfaceHigh,
      error: VxColors.error,
      outline: VxColors.line,
    ),
  );

  final textTheme = base.textTheme.apply(bodyColor: VxColors.text, displayColor: VxColors.text);

  return base.copyWith(
    textTheme: textTheme.apply(fontFamily: VxFonts.text),
    focusColor: VxColors.accent.withValues(alpha: 0.18),
    hoverColor: VxColors.text.withValues(alpha: 0.06),
    splashFactory: InkSparkle.splashFactory,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: VxColors.field,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      hintStyle: VxText.body(16, color: VxColors.textMuted),
      labelStyle: VxText.body(14, weight: FontWeight.w500, color: VxColors.textSecondary),
      errorStyle: VxText.body(13, color: VxColors.error),
      border: _border(VxColors.line),
      enabledBorder: _border(VxColors.line),
      focusedBorder: _border(VxColors.accent, width: 2),
      errorBorder: _border(VxColors.error),
      focusedErrorBorder: _border(VxColors.error, width: 2),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: VxColors.accent,
        foregroundColor: VxColors.onAccent,
        disabledBackgroundColor: VxColors.accent.withValues(alpha: 0.4),
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: VxText.body(16, weight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: VxColors.accent,
        minimumSize: const Size(44, 44),
        textStyle: VxText.body(14, weight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: VxColors.text,
        side: const BorderSide(color: VxColors.lineStrong),
        minimumSize: const Size(64, 48),
        shape: const StadiumBorder(),
        textStyle: VxText.body(15, weight: FontWeight.w500),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: VxColors.surfaceHigh,
      contentTextStyle: VxText.body(15),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: VxColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: VxText.title(22),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: VxColors.accent),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? VxColors.onAccent : VxColors.textSecondary,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? VxColors.accent : VxColors.surfaceHigh,
      ),
    ),
  );
}

OutlineInputBorder _border(Color color, {double width = 1}) => OutlineInputBorder(
  borderRadius: BorderRadius.circular(12),
  borderSide: BorderSide(color: color, width: width),
);
