// The social network of movies and TV shows (vixeo_backend/docs/social.md): every publication is
// about a title (a review, a title watched or liked, a list), the conversation is in the
// comments. This file holds the models, the API calls and the providers; the pages are beside it.
//
// Flutter: a provider (Riverpod) is like a Vue store or a Laravel service the pages ask for; a
// `family` is a provider per argument (a list, a review…), `autoDispose` frees it once unused.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../auth/session.dart';
import '../catalog/catalog_repository.dart' show TitleRef;
import '../catalog/models.dart';
import '../notifications/inbox.dart' show socialAvailable;
import '../social/social_repository.dart';
import '../tmdb/tmdb.dart';

/// A title as the social network keeps it (`{type, id, title, year, poster_url, backdrop_url}`).
MediaItem titleCardOf(Map<String, dynamic> json) => MediaItem(
  id: (json['id'] ?? json['tmdb_id']) as int,
  type: MediaType.parse(json['media_type'] ?? json['type']),
  title: json['title'] as String? ?? '',
  year: json['year'] as int?,
  posterUrl: json['poster_url'] as String?,
  backdropUrl: json['backdrop_url'] as String?,
);

/// `movie:550`, as everywhere in the API.
String itemIdOf(MediaType type, int id) => '${type.name}:$id';

DateTime? _date(Object? value) => value is String ? DateTime.tryParse(value)?.toLocal() : null;

List<T> _list<T>(Object? value, T Function(Map<String, dynamic>) parse) =>
    value is List ? value.whereType<Map<String, dynamic>>().map(parse).toList() : <T>[];

/// A review as a publication: the review, its author, spoilers, comments.
@immutable
class SocialReview {
  const SocialReview({
    required this.item,
    required this.author,
    this.spoilers = false,
    this.commentsCount = 0,
    this.isMine = false,
  });

  factory SocialReview.fromJson(Map<String, dynamic> json) => SocialReview(
    item: RatedItem.fromJson(json),
    author: SocialProfile.fromJson(json['author'] as Map<String, dynamic>),
    spoilers: json['contains_spoilers'] as bool? ?? false,
    commentsCount: json['comments_count'] as int? ?? 0,
    isMine: json['is_mine'] as bool? ?? false,
  );

  final RatedItem item;
  final SocialProfile author;

  /// The comment reveals the story: hidden behind « Afficher ».
  final bool spoilers;
  final int commentsCount;
  final bool isMine;

  int get id => item.reviewId ?? 0;

  /// The movie or TV show reviewed (the show of an episode).
  MediaItem get title => MediaItem(
    id: item.id,
    type: item.mediaType,
    title: item.title,
    year: item.year,
    posterUrl: item.posterUrl,
    backdropUrl: item.backdropUrl,
  );

  SocialReview copyWith({bool? liked, int? likesCount, int? commentsCount}) => SocialReview(
    item: RatedItem(
      type: item.type,
      id: item.id,
      title: item.title,
      value: item.value,
      comment: item.comment,
      ratedAt: item.ratedAt,
      year: item.year,
      seasonNumber: item.seasonNumber,
      episodeNumber: item.episodeNumber,
      episodeName: item.episodeName,
      posterUrl: item.posterUrl,
      backdropUrl: item.backdropUrl,
      stillUrl: item.stillUrl,
      voteAverage: item.voteAverage,
      reviewId: item.reviewId,
      likesCount: likesCount ?? item.likesCount,
      liked: liked ?? item.liked,
      spoilers: item.spoilers,
      commentsCount: commentsCount ?? item.commentsCount,
    ),
    author: author,
    spoilers: spoilers,
    commentsCount: commentsCount ?? this.commentsCount,
    isMine: isMine,
  );
}

/// A list of a member: a title, a description and up to [maxItems] titles in the order its author
/// chose (a « Top 10 » is a list like the others: developer's request, 23/11/2026), with its titles
/// when it was opened ([items]). « À voir » is not one of them: it is the synced `favorite` group
/// (`LibraryState.favorites`), shown first among the lists.
@immutable
class SocialList {
  const SocialList({
    required this.id,
    required this.author,
    required this.title,
    this.description,
    this.itemsCount = 0,
    this.cover = const [],
    this.likesCount = 0,
    this.liked = false,
    this.commentsCount = 0,
    this.isMine = false,
    this.updatedAt,
    this.contains = false,
    this.items,
  });

  factory SocialList.fromJson(Map<String, dynamic> json) => SocialList(
    id: json['id'] as int,
    author: SocialProfile.fromJson(json['author'] as Map<String, dynamic>),
    title: json['title'] as String? ?? '',
    description: json['description'] as String?,
    itemsCount: json['items_count'] as int? ?? 0,
    cover: [
      for (final url in json['cover'] as List? ?? const [])
        if (url is String) url,
    ],
    likesCount: json['likes_count'] as int? ?? 0,
    liked: json['liked'] as bool? ?? false,
    commentsCount: json['comments_count'] as int? ?? 0,
    isMine: json['is_mine'] as bool? ?? false,
    updatedAt: _date(json['updated_at']),
    contains: json['contains'] as bool? ?? false,
    items: json['items'] is List ? _list(json['items'], titleCardOf) : null,
  );

  final int id;
  final SocialProfile author;
  final String title;
  final String? description;
  final int itemsCount;

  /// Titles in a list, at most.
  static const maxItems = 100;

  /// Posters of its first 4 titles.
  final List<String> cover;
  final int likesCount;
  final bool liked;
  final int commentsCount;
  final bool isMine;
  final DateTime? updatedAt;

  /// Has the title asked (« Ajouter à une liste »).
  final bool contains;

  /// Its titles in order (an opened list); null in a list of lists.
  final List<MediaItem>? items;

  /// « 7 titres », « 1 titre », « Aucun titre ».
  String get summary => titleCount(itemsCount);

  SocialList copyWith({bool? liked, int? likesCount, int? commentsCount}) => SocialList(
    id: id,
    author: author,
    title: title,
    description: description,
    itemsCount: itemsCount,
    cover: cover,
    likesCount: likesCount ?? this.likesCount,
    liked: liked ?? this.liked,
    commentsCount: commentsCount ?? this.commentsCount,
    isMine: isMine,
    updatedAt: updatedAt,
    contains: contains,
    items: items,
  );
}

/// « 7 titres », « 1 titre », « Aucun titre ».
String titleCount(int count) => switch (count) {
  0 => 'Aucun titre',
  1 => '1 titre',
  _ => '$count titres',
};

/// What a comment is on: a review or a list.
typedef CommentSubject = ({bool list, int id});

@immutable
class SocialComment {
  const SocialComment({
    required this.id,
    required this.author,
    required this.body,
    this.spoilers = false,
    this.createdAt,
    this.isMine = false,
    this.canDelete = false,
  });

  factory SocialComment.fromJson(Map<String, dynamic> json) => SocialComment(
    id: json['id'] as int,
    author: SocialProfile.fromJson(json['author'] as Map<String, dynamic>),
    body: json['body'] as String? ?? '',
    spoilers: json['contains_spoilers'] as bool? ?? false,
    createdAt: _date(json['created_at']),
    isMine: json['is_mine'] as bool? ?? false,
    canDelete: json['can_delete'] as bool? ?? false,
  );

  final int id;
  final SocialProfile author;
  final String body;
  final bool spoilers;
  final DateTime? createdAt;
  final bool isMine;

  /// Its author, or the author of the review or list.
  final bool canDelete;
}

/// Something of the feed.
@immutable
sealed class FeedItem {
  const FeedItem({required this.activityId, this.createdAt});

  static FeedItem? fromJson(Map<String, dynamic> json) {
    final id = json['activity_id'] as int? ?? 0;
    final at = _date(json['created_at']);
    return switch (json['kind']) {
      'review' when json['review'] is Map<String, dynamic> => FeedReview(
        activityId: id,
        createdAt: at,
        review: SocialReview.fromJson(json['review'] as Map<String, dynamic>),
      ),
      'list' when json['list'] is Map<String, dynamic> => FeedList(
        activityId: id,
        createdAt: at,
        list: SocialList.fromJson(json['list'] as Map<String, dynamic>),
      ),
      'watched' when json['title'] is Map<String, dynamic> => FeedWatched(
        activityId: id,
        createdAt: at,
        title: titleCardOf(json['title'] as Map<String, dynamic>),
        profiles: _list(json['profiles'], SocialProfile.fromJson),
        profilesCount: json['profiles_count'] as int? ?? 1,
        episodesCount: json['episodes_count'] as int? ?? 0,
        rewatch: json['rewatch'] as bool? ?? false,
      ),
      'liked' when json['title'] is Map<String, dynamic> => FeedLiked(
        activityId: id,
        createdAt: at,
        title: titleCardOf(json['title'] as Map<String, dynamic>),
        profiles: _list(json['profiles'], SocialProfile.fromJson),
        profilesCount: json['profiles_count'] as int? ?? 1,
      ),
      _ => null,
    };
  }

  final int activityId;
  final DateTime? createdAt;
}

class FeedReview extends FeedItem {
  const FeedReview({required super.activityId, super.createdAt, required this.review});

  final SocialReview review;
}

class FeedList extends FeedItem {
  const FeedList({required super.activityId, super.createdAt, required this.list});

  final SocialList list;
}

/// A title watched or liked by one or more profiles (grouped in a page).
sealed class FeedTitle extends FeedItem {
  const FeedTitle({
    required super.activityId,
    super.createdAt,
    required this.title,
    required this.profiles,
    this.profilesCount = 1,
  });

  final MediaItem title;

  /// The first 3 who watched or liked it.
  final List<SocialProfile> profiles;
  final int profilesCount;

  /// « Léa », « Léa et Max », « Léa, Max et 2 autres ».
  String get who {
    final names = [for (final p in profiles) p.name.trim().isEmpty ? '@${p.username}' : p.name];
    final others = profilesCount - names.length;
    return switch (names.length) {
      0 => 'Quelqu’un',
      1 when others <= 0 => names.first,
      2 when others <= 0 => '${names[0]} et ${names[1]}',
      _ when others <= 0 => '${names.sublist(0, names.length - 1).join(', ')} et ${names.last}',
      _ => '${names.join(', ')} et $others ${others > 1 ? 'autres' : 'autre'}',
    };
  }

  /// What comes before the title: « Léa a vu », « Léa et Max aiment ».
  String get sentence;
}

/// A title watched by one or more followed profiles (grouped in a page).
class FeedWatched extends FeedTitle {
  const FeedWatched({
    required super.activityId,
    super.createdAt,
    required super.title,
    required super.profiles,
    super.profilesCount,
    this.episodesCount = 0,
    this.rewatch = false,
  });

  final int episodesCount;
  final bool rewatch;

  /// « Léa a vu », « Léa et Max ont vu », « Léa, Max et 2 autres ont vu », « Léa a vu 3 épisodes de ».
  @override
  String get sentence {
    final verb = profilesCount > 1 ? 'ont' : 'a';
    if (episodesCount > 1 && profilesCount == 1) return '$who $verb vu $episodesCount épisodes de';
    return '$who $verb ${rewatch ? 'revu' : 'vu'}';
  }
}

/// A title liked (« J'aime ») by one or more followed profiles (grouped in a page).
class FeedLiked extends FeedTitle {
  const FeedLiked({
    required super.activityId,
    super.createdAt,
    required super.title,
    required super.profiles,
    super.profilesCount,
  });

  /// « Léa aime », « Léa et Max aiment ».
  @override
  String get sentence => '$who ${profilesCount > 1 ? 'aiment' : 'aime'}';
}

/// A page of the feed and where the next one starts.
typedef FeedPage = ({List<FeedItem> items, int? next});

/// A followed profile who watched or rated a title.
typedef FriendRating = ({SocialProfile profile, double? rating, int? reviewId});

/// The social part of a title page.
@immutable
class TitleSocial {
  const TitleSocial({
    this.friends = const [],
    this.friendsCount = 0,
    this.friendsAverage,
    this.reviews = const [],
    this.reviewsCount = 0,
    this.lists = const [],
  });

  factory TitleSocial.fromJson(Map<String, dynamic> json) => TitleSocial(
    friends: [
      for (final f in (json['friends'] as List? ?? const []).whereType<Map<String, dynamic>>())
        (
          profile: SocialProfile.fromJson(f),
          rating: (f['rating'] as num?)?.toDouble(),
          reviewId: f['review_id'] as int?,
        ),
    ],
    friendsCount: json['friends_count'] as int? ?? 0,
    friendsAverage: (json['friends_average'] as num?)?.toDouble(),
    reviews: _list(json['reviews'], SocialReview.fromJson),
    reviewsCount: json['reviews_count'] as int? ?? 0,
    lists: _list(json['lists'], SocialList.fromJson),
  );

  final List<FriendRating> friends;
  final int friendsCount;
  final double? friendsAverage;
  final List<SocialReview> reviews;
  final int reviewsCount;
  final List<SocialList> lists;

  bool get isEmpty => friends.isEmpty && reviews.isEmpty && lists.isEmpty;
}

/// The « Bilan de l'année ».
@immutable
class YearStats {
  const YearStats({
    required this.year,
    this.entriesCount = 0,
    this.moviesCount = 0,
    this.episodesCount = 0,
    this.showsCount = 0,
    this.rewatchesCount = 0,
    this.minutes = 0,
    this.months = const [],
    this.genres = const [],
    this.ratingsCount = 0,
    this.averageRating,
    this.bestRated = const [],
    this.topShow,
    this.topShowEntries = 0,
  });

  factory YearStats.fromJson(Map<String, dynamic> json) => YearStats(
    year: json['year'] as int? ?? DateTime.now().year,
    entriesCount: json['entries_count'] as int? ?? 0,
    moviesCount: json['movies_count'] as int? ?? 0,
    episodesCount: json['episodes_count'] as int? ?? 0,
    showsCount: json['shows_count'] as int? ?? 0,
    rewatchesCount: json['rewatches_count'] as int? ?? 0,
    minutes: json['minutes'] as int? ?? 0,
    months: [for (final m in json['months'] as List? ?? const []) (m as num).toInt()],
    genres: [
      for (final g in (json['genres'] as List? ?? const []).whereType<Map<String, dynamic>>())
        (name: g['name'] as String? ?? '', count: g['count'] as int? ?? 0),
    ],
    ratingsCount: json['ratings_count'] as int? ?? 0,
    averageRating: (json['average_rating'] as num?)?.toDouble(),
    bestRated: [
      for (final b in (json['best_rated'] as List? ?? const []).whereType<Map<String, dynamic>>())
        (title: titleCardOf(b), value: (b['value'] as num?)?.toDouble() ?? 0),
    ],
    topShow: json['top_show'] is Map<String, dynamic>
        ? titleCardOf({...json['top_show'] as Map<String, dynamic>, 'type': 'tv'})
        : null,
    topShowEntries: (json['top_show'] as Map<String, dynamic>?)?['entries_count'] as int? ?? 0,
  );

  final int year;
  final int entriesCount;
  final int moviesCount;
  final int episodesCount;
  final int showsCount;
  final int rewatchesCount;
  final int minutes;

  /// Entries per month, January first.
  final List<int> months;
  final List<({String name, int count})> genres;
  final int ratingsCount;
  final double? averageRating;
  final List<({MediaItem title, double value})> bestRated;
  final MediaItem? topShow;
  final int topShowEntries;

  int get hours => (minutes / 60).round();
}

/// An account to follow, and why.
typedef Suggestion = ({SocialProfile profile, int? compatibility, String reason});

/// A reason to report, and its text.
typedef ReportReason = ({String reason, String label});

/// What « Signaler » points to.
enum ReportSubject { profile, review, list, comment, message }

/// What a message can carry (« Recommander à un ami »).
typedef ShareTarget = ({String type, String id, String label});

class NetworkRepository {
  NetworkRepository(this._api);

  final ApiClient _api;

  static String _user(String username) => Uri.encodeComponent(username);

  Future<FeedPage> feed({int? before}) async {
    final json = await _api.get('/social/feed', query: {'before': before});
    return (
      items: [
        for (final item in (json['data'] as List? ?? const []).whereType<Map<String, dynamic>>())
          ?FeedItem.fromJson(item),
      ],
      next: json['next'] as int?,
    );
  }

  /// « Pour toi »: the reviews and lists of the whole network, and what the followed profiles
  /// watched and liked, ranked by the API (1 first; `next`: the following page).
  Future<FeedPage> forYou({int page = 1}) async {
    final json = await _api.get('/social/feed/for-you', query: {'page': page});
    return (
      items: [
        for (final item in (json['data'] as List? ?? const []).whereType<Map<String, dynamic>>())
          ?FeedItem.fromJson(item),
      ],
      next: json['next'] as int?,
    );
  }

  /// The « Activité » of a member (or mine): each review, list, title watched or liked, with its
  /// date, the most recent first; `before`: the `next` of the previous page.
  Future<FeedPage> activity(String username, {int? before}) async {
    final json = await _api.get('/social/profiles/${_user(username)}/activity', query: {'before': before});
    return (
      items: [
        for (final item in (json['data'] as List? ?? const []).whereType<Map<String, dynamic>>())
          ?FeedItem.fromJson(item),
      ],
      next: json['next'] as int?,
    );
  }

  Future<List<Suggestion>> suggestions() async {
    final json = await _api.get('/social/suggestions');
    return [
      for (final s in (json['data'] as List? ?? const []).whereType<Map<String, dynamic>>())
        (
          profile: SocialProfile.fromJson(s),
          compatibility: s['compatibility'] as int?,
          reason: s['reason'] as String? ?? '',
        ),
    ];
  }

  /// My lists; with [item] (`movie:550`), which ones have it.
  Future<List<SocialList>> myLists({String? item}) async =>
      _list((await _api.get('/social/lists', query: {'item': item}))['data'], SocialList.fromJson);

  Future<List<SocialList>> memberLists(String username) async =>
      _list((await _api.get('/social/profiles/${_user(username)}/lists'))['data'], SocialList.fromJson);

  Future<SocialList> list(int id) async =>
      SocialList.fromJson((await _api.get('/social/lists/$id'))['data'] as Map<String, dynamic>);

  Future<SocialList> createList({required String title, String? description, List<String> items = const []}) async =>
      SocialList.fromJson(
        (await _api.post('/social/lists', body: {'title': title, 'description': description, 'items': items}))['data']
            as Map<String, dynamic>,
      );

  /// Changes a list; [items] (all of them, in order) when given.
  Future<SocialList> updateList(int id, {required String title, String? description, List<String>? items}) async =>
      SocialList.fromJson(
        (await _api.put(
              '/social/lists/$id',
              body: {'title': title, 'description': description, 'items': ?items},
            ))['data']
            as Map<String, dynamic>,
      );

  Future<void> deleteList(int id) => _api.delete('/social/lists/$id');

  Future<SocialList> addToList(int id, String item) async => SocialList.fromJson(
    (await _api.post('/social/lists/$id/items', body: {'item': item}))['data'] as Map<String, dynamic>,
  );

  Future<SocialList> removeFromList(int id, MediaItem title) async => SocialList.fromJson(
    (await _api.delete('/social/lists/$id/items/${title.type.name}/${title.id}'))['data'] as Map<String, dynamic>,
  );

  Future<({bool liked, int likesCount})> likeList(int id, {required bool liked}) async {
    final json = liked ? await _api.put('/social/lists/$id/like') : await _api.delete('/social/lists/$id/like');
    return (liked: json['liked'] as bool? ?? liked, likesCount: json['likes_count'] as int? ?? 0);
  }

  Future<SocialReview> review(int id) async =>
      SocialReview.fromJson((await _api.get('/social/reviews/$id'))['data'] as Map<String, dynamic>);

  static String _comments(CommentSubject subject) =>
      subject.list ? '/social/lists/${subject.id}/comments' : '/social/reviews/${subject.id}/comments';

  Future<({List<SocialComment> comments, bool hasMore})> comments(CommentSubject subject, {int? before}) async {
    final json = await _api.get(_comments(subject), query: {'before': before});
    return (comments: _list(json['data'], SocialComment.fromJson), hasMore: json['has_more'] as bool? ?? false);
  }

  Future<SocialComment> comment(CommentSubject subject, String body, {bool spoilers = false}) async =>
      SocialComment.fromJson(
        (await _api.post(_comments(subject), body: {'body': body, 'contains_spoilers': spoilers}))['data']
            as Map<String, dynamic>,
      );

  Future<void> deleteComment(int id) => _api.delete('/social/comments/$id');

  Future<TitleSocial> titleSocial(TitleRef title) async => TitleSocial.fromJson(
    (await _api.get('/social/titles/${title.type.name}/${title.id}'))['data'] as Map<String, dynamic>,
  );

  /// Every review of a title (with a comment), the most liked first ([popular]) or the most recent.
  Future<({List<SocialReview> reviews, bool hasMore})> titleReviews(
    TitleRef title, {
    bool popular = true,
    int page = 1,
  }) async {
    final json = await _api.get(
      '/social/titles/${title.type.name}/${title.id}/reviews',
      query: {'sort': popular ? 'popular' : 'recent', 'page': page},
    );
    final meta = json['meta'] is Map ? json['meta'] as Map : const {};
    return (
      reviews: _list(json['data'], SocialReview.fromJson),
      hasMore: (meta['current_page'] as int? ?? 1) < (meta['last_page'] as int? ?? 1),
    );
  }

  Future<YearStats> stats(String username, int year) async => YearStats.fromJson(
    (await _api.get('/social/profiles/${_user(username)}/stats', query: {'year': year}))['data']
        as Map<String, dynamic>,
  );

  /// A viewing (an episode watched to the end): in the profile's « Activité » and the feed.
  Future<void> logViewing(int profileId, MediaItem title, {int? season, int? episode}) => _api.post(
    '/profiles/$profileId/diary',
    body: {'item': itemIdOf(title.type, title.id), 'season_number': ?season, 'episode_number': ?episode},
  );

  Future<void> block(String username, {required bool blocked}) => blocked
      ? _api.post('/social/profiles/${_user(username)}/block')
      : _api.delete('/social/profiles/${_user(username)}/block');

  Future<void> mute(String username, {required bool muted}) => muted
      ? _api.post('/social/profiles/${_user(username)}/mute')
      : _api.delete('/social/profiles/${_user(username)}/mute');

  Future<({List<SocialProfile> blocked, List<SocialProfile> muted})> hiddenAccounts() async {
    final json = await _api.get('/social/hidden');
    return (blocked: _list(json['blocked'], SocialProfile.fromJson), muted: _list(json['muted'], SocialProfile.fromJson));
  }

  Future<List<ReportReason>> reportReasons() async {
    final json = await _api.get('/social/report-reasons');
    return [
      for (final r in (json['data'] as List? ?? const []).whereType<Map<String, dynamic>>())
        (reason: r['reason'] as String? ?? 'other', label: r['label'] as String? ?? ''),
    ];
  }

  Future<void> report(ReportSubject subject, int id, String reason, {String? details}) => _api.post(
    '/social/reports',
    body: {'type': subject.name, 'id': id, 'reason': reason, 'details': ?details},
  );

  /// Sends [share] in a conversation (« Recommander à un ami »), with an optional text.
  Future<void> share(int conversationId, ShareTarget share, {String? body}) => _api.post(
    '/messages/$conversationId',
    body: {
      if (body != null && body.trim().isNotEmpty) 'body': body.trim(),
      'share': {'type': share.type, 'id': share.id},
    },
  );
}

final networkRepositoryProvider = Provider<NetworkRepository>((ref) => NetworkRepository(ref.read(apiClientProvider)));

/// The reasons to report, from the API (a fallback when it can't be reached).
const fallbackReportReasons = <ReportReason>[
  (reason: 'spam', label: 'Spam ou publicité'),
  (reason: 'harassment', label: 'Harcèlement ou intimidation'),
  (reason: 'hate', label: 'Discours haineux'),
  (reason: 'sexual', label: 'Contenu sexuel'),
  (reason: 'violence', label: 'Violence ou menaces'),
  (reason: 'spoiler', label: 'Spoiler non signalé'),
  (reason: 'illegal', label: 'Contenu illégal'),
  (reason: 'other', label: 'Autre raison'),
];

/// The two tabs of « Fil d'actualité » (developer's request, 23/11/2026): « Pour toi » (the
/// default) and « Abonnements ».
enum FeedTab {
  forYou('Pour toi'),
  following('Abonnements');

  const FeedTab(this.label);

  final String label;
}

/// A tab of the feed, page after page. `ref.invalidate(feedProvider)` reloads both.
final feedProvider = AsyncNotifierProvider.autoDispose.family<Feed, FeedPage, FeedTab>(Feed.new);

class Feed extends AsyncNotifier<FeedPage> {
  Feed(this.tab);

  final FeedTab tab;
  bool _loading = false;

  @override
  Future<FeedPage> build() {
    ref.watch(sessionProvider.select((s) => s.profile?.id));
    return _page(null);
  }

  /// « Pour toi » is paged by number, « Abonnements » by the last activity.
  Future<FeedPage> _page(int? next) {
    final repository = ref.read(networkRepositoryProvider);
    return switch (tab) {
      FeedTab.forYou => repository.forYou(page: next ?? 1),
      FeedTab.following => repository.feed(before: next),
    };
  }

  bool get hasMore => state.value?.next != null;

  /// The next page, added at the end.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.next == null || _loading) return;
    _loading = true;
    try {
      final page = await _page(current.next);
      if (!ref.mounted) return;
      state = AsyncData((items: [...current.items, ...page.items], next: page.next));
    } catch (_) {
      // Kept as it is: « Afficher plus » tries again.
    } finally {
      _loading = false;
    }
  }

  /// A review or a list changed (a like): the same everywhere in the feed.
  void replace({SocialReview? review, SocialList? list}) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData((
      items: [
        for (final item in current.items)
          switch (item) {
            FeedReview() when review != null && item.review.id == review.id => FeedReview(
              activityId: item.activityId,
              createdAt: item.createdAt,
              review: review,
            ),
            FeedList() when list != null && item.list.id == list.id => FeedList(
              activityId: item.activityId,
              createdAt: item.createdAt,
              list: list,
            ),
            _ => item,
          },
      ],
      next: current.next,
    ));
  }
}

/// Accounts to follow.
final suggestionsProvider = FutureProvider.autoDispose<List<Suggestion>>(
  (ref) => ref.read(networkRepositoryProvider).suggestions(),
);

/// My lists; with an item id (`movie:550`), which ones have it.
final myListsProvider = FutureProvider.autoDispose.family<List<SocialList>, String?>((ref, item) {
  ref.watch(sessionProvider.select((s) => s.profile?.id));
  return ref.read(networkRepositoryProvider).myLists(item: item);
});

/// A member's lists.
final memberListsProvider = FutureProvider.autoDispose.family<List<SocialList>, String>(
  (ref, username) => ref.read(networkRepositoryProvider).memberLists(username),
);

/// A list, with its titles.
final listProvider = FutureProvider.autoDispose.family<SocialList, int>(
  (ref, id) => ref.read(networkRepositoryProvider).list(id),
);

/// A review as a publication.
final socialReviewProvider = FutureProvider.autoDispose.family<SocialReview, int>(
  (ref, id) => ref.read(networkRepositoryProvider).review(id),
);

/// The social part of a title page (needs a profile with social features).
final titleSocialProvider = FutureProvider.autoDispose.family<TitleSocial, TitleRef>((ref, title) {
  if (!socialAvailable(ref.watch(sessionProvider))) return Future.value(const TitleSocial());
  return ref.read(networkRepositoryProvider).titleSocial(title);
});

/// A member's « Bilan de l'année ».
final yearStatsProvider = FutureProvider.autoDispose.family<YearStats, ({String username, int year})>(
  (ref, key) => ref.read(networkRepositoryProvider).stats(key.username, key.year),
);

/// The « Activité » of a member (or mine), by username, page after page.
final activityProvider = AsyncNotifierProvider.autoDispose.family<ProfileActivity, FeedPage, String>(
  ProfileActivity.new,
);

class ProfileActivity extends AsyncNotifier<FeedPage> {
  ProfileActivity(this.username);

  final String username;
  bool _loading = false;

  @override
  Future<FeedPage> build() => ref.read(networkRepositoryProvider).activity(username);

  bool get hasMore => state.value?.next != null;

  /// The next page, added at the end.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.next == null || _loading) return;
    _loading = true;
    try {
      final page = await ref.read(networkRepositoryProvider).activity(username, before: current.next);
      if (!ref.mounted) return;
      state = AsyncData((items: [...current.items, ...page.items], next: page.next));
    } catch (_) {
      // Kept as it is: « Afficher plus » tries again.
    } finally {
      _loading = false;
    }
  }
}

/// Blocked and muted accounts (« Comptes bloqués et masqués »).
final hiddenAccountsProvider = FutureProvider.autoDispose(
  (ref) => ref.read(networkRepositoryProvider).hiddenAccounts(),
);

/// The comments of a review or a list: read, then added or deleted here.
final commentsProvider = AsyncNotifierProvider.autoDispose
    .family<CommentsController, ({List<SocialComment> comments, bool hasMore}), CommentSubject>(
      CommentsController.new,
    );

class CommentsController extends AsyncNotifier<({List<SocialComment> comments, bool hasMore})> {
  CommentsController(this.subject);

  final CommentSubject subject;

  @override
  Future<({List<SocialComment> comments, bool hasMore})> build() =>
      ref.read(networkRepositoryProvider).comments(subject);

  /// Older comments, above.
  Future<void> loadOlder() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.comments.isEmpty) return;
    final page = await ref.read(networkRepositoryProvider).comments(subject, before: current.comments.first.id);
    if (!ref.mounted) return;
    state = AsyncData((comments: [...page.comments, ...current.comments], hasMore: page.hasMore));
  }

  Future<void> add(String body, {bool spoilers = false}) async {
    final comment = await ref.read(networkRepositoryProvider).comment(subject, body, spoilers: spoilers);
    if (!ref.mounted) return;
    final current = state.value;
    state = AsyncData((comments: [...?current?.comments, comment], hasMore: current?.hasMore ?? false));
  }

  Future<void> delete(SocialComment comment) async {
    await ref.read(networkRepositoryProvider).deleteComment(comment.id);
    if (!ref.mounted) return;
    final current = state.value;
    if (current == null) return;
    state = AsyncData((comments: [for (final c in current.comments) if (c.id != comment.id) c], hasMore: current.hasMore));
  }
}
