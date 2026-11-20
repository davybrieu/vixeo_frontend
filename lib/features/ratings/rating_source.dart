import '../catalog/models.dart';

/// Site whose rating the titles show: a profile setting (« Paramètres » → « Source des notes »,
/// API `rating_source`, IMDb by default). Every site but TMDb comes from MDBList, through the API
/// (`GET /catalog/ratings`, vixeo_backend/docs/notes.md); TMDb's is the one given with each title.
///
/// Each site is shown with its logo (`assets/images/ratings/<name>.png`, rendered from
/// `brand/ratings/*.svg` by `brand/tools/rating_logos.py`; TMDb: its official logo, `TmdbLogo`).
enum RatingSource {
  imdb('IMDb', 10, 1.981, 0.95),
  tmdb('TMDb', 10, 820 / 106, 0.7),
  tomatoes('Rotten Tomatoes (critiques)', 100, 1, 1.15),
  audience('Rotten Tomatoes (public)', 100, 1, 1.15),
  metacritic('Metacritic', 100, 1, 1.1),
  letterboxd('Letterboxd', 5, 2.703, 0.75),
  trakt('Trakt', 100, 1, 1.1),
  mal('MyAnimeList', 10, 1.789, 0.95);

  const RatingSource(this.label, this.scale, this.logoAspect, this.logoHeight);

  /// Name in the settings and for screen readers.
  final String label;

  /// Best value: 10 (IMDb, TMDb, MyAnimeList), 5 (Letterboxd) or 100.
  final int scale;

  /// Width / height of the logo.
  final double logoAspect;

  /// Height of the logo next to a text of size 1: wide logos lower, square ones higher, so that
  /// they all look the same size.
  final double logoHeight;

  /// The logo's file (TMDb: `assets/images/tmdb_short.png`, drawn by `TmdbLogo`).
  String get logoAsset => 'assets/images/ratings/$name.png';

  /// The API value (`rating_source`), IMDb when missing or unknown.
  static RatingSource parse(Object? value) =>
      RatingSource.values.firstWhere((s) => s.name == value, orElse: () => RatingSource.imdb);

  /// Percentages: Rotten Tomatoes and Trakt.
  bool get isPercent => this == RatingSource.tomatoes || this == RatingSource.audience || this == RatingSource.trakt;

  /// What the settings say about the site.
  String get detail => switch (this) {
    RatingSource.imdb || RatingSource.tmdb => 'Note sur 10',
    RatingSource.tomatoes => 'Avis des critiques, en %',
    RatingSource.audience => 'Avis du public, en %',
    RatingSource.metacritic => 'Note sur 100',
    RatingSource.letterboxd => 'Note sur 5, films seulement',
    RatingSource.trakt => 'Note en %',
    RatingSource.mal => 'Note sur 10, animés seulement',
  };

  /// "8,8", "79 %", "4,3", "67".
  String format(double value) => scale == 100
      ? (isPercent ? '${value.round()} %' : '${value.round()}')
      : formatRating(value);

  /// For screen readers: "8,8 sur 10", "79 %".
  String spoken(double value) => isPercent ? format(value) : '${format(value)} sur $scale';

  /// A threshold given in tenths of the scale (6 = 60 %), written on this site's scale: "6", "60 %",
  /// "3", "60" (filter « Note » of « Ma liste »).
  String threshold(int tenths) {
    final value = tenths * scale / 10;
    if (scale == 100) return format(value);
    return value == value.roundToDouble() ? '${value.round()}' : formatRating(value);
  }
}
