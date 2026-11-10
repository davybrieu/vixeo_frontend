import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../auth/session.dart';
import 'models.dart';

class TvRepository {
  TvRepository(this._api);

  final ApiClient _api;

  Future<List<TvCategory>> categories() async {
    final json = await _api.get('/tv/categories');
    final data = json['data'];
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => TvCategory.fromJson(Map<String, dynamic>.from(e)))
        .where((c) => c.id.isNotEmpty)
        .toList();
  }

  Future<List<TvChannel>> channels({String? categoryId, String? query}) async {
    final params = <String, dynamic>{};
    if (categoryId != null && categoryId.isNotEmpty) params['category_id'] = categoryId;
    if (query != null && query.trim().isNotEmpty) params['q'] = query.trim();
    final json = await _api.get('/tv/channels', query: params.isEmpty ? null : params);
    final data = json['data'];
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => TvChannel.fromJson(Map<String, dynamic>.from(e)))
        .where((c) => c.id.isNotEmpty)
        .toList();
  }

  /// One channel (its page).
  Future<TvChannel> channel(String channelId) async {
    final json = await _api.get('/tv/channels/${Uri.encodeComponent(channelId)}');
    final data = json['data'];
    if (data is! Map) throw ApiException('Chaîne introuvable.');
    return TvChannel.fromJson(Map<String, dynamic>.from(data));
  }

  /// The channel's programme guide, from the programme on now.
  Future<TvGuide> guide(String channelId) async =>
      TvGuide.fromJson(await _api.get('/tv/channels/${Uri.encodeComponent(channelId)}/epg'));

  Future<TvStream> stream(String channelId) async {
    final json = await _api.get('/tv/channels/$channelId/stream');
    final data = json['data'];
    if (data is! Map) {
      throw ApiException('Flux indisponible.');
    }
    final stream = TvStream.fromJson(Map<String, dynamic>.from(data));
    if (stream.url.isEmpty) throw ApiException('Flux indisponible.');
    return stream;
  }
}

final tvRepositoryProvider = Provider<TvRepository>((ref) {
  return TvRepository(ref.watch(apiClientProvider));
});

/// Categories of the live channels: the « Catégorie » filter of the search page.
final tvCategoriesProvider = FutureProvider.autoDispose<List<TvCategory>>((ref) {
  return ref.watch(tvRepositoryProvider).categories();
});

/// One channel, for its page.
final tvChannelProvider = FutureProvider.autoDispose.family<TvChannel, String>((ref, id) {
  return ref.watch(tvRepositoryProvider).channel(id);
});

/// A channel's programme guide.
final tvGuideProvider = FutureProvider.autoDispose.family<TvGuide, String>((ref, id) {
  return ref.watch(tvRepositoryProvider).guide(id);
});
