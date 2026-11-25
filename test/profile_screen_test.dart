import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:vixeo/core/share.dart';
import 'package:vixeo/router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vixeo/core/api/api_client.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/core/widgets/focusable.dart';
import 'package:vixeo/features/auth/models.dart';
import 'package:vixeo/features/auth/session.dart';
import 'package:vixeo/features/catalog/catalog_repository.dart';
import 'package:vixeo/features/catalog/models.dart';
import 'package:vixeo/features/catalog/widgets.dart';
import 'package:vixeo/features/library/library.dart';
import 'package:vixeo/features/library/my_list_screen.dart';
import 'package:vixeo/features/network/network.dart';
import 'package:vixeo/features/notifications/inbox.dart';
import 'package:vixeo/features/profiles/avatars.dart';
import 'package:vixeo/features/profiles/profile_settings_screen.dart';
import 'package:vixeo/features/social/profile_screen.dart';
import 'package:vixeo/features/social/profile_view.dart';
import 'package:vixeo/features/social/review_likes.dart';
import 'package:vixeo/features/social/social_links.dart';
import 'package:vixeo/features/social/social_search.dart';
import 'package:vixeo/features/social/social_repository.dart';
import 'package:vixeo/features/tmdb/reviews_screen.dart';
import 'package:vixeo/features/tmdb/tmdb.dart';

const _user = User(id: 1, name: 'Davy', email: 'davy@exemple.fr', parentalControl: false);

class _Signed extends SessionController {
  @override
  SessionState build() => SessionState(
    status: SessionStatus.signedIn,
    token: 't',
    user: _user,
    profile: Profile.fromJson({'id': 2, 'name': 'Léa', 'username': 'lea', 'bio': 'Fan de science-fiction.'}),
  );
}

/// A child's profile: no page of its own.
class _Kid extends SessionController {
  @override
  SessionState build() => SessionState(
    status: SessionStatus.signedIn,
    token: 't',
    user: _user,
    profile: Profile.fromJson({'id': 3, 'name': 'Tom', 'is_kid': true}),
  );
}

class _Library extends LibraryController {
  @override
  Future<LibraryState> build() async => LibraryState({
    'tmdb|movie:438631': ProfileItem(
      source: 'tmdb',
      itemId: 'movie:438631',
      type: 'movie',
      title: 'Dune',
      year: 2021,
      isFavorite: true,
      favoritedAt: DateTime(2026, 11, 10),
    ),
    'tmdb|tv:1399': ProfileItem(
      source: 'tmdb',
      itemId: 'tv:1399',
      type: 'tv',
      title: 'Les Hautes Terres',
      year: 2011,
      isFavorite: true,
      favoritedAt: DateTime(2026, 11, 12),
    ),
    // Watched only: not « À voir ».
    'tmdb|movie:550': ProfileItem(
      source: 'tmdb',
      itemId: 'movie:550',
      type: 'movie',
      title: 'Fight Club',
      isWatched: true,
      watchedAt: DateTime(2026, 11, 11),
    ),
    // In « J'aime » ❤ only.
    'tmdb|movie:13': ProfileItem(
      source: 'tmdb',
      itemId: 'movie:13',
      type: 'movie',
      title: 'Forrest Gump',
      isLiked: true,
      likedAt: DateTime(2026, 11, 13),
    ),
    'tmdb|person:287': ProfileItem(
      source: 'tmdb',
      itemId: 'person:287',
      type: 'person',
      title: 'Brad Pitt',
      isFollowed: true,
      followedAt: DateTime(2026, 11, 14),
    ),
  });
}

class _Tmdb extends TmdbRepository {
  _Tmdb() : super(ApiClient(token: () => null, profileId: () => null));

  @override
  Future<Paged<RatedItem>> reviews(
    int profileId, {
    RatedType? type,
    RatedOrder order = RatedOrder.recent,
    int page = 1,
  }) async => Paged(
    items: [
      for (var i = 1; i <= 5; i++)
        RatedItem(
          type: RatedType.movie,
          id: i,
          title: 'Film noté $i',
          value: 7,
          comment: i == 1 ? 'Superbe.' : null,
          reviewId: 100 + i,
          likesCount: i == 1 ? 4 : 0,
        ),
    ],
    totalResults: 5,
  );
}

const _social = SocialProfile(
  id: 2,
  username: 'lea',
  name: 'Léa',
  followersCount: 12,
  followingCount: 1,
  reviewsCount: 5,
  watchedCount: 34,
  listCount: 2,
  episodesCount: 42,
  // 5 days and 9 hours.
  watchMinutes: (5 * 24 + 9) * 60 + 12,
);

/// The « Activité » and the lists of a profile, without the network.
class _FakeNetwork extends NetworkRepository {
  _FakeNetwork() : super(ApiClient(token: () => null, profileId: () => null));

  @override
  Future<FeedPage> activity(String username, {int? before}) async => (
    items: [
      FeedItem.fromJson({
        'kind': 'liked',
        'activity_id': 4,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'title': {'type': 'movie', 'id': 603, 'title': 'Matrix'},
        'profiles': [
          {'id': 2, 'username': username, 'name': username},
        ],
      })!,
    ],
    next: null,
  );

  static final _lists = [
    SocialList.fromJson(const {
      'id': 3,
      'author': {'id': 2, 'username': 'lea', 'name': 'Léa'},
      'title': 'Top 10 de 2026',
      'items_count': 7,
      'is_mine': true,
    }),
  ];

  @override
  Future<Paged<SocialList>> myLists({String? item, int page = 1}) async => Paged(items: _lists);

  @override
  Future<Paged<SocialList>> memberLists(String username, {int page = 1}) async => Paged(items: _lists);
}

/// 3 unread notifications, nothing asked to the server.
class _ThreeUnread extends UnreadNotifications {
  @override
  int build() => 3;

  @override
  Future<void> refresh({bool force = false}) async {}
}

/// Opens the tab [label] of a profile page (« Activité », « Listes », « Avis », « Aimés », « Vus »).
Future<void> _tab(WidgetTester tester, String label) async {
  await tester.tap(
    find.byWidgetPredicate((w) => w is VxFocusable && (w.semanticLabel ?? '').startsWith('$label, onglet')),
  );
  await tester.pumpAndSettle();
}

/// The button (or link) read [label] by screen readers.
Finder _pressable(String label) =>
    find.byWidgetPredicate((widget) => widget is VxFocusable && widget.semanticLabel == label);

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(430, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  Widget page(String text) => Scaffold(body: Text(text));
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const Scaffold(body: ProfileScreen())),
      GoRoute(path: '/listes/a-voir', builder: (_, _) => page('Page À voir')),
      GoRoute(path: '/listes/:id', builder: (_, state) => page('Liste ${state.pathParameters['id']}')),
      GoRoute(path: '/titre/:type/:id', builder: (_, state) => page('Fiche ${state.pathParameters['id']}')),
      GoRoute(path: '/avis', builder: (_, _) => page('Page Mes avis')),
      GoRoute(path: '/parametres', builder: (_, _) => page('Page Paramètres')),
      GoRoute(path: '/notifications', builder: (_, _) => page('Page Notifications')),
      GoRoute(path: '/profils/modifier/:id', builder: (_, state) => page('Modifier ${state.pathParameters['id']}')),
      GoRoute(path: '/profil/comptes-masques', builder: (_, _) => page('Page Comptes masqués')),
      GoRoute(path: '/profil/social/:section', builder: (_, state) => page('Page ${state.pathParameters['section']}')),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        sessionProvider.overrideWith(_Signed.new),
        libraryProvider.overrideWith(_Library.new),
        tmdbRepositoryProvider.overrideWithValue(_Tmdb()),
        networkRepositoryProvider.overrideWithValue(_FakeNetwork()),
        socialProfileProvider.overrideWith((ref, username) async => _social),
        titlesByIdProvider.overrideWith((ref, key) async => const <TitleRef, MediaItem>{}),
        unreadNotificationsProvider.overrideWith(_ThreeUnread.new),
      ],
      child: MaterialApp.router(theme: buildVixeoTheme(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the bell of the profile page opens « Notifications »', (tester) async {
    await _pump(tester);

    await tester.tap(_pressable('Notifications, 3 notifications non lues'));
    await tester.pumpAndSettle();
    expect(find.text('Page Notifications'), findsOneWidget);
  });

  testWidgets('shows the profile, its counters and its five tabs', (tester) async {
    await _pump(tester);

    expect(find.text('Léa'), findsOneWidget);
    expect(find.text('@lea'), findsOneWidget);
    expect(find.text('Fan de science-fiction.'), findsOneWidget);
    expect(_pressable('12 abonnés'), findsOneWidget);
    expect(_pressable('1 abonnement'), findsOneWidget);
    // The people followed (actors, directors…), from this device's library.
    expect(_pressable('1 personne suivie'), findsOneWidget);
    // The top of the page on the left (like Bingers): the avatar, then the name and @username
    // under it; following before followers.
    final page = tester.getRect(find.byType(ProfileView));
    final name = tester.getTopLeft(find.text('Léa')).dx;
    expect(name, lessThan(page.center.dx));
    expect(tester.getTopLeft(find.text('@lea')).dx, moreOrLessEquals(name, epsilon: 1));
    expect(tester.getCenter(find.byType(AvatarTile).first).dx, lessThan(page.center.dx));
    expect(
      tester.getCenter(_pressable('1 abonnement')).dx,
      lessThan(tester.getCenter(_pressable('12 abonnés')).dx),
    );
    // No « Modifier le profil » button nor « Paramètres »: « ⋮ » at the top right.
    expect(find.text('Modifier le profil'), findsNothing);
    expect(_pressable('Paramètres'), findsNothing);
    expect(_pressable('Plus d’options'), findsOneWidget);
    // « Notifications » (not in the navigation any more): next to « ⋮ », with its number.
    final bell = _pressable('Notifications, 3 notifications non lues');
    expect(bell, findsOneWidget);
    expect(tester.getCenter(bell).dx, lessThan(tester.getCenter(_pressable('Plus d’options')).dx));
    expect(find.text('3'), findsWidgets);
    // No invitation to choose « Mes 4 favoris ».
    expect(find.textContaining('Choisissez vos 4'), findsNothing);

    // The figures: time watched (from the API), the titles watched and « À voir » as shown on the
    // page, the episodes watched and the reviews.
    expect(find.text('TEMPS DE VISIONNAGE'), findsOneWidget);
    expect(find.text('5 j 9 h'), findsOneWidget);
    expect(find.bySemanticsLabel('Temps de visionnage : 5 jours et 9 heures'), findsOneWidget);
    expect(find.bySemanticsLabel('Films et séries vus : 1'), findsOneWidget);
    expect(find.bySemanticsLabel('Épisodes vus : 42'), findsOneWidget);
    expect(find.bySemanticsLabel('Avis : 5'), findsOneWidget);
    expect(find.bySemanticsLabel('À voir : 2'), findsOneWidget);

    // « Activité » first: each action with its date; no « Journal ».
    for (final (i, tab) in ['Activité', 'Listes', 'Avis', 'Aimés', 'Vus'].indexed) {
      expect(_pressable('$tab, onglet ${i + 1} sur 5'), findsOneWidget);
    }
    expect(find.textContaining('Journal'), findsNothing);
    expect(find.text('Mon activité'), findsOneWidget);
    expect(find.text('Aujourd’hui'), findsOneWidget);
    expect(find.text('Aimé'), findsOneWidget);
    expect(find.text('Matrix'), findsOneWidget);

    // « Listes »: « À voir » first, then my lists.
    await _tab(tester, 'Listes');
    expect(_pressable('À voir, 2 titres'), findsOneWidget);
    expect(find.text('Top 10 de 2026'), findsOneWidget);
    expect(find.text('Nouvelle liste'), findsOneWidget);
    expect(find.text('Nouveau top 10'), findsNothing);

    // « Avis »: the 10 latest.
    await _tab(tester, 'Avis');
    expect(find.text('Film noté 1'), findsOneWidget);
    expect(find.text('Film noté 5'), findsOneWidget);

    // « Aimés »: the likes (not favorites) and the people followed.
    await _tab(tester, 'Aimés');
    expect(find.text('Mes J’aime'), findsOneWidget);
    expect(find.text('Forrest Gump'), findsWidgets);
    expect(find.text('Personnes suivies'), findsOneWidget);
    expect(find.text('Brad Pitt'), findsOneWidget);
    expect(find.text('Dune'), findsNothing);

    // « Vus »: the titles watched, « Mon année ».
    await _tab(tester, 'Vus');
    expect(find.text('Mes titres vus'), findsOneWidget);
    expect(find.text('Fight Club'), findsWidgets);
    expect(find.textContaining('Mon année'), findsOneWidget);
  });

  testWidgets('« ⋮ » of my page: a drop-down with the profile\'s actions', (tester) async {
    await _pump(tester);

    await tester.tap(_pressable('Plus d’options'));
    await tester.pumpAndSettle();
    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    const items = [
      'Modifier mon profil',
      'Paramètres',
      'Changer de profil',
      'Comptes bloqués et masqués',
      'Se déconnecter',
    ];
    for (var i = 1; i < items.length; i++) {
      expect(top(items[i - 1]), lessThan(top(items[i])), reason: items[i]);
    }
    // Under its button, on the right.
    final button = tester.getRect(_pressable('Plus d’options'));
    expect(top('Modifier mon profil'), greaterThan(button.bottom));
    expect(tester.getTopRight(find.text('Modifier mon profil')).dx, lessThan(button.right));

    await tester.tap(find.text('Modifier mon profil'));
    await tester.pumpAndSettle();
    expect(find.text('Modifier 2'), findsOneWidget);

    await _pump(tester);
    await tester.tap(_pressable('Plus d’options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Comptes bloqués et masqués'));
    await tester.pumpAndSettle();
    expect(find.text('Page Comptes masqués'), findsOneWidget);

    await _pump(tester);
    await tester.tap(_pressable('Plus d’options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paramètres'));
    await tester.pumpAndSettle();
    expect(find.text('Page Paramètres'), findsOneWidget);
  });

  testWidgets('the time watched as the profile page writes it', (tester) async {
    expect(watchTimeLabel(0), (shown: '0 h', spoken: 'aucun'));
    expect(watchTimeLabel(40), (shown: '40 min', spoken: '40 minutes'));
    expect(watchTimeLabel(5 * 60 + 12), (shown: '5 h 12 min', spoken: '5 heures et 12 minutes'));
    expect(watchTimeLabel(60), (shown: '1 h', spoken: '1 heure'));
    expect(watchTimeLabel((2 * 24 + 4) * 60), (shown: '2 j 4 h', spoken: '2 jours et 4 heures'));
    // A month is 30 days.
    expect(
      watchTimeLabel(((3 * 30 + 21) * 24 + 9) * 60),
      (shown: '3 mois 21 j 9 h', spoken: '3 mois, 21 jours et 9 heures'),
    );
    expect(watchTimeLabel(30 * 24 * 60), (shown: '1 mois', spoken: '1 mois'));
  });

  testWidgets('the arrows open « À voir », every review, like and title watched', (tester) async {
    await _pump(tester);
    await _tab(tester, 'Listes');
    await tester.tap(_pressable('À voir, 2 titres'));
    await tester.pumpAndSettle();
    expect(find.text('Page À voir'), findsOneWidget);

    await _pump(tester);
    await _tab(tester, 'Avis');
    await tester.tap(_pressable('Voir tout : Mes avis'));
    await tester.pumpAndSettle();
    expect(find.text('Page Mes avis'), findsOneWidget);

    await _pump(tester);
    await _tab(tester, 'Aimés');
    await tester.tap(_pressable('Voir tout : Mes J’aime'));
    await tester.pumpAndSettle();
    expect(find.text('Page aimes'), findsOneWidget);

    await _pump(tester);
    await _tab(tester, 'Aimés');
    await tester.tap(_pressable('Voir tout : Personnes suivies'));
    await tester.pumpAndSettle();
    expect(find.text('Page personnes'), findsOneWidget);

    await _pump(tester);
    await _tab(tester, 'Vus');
    await tester.tap(_pressable('Voir tout : Mes titres vus'));
    await tester.pumpAndSettle();
    expect(find.text('Page vus'), findsOneWidget);
  });

  testWidgets('followers and followed people open their list', (tester) async {
    await _pump(tester);
    await tester.tap(_pressable('12 abonnés'));
    await tester.pumpAndSettle();
    expect(find.text('Page abonnes'), findsOneWidget);

    await _pump(tester);
    await tester.tap(_pressable('1 personne suivie'));
    await tester.pumpAndSettle();
    expect(find.text('Page personnes'), findsOneWidget);
  });

  testWidgets('a member\'s page: the same page and tabs, and « Suivre »', (tester) async {
    final social = await _pumpMember(tester);

    expect(find.text('Max'), findsOneWidget);
    expect(find.text('@max'), findsOneWidget);
    expect(find.text('Cinéphile.'), findsOneWidget);
    expect(_pressable('3 abonnés'), findsOneWidget);
    expect(_pressable('2 personnes suivies'), findsOneWidget);
    expect(find.bySemanticsLabel('À voir : 1'), findsOneWidget);
    expect(find.text('Son activité'), findsOneWidget);
    expect(find.text('Matrix'), findsOneWidget);

    await _tab(tester, 'Listes');
    expect(_pressable('À voir, 1 titre'), findsOneWidget);
    expect(find.text('Top 10 de 2026'), findsOneWidget);
    expect(find.text('Nouvelle liste'), findsNothing);

    await _tab(tester, 'Aimés');
    expect(find.text('Ses J’aime'), findsOneWidget);
    expect(find.text('Forrest Gump'), findsWidgets);
    expect(find.text('Personnes suivies'), findsOneWidget);
    expect(find.text('Brad Pitt'), findsOneWidget);

    await _tab(tester, 'Vus');
    expect(find.text('Ses titres vus'), findsOneWidget);
    expect(find.text('Le Parrain'), findsWidgets);

    await tester.tap(find.text('Suivre'));
    await tester.pumpAndSettle();
    expect(social.calls, ['follow max']);

    // Their review opens the title, not « Mon avis ».
    await _tab(tester, 'Avis');
    await tester.tap(find.text('Fight Club'));
    await tester.pumpAndSettle();
    expect(find.text('Fiche 550'), findsOneWidget);
  });

  testWidgets('a member\'s « À voir » and titles watched open whole', (tester) async {
    await _pumpMember(tester);
    await _tab(tester, 'Listes');
    await tester.tap(_pressable('À voir, 1 titre'));
    await tester.pumpAndSettle();
    expect(find.text('Page a-voir'), findsOneWidget);

    await _pumpMember(tester);
    await _tab(tester, 'Vus');
    await tester.tap(_pressable('Voir tout : Ses titres vus'));
    await tester.pumpAndSettle();
    expect(find.text('Page vus'), findsOneWidget);
  });

  testWidgets('account search: avatar, name and @username, no follower count', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sessionProvider.overrideWith(_Signed.new),
          socialSearchProvider.overrideWith((ref, query) async => const [_member]),
        ],
        child: MaterialApp(
          theme: buildVixeoTheme(),
          home: const Scaffold(body: SocialSearchResults(query: 'ma')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Max'), findsOneWidget);
    expect(find.text('@max'), findsOneWidget);
    expect(find.text('M'), findsOneWidget, reason: 'without an avatar of the catalog, the initial');
    expect(find.textContaining('abonné'), findsNothing);
  });

  testWidgets('« Ses avis »: a member\'s reviews, searched, filtered and sorted like « Mes avis »', (tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sessionProvider.overrideWith(_Signed.new),
          socialReviewsProvider.overrideWith(
            (ref, key) async => const Paged(items: [
              RatedItem(type: RatedType.movie, id: 1, title: 'Dune', value: 6),
              RatedItem(type: RatedType.tv, id: 2, title: 'Les Hautes Terres', value: 9, comment: 'Superbe.'),
            ]),
          ),
        ],
        child: MaterialApp(theme: buildVixeoTheme(), home: const Scaffold(body: ReviewsScreen(username: 'max'))),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ses avis'), findsOneWidget);
    double y(String title) => tester.getTopLeft(find.text(title)).dy;
    // The most recent first (the API's order).
    expect(y('Dune'), lessThan(y('Les Hautes Terres')));

    // The filter bar scrolls sideways: the order is at its end.
    await tester.ensureVisible(find.text('Tri : Plus récents'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tri : Plus récents'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meilleures notes'));
    await tester.pumpAndSettle();
    expect(y('Les Hautes Terres'), lessThan(y('Dune')));

    await tester.ensureVisible(find.text('Films'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Films'));
    await tester.pumpAndSettle();
    expect(find.text('Les Hautes Terres'), findsNothing);
    expect(find.text('Dune'), findsOneWidget);
  });

  testWidgets('a member\'s followers: 20 first, the next ones as the list scrolls', (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final asked = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sessionProvider.overrideWith(_Signed.new),
          libraryProvider.overrideWith(_Library.new),
          allGenresProvider.overrideWith((ref) async => const {MediaType.movie: <Genre>[], MediaType.tv: <Genre>[]}),
          socialConnectionsProvider.overrideWith((ref, key) async {
            asked.add('followers ${key.page}');
            final first = (key.page - 1) * 20 + 1;
            final last = key.page == 1 ? 20 : 25;
            return Paged(
              items: [
                for (var i = first; i <= last; i++) SocialProfile(id: 100 + i, username: 'fan$i', name: 'Fan $i'),
              ],
              page: key.page,
              totalPages: 2,
            );
          }),
        ],
        child: MaterialApp(
          theme: buildVixeoTheme(),
          home: const SocialCollectionScreen(section: 'abonnes', username: 'max'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(asked, ['followers 1']);
    expect(find.text('Fan 1'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Fan 25'), 400, scrollable: find.byType(Scrollable).last);
    expect(asked, ['followers 1', 'followers 2']);
  });

  testWidgets('a member\'s « À voir »: 20 titles first (their details in one request), then the next page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final asked = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sessionProvider.overrideWith(_Signed.new),
          libraryProvider.overrideWith(_Library.new),
          allGenresProvider.overrideWith((ref) async => const {MediaType.movie: <Genre>[], MediaType.tv: <Genre>[]}),
          socialTitlesProvider.overrideWith((ref, key) async {
            asked.add('à voir ${key.$2}');
            final first = (key.$2 - 1) * 20 + 1;
            final last = key.$2 == 1 ? 20 : 23;
            return Paged(
              items: [for (var i = first; i <= last; i++) MediaItem(id: i, type: MediaType.movie, title: 'Film $i')],
              page: key.$2,
              totalPages: 2,
            );
          }),
          titlesByIdProvider.overrideWith((ref, key) async {
            asked.add('titles ${key.split(',').length}');
            return const <TitleRef, MediaItem>{};
          }),
        ],
        child: MaterialApp(theme: buildVixeoTheme(), home: const Scaffold(body: MyListScreen(username: 'max'))),
      ),
    );
    await tester.pumpAndSettle();
    // The first page, and the catalog's details of its 20 titles in one request.
    expect(asked, ['à voir 1', 'titles 20']);
    await tester.scrollUntilVisible(
      find.bySemanticsLabel(RegExp(r'^Film 23\b')),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    expect(asked, ['à voir 1', 'titles 20', 'à voir 2', 'titles 3']);
  });

  testWidgets('a member\'s « À voir », with the search and the filters of mine', (tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sessionProvider.overrideWith(_Signed.new),
          libraryProvider.overrideWith(_Library.new),
          allGenresProvider.overrideWith((ref) async => const {MediaType.movie: <Genre>[], MediaType.tv: <Genre>[]}),
          socialTitlesProvider.overrideWith(
            (ref, key) async => const Paged(items: [
              MediaItem(id: 1, type: MediaType.movie, title: 'Dune', year: 2021),
              MediaItem(id: 2, type: MediaType.tv, title: 'Les Hautes Terres', year: 2011),
            ]),
          ),
          titlesByIdProvider.overrideWith((ref, key) async => const <TitleRef, MediaItem>{}),
        ],
        child: MaterialApp(theme: buildVixeoTheme(), home: const Scaffold(body: MyListScreen(username: 'max'))),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('À voir'), findsOneWidget);
    expect(find.byType(PosterCard), findsNWidgets(2));
    // No channels in a member's list.
    expect(find.text('Chaînes TV'), findsNothing);

    await tester.tap(find.text('Séries'));
    await tester.pumpAndSettle();
    expect(find.byType(PosterCard), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'dune');
    await tester.pumpAndSettle();
    expect(find.text('Aucun résultat'), findsOneWidget);
  });

  testWidgets('my reviews, with no TMDb account to link', (tester) async {
    await _pump(tester);
    await _tab(tester, 'Avis');
    expect(find.text('Lier mon compte TMDb'), findsNothing);
    expect(find.text('Film noté 1'), findsOneWidget);
    expect(find.bySemanticsLabel('Avis : 5'), findsOneWidget);
  });

  testWidgets('« Paramètres »: no « Profil », « Avancé » nor « Comptes bloqués et masqués »', (tester) async {
    tester.view.physicalSize = const Size(600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionProvider.overrideWith(_Signed.new)],
        child: MaterialApp(theme: buildVixeoTheme(), home: const Scaffold(body: ProfileSettingsScreen())),
      ),
    );
    await tester.pumpAndSettle();

    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    // In the « ⋮ » of the profile page now.
    for (final gone in [
      'PROFIL',
      'Changer de profil',
      'Modifier le profil',
      'Gérer les profils',
      'Biographie',
      'Réseaux sociaux',
      'Compte privé',
      'Comptes bloqués et masqués',
      'Avancé',
    ]) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
    expect(top('COMPTE'), lessThan(top('GÉNÉRAL')));
    expect(find.text('Se déconnecter'), findsOneWidget);
  });

  testWidgets('« Paramètres » of a child\'s profile (no page): « Changer de profil » first', (tester) async {
    tester.view.physicalSize = const Size(600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionProvider.overrideWith(_Kid.new)],
        child: MaterialApp(theme: buildVixeoTheme(), home: const Scaffold(body: ProfileSettingsScreen())),
      ),
    );
    await tester.pumpAndSettle();

    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(top('PROFIL'), lessThan(top('Changer de profil')));
    expect(top('Changer de profil'), lessThan(top('Modifier le profil')));
    expect(top('Modifier le profil'), lessThan(top('COMPTE')));
  });

  testWidgets('« Partager » sends the profile\'s page, or copies it', (tester) async {
    final sharer = _FakeSharer();
    const shared = SocialProfile(
      id: 7,
      username: 'max',
      name: 'Max',
      shareUrl: 'https://www.vixeo.app/max',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith(_Signed.new),
          linkSharerProvider.overrideWithValue(sharer),
          socialProfileProvider.overrideWith((ref, username) async => shared),
          networkRepositoryProvider.overrideWithValue(_FakeNetwork()),
          socialTitlesProvider.overrideWith((ref, key) async => const Paged<MediaItem>(items: [])),
          socialLikedProvider.overrideWith((ref, key) async => const Paged<MediaItem>(items: [])),
          socialWatchedProvider.overrideWith((ref, key) async => const Paged<MediaItem>(items: [])),
          socialPeopleProvider.overrideWith((ref, key) async => const Paged<Person>(items: [])),
          socialReviewsProvider.overrideWith((ref, key) async => const Paged<RatedItem>(items: [])),
          titlesByIdProvider.overrideWith((ref, key) async => const <TitleRef, MediaItem>{}),
        ],
        child: MaterialApp(theme: buildVixeoTheme(), home: const PublicProfileScreen(username: 'max')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Partager le profil'));
    await tester.pumpAndSettle();
    expect(sharer.texts.single, 'Le profil de Max (@max) sur Vixeo\nhttps://www.vixeo.app/max');

    // No share sheet (Windows): the link is copied.
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    sharer.opens = false;
    await tester.tap(find.bySemanticsLabel('Partager le profil'));
    await tester.pumpAndSettle();
    expect(copied, ['https://www.vixeo.app/max']);
    expect(find.text('Lien copié'), findsOneWidget);
  });

  test('a profile\'s link opens the profile', () {
    // www.vixeo.app/lea (like Twitter): a path no page of the app has.
    expect(memberOfLink('/lea', unknownPage: true), 'lea');
    expect(memberOfLink('/lea'), isNull);
    expect(memberOfLink('/a', unknownPage: true), isNull);
    expect(memberOfLink('/Max_9', unknownPage: true), 'Max_9');
    // No other address (old ones are not kept).
    expect(memberOfLink('/@lea', unknownPage: true), isNull);
    expect(memberOfLink('/membre/lea'), isNull);
    expect(memberOfLink('/accueil'), isNull);
  });

  testWidgets('www.vixeo.app/lea opens the profile; the app\'s own pages stay theirs', (tester) async {
    // The same redirect and last route as the app's router (router.dart).
    final router = GoRouter(
      initialLocation: '/recherche',
      redirect: (_, state) {
        final member = memberOfLink(state.uri.path, unknownPage: state.fullPath == profileLinkPath);
        return member == null ? null : '/membre/$member';
      },
      routes: [
        GoRoute(path: '/accueil', builder: (_, _) => const Text('Accueil')),
        GoRoute(path: '/recherche', builder: (_, _) => const Text('Recherche')),
        GoRoute(path: '/membre/:username', builder: (_, state) => Text('Membre ${state.pathParameters['username']}')),
        profileLinkRoute(),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('Recherche'), findsOneWidget);

    router.go('/lea');
    await tester.pumpAndSettle();
    expect(find.text('Membre lea'), findsOneWidget);
    router.go('/recherche');
    await tester.pumpAndSettle();
    expect(find.text('Recherche'), findsOneWidget);
    // Not a username: home.
    router.go('/a');
    await tester.pumpAndSettle();
    expect(find.text('Accueil'), findsOneWidget);
  });

  test('the member search never shows the active profile itself (reached from « Profil »)', () async {
    final container = ProviderContainer(
      overrides: [
        sessionProvider.overrideWith(_Signed.new),
        socialRepositoryProvider.overrideWithValue(_SearchSocial([_social, _member])),
      ],
    );
    addTearDown(container.dispose);

    // Kept alive while read (autoDispose providers).
    container.listen(socialSearchProvider('a'), (_, _) {});
    container.listen(socialSearchProvider('le'), (_, _) {});
    final found = await container.read(socialSearchProvider('a').future);
    expect(found, isEmpty);
    final members = await container.read(socialSearchProvider('le').future);
    // « lea » is the active profile: left out, even if the API returned it.
    expect(members.map((p) => p.username), ['max']);
  });


  testWidgets('a private account: its header only, and « Suivre » sends a request', (tester) async {
    const private = SocialProfile(
      id: 7,
      username: 'max',
      name: 'Max',
      followersCount: 3,
      followingCount: 1,
      isPrivate: true,
      canView: false,
    );
    final social = await _pumpMember(tester, member: private, followAnswer: FollowStatus.requested);

    expect(find.text('Max'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is Icon && w.semanticLabel == 'Compte privé'), findsOneWidget);
    expect(find.text('Ce compte est privé'), findsOneWidget);
    // Its activity, lists, likes and reviews are not asked for.
    expect(find.text('Son activité'), findsNothing);
    expect(find.text('Ses J’aime'), findsNothing);
    expect(find.text('Ses avis'), findsNothing);
    expect(find.text('Fight Club'), findsNothing);

    await tester.tap(find.text('Suivre'));
    await tester.pumpAndSettle();
    expect(social.calls, ['follow max']);
    expect(find.text('Demande d’abonnement envoyée à @max'), findsOneWidget);
  });

  testWidgets('a request waiting: « Demande envoyée » withdraws it', (tester) async {
    const waiting = SocialProfile(
      id: 7,
      username: 'max',
      name: 'Max',
      isPrivate: true,
      canView: false,
      followStatus: FollowStatus.requested,
    );
    final social = await _pumpMember(tester, member: waiting);

    expect(find.textContaining('Votre demande d’abonnement est envoyée'), findsOneWidget);
    await tester.tap(find.text('Demande envoyée'));
    await tester.pumpAndSettle();
    expect(social.calls, ['unfollow max']);
    expect(find.text('Demande d’abonnement annulée'), findsOneWidget);
  });

  testWidgets('unfollowing a private account is confirmed first', (tester) async {
    const followed = SocialProfile(
      id: 7,
      username: 'max',
      name: 'Max',
      isPrivate: true,
      followStatus: FollowStatus.following,
    );
    final social = await _pumpMember(tester, member: followed);

    // Followed: its reviews are shown.
    await _tab(tester, 'Avis');
    expect(find.text('Ses avis'), findsOneWidget);
    await tester.tap(find.text('Ne plus suivre'));
    await tester.pumpAndSettle();
    expect(find.text('Ne plus suivre @max ?'), findsOneWidget);
    expect(social.calls, isEmpty);

    await tester.tap(find.text('Ne plus suivre').last);
    await tester.pumpAndSettle();
    expect(social.calls, ['unfollow max']);
  });

  testWidgets('the social networks of a profile, under its bio', (tester) async {
    const linked = SocialProfile(
      id: 7,
      username: 'max',
      name: 'Max',
      socialLinks: [
        SocialLink(network: SocialNetwork.instagram, handle: 'max.films', url: 'https://www.instagram.com/max.films'),
        SocialLink(network: SocialNetwork.website, handle: 'https://www.max.fr/', url: 'https://www.max.fr/'),
      ],
    );
    await _pumpMember(tester, member: linked);

    expect(find.text('@max.films'), findsOneWidget);
    expect(find.text('max.fr'), findsOneWidget);
    expect(_pressable('Instagram : @max.films'), findsOneWidget);
    expect(_pressable('Site web : max.fr'), findsOneWidget);
  });

  testWidgets('« J’aime » on a member\'s review', (tester) async {
    final social = await _pumpMember(tester);
    await _tab(tester, 'Avis');

    expect(find.text('2'), findsOneWidget);
    await tester.tap(_pressable('J’aime cet avis'));
    await tester.pumpAndSettle();
    expect(social.calls, ['like 31']);
    expect(find.text('3'), findsOneWidget);
    expect(_pressable('Je n’aime plus cet avis'), findsOneWidget);

    await tester.tap(_pressable('Je n’aime plus cet avis'));
    await tester.pumpAndSettle();
    expect(social.calls, ['like 31', 'unlike 31']);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('my reviews: their number of likes, no heart to press', (tester) async {
    await _pump(tester);
    await _tab(tester, 'Avis');
    expect(
      find.byWidgetPredicate(
        (widget) => widget is VxFocusable && (widget.semanticLabel ?? '').startsWith('Film noté 1,') &&
            widget.semanticLabel!.endsWith('4 J’aime'),
      ),
      findsOneWidget,
    );
    expect(find.byType(ReviewLikeButton), findsNothing);
  });
}

class _FakeSocial extends SocialRepository {
  _FakeSocial({this.followAnswer = FollowStatus.following})
    : super(ApiClient(token: () => null, profileId: () => null));

  /// What following a member gives: at once (public account), or a request (private).
  final FollowStatus followAnswer;
  final calls = <String>[];

  @override
  Future<FollowStatus> follow(String username) async {
    calls.add('follow $username');
    return followAnswer;
  }

  @override
  Future<void> unfollow(String username) async => calls.add('unfollow $username');

  @override
  Future<ReviewLikeState> likeReview(int reviewId, {required bool liked}) async {
    calls.add('${liked ? 'like' : 'unlike'} $reviewId');
    return (liked: liked, likesCount: liked ? 3 : 2);
  }
}

const _member = SocialProfile(
  id: 7,
  username: 'max',
  name: 'Max',
  bio: 'Cinéphile.',
  followersCount: 3,
  followingCount: 0,
  reviewsCount: 1,
  watchedCount: 9,
  listCount: 1,
  peopleCount: 2,
);

Future<_FakeSocial> _pumpMember(
  WidgetTester tester, {
  SocialProfile member = _member,
  FollowStatus followAnswer = FollowStatus.following,
}) async {
  tester.view.physicalSize = const Size(430, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final social = _FakeSocial(followAnswer: followAnswer);
  Widget page(String text) => Scaffold(body: Text(text));
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const PublicProfileScreen(username: 'max')),
      GoRoute(path: '/membre/:username/:section', builder: (_, state) => page('Page ${state.pathParameters['section']}')),
      GoRoute(path: '/titre/:type/:id', builder: (_, state) => page('Fiche ${state.pathParameters['id']}')),
      GoRoute(path: '/listes/:id', builder: (_, state) => page('Liste ${state.pathParameters['id']}')),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        sessionProvider.overrideWith(_Signed.new),
        libraryProvider.overrideWith(_Library.new),
        socialRepositoryProvider.overrideWithValue(social),
        networkRepositoryProvider.overrideWithValue(_FakeNetwork()),
        socialWatchedProvider.overrideWith(
          (ref, key) async => const Paged(items: [MediaItem(id: 238, type: MediaType.movie, title: 'Le Parrain', year: 1972)]),
        ),
        socialProfileProvider.overrideWith((ref, username) async => member),
        socialTitlesProvider.overrideWith(
          (ref, key) async => const Paged(items: [MediaItem(id: 438631, type: MediaType.movie, title: 'Dune', year: 2021)]),
        ),
        socialReviewsProvider.overrideWith(
          (ref, key) async => const Paged(items: [
            RatedItem(type: RatedType.movie, id: 550, title: 'Fight Club', value: 9, reviewId: 31, likesCount: 2),
          ]),
        ),
        socialLikedProvider.overrideWith(
          (ref, key) async => const Paged(items: [MediaItem(id: 13, type: MediaType.movie, title: 'Forrest Gump', year: 1994)]),
        ),
        socialPeopleProvider.overrideWith((ref, key) async => const Paged(items: [Person(id: 287, name: 'Brad Pitt')])),
        titlesByIdProvider.overrideWith((ref, key) async => const <TitleRef, MediaItem>{}),
      ],
      child: MaterialApp.router(theme: buildVixeoTheme(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return social;
}

class _FakeSharer extends LinkSharer {
  bool opens = true;
  final texts = <String>[];

  @override
  Future<bool> share({required String text, String? subject}) async {
    if (opens) texts.add(text);
    return opens;
  }
}

class _SearchSocial extends SocialRepository {
  _SearchSocial(this.found) : super(ApiClient(token: () => null, profileId: () => null));

  final List<SocialProfile> found;

  @override
  Future<List<SocialProfile>> search(String query) async => found;

  @override
  Future<SocialProfile> profile(String username) async => found.firstWhere((p) => p.username == username);
}
