import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../auth/session.dart';
import '../catalog/models.dart';
import '../tmdb/tmdb.dart';

class SocialProfile {
  const SocialProfile({
    required this.id, required this.username, required this.name,
    this.avatar, this.bio, this.followersCount = 0, this.followingCount = 0,
    this.isFollowing = false, this.isSelf = false,
    this.reviewsCount = 0, this.watchedCount = 0, this.listCount = 0,
  });

  factory SocialProfile.fromJson(Map<String, dynamic> json) => SocialProfile(
    id: json['id'] as int,
    username: json['username'] as String? ?? '',
    name: json['name'] as String? ?? '',
    avatar: json['avatar'] as String?,
    bio: json['bio'] as String?,
    followersCount: json['followers_count'] as int? ?? 0,
    followingCount: json['following_count'] as int? ?? 0,
    isFollowing: json['is_following'] as bool? ?? false,
    isSelf: json['is_self'] as bool? ?? false,
    reviewsCount: json['reviews_count'] as int? ?? 0,
    watchedCount: json['watched_count'] as int? ?? 0,
    listCount: json['list_count'] as int? ?? 0,
  );

  final int id;
  final String username;
  final String name;
  final String? avatar;
  final String? bio;
  final int followersCount;
  final int followingCount;
  final bool isFollowing;
  final bool isSelf;
  final int reviewsCount;
  final int watchedCount;
  final int listCount;
}

class SocialRepository {
  SocialRepository(this._api);
  final ApiClient _api;

  Future<List<SocialProfile>> search(String query) async {
    final json = await _api.get('/social/search', query: {'query': query});
    return (json['data'] as List).whereType<Map<String, dynamic>>().map(SocialProfile.fromJson).toList();
  }

  Future<SocialProfile> profile(String username) async {
    final json = await _api.get('/social/profiles/${Uri.encodeComponent(username)}');
    return SocialProfile.fromJson(json['data'] as Map<String, dynamic>);
  }

  Future<SocialProfile> update({String? username, String? bio}) async {
    final json = await _api.patch('/social/profile', body: {
      if (username != null) 'username': username,
      if (bio != null) 'bio': bio,
    });
    return SocialProfile.fromJson(json['data'] as Map<String, dynamic>);
  }

  /// The movies and series of a member's list, the most recently added first.
  Future<List<MediaItem>> titles(String username) async {
    final json = await _api.get('/social/profiles/${Uri.encodeComponent(username)}/list');
    return [
      for (final item in (json['data'] as List).whereType<Map<String, dynamic>>()) ?titleOf(item),
    ];
  }

  /// A title of a member's list (`{type, item_id: "movie:550", title, year, poster_url}`), or null
  /// for what is not a movie or a series (a channel…).
  static MediaItem? titleOf(Map<String, dynamic> json) {
    final type = json['type'];
    if (type != 'movie' && type != 'tv') return null;
    final id = int.tryParse((json['item_id'] as String? ?? '').split(':').last);
    if (id == null) return null;
    return MediaItem(
      id: id,
      type: MediaType.parse(type),
      title: json['title'] as String? ?? '',
      year: json['year'] as int?,
      posterUrl: json['poster_url'] as String?,
    );
  }

  /// A member's reviews, the most recently rated first (the fields of « Mes avis »).
  Future<List<RatedItem>> reviews(String username) async {
    final json = await _api.get('/social/profiles/${Uri.encodeComponent(username)}/reviews');
    return (json['data'] as List).whereType<Map<String, dynamic>>().map(RatedItem.fromJson).toList();
  }

  /// The profiles following a member ([followers]), or followed by them.
  Future<List<SocialProfile>> connections(String username, {required bool followers}) async {
    final json = await _api.get(
      '/social/profiles/${Uri.encodeComponent(username)}/${followers ? 'followers' : 'following'}',
    );
    return (json['data'] as List).whereType<Map<String, dynamic>>().map(SocialProfile.fromJson).toList();
  }

  Future<List<Map<String, dynamic>>> collection(String username, String section) async {
    final json = await _api.get('/social/profiles/${Uri.encodeComponent(username)}/$section');
    return (json['data'] as List).whereType<Map<String, dynamic>>().toList();
  }

  Future<void> follow(String username) => _api.post('/social/profiles/${Uri.encodeComponent(username)}/follow');
  Future<void> unfollow(String username) => _api.delete('/social/profiles/${Uri.encodeComponent(username)}/follow');
}

final socialRepositoryProvider = Provider<SocialRepository>((ref) => SocialRepository(ref.read(apiClientProvider)));

/// The public page of a profile (bio, followers, counters), by username. Invalidated when the
/// active profile edits its own.
final socialProfileProvider = FutureProvider.autoDispose.family<SocialProfile, String>(
  (ref, username) => ref.read(socialRepositoryProvider).profile(username),
);
final socialSearchProvider = FutureProvider.autoDispose.family<List<SocialProfile>, String>((ref, query) {
  final activeProfile = ref.watch(sessionProvider.select((s) => s.profile));
  if (activeProfile?.isKid == true) return Future.value(const <SocialProfile>[]);
  if (query.trim().length < 2) return Future.value(const <SocialProfile>[]);
  return ref.read(socialRepositoryProvider).search(query);
});

/// A member's list (movies and series), by username.
final socialTitlesProvider = FutureProvider.autoDispose.family<List<MediaItem>, String>(
  (ref, username) => ref.read(socialRepositoryProvider).titles(username),
);

/// A member's reviews, by username.
final socialReviewsProvider = FutureProvider.autoDispose.family<List<RatedItem>, String>(
  (ref, username) => ref.read(socialRepositoryProvider).reviews(username),
);

/// The followers (`followers: true`) or the followed profiles of a member.
final socialConnectionsProvider =
    FutureProvider.autoDispose.family<List<SocialProfile>, ({String username, bool followers})>(
      (ref, key) => ref.read(socialRepositoryProvider).connections(key.username, followers: key.followers),
    );
