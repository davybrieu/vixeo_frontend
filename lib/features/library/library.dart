import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../auth/session.dart';
import '../catalog/models.dart';
import '../tv/models.dart';

/// Synced state of one content for the active profile (ProfileItemResource).
class ProfileItem {
  const ProfileItem({
    required this.source,
    required this.itemId,
    required this.type,
    required this.title,
    this.year,
    this.posterUrl,
    this.backdropUrl,
    this.parentItemId,
    this.seasonNumber,
    this.episodeNumber,
    this.isFavorite = false,
    this.favoritedAt,
    this.isLiked = false,
    this.likedAt,
    this.positionMs = 0,
    this.durationMs,
    this.progress,
    this.lastEngagedAt,
    this.isWatched = false,
  });

  factory ProfileItem.fromJson(Map<String, dynamic> json) => ProfileItem(
    source: json['source'] as String,
    itemId: json['item_id'] as String,
    type: json['type'] as String,
    title: json['title'] as String? ?? '',
    year: json['year'] as int?,
    posterUrl: json['poster_url'] as String?,
    backdropUrl: json['backdrop_url'] as String?,
    parentItemId: json['parent_item_id'] as String?,
    seasonNumber: json['season_number'] as int?,
    episodeNumber: json['episode_number'] as int?,
    isFavorite: json['is_favorite'] as bool? ?? false,
    favoritedAt: _date(json['favorited_at']),
    isLiked: json['is_liked'] as bool? ?? false,
    likedAt: _date(json['liked_at']),
    positionMs: json['position_ms'] as int? ?? 0,
    durationMs: json['duration_ms'] as int?,
    progress: (json['progress'] as num?)?.toDouble(),
    lastEngagedAt: _date(json['last_engaged_at']),
    isWatched: json['is_watched'] as bool? ?? false,
  );

  final String source;
  final String itemId;

  /// movie, tv, episode, channel, video.
  final String type;
  final String title;
  final int? year;
  final String? posterUrl;
  final String? backdropUrl;
  final String? parentItemId;
  final int? seasonNumber;
  final int? episodeNumber;

  /// In « Ma liste » (the API's historic `favorite` group).
  final bool isFavorite;
  final DateTime? favoritedAt;

  /// In « Favoris » (❤), separate from « Ma liste ».
  final bool isLiked;
  final DateTime? likedAt;
  final int positionMs;
  final int? durationMs;
  final double? progress;
  final DateTime? lastEngagedAt;
  final bool isWatched;

  String get key => '$source|$itemId';

  /// The live channel this item points to (« Favoris »), or null.
  TvChannel? get asChannel => source == LibraryController.channelSource && itemId.startsWith('channel:')
      ? TvChannel(id: itemId.substring('channel:'.length), name: title, categoryId: '', logo: posterUrl)
      : null;

  bool get inContinueWatching => lastEngagedAt != null && !isWatched;

  /// The TMDb title as a catalog item (hero of the TV home), or null for another source.
  MediaItem? get asMediaItem {
    final t = tmdbTitle;
    return t == null
        ? null
        : MediaItem(id: t.id, type: t.type, title: title, year: year, posterUrl: posterUrl, backdropUrl: backdropUrl);
  }

  /// TMDb title this item points to, if any ("movie:550", "tv:1399").
  ({MediaType type, int id})? get tmdbTitle {
    if (source != 'tmdb') return null;
    final parts = (parentItemId ?? itemId).split(':');
    final id = parts.length > 1 ? int.tryParse(parts[1]) : null;
    if (id == null || (parts[0] != 'movie' && parts[0] != 'tv')) return null;
    return (type: MediaType.parse(parts[0]), id: id);
  }

  /// "S3 · É2 · 18 min restantes", "1 h 04 restante".
  String get resumeLabel {
    final parts = <String>[if (seasonNumber != null && episodeNumber != null) 'S$seasonNumber · É$episodeNumber'];
    if (durationMs != null && durationMs! > positionMs) {
      final left = ((durationMs! - positionMs) / 60000).round();
      parts.add(left >= 60 ? '${formatRuntime(left)} restante' : '$left min restantes');
    }
    return parts.join(' · ');
  }

  static DateTime? _date(Object? value) => value is String ? DateTime.tryParse(value) : null;
}

/// The active profile's items, kept in sync with the API (`/profiles/{id}/sync`).
class LibraryState {
  const LibraryState(this.items);

  final Map<String, ProfileItem> items;

  ProfileItem? forItem(MediaItem item) => items['tmdb|${item.syncId}'];

  ProfileItem? forEpisode(int showId, int season, int episode) =>
      items['tmdb|${LibraryController.episodeSyncId(showId, season, episode)}'];

  ProfileItem? forChannel(TvChannel channel) => items['${LibraryController.channelSource}|channel:${channel.id}'];

  /// « Favoris » (❤): movies, TV shows, episodes and channels, most recently added first.
  List<ProfileItem> get liked =>
      items.values.where((i) => i.isLiked).toList()
        ..sort((a, b) => (b.likedAt ?? DateTime(0)).compareTo(a.likedAt ?? DateTime(0)));

  List<ProfileItem> get favorites =>
      items.values.where((i) => i.isFavorite).toList()
        ..sort((a, b) => (b.favoritedAt ?? DateTime(0)).compareTo(a.favoritedAt ?? DateTime(0)));

  List<ProfileItem> get continueWatching =>
      items.values.where((i) => i.inContinueWatching).toList()
        ..sort((a, b) => b.lastEngagedAt!.compareTo(a.lastEngagedAt!));
}

final libraryProvider = AsyncNotifierProvider<LibraryController, LibraryState>(LibraryController.new);

class LibraryController extends AsyncNotifier<LibraryState> {
  ApiClient get _api => ref.read(apiClientProvider);
  int _cursor = 0;
  int? _profileId;

  @override
  Future<LibraryState> build() async {
    _profileId = ref.watch(sessionProvider.select((s) => s.profile?.id));
    _cursor = 0;
    if (_profileId == null) return const LibraryState({});
    return LibraryState(await _pull({}));
  }

  /// Downloads the changes made on other devices since the last pull.
  Future<void> refresh() async {
    final current = state.value;
    if (_profileId == null || current == null) return;
    state = AsyncData(LibraryState(await _pull(Map.of(current.items))));
  }

  Future<void> setFavorite(MediaItem item, bool value) => _push(item, {
    'favorite': {'value': value, 'at': _now()},
  });

  /// « Favoris » (❤) of a movie or a TV show.
  Future<void> setLiked(MediaItem item, bool value) => _push(item, {
    'liked': {'value': value, 'at': _now()},
  });

  /// Sync source of the live channels (`/tv/…`), item ids `channel:<id>`.
  static const channelSource = 'tv';

  /// `episode:1399:1:3` (show, season, episode), as in vixeo_backend/docs/synchronisation.md.
  static String episodeSyncId(int showId, int season, int episode) => 'episode:$showId:$season:$episode';

  /// « Favoris » (❤) of an episode, with what the list needs to show it (still, show, numbers).
  Future<void> setEpisodeLiked(MediaItem show, Episode episode, bool value) => _pushRaw({
    'source': 'tmdb',
    'item_id': episodeSyncId(show.id, episode.seasonNumber, episode.number),
    'type': 'episode',
    'title': episode.name.isEmpty ? 'Épisode ${episode.number}' : episode.name,
    'poster_url': _httpUrl(episode.stillUrl),
    'backdrop_url': _httpUrl(show.backdropUrl),
    'parent_item_id': show.syncId,
    'season_number': episode.seasonNumber,
    'episode_number': episode.number,
    'liked': {'value': value, 'at': _now()},
  });

  /// « Favoris » (❤) of a live channel (its logo as the image).
  Future<void> setChannelLiked(TvChannel channel, bool value) => _pushRaw({
    'source': channelSource,
    'item_id': 'channel:${channel.id}',
    'type': 'channel',
    'title': channel.name,
    'poster_url': _httpUrl(channel.logo),
    'liked': {'value': value, 'at': _now()},
  });

  /// The API takes only http(s) image URLs: anything else is left out.
  static String? _httpUrl(String? url) =>
      url != null && (url.startsWith('https://') || url.startsWith('http://')) ? url : null;

  Future<void> setWatched(MediaItem item, bool value) => _push(item, {
    'watched': {'value': value, 'at': _now()},
    // A finished title leaves "Continuer à regarder".
    if (value) 'progress': {'position_ms': 0, 'continue_watching': false, 'at': _now()},
  });

  Future<void> removeFromContinueWatching(ProfileItem item) => _pushRaw({
    'source': item.source,
    'item_id': item.itemId,
    'type': item.type,
    'title': item.title,
    'progress': {'position_ms': item.positionMs, 'continue_watching': false, 'at': _now()},
  });

  Future<Map<String, ProfileItem>> _pull(Map<String, ProfileItem> items) async {
    var hasMore = true;
    while (hasMore) {
      final json = await _api.get('/profiles/$_profileId/sync', query: {'cursor': _cursor, 'limit': 500});
      for (final raw in (json['data'] as List).whereType<Map<String, dynamic>>()) {
        final item = ProfileItem.fromJson(raw);
        items[item.key] = item;
      }
      _cursor = json['cursor'] as int? ?? _cursor;
      hasMore = json['has_more'] as bool? ?? false;
    }
    return items;
  }

  Future<void> _push(MediaItem item, Map<String, dynamic> groups) => _pushRaw({
    'source': 'tmdb',
    'item_id': item.syncId,
    'type': item.type.name,
    'title': item.title,
    'year': item.year,
    'poster_url': item.posterUrl,
    'backdrop_url': item.backdropUrl,
    ...groups,
  });

  Future<void> _pushRaw(Map<String, dynamic> change) async {
    if (_profileId == null) return;
    final json = await _api.post(
      '/profiles/$_profileId/sync',
      body: {
        'changes': [
          {
            for (final e in change.entries)
              if (e.value != null) e.key: e.value,
          },
        ],
      },
    );
    final items = Map.of(state.value?.items ?? const <String, ProfileItem>{});
    for (final raw in (json['data'] as List).whereType<Map<String, dynamic>>()) {
      final merged = ProfileItem.fromJson(raw);
      items[merged.key] = merged;
    }
    state = AsyncData(LibraryState(items));
  }

  static String _now() => DateTime.now().toUtc().toIso8601String();
}
