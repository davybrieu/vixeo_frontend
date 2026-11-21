import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../auth/session.dart';
import '../catalog/models.dart';
import '../tmdb/tmdb.dart';
import 'social_links.dart';

/// Where the active profile stands with a member: not following, a request waiting for a private
/// account to accept it, or following (`follow_status`, vixeo_backend/docs/social.md).
enum FollowStatus {
  none,
  requested,
  following;

  static FollowStatus parse(Object? value, {bool following = false}) => switch (value) {
    'requested' => requested,
    'following' => FollowStatus.following,
    'none' => none,
    // An older API: only `is_following`.
    _ => following ? FollowStatus.following : none,
  };
}

class SocialProfile {
  const SocialProfile({
    required this.id, required this.username, required this.name,
    this.avatar, this.bio, this.followersCount = 0, this.followingCount = 0,
    this.isFollowing = false, this.isSelf = false,
    this.reviewsCount = 0, this.watchedCount = 0, this.listCount = 0, this.shareUrl,
    this.isPrivate = false, FollowStatus? followStatus, this.canView = true, this.socialLinks = const [],
    this.requestedAt,
  }) : _followStatus = followStatus;

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
    shareUrl: json['share_url'] as String?,
    isPrivate: json['is_private'] as bool? ?? false,
    followStatus: FollowStatus.parse(json['follow_status'], following: json['is_following'] as bool? ?? false),
    canView: json['can_view'] as bool? ?? true,
    socialLinks: SocialLink.listOf(json['social_links']),
    requestedAt: DateTime.tryParse(json['requested_at'] as String? ?? '')?.toLocal(),
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

  /// The profile's page on the site (`www.vixeo.app/pseudo`), sent by « Partager ».
  final String? shareUrl;

  /// A private account (like Twitter): its lists, reviews, followers and followings are seen by
  /// its accepted followers only ([canView]).
  final bool isPrivate;

  final FollowStatus? _followStatus;

  /// Following, a request waiting, or neither.
  FollowStatus get followStatus => _followStatus ?? (isFollowing ? FollowStatus.following : FollowStatus.none);

  /// The active profile sees the lists and the reviews: a public account, itself, or an accepted
  /// follower.
  final bool canView;

  /// Its accounts on social networks, in the order of the page.
  final List<SocialLink> socialLinks;

  /// When a follow request was sent (`GET /social/requests`).
  final DateTime? requestedAt;
}

/// What a like of a review leaves: liked or not, and its number of likes.
typedef ReviewLikeState = ({bool liked, int likesCount});

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

  /// A member's « Favoris » ❤ (movies and series), the most recently added first.
  Future<List<MediaItem>> liked(String username) async {
    final json = await _api.get('/social/profiles/${Uri.encodeComponent(username)}/liked');
    return [
      for (final item in (json['data'] as List).whereType<Map<String, dynamic>>()) ?titleOf(item),
    ];
  }

  /// The people (actors, directors…) a member follows, the most recently followed first.
  Future<List<Person>> people(String username) async {
    final json = await _api.get('/social/profiles/${Uri.encodeComponent(username)}/people');
    return (json['data'] as List).whereType<Map<String, dynamic>>().map(Person.fromJson).toList();
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

  /// Follows a member: at once for a public account, a request for a private one.
  Future<FollowStatus> follow(String username) async {
    final json = await _api.post('/social/profiles/${Uri.encodeComponent(username)}/follow');
    return FollowStatus.parse(json['follow_status'], following: json['following'] as bool? ?? true);
  }

  /// Unfollows a member, or withdraws a request.
  Future<void> unfollow(String username) => _api.delete('/social/profiles/${Uri.encodeComponent(username)}/follow');

  /// The follow requests waiting for the active profile (a private account), the most recent first.
  Future<List<SocialProfile>> requests() async {
    final json = await _api.get('/social/requests');
    return (json['data'] as List).whereType<Map<String, dynamic>>().map(SocialProfile.fromJson).toList();
  }

  Future<void> acceptRequest(String username) =>
      _api.post('/social/requests/${Uri.encodeComponent(username)}/accept');

  Future<void> declineRequest(String username) => _api.delete('/social/requests/${Uri.encodeComponent(username)}');

  /// Likes ([liked]) or unlikes another member's review.
  Future<ReviewLikeState> likeReview(int reviewId, {required bool liked}) async {
    final path = '/social/reviews/$reviewId/like';
    final json = liked ? await _api.put(path) : await _api.delete(path);
    return (liked: json['liked'] as bool? ?? liked, likesCount: json['likes_count'] as int? ?? 0);
  }
}

final socialRepositoryProvider = Provider<SocialRepository>((ref) => SocialRepository(ref.read(apiClientProvider)));

/// The public page of a profile (bio, followers, counters), by username. Invalidated when the
/// active profile edits its own.
final socialProfileProvider = FutureProvider.autoDispose.family<SocialProfile, String>(
  (ref, username) => ref.read(socialRepositoryProvider).profile(username),
);
/// Members whose @pseudo matches a text. Never the active profile itself (developer's request):
/// one's own profile is opened from the navigation (« Profil »). The API leaves it out too.
final socialSearchProvider = FutureProvider.autoDispose.family<List<SocialProfile>, String>((ref, query) async {
  final activeProfile = ref.watch(sessionProvider.select((s) => s.profile));
  if (activeProfile?.isKid == true) return const <SocialProfile>[];
  if (query.trim().length < 2) return const <SocialProfile>[];
  final found = await ref.read(socialRepositoryProvider).search(query);
  final me = activeProfile?.username?.toLowerCase();
  return [
    for (final profile in found)
      if (profile.id != activeProfile?.id && (me == null || profile.username.toLowerCase() != me)) profile,
  ];
});

/// A member's list (movies and series), by username.
final socialTitlesProvider = FutureProvider.autoDispose.family<List<MediaItem>, String>(
  (ref, username) => ref.read(socialRepositoryProvider).titles(username),
);

/// A member's « Favoris » ❤ (movies and series), by username.
final socialLikedProvider = FutureProvider.autoDispose.family<List<MediaItem>, String>(
  (ref, username) => ref.read(socialRepositoryProvider).liked(username),
);

/// The people a member follows, by username.
final socialPeopleProvider = FutureProvider.autoDispose.family<List<Person>, String>(
  (ref, username) => ref.read(socialRepositoryProvider).people(username),
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
