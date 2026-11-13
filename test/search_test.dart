import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/app.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/features/catalog/catalog_repository.dart';
import 'package:vixeo/features/catalog/models.dart';
import 'package:vixeo/features/library/library.dart';
import 'package:vixeo/features/search/filter_bar.dart';
import 'package:vixeo/features/search/search_filters.dart';
import 'package:vixeo/features/search/search_screen.dart';
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
    return SearchResults(
      movies: [title(1, 'Orbite ${key.$1}', MediaType.movie), title(2, 'Le Phare', MediaType.movie)],
      shows: [title(3, 'Les Veilleurs', MediaType.tv)],
      people: key.$2.hasTitleFilters ? const [] : const [Person(id: 9, name: 'Alma Meyer')],
    );
  }
}

Future<FakeCatalog> pumpSearch(WidgetTester tester, {Size size = const Size(390, 844), int totalPages = 1}) async {
  final fake = FakeCatalog()..totalPages = totalPages;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        allGenresProvider.overrideWith((ref) async => genres),
        titlesProvider.overrideWith((ref, q) async => fake.titles(q)),
        searchProvider.overrideWith((ref, key) async => fake.search(key)),
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

void main() {
  group('SearchFilters', () {
    test('sends only what differs from the default order', () {
      expect(const SearchFilters().query(withText: false).values.whereType<Object>(), isEmpty);
      expect(const SearchFilters().query(withText: true)['sort'], isNull);
      expect(const SearchFilters(sort: SearchSort.popularity).query(withText: false)['sort'], isNull);
      expect(const SearchFilters(sort: SearchSort.popularity).query(withText: true)['sort'], 'popularity');

      final query = const SearchFilters(
        genre: drama,
        decade: Decade.before1980,
        minRating: 7,
        sort: SearchSort.oldest,
      ).query(withText: false);
      expect(query, {'genre': 18, 'year_from': null, 'year_to': 1979, 'min_rating': 7, 'sort': 'oldest'});
    });

    test('relevance needs a text; people stay without one (popular people)', () {
      const filters = SearchFilters(kind: SearchKind.person, sort: SearchSort.relevance);
      expect(filters.sortFor(withText: true), SearchSort.relevance);
      expect(filters.sortFor(withText: false), SearchSort.popularity);
      expect(filters.kind, SearchKind.person);
      expect(SearchSort.available(withText: false), isNot(contains(SearchSort.relevance)));
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

  testWidgets('phone: explore without carousel, then a filtered grid of one type', (tester) async {
    final fake = await pumpSearch(tester);

    // Before typing: a row of movies and a row of TV shows, no carousel of trending titles.
    expect(find.text('Tendance tout'), findsNothing);
    expect(find.text('Films'), findsWidgets);
    expect(fake.titleQueries.map((q) => q.type), containsAll([MediaType.movie, MediaType.tv]));
    // « Chaînes TV » and « Personnes » are always there: a type each, and a section of "Tout".
    expect(find.text('Chaînes TV'), findsNWidgets(2));
    expect(find.text('TF1'), findsOneWidget);
    expect(find.ancestor(of: find.text('Personnes'), matching: find.byType(FilterChipButton)), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Alma Meyer'), 300, scrollable: pageScroll);
    expect(find.text('Alma Meyer'), findsOneWidget);

    // "Séries": the TV shows come in a grid.
    await tapChip(tester, 'Séries');
    expect(find.bySemanticsLabel(RegExp('^Série 1-0,')), findsOneWidget);
    expect(find.text('Tendance tv'), findsNothing);

    await choose(tester, 'Genre', 'Drame');
    expect(fake.titleQueries.last.type, MediaType.tv);
    expect(fake.titleQueries.last.filters.genre, drama);
    expect(fake.titleQueries.last.query, isNull);
    expect(find.text('Drame'), findsOneWidget);

    await choose(tester, 'Tri :', 'Mieux notés');
    expect(fake.titleQueries.last.filters.sort, SearchSort.rating);
    expect(find.text('Tri : Mieux notés'), findsOneWidget);

    await tapChip(tester, 'Réinitialiser');
    expect(find.text('Tri : Popularité'), findsOneWidget);
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

    await choose(tester, 'Années', 'Années 2010');
    expect(fake.searches.last.$2.decade, Decade.y2010s);
    // A filtered search has no people.
    expect(find.text('Alma Meyer'), findsNothing);

    await tapChip(tester, 'Personnes');
    expect(find.text('Alma Meyer'), findsOneWidget);
    // Genre, years, rating and order don't apply to people.
    expect(find.text('Genre'), findsNothing);

    // Text erased: « Personnes » stays, with the popular people.
    await tester.tap(find.byTooltip('Effacer'));
    await tester.pumpAndSettle();
    expect(find.text('Personnes'), findsOneWidget);
    expect(find.text('Alma Meyer'), findsOneWidget);
  });

  testWidgets('« Chaînes TV »: a grid, the text and the category filter it, same chips as the filters', (tester) async {
    final fake = await pumpSearch(tester);
    await tapChip(tester, 'Chaînes TV');
    expect(find.text('TF1'), findsOneWidget);
    expect(find.text('L’Équipe'), findsOneWidget);
    // Title filters don't apply to channels: their category instead, a filter chip like « Genre ».
    expect(find.text('Genre'), findsNothing);
    expect(find.ancestor(of: find.text('Catégorie'), matching: find.byType(FilterChipButton)), findsOneWidget);

    await choose(tester, 'Catégorie', 'Sport');
    expect(fake.channelQueries.last, ('', 'sport'));
    expect(find.text('TF1'), findsNothing);
    expect(find.text('L’Équipe'), findsOneWidget);

    // Another type: the category is dropped.
    await tapChip(tester, 'Films');
    await tapChip(tester, 'Chaînes TV');
    expect(find.text('Catégorie'), findsOneWidget);
    expect(find.text('TF1'), findsOneWidget);
  });

  testWidgets('with a text, "Tout" lists the matching channels', (tester) async {
    await pumpSearch(tester);
    await typeQuery(tester, 'tf');
    expect(find.text('TF1'), findsOneWidget);
    expect(find.text('L’Équipe'), findsNothing);

    await typeQuery(tester, 'zzz');
    await tester.scrollUntilVisible(find.text('Aucune chaîne ne correspond à « zzz ».'), 300, scrollable: pageScroll);
    expect(find.text('Aucune chaîne ne correspond à « zzz ».'), findsOneWidget);
  });

  testWidgets('the grid loads the next page at its end', (tester) async {
    final fake = await pumpSearch(tester, totalPages: 3);
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

  testWidgets('large screen: the hero shows the first result, then follows the selection', (tester) async {
    await pumpSearch(tester, size: const Size(1920, 1080));

    // No carousel on a large screen: the hero, with the first title of the first row.
    expect(find.text('Tendance tout'), findsNothing);
    expect(find.text('Résumé de Film 1-0'), findsOneWidget);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.bySemanticsLabel(RegExp('^Film 1-2,')).first));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(find.text('Résumé de Film 1-2'), findsOneWidget);

    // New results: the hero goes back to the first one.
    await typeQuery(tester, 'orbite');
    expect(find.text('Résumé de Orbite orbite'), findsOneWidget);
  });
}
