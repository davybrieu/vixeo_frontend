import 'package:material_ui/material_ui.dart';

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

  /// Destructive actions: filled button (delete the account), red text (sign out).
  static const danger = Color(0xFFB42318);
  static const dangerText = Color(0xFFEF4444);

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

/// Duration of a page change (forward and back).
const vxPageFade = Duration(milliseconds: 300);

/// A page change, on every platform and for the tabs: a "fade through". The page that leaves
/// fades out first, then the new one fades in while growing slightly (96 % → 100 %): the two
/// pages are never seen on top of each other, and nothing slides. Back looks the same: the page
/// that closes fades out, then the one below comes back.
Widget vxPageTransition(Animation<double> animation, Animation<double> secondaryAnimation, Widget child) =>
    VxPageTransition(animation: animation, secondaryAnimation: secondaryAnimation, child: child);

/// See [vxPageTransition].
class VxPageTransition extends StatefulWidget {
  const VxPageTransition({
    super.key,
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  /// This page arriving (0 → 1), or closing (1 → 0).
  final Animation<double> animation;

  /// Another page arriving over this one (0 → 1), or closing and uncovering it (1 → 0).
  final Animation<double> secondaryAnimation;
  final Widget child;

  /// Size of a page when it starts to appear.
  static const startScale = 0.96;

  @override
  State<VxPageTransition> createState() => _VxPageTransitionState();
}

class _VxPageTransitionState extends State<VxPageTransition> {
  // In time, whatever the direction: the page that leaves fades out over the first 40 %, the page
  // that arrives fades in (and grows) from 30 % to the end. Going back, the animations run from 1
  // to 0: each one gets a reverse curve that gives the same timing (`FlippedCurve`, intervals
  // mirrored), otherwise the old page would linger and the new one would appear late.
  static const _arrive = Interval(0.3, 1, curve: Curves.easeOut);
  static const _grow = Interval(0.3, 1, curve: Curves.easeOutCubic);
  static const _leave = Interval(0, 0.4, curve: Curves.easeOut);

  /// This page's opacity: arrives (push) or leaves (back).
  late CurvedAnimation _shown;

  /// This page growing as it arrives (push); full size when it leaves.
  late CurvedAnimation _grown;

  /// Hidden by a page arriving over it (push), shown again when that page closes (back).
  late CurvedAnimation _covered;

  /// Shrunk as it comes back (back), so that it grows like an arriving page.
  late CurvedAnimation _shrunk;

  late Animation<double> _opacity;
  late Animation<double> _scale;
  late Animation<double> _comeBackScale;

  @override
  void initState() {
    super.initState();
    _create();
  }

  @override
  void didUpdateWidget(VxPageTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation || oldWidget.secondaryAnimation != widget.secondaryAnimation) {
      _dispose();
      _create();
    }
  }

  void _create() {
    _shown = CurvedAnimation(
      parent: widget.animation,
      curve: _arrive,
      reverseCurve: const Interval(0.6, 1, curve: FlippedCurve(Curves.easeOut)),
    );
    _grown = CurvedAnimation(parent: widget.animation, curve: _grow, reverseCurve: const Threshold(0));
    _covered = CurvedAnimation(
      parent: widget.secondaryAnimation,
      curve: _leave,
      reverseCurve: const Interval(0, 0.7, curve: FlippedCurve(Curves.easeOut)),
    );
    _shrunk = CurvedAnimation(
      parent: widget.secondaryAnimation,
      curve: const Threshold(1),
      reverseCurve: const Interval(0, 0.7, curve: FlippedCurve(Curves.easeOutCubic)),
    );
    _opacity = ReverseAnimation(_covered);
    _scale = _grown.drive(Tween(begin: VxPageTransition.startScale, end: 1.0));
    _comeBackScale = _shrunk.drive(Tween(begin: 1.0, end: VxPageTransition.startScale));
  }

  void _dispose() {
    _shown.dispose();
    _grown.dispose();
    _covered.dispose();
    _shrunk.dispose();
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _shown,
    child: FadeTransition(
      opacity: _opacity,
      child: ScaleTransition(
        scale: _scale,
        child: ScaleTransition(scale: _comeBackScale, child: widget.child),
      ),
    ),
  );
}

/// The page transition of the whole app, on every platform: [vxPageTransition].
class VxFadePageTransitionsBuilder extends PageTransitionsBuilder {
  const VxFadePageTransitionsBuilder();

  @override
  Duration get transitionDuration => vxPageFade;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => vxPageTransition(animation, secondaryAnimation, child);
}

ThemeData buildVixeoTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: VxColors.background,
    // Every pushed page (go_router `builder`, MaterialPageRoute): fade through, see vxPageTransition.
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {for (final platform in TargetPlatform.values) platform: const VxFadePageTransitionsBuilder()},
    ),
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
