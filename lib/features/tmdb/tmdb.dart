import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../auth/session.dart';
import '../catalog/models.dart';

// The active profile's reviews: a rating and an optional comment per movie or TV show
// (vixeo_backend/docs/avis.md). Kept by Vixeo only: no TMDb account is linked any more, and
// episodes are not rated (developer's request, 20/11/2026).

/// What a profile rates: the type filter of « Mes avis ».
enum RatedType {
  movie('Films'),
  tv('Séries');

  const RatedType(this.label);

  final String label;
}

/// A reviewed movie or TV show.
@immutable
class RatingTarget {
  const RatingTarget.title(this.type, this.id);

  final MediaType type;
  final int id;

  RatedType get ratedType => type == MediaType.movie ? RatedType.movie : RatedType.tv;

  /// Path under `/profiles/{id}/tmdb/ratings/`.
  String get path => '${type.name}/$id';

  @override
  bool operator ==(Object other) => other is RatingTarget && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

/// The profile's rating of a title and its comment.
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
    this.posterUrl,
    this.backdropUrl,
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
    posterUrl: json['poster_url'] as String?,
    backdropUrl: json['backdrop_url'] as String?,
    voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0,
  );

  final RatedType type;

  /// Movie or TV show (the page to open).
  final int id;
  final String title;

  /// The profile's rating, 0.5 to 10.
  final double value;

  /// The profile's comment.
  final String? comment;

  /// When it was rated.
  final DateTime? ratedAt;
  final int? year;
  final String? posterUrl;
  final String? backdropUrl;
  final double voteAverage;

  MediaType get mediaType => type == RatedType.movie ? MediaType.movie : MediaType.tv;

  RatingTarget get target => RatingTarget.title(mediaType, id);

  MyRating get rating => MyRating(value, comment: comment);

  /// "Film · 2021", "Série"…
  String get subtitle => [type == RatedType.movie ? 'Film' : 'Série', if (year != null) '$year'].join(' · ');

  /// "Dune".
  String get label => title;

  /// Matches a search of "Mes avis": title or comment, whatever the case and accents.
  bool matches(String query) {
    final q = foldForSearch(query.trim());
    if (q.isEmpty) return true;
    return [title, comment].any((text) => text != null && foldForSearch(text).contains(q));
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
    posterUrl: posterUrl,
    backdropUrl: backdropUrl,
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

/// `/profiles/{id}/tmdb/ratings…` of the Vixeo API (historical name: the reviews are Vixeo's).
class TmdbRepository {
  TmdbRepository(this._api);

  final ApiClient _api;

  /// Rating and comment of a movie or TV show, null when not rated.
  Future<MyRating?> rating(int profileId, RatingTarget target) async {
    final data = (await _api.get('/profiles/$profileId/tmdb/ratings/${target.path}'))['data'];
    return data is Map<String, dynamic> && data['value'] != null ? MyRating.fromJson(data) : null;
  }

  /// Saves the rating and the comment (null removes it).
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

/// Rates, updates or removes a rating (and its comment), then refreshes what shows it (title
/// page, "Mes avis").
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
    _ref.invalidate(titleRatingProvider(target));
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
