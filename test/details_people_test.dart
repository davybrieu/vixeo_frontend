import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/features/catalog/catalog_repository.dart';
import 'package:vixeo/features/catalog/details_screen.dart';
import 'package:vixeo/features/catalog/models.dart';
import 'package:vixeo/features/catalog/widgets.dart';
import 'package:vixeo/features/library/library.dart';
import 'package:vixeo/features/profiles/no_spoiler.dart';
import 'package:vixeo/features/ratings/ratings.dart';
import 'package:vixeo/features/ratings/ratings_sheet.dart';

class EmptyLibrary extends LibraryController {
  @override
  Future<LibraryState> build() async => const LibraryState({});
}

const cast = [
  Person(id: 1, name: 'Alma Meyer-Lindqvist', role: 'Ingrid'),
  Person(id: 2, name: 'Théo Rivière', role: 'Karl'),
];

Future<void> pumpDetails(
  WidgetTester tester,
  TitleDetails title, {
  Size size = const Size(390, 844),
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        titleProvider.overrideWith((ref, key) async => title),
        libraryProvider.overrideWith(EmptyLibrary.new),
        ...overrides,
      ],
      child: MaterialApp(
        theme: buildVixeoTheme(),
        home: DetailsScreen(type: title.type, id: title.id),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The page itself (not a horizontal row).
final pageScroll = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;

/// Names of the person cards, left to right.
List<String> cardNames(WidgetTester tester) =>
    tester.widgetList<PersonCard>(find.byType(PersonCard)).map((c) => '${c.person.name} (${c.role})').toList();

void main() {
  testWidgets('the title is the TMDb logo when there is one, else the name', (tester) async {
    const logo = 'https://image.tmdb.org/t/p/w500/logo.png';
    await pumpDetails(
      tester,
      const TitleDetails(id: 550, type: MediaType.movie, title: 'Nord Sauvage', logoUrl: logo, logoAspectRatio: 4),
      size: const Size(1920, 1080),
    );

    final image = find.byWidgetPredicate((w) => w is CachedNetworkImage && w.imageUrl == logo);
    expect(image, findsOneWidget);
    // Screen readers still get the title. Its room is kept while the logo loads (4:1, 220 high at most).
    expect(find.bySemanticsLabel('Nord Sauvage'), findsOneWidget);
    expect(tester.getSize(image).height, closeTo(190, 1));

    await pumpDetails(tester, const TitleDetails(id: 3, type: MediaType.movie, title: 'Le Phare'));
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(find.text('Le Phare'), findsOneWidget);
  });

  testWidgets('a press on the rating opens « Notes », every site\'s rating', (tester) async {
    final loader = RatingsLoader(
      fetch: (titles) async => (
        ratings: {for (final t in titles) t: const TitleRatings({RatingSource.imdb: 8.8, RatingSource.metacritic: 67})},
        available: true,
      ),
    );
    await pumpDetails(
      tester,
      const TitleDetails(id: 550, type: MediaType.movie, title: 'Nord Sauvage', voteAverage: 8.4),
      overrides: [ratingsLoaderProvider.overrideWithValue(loader)],
    );

    // The profile's site (IMDb by default), with an arrow: it opens something.
    expect(find.bySemanticsLabel('Note IMDb : 8,8 sur 10. Voir toutes les notes'), findsOneWidget);
    await tester.tap(find.byType(RatingButton));
    await tester.pumpAndSettle();

    expect(find.text('Notes'), findsOneWidget);
    expect(find.bySemanticsLabel('IMDb : 8,8 sur 10, votre source'), findsOneWidget);
    expect(find.bySemanticsLabel('TMDb : 8,4 sur 10'), findsOneWidget);
    expect(find.bySemanticsLabel('Metacritic : 67 sur 100'), findsOneWidget);
  });

  testWidgets('movie: "Créateur et distribution", the director first, then the cast', (tester) async {
    await pumpDetails(
      tester,
      const TitleDetails(
        id: 550,
        type: MediaType.movie,
        title: 'Nord Sauvage',
        cast: cast,
        crew: [Person(id: 9, name: 'Ines Dahl')],
      ),
    );

    await tester.scrollUntilVisible(find.text('Créateur et distribution'), 200, scrollable: pageScroll);
    await tester.pumpAndSettle();
    expect(find.text('Distribution'), findsNothing);
    expect(cardNames(tester), ['Ines Dahl (Réalisation)', 'Alma Meyer-Lindqvist (Ingrid)', 'Théo Rivière (Karl)']);
    expect(find.bySemanticsLabel('Ines Dahl, Réalisation'), findsOneWidget);
    // Only in the row: no "Réalisation : …" line under the overview any more.
    expect(find.textContaining('Réalisation :'), findsNothing);

    // A long name gets two lines on a wider card, instead of being cut after a few letters.
    final name = tester.widget<Text>(find.text('Alma Meyer-Lindqvist'));
    expect(name.maxLines, 2);
    expect(tester.getSize(find.byType(PersonCard).first).width, greaterThanOrEqualTo(100));
  });

  testWidgets('TV show: the creators are marked "Création"', (tester) async {
    await pumpDetails(
      tester,
      const TitleDetails(
        id: 7,
        type: MediaType.tv,
        title: 'Les Veilleurs',
        overview: 'Résumé des Veilleurs',
        cast: cast,
        crew: [Person(id: 9, name: 'Ines Dahl')],
      ),
      size: const Size(1920, 1080),
    );

    await tester.scrollUntilVisible(find.text('Créateur et distribution'), 300, scrollable: pageScroll);
    await tester.pumpAndSettle();
    expect(cardNames(tester).first, 'Ines Dahl (Création)');
    // Title, overview and the sections below start at the same left edge.
    final left = tester.getTopLeft(find.text('Créateur et distribution')).dx;
    expect(tester.getTopLeft(find.text('Les Veilleurs').first).dx, left);
    expect(tester.getTopLeft(find.text('Résumé des Veilleurs')).dx, left);

    // Large screen: no "Avec … · Création : …" line under the overview.
    expect(find.textContaining('Avec '), findsNothing);
    expect(find.textContaining('Création :'), findsNothing);
  });

  testWidgets('no director nor creator: "Distribution" only', (tester) async {
    await pumpDetails(tester, const TitleDetails(id: 3, type: MediaType.movie, title: 'Le Phare', cast: cast));

    await tester.scrollUntilVisible(find.text('Distribution'), 200, scrollable: pageScroll);
    expect(find.text('Créateur et distribution'), findsNothing);
    expect(cardNames(tester).first, 'Alma Meyer-Lindqvist (Ingrid)');
  });

  group('episodes', () {
    const show = TitleDetails(
      id: 1399,
      type: MediaType.tv,
      title: 'Les Hautes Terres',
      seasons: [SeasonSummary(number: 1, name: 'Saison 1', episodeCount: 1)],
    );
    final season = Season(
      showId: 1399,
      number: 1,
      name: 'Saison 1',
      episodes: [
        Episode(id: 1, seasonNumber: 1, number: 1, name: 'Le départ', runtime: 52, airDate: DateTime(2024, 3, 1)),
      ],
    );

    Future<void> scrollToEpisodes(WidgetTester tester) =>
        tester.scrollUntilVisible(find.textContaining('Le départ'), 300, scrollable: pageScroll);

    testWidgets('show their air date', (tester) async {
      await pumpDetails(tester, show, overrides: [seasonProvider.overrideWith((ref, key) async => season)]);
      await scrollToEpisodes(tester);

      expect(find.text('1er mars 2024'), findsOneWidget);
      expect(find.text('52 min'), findsOneWidget);
    });

    testWidgets('are large cards in a horizontal row, with an "Épisode n" badge', (tester) async {
      final long = Season(
        showId: 1399,
        number: 1,
        name: 'Saison 1',
        episodes: [
          for (var n = 1; n <= 6; n++)
            Episode(
              id: n,
              seasonNumber: 1,
              number: n,
              name: n == 1 ? 'Le départ' : 'Suite $n',
              overview: 'Un très long résumé. ' * 30,
              runtime: 52,
              voteAverage: 7.1,
              airDate: DateTime(2024, 3, n),
            ),
        ],
      );
      await pumpDetails(tester, show, overrides: [seasonProvider.overrideWith((ref, key) async => long)]);
      await scrollToEpisodes(tester);
      await tester.pumpAndSettle();

      expect(find.text('Épisode 1'), findsOneWidget);
      // The card's label starts with the episode (its texts follow, for screen readers).
      expect(find.bySemanticsLabel(RegExp('^Épisode 1, Le départ')), findsOneWidget);
      // Wide 16:9 image, most of the phone's width.
      final still = tester.getRect(
        find.ancestor(of: find.text('Épisode 1'), matching: find.byType(ClipRRect)).first,
      );
      expect(still.width, 300);
      expect(still.height, closeTo(168.75, 0.1));
      // The overview never takes more than 2 lines.
      final overview = tester.widget<Text>(find.textContaining('Un très long résumé').first);
      expect(overview.maxLines, 2);
      // Name, overview and facts are on the image, at the bottom, under the badge.
      final badge = tester.getRect(find.text('Épisode 1'));
      final name = tester.getRect(find.text('Le départ'));
      expect(name.top, greaterThan(badge.bottom));
      expect(name.bottom, lessThan(still.bottom));
      // Runtime and rating on the left, air date on the right of the same line, at the bottom of the image.
      final runtime = tester.getCenter(find.text('52 min').first);
      final date = tester.getRect(find.text('1er mars 2024'));
      expect(date.center.dy, closeTo(runtime.dy, 1));
      expect(date.center.dx, greaterThan(runtime.dx));
      expect(date.bottom, lessThanOrEqualTo(still.bottom));
      expect(still.bottom - date.bottom, lessThan(20));

      // The row scrolls from left to right: the last episode comes into view.
      expect(find.text('Épisode 6'), findsNothing);
      final row = find.descendant(of: find.byKey(const ValueKey(1)), matching: find.byType(Scrollable));
      expect(tester.widget<Scrollable>(row).axisDirection, AxisDirection.right);
      await tester.scrollUntilVisible(find.text('Épisode 6'), 300, scrollable: row);
      expect(find.text('Épisode 6'), findsOneWidget);
    });

    testWidgets('hide the air date with No spoil', (tester) async {
      await pumpDetails(
        tester,
        show,
        overrides: [seasonProvider.overrideWith((ref, key) async => season), noSpoilerProvider.overrideWithValue(true)],
      );
      await scrollToEpisodes(tester);

      expect(find.text('1er mars 2024'), findsNothing);
      expect(find.text('52 min'), findsNothing);
    });
  });
}
