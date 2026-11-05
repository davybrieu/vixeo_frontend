import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../auth/session.dart';
import '../search/search_filters.dart';
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

  Future<PersonDetails> person(int id) async =>
      PersonDetails.fromJson((await _api.get('/catalog/person/$id'))['data'] as Map<String, dynamic>);

  /// Movies, TV shows and people at once. With filters or another order than relevance, the
  /// API filters and sorts the first results (and leaves people out when a filter is set).
  Future<SearchResults> search(String query, {SearchFilters filters = const SearchFilters()}) async =>
      SearchResults.fromJson(
        await _api.get('/catalog/search', query: {'query': query, ...filters.query(withText: true)}),
      );

  /// Movies or TV shows of one type: explore (`/discover`, without text) or search by text.
  Future<Paged<MediaItem>> titles(TitleQuery q) async {
    final params = {...q.filters.query(withText: q.query != null), 'page': q.page};
    final json = q.query == null
        ? await _api.get('/catalog/${q.type.name}/discover', query: params)
        : await _api.get('/catalog/search/${q.type.name}', query: {'query': q.query, ...params});
    return Paged.fromJson(json, MediaItem.fromJson);
  }

  Future<Paged<Person>> people(String query, {int page = 1}) async =>
      Paged.fromJson(await _api.get('/catalog/search/person', query: {'query': query, 'page': page}), Person.fromJson);

  Future<Map<MediaType, List<Genre>>> allGenres() async {
    final json = await _api.get('/catalog/genres');
    List<Genre> of(MediaType type) {
      final list = json[type.name];
      return list is List ? list.whereType<Map<String, dynamic>>().map(Genre.fromJson).toList() : [];
    }

    return {for (final type in MediaType.values) type: of(type)};
  }

  Future<List<Genre>> genres(MediaType type) async => (await allGenres())[type] ?? const [];
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

final personProvider = FutureProvider.autoDispose.family<PersonDetails, int>((ref, id) {
  ref.watch(_profileIdProvider);
  return ref.read(catalogRepositoryProvider).person(id);
});

final searchProvider = FutureProvider.autoDispose.family<SearchResults, (String, SearchFilters)>((ref, key) {
  ref.watch(_profileIdProvider);
  return ref.read(catalogRepositoryProvider).search(key.$1, filters: key.$2);
});

/// One page of movies or TV shows of the search page (explore or search by type).
final titlesProvider = FutureProvider.autoDispose.family<Paged<MediaItem>, TitleQuery>((ref, query) {
  ref.watch(_profileIdProvider);
  return ref.read(catalogRepositoryProvider).titles(query);
});

/// One page of people matching a text.
final peopleProvider = FutureProvider.autoDispose.family<Paged<Person>, (String, int)>(
  (ref, key) => ref.read(catalogRepositoryProvider).people(key.$1, page: key.$2),
);

/// Movie and TV genres (one request for both).
final allGenresProvider = FutureProvider.autoDispose<Map<MediaType, List<Genre>>>(
  (ref) => ref.read(catalogRepositoryProvider).allGenres(),
);

final genresProvider = FutureProvider.autoDispose.family<List<Genre>, MediaType>(
  (ref, type) async => (await ref.watch(allGenresProvider.future))[type] ?? const [],
);
