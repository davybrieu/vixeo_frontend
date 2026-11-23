import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vixeo/core/api/api_client.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/core/widgets/focusable.dart';
import 'package:vixeo/features/auth/auth_repository.dart';
import 'package:vixeo/features/auth/models.dart';
import 'package:vixeo/features/auth/session.dart';
import 'package:vixeo/features/catalog/models.dart';
import 'package:vixeo/features/messages/messages.dart';
import 'package:vixeo/features/network/comments.dart';
import 'package:vixeo/features/network/feed_screen.dart';
import 'package:vixeo/features/network/network.dart';
import 'package:vixeo/features/network/rate_prompt.dart';
import 'package:vixeo/features/network/widgets.dart';
import 'package:vixeo/features/profiles/avatars.dart';
import 'package:vixeo/features/profiles/profile_preferences_screen.dart';
import 'package:vixeo/features/social/social_repository.dart';

// The social network of movies and TV shows (developer's request, 23/11/2026;
// vixeo_backend/docs/social.md): models, the feed, comments with spoilers, and the rating
// proposed at the end of playback with its setting.

class _Session extends SessionController {
  _Session([this.profile = const Profile(id: 2, name: 'Léa', username: 'lea')]);

  final Profile profile;

  @override
  SessionState build() => SessionState(status: SessionStatus.signedIn, token: 't', profile: profile);
}

class _NoUnreadMessages extends UnreadMessages {
  @override
  int build() => 0;

  @override
  Future<void> refresh({bool force = false}) async {}
}

const _lea = {'id': 2, 'username': 'lea', 'name': 'Léa', 'avatar': null};
const _max = {'id': 7, 'username': 'max', 'name': 'Max', 'avatar': null};

Map<String, dynamic> _review({int id = 31, bool spoilers = false, String comment = 'Une claque visuelle.'}) => {
  'review_id': id,
  'type': 'movie',
  'id': 693134,
  'title': 'Dune : Deuxième Partie',
  'year': 2024,
  'value': 9,
  'comment': comment,
  'rated_at': '2026-11-22T20:00:00+00:00',
  'poster_url': null,
  'likes_count': 4,
  'liked': false,
  'author': _max,
  'contains_spoilers': spoilers,
  'comments_count': 2,
  'is_mine': false,
};

const _list = {
  'id': 3,
  'author': _max,
  'title': 'Mon top 10 de 2026',
  'description': 'Les meilleurs de l’année.',
  'kind': 'top',
  'items_count': 7,
  'cover': <String>[],
  'likes_count': 12,
  'liked': true,
  'comments_count': 1,
  'is_mine': false,
  'updated_at': '2026-11-23T08:00:00+00:00',
};

class _FakeNetwork extends NetworkRepository {
  _FakeNetwork() : super(ApiClient(token: () => null, profileId: () => null));

  final calls = <String>[];
  final comments = <SocialComment>[];

  @override
  Future<FeedPage> feed({int? before}) async => (
    items: [
      FeedItem.fromJson({'kind': 'review', 'activity_id': 10, 'created_at': '2026-11-23T09:00:00+00:00', 'review': _review()})!,
      FeedItem.fromJson({'kind': 'list', 'activity_id': 9, 'list': _list})!,
      FeedItem.fromJson({
        'kind': 'watched',
        'activity_id': 8,
        'title': {'type': 'movie', 'id': 550, 'title': 'Fight Club', 'year': 1999},
        'profiles': [_lea, _max],
        'profiles_count': 2,
      })!,
    ],
    next: null,
  );

  @override
  Future<List<Suggestion>> suggestions() async => [
    (profile: SocialProfile.fromJson(const {'id': 9, 'username': 'nina', 'name': 'Nina'}), compatibility: 82, reason: ''),
  ];

  @override
  Future<({List<SocialComment> comments, bool hasMore})> comments(CommentSubject subject, {int? before}) async =>
      (comments: List.of(comments), hasMore: false);

  @override
  Future<SocialComment> comment(CommentSubject subject, String body, {bool spoilers = false}) async {
    calls.add('comment ${subject.list ? 'list' : 'review'} ${subject.id}: $body${spoilers ? ' (spoilers)' : ''}');
    return SocialComment(
      id: 50,
      author: SocialProfile.fromJson(_lea),
      body: body,
      spoilers: spoilers,
      isMine: true,
      canDelete: true,
    );
  }
}

class _FakeProfiles extends AuthRepository {
  _FakeProfiles() : super(ApiClient(token: () => null, profileId: () => null));

  final updates = <Map<String, Object?>>[];

  @override
  Future<Profile> updateProfile(int profileId, Map<String, Object?> fields) async {
    updates.add(fields);
    return Profile.fromJson({'id': 2, 'name': 'Léa', 'username': 'lea', ...fields});
  }
}

Finder _pressable(String label) =>
    find.byWidgetPredicate((widget) => widget is VxFocusable && widget.semanticLabel == label);

Future<_FakeNetwork> _pump(WidgetTester tester, Widget home, {List<Override> overrides = const []}) async {
  tester.view.physicalSize = const Size(430, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final network = _FakeNetwork();
  Widget page(String text) => Scaffold(body: Text(text));
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => Scaffold(body: home)),
      GoRoute(path: '/messages', builder: (_, _) => page('Page Messages')),
      GoRoute(path: '/avis/:id', builder: (_, state) => page('Avis ${state.pathParameters['id']}')),
      GoRoute(path: '/listes/:id', builder: (_, state) => page('Liste ${state.pathParameters['id']}')),
      GoRoute(path: '/titre/:type/:id', builder: (_, state) => page('Fiche ${state.pathParameters['id']}')),
      GoRoute(path: '/membre/:username', builder: (_, state) => page('Membre ${state.pathParameters['username']}')),
      GoRoute(path: '/profil/parametres', builder: (_, state) => page('Paramètres ${state.uri.query}')),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWith(_Session.new),
        networkRepositoryProvider.overrideWithValue(network),
        unreadMessagesProvider.overrideWith(_NoUnreadMessages.new),
        avatarCatalogProvider.overrideWith((ref) async => const <AvatarLicense>[]),
        ...overrides,
      ],
      child: MaterialApp.router(theme: buildVixeoTheme(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return network;
}

void main() {
  group('models', () {
    test('a review, a list and a title watched, from the feed', () {
      final review = FeedItem.fromJson({'kind': 'review', 'activity_id': 1, 'review': _review(spoilers: true)});
      expect(review, isA<FeedReview>());
      final post = (review! as FeedReview).review;
      expect(post.id, 31);
      expect(post.author.username, 'max');
      expect(post.spoilers, isTrue);
      expect(post.commentsCount, 2);
      expect(post.item.likesCount, 4);
      expect(post.title.title, 'Dune : Deuxième Partie');

      final list = SocialList.fromJson(_list);
      expect(list.kind, ListKind.top);
      expect(list.kind.maxItems, 10);
      expect(list.summary, 'Top 10 · 7 titres');
      expect(list.copyWith(liked: false, likesCount: 11).likesCount, 11);

      FeedWatched watched(List<Map<String, dynamic>> profiles, int count, {int episodes = 0}) =>
          FeedItem.fromJson({
                'kind': 'watched',
                'activity_id': 2,
                'title': {'type': 'tv', 'id': 1399, 'title': 'Les Hautes Terres'},
                'profiles': profiles,
                'profiles_count': count,
                'episodes_count': episodes,
              })!
              as FeedWatched;
      expect(watched([_lea], 1).sentence, 'Léa a vu');
      expect(watched([_lea, _max], 2).sentence, 'Léa et Max ont vu');
      expect(watched([_lea, _max], 4).sentence, 'Léa, Max et 2 autres ont vu');
      expect(watched([_lea], 1, episodes: 3).sentence, 'Léa a vu 3 épisodes de');
      expect(watched([_lea], 1).title.type, MediaType.tv);
      // A kind this app doesn't know: not shown.
      expect(FeedItem.fromJson({'kind': 'tweet', 'activity_id': 3}), isNull);
    });

    test('the social part of a title, the diary and the year', () {
      final social = TitleSocial.fromJson({
        'friends': [
          {..._max, 'rating': 8.5, 'review_id': 31},
        ],
        'friends_count': 3,
        'friends_average': 7.8,
        'reviews': [_review()],
        'reviews_count': 12,
        'lists': [_list],
      });
      expect(social.friends.single.rating, 8.5);
      expect(social.friends.single.reviewId, 31);
      expect(social.friendsAverage, 7.8);
      expect(social.isEmpty, isFalse);
      expect(const TitleSocial().isEmpty, isTrue);

      final entry = DiaryEntry.fromJson({
        'id': 1,
        'type': 'tv',
        'tmdb_id': 1399,
        'title': 'Les Hautes Terres',
        'season_number': 2,
        'episode_number': 5,
        'watched_at': '2026-11-20T21:00:00+00:00',
        'rewatch': true,
        'rating': 9,
      });
      expect(entry.episodeLabel, 'Saison 2, épisode 5');
      expect(entry.rewatch, isTrue);
      expect(entry.watchedAt.isUtc, isFalse);

      final year = YearStats.fromJson({
        'year': 2026,
        'entries_count': 40,
        'movies_count': 12,
        'episodes_count': 28,
        'minutes': 3000,
        'months': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 0],
        'genres': [
          {'name': 'Drame', 'count': 9},
        ],
        'best_rated': [
          {'type': 'movie', 'id': 550, 'title': 'Fight Club', 'value': 10},
        ],
        'top_show': {'id': 1399, 'title': 'Les Hautes Terres', 'entries_count': 20},
      });
      expect(year.hours, 50);
      expect(year.months, hasLength(12));
      expect(year.genres.single.name, 'Drame');
      expect(year.bestRated.single.title.id, 550);
      expect(year.topShow?.type, MediaType.tv);
      expect(year.topShowEntries, 20);
    });

    test('a title, a review or a list sent in a message', () {
      final title = SharedCard.fromJson(const {
        'type': 'title',
        'media_type': 'movie',
        'id': 550,
        'title': 'Fight Club',
        'year': 1999,
        'poster_url': 'https://image.tmdb.org/t/p/w342/f.jpg',
      });
      expect(title.path, '/titre/movie/550');
      expect(title.subtitle, 'Film · 1999');
      expect(title.images, hasLength(1));

      final review = SharedCard.fromJson(const {
        'type': 'review',
        'review_id': 31,
        'title': 'Les Hautes Terres',
        'season_number': 1,
        'episode_number': 2,
        'value': 8.5,
        'excerpt': 'Superbe.',
        'author': _max,
      });
      expect(review.path, '/avis/31');
      expect(review.title, 'Les Hautes Terres · S1 · É2');
      expect(review.subtitle, 'Avis de @max · ★ 8,5/10');

      final list = SharedCard.fromJson(const {'type': 'list', 'list_id': 3, 'title': 'Top', 'kind': 'top', 'items_count': 10});
      expect(list.path, '/listes/3');
      expect(list.subtitle, 'Top 10 · 10 titres');

      final message = ChatMessage.fromJson(const {
        'id': 1,
        'sender_profile_id': 7,
        'body': '',
        'shared': {'type': 'list', 'list_id': 3, 'title': 'Top', 'kind': 'list', 'items_count': 1},
      });
      expect(message.shared?.kind, 'list');
      expect(ChatMessage.fromJson(const {'id': 2, 'sender_profile_id': 7, 'body': 'Salut'}).shared, isNull);
    });

    test('the end of playback: the credits of a video of 3 minutes or more', () {
      const movie = Duration(minutes: 120);
      // 8 % of the movie, 5 minutes at most.
      expect(atTheEnd(const Duration(minutes: 114), movie), isFalse);
      expect(atTheEnd(const Duration(minutes: 115), movie), isTrue);
      const episode = Duration(minutes: 40);
      expect(atTheEnd(const Duration(minutes: 36), episode), isFalse);
      expect(atTheEnd(const Duration(minutes: 37, seconds: 30), episode), isTrue);
      // Too short (a trailer), or no duration (live).
      expect(atTheEnd(const Duration(minutes: 2), const Duration(minutes: 2)), isFalse);
      expect(atTheEnd(Duration.zero, Duration.zero), isFalse);
    });

    test('a profile proposes to rate at the end by default', () {
      expect(Profile.fromJson({'id': 1, 'name': 'A'}).rateAfterWatching, isTrue);
      expect(Profile.fromJson({'id': 1, 'name': 'A', 'rate_after_watching': false}).rateAfterWatching, isFalse);
      // An older API: no first launch.
      expect(Profile.fromJson({'id': 1, 'name': 'A'}).onboarded, isTrue);
      final pinned = Profile.fromJson({
        'id': 1,
        'name': 'A',
        'onboarded': false,
        'pinned_titles': [
          {'type': 'tv', 'id': 1399, 'title': 'Les Hautes Terres'},
        ],
      });
      expect(pinned.onboarded, isFalse);
      expect(pinned.pinnedTitles.single.type, MediaType.tv);
    });
  });

  testWidgets('« Fil »: reviews, lists and titles watched by the followed members, accounts to follow', (tester) async {
    await _pump(tester, const FeedScreen());

    expect(find.text('Fil'), findsOneWidget);
    // A review: its author, its title, its stars, its comment.
    expect(find.text('Max'), findsWidgets);
    expect(find.text('Dune : Deuxième Partie'), findsOneWidget);
    expect(find.text('9/10'), findsOneWidget);
    expect(find.text('Une claque visuelle.'), findsOneWidget);
    // A top 10.
    expect(find.text('TOP 10'), findsOneWidget);
    expect(find.text('Mon top 10 de 2026'), findsOneWidget);
    expect(find.text('Top 10 · 7 titres'), findsOneWidget);
    // Watched, grouped.
    expect(find.textContaining('Léa et Max ont vu'), findsOneWidget);
    // Accounts to follow.
    expect(find.text('Comptes à suivre'), findsOneWidget);
    expect(find.text('82 % de goûts en commun'), findsOneWidget);

    // « Messages » is the round button of the header (phone).
    await tester.tap(_pressable('Messages'));
    await tester.pumpAndSettle();
    expect(find.text('Page Messages'), findsOneWidget);
  });

  testWidgets('a post opens its review, its list or its title', (tester) async {
    await _pump(tester, const FeedScreen());
    await tester.tap(find.text('Une claque visuelle.'));
    await tester.pumpAndSettle();
    expect(find.text('Avis 31'), findsOneWidget);

    await _pump(tester, const FeedScreen());
    await tester.tap(find.text('Mon top 10 de 2026'));
    await tester.pumpAndSettle();
    expect(find.text('Liste 3'), findsOneWidget);

    await _pump(tester, const FeedScreen());
    await tester.tap(find.textContaining('Léa et Max ont vu'));
    await tester.pumpAndSettle();
    expect(find.text('Fiche 550'), findsOneWidget);
  });

  testWidgets('spoilers stay hidden until « Afficher »', (tester) async {
    await _pump(
      tester,
      ReviewPostHarness(review: SocialReview.fromJson(_review(spoilers: true, comment: 'Le héros meurt à la fin.'))),
    );
    expect(find.text('Le héros meurt à la fin.'), findsNothing);
    await tester.tap(_pressable('Contient des spoilers. Afficher'));
    await tester.pumpAndSettle();
    expect(find.text('Le héros meurt à la fin.'), findsOneWidget);
  });

  testWidgets('a comment, with « Contient des spoilers »', (tester) async {
    final network = await _pump(
      tester,
      const SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: CommentsSection(subject: (list: false, id: 31)),
      ),
    );
    expect(find.text('Aucun commentaire pour l’instant : lancez la conversation.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Je ne m’y attendais pas !');
    await tester.tap(_pressable('Contient des spoilers, désactivé'));
    await tester.pump();
    await tester.tap(find.text('Publier'));
    await tester.pumpAndSettle();
    expect(network.calls, ['comment review 31: Je ne m’y attendais pas ! (spoilers)']);
    // Mine: shown as written.
    expect(find.text('Je ne m’y attendais pas !'), findsOneWidget);
  });

  testWidgets('the end of a movie: « Noter », « Plus tard », and the way to the setting', (tester) async {
    var closed = 0;
    final finished = (
      title: const MediaItem(id: 550, type: MediaType.movie, title: 'Fight Club'),
      season: null,
      episode: null,
    );
    await _pump(tester, RateAfterWatchingCard(finished: finished, onClose: () => closed++));

    expect(find.text('Vous avez terminé'), findsOneWidget);
    expect(find.text('Fight Club'), findsOneWidget);
    await tester.tap(find.text('Plus tard'));
    await tester.pump();
    expect(closed, 1);

    await tester.tap(_pressable('Ne plus proposer de noter : désactiver dans les paramètres'));
    await tester.pumpAndSettle();
    // « Paramètres du profil », on « Proposer de noter à la fin ».
    expect(find.text('Paramètres reglage=noter'), findsOneWidget);
  });

  testWidgets('« Proposer de noter à la fin » can be turned off, and has the focus when asked', (tester) async {
    final auth = _FakeProfiles();
    tester.view.physicalSize = const Size(520, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          sessionProvider.overrideWith(_Session.new),
        ],
        child: MaterialApp(theme: buildVixeoTheme(), home: const ProfilePreferencesScreen(setting: 'noter')),
      ),
    );
    await tester.pumpAndSettle();

    final row = _pressable('Proposer de noter à la fin, activé');
    expect(row, findsOneWidget);
    expect(tester.widget<VxFocusable>(row).autofocus, isTrue);
    expect(tester.widget<VxFocusable>(_pressable('Format des affiches : Vertical')).autofocus, isFalse);

    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(auth.updates, [
      {'rate_after_watching': false},
    ]);
    expect(find.text('Note plus proposée à la fin de la lecture'), findsOneWidget);
  });
}

/// A review post alone on a page.
class ReviewPostHarness extends StatelessWidget {
  const ReviewPostHarness({super.key, required this.review});

  final SocialReview review;

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [ReviewPost(review: review)]);
}
