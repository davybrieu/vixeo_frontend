import 'package:flutter/painting.dart';

import '../catalog/models.dart';

/// Site whose rating the titles show: a profile setting (« Paramètres » → « Source des notes »,
/// API `rating_source`, IMDb by default). Every site but TMDb comes from MDBList, through the API
/// (`GET /catalog/ratings`, vixeo_backend/docs/notes.md); TMDb's is the one given with each title.
enum RatingSource {
  imdb('IMDb', 'IMDb', 10, Color(0xFFF5C518), Color(0xFF000000)),
  tmdb('TMDb', 'TMDb', 10, Color(0xFF0D253F), Color(0xFFFFFFFF)),
  tomatoes('Rotten Tomatoes (critiques)', 'RT', 100, Color(0xFFFA320A), Color(0xFFFFFFFF)),
  audience('Rotten Tomatoes (public)', 'Popcorn', 100, Color(0xFFFA320A), Color(0xFFFFFFFF)),
  metacritic('Metacritic', 'MC', 100, Color(0xFF2B2B2B), Color(0xFFFFCC34)),
  letterboxd('Letterboxd', 'LB', 5, Color(0xFF202830), Color(0xFF00E054)),
  trakt('Trakt', 'Trakt', 100, Color(0xFFED1C24), Color(0xFFFFFFFF)),
  mal('MyAnimeList', 'MAL', 10, Color(0xFF2E51A2), Color(0xFFFFFFFF));

  const RatingSource(this.label, this.tag, this.scale, this.tagColor, this.tagTextColor);

  /// Name in the settings and for screen readers.
  final String label;

  /// Short name written next to the value (TMDb: its logo instead).
  final String tag;

  /// Best value: 10 (IMDb, TMDb, MyAnimeList), 5 (Letterboxd) or 100.
  final int scale;
  final Color tagColor;
  final Color tagTextColor;

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
