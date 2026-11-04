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
    this.posterUrl,
    this.backdropUrl,
    this.posterPath,
    this.backdropPath,
  });

  factory MediaItem.fromJson(Map<String, dynamic> json) => MediaItem(
    id: json['id'] as int,
    type: MediaType.parse(json['type']),
    title: json['title'] as String? ?? '',
    overview: json['overview'] as String?,
    year: json['year'] as int?,
    voteAverage: _double(json['vote_average']),
    posterUrl: json['poster_url'] as String?,
    backdropUrl: json['backdrop_url'] as String?,
    posterPath: json['poster_path'] as String?,
    backdropPath: json['backdrop_path'] as String?,
  );

  final int id;
  final MediaType type;
  final String title;
  final String? overview;
  final int? year;
  final double voteAverage;
  final String? posterUrl;
  final String? backdropUrl;
  final String? posterPath;
  final String? backdropPath;

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
    this.ageRating,
    this.posterUrl,
    this.backdropUrl,
    this.posterPath,
    this.backdropPath,
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
      ageRating: json['age_rating'] as int?,
      posterUrl: json['poster_url'] as String?,
      backdropUrl: json['backdrop_url'] as String?,
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
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

  /// Minimum age (0 = all audiences), null if unknown.
  final int? ageRating;
  final String? posterUrl;
  final String? backdropUrl;
  final String? posterPath;
  final String? backdropPath;
  final Trailer? trailer;
  final List<Person> cast;

  /// Directors (movie) or creators (TV show).
  final List<Person> crew;
  final List<SeasonSummary> seasons;
  final List<MediaItem> recommended;

  String get syncId => '${type.name}:$id';

  MediaItem get asItem => MediaItem(
    id: id,
    type: type,
    title: title,
    overview: overview,
    year: year,
    voteAverage: voteAverage,
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
  });

  factory Episode.fromJson(Map<String, dynamic> json) => Episode(
    id: json['id'] as int,
    seasonNumber: json['season_number'] as int? ?? 0,
    number: json['episode_number'] as int? ?? 0,
    name: json['name'] as String? ?? '',
    overview: json['overview'] as String?,
    runtime: json['runtime'] as int?,
    stillUrl: json['still_url'] as String?,
  );

  final int id;
  final int seasonNumber;
  final int number;
  final String name;
  final String? overview;
  final int? runtime;
  final String? stillUrl;
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

/// Human-readable duration: "2 h 06", "45 min".
String formatRuntime(int? minutes) {
  if (minutes == null || minutes <= 0) return '';
  if (minutes < 60) return '$minutes min';
  final m = minutes % 60;
  return '${minutes ~/ 60} h ${m.toString().padLeft(2, '0')}';
}

/// "8,4" (French decimal comma).
String formatRating(double value) => value.toStringAsFixed(1).replaceAll('.', ',');
