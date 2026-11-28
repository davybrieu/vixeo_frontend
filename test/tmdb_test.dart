import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vixeo/app.dart';
import 'package:vixeo/core/api/api_client.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/core/widgets/common.dart';
import 'package:vixeo/features/auth/models.dart';
import 'package:vixeo/features/auth/session.dart';
import 'package:vixeo/features/catalog/catalog_repository.dart';
import 'package:vixeo/features/catalog/details_screen.dart';
import 'package:vixeo/features/catalog/title_shortcuts.dart';
import 'package:vixeo/features/catalog/models.dart';
import 'package:vixeo/features/catalog/widgets.dart';
import 'package:vixeo/features/library/library.dart';
import 'package:vixeo/features/tmdb/rating_form.dart';
import 'package:vixeo/features/tmdb/review_screen.dart';
import 'package:vixeo/features/tmdb/reviews_screen.dart';
import 'package:vixeo/features/tmdb/tmdb.dart';
import 'package:vixeo/features/network/network.dart' show TitleSocial, titleSocialProvider;

const davy = User(id: 1, name: 'Davy', email: 'davy@exemple.fr');

class WithProfile extends SessionController {
  @override
  SessionState build() => SessionState(
    status: SessionStatus.signedIn,
    token: 't',
    user: davy,
    profile: Profile.fromJson({'id': 2, 'name': 'Léa'}),
  );
}

class EmptyLibrary extends LibraryController {
  @override
  Future<LibraryState> build() async => const LibraryState({});
}

/// The Vixeo API's review routes, in memory.
class FakeTmdb extends TmdbRepository {
  FakeTmdb() : super(ApiClient(token: () => null));

  final calls = <String>[];

  /// Rating path → rating and comment.
  final ratings = <String, MyRating>{};
  var ratedItems = <RatedItem>[];

  @override
  Future<MyRating?> rating(int profileId, RatingTarget target) async => ratings[target.path];

  @override
  Future<Map<int, MyRating>> seasonRatings(int profileId, int showId, int season) async => {
    for (final e in ratings.entries)
      if (e.key.startsWith('tv/$showId/season/$season/episode/')) int.parse(e.key.split('/').last): e.value,
  };

  @override
  Future<void> rate(int profileId, RatingTarget target, MyRating rating) async {
    calls.add('rate ${target.path} ${rating.value}${rating.comment == null ? '' : ' « ${rating.comment} »'}');
    ratings[target.path] = rating;
    // Like the API: the review changed, on top (rated again).
    final index = ratedItems.indexWhere((item) => item.target == target);
    if (index >= 0) ratedItems.insert(0, ratedItems.removeAt(index).rated(rating));
  }

  @override
  Future<void> unrate(int profileId, RatingTarget target) async {
    calls.add('unrate ${target.path}');
    ratings.remove(target.path);
    ratedItems.removeWhere((item) => item.target == target);
  }

  /// Pages asked (`movie recent 1`…).
  final pages = <String>[];

  /// Like the API: of a type, in an order, 20 a page.
  @override
  Future<Paged<RatedItem>> reviews(
    int profileId, {
    RatedType? type,
    RatedOrder order = RatedOrder.recent,
    int page = 1,
  }) async {
    pages.add('${type?.name ?? 'all'} ${order.name} $page');
    final items = [
      for (final item in ratedItems)
        if (type == null || item.type == type) item,
    ];
    final sorted = switch (order) {
      RatedOrder.recent => items,
      RatedOrder.oldest => items.reversed.toList(),
      RatedOrder.highest => [...items]..sort((a, b) => b.value.compareTo(a.value)),
      RatedOrder.lowest => [...items]..sort((a, b) => a.value.compareTo(b.value)),
    };
    return Paged(
      items: sorted.skip((page - 1) * 20).take(20).toList(),
      page: page,
      totalPages: (sorted.length / 20).ceil().clamp(1, 1000).toInt(),
      totalResults: sorted.length,
    );
  }
}

Future<void> pumpPage(
  WidgetTester tester,
  Widget page, {
  required FakeTmdb tmdb,
  Size size = const Size(430, 900),
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => page),
      GoRoute(
        path: '/avis/:type/:id',
        builder: (_, state) => ReviewScreen(
          target: ReviewScreen.targetOf(state.pathParameters, state.uri.queryParameters),
          subject: state.extra as RatingSubject?,
        ),
      ),
      GoRoute(
        path: '/titre/:type/:id',
        builder: (_, state) => Scaffold(body: Text('Fiche ${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/titre/:type/:id/bandes-annonces',
        builder: (_, state) => TitleInfoScreen(
          type: state.pathParameters['type'] == 'tv' ? MediaType.tv : MediaType.movie,
          id: int.parse(state.pathParameters['id']!),
          section: TitleInfoSection.trailers,
        ),
      ),
      GoRoute(
        path: '/titre/:type/:id/images',
        builder: (_, state) => Scaffold(
          body: Text('Images ${state.pathParameters['id']} ${state.uri.queryParameters['sorte'] ?? 'affiche'}'),
        ),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWith(WithProfile.new),
        tmdbRepositoryProvider.overrideWithValue(tmdb),
        libraryProvider.overrideWith(EmptyLibrary.new),
        // The social part of a title page: nothing asked to a server.
        titleSocialProvider.overrideWith((ref, title) async => const TitleSocial()),
        ...overrides,
      ],
      child: MaterialApp.router(
        theme: buildVixeoTheme(),
        routerConfig: router,
        shortcuts: remoteShortcuts,
        actions: remoteActions,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Taps the right half of star [n] (1 to 10): rating n.
Future<void> tapStar(WidgetTester tester, int n) async {
  final stars = find.descendant(of: find.byType(RatingStars).last, matching: find.byType(Icon));
  final star = tester.getRect(stars.at(n - 1));
  await tester.tapAt(Offset(star.left + star.width * 0.8, star.center.dy));
  await tester.pump();
}

void main() {
  test('reads the ratings and the comments of the API', () {
    final episode = RatedItem.fromJson({
      'type': 'episode',
      'id': 1399,
      'title': 'Les Hautes Terres',
      'season_number': 1,
      'episode_number': 2,
      'episode_name': 'La route',
      'value': 7.5,
    });
    expect(episode.target.path, 'tv/1399/season/1/episode/2');
    expect(episode.target, const RatingTarget.episode(1399, 1, 2));
    expect(episode.label, 'Les Hautes Terres · S1 · É2');
    expect(episode.mediaType, MediaType.tv);
    expect(const RatingTarget.title(MediaType.movie, 550).path, 'movie/550');
    final review = RatedItem.fromJson({
      'type': 'movie',
      'id': 550,
      'title': 'Fight Club',
      'value': 8,
      'comment': 'Une claque.',
      'rated_at': '2026-11-09T10:00:00+00:00',
    });
    expect(review.rating, const MyRating(8, comment: 'Une claque.'));
    expect(review.ratedAt, isNotNull);
    expect(MyRating.fromJson({'value': 7.5, 'comment': '  '}).comment, isNull);
    expect(formatScore(8), '8');
    expect(formatScore(7.5), '7,5');
  });

  group('rating page (a page, not a dialog)', () {
    const dune = RatingTarget.title(MediaType.movie, 438631);

    Future<List<(MyRating?,)?>> open(
      WidgetTester tester, {
      MyRating? current,
      Size size = const Size(430, 900),
      FakeTmdb? tmdb,
    }) async {
      final results = <(MyRating?,)?>[];
      await pumpPage(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => results.add(
                  await editRating(
                    context,
                    target: dune,
                    subject: RatingSubject(title: 'Dune', subtitle: 'Film · 2021', current: current, titleLink: false),
                  ),
                ),
                child: const Text('Ouvrir'),
              ),
            ),
          ),
        ),
        tmdb: tmdb ?? FakeTmdb(),
        size: size,
      );
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      return results;
    }

    testWidgets('stars by half points; saving goes back with the rating', (tester) async {
      final tmdb = FakeTmdb();
      final results = await open(tester, tmdb: tmdb);
      // A page of its own: its title, the movie, no dialog.
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Noter'), findsOneWidget);
      expect(find.text('Dune'), findsOneWidget);
      expect(find.text('Film · 2021'), findsOneWidget);
      expect(find.text('Voir la fiche'), findsNothing);
      expect(find.text('– / 10'), findsOneWidget);

      await tapStar(tester, 8);
      expect(find.text('8 / 10'), findsOneWidget, reason: 'tapping a star does not leave the page');

      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(tmdb.calls, ['rate movie/438631 8.0']);
      expect(results, [(const MyRating(8),)]);
      // Back where it came from.
      expect(find.text('Ouvrir'), findsOneWidget);
      expect(find.text('Note enregistrée : 8/10'), findsOneWidget);
    });

    testWidgets('an optional comment, kept by Vixeo', (tester) async {
      final results = await open(tester, current: const MyRating(7, comment: 'Bien.'));
      expect(find.text('Mon avis'), findsOneWidget);
      expect(find.text('Bien.'), findsOneWidget);
      // No word on TMDb on the page (developer's request).
      expect(find.textContaining('TMDb'), findsNothing);

      await tester.enterText(find.byType(TextField), '  Une claque.  ');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(results, [(const MyRating(7, comment: 'Une claque.'),)]);
    });

    testWidgets('TV remote: ← → by half points, digits, OK saves', (tester) async {
      final results = await open(tester, current: const MyRating(6));
      expect(find.text('6 / 10'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(find.text('6,5 / 10'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(find.text('5,5 / 10'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit9);
      await tester.pump();
      expect(find.text('9 / 10'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(results, [(const MyRating(9),)]);
    });

    testWidgets('the stars fit a small phone', (tester) async {
      await open(tester, current: const MyRating(8), size: const Size(320, 640));

      final stars = tester.getRect(find.byType(RatingStars));
      expect(stars.right, lessThanOrEqualTo(320));
      expect(stars.left, greaterThanOrEqualTo(0));
    });

    testWidgets('an existing rating can be removed, after a confirmation', (tester) async {
      final tmdb = FakeTmdb();
      final results = await open(tester, current: const MyRating(7.5), tmdb: tmdb);
      expect(find.text('7,5 / 10'), findsOneWidget);

      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      expect(find.text('Votre note et votre commentaire de « Dune » seront supprimés.'), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Supprimer')));
      await tester.pumpAndSettle();
      expect(tmdb.calls, ['unrate movie/438631']);
      expect(results, [(null,)]);
      expect(find.text('Avis supprimé'), findsOneWidget);
    });

    testWidgets('an address without the title: the rating and the title are asked', (tester) async {
      final tmdb = FakeTmdb()..ratings['movie/3'] = const MyRating(6, comment: 'Correct.');
      await pumpPage(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(onPressed: () => context.push('/avis/movie/3'), child: const Text('Ouvrir')),
          ),
        ),
        tmdb: tmdb,
        overrides: [
          titleProvider.overrideWith(
            (ref, key) async => const TitleDetails(id: 3, type: MediaType.movie, title: 'Le Phare', year: 2019),
          ),
        ],
      );
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      expect(find.text('Mon avis'), findsOneWidget);
      expect(find.text('Le Phare'), findsOneWidget);
      expect(find.text('Film · 2019'), findsOneWidget);
      expect(find.text('6 / 10'), findsOneWidget);
      expect(find.text('Correct.'), findsOneWidget);
    });
  });

  group('title page', () {
    const movie = TitleDetails(
      id: 3,
      type: MediaType.movie,
      title: 'Le Phare',
      voteAverage: 7.1,
      ratings: TitleRatings(tmdb: SiteRating(7.1, 120)),
    );

    List<Override> details(TitleDetails title, {Season? season}) => [
      titleProvider.overrideWith((ref, key) async => title),
      if (season != null) seasonProvider.overrideWith((ref, key) async => season),
    ];

    testWidgets('« Noter » for every profile; the TMDb logo next to the rating', (tester) async {
      await pumpPage(
        tester,
        const DetailsScreen(type: MediaType.movie, id: 3),
        tmdb: FakeTmdb(),
        overrides: details(movie),
      );

      expect(find.bySemanticsLabel('Noter'), findsOneWidget);
      expect(find.byType(TmdbLogo), findsOneWidget);
      // No IMDb rating here: TMDb's, which opens « Notes ».
      expect(find.bySemanticsLabel('Note TMDb : 7,1 sur 10. Voir les notes'), findsOneWidget);
    });

    testWidgets('rates a movie, then changes and removes the rating', (tester) async {
      final tmdb = FakeTmdb();
      await pumpPage(
        tester,
        const DetailsScreen(type: MediaType.movie, id: 3),
        tmdb: tmdb,
        overrides: details(movie),
      );

      await tester.tap(find.bySemanticsLabel('Noter'));
      await tester.pumpAndSettle();
      // The page « Noter », not a dialog.
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Le Phare'), findsOneWidget);
      await tapStar(tester, 8);
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      expect(tmdb.calls, ['rate movie/3 8.0']);
      expect(find.text('Note enregistrée : 8/10'), findsOneWidget);
      expect(find.bySemanticsLabel('Ma note : 8 sur 10, modifier'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Ma note : 8 sur 10, modifier'));
      await tester.pumpAndSettle();
      expect(find.text('Mon avis'), findsOneWidget);
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Supprimer')));
      await tester.pumpAndSettle();
      expect(tmdb.calls.last, 'unrate movie/3');
      expect(find.bySemanticsLabel('Noter'), findsOneWidget);
    });

    testWidgets('rates an episode from the episode list', (tester) async {
      final tmdb = FakeTmdb()..ratings['tv/9/season/1/episode/2'] = const MyRating(8);
      const show = TitleDetails(
        id: 9,
        type: MediaType.tv,
        title: 'Les Hautes Terres',
        seasons: [SeasonSummary(number: 1, name: 'Saison 1', episodeCount: 2)],
      );
      const season = Season(
        showId: 9,
        number: 1,
        name: 'Saison 1',
        episodes: [
          Episode(id: 1, seasonNumber: 1, number: 1, name: 'Le départ'),
          Episode(id: 2, seasonNumber: 1, number: 2, name: 'La route'),
        ],
      );
      await pumpPage(
        tester,
        const DetailsScreen(type: MediaType.tv, id: 9),
        tmdb: tmdb,
        overrides: details(show, season: season),
      );
      final rateFirst = find.bySemanticsLabel('Noter l’épisode 1');
      await tester.scrollUntilVisible(rateFirst, 300, scrollable: find.byType(Scrollable).first);

      expect(find.text('Ma note : 8/10'), findsOneWidget);
      expect(find.bySemanticsLabel('Ma note de l’épisode 2 : 8 sur 10, modifier'), findsOneWidget);

      await tester.tap(rateFirst);
      await tester.pumpAndSettle();
      expect(find.text('Les Hautes Terres · Saison 1, épisode 1'), findsOneWidget);
      await tapStar(tester, 6);
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      expect(tmdb.calls, ['rate tv/9/season/1/episode/1 6.0']);
      expect(find.text('Ma note : 6/10'), findsOneWidget);
    });

    const full = TitleDetails(
      id: 3,
      type: MediaType.movie,
      title: 'Le Phare',
      overview: 'Deux gardiens de phare sur une île de Nouvelle-Angleterre, dans les années 1890.',
      cast: [
        Person(id: 1, name: 'Robert Pattinson', role: 'Ephraim'),
        Person(id: 2, name: 'Willem Dafoe', role: 'Thomas'),
      ],
      trailers: [
        Trailer(
          url: 'https://www.youtube.com/watch?v=a',
          name: 'Bande-annonce VF',
          language: 'fr',
          thumbnailUrl: 'https://i.ytimg.com/vi/a/hqdefault.jpg',
        ),
        Trailer(url: 'https://www.youtube.com/watch?v=b', name: 'Teaser officiel', language: 'en', teaser: true),
      ],
      trailer: Trailer(url: 'https://www.youtube.com/watch?v=a', name: 'Bande-annonce VF'),
    );

    testWidgets('« Voir la bande-annonce » opens the dedicated page with every trailer', (tester) async {
      await pumpPage(tester, const DetailsScreen(type: MediaType.movie, id: 3), tmdb: FakeTmdb(), overrides: details(full));

      final shortcut = find.bySemanticsLabel('Voir la bande-annonce');
      await tester.scrollUntilVisible(shortcut, 300, scrollable: find.byType(Scrollable).first);
      expect(shortcut, findsOneWidget);
      expect(find.bySemanticsLabel('Bande-annonce : Bande-annonce VF'), findsNothing);

      await tester.tap(shortcut);
      await tester.pumpAndSettle();
      expect(find.text('Bandes-annonces'), findsOneWidget);
      expect(find.text('Bande-annonce VF'), findsOneWidget);
      expect(find.text('Teaser officiel'), findsOneWidget);
    });

    testWidgets('« ⋮ » changes the poster, backdrop or logo; no images button any more', (tester) async {
      await pumpPage(tester, const DetailsScreen(type: MediaType.movie, id: 3), tmdb: FakeTmdb(), overrides: details(full));

      expect(find.bySemanticsLabel('Affiches, arrière-plans et logos'), findsNothing);
      // At the top right, across from « Retour ».
      final menu = find.bySemanticsLabel('Plus d’options');
      expect(tester.getCenter(menu).dx, greaterThan(tester.getCenter(find.bySemanticsLabel('Retour')).dx));
      await tester.tap(menu);
      await tester.pumpAndSettle();
      double top(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(top('Changer l’affiche'), lessThan(top('Changer l’arrière-plan')));
      expect(top('Changer l’arrière-plan'), lessThan(top('Changer le logo')));

      // Each opens its tab.
      await tester.tap(find.text('Changer l’arrière-plan'));
      await tester.pumpAndSettle();
      expect(find.text('Images 3 arriere-plan'), findsOneWidget);
    });

    testWidgets('« Retour » and « ⋮ » stay at the top while the page scrolls', (tester) async {
      await pumpPage(tester, const DetailsScreen(type: MediaType.movie, id: 3), tmdb: FakeTmdb(), overrides: details(full));

      final back = find.bySemanticsLabel('Retour');
      final menu = find.bySemanticsLabel('Plus d’options');
      final backAt = tester.getTopLeft(back);
      final menuAt = tester.getTopLeft(menu);
      final playAt = tester.getTopLeft(find.text('Lecture'));

      await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
      await tester.pumpAndSettle();
      // The page moved, not them.
      expect(tester.getTopLeft(find.text('Lecture')).dy, lessThan(playAt.dy));
      expect(tester.getTopLeft(back), backAt);
      expect(tester.getTopLeft(menu), menuAt);
      expect(back.hitTestable(), findsOneWidget);
    });

    testWidgets('a signed-in profile can open the title options', (tester) async {
      await pumpPage(
        tester,
        const DetailsScreen(type: MediaType.movie, id: 3),
        tmdb: FakeTmdb(),
        overrides: details(full),
      );
      expect(find.bySemanticsLabel('Plus d’options'), findsOneWidget);
      expect(find.bySemanticsLabel('Retour'), findsOneWidget);
    });
  });

  group('Mes avis', () {
    final dune = RatedItem(
      type: RatedType.movie,
      id: 438631,
      title: 'Dune',
      value: 8,
      year: 2021,
      comment: 'Une claque visuelle.',
    );
    final episode = RatedItem(
      type: RatedType.episode,
      id: 1399,
      title: 'Les Hautes Terres',
      value: 9.5,
      seasonNumber: 1,
      episodeNumber: 2,
      episodeName: 'La route',
    );
    final show = RatedItem(type: RatedType.tv, id: 1400, title: 'Orbite 9', value: 6, year: 2019);

    testWidgets('everything at first (Tout), then by type and by search', (tester) async {
      final tmdb = FakeTmdb()..ratedItems = [dune, episode, show];
      await pumpPage(tester, const Scaffold(body: ReviewsScreen()), tmdb: tmdb);

      expect(find.text('Mes avis'), findsOneWidget);
      expect(find.bySemanticsLabel('Tout, sélectionné'), findsOneWidget);
      expect(find.text('Dune'), findsOneWidget);
      expect(find.text('Les Hautes Terres'), findsOneWidget);
      expect(find.text('Orbite 9'), findsOneWidget);
      expect(find.text('« Une claque visuelle. »'), findsOneWidget);

      await tester.tap(find.text('Épisodes'));
      await tester.pumpAndSettle();
      expect(find.text('Dune'), findsNothing);
      expect(find.text('Saison 1, épisode 2 · La route'), findsOneWidget);
      // The rating as stars (9 and a half), no button to change or remove it on the list.
      expect(find.text('9,5/10'), findsOneWidget);
      final stars = find.descendant(of: find.byType(StarRow), matching: find.byType(Icon));
      expect(tester.widgetList<Icon>(stars).map((i) => i.icon), [
        for (var i = 0; i < 9; i++) Icons.star_rounded,
        Icons.star_half_rounded,
      ]);
      expect(find.byType(VxIconAction), findsNothing);
      expect(find.text('Modifier'), findsNothing);
      expect(find.text('Supprimer'), findsNothing);

      await tester.tap(find.text('Tout'));
      await tester.pumpAndSettle();
      // Title, episode or comment, without accents or case.
      await tester.enterText(find.byType(TextField), 'CLAQUE');
      await tester.pumpAndSettle();
      expect(find.text('Dune'), findsOneWidget);
      expect(find.text('Orbite 9'), findsNothing);
      await tester.enterText(find.byType(TextField), 'hautes');
      await tester.pumpAndSettle();
      expect(find.text('Les Hautes Terres'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'introuvable');
      await tester.pumpAndSettle();
      expect(find.text('Aucun résultat'), findsOneWidget);
    });

    testWidgets('20 reviews first, the next ones as the list scrolls; the type asked to the API', (tester) async {
      final tmdb = FakeTmdb()
        ..ratedItems = [
          for (var i = 1; i <= 25; i++) RatedItem(type: RatedType.movie, id: i, title: 'Film $i', value: 7),
          episode,
        ];
      await pumpPage(tester, const Scaffold(body: ReviewsScreen()), tmdb: tmdb);

      expect(tmdb.pages, ['all recent 1']);
      expect(find.text('Film 1'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('Les Hautes Terres'), 400, scrollable: find.byType(Scrollable).last);
      expect(tmdb.pages, ['all recent 1', 'all recent 2']);

      // The type: asked to the API, from its first page.
      await tester.tap(find.text('Épisodes'));
      await tester.pumpAndSettle();
      expect(tmdb.pages.last, 'episode recent 1');
      expect(find.text('Saison 1, épisode 2 · La route'), findsOneWidget);
      expect(find.text('Film 1'), findsNothing);
    });

    testWidgets('a review opens its page, where it is changed or removed', (tester) async {
      final tmdb = FakeTmdb()..ratedItems = [episode, dune];
      await pumpPage(tester, const Scaffold(body: ReviewsScreen()), tmdb: tmdb);

      await tester.tap(find.text('Dune'));
      await tester.pumpAndSettle();
      expect(find.text('Mon avis'), findsOneWidget);
      expect(find.text('Film · 2021'), findsOneWidget);
      expect(find.text('8 / 10'), findsOneWidget);
      expect(find.text('Une claque visuelle.'), findsOneWidget);
      await tapStar(tester, 6);
      await tester.enterText(find.byType(TextField), 'Moins bien revu.');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(tmdb.calls, ['rate movie/438631 6.0 « Moins bien revu. »']);
      // Back on the list: changed, and on top (rated again).
      expect(find.text('Mon avis'), findsNothing);
      expect(find.text('Note enregistrée : 6/10'), findsOneWidget);
      expect(find.text('6/10'), findsOneWidget);
      expect(find.text('« Moins bien revu. »'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Dune')).dy, lessThan(tester.getTopLeft(find.text('Les Hautes Terres')).dy));

      await tester.tap(find.text('Dune'));
      await tester.pumpAndSettle();
      expect(find.textContaining('TMDb'), findsNothing);
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      expect(find.text('Votre note et votre commentaire de « Dune » seront supprimés.'), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Supprimer')));
      await tester.pumpAndSettle();
      expect(tmdb.calls.last, 'unrate movie/438631');
      expect(find.text('Mon avis'), findsNothing);
      expect(find.text('Dune'), findsNothing);
      expect(find.text('Avis supprimé'), findsOneWidget);

      // An episode's page opens the TV show.
      await tester.tap(find.text('Les Hautes Terres'));
      await tester.pumpAndSettle();
      expect(find.text('Saison 1, épisode 2 · La route'), findsOneWidget);
      await tester.tap(find.text('Voir la série'));
      await tester.pumpAndSettle();
      expect(find.text('Fiche 1399'), findsOneWidget);
    });

    testWidgets('TV: on the page of a review, the stars have the focus', (tester) async {
      final tmdb = FakeTmdb()..ratedItems = [dune];
      await pumpPage(
        tester,
        const Scaffold(body: ReviewsScreen()),
        tmdb: tmdb,
        size: const Size(1920, 1080),
      );

      await tester.tap(find.text('Dune'));
      await tester.pumpAndSettle();
      final focused = FocusManager.instance.primaryFocus!.context!;
      expect(focused.findAncestorWidgetOfExactType<RatingStars>(), isNotNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(find.text('8,5 / 10'), findsOneWidget);
    });

    test('a review has an address', () {
      expect(ReviewScreen.location(dune.target), '/avis/movie/438631');
      expect(ReviewScreen.location(episode.target), '/avis/tv/1399?saison=1&episode=2');
      expect(ReviewScreen.targetOf({'type': 'tv', 'id': '1399'}, {'saison': '1', 'episode': '2'}), episode.target);
      expect(ReviewScreen.targetOf({'type': 'movie', 'id': '438631'}, {}), dune.target);
    });

    test('searches ignore case and accents', () {
      expect(foldForSearch('Épisode Œuvre'), 'episode oeuvre');
      expect(dune.matches('VISUELLE'), isTrue);
      expect(episode.matches('route'), isTrue);
      expect(show.matches('dune'), isFalse);
      expect(show.matches('  '), isTrue);
    });
  });
}
