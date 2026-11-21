import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/features/auth/models.dart';
import 'package:vixeo/features/auth/session.dart';
import 'package:vixeo/features/catalog/catalog_repository.dart';
import 'package:vixeo/features/catalog/models.dart';
import 'package:vixeo/features/catalog/widgets.dart';
import 'package:vixeo/features/library/library.dart';
import 'package:vixeo/features/library/my_list_screen.dart';
import 'package:vixeo/features/ratings/rating_view.dart';
import 'package:vixeo/features/ratings/ratings_sheet.dart';
import 'package:vixeo/features/search/filter_bar.dart';
import 'package:vixeo/features/social/social_repository.dart';

class _Session extends SessionController {
  @override
  SessionState build() =>
      const SessionState(status: SessionStatus.signedIn, token: 't', profile: Profile(id: 1, name: 'Léa'));
}

class _NoLibrary extends LibraryController {
  @override
  Future<LibraryState> build() async => const LibraryState({});
}

/// IMDb's logo, drawn from its file.
final imdbLogo = find.byWidgetPredicate(
  (w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == 'assets/images/ratings/imdb.png',
);

Widget app(Widget child, {Key? key}) => ProviderScope(
  // A new scope (and app) per key: a new page, not an update of the last one.
  key: key,
  overrides: [
    sessionProvider.overrideWith(_Session.new),
    libraryProvider.overrideWith(_NoLibrary.new),
  ],
  child: MaterialApp(
    theme: buildVixeoTheme(),
    home: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  group('TitleRatings', () {
    test('reads IMDb\'s and TMDb\'s ratings with their votes', () {
      final ratings = TitleRatings.fromJson({
        'imdb': {'id': 'tt0137523', 'rating': 8.8, 'votes': 2400000},
        'tmdb': {'rating': 8.4, 'votes': 30000},
      });
      expect(ratings.imdb, const SiteRating(8.8, 2400000));
      expect(ratings.imdbId, 'tt0137523');
      expect(ratings.tmdb, const SiteRating(8.4, 30000));
      expect(ratings.shown, (RatingSite.imdb, const SiteRating(8.8, 2400000)));
    });

    test('IMDb\'s rating, else TMDb\'s, else none', () {
      final tmdbOnly = TitleRatings.fromJson({
        'imdb': null,
        'tmdb': {'rating': 7.2, 'votes': 12},
      });
      expect(tmdbOnly.imdb, isNull);
      expect(tmdbOnly.shown, (RatingSite.tmdb, const SiteRating(7.2, 12)));

      final none = TitleRatings.fromJson({
        'imdb': null,
        'tmdb': {'rating': null, 'votes': 0},
      });
      expect(none.isEmpty, isTrue);
      expect(none.shown, isNull);
    });

    test('without `ratings` (an older API): TMDb\'s average', () {
      expect(TitleRatings.fromJson(null, voteAverage: 6.5, voteCount: 40).shown, (
        RatingSite.tmdb,
        const SiteRating(6.5, 40),
      ));
      expect(TitleRatings.fromJson(null).isEmpty, isTrue);
    });

    test('title pages, episodes and list items read them', () {
      final details = TitleDetails.fromJson({
        'id': 550,
        'type': 'movie',
        'title': 'Fight Club',
        'vote_average': 8.4,
        'vote_count': 30000,
        'ratings': {
          'imdb': {'id': 'tt0137523', 'rating': 8.8, 'votes': 2400000},
          'tmdb': {'rating': 8.4, 'votes': 30000},
        },
      });
      expect(details.ratings.shown?.$1, RatingSite.imdb);

      final episode = Episode.fromJson({
        'id': 1,
        'episode_number': 1,
        'name': 'Pilote',
        'vote_average': 7.9,
        'vote_count': 300,
        'ratings': {
          'imdb': {'id': 'tt1480055', 'rating': 8.9, 'votes': 50000},
          'tmdb': {'rating': 7.9, 'votes': 300},
        },
      });
      expect(episode.ratings.imdb, const SiteRating(8.9, 50000));

      // A list item: its `ratings` when given (with its summary), else TMDb's average.
      final item = MediaItem.fromJson({
        'id': 550,
        'type': 'movie',
        'title': 'Fight Club',
        'vote_average': 8.4,
        'ratings': {
          'imdb': {'id': 'tt0137523', 'rating': 8.8, 'votes': 2400000},
          'tmdb': {'rating': 8.4, 'votes': 30000},
        },
      });
      expect(item.shownRating, (RatingSite.imdb, const SiteRating(8.8, 2400000)));
      final light = MediaItem.fromJson({
        'id': 550,
        'type': 'movie',
        'title': 'Fight Club',
        'vote_average': 8.4,
        'ratings': null,
      });
      expect(light.ratings, isNull);
      expect(light.shownRating?.$1, RatingSite.tmdb);
      // Completed by its catalog entry: IMDb's then.
      expect(light.withDetails(item).shownRating?.$1, RatingSite.imdb);
    });

    test('writes the votes in French', () {
      expect(formatVotes(2400000), '2 400 000 votants');
      expect(formatVotes(30000), '30 000 votants');
      expect(formatVotes(999), '999 votants');
      expect(formatVotes(1), '1 votant');
    });
  });

  group('display', () {
    testWidgets('a rating with its site\'s logo, read with its scale', (tester) async {
      await tester.pumpWidget(
        app(
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RatingLabel(site: RatingSite.imdb, value: 8.8),
              RatingLabel(site: RatingSite.tmdb, value: 7.1),
            ],
          ),
        ),
      );

      expect(find.text('8,8'), findsOneWidget);
      expect(imdbLogo, findsOneWidget);
      expect(find.bySemanticsLabel('Note IMDb : 8,8 sur 10'), findsOneWidget);
      // TMDb keeps its official logo.
      expect(find.text('7,1'), findsOneWidget);
      expect(find.byType(TmdbLogo), findsOneWidget);
      expect(find.bySemanticsLabel('Note TMDb : 7,1 sur 10'), findsOneWidget);
    });

    testWidgets('phone card: IMDb\'s rating given with the title, else TMDb\'s', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const rated = MediaItem(
        id: 438631,
        type: MediaType.movie,
        title: 'Dune',
        year: 2021,
        voteAverage: 7.8,
        ratings: TitleRatings(imdb: SiteRating(8.0, 900000), tmdb: SiteRating(7.8, 12000)),
      );

      await tester.pumpWidget(app(const PosterCard(item: rated, width: 116)));
      expect(find.text('8,0'), findsOneWidget);
      expect(imdbLogo, findsOneWidget);

      // No ratings with the item (a « Voir tout » page): TMDb's average, at once.
      await tester.pumpWidget(
        app(
          const PosterCard(item: MediaItem(id: 1, type: MediaType.movie, title: 'Dune', voteAverage: 7.8), width: 116),
          key: const ValueKey(2),
        ),
      );
      expect(imdbLogo, findsNothing);
      expect(find.byType(TmdbRating), findsOneWidget);
      expect(find.text('7,8'), findsOneWidget);
    });

    testWidgets('« Notes »: both sites with their votes, « Pas de note » for a missing one', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        app(
          const RatingButton(
            ratings: TitleRatings(imdb: SiteRating(8.8, 2400000), tmdb: SiteRating(8.4, 30000)),
            name: 'Fight Club',
          ),
        ),
      );
      await tester.tap(find.byType(RatingButton));
      await tester.pumpAndSettle();

      expect(find.text('Notes'), findsOneWidget);
      expect(find.text('Fight Club'), findsOneWidget);
      expect(find.text('2 400 000 votants'), findsOneWidget);
      expect(find.text('30 000 votants'), findsOneWidget);
      expect(find.bySemanticsLabel('IMDb : 8,8 sur 10, 2 400 000 votants'), findsOneWidget);
      expect(find.bySemanticsLabel('TMDb : 8,4 sur 10, 30 000 votants'), findsOneWidget);

      Navigator.of(tester.element(find.text('Notes'))).pop();
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        app(
          const RatingButton(ratings: TitleRatings(imdb: SiteRating(6.1, 80)), name: 'Inédit'),
          key: const ValueKey(2),
        ),
      );
      await tester.tap(find.byType(RatingButton));
      await tester.pumpAndSettle();
      expect(find.text('Pas de note'), findsOneWidget);
      expect(find.bySemanticsLabel('TMDb : pas de note'), findsOneWidget);
    });

    testWidgets('« Ma liste » sorts and filters on the rating each card shows', (tester) async {
      tester.view.physicalSize = const Size(430, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const a = MediaItem(id: 1, type: MediaType.movie, title: 'Arrakis', voteAverage: 9);
      const b = MediaItem(id: 2, type: MediaType.movie, title: 'Bene', voteAverage: 5);
      const c = MediaItem(id: 3, type: MediaType.tv, title: 'Caladan', voteAverage: 7);
      // Their catalog entries (one request for the list) give IMDb's ratings, Caladan none.
      final details = {
        (type: MediaType.movie, id: 1): const MediaItem(
          id: 1,
          type: MediaType.movie,
          title: 'Arrakis',
          ratings: TitleRatings(imdb: SiteRating(6, 10), tmdb: SiteRating(9, 10)),
        ),
        (type: MediaType.movie, id: 2): const MediaItem(
          id: 2,
          type: MediaType.movie,
          title: 'Bene',
          ratings: TitleRatings(imdb: SiteRating(8.5, 10), tmdb: SiteRating(5, 10)),
        ),
      };
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith(_Session.new),
            libraryProvider.overrideWith(_NoLibrary.new),
            allGenresProvider.overrideWith((ref) async => const {MediaType.movie: <Genre>[], MediaType.tv: <Genre>[]}),
            socialTitlesProvider.overrideWith((ref, username) async => const [a, b, c]),
            titlesByIdProvider.overrideWith((ref, key) async => details),
          ],
          child: MaterialApp(theme: buildVixeoTheme(), home: const Scaffold(body: MyListScreen(username: 'max'))),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> choose(String chip, String option) async {
        final button = find.ancestor(of: find.textContaining(chip), matching: find.byType(FilterChipButton)).first;
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
        await tester.tap(find.text(option).last);
        await tester.pumpAndSettle();
      }

      List<String> order() {
        final names = ['Arrakis', 'Bene', 'Caladan'].where((n) => find.text(n).evaluate().isNotEmpty).toList();
        // The card's place (its name may wrap on the image: not the same height from one to another).
        Offset at(String n) =>
            tester.getTopLeft(find.ancestor(of: find.text(n).first, matching: find.byType(PosterCard)).first);
        int compare(String x, String y) =>
            at(x).dy != at(y).dy ? at(x).dy.compareTo(at(y).dy) : at(x).dx.compareTo(at(y).dx);
        return names..sort(compare);
      }

      // IMDb: Bene (8,5), Caladan (no IMDb rating: TMDb's 7), Arrakis (6), whatever TMDb says.
      await choose('Tri :', 'Mieux notés');
      expect(order(), ['Bene', 'Caladan', 'Arrakis']);

      await choose('Note', '7 et plus');
      expect(find.text('Note ≥ 7'), findsOneWidget);
      expect(order(), ['Bene', 'Caladan']);
    });
  });
}
