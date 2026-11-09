import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../auth/session.dart';
import '../catalog/models.dart';

// TMDb account of the active profile and its ratings (vixeo_backend/docs/compte-tmdb.md). The
// ratings live on TMDb: the same on every device, every profile linked to that account and
// themoviedb.org. The app only talks to the Vixeo API.

/// TMDb account linked to the profile (API `TmdbAccountResource`).
@immutable
class TmdbAccount {
  const TmdbAccount({required this.linked, this.accountId, this.username, this.name, this.avatarUrl, this.linkedAt});

  factory TmdbAccount.fromJson(Map<String, dynamic> json) => TmdbAccount(
    linked: json['linked'] as bool? ?? false,
    accountId: json['account_id'] as int?,
    username: json['username'] as String?,
    name: json['name'] as String?,
    avatarUrl: json['avatar_url'] as String?,
    linkedAt: DateTime.tryParse(json['linked_at'] as String? ?? '')?.toLocal(),
  );

  static const none = TmdbAccount(linked: false);

  final bool linked;
  final int? accountId;
  final String? username;
  final String? name;
  final String? avatarUrl;
  final DateTime? linkedAt;

  /// Name shown on TMDb, else the username.
  String get displayName => (name?.trim().isNotEmpty ?? false) ? name!.trim() : (username ?? '');
}

/// TMDb page where the person approves Vixeo, and how often to ask whether they did.
@immutable
class TmdbLinkStart {
  const TmdbLinkStart({required this.authorizeUrl, required this.expiresIn, required this.interval});

  factory TmdbLinkStart.fromJson(Map<String, dynamic> json) => TmdbLinkStart(
    authorizeUrl: json['authorize_url'] as String,
    expiresIn: Duration(seconds: json['expires_in'] as int? ?? 3600),
    interval: Duration(seconds: json['interval'] as int? ?? 5),
  );

  final String authorizeUrl;
  final Duration expiresIn;
  final Duration interval;
}

/// What a profile rates: tabs of "Mes notes".
enum RatedType {
  movie('Films'),
  tv('Séries'),
  episode('Épisodes');

  const RatedType(this.label);

  final String label;
}

/// A movie, a TV show or an episode, as TMDb rates it.
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

/// The profile's rating of a title and its comment (kept by Vixeo only, never sent to TMDb).
@immutable
class MyRating {
  const MyRating(this.value, {this.comment});

  factory MyRating.fromJson(Map<String, dynamic> json) => MyRating(
    (json['value'] as num).toDouble(),
    comment: (json['comment'] as String?)?.trim().isEmpty ?? true ? null : json['comment'] as String,
  );

  /// 0.5 to 10.
  final double value;
  final String? comment;

  @override
  bool operator ==(Object other) => other is MyRating && other.value == value && other.comment == comment;

  @override
  int get hashCode => Object.hash(value, comment);
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
  );

  final RatedType type;

  /// Movie or TV show (the page to open), also for an episode.
  final int id;
  final String title;

  /// The profile's rating, 0.5 to 10.
  final double value;

  /// The profile's comment (Vixeo only).
  final String? comment;

  /// When it was rated (first seen by Vixeo for a rating given on themoviedb.org).
  final DateTime? ratedAt;
  final int? year;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? episodeName;
  final String? posterUrl;
  final String? backdropUrl;
  final String? stillUrl;
  final double voteAverage;

  MediaType get mediaType => type == RatedType.movie ? MediaType.movie : MediaType.tv;

  RatingTarget get target => type == RatedType.episode
      ? RatingTarget.episode(id, seasonNumber ?? 0, episodeNumber ?? 0)
      : RatingTarget.title(mediaType, id);

  MyRating get rating => MyRating(value, comment: comment);

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

/// `/profiles/{id}/tmdb…` of the Vixeo API.
class TmdbRepository {
  TmdbRepository(this._api);

  final ApiClient _api;

  Future<TmdbAccount> account(int profileId) async =>
      TmdbAccount.fromJson((await _api.get('/profiles/$profileId/tmdb'))['data'] as Map<String, dynamic>);

  Future<TmdbLinkStart> startLink(int profileId) async =>
      TmdbLinkStart.fromJson(await _api.post('/profiles/$profileId/tmdb/link'));

  /// The account once the person approved Vixeo on TMDb, null until then. Throws an
  /// [ApiException] with status 410 when the approval page expired.
  Future<TmdbAccount?> completeLink(int profileId) async {
    final json = await _api.post('/profiles/$profileId/tmdb/link/complete');
    return json['status'] == 'linked' ? TmdbAccount.fromJson(json['data'] as Map<String, dynamic>) : null;
  }

  Future<void> unlink(int profileId) => _api.delete('/profiles/$profileId/tmdb');

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

  /// Saves the rating on TMDb and the comment at Vixeo (null removes it).
  Future<void> rate(int profileId, RatingTarget target, MyRating rating) => _api.put(
    '/profiles/$profileId/tmdb/ratings/${target.path}',
    body: {'value': rating.value, 'comment': rating.comment},
  );

  Future<void> unrate(int profileId, RatingTarget target) =>
      _api.delete('/profiles/$profileId/tmdb/ratings/${target.path}');

  /// Every review of the profile, the most recently rated first.
  Future<List<RatedItem>> reviews(int profileId) async {
    final items = <RatedItem>[];
    var page = 1;
    while (true) {
      final result = Paged.fromJson(
        await _api.get('/profiles/$profileId/tmdb/ratings', query: {'per_page': 500, 'page': page}),
        RatedItem.fromJson,
      );
      items.addAll(result.items);
      if (!result.hasMore || page >= 20) return items;
      page++;
    }
  }
}

final tmdbRepositoryProvider = Provider<TmdbRepository>((ref) => TmdbRepository(ref.read(apiClientProvider)));

int? _profileId(Ref ref) => ref.read(sessionProvider).profile?.id;

/// TMDb account of the active profile (changing profile reloads it).
final tmdbAccountProvider = AsyncNotifierProvider<TmdbAccountController, TmdbAccount>(TmdbAccountController.new);

class TmdbAccountController extends AsyncNotifier<TmdbAccount> {
  @override
  Future<TmdbAccount> build() async {
    final profileId = ref.watch(sessionProvider.select((s) => s.profile?.id));
    if (profileId == null) return TmdbAccount.none;
    return ref.read(tmdbRepositoryProvider).account(profileId);
  }

  /// Linked from the "Connexions" page.
  void linked(TmdbAccount account) {
    state = AsyncData(account);
    ref.invalidate(reviewsProvider);
  }

  Future<void> unlink() async {
    final profileId = _profileId(ref);
    if (profileId == null) return;
    await ref.read(tmdbRepositoryProvider).unlink(profileId);
    state = const AsyncData(TmdbAccount.none);
    ref.invalidate(reviewsProvider);
  }

  /// The API answered 409: no account linked any more (access removed on TMDb…).
  void lost() => state = const AsyncData(TmdbAccount.none);
}

/// The profile can rate: a TMDb account is linked.
final canRateProvider = Provider<bool>((ref) => ref.watch(tmdbAccountProvider).value?.linked ?? false);

/// The profile's rating and comment of a movie or TV show (null: not rated, or no account).
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

/// Rates, updates or removes a rating (and its comment), then refreshes what shows it (title
/// page, episodes, "Mes avis").
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
    try {
      rating == null ? await repository.unrate(profileId, target) : await repository.rate(profileId, target, rating);
    } on ApiException catch (e) {
      if (e.status == 409) _ref.read(tmdbAccountProvider.notifier).lost();
      rethrow;
    }
    if (target.isEpisode) {
      _ref.invalidate(seasonRatingsProvider((target.id, target.season!)));
    } else {
      _ref.invalidate(titleRatingProvider(target));
    }
    if (_ref.exists(reviewsProvider)) _ref.read(reviewsProvider.notifier).changed(target, rating);
  }
}

/// Every review of the profile ("Mes avis"), the most recently rated first. Loaded at once: the
/// page filters and searches them without asking the API again.
final reviewsProvider = AsyncNotifierProvider.autoDispose<Reviews, List<RatedItem>>(Reviews.new);

class Reviews extends AsyncNotifier<List<RatedItem>> {
  @override
  Future<List<RatedItem>> build() async {
    final profileId = ref.watch(sessionProvider.select((s) => s.profile?.id));
    if (profileId == null || !ref.watch(canRateProvider)) return const [];
    return ref.read(tmdbRepositoryProvider).reviews(profileId);
  }

  /// A rating changed (here or on a title page): moved on top, updated, removed, or (new
  /// rating) the list is read again.
  void changed(RatingTarget target, MyRating? rating) {
    final current = state.value;
    if (current == null) return;
    final index = current.indexWhere((i) => i.target == target);
    if (index < 0) {
      if (rating != null) ref.invalidateSelf();
      return;
    }
    final items = [...current];
    final item = items.removeAt(index);
    if (rating != null) {
      final updated = item.rated(rating);
      items.insert(updated.ratedAt == item.ratedAt ? index : 0, updated);
    }
    state = AsyncData(items);
  }
}
