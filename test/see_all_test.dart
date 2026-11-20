import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/core/widgets/focusable.dart';
import 'package:vixeo/features/auth/session.dart';
import 'package:vixeo/features/catalog/catalog_repository.dart';
import 'package:vixeo/features/catalog/details_screen.dart';
import 'package:vixeo/features/catalog/list_screen.dart';
import 'package:vixeo/features/catalog/models.dart';
import 'package:vixeo/features/catalog/person_screen.dart';
import 'package:vixeo/features/catalog/widgets.dart';
import 'package:vixeo/features/library/library.dart';
import 'package:vixeo/features/ratings/ratings.dart';

// « Voir tout » of the title and person pages (developer's request): « Vous pourriez aussi
// aimer », « Créateur et distribution », « Connu pour » and « Filmographie » open their whole list.

class _EmptyLibrary extends LibraryController {
  @override
  Future<LibraryState> build() async => const LibraryState({});
}

class _Guest extends SessionController {
  @override
  SessionState build() => const SessionState(status: SessionStatus.guest);
}

/// The button read [label] by screen readers.
Finder _pressable(String label) =>
    find.byWidgetPredicate((widget) => widget is VxFocusable && widget.semanticLabel == label);

/// The page itself (not a horizontal row).
final _pageScroll = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;

MediaItem _movie(int id, String title) => MediaItem(id: id, type: MediaType.movie, title: title);

const _title = TitleDetails(
  id: 550,
  type: MediaType.movie,
  title: 'Nord Sauvage',
  crew: [Person(id: 9, name: 'Ines Dahl')],
  cast: [Person(id: 1, name: 'Alma Meyer', role: 'Ingrid')],
  recommended: [MediaItem(id: 807, type: MediaType.movie, title: 'Le Phare')],
);

final _person = PersonDetails(
  id: 287,
  name: 'Alma Meyer',
  knownFor: [_movie(1, 'Connu 1')],
  filmography: [for (var i = 1; i <= 30; i++) _movie(100 + i, 'Film $i')],
);

Future<void> _pump(WidgetTester tester, String start, {List<Override> overrides = const []}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: start,
    routes: [
      GoRoute(
        path: '/titre/:type/:id',
        builder: (_, state) => DetailsScreen(
          type: MediaType.parse(state.pathParameters['type']),
          id: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/titre/:type/:id/recommandations',
        builder: (_, state) => RecommendationsScreen(
          type: MediaType.parse(state.pathParameters['type']),
          id: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/titre/:type/:id/distribution',
        builder: (_, state) => CreditsScreen(
          type: MediaType.parse(state.pathParameters['type']),
          id: int.parse(state.pathParameters['id']!),
          title: state.uri.queryParameters['titre'],
        ),
      ),
      GoRoute(path: '/personne/:id', builder: (_, state) => PersonScreen(id: int.parse(state.pathParameters['id']!))),
      GoRoute(
        path: '/personne/:id/connu-pour',
        builder: (_, state) =>
            PersonTitlesScreen(id: int.parse(state.pathParameters['id']!), sort: PersonCreditsSort.popular),
      ),
      GoRoute(
        path: '/personne/:id/filmographie',
        builder: (_, state) =>
            PersonTitlesScreen(id: int.parse(state.pathParameters['id']!), sort: PersonCreditsSort.date),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWith(_Guest.new),
        libraryProvider.overrideWith(_EmptyLibrary.new),
        // TMDb's rating: nothing to ask the API.
        ratingSourceProvider.overrideWithValue(RatingSource.tmdb),
        titleProvider.overrideWith((ref, key) async => _title),
        personProvider.overrideWith((ref, id) async => _person),
        ...overrides,
      ],
      child: MaterialApp.router(theme: buildVixeoTheme(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('title page: « Vous pourriez aussi aimer » opens every recommendation', (tester) async {
    final asked = <(MediaType, int, int)>[];
    await _pump(
      tester,
      '/titre/movie/550',
      overrides: [
        recommendationsProvider.overrideWith((ref, key) async {
          asked.add(key);
          return Paged(items: [_movie(807, 'Le Phare'), _movie(808, 'La Digue')]);
        }),
      ],
    );

    final seeAll = _pressable('Voir tout : Vous pourriez aussi aimer');
    await tester.scrollUntilVisible(seeAll, 200, scrollable: _pageScroll);
    await tester.tap(seeAll);
    await tester.pumpAndSettle();

    expect(find.text('Vous pourriez aussi aimer'), findsOneWidget);
    expect(asked, [(MediaType.movie, 550, 1)]);
    expect(find.bySemanticsLabel(RegExp(r'^La Digue')), findsOneWidget);
    expect(find.byType(PosterCard), findsNWidgets(2));
  });

  testWidgets('title page: « Créateur et distribution » opens everyone, the director first', (tester) async {
    await _pump(
      tester,
      '/titre/movie/550',
      overrides: [
        titleCreditsProvider.overrideWith(
          (ref, key) async => TitleCredits(
            crew: const [Person(id: 9, name: 'Ines Dahl')],
            cast: [for (var i = 1; i <= 25; i++) Person(id: i, name: 'Acteur $i', role: 'Rôle $i')],
          ),
        ),
      ],
    );

    final seeAll = _pressable('Voir tout : Créateur et distribution');
    await tester.scrollUntilVisible(seeAll, 200, scrollable: _pageScroll);
    await tester.tap(seeAll);
    await tester.pumpAndSettle();

    expect(find.text('Créateur et distribution'), findsOneWidget);
    final cards = tester.widgetList<PersonCard>(find.byType(PersonCard)).toList();
    expect('${cards.first.person.name} (${cards.first.role})', 'Ines Dahl (Réalisation)');
    expect('${cards[1].person.name} (${cards[1].role})', 'Acteur 1 (Rôle 1)');

    // The whole cast, further down the grid.
    await tester.scrollUntilVisible(find.text('Acteur 25'), 300, scrollable: _pageScroll);
    expect(find.text('Rôle 25'), findsOneWidget);
  });

  testWidgets('person page: the filmography is a horizontal row, like « Connu pour »', (tester) async {
    await _pump(tester, '/personne/287');

    await tester.scrollUntilVisible(find.text('Filmographie'), 200, scrollable: _pageScroll);
    await tester.pumpAndSettle();
    final row = find.ancestor(
      of: find.bySemanticsLabel(RegExp(r'^Film 1\b')),
      matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.right),
    );
    expect(row, findsOneWidget);
    // The start of the filmography (newest first); the rest is behind « Voir tout ».
    final listView = tester.widget<ListView>(find.ancestor(of: row, matching: find.byType(ListView)).first);
    expect(listView.childrenDelegate.estimatedChildCount, lessThanOrEqualTo(2 * 20));
    expect(_pressable('Voir tout : Connu pour'), findsOneWidget);
    expect(_pressable('Voir tout : Filmographie'), findsOneWidget);
  });

  testWidgets('person page: « Connu pour » and « Filmographie » open every title', (tester) async {
    final asked = <(int, PersonCreditsSort)>[];
    final overrides = <Override>[
      personCreditsProvider.overrideWith((ref, key) async {
        asked.add(key);
        return [for (var i = 1; i <= 3; i++) _movie(200 + i, key.$2 == PersonCreditsSort.popular ? 'Célèbre $i' : 'Récent $i')];
      }),
    ];

    await _pump(tester, '/personne/287', overrides: overrides);
    await tester.tap(_pressable('Voir tout : Connu pour'));
    await tester.pumpAndSettle();
    expect(find.text('Connu pour'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Célèbre 3')), findsOneWidget);

    await _pump(tester, '/personne/287', overrides: overrides);
    final seeAll = _pressable('Voir tout : Filmographie');
    await tester.scrollUntilVisible(seeAll, 200, scrollable: _pageScroll);
    await tester.tap(seeAll);
    await tester.pumpAndSettle();
    expect(find.text('Filmographie'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Récent 1')), findsOneWidget);

    expect(asked, [(287, PersonCreditsSort.popular), (287, PersonCreditsSort.date)]);
  });
}
