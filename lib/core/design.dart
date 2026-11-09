import 'device/layout.dart';

// Spacing, radii and sizes of the design charter (docs/charte-graphique.md). A value is given
// for phones and tablets (logical px) and, when it differs, for large screens / TV in design px
// of the 1920×1080 screens (converted with Layout.tv). Pages use these instead of raw numbers,
// so the same element has the same size and spacing everywhere.

/// Spacing scale: 4 · 8 · 12 · 16 · 24 · 32 · 48 · 64.
abstract final class VxSpace {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const s = 12.0;
  static const m = 16.0;
  static const l = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
  static const xxxl = 64.0;

  /// On large screens a step is 1.5× (in 1920 design px): 16 → 24, 24 → 36.
  static const tvFactor = 1.5;
}

/// Corner radii (phone px; TV in brackets): posters 10, buttons and fields 12 (18), chips and
/// search field: fully rounded, cards and panels 20 (28), dialogs and sheets 28.
abstract final class VxRadius {
  static const poster = 10.0;
  static const button = 12.0;
  static const buttonTv = 18.0;
  static const card = 20.0;
  static const cardTv = 28.0;
  static const sheet = 28.0;
}

extension VxSizes on Layout {
  /// A size of the charter: [phone] on phones and tablets, [tv] (1920 design px) on large screens.
  double size(double phone, {required double tv}) => isLarge ? this.tv(tv) : phone;

  /// A step of the spacing scale ([VxSpace]), 1.5× on large screens.
  double space(double step) => isLarge ? tv(step * VxSpace.tvFactor) : step;

  /// Page title size: 28 on phones, 56 on TV.
  double get pageTitleSize => size(28, tv: 56);

  /// Row / section title size: 18 on phones, 30 on TV.
  double get sectionTitleSize => size(18, tv: 30);

  /// Body text: 15 on phones, 22 on TV.
  double get bodySize => size(15, tv: 22);

  /// Captions (dates, durations…): 13 on phones, 18 on TV (never smaller on TV).
  double get captionSize => size(13, tv: 18);

  // Gaps of a page (charte, § 5): the same everywhere.

  /// Between two sections or two rows of a page: 24 (TV 36).
  double get sectionGap => space(VxSpace.l);

  /// Under a row or section title, before what it names: 12 (TV 22).
  double get titleGap => size(12, tv: 22);

  /// Under a page's introduction text, before its content: 16 (TV 24).
  double get introGap => space(VxSpace.m);

  /// Between two lines of a list (reviews, devices, episodes, profiles): 12 (TV 18).
  double get listGap => space(VxSpace.s);

  /// Between two cards of a row or a grid (posters, people, avatars): 10 (TV 28).
  double get cardGap => size(10, tv: 28);
}
