import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../auth/session.dart';

/// A recent search of the profile (API `ProfileSearchResource`).
@immutable
class RecentSearch {
  const RecentSearch({required this.id, required this.query, this.searchedAt});

  factory RecentSearch.fromJson(Map<String, dynamic> json) => RecentSearch(
    id: json['id'] as int,
    query: json['query'] as String? ?? '',
    searchedAt: DateTime.tryParse(json['searched_at'] as String? ?? '')?.toLocal(),
  );

  /// 0 while it is being saved.
  final int id;
  final String query;
  final DateTime? searchedAt;

  String get key => query.trim().toLowerCase();
}

/// `/profiles/{id}/searches` (vixeo_backend/docs/lecture.md).
class SearchHistoryRepository {
  SearchHistoryRepository(this._api);

  final ApiClient _api;

  Future<List<RecentSearch>> list(int profileId) async {
    final data = (await _api.get('/profiles/$profileId/searches'))['data'];
    return data is List ? data.whereType<Map<String, dynamic>>().map(RecentSearch.fromJson).toList() : const [];
  }

  Future<RecentSearch> add(int profileId, String query) async => RecentSearch.fromJson(
    (await _api.post('/profiles/$profileId/searches', body: {'query': query}))['data'] as Map<String, dynamic>,
  );

  Future<void> remove(int profileId, int id) => _api.delete('/profiles/$profileId/searches/$id');

  Future<void> clear(int profileId) => _api.post('/profiles/$profileId/searches/clear');
}

final searchHistoryRepositoryProvider = Provider<SearchHistoryRepository>(
  (ref) => SearchHistoryRepository(ref.read(apiClientProvider)),
);

/// Recent searches of the active profile, the same on all its devices. Changes show at once and
/// are saved in the background: a failed save keeps the list as shown (it's only a history).
final recentSearchesProvider = AsyncNotifierProvider<RecentSearches, List<RecentSearch>>(RecentSearches.new);

class RecentSearches extends AsyncNotifier<List<RecentSearch>> {
  static const max = 20;

  /// Same rule as the API: while typing, "orbi" then "orbite" keeps only "orbite".
  static const mergeWindow = Duration(minutes: 2);

  int? get _profileId => ref.read(sessionProvider).profile?.id;

  SearchHistoryRepository get _repository => ref.read(searchHistoryRepositoryProvider);

  List<RecentSearch> get _current => state.value ?? const [];

  @override
  Future<List<RecentSearch>> build() async {
    final profileId = ref.watch(sessionProvider.select((s) => s.profile?.id));
    if (profileId == null) return const [];
    return ref.read(searchHistoryRepositoryProvider).list(profileId);
  }

  Future<void> add(String query) async {
    final profileId = _profileId;
    if (profileId == null) return;
    final draft = RecentSearch(id: 0, query: query, searchedAt: DateTime.now());
    state = AsyncData([draft, ..._current.where((s) => !_replacedBy(s, draft))].take(max).toList());
    try {
      final saved = await _repository.add(profileId, query);
      state = AsyncData([saved, ..._current.where((s) => s.key != saved.key && !_replacedBy(s, saved))]);
    } on ApiException catch (e) {
      debugPrint('Recent search not saved: ${e.message}');
    }
  }

  Future<void> remove(RecentSearch search) async {
    final profileId = _profileId;
    state = AsyncData(_current.where((s) => s.key != search.key).toList());
    if (profileId == null || search.id == 0) return;
    try {
      await _repository.remove(profileId, search.id);
    } on ApiException catch (e) {
      debugPrint('Recent search not removed: ${e.message}');
    }
  }

  Future<void> clear() async {
    final profileId = _profileId;
    state = const AsyncData([]);
    if (profileId == null) return;
    try {
      await _repository.clear(profileId);
    } on ApiException catch (e) {
      debugPrint('Recent searches not cleared: ${e.message}');
    }
  }

  /// [old] is the same search, or one typed just before that [search] extends.
  static bool _replacedBy(RecentSearch old, RecentSearch search) {
    if (old.key == search.key) return true;
    final at = old.searchedAt;
    final recent = at != null && search.searchedAt != null && search.searchedAt!.difference(at) < mergeWindow;
    return recent && search.key.startsWith(old.key);
  }
}
