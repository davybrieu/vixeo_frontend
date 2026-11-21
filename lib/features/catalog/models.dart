import 'package:flutter/foundation.dart';

// Models mirroring the API's catalog resources (see vixeo_backend/docs/openapi.json).

enum MediaType {
  movie,
  tv;

  static MediaType parse(Object? value) => value == 'tv' ? MediaType.tv : MediaType.movie;

  String get label => this == MediaType.movie ? 'Film' : 'Série';
}

List<T> _list<T>(Object? value, T Function(Map<String, dynamic>) parse) =>
    value is List ? value.whereType<Map<String, dynamic>>().map(parse).toList() : <T>[];

double _double(Object? value) => value is num ? value.toDouble() : 0;

/// Movie or TV show summary (MediaItemResource).
class MediaItem {
  const MediaItem({
    required this.id,
    required this.type,
    required this.title,
    this.overview,
    this.year,
    this.voteAverage = 0,
    this.ratings,
    this.posterUrl,
    this.backdropUrl,
    this.posterPath,
    this.backdropPath,
    this.logoUrl,
    this.logoAspectRatio,
    this.summary,
    this.genreIds = const [],
  });

  factory MediaItem.fromJson(Map<String, dynamic> json) => MediaItem(
    id: json['id'] as int,
    type: MediaType.parse(json['type']),
    title: json['title'] as String? ?? '',
    overview: json['overview'] as String?,
    year: json['year'] as int?,
    voteAverage: _double(json['vote_average']),
    ratings: json['ratings'] is Map<String, dynamic> ? TitleRatings.fromJson(json['ratings']) : null,
    posterUrl: json['poster_url'] as String?,
    backdropUrl: json['backdrop_url'] as String?,
    posterPath: json['poster_path'] as String?,
    backdropPath: json['backdrop_path'] as String?,
    logoUrl: json['logo_url'] as String?,
    logoAspectRatio: (json['logo_aspect_ratio'] as num?)?.toDouble(),
    summary: json['summary'] is Map<String, dynamic>
        ? TitleSummary.fromJson(json['summary'] as Map<String, dynamic>)
        : null,
    genreIds: [if (json['genre_ids'] is List) ...(json['genre_ids'] as List).whereType<int>()],
  );

  /// This title completed by its catalog entry ([details], `GET /catalog/titles`): the logo, the
  /// summary, the overview, the rating… it lacks. What it has stays.
  MediaItem withDetails(MediaItem? details) => details == null
      ? this
      : MediaItem(
          id: id,
          type: type,
          title: title,
          overview: overview ?? details.overview,
          year: year ?? details.year,
          voteAverage: voteAverage > 0 ? voteAverage : details.voteAverage,
          ratings: ratings ?? details.ratings,
          posterUrl: posterUrl ?? details.posterUrl,
          backdropUrl: backdropUrl ?? details.backdropUrl,
          posterPath: posterPath ?? details.posterPath,
          backdropPath: backdropPath ?? details.backdropPath,
          logoUrl: logoUrl ?? details.logoUrl,
          logoAspectRatio: logoUrl != null ? logoAspectRatio : details.logoAspectRatio,
          summary: summary ?? details.summary,
          genreIds: genreIds.isNotEmpty ? genreIds : details.genreIds,
        );

  final int id;
  final MediaType type;
  final String title;
  final String? overview;
  final int? year;
  final double voteAverage;

  /// IMDb's and TMDb's ratings, given with every list of titles; null for the light home rows
  /// (until completed by `GET /catalog/titles`) or a title TMDb could not give: no rating is shown.
  final TitleRatings? ratings;
  final String? posterUrl;
  final String? backdropUrl;
  final String? posterPath;
  final String? backdropPath;

  /// Title logo: given on the home rows only (elsewhere, the title page has it).
  final String? logoUrl;
  final double? logoAspectRatio;


  /// Length, genres and age rating, given with home and search items: the hero shows them at once.
  final TitleSummary? summary;

  /// TMDb genre ids (filters of Ma liste).
  final List<int> genreIds;

  /// The rating its card shows: IMDb's, else TMDb's (only a fallback, developer's request,
  /// 21/11/2026); null when neither rates it, or without [ratings]: TMDb's [voteAverage] alone would
  /// pass for the rating chosen while IMDb may have one.
  (RatingSite, SiteRating)? get shownRating => ratings?.shown;

  /// Title logo at the size of a card (w300: lighter than the hero's w500, so it comes with the image).
  String? get cardLogoUrl => tmdbImageSize(logoUrl, 'w300');

  /// Identity used by the sync API (`source` = "tmdb").
  String get syncId => '${type.name}:$id';

  /// Poster at another TMDb size ("w500", "w780"…), falls back to [posterUrl].
  String? poster(String size) => resizeImage(posterUrl, posterPath, size);

  /// Backdrop at another TMDb size ("w780", "original"…), falls back to [backdropUrl].
  String? backdrop(String size) => resizeImage(backdropUrl, backdropPath, size);
}

/// Same image at another size: the API returns `<base><size><path>`
/// (e.g. `https://image.tmdb.org/t/p/w342/abc.jpg`); swap the size segment.
String? resizeImage(String? url, String? path, String size) {
  if (url == null || path == null || !url.endsWith(path)) return url;
  final prefix = url.substring(0, url.length - path.length);
  final base = prefix.substring(0, prefix.lastIndexOf('/', prefix.length - 2) + 1);
  return '$base$size$path';
}

/// The same TMDb image at another size ("w300"): replaces the size segment of the URL
/// (`…/t/p/w500/abc.png`). Other URLs are kept.
String? tmdbImageSize(String? url, String size) =>
    url?.replaceFirstMapped(RegExp(r'/(w\d+|original)/(?=[^/]+$)'), (_) => '/$size/');

/// Home row (SectionResource).
class Section {
  const Section({required this.key, required this.title, required this.type, required this.list, required this.items});

  factory Section.fromJson(Map<String, dynamic> json) => Section(
    key: json['key'] as String,
    title: json['title'] as String,
    type: MediaType.parse(json['type']),
    list: json['list'] as String,
    items: _list(json['items'], MediaItem.fromJson),
  );

  final String key;
  final String title;
  final MediaType type;
  final String list;
  final List<MediaItem> items;
}

class Home {
  const Home({required this.featured, required this.sections});

  factory Home.fromJson(Map<String, dynamic> json) =>
      Home(featured: _list(json['featured'], MediaItem.fromJson), sections: _list(json['sections'], Section.fromJson));

  final List<MediaItem> featured;
  final List<Section> sections;
}

class Genre {
  const Genre(this.id, this.name);

  factory Genre.fromJson(Map<String, dynamic> json) => Genre(json['id'] as int, json['name'] as String);

  final int id;
  final String name;

  @override
  bool operator ==(Object other) => other is Genre && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// One page of a paginated list (`data` + `meta`: discover, search by type).
/// What the hero shows besides the name: length, genres, age rating (API `summary` of home and
/// search items, or taken from the title page).
@immutable
class TitleSummary {
  const TitleSummary({this.runtime, this.numberOfSeasons, this.genres = const [], this.ageRating});

  factory TitleSummary.fromJson(Map<String, dynamic> json) => TitleSummary(
    runtime: json['runtime'] as int?,
    numberOfSeasons: json['number_of_seasons'] as int?,
    genres: [if (json['genres'] is List) ...(json['genres'] as List).whereType<String>()],
    ageRating: json['age_rating'] as int?,
  );

  factory TitleSummary.of(TitleDetails title) => TitleSummary(
    runtime: title.type == MediaType.movie ? title.runtime : null,
    numberOfSeasons: title.type == MediaType.tv && title.numberOfSeasons > 0 ? title.numberOfSeasons : null,
    genres: [for (final g in title.genres) g.name],
    ageRating: title.ageRating,
  );

  /// Movie length in minutes.
  final int? runtime;

  /// TV show: number of seasons.
  final int? numberOfSeasons;
  final List<String> genres;

  /// Minimum age (0 = all audiences).
  final int? ageRating;

  /// "2 h 19", "3 saisons".
  String? get length => runtime != null
      ? formatRuntime(runtime)
      : numberOfSeasons == null
      ? null
      : '$numberOfSeasons saison${numberOfSeasons! > 1 ? 's' : ''}';

  /// "Tous publics", "12+".
  String? get ageLabel => ageRating == null ? null : (ageRating == 0 ? 'Tous publics' : '$ageRating+');
}

class Paged<T> {
  const Paged({required this.items, this.page = 1, this.totalPages = 1});

  factory Paged.fromJson(Map<String, dynamic> json, T Function(Map<String, dynamic>) parse) {
    final meta = json['meta'] is Map ? json['meta'] as Map : const {};
    return Paged(
      items: _list(json['data'], parse),
      page: meta['page'] as int? ?? 1,
      totalPages: meta['total_pages'] as int? ?? 1,
    );
  }

  final List<T> items;
  final int page;
  final int totalPages;

  bool get hasMore => page < totalPages;
}

class Person {
  const Person({required this.id, required this.name, this.role, this.profileUrl});

  factory Person.fromJson(Map<String, dynamic> json) => Person(
    id: json['id'] as int,
    name: json['name'] as String? ?? '',
    role: (json['character'] ?? json['known_for_department']) as String?,
    profileUrl: json['profile_url'] as String?,
  );

  final int id;
  final String name;

  /// Character (cast) or department (search results).
  final String? role;
  final String? profileUrl;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final first = String.fromCharCode(parts.first.runes.first);
    final last = parts.length > 1 ? String.fromCharCode(parts.last.runes.first) : '';
    return (first + last).toUpperCase();
  }
}

/// Everyone of a title, for « Créateur et distribution » → « Voir tout »
/// (`GET /catalog/{type}/{id}/credits`; the title page only has 20 cast members).
class TitleCredits {
  const TitleCredits({required this.crew, required this.cast});

  factory TitleCredits.fromJson(Map<String, dynamic> json) =>
      TitleCredits(crew: _list(json['crew'], Person.fromJson), cast: _list(json['cast'], Person.fromJson));

  /// Directors (movie) or creators (TV show).
  final List<Person> crew;

  /// The whole cast, in billing order; [Person.role] is the character.
  final List<Person> cast;
}

/// Order of a person's titles (`GET /catalog/person/{id}/credits?sort=`).
enum PersonCreditsSort {
  /// Most voted first: « Connu pour ».
  popular,

  /// Newest first: « Filmographie ».
  date,
}

class Trailer {
  const Trailer({required this.url, this.name});

  factory Trailer.fromJson(Map<String, dynamic> json) =>
      Trailer(url: json['url'] as String, name: json['name'] as String?);

  final String url;
  final String? name;
}

class SeasonSummary {
  const SeasonSummary({required this.number, required this.name, required this.episodeCount});

  factory SeasonSummary.fromJson(Map<String, dynamic> json) => SeasonSummary(
    number: json['season_number'] as int,
    name: json['name'] as String? ?? '',
    episodeCount: json['episode_count'] as int? ?? 0,
  );

  final int number;
  final String name;
  final int episodeCount;
}

/// A site whose rating the app shows: IMDb's (imported from IMDb's datasets by the API), else
/// TMDb's (vixeo_backend/docs/notes.md).
enum RatingSite {
  imdb('IMDb'),
  tmdb('TMDb');

  const RatingSite(this.label);

  /// Name shown in « Notes » and read by screen readers.
  final String label;
}

/// A rating out of 10 and its number of votes.
@immutable
class SiteRating {
  const SiteRating(this.value, this.votes);

  final double value;
  final int votes;

  @override
  bool operator ==(Object other) => other is SiteRating && other.value == value && other.votes == votes;

  @override
  int get hashCode => Object.hash(value, votes);
}

/// IMDb's and TMDb's ratings of a movie, a TV show or an episode, with their votes (`ratings` of the
/// API, RatingsResource). [imdb] null: IMDb doesn't rate it (or the title has no IMDb id); [tmdb]
/// null: nobody voted on TMDb yet.
@immutable
class TitleRatings {
  const TitleRatings({this.imdb, this.imdbId, this.tmdb});

  /// `ratings` of the API; without it (older API), TMDb's [voteAverage] / [voteCount] alone.
  factory TitleRatings.fromJson(Object? json, {double voteAverage = 0, int voteCount = 0}) {
    SiteRating? parse(Object? site) => switch (site) {
      {'rating': final num value, 'votes': final num votes} when value > 0 => SiteRating(
        value.toDouble(),
        votes.toInt(),
      ),
      _ => null,
    };
    if (json is! Map<String, dynamic>) {
      return TitleRatings(tmdb: voteAverage > 0 ? SiteRating(voteAverage, voteCount) : null);
    }
    final imdb = json['imdb'];
    return TitleRatings(
      imdb: parse(imdb),
      imdbId: imdb is Map<String, dynamic> ? imdb['id'] as String? : null,
      tmdb: parse(json['tmdb']),
    );
  }

  static const none = TitleRatings();

  final SiteRating? imdb;

  /// IMDb id of the rated title (tt…).
  final String? imdbId;
  final SiteRating? tmdb;

  SiteRating? operator [](RatingSite site) => site == RatingSite.imdb ? imdb : tmdb;

  /// The rating shown next to the title: IMDb's, else TMDb's; null when neither rates it.
  (RatingSite, SiteRating)? get shown => switch ((imdb, tmdb)) {
    (final imdb?, _) => (RatingSite.imdb, imdb),
    (null, final tmdb?) => (RatingSite.tmdb, tmdb),
    _ => null,
  };

  bool get isEmpty => imdb == null && tmdb == null;
}

/// Movie page (MovieResource) or TV show page (ShowResource).
class TitleDetails {
  const TitleDetails({
    required this.id,
    required this.type,
    required this.title,
    this.tagline,
    this.overview,
    this.year,
    this.runtime,
    this.numberOfSeasons = 0,
    this.genres = const [],
    this.voteAverage = 0,
    this.ratings = TitleRatings.none,
    this.ageRating,
    this.posterUrl,
    this.backdropUrl,
    this.posterPath,
    this.backdropPath,
    this.logoUrl,
    this.logoAspectRatio,
    this.textlessBackdropUrl,
    this.textlessBackdropPath,
    this.trailer,
    this.cast = const [],
    this.crew = const [],
    this.seasons = const [],
    this.recommended = const [],
  });

  factory TitleDetails.fromJson(Map<String, dynamic> json) {
    final type = MediaType.parse(json['type']);
    return TitleDetails(
      id: json['id'] as int,
      type: type,
      title: json['title'] as String? ?? '',
      tagline: json['tagline'] as String?,
      overview: json['overview'] as String?,
      year: json['year'] as int?,
      runtime: (type == MediaType.movie ? json['runtime'] : json['episode_runtime']) as int?,
      numberOfSeasons: json['number_of_seasons'] as int? ?? 0,
      genres: _list(json['genres'], Genre.fromJson),
      voteAverage: _double(json['vote_average']),
      ratings: TitleRatings.fromJson(
        json['ratings'],
        voteAverage: _double(json['vote_average']),
        voteCount: json['vote_count'] as int? ?? 0,
      ),
      ageRating: json['age_rating'] as int?,
      posterUrl: json['poster_url'] as String?,
      backdropUrl: json['backdrop_url'] as String?,
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      logoUrl: json['logo_url'] as String?,
      logoAspectRatio: (json['logo_aspect_ratio'] as num?)?.toDouble(),
      textlessBackdropUrl: json['textless_backdrop_url'] as String?,
      textlessBackdropPath: json['textless_backdrop_path'] as String?,
      trailer: json['trailer'] is Map<String, dynamic>
          ? Trailer.fromJson(json['trailer'] as Map<String, dynamic>)
          : null,
      cast: _list(json['cast'], Person.fromJson),
      crew: _list(json[type == MediaType.movie ? 'directors' : 'creators'], Person.fromJson),
      // Specials (season 0) last.
      seasons: _list(json['seasons'], SeasonSummary.fromJson)
        ..sort((a, b) => (a.number == 0 ? 9999 : a.number).compareTo(b.number == 0 ? 9999 : b.number)),
      recommended: _list(json['recommended'], MediaItem.fromJson),
    );
  }

  final int id;
  final MediaType type;
  final String title;
  final String? tagline;
  final String? overview;
  final int? year;

  /// Movie duration, or typical episode duration, in minutes.
  final int? runtime;
  final int numberOfSeasons;
  final List<Genre> genres;
  final double voteAverage;

  /// IMDb's and TMDb's ratings: IMDb's shown, else TMDb's; both in « Notes ».
  final TitleRatings ratings;

  /// Minimum age (0 = all audiences), null if unknown.
  final int? ageRating;
  final String? posterUrl;
  final String? backdropUrl;
  final String? posterPath;
  final String? backdropPath;

  /// Title logo from TMDb (transparent PNG), null when there is none: the title is written.
  final String? logoUrl;

  /// Logo width / height.
  final double? logoAspectRatio;

  /// Backdrop without text, to show under the logo.
  final String? textlessBackdropUrl;
  final String? textlessBackdropPath;
  final Trailer? trailer;
  final List<Person> cast;

  /// Directors (movie) or creators (TV show).
  final List<Person> crew;
  final List<SeasonSummary> seasons;
  final List<MediaItem> recommended;

  String get syncId => '${type.name}:$id';

  /// Background of the title page: the backdrop without text if TMDb has one, else the main one.
  String? background(String size) =>
      resizeImage(textlessBackdropUrl, textlessBackdropPath, size) ?? asItem.backdrop(size);

  MediaItem get asItem => MediaItem(
    id: id,
    type: type,
    title: title,
    overview: overview,
    year: year,
    voteAverage: voteAverage,
    ratings: ratings,
    posterUrl: posterUrl,
    backdropUrl: backdropUrl,
    posterPath: posterPath,
    backdropPath: backdropPath,
  );
}

class Episode {
  const Episode({
    required this.id,
    required this.seasonNumber,
    required this.number,
    required this.name,
    this.overview,
    this.runtime,
    this.stillUrl,
    this.voteAverage = 0,
    this.ratings = TitleRatings.none,
    this.airDate,
  });

  factory Episode.fromJson(Map<String, dynamic> json) => Episode(
    id: json['id'] as int,
    seasonNumber: json['season_number'] as int? ?? 0,
    number: json['episode_number'] as int? ?? 0,
    name: json['name'] as String? ?? '',
    overview: json['overview'] as String?,
    runtime: json['runtime'] as int?,
    stillUrl: json['still_url'] as String?,
    voteAverage: _double(json['vote_average']),
    ratings: TitleRatings.fromJson(
      json['ratings'],
      voteAverage: _double(json['vote_average']),
      voteCount: json['vote_count'] as int? ?? 0,
    ),
    airDate: DateTime.tryParse(json['air_date'] as String? ?? ''),
  );

  final int id;
  final int seasonNumber;
  final int number;
  final String name;
  final String? overview;
  final int? runtime;
  final String? stillUrl;
  final double voteAverage;

  /// IMDb's and TMDb's ratings of the episode.
  final TitleRatings ratings;

  /// First broadcast (null when TMDb doesn't know it yet).
  final DateTime? airDate;
}

class Season {
  const Season({required this.showId, required this.number, required this.name, required this.episodes});

  factory Season.fromJson(Map<String, dynamic> json) => Season(
    showId: json['show_id'] as int,
    number: json['season_number'] as int? ?? 0,
    name: json['name'] as String? ?? '',
    episodes: _list(json['episodes'], Episode.fromJson),
  );

  final int showId;
  final int number;
  final String name;
  final List<Episode> episodes;
}

class SearchResults {
  const SearchResults({required this.movies, required this.shows, required this.people});

  factory SearchResults.fromJson(Map<String, dynamic> json) => SearchResults(
    movies: _list((json['movies'] as Map?)?['data'], MediaItem.fromJson),
    shows: _list((json['shows'] as Map?)?['data'], MediaItem.fromJson),
    people: _list((json['people'] as Map?)?['data'], Person.fromJson),
  );

  final List<MediaItem> movies;
  final List<MediaItem> shows;
  final List<Person> people;

  bool get isEmpty => movies.isEmpty && shows.isEmpty && people.isEmpty;
}

/// Actor / director page (PersonResource).
class PersonDetails {
  const PersonDetails({
    required this.id,
    required this.name,
    this.biography,
    this.birthday,
    this.deathday,
    this.placeOfBirth,
    this.knownForDepartment,
    this.profileUrl,
    this.knownFor = const [],
    this.filmography = const [],
  });

  factory PersonDetails.fromJson(Map<String, dynamic> json) => PersonDetails(
    id: json['id'] as int,
    name: json['name'] as String? ?? '',
    biography: json['biography'] as String?,
    birthday: DateTime.tryParse(json['birthday'] as String? ?? ''),
    deathday: DateTime.tryParse(json['deathday'] as String? ?? ''),
    placeOfBirth: json['place_of_birth'] as String?,
    knownForDepartment: json['known_for_department'] as String?,
    profileUrl: json['profile_url'] as String?,
    knownFor: _list(json['known_for'], MediaItem.fromJson),
    filmography: _list(json['filmography'], MediaItem.fromJson),
  );

  final int id;
  final String name;
  final String? biography;
  final DateTime? birthday;
  final DateTime? deathday;
  final String? placeOfBirth;
  final String? knownForDepartment;
  final String? profileUrl;

  /// Best-known titles.
  final List<MediaItem> knownFor;

  /// All titles as cast member, most recent first.
  final List<MediaItem> filmography;

  /// "Interprétation", "Réalisation"…
  String? get department => switch (knownForDepartment) {
    null => null,
    'Acting' => 'Interprétation',
    'Directing' => 'Réalisation',
    'Writing' => 'Scénario',
    'Production' => 'Production',
    'Sound' => 'Musique et son',
    'Camera' => 'Image',
    'Editing' => 'Montage',
    'Art' => 'Décors',
    'Costume & Make-Up' => 'Costumes et maquillage',
    'Visual Effects' => 'Effets visuels',
    'Crew' => 'Équipe technique',
    final other => other,
  };

  /// "Né le 18 décembre 1963 à Shawnee, Oklahoma, USA" / "1963 – 2020"…
  String? get lifeLine {
    if (birthday == null) return placeOfBirth == null ? null : 'Originaire de $placeOfBirth';
    final born = 'Naissance : ${formatFrenchDate(birthday!)}${placeOfBirth != null ? ' à $placeOfBirth' : ''}';
    return deathday == null ? born : '$born · Décès : ${formatFrenchDate(deathday!)}';
  }
}

const _frenchMonths = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin', //
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
];

/// "18 décembre 1963" ("1er" for the first day of the month).
String formatFrenchDate(DateTime date) =>
    '${date.day == 1 ? '1er' : date.day} ${_frenchMonths[date.month - 1]} ${date.year}';

/// Human-readable duration: "2 h 06", "45 min".
String formatRuntime(int? minutes) {
  if (minutes == null || minutes <= 0) return '';
  if (minutes < 60) return '$minutes min';
  final m = minutes % 60;
  return '${minutes ~/ 60} h ${m.toString().padLeft(2, '0')}';
}

/// "8,4" (French decimal comma).
String formatRating(double value) => value.toStringAsFixed(1).replaceAll('.', ',');

/// "2 400 000 votants", "1 votant" (thousands separated by a narrow no-break space).
String formatVotes(int votes) => '${formatCount(votes)} ${votes > 1 ? 'votants' : 'votant'}';

/// "2 400 000" (thousands separated by a narrow no-break space, as in French).
String formatCount(int count) =>
    '$count'.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '\u202F');
