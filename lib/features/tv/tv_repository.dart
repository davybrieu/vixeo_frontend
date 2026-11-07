import '../auth/session.dart';
import '../../core/api/api_client.dart';
import 'models.dart';

class TvRepository {
  TvRepository(this._api);

  final ApiClient _api;

  Future<List<TvCategory>> categories() async {
    final json = await _api.getJson('/tv/categories');
    final data = json['data'];
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => TvCategory.fromJson(Map<String, dynamic>.from(e)))
        .where((c) => c.id.isNotEmpty)
        .toList();
  }

  Future<List<TvChannel>> channels({String? categoryId, String? query}) async {
    final params = <String, String>{};
    if (categoryId != null && categoryId.isNotEmpty) params['category_id'] = categoryId;
    if (query != null && query.trim().isNotEmpty) params['q'] = query.trim();
    final json = await _api.getJson('/tv/channels', query: params);
    final data = json['data'];
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => TvChannel.fromJson(Map<String, dynamic>.from(e)))
        .where((c) => c.id.isNotEmpty)
        .toList();
  }

  Future<TvStream> stream(String channelId) async {
    final json = await _api.getJson('/tv/channels/$channelId/stream');
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
  final api = ref.watch(apiClientProvider);
  return TvRepository(api);
});
