import 'package:flutter/foundation.dart';

import '../catalog/models.dart';
import '../tv/models.dart';

/// "Type" filter of the search page.
enum SearchKind {
  all('Tout'),
  movie('Films'),
  tv('Séries'),

  /// Live channels from the TV API.
  channels('Chaînes TV'),

  /// People: the search results with a text, TMDb's popular people without one.
  person('Personnes'),

  /// Public Vixeo profiles.
  accounts('Comptes');

  const SearchKind(this.label);

  final String label;

  /// Movies or TV shows only (null for "Tout", channels and people).
  MediaType? get mediaType => switch (this) {
    SearchKind.movie => MediaType.movie,
    SearchKind.tv => MediaType.tv,
    _ => null,
  };

  bool get isChannels => this == SearchKind.channels;
}

/// Order of the results (API `sort`).
enum SearchSort {
  /// TMDb order for the typed text: only with a text.
  relevance('Pertinence'),
  popularity('Popularité'),

  /// Best rated first, on the rating each card shows (IMDb's, else TMDb's; developer's request,
  /// 21/11/2026): the search page asks the API (`sort=rating`), « À voir » sorts itself.
  rating('Mieux notés'),
  recent('Plus récents'),
  oldest('Plus anciens');

  const SearchSort(this.label);

  final String label;

  /// Orders offered with or without a text, [withRating] or not (« À voir »).
  static List<SearchSort> available({required bool withText, bool withRating = false}) => [
    for (final s in values)
      if ((withText || s != SearchSort.relevance) && (withRating || s != SearchSort.rating)) s,
  ];
}

/// Positions of a two-thumb slider (« Années », « Note », « Votants », developer's request,
/// 21/11/2026): the values offered, in order. The first position of the start thumb and the last
/// one of the end thumb mean "no limit" (null).
@immutable
class RangeStops<T extends num> {
  const RangeStops(this.values);

  /// 1900 to this year.
  static RangeStops<int> years() => RangeStops([for (var y = 1900; y <= DateTime.now().year; y++) y]);

  /// 0 to 10, by half points.
  static const ratings = RangeStops<double>([
    0, 0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5, 5.5, 6, 6.5, 7, 7.5, 8, 8.5, 9, 9.5, 10,
  ]);

  /// 0 to 1 000 000 and more.
  static const votes = RangeStops<int>([
    0, 100, 500, 1000, 2500, 5000, 10000, 25000, 50000, 100000, 250000, 500000, 1000000,
  ]);

  final List<T> values;

  int get count => values.length;

  /// The positions of a range (null ends: the ends of the track).
  (int, int) indexesOf(T? from, T? to) =>
      (from == null ? 0 : _nearest(from), to == null ? count - 1 : _nearest(to));

  /// The range of positions: null at the ends of the track.
  (T?, T?) valuesAt((int, int) indexes) => (
    indexes.$1 <= 0 ? null : values[indexes.$1],
    indexes.$2 >= count - 1 ? null : values[indexes.$2],
  );

  int _nearest(T value) {
    var best = 0;
    for (var i = 1; i < count; i++) {
      if ((values[i] - value).abs() < (values[best] - value).abs()) best = i;
    }
    return best;
  }
}

/// « 2010–2019 », « Depuis 2010 », « Jusqu’à 1979 », « 2015 »; null without limits.
String? yearRangeLabel(int? from, int? to) => switch ((from, to)) {
  (null, null) => null,
  (final f?, null) => 'Depuis $f',
  (null, final t?) => 'Jusqu’à $t',
  (final f?, final t?) => f == t ? '$f' : '$f–$t',
};

/// « 7 », « 7,5 »: a bound of the « Note » slider.
String formatRatingBound(double value) => value == value.roundToDouble() ? '${value.round()}' : formatRating(value);

/// « Note ≥ 7 », « Note ≤ 6 », « Note 6–8,5 »; null without limits.
String? ratingRangeLabel(double? min, double? max) => switch ((min, max)) {
  (null, null) => null,
  (final a?, null) => 'Note ≥ ${formatRatingBound(a)}',
  (null, final b?) => 'Note ≤ ${formatRatingBound(b)}',
  (final a?, final b?) =>
    a == b ? 'Note ${formatRatingBound(a)}' : 'Note ${formatRatingBound(a)}–${formatRatingBound(b)}',
};

/// « Votants ≥ 10 000 », « Votants ≤ 50 000 », « Votants 1 000–50 000 »; null without limits.
String? votesRangeLabel(int? min, int? max) => switch ((min, max)) {
  (null, null) => null,
  (final a?, null) => 'Votants ≥ ${formatCount(a)}',
  (null, final b?) => 'Votants ≤ ${formatCount(b)}',
  (final a?, final b?) => a == b ? 'Votants ${formatCount(a)}' : 'Votants ${formatCount(a)}–${formatCount(b)}',
};

/// Filters and order of the search page. Genre, years, rating and voters apply to movies and TV
/// shows only, [category] to live channels only; [sort] null = the default order (relevance with a
/// text, popularity without). Years, rating and voters are ranges chosen with two-thumb sliders
/// (each end optional). The rating ([minRating], [maxRating], [SearchSort.rating]) is the one each
/// card shows (IMDb's, else TMDb's), and [minVotes] / [maxVotes] count its voters: the search page
/// asks the API, « À voir » applies them itself ([yearWithin], [ratingWithin]).
@immutable
class SearchFilters {
  const SearchFilters({
    this.kind = SearchKind.all,
    this.genre,
    this.yearFrom,
    this.yearTo,
    this.minRating,
    this.maxRating,
    this.minVotes,
    this.maxVotes,
    this.sort,
    this.category,
  });

  final SearchKind kind;

  /// Category of the live channels (type « Chaînes TV »), null = all.
  final TvCategory? category;
  final Genre? genre;

  /// First and last years (null: no limit).
  final int? yearFrom;
  final int? yearTo;

  /// Rating out of 10, at least / at most (« Note 6–8 »).
  final double? minRating;
  final double? maxRating;

  /// Number of voters of the rating shown, at least / at most (developer's request, 21/11/2026):
  /// IMDb's when the title has an IMDb rating, else TMDb's.
  final int? minVotes;
  final int? maxVotes;
  final SearchSort? sort;

  bool get hasYears => yearFrom != null || yearTo != null;

  /// A bound of the rating or of its voters.
  bool get hasRatingBounds => minRating != null || maxRating != null || minVotes != null || maxVotes != null;

  bool get hasTitleFilters => genre != null || hasYears || hasRatingBounds;

  bool get isDefault => kind == SearchKind.all && !hasTitleFilters && sort == null && category == null;

  /// Without a text, movies and TV shows are browsed when a filter (genre, years, rating, voters) or an
  /// order is chosen (developer's request, 21/11/2026: « les films d'horreur depuis 2010 notés 8 et
  /// plus »); otherwise the empty field shows the recent searches.
  bool get canBrowse => (hasTitleFilters || sort != null) && (kind == SearchKind.all || kind.mediaType != null);

  /// Whether a year is within « Années » (a title without a year is kept).
  bool yearWithin(int? year) =>
      year == null || ((yearFrom == null || year >= yearFrom!) && (yearTo == null || year <= yearTo!));

  /// Whether a title's rating shown (IMDb's, else TMDb's) and its voters are within the bounds, as
  /// the API checks them: an unrated title is left out by any bound.
  bool ratingWithin(double? rating, int votes) {
    if (!hasRatingBounds) return true;
    if (rating == null) return false;
    return (minRating == null || rating >= minRating!) &&
        (maxRating == null || rating <= maxRating!) &&
        (minVotes == null || votes >= minVotes!) &&
        (maxVotes == null || votes <= maxVotes!);
  }

  /// The order really used: relevance needs a text.
  SearchSort sortFor({required bool withText}) {
    final value = sort ?? (withText ? SearchSort.relevance : SearchSort.popularity);
    return !withText && value == SearchSort.relevance ? SearchSort.popularity : value;
  }

  /// Query parameters of the API (search, or browsing without a text), the default ones left out.
  Map<String, Object?> query({required bool withText}) {
    final order = sortFor(withText: withText);
    final byDefault = order == (withText ? SearchSort.relevance : SearchSort.popularity);
    return {
      'genre': genre?.id,
      'year_from': yearFrom,
      'year_to': yearTo,
      'min_rating': minRating,
      'max_rating': maxRating,
      'min_votes': minVotes,
      'max_votes': maxVotes,
      'sort': byDefault ? null : order.name,
    };
  }

  SearchFilters copyWith({
    SearchKind? kind,
    Genre? Function()? genre,
    int? Function()? yearFrom,
    int? Function()? yearTo,
    double? Function()? minRating,
    double? Function()? maxRating,
    int? Function()? minVotes,
    int? Function()? maxVotes,
    SearchSort? Function()? sort,
    TvCategory? Function()? category,
  }) => SearchFilters(
    kind: kind ?? this.kind,
    genre: genre == null ? this.genre : genre(),
    yearFrom: yearFrom == null ? this.yearFrom : yearFrom(),
    yearTo: yearTo == null ? this.yearTo : yearTo(),
    minRating: minRating == null ? this.minRating : minRating(),
    maxRating: maxRating == null ? this.maxRating : maxRating(),
    minVotes: minVotes == null ? this.minVotes : minVotes(),
    maxVotes: maxVotes == null ? this.maxVotes : maxVotes(),
    sort: sort == null ? this.sort : sort(),
    category: category == null ? this.category : category(),
  );

  @override
  bool operator ==(Object other) =>
      other is SearchFilters &&
      other.kind == kind &&
      other.genre == genre &&
      other.yearFrom == yearFrom &&
      other.yearTo == yearTo &&
      other.minRating == minRating &&
      other.maxRating == maxRating &&
      other.minVotes == minVotes &&
      other.maxVotes == maxVotes &&
      other.sort == sort &&
      other.category == category;

  @override
  int get hashCode =>
      Object.hash(kind, genre, yearFrom, yearTo, minRating, maxRating, minVotes, maxVotes, sort, category);
}

/// One search of titles of one type (the search page shows nothing without a text).
@immutable
class TitleQuery {
  const TitleQuery(this.type, this.filters, {required this.query, this.page = 1});

  final MediaType type;
  final SearchFilters filters;
  final String query;
  final int page;

  TitleQuery atPage(int page) => TitleQuery(type, filters, query: query, page: page);

  @override
  bool operator ==(Object other) =>
      other is TitleQuery &&
      other.type == type &&
      other.filters == filters &&
      other.query == query &&
      other.page == page;

  @override
  int get hashCode => Object.hash(type, filters, query, page);
}
