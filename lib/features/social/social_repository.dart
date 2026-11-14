import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../auth/session.dart';

class SocialProfile {
  const SocialProfile({
    required this.id, required this.username, required this.name,
    this.avatar, this.bio, this.followersCount = 0, this.followingCount = 0,
    this.isFollowing = false, this.isSelf = false,
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

  Future<List<Map<String, dynamic>>> collection(String username, String section) async {
    final json = await _api.get('/social/profiles/${Uri.encodeComponent(username)}/$section');
    return (json['data'] as List).whereType<Map<String, dynamic>>().toList();
  }

  Future<void> follow(String username) => _api.post('/social/profiles/${Uri.encodeComponent(username)}/follow');
  Future<void> unfollow(String username) => _api.delete('/social/profiles/${Uri.encodeComponent(username)}/follow');
}

final socialRepositoryProvider = Provider<SocialRepository>((ref) => SocialRepository(ref.read(apiClientProvider)));
final socialSearchProvider = FutureProvider.autoDispose.family<List<SocialProfile>, String>((ref, query) {
  ref.watch(sessionProvider.select((s) => s.profile?.id));
  return ref.read(socialRepositoryProvider).search(query);
});
