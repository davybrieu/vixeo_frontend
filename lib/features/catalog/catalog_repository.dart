import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../auth/session.dart';
import 'models.dart';

/// `/catalog/*` endpoints (TMDb metadata, cached and age-filtered by the API).
class CatalogRepository {
  CatalogRepository(this._api);

  final ApiClient _api;

  Future<Home> home({MediaType? type}) async =>
      Home.fromJson(await _api.get('/catalog/home', query: {'type': type?.name}));

  Future<TitleDetails> movie(int id) async =>
      TitleDetails.fromJson((await _api.get('/catalog/movie/$id'))['data'] as Map<String, dynamic>);

  Future<TitleDetails> show(int id) async =>
      TitleDetails.fromJson((await _api.get('/catalog/tv/$id'))['data'] as Map<String, dynamic>);

  Future<Season> season(int showId, int number) async =>
      Season.fromJson((await _api.get('/catalog/tv/$showId/season/$number'))['data'] as Map<String, dynamic>);

  Future<SearchResults> search(String query) async =>
      SearchResults.fromJson(await _api.get('/catalog/search', query: {'query': query}));

  Future<List<Genre>> genres(MediaType type) async {
    final json = await _api.get('/catalog/genres');
    final list = json[type.name];
    return list is List ? list.whereType<Map<String, dynamic>>().map(Genre.fromJson).toList() : [];
  }

  Future<List<MediaItem>> discover(MediaType type, {int? genre, int page = 1}) async {
    final json = await _api.get('/catalog/${type.name}/discover', query: {'genre': genre, 'page': page});
    return (json['data'] as List).whereType<Map<String, dynamic>>().map(MediaItem.fromJson).toList();
  }
}

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) => CatalogRepository(ref.read(apiClientProvider)));

/// Active profile id: catalog providers watch it so a profile switch refetches
/// (the API filters titles with the profile's age limit).
final _profileIdProvider = Provider<int?>((ref) => ref.watch(sessionProvider.select((s) => s.profile?.id)));

final homeProvider = FutureProvider.autoDispose.family<Home, MediaType?>((ref, type) {
  ref.watch(_profileIdProvider);
  return ref.read(catalogRepositoryProvider).home(type: type);
});

final titleProvider = FutureProvider.autoDispose.family<TitleDetails, (MediaType, int)>((ref, key) {
  ref.watch(_profileIdProvider);
  final repo = ref.read(catalogRepositoryProvider);
  return key.$1 == MediaType.movie ? repo.movie(key.$2) : repo.show(key.$2);
});

final seasonProvider = FutureProvider.autoDispose.family<Season, (int, int)>((ref, key) {
  ref.watch(_profileIdProvider);
  return ref.read(catalogRepositoryProvider).season(key.$1, key.$2);
});

final searchProvider = FutureProvider.autoDispose.family<SearchResults, String>((ref, query) {
  ref.watch(_profileIdProvider);
  return ref.read(catalogRepositoryProvider).search(query);
});

final genresProvider = FutureProvider.autoDispose.family<List<Genre>, MediaType>(
  (ref, type) => ref.read(catalogRepositoryProvider).genres(type),
);

final discoverProvider = FutureProvider.autoDispose.family<List<MediaItem>, (MediaType, int)>((ref, key) {
  ref.watch(_profileIdProvider);
  return ref.read(catalogRepositoryProvider).discover(key.$1, genre: key.$2);
});
