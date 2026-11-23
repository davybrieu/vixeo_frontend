import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/app.dart';
import 'package:vixeo/core/features.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/core/widgets/focusable.dart';
import 'package:vixeo/features/catalog/catalog_repository.dart';
import 'package:vixeo/features/catalog/models.dart';
import 'package:vixeo/features/catalog/widgets.dart';
import 'package:vixeo/features/library/library.dart';
import 'package:vixeo/features/search/filter_bar.dart';
import 'package:vixeo/features/search/search_filters.dart';
import 'package:vixeo/features/search/search_screen.dart';
import 'package:vixeo/features/social/social_repository.dart';
import 'package:vixeo/features/tv/channel_search.dart';
import 'package:vixeo/features/tv/models.dart';
import 'package:vixeo/features/tv/tv_repository.dart';

class EmptyLibrary extends LibraryController {
  @override
  Future<LibraryState> build() async => const LibraryState({});
}

const drama = Genre(18, 'Drame');
const horror = Genre(27, 'Horreur');
const scifiTv = Genre(10765, 'Science-Fiction & Fantastique');

final genres = {
  MediaType.movie: const [Genre(28, 'Action'), drama, horror],
  MediaType.tv: const [drama, scifiTv],
};

MediaItem title(int id, String name, MediaType type) =>
    MediaItem(id: id, type: type, title: name, overview: 'Résumé de $name', year: 2020);

/// Fake API: records every request of titles and searches.
class FakeCatalog {
  final titleQueries = <TitleQuery>[];
  final searches = <(String, SearchFilters)>[];
  final channelQueries = <(String, String?)>[];
  int totalPages = 1;

  Paged<MediaItem> titles(TitleQuery q) {
    titleQueries.add(q);
    final type = q.type;
    final base = type == MediaType.movie ? 100 : 200;
    final items = [
      for (var i = 0; i < 20; i++)
        title(
          base + (q.page - 1) * 20 + i,
          '${type == MediaType.movie ? 'Film' : 'Série'} ${q.page}-$i${q.filters.genre == null ? '' : ' ${q.filters.genre!.name}'}',
          type,
        ),
    ];
    return Paged(items: items, page: q.page, totalPages: totalPages);
  }

  SearchResults search((String, SearchFilters) key) {
    searches.add(key);
    // Nothing is called "introuvable".
    if (key.$1 == 'introuvable') return const SearchResults(movies: [], shows: [], people: []);
    return SearchResults(
      movies: [title(1, 'Orbite ${key.$1}', MediaType.movie), title(2, 'Le Phare', MediaType.movie)],
      shows: [title(3, 'Les Veilleurs', MediaType.tv)],
      people: key.$2.hasTitleFilters ? const [] : const [Person(id: 9, name: 'Alma Meyer')],
    );
  }
}

/// The search page; [liveTv]: with the live channels (hidden for now: core/features.dart).
Future<FakeCatalog> pumpSearch(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  int totalPages = 1,
  bool liveTv = false,
  List<SocialProfile> accounts = const [],
}) async {
  final fake = FakeCatalog()..totalPages = totalPages;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        liveTvProvider.overrideWithValue(liveTv),
        allGenresProvider.overrideWith((ref) async => genres),
        titlesProvider.overrideWith((ref, q) async => fake.titles(q)),
        searchProvider.overrideWith((ref, key) async => fake.search(key)),
        socialSearchProvider.overrideWith((ref, query) async => accounts),
        peopleProvider.overrideWith((ref, key) async => const Paged(items: [Person(id: 9, name: 'Alma Meyer')])),
        channelSearchProvider.overrideWith((ref, key) async {
          fake.channelQueries.add(key);
          const all = [
            TvChannel(id: 'tf1', name: 'TF1', categoryId: 'gen'),
            TvChannel(id: 'eqp', name: 'L’Équipe', categoryId: 'sport'),
          ];
          final (query, category) = key;
          return [
            for (final c in all)
              if ((category == null || c.categoryId == category) && c.name.toLowerCase().contains(query.toLowerCase()))
                c,
          ];
        }),
        tvCategoriesProvider.overrideWith(
          (ref) async => const [TvCategory(id: 'gen', name: 'Généralistes'), TvCategory(id: 'sport', name: 'Sport')],
        ),
        homeProvider.overrideWith(
          (ref) async => Home(featured: [title(50, 'Tendance tout', MediaType.movie)], sections: []),
        ),
        titleProvider.overrideWith(
          (ref, key) async => TitleDetails(id: key.$2, type: key.$1, title: 'Titre ${key.$2}', genres: const [drama]),
        ),
        libraryProvider.overrideWith(EmptyLibrary.new),
      ],
      child: MaterialApp(
        shortcuts: remoteShortcuts,
        actions: remoteActions,
        theme: buildVixeoTheme(),
        home: const Scaffold(body: SearchScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

Future<void> typeQuery(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump(const Duration(milliseconds: 450));
  await tester.pumpAndSettle();
}

/// A chip of the filter bar, scrolled into view first (the bar scrolls sideways on a phone).
/// The vertical scroll of the page (not a row's).
final pageScroll = find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)).first;

Future<void> tapChip(WidgetTester tester, String label) async {
  final chip = find.ancestor(of: find.textContaining(label), matching: find.byType(FilterChipButton)).first;
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, String chip, String option) async {
  await tapChip(tester, chip);
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

/// Opens the two-thumb slider of [chip] and moves its thumbs with the arrow keys, like a remote:
/// [start] steps for the start thumb (it has the focus first), then OK and [end] steps for the end
/// one (negative: to the left); then « Appliquer ».
Future<void> slide(WidgetTester tester, String chip, {int start = 0, int end = 0}) async {
  await tapChip(tester, chip);
  Future<void> press(int steps) async {
    for (var i = 0; i < steps.abs(); i++) {
      await tester.sendKeyEvent(steps > 0 ? LogicalKeyboardKey.arrowRight : LogicalKeyboardKey.arrowLeft);
      await tester.pump();
    }
  }

  await press(start);
  if (end != 0) {
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await press(end);
  }
  await tester.tap(find.text('Appliquer'));
  await tester.pumpAndSettle();
}

void main() {
  group('SearchFilters', () {
    test('sends only what differs from the default order', () {
      expect(const SearchFilters().query(withText: false).values.whereType<Object>(), isEmpty);
      expect(const SearchFilters().query(withText: true)['sort'], isNull);
      expect(const SearchFilters(sort: SearchSort.popularity).query(withText: false)['sort'], isNull);
      expect(const SearchFilters(sort: SearchSort.popularity).query(withText: true)['sort'], 'popularity');

      final query = const SearchFilters(
        genre: drama,
        yearTo: 1979,
        minRating: 7,
        maxRating: 8.5,
        sort: SearchSort.oldest,
      ).query(withText: false);
      // Ranges (two-thumb sliders): the rating and « Mieux notés » are asked to the API (IMDb's
      // rating, else TMDb's).
      expect(query, {
        'genre': 18,
        'year_from': null,
        'year_to': 1979,
        'min_rating': 7,
        'max_rating': 8.5,
        'min_votes': null,
        'max_votes': null,
        'sort': 'oldest',
      });
      // The voters of that rating too; a filter: browsing without a text.
      const voters = SearchFilters(minVotes: 1000, maxVotes: 50000);
      expect(voters.query(withText: false)['min_votes'], 1000);
      expect(voters.query(withText: false)['max_votes'], 50000);
      expect((voters.hasTitleFilters, voters.canBrowse, voters.isDefault), (true, true, false));
      // « À voir » checks them like the API: both ends included, an unrated title left out.
      expect(voters.ratingWithin(7, 1000), isTrue);
      expect(voters.ratingWithin(7, 50001), isFalse);
      expect(voters.ratingWithin(null, 5000), isFalse);
      expect(const SearchFilters().ratingWithin(null, 0), isTrue);
      const years = SearchFilters(yearFrom: 2010, yearTo: 2019);
      expect([2009, 2010, 2019, 2020, null].map(years.yearWithin), [false, true, true, false, true]);
      expect(const SearchFilters(sort: SearchSort.rating).query(withText: true)['sort'], 'rating');
    });

    test('relevance needs a text; people stay without one (popular people)', () {
      const filters = SearchFilters(kind: SearchKind.person, sort: SearchSort.relevance);
      expect(filters.sortFor(withText: true), SearchSort.relevance);
      expect(filters.sortFor(withText: false), SearchSort.popularity);
      expect(filters.kind, SearchKind.person);
      expect(SearchSort.available(withText: false), isNot(contains(SearchSort.relevance)));
      // « Mieux notés »: offered with [withRating] (search page, « À voir »).
      expect(SearchSort.available(withText: true), isNot(contains(SearchSort.rating)));
      expect(SearchSort.available(withText: false, withRating: true), [
        SearchSort.popularity,
        SearchSort.rating,
        SearchSort.recent,
        SearchSort.oldest,
      ]);
    });

    test('"Tout" offers the movie and TV genres once, sorted', () {
      expect(genresFor(SearchKind.all, genres).map((g) => g.name), [
        'Action',
        'Drame',
        'Horreur',
        'Science-Fiction & Fantastique',
      ]);
      expect(genresFor(SearchKind.tv, genres), [drama, scifiTv]);
    });
  });

  testWidgets('nothing searched: no results, no "Aucun résultat", nothing asked', (tester) async {
    final fake = await pumpSearch(tester, liveTv: true);

    expect(find.text('Tendance tout'), findsNothing);
    expect(find.byType(PosterCard), findsNothing);
    expect(find.text('TF1'), findsNothing);
    expect(find.text('Alma Meyer'), findsNothing);
    expect(find.text('Aucun résultat'), findsNothing);
    expect(fake.titleQueries, isEmpty);
    expect(fake.searches, isEmpty);
    expect(fake.channelQueries, isEmpty);
    // The filters are there, ready for the search.
    expect(find.ancestor(of: find.text('Personnes'), matching: find.byType(FilterChipButton)), findsOneWidget);

    // A type chosen without a text: still nothing.
    await tapChip(tester, 'Films');
    expect(find.byType(PosterCard), findsNothing);
    expect(find.text('Aucun résultat'), findsNothing);
    await tapChip(tester, 'Chaînes TV');
    expect(find.text('TF1'), findsNothing);
    expect(fake.titleQueries, isEmpty);
    expect(fake.channelQueries, isEmpty);

    // One letter is not a search yet: nothing, and no "Aucun résultat".
    await tapChip(tester, 'Tout');
    await typeQuery(tester, 'o');
    expect(find.byType(PosterCard), findsNothing);
    expect(find.text('Aucun résultat'), findsNothing);
    expect(fake.searches, isEmpty);
  });

  testWidgets('no text, but filters: the movies and TV shows that match them', (tester) async {
    final fake = await pumpSearch(tester);

    // « Les films d'horreur depuis 2010 notés 8 et plus »: the sliders' start thumbs, from 1900 and 0.
    await tapChip(tester, 'Films');
    await choose(tester, 'Genre', 'Horreur');
    await slide(tester, 'Années', start: 110);
    expect(find.text('Depuis 2010'), findsOneWidget);
    await slide(tester, 'Note', start: 16);
    expect(find.text('Note ≥ 8'), findsOneWidget);
    final q = fake.titleQueries.last;
    expect((q.type, q.query, q.filters.genre, q.filters.yearFrom, q.filters.yearTo, q.filters.minRating), (
      MediaType.movie,
      '',
      horror,
      2010,
      null,
      8,
    ));
    expect(q.filters.query(withText: false), {
      'genre': 27,
      'year_from': 2010,
      'year_to': null,
      'min_rating': 8,
      'max_rating': null,
      'min_votes': null,
      'max_votes': null,
      'sort': null,
    });
    expect(find.byType(PosterCard), findsWidgets);
    // No relevance without a text.
    expect(find.text('Tri : Popularité'), findsOneWidget);

    // "Tout": the movies and the TV shows, without people.
    await tapChip(tester, 'Tout');
    expect(fake.searches.last.$1, '');
    expect(find.text('Alma Meyer'), findsNothing);

    // Back to no filter: the empty page again, nothing more asked.
    await tapChip(tester, 'Réinitialiser');
    final asked = fake.searches.length;
    expect(find.byType(PosterCard), findsNothing);
    expect(fake.searches.length, asked);
  });

  testWidgets('"Aucun résultat" only when a text finds nothing; emptying the field removes it', (tester) async {
    final fake = await pumpSearch(tester);

    await typeQuery(tester, 'introuvable');
    expect(fake.searches.last.$1, 'introuvable');
    expect(find.text('Aucun résultat'), findsOneWidget);
    expect(find.textContaining('Rien ne correspond à « introuvable »'), findsOneWidget);

    await tester.tap(find.byTooltip('Effacer'));
    await tester.pumpAndSettle();
    expect(find.text('Aucun résultat'), findsNothing);

    await typeQuery(tester, 'orbite');
    expect(find.text('Aucun résultat'), findsNothing);
    expect(find.byType(PosterCard), findsWidgets);
  });

  testWidgets('phone: with a text, a filtered grid of one type', (tester) async {
    final fake = await pumpSearch(tester);
    await typeQuery(tester, 'film');

    // "Séries": the TV shows come in a grid.
    await tapChip(tester, 'Séries');
    expect(find.bySemanticsLabel(RegExp('^Série 1-0,')), findsOneWidget);
    expect(find.text('Tendance tv'), findsNothing);

    await choose(tester, 'Genre', 'Drame');
    expect(fake.titleQueries.last.type, MediaType.tv);
    expect(fake.titleQueries.last.filters.genre, drama);
    expect(fake.titleQueries.last.query, 'film');
    expect(find.text('Drame'), findsOneWidget);

    // « Note » (0 to 10 by half points) and « Mieux notés », asked to the API.
    await slide(tester, 'Note', start: 6, end: -3);
    expect((fake.titleQueries.last.filters.minRating, fake.titleQueries.last.filters.maxRating), (3, 8.5));
    expect(find.text('Note 3–8,5'), findsOneWidget);
    // « Votants », asked to the API too: 0, 100, 500, 1 000, 2 500, 5 000, 10 000…
    await slide(tester, 'Votants', start: 6);
    expect((fake.titleQueries.last.filters.minVotes, fake.titleQueries.last.filters.maxVotes), (10000, null));
    expect(find.text('Votants ≥ ${formatCount(10000)}'), findsOneWidget);
    // Opened again: where it was; « Réinitialiser » then « Appliquer »: no limit.
    await tapChip(tester, 'Votants');
    expect(find.text('Votants ≥ ${formatCount(10000)}'), findsNWidgets(2));
    await tester.tap(find.text('Réinitialiser').last); // The window's, not the bar's chip.
    await tester.pump();
    expect(find.text('Sans limite de votants'), findsOneWidget);
    await tester.tap(find.text('Appliquer'));
    await tester.pumpAndSettle();
    expect(fake.titleQueries.last.filters.minVotes, isNull);
    expect(find.text('Votants'), findsOneWidget);
    await choose(tester, 'Tri :', 'Mieux notés');
    expect(fake.titleQueries.last.filters.sort, SearchSort.rating);
    expect(find.text('Tri : Mieux notés'), findsOneWidget);
    await tapChip(tester, 'Tri :');
    await tester.tap(find.text('Plus récents').last);
    await tester.pumpAndSettle();
    expect(fake.titleQueries.last.filters.sort, SearchSort.recent);
    expect(find.text('Tri : Plus récents'), findsOneWidget);

    await tapChip(tester, 'Réinitialiser');
    expect(find.text('Tri : Pertinence'), findsOneWidget);
    expect(find.text('Genre'), findsOneWidget);
  });

  testWidgets('a genre the new type does not have is dropped', (tester) async {
    await pumpSearch(tester);

    await choose(tester, 'Genre', 'Horreur');
    expect(find.text('Horreur'), findsOneWidget);
    // TV shows have no "Horreur" genre on TMDb.
    await tapChip(tester, 'Séries');
    expect(find.text('Horreur'), findsNothing);
    expect(find.text('Genre'), findsOneWidget);
  });

  testWidgets('with a text: filtered results, "Pertinence" and "Personnes" offered', (tester) async {
    final fake = await pumpSearch(tester);

    await typeQuery(tester, 'orbite');
    expect(fake.searches.last, ('orbite', const SearchFilters()));
    expect(find.text('Tri : Pertinence'), findsOneWidget);
    expect(find.text('Tendance tout'), findsNothing);
    expect(find.text('Alma Meyer'), findsOneWidget);

    // Both thumbs: 1900 → 2010, OK, this year → 2019.
    await slide(tester, 'Années', start: 110, end: -(DateTime.now().year - 2019));
    expect((fake.searches.last.$2.yearFrom, fake.searches.last.$2.yearTo), (2010, 2019));
    expect(find.text('2010–2019'), findsOneWidget);
    // A filtered search has no people.
    expect(find.text('Alma Meyer'), findsNothing);

    await tapChip(tester, 'Personnes');
    expect(find.text('Alma Meyer'), findsOneWidget);
    // Genre, years, rating and order don't apply to people.
    expect(find.text('Genre'), findsNothing);

    // Text erased: the « Personnes » chip stays, the people leave (nothing is searched).
    await tester.tap(find.byTooltip('Effacer'));
    await tester.pumpAndSettle();
    expect(find.text('Personnes'), findsOneWidget);
    expect(find.text('Alma Meyer'), findsNothing);
    expect(find.text('Aucun résultat'), findsNothing);
  });

  testWidgets('« Voir tout » of a section of "Tout": every result of that type', (tester) async {
    final fake = await pumpSearch(tester, accounts: const [SocialProfile(id: 4, username: 'maxime', name: 'Maxime')]);
    await typeQuery(tester, 'orbite');

    Finder seeAllButton(String section) =>
        find.byWidgetPredicate((w) => w is VxFocusable && w.semanticLabel == 'Voir tout : $section');
    Future<void> seeAll(String section) async {
      final button = seeAllButton(section);
      await tester.scrollUntilVisible(button, 200, scrollable: pageScroll);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    // Films and Séries: the grid of that type, for the same text.
    await seeAll('Films');
    expect((fake.titleQueries.last.type, fake.titleQueries.last.query), (MediaType.movie, 'orbite'));
    expect(find.text('Film 1-0'), findsWidgets);
    expect(seeAllButton('Séries'), findsNothing);

    await tapChip(tester, 'Tout');
    await seeAll('Séries');
    expect((fake.titleQueries.last.type, fake.titleQueries.last.query), (MediaType.tv, 'orbite'));
    expect(find.text('Série 1-0'), findsWidgets);

    // Personnes and Comptes: their lists, without the titles.
    await tapChip(tester, 'Tout');
    await seeAll('Personnes');
    expect(find.text('Alma Meyer'), findsWidgets);
    expect(find.text('Le Phare'), findsNothing);

    await tapChip(tester, 'Tout');
    await seeAll('Comptes');
    expect(find.text('Maxime'), findsWidgets);
    expect(find.text('Le Phare'), findsNothing);
    expect(find.text('Alma Meyer'), findsNothing);
  });

  testWidgets('« Chaînes TV »: a grid, the text and the category filter it, same chips as the filters', (tester) async {
    final fake = await pumpSearch(tester, liveTv: true);
    await tapChip(tester, 'Chaînes TV');
    await typeQuery(tester, 'tf');
    expect(find.text('TF1'), findsOneWidget);
    expect(find.text('L’Équipe'), findsNothing);
    // Title filters don't apply to channels: their category instead, a filter chip like « Genre ».
    expect(find.text('Genre'), findsNothing);
    expect(find.ancestor(of: find.text('Catégorie'), matching: find.byType(FilterChipButton)), findsOneWidget);

    await choose(tester, 'Catégorie', 'Sport');
    expect(fake.channelQueries.last, ('tf', 'sport'));
    expect(find.text('TF1'), findsNothing);

    // Another type: the category is dropped.
    await tapChip(tester, 'Films');
    await tapChip(tester, 'Chaînes TV');
    expect(find.text('Catégorie'), findsOneWidget);
    expect(find.text('TF1'), findsOneWidget);
  });

  testWidgets('live TV hidden (for now): no « Chaînes TV » chip nor section, no channel asked', (tester) async {
    final fake = await pumpSearch(tester);
    expect(find.ancestor(of: find.text('Chaînes TV'), matching: find.byType(FilterChipButton)), findsNothing);
    expect(find.ancestor(of: find.text('Personnes'), matching: find.byType(FilterChipButton)), findsOneWidget);

    await typeQuery(tester, 'tf');
    expect(find.text('Alma Meyer'), findsOneWidget);
    expect(find.text('TF1'), findsNothing);
    expect(find.text('Chaînes TV'), findsNothing);
    expect(fake.channelQueries, isEmpty);
  });

  testWidgets('with a text, "Tout" lists the matching channels', (tester) async {
    await pumpSearch(tester, liveTv: true);
    await typeQuery(tester, 'tf');
    expect(find.text('TF1'), findsOneWidget);
    expect(find.text('L’Équipe'), findsNothing);

    await typeQuery(tester, 'zzz');
    await tester.scrollUntilVisible(find.text('Aucune chaîne ne correspond à « zzz ».'), 300, scrollable: pageScroll);
    expect(find.text('Aucune chaîne ne correspond à « zzz ».'), findsOneWidget);
  });

  testWidgets('the grid loads the next page at its end', (tester) async {
    final fake = await pumpSearch(tester, totalPages: 3);
    await typeQuery(tester, 'film');
    await tapChip(tester, 'Films');
    Set<int> moviePages() => fake.titleQueries.where((q) => q.type == MediaType.movie).map((q) => q.page).toSet();
    expect(moviePages(), isNot(contains(3)));

    final page = find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.bySemanticsLabel(RegExp('^Film 2-19,')), 400, scrollable: page);
    await tester.pumpAndSettle();
    expect(moviePages(), {1, 2, 3});

    // Last page reached: nothing more is asked.
    await tester.scrollUntilVisible(find.bySemanticsLabel(RegExp('^Film 3-19,')), 400, scrollable: page);
    await tester.pumpAndSettle();
    expect(moviePages(), {1, 2, 3});
  });

  testWidgets('large screen: no hero before a search, then the first result, then the selection', (tester) async {
    await pumpSearch(tester, size: const Size(1920, 1080));

    // Nothing searched: no carousel, no hero.
    expect(find.text('Tendance tout'), findsNothing);
    expect(find.textContaining('Résumé de'), findsNothing);

    await typeQuery(tester, 'orbite');
    expect(find.text('Résumé de Orbite orbite'), findsOneWidget);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.bySemanticsLabel(RegExp('^Le Phare,')).first));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(find.text('Résumé de Le Phare'), findsOneWidget);
  });
}
