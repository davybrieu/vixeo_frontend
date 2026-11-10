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
  person('Personnes');

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
  rating('Mieux notés'),
  recent('Plus récents'),
  oldest('Plus anciens');

  const SearchSort(this.label);

  final String label;

  /// Orders offered with or without a text.
  static List<SearchSort> available({required bool withText}) =>
      withText ? values : values.where((s) => s != SearchSort.relevance).toList();
}

/// "Années" filter.
enum Decade {
  y2020s(2020, 2029, 'Années 2020'),
  y2010s(2010, 2019, 'Années 2010'),
  y2000s(2000, 2009, 'Années 2000'),
  y1990s(1990, 1999, 'Années 1990'),
  y1980s(1980, 1989, 'Années 1980'),
  before1980(null, 1979, 'Avant 1980');

  const Decade(this.from, this.to, this.label);

  final int? from;
  final int to;
  final String label;
}

/// Filters and order of the search page. Genre, years and rating apply to movies and TV shows
/// only, [category] to live channels only; [sort] null = the default order (relevance with a
/// text, popularity without).
@immutable
class SearchFilters {
  const SearchFilters({this.kind = SearchKind.all, this.genre, this.decade, this.minRating, this.sort, this.category});

  final SearchKind kind;

  /// Category of the live channels (type « Chaînes TV »), null = all.
  final TvCategory? category;
  final Genre? genre;
  final Decade? decade;

  /// Minimum TMDb rating out of 10 (6, 7, 8).
  final int? minRating;
  final SearchSort? sort;

  static const ratings = [6, 7, 8];

  bool get hasTitleFilters => genre != null || decade != null || minRating != null;

  bool get isDefault => kind == SearchKind.all && !hasTitleFilters && sort == null && category == null;

  /// The order really used: relevance needs a text.
  SearchSort sortFor({required bool withText}) {
    final value = sort ?? (withText ? SearchSort.relevance : SearchSort.popularity);
    return !withText && value == SearchSort.relevance ? SearchSort.popularity : value;
  }

  /// Query parameters of the API (discover and search), the default ones left out.
  Map<String, Object?> query({required bool withText}) {
    final order = sortFor(withText: withText);
    return {
      'genre': genre?.id,
      'year_from': decade?.from,
      'year_to': decade?.to,
      'min_rating': minRating,
      'sort': order == (withText ? SearchSort.relevance : SearchSort.popularity) ? null : order.name,
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

/// One request of titles: explore (no [query]) or search, for one type.
@immutable
class TitleQuery {
  const TitleQuery(this.type, this.filters, {this.query, this.page = 1});

  final MediaType type;
  final SearchFilters filters;
  final String? query;
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
