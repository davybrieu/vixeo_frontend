import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../auth/session.dart';
import '../search/search_filters.dart';
import 'models.dart';

/// `/catalog/*` endpoints (TMDb metadata, cached and age-filtered by the API).
class CatalogRepository {
  CatalogRepository(this._api);

  final ApiClient _api;

  Future<Home> home() async => Home.fromJson(await _api.get('/catalog/home'));

  /// One page of a home list ("Voir tout" of a row): `trending`, `popular`, `top_rated`…
  Future<Paged<MediaItem>> list(MediaType type, String list, {int page = 1}) async => Paged.fromJson(
    await _api.get('/catalog/${type.name}/lists/${Uri.encodeComponent(list)}', query: {'page': page}),
    MediaItem.fromJson,
  );

  /// Additional ratings from MDBList; called only when the user opens the ratings modal.
  Future<Map<String, SiteRating>> externalRatings(MediaType type, int id) async {
    final json = await _api.get('/catalog/ratings', query: {'ids': '${type.name}:$id'});
    final rows = (json['data'] as List?)?.whereType<Map<String, dynamic>>() ?? const [];
    if (rows.isEmpty) return const {};
    final row = rows.first;
    const sources = {
      'trakt': 'trakt',
      'letterboxd': 'letterboxd',
      'tomatoes': 'tomatoes',
      'audience': 'audience',
      'metacritic': 'metacritic',
      'mal': 'mal',
    };
    final result = <String, SiteRating>{};
    for (final entry in sources.entries) {
      final value = row[entry.key];
      if (value is num && value > 0) result[entry.value] = SiteRating(value.toDouble(), 0);
    }
    return result;
  }

  Future<TitleDetails> movie(int id) async =>
      TitleDetails.fromJson((await _api.get('/catalog/movie/$id'))['data'] as Map<String, dynamic>);

  Future<TitleDetails> show(int id) async =>
      TitleDetails.fromJson((await _api.get('/catalog/tv/$id'))['data'] as Map<String, dynamic>);

  Future<Season> season(int showId, int number) async =>
      Season.fromJson((await _api.get('/catalog/tv/$showId/season/$number'))['data'] as Map<String, dynamic>);

  /// Several titles at once (Ma liste…), with their logo, length, genres and age rating, in the
  /// order asked: one request per 100 titles instead of one per title.
  Future<List<MediaItem>> titlesById(List<TitleRef> titles) async {
    final items = <MediaItem>[];
    for (var i = 0; i < titles.length; i += 100) {
      final ids = titles.skip(i).take(100).map((t) => '${t.type.name}:${t.id}').join(',');
      final data = (await _api.get('/catalog/titles', query: {'ids': ids}))['data'];
      if (data is List) items.addAll(data.whereType<Map<String, dynamic>>().map(MediaItem.fromJson));
    }
    return items;
  }

  Future<PersonDetails> person(int id) async =>
      PersonDetails.fromJson((await _api.get('/catalog/person/$id'))['data'] as Map<String, dynamic>);

  /// Every title of a person, each once: « Connu pour » or « Filmographie » → « Voir tout » (the
  /// person page only has their start).
  Future<List<MediaItem>> personCredits(int id, PersonCreditsSort sort) async {
    final json = await _api.get('/catalog/person/$id/credits', query: {'sort': sort.name});
    return (json['data'] as List).whereType<Map<String, dynamic>>().map(MediaItem.fromJson).toList();
  }

  /// One page of « Vous pourriez aussi aimer » (the title page has the first 20).
  Future<Paged<MediaItem>> recommendations(MediaType type, int id, {int page = 1}) async => Paged.fromJson(
    await _api.get('/catalog/${type.name}/$id/recommendations', query: {'page': page}),
    MediaItem.fromJson,
  );

  /// Everyone of « Créateur et distribution » (the title page has 20 cast members).
  Future<TitleCredits> credits(MediaType type, int id) async =>
      TitleCredits.fromJson((await _api.get('/catalog/${type.name}/$id/credits'))['data'] as Map<String, dynamic>);

  /// Movies, TV shows and people at once. With filters or another order than relevance, the
  /// API filters and sorts the first results (and leaves people out when a filter is set).
  /// An empty [query]: movies and TV shows matching the filters, without a text
  /// (`/catalog/discover`, no people).
  Future<SearchResults> search(String query, {SearchFilters filters = const SearchFilters()}) async =>
      SearchResults.fromJson(
        query.isEmpty
            ? await _api.get('/catalog/discover', query: filters.query(withText: false))
            : await _api.get('/catalog/search', query: {'query': query, ...filters.query(withText: true)}),
      );

  /// Movies or TV shows of one type matching a text, or only the filters when the text is empty
  /// (`/catalog/discover/{type}`: with a minimum rating, a page may be short or empty).
  Future<Paged<MediaItem>> titles(TitleQuery q) async => Paged.fromJson(
    q.query.isEmpty
        ? await _api.get(
            '/catalog/discover/${q.type.name}',
            query: {...q.filters.query(withText: false), 'page': q.page},
          )
        : await _api.get(
            '/catalog/search/${q.type.name}',
            query: {'query': q.query, ...q.filters.query(withText: true), 'page': q.page},
          ),
    MediaItem.fromJson,
  );

  /// People matching [query].
  Future<Paged<Person>> people(String query, {int page = 1}) async => Paged.fromJson(
    await _api.get('/catalog/search/person', query: {'query': query, 'page': page}),
    Person.fromJson,
  );

  Future<Map<MediaType, List<Genre>>> allGenres() async {
    final json = await _api.get('/catalog/genres');
    List<Genre> of(MediaType type) {
      final list = json[type.name];
      return list is List ? list.whereType<Map<String, dynamic>>().map(Genre.fromJson).toList() : [];
    }

    return {for (final type in MediaType.values) type: of(type)};
  }

}

/// Loaded lazily when the ratings modal is opened.
final externalRatingsProvider = FutureProvider.autoDispose.family<Map<String, SiteRating>, (MediaType, int)>((ref, key) {
  return ref.read(catalogRepositoryProvider).externalRatings(key.$1, key.$2);
});

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) => CatalogRepository(ref.read(apiClientProvider)));

/// Active profile id: catalog providers watch it so a profile switch refetches
/// (the API filters titles with the profile's age limit).
final _profileIdProvider = Provider<int?>((ref) => ref.watch(sessionProvider.select((s) => s.profile?.id)));

/// A movie or TV show by id.
typedef TitleRef = ({MediaType type, int id});

/// Titles by id, fetched together (`/catalog/titles`): the key is the list of ids, e.g. "movie:550,tv:1399".
final titlesByIdProvider = FutureProvider.autoDispose.family<Map<TitleRef, MediaItem>, String>((ref, ids) async {
  ref.watch(_profileIdProvider);
  final refs = [
    for (final key in ids.split(',').where((k) => k.contains(':')))
      (type: MediaType.parse(key.split(':').first), id: int.parse(key.split(':').last)),
  ];
  if (refs.isEmpty) return const {};
  final items = await ref.read(catalogRepositoryProvider).titlesById(refs);
  return {for (final item in items) (type: item.type, id: item.id): item};
});

/// Key of [titlesByIdProvider] for these titles (sorted: the same set, the same request).
String titlesKey(Iterable<TitleRef> titles) =>
    (titles.map((t) => '${t.type.name}:${t.id}').toSet().toList()..sort()).join(',');

final homeProvider = FutureProvider.autoDispose<Home>((ref) {
  ref.watch(_profileIdProvider);
  return ref.read(catalogRepositoryProvider).home();
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

/// Every title of a person (id, order): « Voir tout » of « Connu pour » and « Filmographie ».
final personCreditsProvider = FutureProvider.autoDispose.family<List<MediaItem>, (int, PersonCreditsSort)>((ref, key) {
  ref.watch(_profileIdProvider);
  return ref.read(catalogRepositoryProvider).personCredits(key.$1, key.$2);
});

/// One page of « Vous pourriez aussi aimer » (type, id, page): its « Voir tout » page.
final recommendationsProvider = FutureProvider.autoDispose.family<Paged<MediaItem>, (MediaType, int, int)>((ref, key) {
  ref.watch(_profileIdProvider);
  return ref.read(catalogRepositoryProvider).recommendations(key.$1, key.$2, page: key.$3);
});

/// Everyone of a title (type, id): « Voir tout » of « Créateur et distribution ».
final titleCreditsProvider = FutureProvider.autoDispose.family<TitleCredits, (MediaType, int)>((ref, key) {
  ref.watch(_profileIdProvider);
  return ref.read(catalogRepositoryProvider).credits(key.$1, key.$2);
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

/// One page of a home list (type, list, page): the "Voir tout" page of a row.
final titleListProvider = FutureProvider.autoDispose.family<Paged<MediaItem>, (MediaType, String, int)>((ref, key) {
  ref.watch(_profileIdProvider);
  return ref.read(catalogRepositoryProvider).list(key.$1, key.$2, page: key.$3);
});

/// One page of people matching a text.
final peopleProvider = FutureProvider.autoDispose.family<Paged<Person>, (String, int)>(
  (ref, key) => ref.read(catalogRepositoryProvider).people(key.$1, page: key.$2),
);

/// Movie and TV genres (one request for both).
final allGenresProvider = FutureProvider.autoDispose<Map<MediaType, List<Genre>>>(
  (ref) => ref.read(catalogRepositoryProvider).allGenres(),
);
