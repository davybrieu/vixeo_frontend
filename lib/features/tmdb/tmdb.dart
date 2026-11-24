import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../auth/session.dart';
import '../catalog/models.dart';
import '../catalog/paging.dart' show pageSize;
import '../library/library.dart';

// The active profile's reviews: a rating and an optional comment per movie, TV show or episode
// (vixeo_backend/docs/avis.md). Kept by Vixeo only: no TMDb account is linked any more.

/// What a profile rates: tabs of "Mes notes".
enum RatedType {
  movie('Films'),
  tv('Séries'),
  episode('Épisodes');

  const RatedType(this.label);

  final String label;
}

/// A reviewed movie, TV show or episode.
@immutable
class RatingTarget {
  const RatingTarget.title(this.type, this.id) : season = null, episode = null;

  const RatingTarget.episode(this.id, int this.season, int this.episode) : type = MediaType.tv;

  final MediaType type;

  /// Movie or TV show (also for an episode).
  final int id;
  final int? season;
  final int? episode;

  bool get isEpisode => episode != null;

  RatedType get ratedType => isEpisode ? RatedType.episode : (type == MediaType.movie ? RatedType.movie : RatedType.tv);

  /// Path under `/profiles/{id}/tmdb/ratings/`.
  String get path => isEpisode ? 'tv/$id/season/$season/episode/$episode' : '${type.name}/$id';

  @override
  bool operator ==(Object other) => other is RatingTarget && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

/// The profile's rating of a title and its comment.
@immutable
class MyRating {
  const MyRating(this.value, {this.comment, this.spoilers = false});

  factory MyRating.fromJson(Map<String, dynamic> json) => MyRating(
    (json['value'] as num).toDouble(),
    comment: (json['comment'] as String?)?.trim().isEmpty ?? true ? null : json['comment'] as String,
    spoilers: json['contains_spoilers'] as bool? ?? false,
  );

  /// 0.5 to 10.
  final double value;
  final String? comment;

  /// The comment reveals the story (« Contient des spoilers »): hidden from the other members until
  /// they ask.
  final bool spoilers;

  @override
  bool operator ==(Object other) =>
      other is MyRating && other.value == value && other.comment == comment && other.spoilers == spoilers;

  @override
  int get hashCode => Object.hash(value, comment, spoilers);
}

/// A review of "Mes avis": rating and comment (API `RatedItemResource`).
@immutable
class RatedItem {
  const RatedItem({
    required this.type,
    required this.id,
    required this.title,
    required this.value,
    this.comment,
    this.ratedAt,
    this.year,
    this.seasonNumber,
    this.episodeNumber,
    this.episodeName,
    this.posterUrl,
    this.backdropUrl,
    this.stillUrl,
    this.voteAverage = 0,
    this.reviewId,
    this.likesCount = 0,
    this.liked = false,
    this.spoilers = false,
    this.commentsCount = 0,
  });

  factory RatedItem.fromJson(Map<String, dynamic> json) => RatedItem(
    type: RatedType.values.asNameMap()[json['type']] ?? RatedType.movie,
    id: json['id'] as int,
    title: json['title'] as String? ?? '',
    value: (json['value'] as num?)?.toDouble() ?? 0,
    comment: json['comment'] as String?,
    ratedAt: DateTime.tryParse(json['rated_at'] as String? ?? '')?.toLocal(),
    year: json['year'] as int?,
    seasonNumber: json['season_number'] as int?,
    episodeNumber: json['episode_number'] as int?,
    episodeName: json['episode_name'] as String?,
    posterUrl: json['poster_url'] as String?,
    backdropUrl: json['backdrop_url'] as String?,
    stillUrl: json['still_url'] as String?,
    voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0,
    reviewId: json['review_id'] as int?,
    likesCount: json['likes_count'] as int? ?? 0,
    liked: json['liked'] as bool? ?? false,
    spoilers: json['contains_spoilers'] as bool? ?? false,
    commentsCount: json['comments_count'] as int? ?? 0,
  );

  final RatedType type;

  /// Movie or TV show (the page to open), also for an episode.
  final int id;
  final String title;

  /// The profile's rating, 0.5 to 10.
  final double value;

  /// The profile's comment.
  final String? comment;

  /// When it was rated.
  final DateTime? ratedAt;
  final int? year;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? episodeName;
  final String? posterUrl;
  final String? backdropUrl;
  final String? stillUrl;
  final double voteAverage;

  /// The review's id, for « J'aime » (`PUT /social/reviews/{review_id}/like`); null from an older API.
  final int? reviewId;

  /// How many members like this review.
  final int likesCount;

  /// The active profile likes this review (another member's).
  final bool liked;

  /// The comment reveals the story (« Contient des spoilers »).
  final bool spoilers;

  /// Comments of other members on this review.
  final int commentsCount;

  MediaType get mediaType => type == RatedType.movie ? MediaType.movie : MediaType.tv;

  RatingTarget get target => type == RatedType.episode
      ? RatingTarget.episode(id, seasonNumber ?? 0, episodeNumber ?? 0)
      : RatingTarget.title(mediaType, id);

  MyRating get rating => MyRating(value, comment: comment, spoilers: spoilers);

  /// "Film · 2021", "Série", "Saison 1, épisode 2 · Le Départ"…
  String get subtitle => type == RatedType.episode
      ? 'Saison $seasonNumber, épisode $episodeNumber${episodeName == null ? '' : ' · $episodeName'}'
      : [type == RatedType.movie ? 'Film' : 'Série', if (year != null) '$year'].join(' · ');

  /// "Dune", "Les Hautes Terres · S1 · É2"…
  String get label => type == RatedType.episode ? '$title · S$seasonNumber · É$episodeNumber' : title;

  /// Matches a search of "Mes avis": title, episode name or comment, whatever the case and accents.
  bool matches(String query) {
    final q = foldForSearch(query.trim());
    if (q.isEmpty) return true;
    return [title, episodeName, comment].any((text) => text != null && foldForSearch(text).contains(q));
  }

  /// The same review, rated again (now on top of "Mes avis").
  RatedItem rated(MyRating rating) => RatedItem(
    type: type,
    id: id,
    title: title,
    value: rating.value,
    comment: rating.comment,
    ratedAt: rating.value == value ? ratedAt : DateTime.now(),
    year: year,
    seasonNumber: seasonNumber,
    episodeNumber: episodeNumber,
    episodeName: episodeName,
    posterUrl: posterUrl,
    backdropUrl: backdropUrl,
    stillUrl: stillUrl,
    voteAverage: voteAverage,
    reviewId: reviewId,
    likesCount: likesCount,
    liked: liked,
    spoilers: rating.spoilers,
    commentsCount: commentsCount,
  );
}

/// Lowercase, without accents ("Épisode" → "episode"): searches ignore both.
String foldForSearch(String text) {
  const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyy';
  final buffer = StringBuffer();
  for (final char in text.toLowerCase().split('')) {
    final i = from.indexOf(char);
    buffer.write(switch (char) {
      'œ' => 'oe',
      'æ' => 'ae',
      _ => i < 0 || i >= to.length ? char : to[i],
    });
  }
  return buffer.toString();
}

/// A rating the way people say it: "8", "7,5".
String formatScore(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(1).replaceAll('.', ',');

/// `/profiles/{id}/tmdb/ratings…` of the Vixeo API (historical name: the reviews are Vixeo's).
class TmdbRepository {
  TmdbRepository(this._api);

  final ApiClient _api;

  /// Rating and comment of a movie or TV show, null when not rated.
  Future<MyRating?> rating(int profileId, RatingTarget target) async {
    final data = (await _api.get('/profiles/$profileId/tmdb/ratings/${target.path}'))['data'];
    return data is Map<String, dynamic> && data['value'] != null ? MyRating.fromJson(data) : null;
  }

  /// Ratings of a season's episodes: episode number → rating and comment.
  Future<Map<int, MyRating>> seasonRatings(int profileId, int showId, int season) async {
    final data = (await _api.get('/profiles/$profileId/tmdb/ratings/tv/$showId/season/$season'))['data'];
    return {
      if (data is List)
        for (final e in data.whereType<Map<String, dynamic>>()) e['episode_number'] as int: MyRating.fromJson(e),
    };
  }

  /// Saves the rating and the comment (null removes it).
  Future<void> rate(int profileId, RatingTarget target, MyRating rating) => _api.put(
    '/profiles/$profileId/tmdb/ratings/${target.path}',
    body: {'value': rating.value, 'comment': rating.comment, 'contains_spoilers': rating.spoilers},
  );

  Future<void> unrate(int profileId, RatingTarget target) =>
      _api.delete('/profiles/$profileId/tmdb/ratings/${target.path}');

  /// A page of the profile's reviews (20), of a [type] (null: every type), in an [order].
  Future<Paged<RatedItem>> reviews(
    int profileId, {
    RatedType? type,
    RatedOrder order = RatedOrder.recent,
    int page = 1,
  }) async => Paged.fromJson(
        await _api.get(
          '/profiles/$profileId/tmdb/ratings',
          query: {'type': type?.name, 'sort': order.name, 'per_page': pageSize, 'page': page},
        ),
        RatedItem.fromJson,
      );
}

final tmdbRepositoryProvider = Provider<TmdbRepository>((ref) => TmdbRepository(ref.read(apiClientProvider)));

int? _profileId(Ref ref) => ref.read(sessionProvider).profile?.id;

/// The profile can rate: signed in, with a profile.
final canRateProvider = Provider<bool>((ref) {
  final session = ref.watch(sessionProvider);
  return session.isSignedIn && session.profile != null;
});

/// The profile's rating and comment of a movie or TV show (null: not rated).
final titleRatingProvider = FutureProvider.autoDispose.family<MyRating?, RatingTarget>((ref, target) async {
  final profileId = _profileId(ref);
  if (!ref.watch(canRateProvider) || profileId == null) return null;
  return ref.read(tmdbRepositoryProvider).rating(profileId, target);
});

/// The profile's ratings of a season's episodes, by episode number.
final seasonRatingsProvider = FutureProvider.autoDispose.family<Map<int, MyRating>, (int, int)>((ref, key) async {
  final profileId = _profileId(ref);
  if (!ref.watch(canRateProvider) || profileId == null) return const {};
  return ref.read(tmdbRepositoryProvider).seasonRatings(profileId, key.$1, key.$2);
});

/// The profile's rating of a movie, a TV show or an episode (the API answers one episode with its
/// season: one request, shared with the episode cards).
final myRatingProvider = FutureProvider.autoDispose.family<MyRating?, RatingTarget>((ref, target) async {
  if (target.isEpisode) {
    final season = await ref.watch(seasonRatingsProvider((target.id, target.season!)).future);
    return season[target.episode];
  }
  return ref.watch(titleRatingProvider(target).future);
});

/// Rates, updates or removes a rating (and its comment), then refreshes what shows it (title
/// page, episodes, "Mes avis"). A new review marks its title or episode watched on the API
/// (developer's request, 23/11/2026): the library is read again so « Vu » shows at once.
final tmdbRatingsProvider = Provider<TmdbRatings>(TmdbRatings.new);

class TmdbRatings {
  TmdbRatings(this._ref);

  final Ref _ref;

  Future<void> rate(RatingTarget target, MyRating rating) => _write(target, rating);

  Future<void> remove(RatingTarget target) => _write(target, null);

  Future<void> _write(RatingTarget target, MyRating? rating) async {
    final profileId = _profileId(_ref);
    if (profileId == null) return;
    final repository = _ref.read(tmdbRepositoryProvider);
    rating == null ? await repository.unrate(profileId, target) : await repository.rate(profileId, target, rating);
    if (target.isEpisode) {
      _ref.invalidate(seasonRatingsProvider((target.id, target.season!)));
    } else {
      _ref.invalidate(titleRatingProvider(target));
    }
    // « Mes avis » and the profile page: read again (the pages they show).
    _ref.invalidate(myReviewsProvider);
    if (rating != null && _ref.exists(libraryProvider)) {
      // In the background: a failed read changes nothing to the saved review.
      unawaited(_ref.read(libraryProvider.notifier).refresh().catchError((Object _) {}));
    }
  }
}

/// The orders of « Mes avis » the API applies (`sort`): the most recent first, the oldest first,
/// the best rated first, the worst rated first.
enum RatedOrder { recent, oldest, highest, lowest }

/// A page of « Mes avis » (type, order, page).
typedef MyReviewsPage = ({RatedType? type, RatedOrder order, int page});

/// A page of the profile's reviews (« Mes avis », the profile page): 20 at a time, the next ones as
/// the page scrolls.
final myReviewsProvider = FutureProvider.autoDispose.family<Paged<RatedItem>, MyReviewsPage>((ref, key) async {
  final profileId = ref.watch(sessionProvider.select((s) => s.profile?.id));
  if (profileId == null || !ref.watch(canRateProvider)) return const Paged(items: []);
  return ref.read(tmdbRepositoryProvider).reviews(profileId, type: key.type, order: key.order, page: key.page);
});
