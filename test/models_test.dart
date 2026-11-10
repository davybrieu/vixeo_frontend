import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/features/auth/models.dart';
import 'package:vixeo/features/catalog/models.dart';
import 'package:vixeo/features/library/library.dart';
import 'package:vixeo/features/tv/models.dart';

// Payloads shaped like the API's resources (vixeo_backend/docs/openapi.json).

void main() {
  test('reads a live channel and keeps its logo on https, as the provider gives it', () {
    TvChannel channel(Object? logo) =>
        TvChannel.fromJson({'id': 'tf1', 'name': 'TF1', 'category_id': '1', 'logo': logo});

    expect(channel('https://logos.example/tf1.png').logo, 'https://logos.example/tf1.png');
    // A release Android build refuses cleartext: the same address over https.
    expect(channel('http://logos.example/tf1.png').logo, 'https://logos.example/tf1.png');
    expect(channel('').logo, isNull);
    expect(channel(null).logo, isNull);
    expect(channel('https://logos.example/tf1.png').name, 'TF1');
  });

  test('reads a profile', () {
    final profile = Profile.fromJson({
      'id': 3,
      'name': 'léa',
      'avatar': null,
      'is_kid': true,
      'max_age_rating': null,
      'effective_max_age_rating': 10,
      'allow_unrated': false,
      'locked_sources': [],
      'has_pin': false,
      'position': 2,
      'created_at': '2026-11-04T10:00:00.000000Z',
      'updated_at': '2026-11-04T10:00:00.000000Z',
    });

    expect(profile.isKid, isTrue);
    expect(profile.effectiveMaxAgeRating, 10);
    expect(profile.initial, 'L');
  });

  test('reads the playback settings of a profile', () {
    final profile = Profile.fromJson({
      'id': 3,
      'name': 'Léa',
      'audio_language': 'fr',
      'subtitle_language': 'pt-BR',
      'no_spoiler': true,
      'skip_intro': true,
      'skip_recap': false,
      'skip_credits': true,
      'skip_preview': false,
    });
    expect(profile.audioLanguage, 'fr');
    expect(profile.subtitleLanguage, 'pt-BR');
    expect(profile.noSpoiler, isTrue);
    expect(profile.skipIntro, isTrue);
    expect(profile.skipCredits, isTrue);
    expect(profile.skipRecap, isFalse);

    final older = Profile.fromJson({'id': 3, 'name': 'Léa'});
    expect(older.audioLanguage, isNull);
    expect(older.noSpoiler, isFalse);
    expect(older.skipIntro, isFalse);
  });

  test('reads a catalog item and builds image sizes', () {
    final item = MediaItem.fromJson({
      'id': 1399,
      'type': 'tv',
      'title': 'Game of Thrones',
      'original_title': 'Game of Thrones',
      'overview': null,
      'date': '2011-04-17',
      'year': 2011,
      'vote_average': 8.4,
      'genre_ids': [10765],
      'poster_path': '/got.jpg',
      'poster_url': 'https://image.tmdb.org/t/p/w342/got.jpg',
      'backdrop_path': '/bd.jpg',
      'backdrop_url': 'https://image.tmdb.org/t/p/w1280/bd.jpg',
    });

    expect(item.type, MediaType.tv);
    expect(item.syncId, 'tv:1399');
    expect(item.poster('w780'), 'https://image.tmdb.org/t/p/w780/got.jpg');
    expect(item.backdrop('original'), 'https://image.tmdb.org/t/p/original/bd.jpg');
  });

  test('reads a page of titles (discover, search by type)', () {
    final page = Paged.fromJson({
      'data': [
        {
          'id': 550,
          'type': 'movie',
          'title': 'Fight Club',
          'genre_ids': [18],
        },
      ],
      'meta': {'page': 2, 'total_pages': 3, 'total_results': 60},
    }, MediaItem.fromJson);

    expect(page.items.single.title, 'Fight Club');
    expect(page.page, 2);
    expect(page.hasMore, isTrue);
    expect(Paged.fromJson({'data': []}, MediaItem.fromJson).hasMore, isFalse);
  });

  test('reads the logo of a home item', () {
    final item = MediaItem.fromJson({
      'id': 550,
      'type': 'movie',
      'title': 'Fight Club',
      'logo_url': 'https://image.tmdb.org/t/p/w500/logo.png',
      'logo_aspect_ratio': 4,
    });
    expect(item.logoUrl, 'https://image.tmdb.org/t/p/w500/logo.png');
    expect(item.logoAspectRatio, 4.0);
    expect(MediaItem.fromJson({'id': 1, 'type': 'tv', 'title': 'Dark'}).logoUrl, isNull);
  });

  test('prefers the poster without text, else the usual one', () {
    final item = MediaItem.fromJson({
      'id': 550,
      'type': 'movie',
      'title': 'Fight Club',
      'poster_path': '/poster.jpg',
      'poster_url': 'https://image.tmdb.org/t/p/w342/poster.jpg',
      'textless_poster_path': '/clean.jpg',
      'textless_poster_url': 'https://image.tmdb.org/t/p/w500/clean.jpg',
    });
    expect(item.cleanPoster('w780'), 'https://image.tmdb.org/t/p/w780/clean.jpg');

    final usual = MediaItem.fromJson({
      'id': 550,
      'type': 'movie',
      'title': 'Fight Club',
      'poster_path': '/poster.jpg',
      'poster_url': 'https://image.tmdb.org/t/p/w342/poster.jpg',
    });
    expect(usual.cleanPoster('w780'), 'https://image.tmdb.org/t/p/w780/poster.jpg');
  });

  test('resizes images on whatever host the API uses', () {
    expect(resizeImage('http://cdn.test/t/p/w342/a.jpg', '/a.jpg', 'w780'), 'http://cdn.test/t/p/w780/a.jpg');
    expect(resizeImage(null, '/a.jpg', 'w780'), isNull);
    expect(resizeImage('http://cdn.test/other.jpg', '/a.jpg', 'w780'), 'http://cdn.test/other.jpg');
  });

  test('reads a movie page', () {
    final movie = TitleDetails.fromJson({
      'id': 550,
      'type': 'movie',
      'title': 'Fight Club',
      'year': 1999,
      'runtime': 139,
      'genres': [
        {'id': 18, 'name': 'Drame'},
      ],
      'vote_average': 8.4,
      'age_rating': 16,
      'trailer': {
        'name': 'Bande-annonce',
        'site': 'YouTube',
        'key': 'k',
        'url': 'https://www.youtube.com/watch?v=k',
        'language': 'fr',
      },
      'directors': [
        {'id': 7467, 'name': 'David Fincher', 'profile_url': null},
      ],
      'cast': [
        {'id': 287, 'name': 'Brad Pitt', 'character': 'Tyler Durden', 'profile_url': null},
      ],
      'recommended': [
        {'id': 807, 'type': 'movie', 'title': 'Seven'},
      ],
    });

    expect(movie.runtime, 139);
    expect(formatRuntime(movie.runtime), '2 h 19');
    expect(movie.ageRating, 16);
    expect(movie.trailer?.url, 'https://www.youtube.com/watch?v=k');
    expect(movie.crew.single.name, 'David Fincher');
    expect(movie.cast.single.role, 'Tyler Durden');
    expect(movie.cast.single.initials, 'BP');
    expect(movie.recommended.single.title, 'Seven');
    // No logo nor textless backdrop: the title is written on the main backdrop.
    expect(movie.logoUrl, isNull);
    expect(movie.background('original'), isNull);
  });

  test('reads the title logo and the textless backdrop of a page', () {
    final movie = TitleDetails.fromJson({
      'id': 550,
      'type': 'movie',
      'title': 'Fight Club',
      'backdrop_path': '/main.jpg',
      'backdrop_url': 'https://image.tmdb.org/t/p/w1280/main.jpg',
      'logo_url': 'https://image.tmdb.org/t/p/w500/logo.png',
      'logo_aspect_ratio': 2,
      'textless_backdrop_path': '/clean.jpg',
      'textless_backdrop_url': 'https://image.tmdb.org/t/p/w1280/clean.jpg',
    });

    expect(movie.logoUrl, 'https://image.tmdb.org/t/p/w500/logo.png');
    expect(movie.logoAspectRatio, 2.0);
    expect(movie.background('original'), 'https://image.tmdb.org/t/p/original/clean.jpg');

    final withoutTextless = TitleDetails.fromJson({
      'id': 550,
      'type': 'movie',
      'title': 'Fight Club',
      'backdrop_path': '/main.jpg',
      'backdrop_url': 'https://image.tmdb.org/t/p/w1280/main.jpg',
    });
    expect(withoutTextless.background('original'), 'https://image.tmdb.org/t/p/original/main.jpg');
  });

  test('reads a TV show page and puts specials last', () {
    final show = TitleDetails.fromJson({
      'id': 1399,
      'type': 'tv',
      'title': 'Game of Thrones',
      'episode_runtime': 60,
      'number_of_seasons': 8,
      'creators': [
        {'id': 1, 'name': 'David Benioff'},
      ],
      'seasons': [
        {'id': 1, 'season_number': 0, 'name': 'Épisodes spéciaux', 'episode_count': 14},
        {'id': 2, 'season_number': 1, 'name': 'Saison 1', 'episode_count': 10},
      ],
    });

    expect(show.runtime, 60);
    expect(show.crew.single.name, 'David Benioff');
    expect(show.seasons.map((s) => s.number), [1, 0]);
  });

  test('reads the length, genres and age rating given with home and search items', () {
    final movie = MediaItem.fromJson({
      'id': 550,
      'type': 'movie',
      'title': 'Fight Club',
      'summary': {
        'runtime': 139,
        'number_of_seasons': null,
        'genres': ['Drame', 'Thriller'],
        'age_rating': 16,
      },
    });
    expect(movie.summary!.length, '2 h 19');
    expect(movie.summary!.genres, ['Drame', 'Thriller']);
    expect(movie.summary!.ageLabel, '16+');

    final show = MediaItem.fromJson({
      'id': 1399,
      'type': 'tv',
      'title': 'Game of Thrones',
      'summary': {'runtime': null, 'number_of_seasons': 1, 'genres': [], 'age_rating': 0},
    });
    expect(show.summary!.length, '1 saison');
    expect(show.summary!.ageLabel, 'Tous publics');
    expect(const TitleSummary(numberOfSeasons: 8).length, '8 saisons');

    // Other lists: the title page gives them.
    expect(MediaItem.fromJson({'id': 1, 'type': 'movie', 'title': 'Dune', 'summary': null}).summary, isNull);
  });

  test('reads the episodes of a season and their air date', () {
    final season = Season.fromJson({
      'show_id': 1399,
      'season_number': 1,
      'name': 'Saison 1',
      'episodes': [
        {'id': 63056, 'season_number': 1, 'episode_number': 1, 'name': 'L’hiver vient', 'air_date': '2011-04-17'},
        {'id': 63057, 'season_number': 1, 'episode_number': 2, 'name': 'La route royale', 'air_date': null},
      ],
    });

    expect(season.episodes.first.airDate, DateTime(2011, 4, 17));
    expect(formatFrenchDate(season.episodes.first.airDate!), '17 avril 2011');
    expect(season.episodes.last.airDate, isNull);
  });

  test('formats ratings and durations the French way', () {
    expect(formatRating(8.44), '8,4');
    expect(formatRuntime(45), '45 min');
    expect(formatRuntime(126), '2 h 06');
    expect(formatRuntime(null), '');
  });

  test('reads a synced item and describes the resume point', () {
    final item = ProfileItem.fromJson({
      'source': 'tmdb',
      'item_id': 'episode:1399:3:2',
      'type': 'episode',
      'title': 'La tour',
      'parent_item_id': 'tv:1399',
      'season_number': 3,
      'episode_number': 2,
      'is_favorite': false,
      'position_ms': 1_800_000,
      'duration_ms': 2_880_000,
      'progress': 0.625,
      'last_engaged_at': '2026-06-01T10:30:00.000000Z',
      'is_watched': false,
    });

    expect(item.inContinueWatching, isTrue);
    expect(item.resumeLabel, 'S3 · É2 · 18 min restantes');
    expect(item.tmdbTitle, (type: MediaType.tv, id: 1399));
  });

  test('lists favorites and continue watching from the synced items', () {
    ProfileItem make(String id, {bool favorite = false, String? favAt, String? engaged, bool watched = false}) =>
        ProfileItem.fromJson({
          'source': 'tmdb',
          'item_id': id,
          'type': 'movie',
          'title': id,
          'is_favorite': favorite,
          'favorited_at': favAt,
          'last_engaged_at': engaged,
          'is_watched': watched,
        });

    final state = LibraryState({
      for (final i in [
        make('movie:1', favorite: true, favAt: '2026-01-01T00:00:00Z'),
        make('movie:2', favorite: true, favAt: '2026-01-03T00:00:00Z', engaged: '2026-01-02T00:00:00Z'),
        make('movie:3', engaged: '2026-01-05T00:00:00Z'),
        make('movie:4', engaged: '2026-01-06T00:00:00Z', watched: true),
      ])
        i.key: i,
    });

    expect(state.favorites.map((i) => i.itemId), ['movie:2', 'movie:1']);
    expect(state.continueWatching.map((i) => i.itemId), ['movie:3', 'movie:2']);
    expect(state.forItem(const MediaItem(id: 2, type: MediaType.movie, title: 'x'))?.isFavorite, isTrue);
  });
}
