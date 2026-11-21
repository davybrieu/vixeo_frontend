import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../auth/session.dart';
import '../social/social_repository.dart';
import '../tmdb/review_screen.dart';
import '../tmdb/tmdb.dart';

// The « Notifications » page (`/notifications`, a destination of the navigation; developer's
// request, 21/11/2026): what other members did for the active profile, its follow requests and
// the next episodes of its « Ma liste » shows. API: vixeo_backend/docs/social.md.

/// What another member did.
enum ActivityType {
  follow('follow'),
  followRequest('follow_request'),
  followAccepted('follow_accepted'),
  reviewLike('review_like'),

  /// A type this app doesn't know (a newer API): not shown.
  unknown('');

  const ActivityType(this.key);

  final String key;

  static ActivityType parse(Object? value) =>
      values.firstWhere((type) => type != unknown && type.key == value, orElse: () => unknown);
}

/// One notification: who, what, when, read or not.
class Activity {
  const Activity({
    required this.id,
    required this.type,
    required this.actor,
    this.createdAt,
    this.read = false,
    this.review,
  });

  factory Activity.fromJson(Map<String, dynamic> json) => Activity(
    id: json['id'] as int,
    type: ActivityType.parse(json['type']),
    actor: SocialProfile.fromJson((json['actor'] as Map<String, dynamic>?) ?? const {'id': 0}),
    createdAt: DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal(),
    read: json['read'] as bool? ?? false,
    review: switch (json['review']) {
      final Map<String, dynamic> review => RatedItem.fromJson(review),
      _ => null,
    },
  );

  final int id;
  final ActivityType type;
  final SocialProfile actor;
  final DateTime? createdAt;
  final bool read;

  /// My review liked ([ActivityType.reviewLike]).
  final RatedItem? review;

  /// After the member's name: "vous suit.", "aime votre avis sur Dune."…
  String get message => switch (type) {
    ActivityType.follow => 'vous suit.',
    ActivityType.followRequest => 'demande à vous suivre.',
    ActivityType.followAccepted => 'a accepté votre demande d’abonnement.',
    ActivityType.reviewLike => 'aime votre avis sur ${review?.label ?? 'un titre'}.',
    ActivityType.unknown => '',
  };

  /// The page a press opens: my review liked, otherwise the member's page.
  String get path => switch (review) {
    final review? when type == ActivityType.reviewLike => ReviewScreen.location(review.target),
    _ => '/membre/${Uri.encodeComponent(actor.username)}',
  };
}

/// A page of notifications.
class ActivityPage {
  const ActivityPage({required this.items, required this.currentPage, required this.lastPage, this.unreadCount});

  final List<Activity> items;
  final int currentPage;
  final int lastPage;
  final int? unreadCount;
}

/// The next (or a recent) episode of a « Ma liste » show.
class ShowEpisode {
  const ShowEpisode({
    required this.showId,
    required this.showName,
    required this.availableAt,
    this.posterUrl,
    this.backdropUrl,
    this.seasonNumber,
    this.episodeNumber,
    this.name,
    this.stillUrl,
  });

  static ShowEpisode? fromJson(Map<String, dynamic> json) {
    final show = json['show'];
    final at = DateTime.tryParse(json['available_at'] as String? ?? '');
    if (show is! Map<String, dynamic> || show['id'] is! int || at == null) return null;
    return ShowEpisode(
      showId: show['id'] as int,
      showName: show['name'] as String? ?? '',
      posterUrl: show['poster_url'] as String?,
      backdropUrl: show['backdrop_url'] as String?,
      seasonNumber: json['season_number'] as int?,
      episodeNumber: json['episode_number'] as int?,
      name: json['name'] as String?,
      stillUrl: json['still_url'] as String?,
      availableAt: at.toLocal(),
    );
  }

  final int showId;
  final String showName;
  final String? posterUrl;
  final String? backdropUrl;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? name;
  final String? stillUrl;

  /// When it is (or was) out here: an estimate made not to be early.
  final DateTime availableAt;

  /// "Saison 2, épisode 5 · Le Retour".
  String get label => [
    if (seasonNumber != null && episodeNumber != null) 'Saison $seasonNumber, épisode $episodeNumber',
    if (name?.trim().isNotEmpty == true) name!.trim(),
  ].join(' · ');
}

/// The next episodes of the « Ma liste » shows (the soonest first) and those out this week.
class EpisodeCalendar {
  const EpisodeCalendar({this.upcoming = const [], this.recent = const []});

  final List<ShowEpisode> upcoming;
  final List<ShowEpisode> recent;
}

class InboxRepository {
  InboxRepository(this._api);

  final ApiClient _api;

  Future<ActivityPage> activity({int page = 1}) async {
    final json = await _api.get('/notifications', query: {'page': page});
    final meta = json['meta'] as Map<String, dynamic>? ?? const {};
    return ActivityPage(
      items: [
        for (final item in (json['data'] as List? ?? const []).whereType<Map<String, dynamic>>())
          Activity.fromJson(item),
      ],
      currentPage: meta['current_page'] as int? ?? page,
      lastPage: meta['last_page'] as int? ?? page,
      unreadCount: json['unread_count'] as int?,
    );
  }

  /// The badge of the navigation.
  Future<int> unreadCount() async {
    final json = await _api.get('/notifications/count');
    return json['unread_count'] as int? ?? 0;
  }

  /// Every notification read (the page was opened).
  Future<void> markRead() => _api.post('/notifications/read');

  Future<EpisodeCalendar> episodes() async {
    final json = await _api.get('/notifications/episodes');
    List<ShowEpisode> list(Object? value) => [
      if (value is List)
        for (final item in value.whereType<Map<String, dynamic>>()) ?ShowEpisode.fromJson(item),
    ];
    return EpisodeCalendar(upcoming: list(json['upcoming']), recent: list(json['recent']));
  }
}

final inboxRepositoryProvider = Provider<InboxRepository>((ref) => InboxRepository(ref.read(apiClientProvider)));

/// The page and its badge exist for a signed-in profile that isn't a child's.
bool socialAvailable(SessionState session) =>
    session.isSignedIn && session.profile != null && !session.profile!.isKid;

/// Unread notifications: the badge of « Notifications » in the navigation. Read again when the
/// navigation is shown or changes page (30 s at most between two), when the app comes back to the
/// foreground and when a push of the `social` channel arrives; 0 once the page is opened.
final unreadNotificationsProvider = NotifierProvider<UnreadNotifications, int>(UnreadNotifications.new);

class UnreadNotifications extends Notifier<int> {
  DateTime? _readAt;

  /// Shortest time between two readings, unless forced.
  static const minInterval = Duration(seconds: 30);

  @override
  int build() {
    ref.watch(sessionProvider.select((s) => (s.status, s.profile?.id)));
    _readAt = null;
    return 0;
  }

  Future<void> refresh({bool force = false}) async {
    if (!socialAvailable(ref.read(sessionProvider))) return;
    final now = DateTime.now();
    final last = _readAt;
    if (!force && last != null && now.difference(last) < minInterval) return;
    _readAt = now;
    try {
      final count = await ref.read(inboxRepositoryProvider).unreadCount();
      if (ref.mounted) state = count;
    } catch (_) {
      // Offline, server down: the badge stays as it was.
    }
  }

  /// Everything read (the page was opened).
  void clear() => state = 0;
}

/// Follow requests waiting for the active profile (a private account).
final followRequestsProvider = FutureProvider.autoDispose<List<SocialProfile>>((ref) async {
  if (!socialAvailable(ref.watch(sessionProvider))) return const [];
  return ref.read(socialRepositoryProvider).requests();
});

/// The next episodes of the active profile's « Ma liste » shows.
final episodeCalendarProvider = FutureProvider.autoDispose<EpisodeCalendar>((ref) async {
  if (!socialAvailable(ref.watch(sessionProvider))) return const EpisodeCalendar();
  return ref.read(inboxRepositoryProvider).episodes();
});

/// The notifications loaded so far (30 per page, the most recent first).
class ActivityFeedState {
  const ActivityFeedState({required this.items, required this.page, required this.lastPage, this.loadingMore = false});

  final List<Activity> items;
  final int page;
  final int lastPage;
  final bool loadingMore;

  bool get hasMore => page < lastPage;
}

final activityFeedProvider = AsyncNotifierProvider.autoDispose<ActivityFeed, ActivityFeedState>(ActivityFeed.new);

class ActivityFeed extends AsyncNotifier<ActivityFeedState> {
  @override
  Future<ActivityFeedState> build() async {
    if (!socialAvailable(ref.watch(sessionProvider))) {
      return const ActivityFeedState(items: [], page: 1, lastPage: 1);
    }
    final first = await ref.read(inboxRepositoryProvider).activity();
    return ActivityFeedState(items: first.items, page: first.currentPage, lastPage: first.lastPage);
  }

  /// The next page, under the others.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(
      ActivityFeedState(items: current.items, page: current.page, lastPage: current.lastPage, loadingMore: true),
    );
    try {
      final next = await ref.read(inboxRepositoryProvider).activity(page: current.page + 1);
      if (!ref.mounted) return;
      final known = {for (final item in current.items) item.id};
      state = AsyncData(
        ActivityFeedState(
          items: [...current.items, ...next.items.where((item) => !known.contains(item.id))],
          page: next.currentPage,
          lastPage: next.lastPage,
        ),
      );
    } catch (_) {
      if (ref.mounted) state = AsyncData(current);
    }
  }
}

const _weekdays = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
const _months = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin', //
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
];

/// "aujourd’hui", "demain", "hier", or "lundi 24 novembre" (with the year when it isn't this one).
String dayLabel(DateTime at, DateTime now) {
  final day = DateTime(at.year, at.month, at.day);
  final today = DateTime(now.year, now.month, now.day);
  final days = day.difference(today).inHours / 24;
  switch (days.round()) {
    case 0:
      return 'aujourd’hui';
    case 1:
      return 'demain';
    case -1:
      return 'hier';
  }
  final date = '${_weekdays[at.weekday - 1]} ${at.day == 1 ? '1er' : at.day} ${_months[at.month - 1]}';
  return at.year == now.year ? date : '$date ${at.year}';
}

String _hourMinute(DateTime at) => '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

/// When an episode comes out: "Demain à 21:00", "Lundi 24 novembre à 08:00"; out already:
/// "Sorti aujourd’hui", "Sorti hier", "Sorti lundi 17 novembre".
String episodeWhen(DateTime at, DateTime now) {
  final day = dayLabel(at, now);
  if (!at.isAfter(now)) return 'Sorti $day';
  return '${day[0].toUpperCase()}${day.substring(1)} à ${_hourMinute(at)}';
}

/// How long ago, as on a social network: "à l’instant", "il y a 5 min", "il y a 3 h", "hier",
/// "il y a 4 jours", then the date ("12 novembre").
String timeAgo(DateTime at, DateTime now) {
  final elapsed = now.difference(at);
  if (elapsed.inMinutes < 1) return 'à l’instant';
  if (elapsed.inHours < 1) return 'il y a ${elapsed.inMinutes} min';
  if (elapsed.inHours < 24) return 'il y a ${elapsed.inHours} h';
  final day = dayLabel(at, now);
  if (day == 'hier') return day;
  if (elapsed.inDays < 7) return 'il y a ${elapsed.inDays} jours';
  final date = '${at.day == 1 ? '1er' : at.day} ${_months[at.month - 1]}';
  return at.year == now.year ? date : '$date ${at.year}';
}
