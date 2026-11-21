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
  /// 21/11/2026): the search page asks the API (`sort=rating`), « Ma liste » sorts itself.
  rating('Mieux notés'),
  recent('Plus récents'),
  oldest('Plus anciens');

  const SearchSort(this.label);

  final String label;

  /// Orders offered with or without a text, [withRating] or not (« Ma liste »).
  static List<SearchSort> available({required bool withText, bool withRating = false}) => [
    for (final s in values)
      if ((withText || s != SearchSort.relevance) && (withRating || s != SearchSort.rating)) s,
  ];
}

/// "Années" filter.
enum Decade {
  // From a year on (« les films depuis 2010 », developer's request, 21/11/2026).
  since2010(2010, null, 'Depuis 2010'),
  since2000(2000, null, 'Depuis 2000'),
  y2020s(2020, 2029, 'Années 2020'),
  y2010s(2010, 2019, 'Années 2010'),
  y2000s(2000, 2009, 'Années 2000'),
  y1990s(1990, 1999, 'Années 1990'),
  y1980s(1980, 1989, 'Années 1980'),
  before1980(null, 1979, 'Avant 1980');

  const Decade(this.from, this.to, this.label);

  /// First and last years (null: no limit).
  final int? from;
  final int? to;
  final String label;

  bool contains(int year) => year >= (from ?? 0) && year <= (to ?? 9999);
}

/// Filters and order of the search page. Genre, years and rating apply to movies and TV shows
/// only, [category] to live channels only; [sort] null = the default order (relevance with a
/// text, popularity without). The rating ([minRating], [SearchSort.rating]) is the one each card
/// shows (IMDb's, else TMDb's): the search page asks the API, « Ma liste » applies it itself.
@immutable
class SearchFilters {
  const SearchFilters({this.kind = SearchKind.all, this.genre, this.decade, this.minRating, this.sort, this.category});

  final SearchKind kind;

  /// Category of the live channels (type « Chaînes TV »), null = all.
  final TvCategory? category;
  final Genre? genre;
  final Decade? decade;

  /// Minimum rating out of 10 (« Note ≥ 7 »).
  final int? minRating;
  final SearchSort? sort;

  /// Thresholds of the « Note » filter: 1 to 9.
  static const ratings = [1, 2, 3, 4, 5, 6, 7, 8, 9];

  bool get hasTitleFilters => genre != null || decade != null || minRating != null;

  bool get isDefault => kind == SearchKind.all && !hasTitleFilters && sort == null && category == null;

  /// Without a text, movies and TV shows are browsed when a filter (genre, years, rating) or an
  /// order is chosen (developer's request, 21/11/2026: « les films d'horreur depuis 2010 notés 8 et
  /// plus »); otherwise the empty field shows the recent searches.
  bool get canBrowse => (hasTitleFilters || sort != null) && (kind == SearchKind.all || kind.mediaType != null);

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
      'year_from': decade?.from,
      'year_to': decade?.to,
      'min_rating': minRating,
      'sort': byDefault ? null : order.name,
    };
  }

  SearchFilters copyWith({
    SearchKind? kind,
    Genre? Function()? genre,
    Decade? Function()? decade,
    int? Function()? minRating,
    SearchSort? Function()? sort,
    TvCategory? Function()? category,
  }) => SearchFilters(
    kind: kind ?? this.kind,
    genre: genre == null ? this.genre : genre(),
    decade: decade == null ? this.decade : decade(),
    minRating: minRating == null ? this.minRating : minRating(),
    sort: sort == null ? this.sort : sort(),
    category: category == null ? this.category : category(),
  );

  @override
  bool operator ==(Object other) =>
      other is SearchFilters &&
      other.kind == kind &&
      other.genre == genre &&
      other.decade == decade &&
      other.minRating == minRating &&
      other.sort == sort &&
      other.category == category;

  @override
  int get hashCode => Object.hash(kind, genre, decade, minRating, sort, category);
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
