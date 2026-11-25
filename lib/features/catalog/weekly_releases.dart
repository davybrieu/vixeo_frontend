import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../auth/session.dart';

/// Normalized movie, first-air TV show or episode from the releases endpoint.
class WeeklyRelease {
  const WeeklyRelease({
    required this.type,
    required this.tmdbId,
    required this.title,
    required this.releaseDate,
    this.posterUrl,
    this.releaseType,
    this.countryCode,
    this.overview,
    this.episodeName,
    this.seasonNumber,
    this.episodeNumber,
  });

  factory WeeklyRelease.fromJson(Map<String, dynamic> json) => WeeklyRelease(
    type: json['type'] as String? ?? 'movie',
    tmdbId: json['tmdb_id'] as int? ?? json['id'] as int? ?? 0,
    title: json['title'] as String? ?? 'Titre inconnu',
    releaseDate: DateTime.tryParse(json['release_date'] as String? ?? ''),
    posterUrl: json['poster_url'] as String?,
    releaseType: json['release_type'] as String?,
    countryCode: json['country_code'] as String?,
    overview: json['overview'] as String?,
    episodeName: json['episode_name'] as String?,
    seasonNumber: json['season_number'] as int?,
    episodeNumber: json['episode_number'] as int?,
  );

  final String type;
  final int tmdbId;
  final String title;
  final DateTime? releaseDate;
  final String? posterUrl;
  final String? releaseType;
  final String? countryCode;
  final String? overview;
  final String? episodeName;
  final int? seasonNumber;
  final int? episodeNumber;

  bool get isEpisode => type == 'episode';

  String get categoryLabel => switch (type) {
    'movie' => 'Film',
    'tv' => 'Nouvelle série',
    'episode' => 'Épisode',
    _ => 'Sortie',
  };

  String get episodeCode {
    final season = (seasonNumber ?? 0).toString().padLeft(2, '0');
    final episode = (episodeNumber ?? 0).toString().padLeft(2, '0');
    return 'S$season · E$episode';
  }

  String get navigationType => type == 'movie' ? 'movie' : 'tv';
}

class WeeklyReleasesRepository {
  WeeklyReleasesRepository(this._api);

  final ApiClient _api;

  Future<List<WeeklyRelease>> fetch({
    required DateTime from,
    required DateTime to,
    required String type,
  }) async {
    String date(DateTime value) =>
        '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

    final response = await _api.get('/catalog/releases', query: {
      'from': date(from),
      'to': date(to),
      'type': type,
    });
    final data = response['data'];
    if (data is! List) return const [];
    return data.whereType<Map<String, dynamic>>().map(WeeklyRelease.fromJson).toList();
  }
}

final weeklyReleasesRepositoryProvider = Provider<WeeklyReleasesRepository>(
  (ref) => WeeklyReleasesRepository(ref.read(apiClientProvider)),
);

final weeklyReleasesProvider = FutureProvider.autoDispose.family<
    List<WeeklyRelease>,
    ({DateTime from, DateTime to, String type})>((ref, range) {
  ref.watch(sessionProvider.select((session) => session.profile?.id));
  return ref.read(weeklyReleasesRepositoryProvider).fetch(
    from: range.from,
    to: range.to,
    type: range.type,
  );
});
