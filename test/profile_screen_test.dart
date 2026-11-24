import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:vixeo/core/share.dart';
import 'package:vixeo/features/auth/auth_repository.dart';
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
import 'package:vixeo/features/profiles/profile_settings_screen.dart';
import 'package:vixeo/features/social/profile_screen.dart';
import 'package:vixeo/features/social/public_profile_settings.dart';
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
  Future<List<RatedItem>> reviews(int profileId) async => [
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
  Future<List<SocialList>> myLists({String? item}) async => _lists;

  @override
  Future<List<SocialList>> memberLists(String username) async => _lists;
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
      ],
      child: MaterialApp.router(theme: buildVixeoTheme(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the profile, its counters and its five tabs', (tester) async {
    await _pump(tester);

    expect(find.text('Léa'), findsOneWidget);
    expect(find.text('@lea'), findsOneWidget);
    expect(find.text('Fan de science-fiction.'), findsOneWidget);
    expect(_pressable('12 abonnés'), findsOneWidget);
    expect(_pressable('1 abonnement'), findsOneWidget);
    // No « Modifier le profil » (the biography and networks are in « Paramètres »), « Paramètres »
    // at the top right on a phone.
    expect(find.text('Modifier le profil'), findsNothing);
    expect(_pressable('Paramètres'), findsOneWidget);
    // No invitation to choose « Mes 4 favoris ».
    expect(find.textContaining('Choisissez vos 4'), findsNothing);

    // Counters: the reviews, the titles watched and « À voir » as shown on the page.
    expect(find.bySemanticsLabel('Avis : 5'), findsOneWidget);
    expect(find.bySemanticsLabel('Vus : 1'), findsOneWidget);
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

  testWidgets('followers open their list', (tester) async {
    await _pump(tester);
    await tester.tap(_pressable('12 abonnés'));
    await tester.pumpAndSettle();
    expect(find.text('Page abonnes'), findsOneWidget);
  });

  testWidgets('a member\'s page: the same page and tabs, and « Suivre »', (tester) async {
    final social = await _pumpMember(tester);

    expect(find.text('Max'), findsOneWidget);
    expect(find.text('@max'), findsOneWidget);
    expect(find.text('Cinéphile.'), findsOneWidget);
    expect(_pressable('3 abonnés'), findsOneWidget);
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
            (ref, username) async => const [
              RatedItem(type: RatedType.movie, id: 1, title: 'Dune', value: 6),
              RatedItem(type: RatedType.tv, id: 2, title: 'Les Hautes Terres', value: 9, comment: 'Superbe.'),
            ],
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
            (ref, username) async => const [
              MediaItem(id: 1, type: MediaType.movie, title: 'Dune', year: 2021),
              MediaItem(id: 2, type: MediaType.tv, title: 'Les Hautes Terres', year: 2011),
            ],
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

  testWidgets('« Biographie » (Paramètres): 160 characters at most, saved', (tester) async {
    final auth = _FakeAuth();
    await _pumpSettings(tester, auth, BioSettingsScreen.location);

    final bio = find.widgetWithText(TextField, 'Biographie');
    expect(tester.widget<TextField>(bio).controller!.text, 'Fan de science-fiction.');
    expect(tester.widget<TextField>(bio).maxLength, 160);
    await tester.enterText(bio, 'a' * 200);
    await tester.pump();
    expect(tester.widget<TextField>(bio).controller!.text.length, 160);
    expect(find.text('160/160'), findsOneWidget);

    await tester.enterText(bio, ' Cinéphile. ');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(auth.saved.single, {'bio': 'Cinéphile.'});
    expect(find.text('Page Profil'), findsOneWidget);
  });

  testWidgets('« Réseaux sociaux » (Paramètres): one field per network, an emptied one removed', (tester) async {
    final auth = _FakeAuth();
    await _pumpSettings(tester, auth, SocialLinksSettingsScreen.location);

    await tester.enterText(find.widgetWithText(TextField, 'Instagram'), ' @lea.cine ');
    await tester.enterText(find.widgetWithText(TextField, 'Site web'), 'lea.fr');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();

    final links = auth.saved.single['social_links']! as Map<String, String?>;
    expect(links['instagram'], '@lea.cine');
    expect(links['website'], 'lea.fr');
    expect(links['x'], isNull);
    expect(links.keys, [for (final network in SocialNetwork.values) network.key]);
  });

  testWidgets('« Compte privé » (Paramètres): saved at once', (tester) async {
    final auth = _FakeAuth();
    await _pumpSettings(tester, auth, PrivateAccountSettingsScreen.location);

    await tester.tap(_pressable('Compte privé, désactivé'));
    await tester.pumpAndSettle();
    expect(auth.saved.single, {'is_private': true});
    expect(_pressable('Compte privé, activé'), findsOneWidget);
    expect(find.text('Compte privé activé'), findsOneWidget);
  });

  testWidgets('« Paramètres »: « Profil » first, « Changer de profil » first in it', (tester) async {
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
    // The sections, « Profil » (formerly « Profil public ») first.
    expect(find.text('PROFIL PUBLIC'), findsNothing);
    expect(top('PROFIL'), lessThan(top('COMPTE')));
    expect(top('COMPTE'), lessThan(top('GÉNÉRAL')));
    // « Profil »: changing profile first, then the profiles, then the public page.
    const profile = ['Changer de profil', 'Modifier le profil', 'Gérer les profils', 'Biographie', 'Réseaux sociaux'];
    for (var i = 1; i < profile.length; i++) {
      expect(top(profile[i - 1]), lessThan(top(profile[i])), reason: profile[i]);
    }
    expect(top('Compte privé'), lessThan(top('COMPTE')));
    expect(top('PROFIL'), lessThan(top('Changer de profil')));
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
          socialTitlesProvider.overrideWith((ref, username) async => const <MediaItem>[]),
          socialLikedProvider.overrideWith((ref, username) async => const <MediaItem>[]),
          socialWatchedProvider.overrideWith((ref, username) async => const <MediaItem>[]),
          socialPeopleProvider.overrideWith((ref, username) async => const <Person>[]),
          socialReviewsProvider.overrideWith((ref, username) async => const <RatedItem>[]),
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

/// A page of « Paramètres » ([location]) over a « Profil » page, saving with [auth].
Future<void> _pumpSettings(WidgetTester tester, _FakeAuth auth, String location) async {
  tester.view.physicalSize = const Size(600, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('Page Profil'))),
      GoRoute(path: BioSettingsScreen.location, builder: (_, _) => const BioSettingsScreen()),
      GoRoute(path: SocialLinksSettingsScreen.location, builder: (_, _) => const SocialLinksSettingsScreen()),
      GoRoute(path: PrivateAccountSettingsScreen.location, builder: (_, _) => const PrivateAccountSettingsScreen()),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        sessionProvider.overrideWith(_Signed.new),
        socialProfileProvider.overrideWith((ref, username) async => _social),
        authRepositoryProvider.overrideWithValue(auth),
      ],
      child: MaterialApp.router(theme: buildVixeoTheme(), routerConfig: router),
    ),
  );
  router.push(location);
  await tester.pumpAndSettle();
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
          (ref, username) async => const [MediaItem(id: 238, type: MediaType.movie, title: 'Le Parrain', year: 1972)],
        ),
        socialProfileProvider.overrideWith((ref, username) async => member),
        socialTitlesProvider.overrideWith(
          (ref, username) async => const [MediaItem(id: 438631, type: MediaType.movie, title: 'Dune', year: 2021)],
        ),
        socialReviewsProvider.overrideWith(
          (ref, username) async => const [
            RatedItem(type: RatedType.movie, id: 550, title: 'Fight Club', value: 9, reviewId: 31, likesCount: 2),
          ],
        ),
        socialLikedProvider.overrideWith(
          (ref, username) async => const [MediaItem(id: 13, type: MediaType.movie, title: 'Forrest Gump', year: 1994)],
        ),
        socialPeopleProvider.overrideWith((ref, username) async => const [Person(id: 287, name: 'Brad Pitt')]),
        titlesByIdProvider.overrideWith((ref, key) async => const <TitleRef, MediaItem>{}),
      ],
      child: MaterialApp.router(theme: buildVixeoTheme(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return social;
}

/// Answers every search with [found].
class _FakeAuth extends AuthRepository {
  _FakeAuth() : super(ApiClient(token: () => null, profileId: () => null));

  final saved = <Map<String, Object?>>[];

  @override
  Future<Profile> updateProfile(int profileId, Map<String, Object?> fields) async {
    saved.add(fields);
    return Profile.fromJson({
      'id': profileId,
      'name': 'Léa',
      'username': 'lea',
      'bio': 'Fan de science-fiction.',
      ...fields,
      'social_links': null,
    });
  }
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
