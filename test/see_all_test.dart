import 'package:material_ui/material_ui.dart';
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

// « Voir tout » of the title and person pages (developer's request): « Vous pourriez aussi
// aimer », « Distribution », « Équipe technique », « Films » and « Séries » open their whole list.

class _EmptyLibrary extends LibraryController {
  @override
  Future<LibraryState> build() async => const LibraryState({});
}

class _SignedOut extends SessionController {
  @override
  SessionState build() => const SessionState(status: SessionStatus.signedOut);
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
  movies: [for (var i = 1; i <= 30; i++) _movie(100 + i, 'Film $i')],
  shows: [MediaItem(id: 2, type: MediaType.tv, title: 'Série 1')],
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
        ),
      ),
      GoRoute(
        path: '/titre/:type/:id/equipe',
        builder: (_, state) => CreditsScreen(
          type: MediaType.parse(state.pathParameters['type']),
          id: int.parse(state.pathParameters['id']!),
          crew: true,
        ),
      ),
      GoRoute(path: '/personne/:id', builder: (_, state) => PersonScreen(id: int.parse(state.pathParameters['id']!))),
      GoRoute(
        path: '/personne/:id/films',
        builder: (_, state) =>
            PersonTitlesScreen(id: int.parse(state.pathParameters['id']!), sort: PersonCreditsType.movie),
      ),
      GoRoute(
        path: '/personne/:id/series',
        builder: (_, state) =>
            PersonTitlesScreen(id: int.parse(state.pathParameters['id']!), sort: PersonCreditsType.tv),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWith(_SignedOut.new),
        libraryProvider.overrideWith(_EmptyLibrary.new),
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

  testWidgets('title page: « Distribution » opens the whole cast, 20 at a time', (tester) async {
    final asked = <int>[];
    await _pump(
      tester,
      '/titre/movie/550',
      overrides: [
        // Two pages of 20: 20 actors, then 6 more.
        titleCreditsProvider.overrideWith((ref, key) async {
          asked.add(key.$3);
          return key.$3 == 1
              ? Paged(items: [for (var i = 1; i <= 20; i++) Person(id: i, name: 'Acteur $i', role: 'Rôle $i')], totalPages: 2)
              : Paged(
                  items: [for (var i = 21; i <= 26; i++) Person(id: i, name: 'Acteur $i', role: 'Rôle $i')],
                  page: 2,
                  totalPages: 2,
                );
        }),
      ],
    );

    final seeAll = _pressable('Voir tout : Distribution');
    await tester.scrollUntilVisible(seeAll, 200, scrollable: _pageScroll);
    await tester.tap(seeAll);
    await tester.pumpAndSettle();

    expect(find.text('Distribution'), findsOneWidget);
    final cards = tester.widgetList<PersonCard>(find.byType(PersonCard)).toList();
    expect('${cards.first.person.name} (${cards.first.role})', 'Acteur 1 (Rôle 1)');
    // 20 people first.
    expect(asked, [1]);

    // The rest of the cast, read as the grid scrolls.
    await tester.scrollUntilVisible(find.text('Acteur 26'), 300, scrollable: _pageScroll);
    expect(find.text('Rôle 26'), findsOneWidget);
    expect(asked, [1, 2]);
  });

  testWidgets('title page: « Équipe technique » opens the whole crew, with their jobs', (tester) async {
    final asked = <int>[];
    await _pump(
      tester,
      '/titre/movie/550',
      overrides: [
        titleCrewProvider.overrideWith((ref, key) async {
          asked.add(key.$3);
          return Paged(
            items: const [
              Person(id: 9, name: 'Ines Dahl', role: 'Réalisation, Scénario'),
              Person(id: 10, name: 'Oskar Brun', role: 'Musique'),
            ],
          );
        }),
      ],
    );

    final seeAll = _pressable('Voir tout : Équipe technique');
    await tester.scrollUntilVisible(seeAll, 200, scrollable: _pageScroll);
    await tester.tap(seeAll);
    await tester.pumpAndSettle();

    expect(find.text('Équipe technique'), findsOneWidget);
    final cards = tester.widgetList<PersonCard>(find.byType(PersonCard)).toList();
    expect([for (final c in cards) '${c.person.name} (${c.role})'], ['Ines Dahl (Réalisation, Scénario)', 'Oskar Brun (Musique)']);
    expect(asked, [1]);
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
    final asked = <(int, PersonCreditsType, int)>[];
    final overrides = <Override>[
      personCreditsProvider.overrideWith((ref, key) async {
        asked.add(key);
        return Paged(
          items: [for (var i = 1; i <= 3; i++) _movie(200 + i, key.$2 == PersonCreditsType.popular ? 'Célèbre $i' : 'Récent $i')],
        );
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

    expect(asked, [(287, PersonCreditsType.popular, 1), (287, PersonCreditsType.date, 1)]);
  });
}
