import 'package:flutter/material.dart';
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
import 'package:vixeo/features/social/profile_screen.dart';
import 'package:vixeo/features/social/social_search.dart';
import 'package:vixeo/features/social/social_repository.dart';
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
    // Watched only: not in « Ma liste ».
    'tmdb|movie:550': const ProfileItem(source: 'tmdb', itemId: 'movie:550', type: 'movie', title: 'Fight Club'),
  });
}

class _Tmdb extends TmdbRepository {
  _Tmdb({required this.linked}) : super(ApiClient(token: () => null, profileId: () => null));

  final bool linked;

  @override
  Future<TmdbAccount> account(int profileId) async => linked
      ? TmdbAccount(linked: true, accountId: 42, username: 'lea', name: 'Léa', linkedAt: DateTime(2026, 11, 9))
      : TmdbAccount.none;

  @override
  Future<List<RatedItem>> reviews(int profileId) async => [
    for (var i = 1; i <= 5; i++)
      RatedItem(type: RatedType.movie, id: i, title: 'Film noté $i', value: 7, comment: i == 1 ? 'Superbe.' : null),
  ];
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
);

/// The button (or link) read [label] by screen readers.
Finder _pressable(String label) =>
    find.byWidgetPredicate((widget) => widget is VxFocusable && widget.semanticLabel == label);

Future<void> _pump(WidgetTester tester, {bool linked = true}) async {
  tester.view.physicalSize = const Size(430, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  Widget page(String text) => Scaffold(body: Text(text));
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const Scaffold(body: ProfileScreen())),
      GoRoute(path: '/ma-liste', builder: (_, _) => page('Page Ma liste')),
      GoRoute(path: '/avis', builder: (_, _) => page('Page Mes avis')),
      GoRoute(path: '/profil/connexions', builder: (_, _) => page('Page Connexions')),
      GoRoute(path: '/profil/social/edition', builder: (_, _) => page('Page Modifier')),
      GoRoute(path: '/profil/social/:section', builder: (_, state) => page('Page ${state.pathParameters['section']}')),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        sessionProvider.overrideWith(_Signed.new),
        libraryProvider.overrideWith(_Library.new),
        tmdbRepositoryProvider.overrideWithValue(_Tmdb(linked: linked)),
        socialProfileProvider.overrideWith((ref, username) async => _social),
        titlesByIdProvider.overrideWith((ref, key) async => const <TitleRef, MediaItem>{}),
      ],
      child: MaterialApp.router(theme: buildVixeoTheme(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the profile, its counters, « Ma liste » and the latest reviews', (tester) async {
    await _pump(tester);

    expect(find.text('Léa'), findsOneWidget);
    expect(find.text('@lea'), findsOneWidget);
    expect(find.text('Fan de science-fiction.'), findsOneWidget);
    expect(_pressable('12 abonnés'), findsOneWidget);
    expect(_pressable('1 abonnement'), findsOneWidget);
    expect(find.text('Modifier le profil'), findsOneWidget);

    // Counters: the reviews and the list as shown on the page, the watched titles from the API.
    expect(find.bySemanticsLabel('Avis : 5'), findsOneWidget);
    expect(find.bySemanticsLabel('Vus : 34'), findsOneWidget);
    expect(find.bySemanticsLabel('Ma liste : 2'), findsOneWidget);

    // « Ma liste »: a row of posters, the most recently added first.
    Offset card(String title) =>
        tester.getTopLeft(find.ancestor(of: find.text(title).first, matching: find.byType(PosterCard)).first);
    final series = card('Les Hautes Terres');
    final movie = card('Dune');
    expect(series.dy, closeTo(movie.dy, 1));
    expect(series.dx, lessThan(movie.dx));
    expect(find.text('Fight Club'), findsNothing);

    // « Mes avis »: the 3 latest only.
    expect(find.text('Film noté 1'), findsOneWidget);
    expect(find.text('Film noté 3'), findsOneWidget);
    expect(find.text('Film noté 4'), findsNothing);
  });

  testWidgets('the arrows open the whole list and every review', (tester) async {
    await _pump(tester);
    await tester.tap(_pressable('Voir tout : Ma liste'));
    await tester.pumpAndSettle();
    expect(find.text('Page Ma liste'), findsOneWidget);

    await _pump(tester);
    await tester.tap(_pressable('Voir tout : Mes avis'));
    await tester.pumpAndSettle();
    expect(find.text('Page Mes avis'), findsOneWidget);
  });

  testWidgets('followers open their list', (tester) async {
    await _pump(tester);
    await tester.tap(_pressable('12 abonnés'));
    await tester.pumpAndSettle();
    expect(find.text('Page abonnes'), findsOneWidget);
  });

  testWidgets('a member\'s page: the same page, with their list, their reviews and « Suivre »', (tester) async {
    final social = await _pumpMember(tester);

    expect(find.text('Max'), findsOneWidget);
    expect(find.text('@max'), findsOneWidget);
    expect(find.text('Cinéphile.'), findsOneWidget);
    expect(_pressable('3 abonnés'), findsOneWidget);
    expect(find.bySemanticsLabel('Sa liste : 1'), findsOneWidget);
    expect(find.text('Dune'), findsWidgets);
    expect(find.text('Fight Club'), findsOneWidget);

    await tester.tap(find.text('Suivre'));
    await tester.pumpAndSettle();
    expect(social.calls, ['follow max']);

    // Their review opens the title, not « Mon avis ».
    await tester.tap(find.text('Fight Club'));
    await tester.pumpAndSettle();
    expect(find.text('Fiche 550'), findsOneWidget);
  });

  testWidgets('a member\'s whole list opens from the arrow', (tester) async {
    await _pumpMember(tester);
    await tester.tap(_pressable('Voir tout : Sa liste'));
    await tester.pumpAndSettle();
    expect(find.text('Page list'), findsOneWidget);
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

  testWidgets('without a TMDb account, invites to link one', (tester) async {
    await _pump(tester, linked: false);
    expect(find.text('Lier mon compte TMDb'), findsOneWidget);
    await tester.tap(find.text('Lier mon compte TMDb'));
    await tester.pumpAndSettle();
    expect(find.text('Page Connexions'), findsOneWidget);
  });
}

class _FakeSocial extends SocialRepository {
  _FakeSocial() : super(ApiClient(token: () => null, profileId: () => null));

  final calls = <String>[];

  @override
  Future<void> follow(String username) async => calls.add('follow $username');

  @override
  Future<void> unfollow(String username) async => calls.add('unfollow $username');
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
);

Future<_FakeSocial> _pumpMember(WidgetTester tester) async {
  tester.view.physicalSize = const Size(430, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final social = _FakeSocial();
  Widget page(String text) => Scaffold(body: Text(text));
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const PublicProfileScreen(username: 'max')),
      GoRoute(path: '/membre/:username/:section', builder: (_, state) => page('Page ${state.pathParameters['section']}')),
      GoRoute(path: '/titre/:type/:id', builder: (_, state) => page('Fiche ${state.pathParameters['id']}')),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        sessionProvider.overrideWith(_Signed.new),
        libraryProvider.overrideWith(_Library.new),
        socialRepositoryProvider.overrideWithValue(social),
        socialProfileProvider.overrideWith((ref, username) async => _member),
        socialTitlesProvider.overrideWith(
          (ref, username) async => const [MediaItem(id: 438631, type: MediaType.movie, title: 'Dune', year: 2021)],
        ),
        socialReviewsProvider.overrideWith(
          (ref, username) async => const [RatedItem(type: RatedType.movie, id: 550, title: 'Fight Club', value: 9)],
        ),
        titlesByIdProvider.overrideWith((ref, key) async => const <TitleRef, MediaItem>{}),
      ],
      child: MaterialApp.router(theme: buildVixeoTheme(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return social;
}

