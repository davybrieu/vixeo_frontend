import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/local_store.dart';
import '../auth/session.dart';
import '../catalog/models.dart';
import '../catalog/widgets.dart' show titlePath;
import '../library/library.dart';
import 'system_notifications.dart';

/// An episode coming out soon in a TV show of « Ma liste » (`/catalog/episodes/upcoming`).
class UpcomingEpisode {
  const UpcomingEpisode({
    required this.showId,
    required this.showName,
    required this.season,
    required this.episode,
    required this.availableAt,
    this.name,
    this.posterUrl,
  });

  factory UpcomingEpisode.fromJson(Map<String, dynamic> json) => UpcomingEpisode(
    showId: json['show_id'] as int,
    showName: json['show_name'] as String? ?? '',
    season: json['season_number'] as int? ?? 0,
    episode: json['episode_number'] as int? ?? 0,
    name: json['name'] as String?,
    posterUrl: json['poster_url'] as String?,
    availableAt: DateTime.parse(json['available_at'] as String),
  );

  final int showId;
  final String showName;
  final int season;
  final int episode;
  final String? name;
  final String? posterUrl;

  /// When it should be available: the API's estimate, never early on purpose.
  final DateTime availableAt;

  /// "S2 · É3".
  String get code => 'S$season · É$episode';

  /// The name TMDb gives, unless it is only "Épisode 3".
  String? get title {
    final value = name?.trim();
    if (value == null || value.isEmpty || RegExp(r'^[ÉE]pisode\s*\d+$', caseSensitive: false).hasMatch(value)) {
      return null;
    }
    return value;
  }
}

/// When to notify an episode available at [availableAt]: that moment in the device's time, out of
/// the night (23:00 – 08:00 → 08:00).
DateTime alertTime(DateTime availableAt) {
  final local = availableAt.toLocal();
  if (local.hour >= 23) return DateTime(local.year, local.month, local.day + 1, 8);
  if (local.hour < 8) return DateTime(local.year, local.month, local.day, 8);
  return local;
}

/// One notification: the episodes of a show available at the same moment (a whole season on a
/// streaming platform makes one notification, not ten).
class EpisodeAlert {
  const EpisodeAlert({required this.showId, required this.showName, required this.at, required this.episodes});

  final int showId;
  final String showName;
  final DateTime at;
  final List<UpcomingEpisode> episodes;

  /// « S2 · É3 « Le Pont » est disponible. », « 8 nouveaux épisodes de la saison 2 sont disponibles. »
  String get body {
    if (episodes.length == 1) {
      final e = episodes.single;
      final title = e.title;
      return title == null ? '${e.code} est disponible.' : '${e.code} « $title » est disponible.';
    }
    final seasons = {for (final e in episodes) e.season};
    return seasons.length == 1
        ? '${episodes.length} nouveaux épisodes de la saison ${seasons.single} sont disponibles.'
        : '${episodes.length} nouveaux épisodes sont disponibles.';
  }

  /// « S2 · É3 », « S2 · É1 à É8 »: the episodes, short (the list of the page).
  String get codes {
    if (episodes.length == 1) return episodes.single.code;
    final first = episodes.first;
    final last = episodes.last;
    return first.season == last.season
        ? 'S${first.season} · É${first.episode} à É${last.episode}'
        : '${first.code} à ${last.code}';
  }

  String get path => titlePath(MediaType.tv, showId);

  /// Stable id: the same show at the same time replaces the same notification.
  int get id => notificationId('$showId@${at.toUtc().toIso8601String()}');

  LocalNotification get notification => LocalNotification(id: id, title: showName, body: body, path: path, at: at);
}

/// Id of the test notification (never one of an episode: [notificationId] avoids it).
const testNotificationId = 1;

/// A positive 31-bit id from a text (FNV-1a), never 0 or [testNotificationId].
int notificationId(String key) {
  var hash = 0x811c9dc5;
  for (final unit in key.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  final id = hash & 0x7fffffff;
  return id <= testNotificationId ? id + 2 : id;
}

/// Alerts still to come, the soonest first: episodes grouped by show and time ([alertTime]).
/// At most [max] (the system keeps a few hundred programmed notifications per app).
List<EpisodeAlert> episodeAlerts(List<UpcomingEpisode> episodes, {required DateTime now, int max = 100}) {
  final groups = <(int, DateTime), List<UpcomingEpisode>>{};
  for (final e in episodes) {
    final at = alertTime(e.availableAt);
    if (!at.isAfter(now)) continue;
    groups.putIfAbsent((e.showId, at), () => []).add(e);
  }
  final alerts = [
    for (final MapEntry(key: (showId, at), value: list) in groups.entries)
      EpisodeAlert(
        showId: showId,
        showName: list.first.showName,
        at: at,
        episodes: list..sort((a, b) => (a.season, a.episode).compareTo((b.season, b.episode))),
      ),
  ]..sort((a, b) => a.at != b.at ? a.at.compareTo(b.at) : a.showName.compareTo(b.showName));
  return alerts.take(max).toList();
}

extension on (int, int) {
  int compareTo((int, int) other) => $1 != other.$1 ? $1.compareTo(other.$1) : $2.compareTo(other.$2);
}

/// « Aujourd’hui, 21:00 », « Demain, 08:00 », « Jeudi 20 novembre, 21:00 ».
String alertDateLabel(DateTime at, {required DateTime now}) {
  final time = '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
  final day = DateTime(at.year, at.month, at.day);
  final today = DateTime(now.year, now.month, now.day);
  // Rounded: a day can last 23 or 25 hours (summer time).
  final days = (day.difference(today).inHours / 24).round();
  if (days == 0) return 'Aujourd’hui, $time';
  if (days == 1) return 'Demain, $time';
  const weekdays = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];
  const months = [
    'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
    'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
  ];
  final date = '${weekdays[at.weekday - 1]} ${at.day == 1 ? '1er' : at.day} ${months[at.month - 1]}';
  return '$date, $time';
}

/// TMDb ids of the TV shows of « Ma liste » (most recently added first).
List<int> favoriteShowIds(LibraryState library) => [
  for (final item in library.favorites)
    if (item.type == 'tv' && item.tmdbTitle?.type == MediaType.tv) item.tmdbTitle!.id,
];

/// The API's coming episodes of these shows (100 shows per request).
Future<List<UpcomingEpisode>> fetchUpcomingEpisodes(ApiClient api, List<int> showIds) async {
  final episodes = <UpcomingEpisode>[];
  final ids = showIds.toSet().toList();
  for (var i = 0; i < ids.length; i += 100) {
    final query = {'ids': ids.skip(i).take(100).join(',')};
    final data = (await api.get('/catalog/episodes/upcoming', query: query))['data'];
    if (data is List) episodes.addAll(data.whereType<Map<String, dynamic>>().map(UpcomingEpisode.fromJson));
  }
  return episodes;
}

/// Coming alerts of the active profile (« Notifications » page): its « Ma liste » shows.
final upcomingAlertsProvider = FutureProvider.autoDispose<List<EpisodeAlert>>((ref) async {
  final library = await ref.watch(libraryProvider.future);
  final ids = favoriteShowIds(library);
  if (ids.isEmpty) return const [];
  return episodeAlerts(await fetchUpcomingEpisodes(ref.read(apiClientProvider), ids), now: DateTime.now());
});

/// « Alertes de sortie d'épisodes » of the active profile on this device (off by default).
/// Kept on the device: the notifications are this device's.
final episodeAlertsSettingProvider = AsyncNotifierProvider<EpisodeAlertsSetting, bool>(EpisodeAlertsSetting.new);

class EpisodeAlertsSetting extends AsyncNotifier<bool> {
  static String keyFor(int profileId) => 'vixeo.notifications.episodes.$profileId';

  @override
  Future<bool> build() async {
    final profileId = ref.watch(sessionProvider.select((s) => s.profile?.id));
    if (profileId == null) return false;
    try {
      return await ref.read(localStoreProvider).read(keyFor(profileId)) == '1';
    } catch (_) {
      return false;
    }
  }

  Future<void> set(bool value) async {
    final profileId = ref.read(sessionProvider).profile?.id;
    if (profileId == null) return;
    state = AsyncData(value);
    try {
      await ref.read(localStoreProvider).write(keyFor(profileId), value ? '1' : null);
    } catch (_) {
      // Not kept (private browsing…): on for this launch only.
    }
  }
}

/// Programs the notifications of the active profile's coming episodes, or removes them (alerts
/// off, no profile). Run at launch, back in the foreground, and when « Ma liste », the profile or
/// the setting changes ([NotificationsGate]). The notifications follow the profile in use on this
/// device: another profile replaces them with its own.
class EpisodeAlertsScheduler {
  EpisodeAlertsScheduler(this._ref);

  final Ref _ref;
  Future<void>? _running;
  bool _again = false;

  /// One run at a time; a request during a run starts one more after it.
  Future<void> sync() {
    if (_running != null) {
      _again = true;
      return _running!;
    }
    return _running = _run().whenComplete(() {
      _running = null;
      if (_again) {
        _again = false;
        sync();
      }
    });
  }

  Future<void> _run() async {
    final notifications = _ref.read(systemNotificationsProvider);
    if (!notifications.supported) return;
    try {
      final session = _ref.read(sessionProvider);
      // Not known yet (launch, server unreachable) or a profile being chosen: keep what is programmed.
      if (session.status == SessionStatus.restoring || session.status == SessionStatus.unreachable) return;
      if (session.isSignedIn && session.profile == null) return;
      final enabled = session.profile != null && await _ref.read(episodeAlertsSettingProvider.future);
      if (!enabled) {
        await notifications.schedule(const []);
        return;
      }
      final ids = favoriteShowIds(await _ref.read(libraryProvider.future));
      final episodes = ids.isEmpty
          ? const <UpcomingEpisode>[]
          : await fetchUpcomingEpisodes(_ref.read(apiClientProvider), ids);
      final alerts = episodeAlerts(episodes, now: DateTime.now());
      await notifications.schedule([for (final alert in alerts) alert.notification]);
    } catch (_) {
      // API unreachable: the notifications already programmed stay; next try at the next change.
    }
  }
}

final episodeAlertsSchedulerProvider = Provider<EpisodeAlertsScheduler>(EpisodeAlertsScheduler.new);
