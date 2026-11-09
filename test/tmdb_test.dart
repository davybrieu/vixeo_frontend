import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vixeo/app.dart';
import 'package:vixeo/core/api/api_client.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/features/auth/models.dart';
import 'package:vixeo/features/auth/session.dart';
import 'package:vixeo/features/catalog/catalog_repository.dart';
import 'package:vixeo/features/catalog/details_screen.dart';
import 'package:vixeo/features/catalog/models.dart';
import 'package:vixeo/features/catalog/widgets.dart';
import 'package:vixeo/features/library/library.dart';
import 'package:vixeo/features/tmdb/my_ratings_screen.dart';
import 'package:vixeo/features/tmdb/rating_dialog.dart';
import 'package:vixeo/features/tmdb/tmdb.dart';
import 'package:vixeo/features/tmdb/tmdb_link_screen.dart';

const davy = User(id: 1, name: 'Davy', email: 'davy@exemple.fr', parentalControl: false);

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

final linkedAccount = TmdbAccount(
  linked: true,
  accountId: 42,
  username: 'davy',
  name: 'Davy B.',
  linkedAt: DateTime(2026, 11, 9),
);

/// The Vixeo API's TMDb routes, in memory.
class FakeTmdb extends TmdbRepository {
  FakeTmdb({this.current = TmdbAccount.none}) : super(ApiClient(token: () => null, profileId: () => null));

  TmdbAccount current;
  final calls = <String>[];

  /// Rating path → value.
  final ratings = <String, double>{};
  var ratedItems = <RatedItem>[];

  /// Polls answered "pending" before the approval.
  int pendingPolls = 1;

  @override
  Future<TmdbAccount> account(int profileId) async => current;

  @override
  Future<TmdbLinkStart> startLink(int profileId) async {
    calls.add('start');
    return const TmdbLinkStart(
      authorizeUrl: 'https://www.themoviedb.org/authenticate/tok',
      expiresIn: Duration(hours: 1),
      interval: Duration(seconds: 5),
    );
  }

  @override
  Future<TmdbAccount?> completeLink(int profileId) async {
    calls.add('poll');
    if (pendingPolls-- > 0) return null;
    return current = linkedAccount;
  }

  @override
  Future<void> unlink(int profileId) async {
    calls.add('unlink');
    current = TmdbAccount.none;
  }

  @override
  Future<double?> rating(int profileId, RatingTarget target) async => ratings[target.path];

  @override
  Future<Map<int, double>> seasonRatings(int profileId, int showId, int season) async => {
    for (final e in ratings.entries)
      if (e.key.startsWith('tv/$showId/season/$season/episode/')) int.parse(e.key.split('/').last): e.value,
  };

  @override
  Future<void> rate(int profileId, RatingTarget target, double value) async {
    calls.add('rate ${target.path} $value');
    ratings[target.path] = value;
  }

  @override
  Future<void> unrate(int profileId, RatingTarget target) async {
    calls.add('unrate ${target.path}');
    ratings.remove(target.path);
  }

  @override
  Future<Paged<RatedItem>> rated(int profileId, RatedType type, int page) async =>
      Paged(items: ratedItems.where((i) => i.type == type).toList());
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
        path: '/profil/tmdb',
        builder: (_, _) => const Scaffold(body: Text('Page de liaison')),
      ),
      GoRoute(
        path: '/titre/:type/:id',
        builder: (_, state) => Scaffold(body: Text('Fiche ${state.pathParameters['id']}')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWith(WithProfile.new),
        tmdbRepositoryProvider.overrideWithValue(tmdb),
        libraryProvider.overrideWith(EmptyLibrary.new),
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
  test('reads the TMDb account and the ratings of the API', () {
    final account = TmdbAccount.fromJson({
      'linked': true,
      'account_id': 42,
      'username': 'davy',
      'name': null,
      'avatar_url': 'https://image.tmdb.org/t/p/w185/me.png',
      'linked_at': '2026-11-09T08:00:00+00:00',
    });
    expect(account.linked, isTrue);
    expect(account.displayName, 'davy');
    expect(TmdbAccount.fromJson({'linked': false}).linked, isFalse);

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
    expect(formatScore(8), '8');
    expect(formatScore(7.5), '7,5');
  });

  group('rating dialog', () {
    Future<List<(double?,)?>> open(WidgetTester tester, {double? current, Size size = const Size(430, 900)}) async {
      final results = <(double?,)?>[];
      await pumpPage(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => results.add(await showRatingDialog(context, name: 'Dune', current: current)),
                child: const Text('Ouvrir'),
              ),
            ),
          ),
        ),
        tmdb: FakeTmdb(),
        size: size,
      );
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      return results;
    }

    testWidgets('stars by half points; saving returns the rating', (tester) async {
      final results = await open(tester);
      expect(find.text('– / 10'), findsOneWidget);

      await tapStar(tester, 8);
      expect(find.text('8 / 10'), findsOneWidget, reason: 'tapping a star does not close the dialog');

      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(results, [(8.0,)]);
    });

    testWidgets('TV remote: ← → by half points, digits, OK saves', (tester) async {
      final results = await open(tester, current: 6);
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
      expect(results, [(9.0,)]);
    });

    testWidgets('the stars fit a small phone', (tester) async {
      await open(tester, current: 8, size: const Size(320, 640));

      final dialog = tester.getRect(find.byType(Dialog));
      final stars = tester.getRect(find.byType(RatingStars));
      expect(stars.right, lessThanOrEqualTo(dialog.right));
      expect(stars.left, greaterThanOrEqualTo(dialog.left));
    });

    testWidgets('an existing rating can be removed', (tester) async {
      final results = await open(tester, current: 7.5);
      expect(find.text('7,5 / 10'), findsOneWidget);

      await tester.tap(find.text('Supprimer ma note'));
      await tester.pumpAndSettle();
      expect(results, [(null,)]);
    });
  });

  group('title page', () {
    const movie = TitleDetails(id: 3, type: MediaType.movie, title: 'Le Phare', voteAverage: 7.1);

    List<Override> details(TitleDetails title, {Season? season}) => [
      titleProvider.overrideWith((ref, key) async => title),
      if (season != null) seasonProvider.overrideWith((ref, key) async => season),
    ];

    testWidgets('no "Noter" without a TMDb account; the TMDb logo next to the rating', (tester) async {
      await pumpPage(
        tester,
        const DetailsScreen(type: MediaType.movie, id: 3),
        tmdb: FakeTmdb(),
        overrides: details(movie),
      );

      expect(find.bySemanticsLabel('Noter'), findsNothing);
      expect(find.byType(TmdbLogo), findsOneWidget);
      expect(find.bySemanticsLabel('Note TMDb : 7,1 sur 10'), findsOneWidget);
    });

    testWidgets('rates a movie, then changes and removes the rating', (tester) async {
      final tmdb = FakeTmdb(current: linkedAccount);
      await pumpPage(
        tester,
        const DetailsScreen(type: MediaType.movie, id: 3),
        tmdb: tmdb,
        overrides: details(movie),
      );

      await tester.tap(find.bySemanticsLabel('Noter'));
      await tester.pumpAndSettle();
      await tapStar(tester, 8);
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      expect(tmdb.calls, ['rate movie/3 8.0']);
      expect(find.text('Note enregistrée : 8/10'), findsOneWidget);
      expect(find.bySemanticsLabel('Ma note : 8 sur 10, modifier'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Ma note : 8 sur 10, modifier'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer ma note'));
      await tester.pumpAndSettle();
      expect(tmdb.calls.last, 'unrate movie/3');
      expect(find.bySemanticsLabel('Noter'), findsOneWidget);
    });

    testWidgets('rates an episode from the episode list', (tester) async {
      final tmdb = FakeTmdb(current: linkedAccount)..ratings['tv/9/season/1/episode/2'] = 8;
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
  });

  group('TMDb account page', () {
    testWidgets('large screen: QR code, then linked once approved on TMDb', (tester) async {
      final tmdb = FakeTmdb();
      await pumpPage(tester, const TmdbLinkScreen(), tmdb: tmdb, size: const Size(1600, 900));

      await tester.tap(find.text('Lier mon compte TMDb'));
      await tester.pump();
      await tester.pump();
      expect(find.bySemanticsLabel('QR code de la page d’autorisation TMDb'), findsOneWidget);
      expect(find.text('En attente de votre autorisation…'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      expect(tmdb.calls, ['start', 'poll'], reason: 'not approved yet');
      expect(find.text('En attente de votre autorisation…'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(tmdb.calls, ['start', 'poll', 'poll']);

      expect(find.text('Davy B.'), findsOneWidget);
      expect(find.text('@davy'), findsOneWidget);
      expect(find.text('Compte TMDb lié : Davy B.'), findsOneWidget);
    });

    testWidgets('unlinks after a confirmation', (tester) async {
      final tmdb = FakeTmdb(current: linkedAccount);
      await pumpPage(tester, const TmdbLinkScreen(), tmdb: tmdb);

      await tester.tap(find.text('Délier'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Délier').last);
      await tester.pumpAndSettle();

      expect(tmdb.calls, ['unlink']);
      expect(find.text('Lier mon compte TMDb'), findsOneWidget);
      expect(find.text('Compte TMDb délié'), findsOneWidget);
    });
  });

  group('Mes notes', () {
    final dune = RatedItem(type: RatedType.movie, id: 438631, title: 'Dune', value: 8, year: 2021);
    final episode = RatedItem(
      type: RatedType.episode,
      id: 1399,
      title: 'Les Hautes Terres',
      value: 9.5,
      seasonNumber: 1,
      episodeNumber: 2,
      episodeName: 'La route',
    );

    testWidgets('lists the ratings by type; changes and removes them', (tester) async {
      final tmdb = FakeTmdb(current: linkedAccount)..ratedItems = [dune, episode];
      await pumpPage(tester, const MyRatingsScreen(), tmdb: tmdb);

      expect(find.text('Dune'), findsOneWidget);
      expect(find.text('Ma note : 8/10'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Modifier ma note de Dune'));
      await tester.pumpAndSettle();
      await tapStar(tester, 6);
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(tmdb.calls, ['rate movie/438631 6.0']);
      expect(find.text('Ma note : 6/10'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Supprimer ma note de Dune'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      expect(tmdb.calls.last, 'unrate movie/438631');
      expect(find.text('Dune'), findsNothing);
      expect(find.text('Aucune note'), findsOneWidget);

      await tester.tap(find.text('Épisodes'));
      await tester.pumpAndSettle();
      expect(find.text('Saison 1, épisode 2 · La route'), findsOneWidget);
      expect(find.text('Ma note : 9,5/10'), findsOneWidget);

      // The row opens the TV show's page.
      await tester.tap(find.text('Les Hautes Terres'));
      await tester.pumpAndSettle();
      expect(find.text('Fiche 1399'), findsOneWidget);
    });

    testWidgets('without a TMDb account: a way to link one', (tester) async {
      await pumpPage(tester, const MyRatingsScreen(), tmdb: FakeTmdb());

      expect(find.text('Aucun compte TMDb lié'), findsOneWidget);
      await tester.tap(find.text('Lier mon compte TMDb'));
      await tester.pumpAndSettle();
      expect(find.text('Page de liaison'), findsOneWidget);
    });
  });
}
