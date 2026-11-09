import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vixeo/app.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/core/widgets/focusable.dart';
import 'package:vixeo/features/catalog/catalog_repository.dart';
import 'package:vixeo/features/catalog/home_screen.dart';
import 'package:vixeo/features/catalog/models.dart';
import 'package:vixeo/features/library/library.dart';

class EmptyLibrary extends LibraryController {
  @override
  Future<LibraryState> build() async => const LibraryState({});
}

/// Title pages of the hero, without network.
TitleDetails details((MediaType, int) key) => TitleDetails(
  id: key.$2,
  type: key.$1,
  title: 'Titre ${key.$2}',
  overview: 'Résumé complet du titre ${key.$2}',
  year: 2024,
  runtime: 126,
  ageRating: 12,
  genres: const [Genre(18, 'Drame'), Genre(12, 'Aventure')],
);

final home = Home(
  featured: [movie(1, 'Nord Sauvage')],
  sections: [
    Section(
      key: 'movie_trending',
      title: 'Films tendance',
      type: MediaType.movie,
      list: 'trending',
      items: [movie(2, 'Orbite 9'), movie(3, 'Le Phare')],
    ),
  ],
);

/// Title pages asked by the hero.
final asked = <int>[];

Future<void> pumpHome(
  WidgetTester tester, {
  LibraryController Function() library = EmptyLibrary.new,
  Home? withHome,
}) async {
  asked.clear();
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        homeProvider.overrideWith((ref, type) async => withHome ?? home),
        libraryProvider.overrideWith(library),
        titleProvider.overrideWith((ref, key) async {
          asked.add(key.$2);
          return details(key);
        }),
      ],
      child: MaterialApp(
        shortcuts: remoteShortcuts,
        actions: remoteActions,
        theme: buildVixeoTheme(),
        home: const Scaffold(body: HomeScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

MediaItem movie(int id, String title) =>
    MediaItem(id: id, type: MediaType.movie, title: title, overview: 'Résumé de $title');

String? focusedLabel() {
  final context = FocusManager.instance.primaryFocus?.context;
  return context?.findAncestorWidgetOfExactType<VxFocusable>()?.semanticLabel;
}

void main() {
  testWidgets('TV home: the first card of the list has the focus, and the hero follows the focus', (tester) async {
    await pumpHome(tester);

    // Nothing to resume: the first card of the first list has the focus, and is in the hero
    // (not the featured title). No "Plus d’infos" button: the card opens the title page.
    expect(focusedLabel(), startsWith('Orbite 9'));
    expect(find.text('Résumé de Orbite 9'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(find.text('Résumé complet du titre 2'), findsOneWidget);
    expect(find.text('Plus d’infos'), findsNothing);
    expect(find.text('Nord Sauvage'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(focusedLabel(), startsWith('Le Phare'));
    expect(find.text('Résumé complet du titre 3'), findsOneWidget);
  });

  testWidgets('a click on a card opens its title page', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: HomeScreen()),
        ),
        GoRoute(path: '/titre/:type/:id', builder: (_, state) => Text('Fiche ${state.pathParameters['id']}')),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeProvider.overrideWith((ref, type) async => home),
          libraryProvider.overrideWith(EmptyLibrary.new),
          titleProvider.overrideWith((ref, key) async => details(key)),
        ],
        child: MaterialApp.router(theme: buildVixeoTheme(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel(RegExp('^Le Phare')).first);
    await tester.pumpAndSettle();
    expect(find.text('Fiche 3'), findsOneWidget);
  });

  testWidgets('the hero shows the title page details once the selection rests', (tester) async {
    await pumpHome(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    // At once: what the list gives.
    expect(find.text('Résumé de Le Phare'), findsOneWidget);
    expect(find.text('Drame · Aventure'), findsNothing);

    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(find.text('Drame · Aventure'), findsOneWidget);
    expect(find.text('2 h 06'), findsOneWidget);
    expect(find.text('12+'), findsOneWidget);
    expect(find.text('Résumé complet du titre 3'), findsOneWidget);
  });

  testWidgets('home items bring their length, genres and age rating: shown at once, no title page', (tester) async {
    const summary = TitleSummary(runtime: 139, genres: ['Drame', 'Thriller'], ageRating: 16);
    MediaItem full(int id, String title) => MediaItem(
      id: id,
      type: MediaType.movie,
      title: title,
      year: 1999,
      overview: 'Résumé de $title',
      summary: summary,
    );
    await pumpHome(
      tester,
      withHome: Home(
        featured: const [],
        sections: [
          Section(
            key: 'movie_trending',
            title: 'Films tendance',
            type: MediaType.movie,
            list: 'trending',
            items: [full(2, 'Orbite 9'), full(3, 'Le Phare')],
          ),
        ],
      ),
    );

    expect(find.text('2 h 19'), findsOneWidget);
    expect(find.text('Drame · Thriller'), findsOneWidget);
    expect(find.text('16+'), findsOneWidget);
    expect(find.text('1999'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('Résumé de Le Phare'), findsOneWidget);
    expect(find.text('2 h 19'), findsOneWidget, reason: 'at once, not after a pause');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(asked, isEmpty);
  });

  testWidgets('the hero follows the mouse too', (tester) async {
    await pumpHome(tester);
    expect(find.text('Résumé de Orbite 9'), findsOneWidget);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    final poster = find.bySemanticsLabel(RegExp('^Le Phare'));
    await mouse.moveTo(tester.getCenter(poster.first));
    // Not before the pointer rests on the card.
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Résumé de Le Phare'), findsNothing);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(find.text('Résumé de Le Phare'), findsOneWidget);
  });

  testWidgets('a "Continuer à regarder" card puts its title in the hero', (tester) async {
    await pumpHome(tester, library: ResumeLibrary.new);

    // The first resume card has the focus on arrival: its title is in the hero.
    expect(focusedLabel(), startsWith('Les Veilleurs'));
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(find.text('Les Veilleurs'), findsWidgets);
    expect(find.text('Résumé complet du titre 7'), findsOneWidget);
  });
}

class ResumeLibrary extends LibraryController {
  @override
  Future<LibraryState> build() async => LibraryState({
    'tmdb|tv:7': ProfileItem(
      source: 'tmdb',
      itemId: 'tv:7',
      type: 'tv',
      title: 'Les Veilleurs',
      positionMs: 600000,
      durationMs: 3000000,
      progress: 0.2,
      lastEngagedAt: DateTime(2026, 11, 4),
    ),
  });
}
